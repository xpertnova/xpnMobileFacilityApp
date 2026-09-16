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
                NotificationCommentEditorOverlay(
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
        .facilityConfirmationDialog(
            isPresented: $isCloseConfirmationPresented,
            titleKey: "notifications.detail.closeConfirmation.title",
            messageKey: "notifications.detail.closeConfirmation.message",
            confirmTitleKey: "notifications.detail.closeConfirmation.confirm"
        ) {
            Task { await model.save(closed: true) }
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
            isReadOnly: isReadOnly,
            maxAttachments: nil,
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

    private var headerInfo: NotificationFormHeaderInfo {
        NotificationFormHeaderInfo(detail: detail)
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

    /// The execution date lives on the checklist toolbar, where the legacy
    /// `form.date` row of `TableFormHeader.fragment.xml` puts it.
    private var metadataCard: some View {
        NotificationFormHeaderCard(info: headerInfo)
    }

    /// TFM3 Rundgang. Same shared checklist as every other form, configured
    /// by its form code: a two-value segmented result, no action or material
    /// column, and no header status.
    private var variant: InspectionFormVariant {
        InspectionFormVariant.forFormCode("TFM3")
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
            isEditable: !isEditingDisabled,
            emptyState: InspectionFormEmptyState(
                titleKey: "notifications.detail.noInspectionItems.title",
                messageKey: "notifications.detail.noInspectionItems.message",
                systemImage: "list.bullet"
            ),
            performedOn: variant.showsPerformedOnDate
                ? Binding(get: { model.performedOn }, set: { model.performedOn = $0 })
                : nil,
            isPerformedOnDisabled: isEditingDisabled,
            actions: InspectionFormActions(
                selectResult: { item, option in
                    guard !isEditingDisabled,
                          let result = NotificationReviewResult(optionID: option.id)
                    else { return }
                    model.results[item.id] = result
                    // `Rundgang.controller.js.onBefundChange` opens the comment
                    // popover as soon as a defect is picked, because closing
                    // the notification then requires one.
                    if result == .yes, model.isCommentMissing(for: item.id) {
                        editingCommentID = item.id
                    }
                },
                openPhotos: { photoWorkspaceItemID = $0.id },
                editComment: { item in
                    guard !isEditingDisabled else { return }
                    editingCommentID = item.id
                }
            )
        )
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
        FacilityInspectionActionBar(
            markEverythingOkay: {
                for item in detail.inspectionItems {
                    model.results[item.id] = .no
                }
            },
            saveDraft: {
                Task { await model.save(closed: false) }
            },
            closeNotification: {
                isCloseConfirmationPresented = true
            },
            isMarkEverythingOkayEnabled: !isEditingDisabled && !detail.inspectionItems.isEmpty && !model.isSaving,
            isSaveDraftEnabled: !isEditingDisabled && !model.isSaving,
            isCloseNotificationEnabled: !isEditingDisabled && !model.isSaving && canCloseNotification
        )
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
