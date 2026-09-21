import SwiftUI

/// The one screen of every shared equipment inspection (TFM2
/// Aufzugskontrolle, TFM4 Steigleitern). It is assembled from the shared form
/// components — `NotificationFormHeaderBar`/`Card`, `InspectionFormTable`,
/// `InspectionOutOfServiceControls`, `PhotoWorkspace` and
/// `FacilityInspectionActionBar` — and takes every per-form difference from
/// `EquipmentInspectionForm`.
struct EquipmentInspectionView: View {
    let detail: SAPNotificationDetail
    let backDestination: AppDestination
    let dismiss: () -> Void
    /// The legacy missing-class-characteristics acknowledgement always returns
    /// to the notification list. This is deliberately separate from the
    /// normal Back action, which can return an offline draft to its source.
    let dismissForMissingMasterData: () -> Void

    @Environment(\.accessibilityReduceMotion) private var accessibilityReduceMotion
    @State private var model: EquipmentInspectionViewModel
    @State private var isSaveDraftConfirmationPresented = false
    @State private var editingCommentID: String?
    @State private var photoWorkspaceItemID: String?
    @State private var isMasterDataErrorPresented = false

    init(
        detail: SAPNotificationDetail,
        form: EquipmentInspectionForm? = nil,
        offlineWorkStore: OfflineWorkStore,
        photoAttachmentStore: any PhotoAttachmentStore,
        sapDataStore: SAPDataStore? = nil,
        elevatorAssetDataProvider: any ElevatorAssetDataProviding = UnavailableElevatorAssetDataProvider(),
        backDestination: AppDestination,
        dismiss: @escaping () -> Void,
        dismissForMissingMasterData: (() -> Void)? = nil
    ) {
        self.detail = detail
        self.backDestination = backDestination
        self.dismiss = dismiss
        self.dismissForMissingMasterData = dismissForMissingMasterData ?? dismiss
        _model = State(initialValue: EquipmentInspectionViewModel(
            detail: detail,
            form: form,
            offlineWorkStore: offlineWorkStore,
            photoStore: photoAttachmentStore,
            sapDataStore: sapDataStore,
            elevatorAssetDataProvider: elevatorAssetDataProvider
        ))
    }

    var body: some View {
        ZStack {
            if let photoWorkspaceItemID {
                photoWorkspace(for: photoWorkspaceItemID)
                    .transition(PhotoWorkspaceMotion.destination)
                    .zIndex(1)
            } else {
                VStack(spacing: 0) {
                    header

                    ScrollView {
                        VStack(spacing: 18) {
                            metadataCard
                            // Cordova dismisses every form that requires
                            // class characteristics instead of leaving an
                            // unavailable master-data surface in the form.
                            // Keep the section out of the layer beneath its
                            // blocking error frame.
                            if !model.isMasterDataMissing {
                                masterDataCard
                            }
                            inspectionCard
                        }
                        .facilityPageContent()
                    }
                }
                .background(FacilityTheme.canvas.ignoresSafeArea())
                .safeAreaInset(edge: .bottom) { actionBar }
                .transition(PhotoWorkspaceMotion.source)
            }

            // This must be in the root ZStack, above the notification and
            // photo workspace, rather than a same-level view modifier. It is
            // intentionally non-dismissible except for its acknowledgement.
            if isMasterDataErrorPresented {
                masterDataErrorOverlay
                    .zIndex(100)
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
            } else if let characteristic = proposalCharacteristic {
                MasterDataProposalEditor(
                    fieldTitle: characteristic.title,
                    initialText: model.proposal(for: characteristic),
                    history: model.proposalHistory(for: characteristic),
                    cancel: { model.proposalCharacteristicID = nil },
                    save: { model.saveProposal($0, for: characteristic) }
                )
                .id(characteristic.name)
            }
        }
        // If SwiftUI retains this destination while it is navigated away from
        // and opened again, its data may already be unavailable. Re-present
        // the blocking frame on each appearance; the post-load check below
        // covers a newly fetched failure.
        .onAppear {
            presentMasterDataErrorIfNeeded()
        }
        .task(id: detail.summary.id) {
            await model.load()
            presentMasterDataErrorIfNeeded()
        }
        // Cordova's `HeaderFormBuilder.showInvalidData` blocks every form
        // that requires class characteristics when they are unavailable,
        // then returns to the notification list after acknowledgement.
        .onChange(of: model.isMasterDataMissing) { _, isMissing in
            if isMissing { presentMasterDataErrorIfNeeded() }
        }
        .alert(item: $model.feedback) { feedback in
            Alert(
                title: Text("notifications.detail.action.title"),
                message: Text(feedback.messageKey),
                dismissButton: .default(Text("notifications.detail.commentEditor.done")) {
                    switch feedback {
                    case .closedLocally, .i2NotificationsQueued:
                        dismiss()
                    default:
                        break
                    }
                }
            )
        }
        .facilitySaveDraftConfirmation(isPresented: $isSaveDraftConfirmationPresented) {
            Task {
                if await model.save(closed: false) {
                    model.feedback = nil
                    dismiss()
                }
            }
        }
        .facilityConfirmationDialog(
            isPresented: $model.isCloseConfirmationPresented,
            titleKey: "notifications.detail.closeConfirmation.title",
            messageKey: "notifications.detail.closeConfirmation.message",
            confirmTitleKey: "notifications.detail.closeConfirmation.confirm"
        ) {
            Task { await model.confirmClose() }
        }
        // A defective inspection asks for a status instead of a plain
        // confirmation, in the same framed dialog.
        .facilityConfirmationDialog(
            isPresented: $model.isStatusDecisionPresented,
            titleKey: "elevator.closeDialog.title",
            messageKey: model.form.defectCloseMessageKey,
            actions: [
                FacilityDialogAction(titleKey: "elevator.closeDialog.leaveOpen") {
                    Task { await model.confirmStatusDecision(.leaveOpen) }
                },
                FacilityDialogAction(
                    titleKey: "elevator.closeDialog.close",
                    emphasis: .primary
                ) {
                    Task { await model.confirmStatusDecision(.close) }
                }
            ]
        )
        .alert(item: $model.outOfServiceTransition) { transition in
            Alert(
                title: Text(LocalizedStringKey(transition.titleKey)),
                message: Text(LocalizedStringKey(transition.messageKey)),
                primaryButton: .destructive(Text("inspection.outOfService.continue")) {
                    Task { await model.confirmOutOfServiceChange(to: transition.isActive) }
                },
                secondaryButton: .cancel(Text("common.cancel"))
            )
        }
        .i2DefectSelectionDialog(
            model.i2Selection,
            accept: {
                Task {
                    if !(await model.acceptI2Selection()) {
                        dismiss()
                    }
                }
            },
            cancel: {
                model.cancelI2Selection()
                dismiss()
            }
        )
    }

    /// Photos belong either to a checklist position or to the header status
    /// row, which is not part of `model.items`.
    private func photoWorkspace(for rowID: String) -> some View {
        let isOutOfServiceRow = rowID == model.outOfServiceRowID
        let item = model.items.first { $0.id == rowID }
        let attachments = model.attachments(for: rowID)
        let subtitle = isOutOfServiceRow
            ? String(localized: "inspection.outOfService")
            : (item?.title ?? "")
        return PhotoWorkspace(
            title: String(localized: "photos.workspace.title"),
            subtitle: subtitle,
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
            isReadOnly: isReadOnly || (!isOutOfServiceRow && model.isOutOfService),
            maxAttachments: EquipmentInspectionViewModel.maximumPhotoCount - (model.photoAttachments.count - attachments.count),
            close: { photoWorkspaceItemID = nil },
            addPhoto: { data in
                if isOutOfServiceRow {
                    await model.addOutOfServicePhoto(jpegData: data)
                } else if let item {
                    await model.addPhoto(jpegData: data, to: item)
                }
            },
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
        NotificationFormHeaderInfo(detail: detail, formCode: model.form.formCode)
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

    /// The execution date and the header status live on the checklist
    /// toolbar, not here — the legacy `form.date` and `form.outOfOrder`
    /// controls sit in `TableFormHeader.fragment.xml`, directly above the
    /// position table.
    private var metadataCard: some View {
        NotificationFormHeaderCard(info: headerInfo)
    }

    /// The header "Außer Betrieb" status that
    /// `BaseFormController.buildDefaultElements` builds for TFM2 and TFM4.
    private var outOfServiceControls: InspectionOutOfServiceControls? {
        guard let titleKey = variant.outOfServiceTitleKey else { return nil }
        return InspectionOutOfServiceControls(
            titleKey: titleKey,
            isActive: model.isOutOfService,
            photoCount: model.attachments(for: model.outOfServiceRowID).count,
            isPhotoLimitReached: model.photoAttachments.count >= EquipmentInspectionViewModel.maximumPhotoCount,
            hasComment: !model.outOfServiceComment.isEmpty,
            isCommentMissing: model.isOutOfServiceCommentMissing,
            isEnabled: !isEditingDisabled && !model.isSaving,
            requestStatusChange: { model.requestOutOfServiceChange() },
            openPhotos: { photoWorkspaceItemID = model.outOfServiceRowID },
            editComment: { editingCommentID = model.outOfServiceRowID }
        )
    }

    /// Class characteristics above the checklist
    /// (`HeaderFormBuilder.createHeaderForm`), editable unless the equipment
    /// type is read-only (`_isEditable`).
    private var masterDataCard: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack(alignment: .firstTextBaseline, spacing: 10) {
                Image(systemName: "building.2.crop.circle")
                    .foregroundStyle(FacilityTheme.blue)
                    .accessibilityHidden(true)

                VStack(alignment: .leading, spacing: 3) {
                    Text(LocalizedStringKey(model.form.masterDataTitleKey))
                        .font(.title3.weight(.bold))
                        .foregroundStyle(FacilityTheme.ink)
                    Text(LocalizedStringKey(model.form.masterDataSubtitleKey))
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                Spacer(minLength: 12)
                if model.elevatorAssetDataState == .ready && !model.isMasterDataRecordEditable {
                    Text("elevator.assetData.readOnly")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, 9)
                        .padding(.vertical, 5)
                        .background(Color.black.opacity(0.05), in: Capsule())
                }
            }

            switch model.elevatorAssetDataState {
            case .loading:
                HStack(spacing: 12) {
                    ProgressView()
                    Text(LocalizedStringKey(model.form.masterDataLoadingKey))
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, minHeight: 88, alignment: .leading)

            case .ready:
                EquipmentMasterDataFields(model: model)

            case .unavailable:
                ContentUnavailableView(
                    LocalizedStringKey(model.form.masterDataUnavailableTitleKey),
                    systemImage: model.isMasterDataMissing ? "exclamationmark.triangle" : "archivebox",
                    description: Text(LocalizedStringKey(model.form.masterDataUnavailableMessageKey))
                )
                .frame(maxWidth: .infinity, minHeight: 124)

                Button {
                    Task { await model.reloadElevatorAssetData() }
                } label: {
                    Label("elevator.assetData.retry", systemImage: "arrow.clockwise")
                }
                .buttonStyle(.bordered)
                .tint(FacilityTheme.blue)
                .frame(minHeight: 44)
            }
        }
        .facilityCard(padding: 22)
    }

    /// The shared checklist configured by the form code: SAP-driven dropdowns
    /// for result and action, the material checkbox where the form has one,
    /// and the header "Außer Betrieb" status.
    private var variant: InspectionFormVariant {
        model.form.variant
            .adjusted(
                hasActionValues: model.items.contains { $0.hasAction },
                hasMaterialValues: model.hasMaterialColumn
            )
    }

    private var formItems: [InspectionFormItem] {
        model.items.map(\.inspectionFormItem)
    }

    private var inspectionCard: some View {
        InspectionFormTable(
            variant: variant,
            items: formItems,
            state: { item in
                InspectionFormItemState(
                    resultID: model.results[item.id],
                    actionID: model.actions[item.id],
                    isMaterialSelected: model.materials[item.id] ?? false,
                    comment: model.comments[item.id, default: ""],
                    photoCount: model.attachments(for: item.id).count,
                    isFlagged: model.validationErrors.contains(item.id)
                )
            },
            isEditable: model.arePositionsEditable,
            isPhotoLimitReached: model.photoAttachments.count >= EquipmentInspectionViewModel.maximumPhotoCount,
            emptyState: InspectionFormEmptyState(
                titleKey: model.form.checklistUnavailableTitleKey,
                messageKey: "elevator.unavailable.message",
                systemImage: "exclamationmark.triangle",
                retry: { Task { await model.load() } }
            ),
            performedOn: variant.showsPerformedOnDate ? $model.performedOn : nil,
            isPerformedOnDisabled: isReadOnly,
            outOfService: outOfServiceControls,
            existingI2Notifications: model.existingI2Notifications,
            actions: InspectionFormActions(
                selectResult: { item, option in
                    guard model.arePositionsEditable else { return }
                    model.results[item.id] = option.code
                    // `BaseFormController.onBefundChange` clears an action and
                    // a material flag the new result no longer permits.
                    let resolved = InspectionFormRules.resolvedSelection(
                        resultCode: option.code,
                        actionCode: model.actions[item.id],
                        isMaterialSelected: model.materials[item.id] ?? false,
                        style: variant.resultStyle
                    )
                    model.actions[item.id] = resolved.actionCode
                    model.materials[item.id] = resolved.isMaterialSelected
                    model.validationErrors.remove(item.id)
                },
                selectAction: { item, option in
                    guard model.arePositionsEditable else { return }
                    model.actions[item.id] = option.code
                },
                toggleMaterial: { item in
                    guard model.arePositionsEditable else { return }
                    model.materials[item.id] = !(model.materials[item.id] ?? false)
                },
                openPhotos: { photoWorkspaceItemID = $0.id },
                editComment: { item in
                    guard model.arePositionsEditable else { return }
                    editingCommentID = item.id
                }
            )
        )
    }

    private func commentBinding(for itemID: String) -> Binding<String> {
        if itemID == model.outOfServiceRowID {
            return Binding(
                get: { model.outOfServiceComment },
                set: { newValue in
                    guard !isEditingDisabled else { return }
                    model.outOfServiceComment = newValue
                }
            )
        }
        return Binding(
            get: { model.comments[itemID, default: ""] },
            set: { newValue in
                guard model.arePositionsEditable else { return }
                if newValue.isEmpty {
                    model.comments.removeValue(forKey: itemID)
                } else {
                    model.comments[itemID] = newValue
                }
            }
        )
    }

    /// The same three-button bar every other inspection form uses; the order
    /// and treatment come from `FacilityInspectionActionBar`.
    private var actionBar: some View {
        FacilityInspectionActionBar(
            markEverythingOkay: { model.applyAllGood() },
            saveDraft: { isSaveDraftConfirmationPresented = true },
            closeNotification: { model.handleCloseTapped() },
            // `setValues4AnwStatus` disables "Alles OK" while the form is out
            // of service.
            isMarkEverythingOkayEnabled: model.arePositionsEditable
                && model.isAllGoodAvailable
                && !model.isSaving,
            isSaveDraftEnabled: !isEditingDisabled && !model.isSaving,
            isCloseNotificationEnabled: !isEditingDisabled
                && !model.isSaving
                && (!model.items.isEmpty || model.isOutOfService)
        )
    }

    private var masterDataErrorOverlay: some View {
        ZStack {
            Color.black.opacity(0.32)
                .ignoresSafeArea()

            FacilityConfirmationDialog(
                titleKey: "inspection.masterData.error.title",
                messageKey: "inspection.masterData.error.message",
                symbol: "exclamationmark.circle",
                tint: FacilityTheme.red,
                cancelTitleKey: nil,
                actions: [
                    FacilityDialogAction(titleKey: "common.ok", emphasis: .primary) {
                        isMasterDataErrorPresented = false
                        dismissForMissingMasterData()
                    }
                ],
                cancel: {}
            )
        }
        .accessibilityAddTraits(.isModal)
    }

    private func presentMasterDataErrorIfNeeded() {
        guard model.isMasterDataMissing else { return }
        isMasterDataErrorPresented = true
    }

    /// Characteristic whose proposal editor is open.
    private var proposalCharacteristic: ElevatorAssetCharacteristic? {
        guard let id = model.proposalCharacteristicID else { return nil }
        return model.elevatorAssetCharacteristics.first { $0.name == id }
    }

    private var isReadOnly: Bool {
        model.isClosedLocally
    }

    private var isEditingDisabled: Bool {
        model.isEditingDisabled
    }
}

private extension ElevatorInspectionFeedback {
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
        case .i2NotificationsQueued: "i2.selection.success"
        }
    }

}
