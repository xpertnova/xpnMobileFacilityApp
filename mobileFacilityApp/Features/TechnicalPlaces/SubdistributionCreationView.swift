import SwiftUI

struct SubdistributionCreationView: View {
    private enum OutOfOperationTransition: Identifiable {
        case enable, disable
        var id: String { self == .enable ? "enable" : "disable" }
        var value: Bool { self == .enable }
    }

    let demo: FacilityDemoViewModel
    let itemID: UUID?
    let close: () -> Void
    @Environment(\.accessibilityReduceMotion) private var accessibilityReduceMotion
    @State private var model: SubdistributionCreationViewModel
    @State private var photoWorkspaceScope: LocalPhotoScope?
    @State private var photoWorkspaceExclusionID: String?
    @State private var editingCommentID: String?
    @State private var outOfOperationTransition: OutOfOperationTransition?
    @State private var isTemporarySaveConfirmationPresented = false
    @State private var isCloseConfirmationPresented = false
    @State private var isDefectResolutionPresented = false
    @State private var isShowingBusinessEntityEditor = false
    @State private var isBuildingPickerPresented = false
    @State private var isParentPickerPresented = false

    init(demo: FacilityDemoViewModel, itemID: UUID?, close: @escaping () -> Void) {
        self.demo = demo
        self.itemID = itemID
        self.close = close
        _model = State(initialValue: SubdistributionCreationViewModel(
            provider: demo.subdistributionCreationProvider,
            offlineWorkStore: demo.offlineWorkStore,
            photoStore: demo.photoAttachmentStore,
            isDemo: demo.isDemoMode,
            item: demo.offlineWorkStore.subdistributionItem(id: itemID)
        ))
    }

    var body: some View {
        ZStack {
            if let photoWorkspaceScope, let photoWorkspaceExclusionID {
                LocalPhotoWorkspace(
                    scope: photoWorkspaceScope,
                    offlineWorkStore: demo.offlineWorkStore,
                    photoStore: demo.photoAttachmentStore,
                    isReadOnly: model.isReadOnly,
                    maxAttachments: model.remainingPhotoCapacity(excluding: photoWorkspaceExclusionID),
                    close: closePhotoWorkspace
                )
                .transition(PhotoWorkspaceMotion.destination)
            } else {
                VStack(spacing: 0) {
                    header
                    content
                }
                .background(FacilityTheme.canvas.ignoresSafeArea())
                .safeAreaInset(edge: .bottom) {
                    if model.state == .ready { actionBar }
                }
                .transition(PhotoWorkspaceMotion.source)
            }
        }
        .overlay {
            ZStack {
                LegacyBriefingPartnerEditorOverlay(isPresented: isShowingBusinessEntityEditor) {
                    BriefingBusinessEntitySelectionEditor(
                        entities: model.businessEntityItems,
                        selectedBusinessEntityID: model.selectedBusinessEntity,
                        onCancel: { isShowingBusinessEntityEditor = false },
                        onSelect: { selectedID in
                            model.selectBusinessEntity(selectedID)
                            isShowingBusinessEntityEditor = false
                        }
                    )
                }

                if let editingCommentID {
                    FacilityCommentEditorOverlay(
                        comment: commentBinding(for: editingCommentID),
                        dismiss: { self.editingCommentID = nil }
                    )
                }
            }
        }
        .animation(accessibilityReduceMotion ? nil : PhotoWorkspaceMotion.navigation, value: photoWorkspaceScope?.rowID)
        .task { await model.load() }
        .alert(item: $outOfOperationTransition) { transition in
            Alert(
                title: Text("subdistribution.outOfOperation.warning.title"),
                message: Text("subdistribution.outOfOperation.warning.message"),
                primaryButton: .destructive(Text("subdistribution.outOfOperation.warning.continue")) {
                    Task { _ = await model.confirmOutOfOperationChange(to: transition.value) }
                },
                secondaryButton: .cancel(Text("common.cancel"))
            )
        }
        .alert("subdistribution.validation.title", isPresented: Binding(
            get: { if case .some(.validation) = model.feedback { return true }; return false },
            set: { if !$0 { model.feedback = nil } }
        )) {
            Button("common.ok", role: .cancel) { model.feedback = nil }
        } message: {
            Text("subdistribution.validation.message")
        }
        .alert("subdistribution.save.failed", isPresented: Binding(
            get: { if case .some(.failed) = model.feedback { return true }; return false },
            set: { if !$0 { model.feedback = nil } }
        )) {
            Button("common.ok", role: .cancel) { model.feedback = nil }
        } message: {
            if case let .failed(message) = model.feedback { Text(message) }
        }
        .alert("subdistribution.queued.title", isPresented: Binding(
            get: { if case .some(.queued) = model.feedback { return true }; return false },
            set: { if !$0 { model.feedback = nil } }
        )) {
            Button("common.ok") { close() }
        } message: {
            Text(demo.isDemoMode ? "subdistribution.queued.demo.message" : "subdistribution.queued.message")
        }
        .alert("subdistribution.save.title", isPresented: $isTemporarySaveConfirmationPresented) {
            Button("common.ok", action: close)
        } message: {
            Text("subdistribution.save.message")
        }
        .facilityConfirmationDialog(
            isPresented: $isCloseConfirmationPresented,
            titleKey: "notifications.detail.closeConfirmation.title",
            messageKey: "notifications.detail.closeConfirmation.message",
            confirmTitleKey: "notifications.detail.closeConfirmation.confirm"
        ) {
            continueClosingNotification()
        }
        // Second step of the same close flow, so it keeps the same framed
        // dialog rather than dropping back to a system alert.
        .facilityConfirmationDialog(
            isPresented: $isDefectResolutionPresented,
            titleKey: "subdistribution.defect.title",
            messageKey: "subdistribution.defect.message",
            actions: [
                FacilityDialogAction(titleKey: "subdistribution.defect.leaveOpen") {
                    model.selectDefectCloseAction(.leaveOpen)
                    Task { _ = await model.close() }
                },
                FacilityDialogAction(
                    titleKey: "subdistribution.defect.close",
                    emphasis: .primary
                ) {
                    model.selectDefectCloseAction(.close)
                    Task { _ = await model.close() }
                }
            ]
        )
    }

    private var header: some View {
        HStack(alignment: .top, spacing: 20) {
            VStack(alignment: .leading, spacing: 7) {
                Button(action: close) {
                    Label("common.back", systemImage: "chevron.left")
                        .font(.subheadline.weight(.semibold))
                }
                .buttonStyle(.plain).foregroundStyle(FacilityTheme.blue)
                .frame(minHeight: 44, alignment: .leading)
                Text("subdistribution.title")
                    .facilityPageTitleFont().foregroundStyle(FacilityTheme.ink)
            }
            Spacer(minLength: 12)
            if model.draft.isOutOfOperation {
                Label("subdistribution.outOfOperation", systemImage: "bolt.slash.fill")
                    .font(.subheadline.weight(.bold)).foregroundStyle(FacilityTheme.red)
                    .padding(.horizontal, 12).frame(minHeight: 44)
                    .background(FacilityTheme.red.opacity(0.1), in: Capsule())
            }
        }
        .facilityPageHorizontalPadding().padding(.vertical, 18).background(FacilityTheme.surface)
    }

    @ViewBuilder private var content: some View {
        switch model.state {
        case .loading:
            ProgressView("subdistribution.loading").frame(maxWidth: .infinity, maxHeight: .infinity)
        case .unavailable:
            ContentUnavailableView {
                Label("subdistribution.unavailable.title", systemImage: "arrow.triangle.2.circlepath")
            } description: {
                Text("subdistribution.unavailable.message")
            } actions: {
                Button("common.retry") { Task { await model.load() } }
                    .buttonStyle(.borderedProminent)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        case .ready:
            ScrollView {
                VStack(spacing: 18) { contextCard; masterDataCard; inspectionCard }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .facilityPageContent()
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .disabled(model.isReadOnly)
            }
            .scrollDismissesKeyboard(.interactively)
        }
    }

    private var contextCard: some View {
        @Bindable var model = model
        return VStack(alignment: .leading, spacing: 18) {
            Text("subdistribution.context.title").font(.headline).foregroundStyle(FacilityTheme.ink)
            Text("subdistribution.context.subtitle").font(.subheadline).foregroundStyle(.secondary)
            FacilityColumnsLayout(columnCounts: [3, 2, 1], minimumColumnWidth: 220, spacing: 14) {
                SafetyFormField("subdistribution.context.we", required: true) {
                    Button { isShowingBusinessEntityEditor = true } label: {
                        HStack(spacing: 12) {
                            Text(model.selectedBusinessEntity ?? String(localized: "subdistribution.context.choose"))
                                .foregroundStyle(model.selectedBusinessEntity == nil ? .secondary : FacilityTheme.ink)
                                .lineLimit(1)
                            Spacer(minLength: 0)
                            Image(systemName: "square.on.square")
                                .font(.caption.weight(.bold))
                                .foregroundStyle(model.businessEntities.isEmpty ? .secondary : FacilityTheme.blue)
                        }
                        .briefingFieldChrome(invalid: false)
                    }
                    .buttonStyle(.plain)
                    .disabled(model.businessEntities.isEmpty)
                }

                TechnicalPlaceContextDropdownField(
                    "subdistribution.context.ge",
                    placeholder: "subdistribution.context.choose",
                    iconName: "building.2",
                    options: model.buildings,
                    selection: model.selectedBuilding,
                    isRequired: true,
                    isEnabled: model.selectedBusinessEntity != nil,
                    isPresented: $isBuildingPickerPresented,
                    onOpen: { isParentPickerPresented = false },
                    onSelect: model.selectBuilding
                )

                TechnicalPlaceContextDropdownField(
                    "subdistribution.context.parent",
                    placeholder: "subdistribution.context.choose",
                    iconName: "point.3.connected.trianglepath.dotted",
                    options: model.parentLocations,
                    selection: model.selectedParentLocation,
                    isRequired: true,
                    isEnabled: model.selectedBuilding != nil,
                    isPresented: $isParentPickerPresented,
                    onOpen: { isBuildingPickerPresented = false },
                    onSelect: model.selectParentLocation
                )
            }
            if let context = model.draft.context {
                VStack(spacing: 18) {
                    Divider()
                    HStack(alignment: .top, spacing: 24) {
                        contextValue("notifications.detail.technicalPlace", context.legacyContext.functionalLocation, mono: true)
                        contextValue("externalCompany.address", address(for: context))
                    }
                }
                .id(context.legacyContext.functionalLocation)
                .transition(
                    accessibilityReduceMotion
                        ? .opacity
                        : .opacity.combined(with: .move(edge: .top))
                )
            }
        }
        .animation(
            accessibilityReduceMotion ? nil : .easeInOut(duration: 0.28),
            value: model.draft.context?.legacyContext.functionalLocation
        )
        .frame(maxWidth: .infinity, alignment: .leading)
        .facilityCard(padding: 22)
    }

    private func contextValue(_ key: LocalizedStringKey, _ value: String, mono: Bool = false) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(key).font(.subheadline.weight(.semibold)).foregroundStyle(.secondary)
            Text(verbatim: value).font(mono ? .subheadline.monospaced() : .body).foregroundStyle(FacilityTheme.ink)
        }.frame(maxWidth: .infinity, alignment: .leading)
    }

    private func address(for context: SubdistributionCreationContext) -> String {
        [context.legacyContext.street, [context.legacyContext.postalCode, context.legacyContext.city].filter { !$0.isEmpty }.joined(separator: " ")]
            .filter { !$0.isEmpty }.joined(separator: " · ")
    }

    private var masterDataCard: some View {
        @Bindable var model = model
        let areMasterDataFieldsDisabled = !model.isContextSelected || model.isSaving
        return VStack(alignment: .leading, spacing: 18) {
            Text("subdistribution.masterData.title").font(.headline).foregroundStyle(FacilityTheme.ink)
            LazyVGrid(columns: [GridItem(.flexible(), spacing: 14), GridItem(.flexible(), spacing: 14)], spacing: 14) {
                ForEach(model.masterDataTemplate?.characteristics ?? []) { characteristic in
                    characteristicField(characteristic, isDisabled: areMasterDataFieldsDisabled)
                }
            }
            .disabled(areMasterDataFieldsDisabled)
        }
        .facilityCard(padding: 22)
    }

    private var outOfOperationControls: InspectionOutOfServiceControls {
        let canChangeStatus = model.isContextSelected && !model.isSaving
        let isOutOfOperation = model.draft.isOutOfOperation
        let statusPhotoCount = model.photoCount(for: SubdistributionDraftPayload.statusRowID)

        return InspectionOutOfServiceControls(
            titleKey: "subdistribution.outOfOperation",
            isActive: isOutOfOperation,
            photoCount: statusPhotoCount,
            hasComment: !(model.draft.outOfOperationComment ?? "").isEmpty,
            isCommentMissing: isOutOfOperation
                && !InspectionFormRules.outOfServiceIssues(
                    comment: model.draft.outOfOperationComment
                ).isEmpty,
            isEnabled: canChangeStatus,
            requestStatusChange: {
                outOfOperationTransition = isOutOfOperation ? .disable : .enable
            },
            openPhotos: openOutOfOperationPhotos,
            editComment: { editingCommentID = SubdistributionDraftPayload.statusRowID }
        )
    }

    private func characteristicField(
        _ characteristic: SubdistributionCharacteristic,
        isDisabled: Bool
    ) -> some View {
        let value = Binding<String>(
            get: { model.draft.characteristicValues[characteristic.name, default: ""] },
            set: { model.setCharacteristicValue($0, for: characteristic) }
        )
        return VStack(alignment: .leading, spacing: 7) {
            HStack(spacing: 3) {
                Text(verbatim: characteristic.title.isEmpty ? characteristic.name : characteristic.title)
                    .font(.subheadline.weight(.semibold)).foregroundStyle(FacilityTheme.ink)
                if characteristic.required { Text("*").foregroundStyle(FacilityTheme.red).font(.subheadline.weight(.bold)) }
            }
            HStack(spacing: 8) {
                if characteristic.kind == .choice {
                    Picker("", selection: value) {
                        Text("subdistribution.context.choose").tag("")
                        ForEach(characteristic.values) { option in
                            Text(verbatim: option.title).tag(option.value)
                        }
                    }
                    .labelsHidden().pickerStyle(.menu).frame(maxWidth: .infinity, alignment: .leading)
                } else {
                    TextField("", text: value)
                        .keyboardType(characteristic.kind == .numeric ? .numberPad : .default)
                        .textInputAutocapitalization(.words)
                }
                if !characteristic.unit.isEmpty { Text(verbatim: characteristic.unit).font(.subheadline.weight(.semibold)).foregroundStyle(.secondary) }
            }
            .briefingFieldChrome(invalid: false, isDisabled: isDisabled)
        }
    }

    /// TFM7 FI-Schutzschalter. The shared checklist configured by its form
    /// code: SAP code dropdowns for result and action, no material column.
    private var variant: InspectionFormVariant {
        InspectionFormVariant.forFormCode("TFM7")
    }

    private var inspectionCard: some View {
        let isEditable = !model.isReadOnly && !model.draft.isOutOfOperation && !model.isSaving
        return InspectionFormTable(
            variant: variant,
            items: model.draft.inspectionItems.map(\.inspectionFormItem),
            state: { item in
                guard let source = model.draft.inspectionItems.first(where: { $0.id == item.id }) else {
                    return InspectionFormItemState()
                }
                var state = source.inspectionFormState
                state.photoCount = model.photoCount(for: item.id)
                state.isFlagged = model.isInspectionItemIncomplete(source)
                return state
            },
            isEditable: isEditable,
            emptyState: InspectionFormEmptyState(
                titleKey: "subdistribution.context.notSelected",
                messageKey: "subdistribution.context.subtitle"
            ),
            performedOn: $model.draft.performedOn,
            isPerformedOnDisabled: !model.isContextSelected || model.isSaving,
            outOfService: outOfOperationControls,
            actions: InspectionFormActions(
                selectResult: { item, option in
                    guard isEditable,
                          let index = model.draft.inspectionItems.firstIndex(where: { $0.id == item.id })
                    else { return }
                    model.draft.inspectionItems[index].result = option.code
                    // `BaseFormController.onBefundChange` clears an action the
                    // new result no longer permits.
                    if option.code == "1" {
                        model.draft.inspectionItems[index].action = nil
                    }
                    model.draft.defectCloseAction = nil
                },
                selectAction: { item, option in
                    guard isEditable,
                          let index = model.draft.inspectionItems.firstIndex(where: { $0.id == item.id })
                    else { return }
                    model.draft.inspectionItems[index].action = option.code
                },
                openPhotos: { item in
                    guard let source = model.draft.inspectionItems.first(where: { $0.id == item.id })
                    else { return }
                    openInspectionPhotos(source)
                },
                editComment: { editingCommentID = $0.id }
            )
        )
    }

    @ViewBuilder
    private var actionBar: some View {
        if model.isReadOnly {
            HStack(spacing: 14) {
                Spacer(minLength: 12)
                Button("common.back", action: close).buttonStyle(.bordered).tint(FacilityTheme.ink)
            }
            .facilityPageHorizontalPadding()
            .padding(.vertical, 12)
            .background(.ultraThinMaterial)
            .overlay(alignment: .top) { Divider() }
        } else {
            FacilityInspectionActionBar(
                markEverythingOkay: { model.markEverythingOkay() },
                saveDraft: {
                    Task {
                        if await model.saveTemporarily() {
                            isTemporarySaveConfirmationPresented = true
                        }
                    }
                },
                closeNotification: requestNotificationClose,
                isMarkEverythingOkayEnabled: !model.draft.inspectionItems.isEmpty && !model.draft.isOutOfOperation && !model.isSaving,
                isSaveDraftEnabled: !model.isSaving,
                isCloseNotificationEnabled: !model.isSaving && model.isReadyForCloseAction
            )
        }
    }

    private func commentBinding(for itemID: String) -> Binding<String> {
        Binding(
            get: {
                if itemID == SubdistributionDraftPayload.statusRowID {
                    return model.draft.outOfOperationComment ?? ""
                }
                return model.draft.inspectionItems.first { $0.id == itemID }?.comment ?? ""
            },
            set: { value in
                if itemID == SubdistributionDraftPayload.statusRowID {
                    model.draft.outOfOperationComment = value
                    return
                }
                guard let index = model.draft.inspectionItems.firstIndex(where: { $0.id == itemID }) else { return }
                model.draft.inspectionItems[index].comment = value
            }
        )
    }

    private func closePhotoWorkspace() {
        photoWorkspaceScope = nil; photoWorkspaceExclusionID = nil
        Task { await demo.offlineWorkStore.load(); model.refreshPhotos() }
    }

    private func openInspectionPhotos(_ item: SubdistributionInspectionItem) {
        photoWorkspaceScope = model.photoScope(for: item); photoWorkspaceExclusionID = item.id
    }

    private func openOutOfOperationPhotos() {
        photoWorkspaceScope = model.outOfOperationPhotoScope()
        photoWorkspaceExclusionID = SubdistributionDraftPayload.statusRowID
    }

    private func requestNotificationClose() {
        if demo.isDemoMode {
            continueClosingNotification()
        } else {
            isCloseConfirmationPresented = true
        }
    }

    private func continueClosingNotification() {
        if model.hasDefect && !model.draft.isOutOfOperation {
            isDefectResolutionPresented = true
        } else {
            Task { _ = await model.close() }
        }
    }
}

