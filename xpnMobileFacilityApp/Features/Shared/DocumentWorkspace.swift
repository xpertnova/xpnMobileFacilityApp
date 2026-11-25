import Observation
import QuickLook
import SwiftUI
import UniformTypeIdentifiers

@MainActor
@Observable
final class LocalDocumentCollectionViewModel {
    enum Feedback: String, Identifiable {
        case saveFailed
        case importFailed
        case tooLarge
        case openFailed

        var id: String { rawValue }

        var messageKey: LocalizedStringKey {
            switch self {
            case .saveFailed: "documents.workspace.error.save"
            case .importFailed: "documents.workspace.error.import"
            case .tooLarge: "documents.workspace.error.tooLarge"
            case .openFailed: "documents.workspace.error.open"
            }
        }
    }

    /// Keeps a single attachment from filling the shared iPad.
    static let maximumByteCount = 50 * 1024 * 1024

    let scope: LocalPhotoScope
    private let offlineWorkStore: OfflineWorkStore
    private let documentStore: any DocumentAttachmentStore

    private(set) var documents: [LocalDocumentAttachment] = []
    private(set) var isLoading = true
    private(set) var isSaving = false
    var feedback: Feedback?
    var previewURL: URL?

    init(scope: LocalPhotoScope, offlineWorkStore: OfflineWorkStore, documentStore: any DocumentAttachmentStore) {
        self.scope = scope
        self.offlineWorkStore = offlineWorkStore
        self.documentStore = documentStore
    }

    func load() async {
        isLoading = true
        defer { isLoading = false }
        await offlineWorkStore.load()
        documents = offlineWorkStore.documentCollection(for: scope)?.payload.documentCollection?.documents ?? []
    }

    func importFiles(_ urls: [URL]) async {
        guard !isSaving, !urls.isEmpty else { return }
        isSaving = true
        defer { isSaving = false }

        var imported: [LocalDocumentAttachment] = []
        var failure: Feedback?
        for url in urls {
            // Files from the document picker are security-scoped.
            let isAccessing = url.startAccessingSecurityScopedResource()
            do {
                let file = try await documentStore.importFile(from: url, maximumByteCount: Self.maximumByteCount)
                imported.append(LocalDocumentAttachment(
                    localAttachmentID: file.id,
                    fileName: file.fileName,
                    contentType: file.contentType,
                    byteCount: file.byteCount,
                    addedAt: .now
                ))
            } catch DocumentAttachmentStoreError.tooLarge {
                failure = .tooLarge
            } catch {
                failure = failure ?? .importFailed
            }
            if isAccessing { url.stopAccessingSecurityScopedResource() }
        }

        guard !imported.isEmpty else {
            feedback = failure
            return
        }
        let updated = documents + imported
        do {
            try await offlineWorkStore.saveDocumentCollection(scope: scope, documents: updated)
            documents = updated
            feedback = failure
        } catch {
            for document in imported {
                try? await documentStore.delete(id: document.localAttachmentID)
            }
            feedback = .saveFailed
        }
    }

    func remove(id: String) async {
        guard !isSaving, let document = documents.first(where: { $0.id == id }) else { return }
        isSaving = true
        defer { isSaving = false }

        let updated = documents.filter { $0.id != id }
        do {
            try await offlineWorkStore.saveDocumentCollection(scope: scope, documents: updated)
            documents = updated
            try? await documentStore.delete(id: document.localAttachmentID)
        } catch {
            feedback = .saveFailed
        }
    }

    func open(_ document: LocalDocumentAttachment) async {
        do {
            previewURL = try await documentStore.fileURL(
                id: document.localAttachmentID,
                fileName: document.fileName
            )
        } catch {
            feedback = .openFailed
        }
    }
}

/// Files attached to a technical place or equipment. They are kept only on
/// this iPad: neither reference app links documents to a technical place in
/// SAP, so there is no verified upload to send them with.
struct LocalDocumentWorkspace: View {
    let close: () -> Void
    @State private var model: LocalDocumentCollectionViewModel
    @State private var isImporterPresented = false
    @State private var pendingDeletion: LocalDocumentAttachment?
    @Environment(\.locale) private var locale

    init(
        scope: LocalPhotoScope,
        offlineWorkStore: OfflineWorkStore,
        documentStore: any DocumentAttachmentStore,
        close: @escaping () -> Void
    ) {
        self.close = close
        _model = State(initialValue: LocalDocumentCollectionViewModel(
            scope: scope,
            offlineWorkStore: offlineWorkStore,
            documentStore: documentStore
        ))
    }

    var body: some View {
        VStack(spacing: 0) {
            header
            localOnlyNotice
            content
        }
        .background(FacilityTheme.canvas.ignoresSafeArea())
        .task(id: model.scope) { await model.load() }
        // Any file type: PDFs are the common case, but plans, photos and
        // spreadsheets are attached too.
        .fileImporter(isPresented: $isImporterPresented, allowedContentTypes: [.data], allowsMultipleSelection: true) { result in
            switch result {
            case let .success(urls):
                Task { await model.importFiles(urls) }
            case .failure:
                model.feedback = .importFailed
            }
        }
        .quickLookPreview($model.previewURL)
        .confirmationDialog(
            "documents.workspace.delete.confirm.title",
            isPresented: Binding(
                get: { pendingDeletion != nil },
                set: { if !$0 { pendingDeletion = nil } }
            ),
            titleVisibility: .visible,
            presenting: pendingDeletion
        ) { document in
            Button("documents.workspace.delete", role: .destructive) {
                Task { await model.remove(id: document.id) }
            }
        } message: { document in
            Text(verbatim: "\(document.fileName)\n") + Text("documents.workspace.delete.confirm.message")
        }
        .alert(item: $model.feedback) { feedback in
            Alert(
                title: Text("documents.workspace.error.title"),
                message: Text(feedback.messageKey),
                dismissButton: .default(Text("common.ok"))
            )
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
                Text("documents.workspace.title")
                    .font(.title2.bold())
                    .foregroundStyle(FacilityTheme.ink)
                if !model.scope.localizedSubtitle.isEmpty {
                    Text(model.scope.localizedSubtitle)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }

            Spacer()

            if model.isSaving {
                ProgressView()
                    .accessibilityLabel(Text("documents.workspace.importing"))
            }

            Text(String(format: String(localized: "documents.workspace.count", bundle: .appLanguage), model.documents.count))
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.secondary)

            Button { isImporterPresented = true } label: {
                Label("documents.workspace.add", systemImage: "plus")
                    .frame(minHeight: 44)
            }
            .buttonStyle(.borderedProminent)
            .tint(FacilityTheme.accent)
            .disabled(model.isLoading || model.isSaving)
        }
        .padding(.horizontal, 24)
        .padding(.vertical, 14)
        .background(FacilityTheme.surface)
        .overlay(alignment: .bottom) { Divider() }
    }

    private var localOnlyNotice: some View {
        Label("documents.workspace.localOnly", systemImage: "ipad.landscape")
            .font(.subheadline)
            .foregroundStyle(.secondary)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 24)
            .padding(.vertical, 10)
            .background(FacilityTheme.surface)
            .overlay(alignment: .bottom) { Divider() }
    }

    @ViewBuilder
    private var content: some View {
        if model.isLoading {
            ProgressView("documents.workspace.loading")
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if model.documents.isEmpty {
            ContentUnavailableView {
                Label("documents.workspace.empty.title", systemImage: "doc")
            } description: {
                Text("documents.workspace.empty.message")
            } actions: {
                Button("documents.workspace.add") { isImporterPresented = true }
                    .buttonStyle(.borderedProminent)
                    .tint(FacilityTheme.accent)
                    .disabled(model.isSaving)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            List {
                ForEach(model.documents.reversed()) { document in
                    row(document)
                        .listRowInsets(EdgeInsets(top: 4, leading: 24, bottom: 4, trailing: 24))
                        .listRowSeparator(.hidden)
                        .listRowBackground(Color.clear)
                        .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                            Button(role: .destructive) { pendingDeletion = document } label: {
                                Label("documents.workspace.delete", systemImage: "trash")
                            }
                            .disabled(model.isSaving)
                        }
                }
            }
            .listStyle(.plain)
            .scrollContentBackground(.hidden)
        }
    }

    private func row(_ document: LocalDocumentAttachment) -> some View {
        HStack(spacing: 12) {
            Button {
                Task { await model.open(document) }
            } label: {
                HStack(spacing: 12) {
                    Image(systemName: Self.symbolName(for: document))
                        .font(.body.weight(.semibold))
                        .foregroundStyle(FacilityTheme.blue)
                        .frame(width: 44, height: 44)
                        .background(FacilityTheme.blue.opacity(0.10), in: RoundedRectangle(cornerRadius: 12))
                    VStack(alignment: .leading, spacing: 3) {
                        Text(document.fileName)
                            .font(.body.weight(.semibold))
                            .foregroundStyle(FacilityTheme.ink)
                            .lineLimit(2)
                            .truncationMode(.middle)
                        (Text(verbatim: "\(Self.typeLabel(for: document)) · \(Int64(document.byteCount).formatted(.byteCount(style: .file).locale(locale))) · ")
                            + Text(document.addedAt, format: .dateTime.day().month().year().hour().minute().locale(locale)))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    Spacer(minLength: 0)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityHint(Text("documents.workspace.open.document.hint"))

            Button(role: .destructive) { pendingDeletion = document } label: {
                Image(systemName: "trash")
                    .frame(width: 44, height: 44)
            }
            .buttonStyle(.plain)
            .foregroundStyle(FacilityTheme.red)
            .disabled(model.isSaving)
            .accessibilityLabel(Text("documents.workspace.delete"))
        }
        .padding(12)
        .background(FacilityTheme.surface, in: RoundedRectangle(cornerRadius: 14))
    }

    private static func symbolName(for document: LocalDocumentAttachment) -> String {
        guard let type = UTType(document.contentType) else { return "doc" }
        if type.conforms(to: .pdf) { return "doc.richtext" }
        if type.conforms(to: .image) { return "photo" }
        if type.conforms(to: .spreadsheet) { return "tablecells" }
        if type.conforms(to: .presentation) { return "rectangle.on.rectangle" }
        if type.conforms(to: .text) { return "doc.text" }
        return "doc"
    }

    private static func typeLabel(for document: LocalDocumentAttachment) -> String {
        let fileExtension = (document.fileName as NSString).pathExtension
        if !fileExtension.isEmpty { return fileExtension.uppercased() }
        return UTType(document.contentType)?.preferredFilenameExtension?.uppercased() ?? "—"
    }
}

struct DocumentWorkspaceButton: View {
    let count: Int
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 12) {
                Image(systemName: count == 0 ? "doc.badge.plus" : "doc.on.doc.fill")
                    .font(.body.weight(.semibold))
                    .foregroundStyle(FacilityTheme.blue)
                    .frame(width: 44, height: 44)
                    .background(FacilityTheme.blue.opacity(0.10), in: RoundedRectangle(cornerRadius: 12))
                VStack(alignment: .leading, spacing: 3) {
                    Text("documents.workspace.open")
                        .font(.body.weight(.semibold))
                        .foregroundStyle(FacilityTheme.ink)
                    Text(String(format: String(localized: "documents.workspace.count", bundle: .appLanguage), count))
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
        .accessibilityHint(Text("documents.workspace.open.hint"))
    }
}
