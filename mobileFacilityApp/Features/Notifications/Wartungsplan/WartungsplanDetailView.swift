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
        .facilityConfirmationDialog(
            isPresented: $isCloseConfirmationPresented,
            titleKey: "notifications.detail.closeConfirmation.title",
            messageKey: "notifications.detail.closeConfirmation.message",
            confirmTitleKey: "notifications.detail.closeConfirmation.confirm"
        ) {
            Task {
                if await model.save(closed: true) {
                    dismiss()
                }
            }
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

    /// TFM1 Wartungsplan. The shared checklist configured by its form code:
    /// a two-value segmented result, no action or material column, and no
    /// header status (`BaseFormController.buildDefaultElements` returns early
    /// for TFM1).
    private var variant: InspectionFormVariant {
        InspectionFormVariant.forFormCode("TFM1")
    }

    private var formItems: [InspectionFormItem] {
        detail.inspectionItems.enumerated().map { index, item in
            item.inspectionFormItem(number: index + 1)
        }
    }

    private var inspectionCard: some View {
        InspectionFormTable(
            variant: variant,
            items: formItems,
            state: { item in
                InspectionFormItemState(
                    resultID: model.results[item.id]?.optionID,
                    comment: model.comments[item.id, default: ""],
                    photoCount: model.attachments(for: item.id).count
                )
            },
            isEditable: !model.isEditingDisabled,
            emptyState: InspectionFormEmptyState(
                titleKey: "notifications.detail.noInspectionItems.title",
                messageKey: "notifications.detail.noInspectionItems.message",
                systemImage: "list.bullet"
            ),
            actions: InspectionFormActions(
                selectResult: { item, option in
                    guard !model.isEditingDisabled,
                          let result = NotificationReviewResult(optionID: option.id)
                    else { return }
                    model.results[item.id] = result
                    // `WartungsPlan.controller.js.onBefundChange` opens the
                    // comment popover as soon as a defect is picked.
                    if result == .yes, model.isCommentMissing(for: item.id) {
                        editingCommentID = item.id
                    }
                },
                openPhotos: { photoWorkspaceItemID = $0.id },
                editComment: { item in
                    guard !model.isEditingDisabled else { return }
                    editingCommentID = item.id
                }
            )
        )
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
                    capturedAt: $0.capturedAt,
                    name: $0.name,
                    description: $0.description
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
            updatePhoto: { id, name, description in
                await model.updatePhoto(id: id, name: name, description: description)
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
