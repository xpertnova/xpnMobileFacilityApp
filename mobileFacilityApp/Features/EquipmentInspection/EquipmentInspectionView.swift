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

    @Environment(\.accessibilityReduceMotion) private var accessibilityReduceMotion
    @State private var model: EquipmentInspectionViewModel
    @State private var editingCommentID: String?
    @State private var photoWorkspaceItemID: String?

    init(
        detail: SAPNotificationDetail,
        form: EquipmentInspectionForm? = nil,
        offlineWorkStore: OfflineWorkStore,
        photoAttachmentStore: any PhotoAttachmentStore,
        sapDataStore: SAPDataStore? = nil,
        elevatorAssetDataProvider: any ElevatorAssetDataProviding = UnavailableElevatorAssetDataProvider(),
        backDestination: AppDestination,
        dismiss: @escaping () -> Void
    ) {
        self.detail = detail
        self.backDestination = backDestination
        self.dismiss = dismiss
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
                            masterDataCard
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
        .task(id: detail.summary.id) {
            await model.load()
        }
        .alert(item: $model.feedback) { feedback in
            Alert(
                title: Text("notifications.detail.action.title"),
                message: Text(feedback.messageKey),
                dismissButton: .default(Text("notifications.detail.commentEditor.done")) {
                    if case .closedLocally = feedback {
                        if !model.isI2DefectSelectionPresented {
                            dismiss()
                        }
                    } else if case .i2DefectsCreated = feedback {
                        dismiss()
                    }
                }
            )
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
        .sheet(isPresented: $model.isI2DefectSelectionPresented, onDismiss: {
            dismiss()
        }) {
            ElevatorI2DefectSelectionSheet(
                items: model.deficientItems,
                selectedIDs: $model.selectedI2DefectIDs,
                confirm: {
                    Task {
                        await model.createI2Defects(for: model.selectedI2DefectIDs)
                    }
                },
                cancel: {
                    model.isI2DefectSelectionPresented = false
                    dismiss()
                }
            )
        }
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
                    capturedAt: $0.capturedAt
                )
            },
            photoData: model.photoData,
            isLoading: model.isLoading,
            isSaving: model.isSaving,
            isReadOnly: isReadOnly || (!isOutOfServiceRow && model.isOutOfService),
            maxAttachments: EquipmentInspectionViewModel.maximumPhotoCount,
            close: { photoWorkspaceItemID = nil },
            addPhoto: { data in
                Task {
                    if isOutOfServiceRow {
                        await model.addOutOfServicePhoto(jpegData: data)
                    } else if let item {
                        await model.addPhoto(jpegData: data, to: item)
                    }
                }
            },
            removePhoto: { id in
                guard let attachment = attachments.first(where: { $0.id == id }) else { return }
                Task { await model.removePhoto(attachment) }
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
            hasComment: !model.outOfServiceComment.isEmpty,
            isCommentMissing: model.isOutOfServiceCommentMissing,
            isEnabled: !isEditingDisabled && !model.isSaving,
            requestStatusChange: { model.requestOutOfServiceChange() },
            openPhotos: { photoWorkspaceItemID = model.outOfServiceRowID },
            editComment: { editingCommentID = model.outOfServiceRowID }
        )
    }

    /// Read-only class characteristics above the checklist
    /// (`HeaderFormBuilder.createHeaderForm`).
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
                if model.elevatorAssetDataState == .ready {
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
                LazyVGrid(
                    columns: [GridItem(.adaptive(minimum: 290, maximum: 520), spacing: 16)],
                    alignment: .leading,
                    spacing: 16
                ) {
                    ForEach(model.elevatorAssetCharacteristics) { characteristic in
                        elevatorAssetValueCell(for: characteristic)
                    }
                }

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

    private func elevatorAssetValueCell(for characteristic: ElevatorAssetCharacteristic) -> some View {
        let value = model.elevatorAssetDisplayValue(for: characteristic)
        return VStack(alignment: .leading, spacing: 7) {
            HStack(spacing: 5) {
                Text(characteristic.title)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(FacilityTheme.ink)
                    .fixedSize(horizontal: false, vertical: true)
                if characteristic.isRequired {
                    Image(systemName: "asterisk")
                        .font(.caption2.weight(.bold))
                        .foregroundStyle(FacilityTheme.accent)
                        .accessibilityLabel(Text("elevator.assetData.required"))
                }
            }

            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text(value)
                    .font(characteristic.isNumeric ? .body.monospacedDigit() : .body)
                    .foregroundStyle(value == "—" ? Color.secondary : FacilityTheme.ink)
                    .textSelection(.enabled)
                    .fixedSize(horizontal: false, vertical: true)
                if !characteristic.unit.isEmpty {
                    Text(characteristic.unit)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
            }
            .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
            .padding(.horizontal, 12)
            .background(Color.white.opacity(0.78), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .stroke(Color.black.opacity(0.10))
            }
        }
        .accessibilityElement(children: .combine)
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
            emptyState: InspectionFormEmptyState(
                titleKey: model.form.checklistUnavailableTitleKey,
                messageKey: "elevator.unavailable.message",
                systemImage: "exclamationmark.triangle",
                retry: { Task { await model.load() } }
            ),
            performedOn: variant.showsPerformedOnDate ? $model.performedOn : nil,
            isPerformedOnDisabled: isReadOnly,
            outOfService: outOfServiceControls,
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
            saveDraft: { Task { await model.save(closed: false) } },
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
        case .i2DefectsCreated: "elevator.i2.created.success"
        }
    }
}

private struct ElevatorI2DefectSelectionSheet: View {
    let items: [ElevatorInspectionItem]
    @Binding var selectedIDs: Set<String>
    let confirm: () -> Void
    let cancel: () -> Void

    var body: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: 16) {
                Text("elevator.i2.sheet.description")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 20)
                    .padding(.top, 16)

                List {
                    ForEach(items) { item in
                        Button {
                            if selectedIDs.contains(item.id) {
                                selectedIDs.remove(item.id)
                            } else {
                                selectedIDs.insert(item.id)
                            }
                        } label: {
                            HStack(spacing: 14) {
                                Image(systemName: selectedIDs.contains(item.id) ? "checkmark.circle.fill" : "circle")
                                    .font(.title3)
                                    .foregroundStyle(selectedIDs.contains(item.id) ? FacilityTheme.blue : .secondary)
                                    .frame(width: 44, height: 44)

                                VStack(alignment: .leading, spacing: 4) {
                                    Text(item.title)
                                        .font(.body.weight(.semibold))
                                        .foregroundStyle(FacilityTheme.ink)
                                    Text("\(item.steus) - \(item.vornr)")
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                            }
                            .frame(minHeight: 44)
                        }
                        .buttonStyle(.plain)
                    }
                }
                .listStyle(.insetGrouped)
            }
            .navigationTitle("elevator.i2.sheet.title")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("elevator.i2.sheet.skip", action: cancel)
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("elevator.i2.sheet.create", action: confirm)
                        .bold()
                }
            }
        }
    }
}
