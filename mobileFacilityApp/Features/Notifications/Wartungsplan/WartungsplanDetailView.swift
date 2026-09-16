import SwiftUI

struct WartungsplanDetailView: View {
    let detail: SAPNotificationDetail
    let offlineWorkStore: OfflineWorkStore
    let photoAttachmentStore: any PhotoAttachmentStore
    let backDestination: AppDestination
    let dismiss: () -> Void

    @Environment(\.accessibilityReduceMotion) private var accessibilityReduceMotion
    @State private var model: WartungsplanViewModel
    @State private var editingCommentID: String?
    @State private var isDraftSavedConfirmationPresented = false
    @State private var isCloseConfirmationPresented = false
    @State private var photoWorkspaceItemID: String?

    init(
        detail: SAPNotificationDetail,
        offlineWorkStore: OfflineWorkStore,
        photoAttachmentStore: any PhotoAttachmentStore,
        backDestination: AppDestination = .notifications,
        dismiss: @escaping () -> Void
    ) {
        self.detail = detail
        self.offlineWorkStore = offlineWorkStore
        self.photoAttachmentStore = photoAttachmentStore
        self.backDestination = backDestination
        self.dismiss = dismiss
        _model = State(initialValue: WartungsplanViewModel(
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
                        VStack(spacing: 20) {
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
                NotificationCommentEditorOverlay(
                    comment: commentBinding(for: editingCommentID),
                    dismiss: { self.editingCommentID = nil }
                )
            }
        }
        .task(id: detail.summary.id) { await model.load() }
        .alert(
            "mobileLadder.feedback.saved.title",
            isPresented: $isDraftSavedConfirmationPresented
        ) {
            Button("common.ok") { dismiss() }
        } message: {
            Text("mobileLadder.feedback.saved.message")
        }
        .alert(
            "notifications.detail.closeConfirmation.title",
            isPresented: $isCloseConfirmationPresented
        ) {
            Button("notifications.detail.closeConfirmation.confirm", role: .destructive) {
                Task {
                    if await model.save(closed: true) {
                        dismiss()
                    }
                }
            }
            Button("common.cancel", role: .cancel) { }
        } message: {
            Text("notifications.detail.closeConfirmation.message")
        }
        .alert(item: $model.feedback) { feedback in
            Alert(
                title: Text("notifications.detail.action.title"),
                message: Text(feedbackMessage(for: feedback)),
                dismissButton: .default(Text("common.ok")) {
                    if feedback == .closedLocally {
                        dismiss()
                    }
                }
            )
        }
    }

    private var headerInfo: NotificationFormHeaderInfo {
        NotificationFormHeaderInfo(detail: detail, formCode: "TFM1")
    }

    private var header: some View {
        NotificationFormHeaderBar(
            info: headerInfo,
            backTitleKey: backDestination.titleKey,
            isClosedLocally: model.isClosedLocally,
            back: {
                Task {
                    await model.cancel()
                    dismiss()
                }
            }
        )
    }

    /// TFM1 is the one form that carries no execution date in its header:
    /// `WartungsPlan.controller.js` hides the legacy `form.date` row that every
    /// other form view shows, so the card is rendered without the date picker
    /// and `model.performedOn` stays at the default the upload sends as `AEDAT`.
    private var metadataCard: some View {
        NotificationFormHeaderCard(info: headerInfo)
    }

    /// Inspection checklist table card with columns: No., [i], Reviewed asset, Result, Photo, Comment.
    private var inspectionCard: some View {
        VStack(spacing: 0) {
            tableHeader
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
                    WartungsplanItemRow(
                        item: item,
                        number: index + 1,
                        result: model.results[item.id],
                        isCommentMissing: model.isCommentMissing(for: item.id),
                        isReadOnly: model.isEditingDisabled,
                        selectResult: { newResult in
                            guard !model.isEditingDisabled else { return }
                            model.results[item.id] = newResult
                            // When defect is selected and comment is empty, prompt comment overlay immediately.
                            if newResult == .yes && (model.comments[item.id]?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ?? true) {
                                editingCommentID = item.id
                            }
                        },
                        attachments: model.attachments(for: item.id),
                        openPhotos: { photoWorkspaceItemID = item.id },
                        comment: model.comments[item.id, default: ""],
                        editComment: {
                            guard !model.isEditingDisabled else { return }
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
        .overlay {
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .stroke(Color.black.opacity(0.06))
        }
    }

    private var tableHeader: some View {
        HStack(spacing: 12) {
            Text("notifications.detail.numberColumn")
                .frame(width: 42, alignment: .leading)

            Color.clear
                .frame(width: 28, height: 1)

            Text("wartungsplan.column.reviewedAsset")
                .frame(maxWidth: .infinity, alignment: .leading)

            Text("notifications.detail.result")
                .frame(width: 150, alignment: .center)

            Text("notifications.detail.photo")
                .frame(width: 52, alignment: .center)

            Text("notifications.detail.comment")
                .frame(width: 58, alignment: .center)
        }
        .font(.subheadline.weight(.bold))
        .foregroundStyle(.secondary)
        .padding(.horizontal, 22)
        .padding(.vertical, 14)
    }

    /// Bottom bar reused from Mobile Ladder (FacilityInspectionActionBar).
    @ViewBuilder
    private var actionBar: some View {
        if model.isClosedLocally {
            HStack(spacing: 14) {
                Spacer(minLength: 12)
                Button("common.back", action: dismiss)
                    .buttonStyle(.bordered)
                    .tint(FacilityTheme.ink)
            }
            .padding(.horizontal, 28)
            .padding(.vertical, 12)
            .background(.ultraThinMaterial)
            .overlay(alignment: .top) { Divider() }
        } else {
            FacilityInspectionActionBar(
                markEverythingOkay: { model.markEverythingOkay() },
                saveDraft: {
                    Task {
                        if await model.save(closed: false) {
                            isDraftSavedConfirmationPresented = true
                        }
                    }
                },
                closeNotification: {
                    isCloseConfirmationPresented = true
                },
                isMarkEverythingOkayEnabled: !model.isEditingDisabled && !detail.inspectionItems.isEmpty && !model.isSaving,
                isSaveDraftEnabled: !model.isEditingDisabled && !model.isSaving,
                isCloseNotificationEnabled: !model.isEditingDisabled && !model.isSaving && model.canClose
            )
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
            isReadOnly: model.isEditingDisabled,
            maxAttachments: WartungsplanViewModel.maximumPhotoCount - (model.photoAttachments.count - attachments.count),
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

    private func commentBinding(for itemID: String) -> Binding<String> {
        Binding(
            get: { model.comments[itemID, default: ""] },
            set: { newValue in
                guard !model.isEditingDisabled else { return }
                if newValue.isEmpty {
                    model.comments.removeValue(forKey: itemID)
                } else {
                    model.comments[itemID] = newValue
                }
            }
        )
    }

    private func feedbackMessage(for feedback: WartungsplanViewModel.Feedback) -> LocalizedStringKey {
        switch feedback {
        case .savedLocally: "notifications.detail.action.saved"
        case .closedLocally: "notifications.detail.action.closed"
        case .incomplete: "wartungsplan.validation.incomplete"
        case .commentRequired: "wartungsplan.validation.commentRequired"
        case .saveFailed: "notifications.detail.action.failed"
        case .photoFailed: "notifications.detail.photo.failed"
        case .photoLimitReached: "notifications.detail.photo.limit"
        case .cameraUnavailable: "notifications.detail.photo.cameraUnavailable"
        case .cameraPermissionDenied: "notifications.detail.photo.cameraPermissionDenied"
        }
    }
}

private struct WartungsplanItemRow: View {
    let item: SAPNotificationDetail.InspectionItem
    let number: Int
    let result: NotificationReviewResult?
    let isCommentMissing: Bool
    let isReadOnly: Bool
    let selectResult: (NotificationReviewResult) -> Void
    let attachments: [NotificationPhotoAttachment]
    let openPhotos: () -> Void
    let comment: String
    let editComment: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            Text(number, format: .number)
                .font(.body.weight(.semibold))
                .foregroundStyle(.secondary)
                .frame(width: 42, alignment: .leading)

            HStack(spacing: 10) {
                NotificationInfoButton(information: item.information)

                Text(item.title)
                    .font(.body)
                    .foregroundStyle(FacilityTheme.ink)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }

            segmentedResultControl
                .frame(width: 150)

            NotificationPhotoButton(count: attachments.count, action: openPhotos)

            NotificationCommentButton(
                hasComment: !comment.isEmpty,
                isMissing: isCommentMissing,
                isReadOnly: isReadOnly,
                action: editComment
            )
        }
        .padding(.horizontal, 22)
        .padding(.vertical, 10)
        .frame(minHeight: 64)
    }

    /// Segmented result control with [ Nein | Ja ] matching legacy screenshot styling.
    private var segmentedResultControl: some View {
        HStack(spacing: 0) {
            Button {
                selectResult(.no)
            } label: {
                Text("notifications.detail.result.no")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(result == .no ? .white : FacilityTheme.blue)
                    .frame(maxWidth: .infinity, minHeight: 36)
                    .background(result == .no ? FacilityTheme.blue : Color.clear)
            }
            .buttonStyle(.plain)
            .disabled(isReadOnly)

            Rectangle()
                .fill(FacilityTheme.blue.opacity(0.35))
                .frame(width: 1, height: 36)

            Button {
                selectResult(.yes)
            } label: {
                Text("notifications.detail.result.yes")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(result == .yes ? .white : FacilityTheme.blue)
                    .frame(maxWidth: .infinity, minHeight: 36)
                    .background(result == .yes ? FacilityTheme.blue : Color.clear)
            }
            .buttonStyle(.plain)
            .disabled(isReadOnly)
        }
        .frame(width: 150)
        .background(Color.white)
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .stroke(FacilityTheme.blue, lineWidth: 1.5)
        )
    }
}
