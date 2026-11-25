import Foundation
import Observation
import PhotosUI
import SwiftUI
import UIKit

enum PhotoLibrarySelectionLimit {
    static let maximumBatchCount = 20

    static func remaining(maxAttachments: Int?, currentCount: Int) -> Int {
        min(maximumBatchCount, max(0, maxAttachments.map { $0 - currentCount } ?? maximumBatchCount))
    }
}

struct PhotoWorkspaceEntry: Identifiable, Equatable {
    let id: String
    let localAttachmentID: String
    let capturedAt: Date
    let name: String
    let description: String
}

@MainActor
@Observable
final class LocalPhotoCollectionViewModel {
    enum Feedback: Identifiable {
        case saveFailed
        case importFailed
        case photoLimitReached
        case cameraUnavailable
        case cameraPermissionDenied

        var id: String { String(describing: self) }
    }

    let scope: LocalPhotoScope
    private let offlineWorkStore: OfflineWorkStore
    private let photoStore: any PhotoAttachmentStore
    private let legacyAttachmentIDs: [String]
    private let maxAttachments: Int

    private(set) var attachments: [LocalPhotoAttachment] = []
    private(set) var photoData: [String: Data] = [:]
    private(set) var isLoading = true
    private(set) var isSaving = false
    var feedback: Feedback?

    init(
        scope: LocalPhotoScope,
        offlineWorkStore: OfflineWorkStore,
        photoStore: any PhotoAttachmentStore,
        legacyAttachmentIDs: [String] = [],
        maxAttachments: Int = PhotoLibrarySelectionLimit.maximumBatchCount
    ) {
        self.scope = scope
        self.offlineWorkStore = offlineWorkStore
        self.photoStore = photoStore
        self.legacyAttachmentIDs = legacyAttachmentIDs
        self.maxAttachments = maxAttachments
    }

    var entries: [PhotoWorkspaceEntry] {
        attachments.map {
            PhotoWorkspaceEntry(
                id: $0.id,
                localAttachmentID: $0.localAttachmentID,
                capturedAt: $0.capturedAt,
                name: $0.name,
                description: $0.description
            )
        }
    }

    func load() async {
        isLoading = true
        defer { isLoading = false }
        await offlineWorkStore.load()

        if let saved = offlineWorkStore.photoCollection(for: scope)?.payload.photoCollection {
            attachments = saved.attachments
        } else if !legacyAttachmentIDs.isEmpty {
            let migrated = legacyAttachmentIDs.map {
                LocalPhotoAttachment(localAttachmentID: $0, capturedAt: .now)
            }
            do {
                _ = try await offlineWorkStore.savePhotoCollection(scope: scope, attachments: migrated)
                attachments = migrated
            } catch {
                feedback = .saveFailed
            }
        }

        photoData.removeAll()
        for attachment in attachments {
            if let data = try? await photoStore.loadJPEG(id: attachment.localAttachmentID) {
                photoData[attachment.localAttachmentID] = data
            }
        }
    }

    func addPhoto(jpegData: Data) async {
        guard !isSaving else { return }
        guard attachments.count < maxAttachments else {
            feedback = .photoLimitReached
            return
        }
        isSaving = true
        defer { isSaving = false }

        var savedFileID: String?
        do {
            let fileID = try await photoStore.saveJPEG(jpegData)
            savedFileID = fileID
            let attachment = LocalPhotoAttachment(localAttachmentID: fileID, capturedAt: .now)
            let updated = attachments + [attachment]
            _ = try await offlineWorkStore.savePhotoCollection(
                scope: scope,
                attachments: updated,
                retainEmpty: !legacyAttachmentIDs.isEmpty
            )
            attachments = updated
            photoData[fileID] = jpegData
        } catch {
            if let savedFileID { try? await photoStore.delete(id: savedFileID) }
            feedback = .saveFailed
        }
    }

    func removePhoto(id: String) async {
        guard !isSaving, let attachment = attachments.first(where: { $0.id == id }) else { return }
        isSaving = true
        defer { isSaving = false }

        let updated = attachments.filter { $0.id != id }
        do {
            _ = try await offlineWorkStore.savePhotoCollection(scope: scope, attachments: updated)
            attachments = updated
            photoData[attachment.localAttachmentID] = nil
            try? await photoStore.delete(id: attachment.localAttachmentID)
        } catch {
            feedback = .saveFailed
        }
    }

    func updatePhoto(id: String, name: String, description: String) async {
        guard !isSaving, let attachment = attachments.first(where: { $0.id == id }) else { return }
        isSaving = true
        defer { isSaving = false }

        let updated = attachments.map {
            $0.id == id ? attachment.updatingMetadata(name: name, description: description) : $0
        }
        do {
            _ = try await offlineWorkStore.savePhotoCollection(
                scope: scope,
                attachments: updated,
                retainEmpty: !legacyAttachmentIDs.isEmpty
            )
            attachments = updated
        } catch {
            feedback = .saveFailed
        }
    }
}

struct LocalPhotoWorkspace: View {
    let isReadOnly: Bool
    let maxAttachments: Int
    let close: () -> Void
    @State private var model: LocalPhotoCollectionViewModel

    init(
        scope: LocalPhotoScope,
        offlineWorkStore: OfflineWorkStore,
        photoStore: any PhotoAttachmentStore,
        legacyAttachmentIDs: [String] = [],
        isReadOnly: Bool = false,
        maxAttachments: Int = PhotoLibrarySelectionLimit.maximumBatchCount,
        close: @escaping () -> Void
    ) {
        self.isReadOnly = isReadOnly
        self.maxAttachments = maxAttachments
        self.close = close
        _model = State(initialValue: LocalPhotoCollectionViewModel(
            scope: scope,
            offlineWorkStore: offlineWorkStore,
            photoStore: photoStore,
            legacyAttachmentIDs: legacyAttachmentIDs,
            maxAttachments: maxAttachments
        ))
    }

    var body: some View {
        PhotoWorkspace(
            title: model.scope.localizedTitle,
            subtitle: model.scope.localizedSubtitle,
            entries: model.entries,
            photoData: model.photoData,
            isLoading: model.isLoading,
            isSaving: model.isSaving,
            isReadOnly: isReadOnly,
            maxAttachments: maxAttachments,
            close: close,
            addPhoto: { data in await model.addPhoto(jpegData: data) },
            removePhoto: { id in Task { await model.removePhoto(id: id) } },
            updatePhoto: { id, name, description in
                await model.updatePhoto(id: id, name: name, description: description)
            },
            reportImportFailure: { model.feedback = .importFailed },
            reportCameraUnavailable: { model.feedback = .cameraUnavailable },
            reportCameraPermissionDenied: { model.feedback = .cameraPermissionDenied }
        )
        .task(id: model.scope) { await model.load() }
        .alert(item: $model.feedback) { feedback in
            Alert(
                title: Text("photos.workspace.error.title"),
                message: Text(feedback.messageKey),
                dismissButton: .default(Text("common.ok"))
            )
        }
    }
}

private extension LocalPhotoCollectionViewModel.Feedback {
    var messageKey: LocalizedStringKey {
        switch self {
        case .saveFailed: "photos.workspace.error.save"
        case .importFailed: "photos.workspace.error.import"
        case .photoLimitReached: "photos.workspace.error.limit"
        case .cameraUnavailable: "photos.workspace.error.cameraUnavailable"
        case .cameraPermissionDenied: "photos.workspace.error.cameraPermissionDenied"
        }
    }
}

struct PhotoWorkspace: View {
    private enum MetadataField: Hashable {
        case name
        case description
    }

    let title: String
    let subtitle: String
    let entries: [PhotoWorkspaceEntry]
    let photoData: [String: Data]
    let isLoading: Bool
    let isSaving: Bool
    let isReadOnly: Bool
    let maxAttachments: Int?
    let close: () -> Void
    let addPhoto: (Data) async -> Void
    let removePhoto: (String) -> Void
    let updatePhoto: (String, String, String) async -> Void
    let reportImportFailure: () -> Void
    let reportCameraUnavailable: () -> Void
    let reportCameraPermissionDenied: () -> Void

    @State private var selectedID: String?
    @State private var selectedLibraryPhotos: [PhotosPickerItem] = []
    @State private var isPhotoLibraryPresented = false
    @State private var isImportingPhotos = false
    @State private var isCameraPresented = false
    @State private var draftName = ""
    @State private var draftDescription = ""
    @State private var metadataDraftEntryID: String?
    @State private var metadataSaveTask: Task<Void, Never>?
    @State private var isMetadataExpanded = true
    @FocusState private var focusedMetadataField: MetadataField?

    private var selectedEntry: PhotoWorkspaceEntry? {
        entries.first { $0.id == selectedID } ?? entries.first
    }

    var body: some View {
        VStack(spacing: 0) {
            header

            GeometryReader { geometry in
                let isWide = geometry.size.width >= 720
                // Switching the layout, not the view tree, keeps the preview's
                // name and description fields in place when the width crosses
                // the threshold.
                let layout = isWide
                    ? AnyLayout(HStackLayout(spacing: 0))
                    : AnyLayout(VStackLayout(spacing: 0))
                layout {
                    Group {
                        if isWide {
                            photoList
                                .frame(width: min(310, max(230, geometry.size.width * 0.29)))
                        } else {
                            compactPhotoStrip
                        }
                    }
                    Divider()
                    preview
                }
            }
        }
        .background(FacilityTheme.canvas.ignoresSafeArea())
        .photosPicker(
            isPresented: $isPhotoLibraryPresented,
            selection: $selectedLibraryPhotos,
            maxSelectionCount: max(1, remainingPhotoCapacity),
            matching: .images
        )
        .onChange(of: selectedLibraryPhotos) { _, items in
            guard !isPhotoLibraryPresented, !items.isEmpty else { return }
            Task { await importPhotos(items) }
        }
        .onChange(of: isPhotoLibraryPresented) { _, isPresented in
            guard !isPresented, !selectedLibraryPhotos.isEmpty else { return }
            let items = selectedLibraryPhotos
            Task { await importPhotos(items) }
        }
        .sheet(isPresented: $isCameraPresented) {
            CameraCaptureView(compressionQuality: 0.5) { data in
                isCameraPresented = false
                Task { await addPhoto(data) }
            } onCancel: {
                isCameraPresented = false
            }
            .ignoresSafeArea()
        }
        .onChange(of: entries) { _, newEntries in
            synchronizeSelectedEntry(in: newEntries)
        }
        .onChange(of: selectedID) { _, _ in
            saveMetadataImmediately()
            synchronizeSelectedEntry(in: entries)
        }
        .onChange(of: draftName) { _, _ in scheduleMetadataSave() }
        .onChange(of: draftDescription) { _, _ in scheduleMetadataSave() }
        .onAppear { synchronizeSelectedEntry(in: entries) }
        .onDisappear { saveMetadataImmediately() }
        .toolbar {
            ToolbarItemGroup(placement: .keyboard) {
                Spacer()
                Button("photos.workspace.done") {
                    saveMetadataImmediately()
                    focusedMetadataField = nil
                }
            }
        }
    }

    private var isAtAttachmentLimit: Bool {
        maxAttachments.map { entries.count >= $0 } == true
    }

    private var remainingPhotoCapacity: Int {
        PhotoLibrarySelectionLimit.remaining(maxAttachments: maxAttachments, currentCount: entries.count)
    }

    private var header: some View {
        HStack(spacing: 16) {
            Button(action: close) {
                Label("photos.workspace.back", systemImage: "chevron.left")
                    .frame(minHeight: 44)
            }
            .buttonStyle(.plain)
            .foregroundStyle(FacilityTheme.blue)
            .disabled(isImportingPhotos)

            VStack(alignment: .leading, spacing: 3) {
                Text(title.isEmpty ? String(localized: "photos.workspace.title", bundle: .appLanguage) : title)
                    .font(.title2.bold())
                    .foregroundStyle(FacilityTheme.ink)
                if !subtitle.isEmpty {
                    Text(subtitle)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }

            Spacer()

            if isImportingPhotos {
                ProgressView()
                    .accessibilityLabel(Text("photos.workspace.importing"))
            }

            Text(String(format: String(localized: "photos.workspace.count", bundle: .appLanguage), entries.count))
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(isAtAttachmentLimit ? FacilityTheme.red : Color.secondary)

            if !isReadOnly {
                Menu {
                    Button { isPhotoLibraryPresented = true } label: {
                        Label("photos.workspace.library", systemImage: "photo.on.rectangle")
                    }
                    Button { openCamera() } label: {
                        Label("photos.workspace.camera", systemImage: "camera")
                    }
                } label: {
                    Label("photos.workspace.add", systemImage: "plus")
                        .frame(minHeight: 44)
                }
                .buttonStyle(.borderedProminent)
                .tint(isAtAttachmentLimit ? FacilityTheme.red : FacilityTheme.accent)
                .disabled(isSaving || isImportingPhotos || isAtAttachmentLimit)
            }
        }
        .padding(.horizontal, 24)
        .padding(.vertical, 14)
        .background(FacilityTheme.surface)
        .overlay(alignment: .bottom) { Divider() }
    }

    private var photoList: some View {
        Group {
            if isLoading {
                ProgressView("photos.workspace.loading")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if entries.isEmpty {
                emptyState
            } else {
                List {
                    ForEach(entries) { entry in
                        photoListRow(entry, allowsSwipeActions: true)
                            .listRowInsets(EdgeInsets(top: 4, leading: 12, bottom: 4, trailing: 12))
                            .listRowSeparator(.hidden)
                            .listRowBackground(Color.clear)
                    }
                }
                .listStyle(.plain)
                .scrollContentBackground(.hidden)
            }
        }
        .background(FacilityTheme.surface)
    }

    private var compactPhotoStrip: some View {
        Group {
            if entries.isEmpty {
                emptyState.frame(height: 112)
            } else {
                ScrollView(.horizontal) {
                    HStack(spacing: 10) {
                        ForEach(entries) { entry in
                            photoListRow(entry, allowsSwipeActions: false).frame(width: 210)
                        }
                    }
                    .padding(12)
                }
                .scrollIndicators(.hidden)
                .frame(height: 112)
            }
        }
        .background(FacilityTheme.surface)
    }

    @ViewBuilder
    private func photoListRow(_ entry: PhotoWorkspaceEntry, allowsSwipeActions: Bool) -> some View {
        if allowsSwipeActions && !isReadOnly {
            photoListRowContent(entry)
                .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                    Button(role: .destructive) { removePhoto(entry.id) } label: {
                        Label("photos.workspace.delete", systemImage: "trash")
                    }
                    .disabled(isSaving || isImportingPhotos)
                }
        } else {
            photoListRowContent(entry)
        }
    }

    private func photoListRowContent(_ entry: PhotoWorkspaceEntry) -> some View {
        Button { selectedID = entry.id } label: {
            HStack(spacing: 12) {
                Group {
                    if let data = photoData[entry.localAttachmentID] {
                        JPEGThumbnailView(data: data)
                    } else {
                        Image(systemName: "photo.badge.exclamationmark")
                            .foregroundStyle(.secondary)
                    }
                }
                .frame(width: 72, height: 58)
                .background(FacilityTheme.canvas)
                .clipShape(RoundedRectangle(cornerRadius: 9, style: .continuous))

                VStack(alignment: .leading, spacing: 4) {
                    Text(entry.name.isEmpty ? String(localized: "photos.workspace.untitled", bundle: .appLanguage) : entry.name)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(FacilityTheme.ink)
                        .lineLimit(1)
                    Text(entry.description.isEmpty ? String(localized: "photos.workspace.noDescription", bundle: .appLanguage) : entry.description)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }
                Spacer(minLength: 0)
            }
            .padding(8)
            .background(
                selectedEntry?.id == entry.id ? FacilityTheme.blue.opacity(0.10) : Color.clear,
                in: RoundedRectangle(cornerRadius: 12, style: .continuous)
            )
            .overlay {
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .stroke(selectedEntry?.id == entry.id ? FacilityTheme.blue.opacity(0.5) : Color.clear)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(Text(entry.name.isEmpty ? String(localized: "photos.workspace.untitled", bundle: .appLanguage) : entry.name))
    }

    private var preview: some View {
        ZStack {
            if isLoading {
                ProgressView()
            } else if let entry = selectedEntry {
                VStack(spacing: 18) {
                    Group {
                        if let data = photoData[entry.localAttachmentID] {
                            PhotoPreviewImage(data: data)
                        } else {
                            ContentUnavailableView(
                                "photos.workspace.missing.title",
                                systemImage: "photo.badge.exclamationmark",
                                description: Text("photos.workspace.missing.message")
                            )
                        }
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .background(Color.black.opacity(0.04), in: RoundedRectangle(cornerRadius: 18))

                    if !isReadOnly {
                        photoMetadataEditor(for: entry)
                    }

                    if !isReadOnly {
                        HStack {
                            Spacer()
                            Button(role: .destructive) { removePhoto(entry.id) } label: {
                                Label("photos.workspace.delete", systemImage: "trash")
                                    .frame(minHeight: 44)
                            }
                            .buttonStyle(.bordered)
                            .disabled(isSaving || isImportingPhotos)
                        }
                    }
                }
                .padding(24)
            } else {
                ContentUnavailableView(
                    "photos.workspace.empty.title",
                    systemImage: "photo.on.rectangle.angled",
                    description: Text("photos.workspace.empty.message")
                )
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func photoMetadataEditor(for entry: PhotoWorkspaceEntry) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            Button {
                saveMetadataImmediately()
                focusedMetadataField = nil
                withFacilityAnimation {
                    isMetadataExpanded.toggle()
                }
            } label: {
                HStack(spacing: 10) {
                    Label("photos.workspace.details", systemImage: "pencil.and.list.clipboard")
                        .font(.headline.weight(.semibold))
                    Spacer()
                    Image(systemName: isMetadataExpanded ? "chevron.up" : "chevron.down")
                        .font(.subheadline.weight(.bold))
                }
                .foregroundStyle(FacilityTheme.ink)
                .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
            }
            .buttonStyle(.plain)
            .accessibilityHint(Text(
                isMetadataExpanded
                    ? "photos.workspace.details.collapse"
                    : "photos.workspace.details.expand"
            ))

            if isMetadataExpanded {
                VStack(alignment: .leading, spacing: 14) {
                    photoMetadataField(
                        "photos.workspace.name",
                        isFocused: focusedMetadataField == .name
                    ) {
                        TextField("photos.workspace.name", text: $draftName)
                            .focused($focusedMetadataField, equals: .name)
                            .submitLabel(.next)
                            .onSubmit { focusedMetadataField = .description }
                            .accessibilityLabel(Text("photos.workspace.name"))
                    }

                    photoMetadataField(
                        "photos.workspace.description",
                        isFocused: focusedMetadataField == .description
                    ) {
                        TextField("photos.workspace.description", text: $draftDescription)
                            .focused($focusedMetadataField, equals: .description)
                            .submitLabel(.done)
                            .onSubmit {
                                saveMetadataImmediately()
                                focusedMetadataField = nil
                            }
                            .accessibilityLabel(Text("photos.workspace.description"))
                    }
                }
                .transition(FacilityMotion.reveal)
            }
        }
        .facilityCard(padding: 18)
    }

    private func photoMetadataField<Content: View>(
        _ title: LocalizedStringKey,
        isFocused: Bool,
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: 7) {
            Text(title)
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
            content()
                .font(.body)
                .padding(.horizontal, 14)
                .frame(maxWidth: .infinity, minHeight: 48)
                .background(FacilityTheme.canvas, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                .overlay {
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .stroke(isFocused ? FacilityTheme.blue : Color.black.opacity(0.11), lineWidth: isFocused ? 2 : 1)
                }
        }
    }

    private var emptyState: some View {
        VStack(spacing: 9) {
            Image(systemName: "photo.on.rectangle.angled")
                .font(.title2)
                .foregroundStyle(.secondary)
            Text("photos.workspace.empty.short")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .padding(20)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func openCamera() {
        guard CameraCaptureAvailability.isAvailable else {
            reportCameraUnavailable()
            return
        }
        Task {
            guard await CameraCaptureAvailability.requestAccess() else {
                reportCameraPermissionDenied()
                return
            }
            isCameraPresented = true
        }
    }

    private func importPhotos(_ items: [PhotosPickerItem]) async {
        guard !isImportingPhotos else { return }
        isImportingPhotos = true
        defer {
            selectedLibraryPhotos = []
            isImportingPhotos = false
        }

        let allowedCount = remainingPhotoCapacity
        var hadImportFailure = false
        for item in items.prefix(allowedCount) {
            guard let rawData = try? await item.loadTransferable(type: Data.self),
                  let jpegData = JPEGPhotoEncoder.encode(rawData, compressionQuality: 0.5) else {
                hadImportFailure = true
                continue
            }
            await addPhoto(jpegData)
        }
        if hadImportFailure { reportImportFailure() }
    }

    private func synchronizeSelectedEntry(in entries: [PhotoWorkspaceEntry]) {
        let entry = entries.first { $0.id == selectedID } ?? entries.first
        guard let entry else {
            selectedID = nil
            metadataDraftEntryID = nil
            draftName = ""
            draftDescription = ""
            return
        }
        selectedID = entry.id
        metadataDraftEntryID = entry.id
        draftName = entry.name
        draftDescription = entry.description
    }

    private func isMetadataDirty(for entry: PhotoWorkspaceEntry) -> Bool {
        draftName.trimmingCharacters(in: .whitespacesAndNewlines) != entry.name
            || draftDescription.trimmingCharacters(in: .whitespacesAndNewlines) != entry.description
    }

    private func scheduleMetadataSave() {
        metadataSaveTask?.cancel()
        guard let entry = metadataDraftEntry, isMetadataDirty(for: entry) else { return }

        let photoID = entry.id
        let name = draftName.trimmingCharacters(in: .whitespacesAndNewlines)
        let description = draftDescription.trimmingCharacters(in: .whitespacesAndNewlines)
        metadataSaveTask = Task {
            try? await Task<Never, Never>.sleep(nanoseconds: 450_000_000)
            guard !Task.isCancelled else { return }
            await updatePhoto(photoID, name, description)
        }
    }

    private func saveMetadataImmediately() {
        metadataSaveTask?.cancel()
        metadataSaveTask = nil
        guard let entry = metadataDraftEntry, isMetadataDirty(for: entry) else { return }

        let photoID = entry.id
        let name = draftName.trimmingCharacters(in: .whitespacesAndNewlines)
        let description = draftDescription.trimmingCharacters(in: .whitespacesAndNewlines)
        Task { await updatePhoto(photoID, name, description) }
    }

    private var metadataDraftEntry: PhotoWorkspaceEntry? {
        entries.first { $0.id == metadataDraftEntryID }
    }
}

private struct PhotoPreviewImage: View {
    let data: Data

    var body: some View {
        if let image = UIImage(data: data) {
            Image(uiImage: image)
                .resizable()
                .scaledToFit()
                .accessibilityLabel(Text("photos.workspace.selectedPhoto"))
        } else {
            Image(systemName: "photo.badge.exclamationmark")
                .foregroundStyle(.secondary)
        }
    }
}

struct PhotoWorkspaceButton: View {
    let count: Int
    var isDisabled = false
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 12) {
                Image(systemName: count == 0 ? "camera" : "photo.stack.fill")
                    .font(.body.weight(.semibold))
                    .foregroundStyle(FacilityTheme.blue)
                    .frame(width: 44, height: 44)
                    .background(FacilityTheme.blue.opacity(0.10), in: RoundedRectangle(cornerRadius: 12))
                VStack(alignment: .leading, spacing: 3) {
                    Text("photos.workspace.open")
                        .font(.body.weight(.semibold))
                        .foregroundStyle(FacilityTheme.ink)
                    Text(String(format: String(localized: "photos.workspace.count", bundle: .appLanguage), count))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Image(systemName: "chevron.right")
                    .foregroundStyle(.secondary)
            }
            .padding(12)
            .background(FacilityTheme.canvas, in: RoundedRectangle(cornerRadius: 14))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(isDisabled)
        .accessibilityHint(Text("photos.workspace.open.hint"))
    }
}
