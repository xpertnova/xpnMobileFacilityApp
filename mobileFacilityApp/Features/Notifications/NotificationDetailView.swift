import SwiftUI

struct NotificationDetailView: View {
    let detail: SAPNotificationDetail
    let backDestination: AppDestination
    let dismiss: () -> Void
    @Environment(\.accessibilityReduceMotion) private var accessibilityReduceMotion
    @State private var model: NotificationReviewViewModel
    @State private var editingCommentID: String?
    @State private var isCloseConfirmationPresented = false
    @State private var photoWorkspaceItemID: String?

    init(
        detail: SAPNotificationDetail,
        offlineWorkStore: OfflineWorkStore,
        photoAttachmentStore: any PhotoAttachmentStore,
        backDestination: AppDestination,
        dismiss: @escaping () -> Void
    ) {
        self.detail = detail
        self.backDestination = backDestination
        self.dismiss = dismiss
        _model = State(initialValue: NotificationReviewViewModel(
            detail: detail,
            offlineWorkStore: offlineWorkStore,
            photoStore: photoAttachmentStore
        ))
    }

    var body: some View {
        ZStack {
            if let item = photoWorkspaceItem {
                photoWorkspace(for: item)
                    .transition(PhotoWorkspaceMotion.destination)
                    .zIndex(1)
            } else {
                VStack(spacing: 0) {
                    header

                    ScrollView {
                        VStack(spacing: 18) {
                            metadataCard
                            inspectionCard
                        }
                        .padding(28)
                        .frame(maxWidth: 1280, alignment: .leading)
                    }
                }
                .background(FacilityTheme.canvas.ignoresSafeArea())
                .safeAreaInset(edge: .bottom) { actionBar }
                .transition(PhotoWorkspaceMotion.source)
            }
        }
        .animation(
            accessibilityReduceMotion ? nil : PhotoWorkspaceMotion.navigation,
            value: photoWorkspaceItemID
        )
        .overlay {
            if let editingCommentID {
                CommentEditorOverlay(
                    comment: commentBinding(for: editingCommentID),
                    dismiss: { self.editingCommentID = nil }
                )
            }
        }
        .task(id: detail.summary.id) { await model.load() }
        .alert(item: $model.feedback) { feedback in
            Alert(
                title: Text("notifications.detail.action.title"),
                message: Text(feedback.messageKey),
                dismissButton: .default(Text("notifications.detail.commentEditor.done")) {
                    if case .closedLocally = feedback {
                        dismiss()
                    }
                }
            )
        }
        .alert(
            "notifications.detail.closeConfirmation.title",
            isPresented: $isCloseConfirmationPresented
        ) {
            Button("notifications.detail.closeConfirmation.confirm", role: .destructive) {
                Task { await model.save(closed: true) }
            }
            Button("common.cancel", role: .cancel) { }
        } message: {
            Text("notifications.detail.closeConfirmation.message")
        }
    }

    private var photoWorkspaceItem: SAPNotificationDetail.InspectionItem? {
        detail.inspectionItems.first { $0.id == photoWorkspaceItemID }
    }

    private func photoWorkspace(for item: SAPNotificationDetail.InspectionItem) -> some View {
        let attachments = model.attachments(for: item.id)
        return PhotoWorkspace(
            title: String(localized: "photos.workspace.title"),
            subtitle: item.title,
            entries: attachments.map {
                PhotoWorkspaceEntry(
                    id: $0.id,
                    localAttachmentID: $0.localAttachmentID,
                    capturedAt: $0.capturedAt
                )
            },
            photoData: model.photoData,
            isLoading: model.isLoading,
            isSaving: model.isSaving,
            isReadOnly: isReadOnly,
            maxAttachments: nil,
            close: { photoWorkspaceItemID = nil },
            addPhoto: { data in Task { await model.addPhoto(jpegData: data, to: item) } },
            removePhoto: { id in
                guard let attachment = attachments.first(where: { $0.id == id }) else { return }
                Task { await model.removePhoto(attachment) }
            },
            reportImportFailure: { model.feedback = .photoFailed },
            reportCameraUnavailable: { model.feedback = .cameraUnavailable },
            reportCameraPermissionDenied: { model.feedback = .cameraPermissionDenied }
        )
    }

    private var header: some View {
        HStack(alignment: .top, spacing: 20) {
            VStack(alignment: .leading, spacing: 7) {
                Button {
                    Task {
                        await model.cancel()
                        dismiss()
                    }
                } label: {
                    Label(LocalizedStringKey(backDestination.titleKey), systemImage: "chevron.left")
                        .font(.subheadline.weight(.semibold))
                }
                .buttonStyle(.plain)
                .foregroundStyle(FacilityTheme.blue)
                .frame(minHeight: 44, alignment: .leading)

                Text(detail.summary.title.isEmpty ? detail.summary.id : detail.summary.title)
                    .font(.system(size: 29, weight: .bold))
                    .foregroundStyle(FacilityTheme.ink)

                Text(notificationSubtitle)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }

            Spacer(minLength: 12)

            VStack(alignment: .trailing, spacing: 10) {
                if !detail.summary.displayStatus.isEmpty {
                    Text(detail.summary.displayStatus)
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(FacilityTheme.blue)
                        .multilineTextAlignment(.trailing)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 7)
                        .background(FacilityTheme.blue.opacity(0.10), in: Capsule())
                }
            }
        }
        .padding(.horizontal, 28)
        .padding(.vertical, 18)
        .background(FacilityTheme.surface)
    }

    private var notificationSubtitle: String {
        let identifier = "\(String(localized: "notifications.detail.number")) \(detail.summary.id)"
        return [identifier, detail.summary.displayDateRange]
            .filter { !$0.isEmpty }
            .joined(separator: " · ")
    }

    private var metadataCard: some View {
        HStack(alignment: .top, spacing: 30) {
            VStack(alignment: .leading, spacing: 15) {
                metadataRow(
                    "notifications.detail.technicalPlace",
                    detail.summary.functionalLocationID,
                    monospaced: true
                )
                metadataRow("notifications.detail.description", detail.summary.functionalLocationName)

                if !detail.structure.isEmpty {
                    metadataRow("notifications.detail.structure", detail.structure)
                }
                if !detail.equipmentID.isEmpty {
                    metadataRow("notifications.detail.equipment", detail.equipmentID, monospaced: true)
                }
                if !detail.summary.systemStatus.isEmpty {
                    metadataRow("notifications.detail.systemStatus", detail.summary.systemStatus)
                }
                if !detail.summary.userStatus.isEmpty {
                    metadataRow("notifications.detail.userStatus", detail.summary.userStatus)
                }
                if !detail.summary.displayDateRange.isEmpty {
                    metadataRow("notifications.detail.dateRange", detail.summary.displayDateRange)
                }
            }

            Spacer(minLength: 0)

            VStack(alignment: .leading, spacing: 8) {
                Text("notifications.detail.performedOn")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.secondary)

                DatePicker(
                    "notifications.detail.performedOn",
                    selection: Binding(
                        get: { model.performedOn },
                        set: { model.performedOn = $0 }
                    ),
                    displayedComponents: .date
                )
                .labelsHidden()
                .datePickerStyle(.compact)
                .disabled(isEditingDisabled)
                .padding(.horizontal, 8)
                .frame(minHeight: 44)
                .background(.white, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                .overlay {
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .stroke(.gray.opacity(0.22))
                }
            }
            .frame(width: 190, alignment: .leading)
        }
        .facilityCard(padding: 22)
    }

    private func metadataRow(
        _ titleKey: String,
        _ value: String,
        monospaced: Bool = false
    ) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 24) {
            Text(LocalizedStringKey(titleKey))
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .frame(width: 180, alignment: .leading)

            Text(value)
                .font(monospaced ? .subheadline.monospaced() : .body)
                .foregroundStyle(FacilityTheme.ink)
                .fixedSize(horizontal: false, vertical: true)

            Spacer(minLength: 0)
        }
    }

    private var inspectionCard: some View {
        VStack(spacing: 0) {
            HStack(spacing: 12) {
                Text("notifications.detail.numberColumn")
                    .frame(width: 42, alignment: .leading)
                Color.clear
                    .frame(width: 28, height: 1)
                Text("notifications.detail.inspectionPoint")
                    .frame(maxWidth: .infinity, alignment: .leading)
                Text("notifications.detail.result")
                    .frame(width: 130, alignment: .center)
                Text("notifications.detail.photo")
                    .frame(width: 52, alignment: .center)
                Text("notifications.detail.comment")
                    .frame(width: 58, alignment: .center)
            }
            .font(.subheadline.weight(.bold))
            .foregroundStyle(.secondary)
            .padding(.horizontal, 22)
            .padding(.vertical, 14)

            Divider()

            if detail.inspectionItems.isEmpty {
                ContentUnavailableView(
                    "notifications.detail.noInspectionItems.title",
                    systemImage: "list.bullet",
                    description: Text("notifications.detail.noInspectionItems.message")
                )
                .frame(maxWidth: .infinity, minHeight: 180)
            } else {
                ForEach(Array(detail.inspectionItems.enumerated()), id: \.element.id) { index, item in
                    InspectionItemRow(
                        item: item,
                        number: index + 1,
                        result: model.results[item.id],
                        isResultMissing: model.results[item.id] == nil,
                        isReadOnly: isEditingDisabled,
                        selectResult: {
                            guard !isEditingDisabled else { return }
                            model.results[item.id] = $0
                        },
                        attachments: model.attachments(for: item.id),
                        openPhotos: { photoWorkspaceItemID = item.id },
                        comment: model.comments[item.id, default: ""],
                        editComment: {
                            guard !isEditingDisabled else { return }
                            editingCommentID = item.id
                        }
                    )
                    if index < detail.inspectionItems.count - 1 {
                        Divider().padding(.leading, 22)
                    }
                }
            }
        }
        .background(FacilityTheme.surface, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        // A shadow around one long scrolling surface forces expensive
        // off-screen compositing. A subtle border keeps the same card edge
        // without making scroll performance depend on checklist height.
        .overlay {
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .stroke(Color.black.opacity(0.06))
        }
    }

    private func commentBinding(for itemID: String) -> Binding<String> {
        Binding(
            get: { model.comments[itemID, default: ""] },
            set: { newValue in
                guard !isEditingDisabled else { return }
                if newValue.isEmpty {
                    model.comments.removeValue(forKey: itemID)
                } else {
                    model.comments[itemID] = newValue
                }
            }
        )
    }

    private var actionBar: some View {
        HStack(spacing: 14) {
            Spacer(minLength: 12)

            Button("notifications.detail.allGood") {
                for item in detail.inspectionItems {
                    model.results[item.id] = .no
                }
            }
            .buttonStyle(.plain)
            .foregroundStyle(FacilityTheme.blue)
            .disabled(isEditingDisabled || detail.inspectionItems.isEmpty || model.isSaving)

            Button("notifications.detail.saveTemporary") {
                Task { await model.save(closed: false) }
            }
            .buttonStyle(.bordered)
            .tint(FacilityTheme.ink)
            .disabled(isEditingDisabled || model.isSaving)

            Button("notifications.detail.closeNotification") {
                isCloseConfirmationPresented = true
            }
            .buttonStyle(.borderedProminent)
            .tint(FacilityTheme.accent)
            .disabled(isEditingDisabled || model.isSaving || !canCloseNotification)
        }
        .padding(.horizontal, 28)
        .padding(.vertical, 12)
        .background(.ultraThinMaterial)
        .overlay(alignment: .top) { Divider() }
    }

    private var canCloseNotification: Bool {
        model.canClose
    }

    private var isReadOnly: Bool {
        model.isClosedLocally
    }

    private var isEditingDisabled: Bool {
        model.isEditingDisabled
    }

}

private extension NotificationReviewViewModel.Feedback {
    var messageKey: LocalizedStringKey {
        switch self {
        case .savedLocally: "notifications.detail.action.saved"
        case .closedLocally: "notifications.detail.action.closed"
        case .incomplete: "notifications.detail.action.incomplete"
        case .saveFailed: "notifications.detail.action.failed"
        case .photoFailed: "notifications.detail.photo.failed"
        case .photoLimitReached: "notifications.detail.photo.limit"
        case .cameraUnavailable: "notifications.detail.photo.cameraUnavailable"
        case .cameraPermissionDenied: "notifications.detail.photo.cameraPermissionDenied"
        }
    }
}

private struct CommentEditorOverlay: View {
    @Binding var comment: String
    let dismiss: () -> Void
    @FocusState private var isEditorFocused: Bool

    var body: some View {
        ZStack {
            Color.black.opacity(0.14)
                .ignoresSafeArea()
                .onTapGesture(perform: dismiss)

            VStack(alignment: .leading, spacing: 16) {
                Text("notifications.detail.commentEditor.title")
                    .font(.headline)
                    .foregroundStyle(FacilityTheme.ink)

                ZStack(alignment: .topLeading) {
                    if comment.isEmpty {
                        Text("notifications.detail.commentEditor.placeholder")
                            .font(.body)
                            .foregroundStyle(.tertiary)
                            .padding(.horizontal, 16)
                            .padding(.vertical, 18)
                            .allowsHitTesting(false)
                    }

                    TextEditor(text: $comment)
                        .font(.body)
                        .scrollContentBackground(.hidden)
                        .padding(10)
                        .focused($isEditorFocused)
                        .accessibilityLabel(Text("notifications.detail.commentEditor.placeholder"))
                }
                .frame(height: 190)
                .background(Color(white: 0.89), in: RoundedRectangle(cornerRadius: 12, style: .continuous))

                HStack {
                    Spacer()
                    Button("notifications.detail.commentEditor.done", action: dismiss)
                        .buttonStyle(.borderedProminent)
                        .tint(FacilityTheme.accent)
                }
            }
            .padding(22)
            .frame(maxWidth: 460)
            .background(Color(white: 0.95), in: RoundedRectangle(cornerRadius: 24, style: .continuous))
            .shadow(color: Color.black.opacity(0.20), radius: 26, y: 12)
            .padding(28)
        }
        .onAppear { isEditorFocused = true }
    }
}

private struct InspectionItemRow: View {
    let item: SAPNotificationDetail.InspectionItem
    let number: Int
    let result: NotificationReviewResult?
    let isResultMissing: Bool
    let isReadOnly: Bool
    let selectResult: (NotificationReviewResult) -> Void
    let attachments: [NotificationPhotoAttachment]
    let openPhotos: () -> Void
    let comment: String
    let editComment: () -> Void
    @State private var isShowingInformation = false

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 12) {
                Text(number, format: .number)
                    .font(.body.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .frame(width: 42, alignment: .leading)

                Image(systemName: "exclamationmark.triangle")
                    .font(.title3.weight(.semibold))
                    .foregroundStyle(FacilityTheme.red)
                    .frame(width: 28, height: 52)
                    .opacity(isResultMissing ? 1 : 0)
                    .accessibilityLabel(Text("notifications.detail.validation.incompleteItem"))
                    .accessibilityHidden(!isResultMissing)

                HStack(spacing: 10) {
                    if item.information.isEmpty {
                        Image(systemName: "info.circle")
                            .foregroundStyle(.tertiary)
                            .frame(width: 28, height: 28)
                    } else {
                        Button {
                            isShowingInformation = true
                        } label: {
                            Image(systemName: "info.circle.fill")
                                .font(.title2.weight(.semibold))
                                .foregroundStyle(FacilityTheme.blue)
                                .frame(width: 52, height: 52)
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel(Text("notifications.detail.showInformation"))
                        .popover(isPresented: $isShowingInformation) {
                            Text(item.information)
                                .font(.body)
                                .padding(20)
                                .frame(width: 360, alignment: .leading)
                        }
                    }

                    Text(item.title)
                        .font(.body)
                        .foregroundStyle(FacilityTheme.ink)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }

                resultControl
                    .frame(width: 130)

                Button(action: openPhotos) {
                    ZStack(alignment: .topTrailing) {
                        Image(systemName: attachments.isEmpty ? "camera" : "camera.fill")
                            .foregroundStyle(attachments.isEmpty ? FacilityTheme.ink : FacilityTheme.blue)
                            .frame(width: 44, height: 44)
                            .background(.white, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                            .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous).stroke(.gray.opacity(0.25)))
                        if !attachments.isEmpty {
                            Text(attachments.count, format: .number)
                                .font(.caption2.bold())
                                .foregroundStyle(.white)
                                .frame(minWidth: 18, minHeight: 18)
                                .background(FacilityTheme.blue, in: Circle())
                                .offset(x: 5, y: -5)
                        }
                    }
                }
                .buttonStyle(.plain)
                .accessibilityLabel(Text("notifications.detail.photo"))
                .accessibilityValue(Text(String(format: String(localized: "notifications.detail.photo.count"), attachments.count)))
                .frame(width: 52)

                Button(action: editComment) {
                    Image(systemName: comment.isEmpty ? "pencil" : "note.text")
                        .foregroundStyle(comment.isEmpty ? FacilityTheme.ink : FacilityTheme.blue)
                        .frame(width: 44, height: 44)
                        .background(.white, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                        .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous).stroke(.gray.opacity(0.25)))
                }
                .buttonStyle(.plain)
                .disabled(isReadOnly)
                .accessibilityLabel(Text("notifications.detail.comment"))
                .frame(width: 58)
            }

        }
        .padding(.horizontal, 22)
        .padding(.vertical, 10)
        .frame(minHeight: 64)
    }

    private var resultControl: some View {
        HStack(spacing: 0) {
            resultButton(.no, titleKey: "notifications.detail.result.no")
            resultButton(.yes, titleKey: "notifications.detail.result.yes")
        }
        .background(Color(white: 0.94), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
    }

    private func resultButton(_ value: NotificationReviewResult, titleKey: String) -> some View {
        Button { selectResult(value) } label: {
            Text(LocalizedStringKey(titleKey))
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(result == value ? .white : .secondary)
                .frame(maxWidth: .infinity, minHeight: 38)
                .background(result == value ? FacilityTheme.accent : .clear, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
        }
        .buttonStyle(.plain)
        .disabled(isReadOnly)
    }
}
