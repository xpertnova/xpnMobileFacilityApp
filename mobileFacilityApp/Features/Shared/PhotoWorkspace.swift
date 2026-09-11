import Foundation
import Observation
import PhotosUI
import SwiftUI
import UIKit

enum PhotoWorkspaceMotion {
    static let navigation = Animation.snappy(duration: 0.32, extraBounce: 0)
    static let destination = AnyTransition.move(edge: .trailing).combined(with: .opacity)
    static let source = AnyTransition.opacity
}

struct PhotoWorkspaceEntry: Identifiable, Equatable {
    let id: String
    let localAttachmentID: String
    let capturedAt: Date
}

@MainActor
@Observable
final class LocalPhotoCollectionViewModel {
    enum Feedback: Identifiable {
        case saveFailed
        case importFailed
        case cameraUnavailable
        case cameraPermissionDenied

        var id: String { String(describing: self) }
    }

    let scope: LocalPhotoScope
    private let offlineWorkStore: OfflineWorkStore
    private let photoStore: any PhotoAttachmentStore
    private let legacyAttachmentIDs: [String]

    private(set) var attachments: [LocalPhotoAttachment] = []
    private(set) var photoData: [String: Data] = [:]
    private(set) var isLoading = true
    private(set) var isSaving = false
    var feedback: Feedback?

    init(
        scope: LocalPhotoScope,
        offlineWorkStore: OfflineWorkStore,
        photoStore: any PhotoAttachmentStore,
        legacyAttachmentIDs: [String] = []
    ) {
        self.scope = scope
        self.offlineWorkStore = offlineWorkStore
        self.photoStore = photoStore
        self.legacyAttachmentIDs = legacyAttachmentIDs
    }

    var entries: [PhotoWorkspaceEntry] {
        attachments.map {
            PhotoWorkspaceEntry(
                id: $0.id,
                localAttachmentID: $0.localAttachmentID,
                capturedAt: $0.capturedAt
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
}

struct LocalPhotoWorkspace: View {
    let isReadOnly: Bool
    let close: () -> Void
    @State private var model: LocalPhotoCollectionViewModel

    init(
        scope: LocalPhotoScope,
        offlineWorkStore: OfflineWorkStore,
        photoStore: any PhotoAttachmentStore,
        legacyAttachmentIDs: [String] = [],
        isReadOnly: Bool = false,
        close: @escaping () -> Void
    ) {
        self.isReadOnly = isReadOnly
        self.close = close
        _model = State(initialValue: LocalPhotoCollectionViewModel(
            scope: scope,
            offlineWorkStore: offlineWorkStore,
            photoStore: photoStore,
            legacyAttachmentIDs: legacyAttachmentIDs
        ))
    }

    var body: some View {
        PhotoWorkspace(
            title: model.scope.displayTitle,
            subtitle: model.scope.displaySubtitle,
            entries: model.entries,
            photoData: model.photoData,
            isLoading: model.isLoading,
            isSaving: model.isSaving,
            isReadOnly: isReadOnly,
            close: close,
            addPhoto: { data in Task { await model.addPhoto(jpegData: data) } },
            removePhoto: { id in Task { await model.removePhoto(id: id) } },
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
        case .cameraUnavailable: "photos.workspace.error.cameraUnavailable"
        case .cameraPermissionDenied: "photos.workspace.error.cameraPermissionDenied"
        }
    }
}

struct PhotoWorkspace: View {
    let title: String
    let subtitle: String
    let entries: [PhotoWorkspaceEntry]
    let photoData: [String: Data]
    let isLoading: Bool
    let isSaving: Bool
    let isReadOnly: Bool
    let close: () -> Void
    let addPhoto: (Data) -> Void
    let removePhoto: (String) -> Void
    let reportImportFailure: () -> Void
    let reportCameraUnavailable: () -> Void
    let reportCameraPermissionDenied: () -> Void

    @State private var selectedID: String?
    @State private var selectedLibraryPhoto: PhotosPickerItem?
    @State private var isPhotoLibraryPresented = false
    @State private var isCameraPresented = false

    private var selectedEntry: PhotoWorkspaceEntry? {
        entries.first { $0.id == selectedID } ?? entries.first
    }

    var body: some View {
        VStack(spacing: 0) {
            header

            GeometryReader { geometry in
                if geometry.size.width >= 720 {
                    HStack(spacing: 0) {
                        photoList
                            .frame(width: min(310, max(230, geometry.size.width * 0.29)))
                        Divider()
                        preview
                    }
                } else {
                    VStack(spacing: 0) {
                        compactPhotoStrip
                        Divider()
                        preview
                    }
                }
            }
        }
        .background(FacilityTheme.canvas.ignoresSafeArea())
        .photosPicker(
            isPresented: $isPhotoLibraryPresented,
            selection: $selectedLibraryPhoto,
            matching: .images
        )
        .onChange(of: selectedLibraryPhoto) { _, item in
            guard let item else { return }
            Task { await importPhoto(item) }
        }
        .sheet(isPresented: $isCameraPresented) {
            CameraCaptureView(compressionQuality: 0.5) { data in
                isCameraPresented = false
                addPhoto(data)
            } onCancel: {
                isCameraPresented = false
            }
            .ignoresSafeArea()
        }
        .onChange(of: entries) { _, newEntries in
            if let selectedID, newEntries.contains(where: { $0.id == selectedID }) { return }
            self.selectedID = newEntries.first?.id
        }
    }

    private var header: some View {
        HStack(spacing: 16) {
            Button(action: close) {
                Label("photos.workspace.back", systemImage: "chevron.left")
                    .frame(minHeight: 44)
            }
            .buttonStyle(.plain)
            .foregroundStyle(FacilityTheme.blue)

            VStack(alignment: .leading, spacing: 3) {
                Text(title.isEmpty ? String(localized: "photos.workspace.title") : title)
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

            Text(String(format: String(localized: "photos.workspace.count"), entries.count))
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.secondary)

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
                .tint(FacilityTheme.accent)
                .disabled(isSaving)
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
                ScrollView {
                    LazyVStack(spacing: 8) {
                        ForEach(entries) { entry in
                            photoListRow(entry)
                        }
                    }
                    .padding(12)
                }
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
                        ForEach(entries) { entry in photoListRow(entry).frame(width: 210) }
                    }
                    .padding(12)
                }
                .scrollIndicators(.hidden)
                .frame(height: 112)
            }
        }
        .background(FacilityTheme.surface)
    }

    private func photoListRow(_ entry: PhotoWorkspaceEntry) -> some View {
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
                    Text(entry.capturedAt, format: .dateTime.day().month().year())
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(FacilityTheme.ink)
                    Text(entry.capturedAt, format: .dateTime.hour().minute())
                        .font(.caption)
                        .foregroundStyle(.secondary)
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
        .accessibilityLabel(Text(String(format: String(localized: "photos.workspace.photo.accessibility"), entry.capturedAt.formatted())))
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
                        HStack {
                            Spacer()
                            Button(role: .destructive) { removePhoto(entry.id) } label: {
                                Label("photos.workspace.delete", systemImage: "trash")
                                    .frame(minHeight: 44)
                            }
                            .buttonStyle(.bordered)
                            .disabled(isSaving)
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

    private func importPhoto(_ item: PhotosPickerItem) async {
        defer { selectedLibraryPhoto = nil }
        guard let rawData = try? await item.loadTransferable(type: Data.self),
              let jpegData = JPEGPhotoEncoder.encode(rawData, compressionQuality: 0.5) else {
            reportImportFailure()
            return
        }
        addPhoto(jpegData)
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
                    Text(String(format: String(localized: "photos.workspace.count"), count))
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
