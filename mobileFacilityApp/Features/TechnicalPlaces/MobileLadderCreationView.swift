import SwiftUI

struct MobileLadderCreationView: View {
private enum DisassembledTransition: Hashable, Identifiable {
        case enable
        case disable

        var id: Self { self }
        var isDisassembled: Bool { self == .enable }
        var messageKey: LocalizedStringKey {
            switch self {
            case .enable: "mobileLadder.disassembled.warning.enable"
            case .disable: "mobileLadder.disassembled.warning.disable"
            }
        }
    }

    let demo: FacilityDemoViewModel
    let itemID: UUID?
    let close: () -> Void
    @Environment(\.accessibilityReduceMotion) private var accessibilityReduceMotion
    @State private var model: MobileLadderCreationViewModel
    @State private var photoWorkspaceScope: LocalPhotoScope?
    @State private var photoWorkspaceExclusionID: String?
    @State private var editingCommentID: String?
    @State private var disassembledTransition: DisassembledTransition?
    @State private var isDraftSavedConfirmationPresented = false
    @State private var isCloseConfirmationPresented = false
    @State private var isShowingBusinessEntityEditor = false
    @State private var isBuildingPickerPresented = false
    @State private var isTradePickerPresented = false
    @State private var presentedCatalogField: MobileLadderCatalogField?
    @State private var isProposalAlertPresented = false
    @State private var proposalTargetField: MobileLadderCatalogField?
    @State private var proposalInputText = ""

    init(demo: FacilityDemoViewModel, itemID: UUID?, close: @escaping () -> Void) {
        self.demo = demo
        self.itemID = itemID
        self.close = close
        _model = State(initialValue: MobileLadderCreationViewModel(
            provider: demo.mobileLadderCreationProvider,
            offlineWorkStore: demo.offlineWorkStore,
            photoStore: demo.photoAttachmentStore,
            isDemo: demo.isDemoMode,
            item: demo.offlineWorkStore.mobileLadderItem(id: itemID)
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
                .zIndex(1)
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
        .animation(
            accessibilityReduceMotion ? nil : PhotoWorkspaceMotion.navigation,
            value: photoWorkspaceScope?.rowID
        )
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
        .animation(.easeOut(duration: 0.16), value: isShowingBusinessEntityEditor)
        .task { await model.load() }
        .alert(item: $model.feedback) { feedback in
            Alert(
                title: Text(feedback.titleKey),
                message: Text(feedback.messageKey),
                dismissButton: .default(Text("common.ok")) {
                    if feedback.closesForm { close() }
                }
            )
        }
        .alert(item: $disassembledTransition) { transition in
            Alert(
                title: Text("mobileLadder.disassembled.warning.title"),
                message: Text(transition.messageKey),
                primaryButton: .default(Text("mobileLadder.disassembled.warning.continue")) {
                    Task { _ = await model.confirmDisassembledChange(to: transition.isDisassembled) }
                },
                secondaryButton: .cancel(Text("common.cancel"))
            )
        }
        .alert(
            "notifications.detail.closeConfirmation.title",
            isPresented: $isCloseConfirmationPresented
        ) {
            Button("notifications.detail.closeConfirmation.confirm", role: .destructive) {
                Task { _ = await model.close() }
            }
            Button("common.cancel", role: .cancel) { }
        } message: {
            Text("notifications.detail.closeConfirmation.message")
        }
        .alert(
            "vorschlagPopover.title",
            isPresented: $isProposalAlertPresented
        ) {
            TextField("vorschlag.new", text: $proposalInputText)
            Button("common.cancel", role: .cancel) {
                proposalInputText = ""
            }
            Button("common.ok") {
                if let field = proposalTargetField {
                    _ = model.saveProposal(proposalInputText, for: field)
                }
                proposalInputText = ""
            }
        } message: {
            Text("vorschlag.history")
        }
    }

    /// TFM5 shares the notification header with TFM1/TFM2/TFM3 the way the
    /// legacy `CreateNewForm` view embedded the same `FormHeader` fragment.
    /// A ladder that has not been queued yet has no `QMNUM`/`EQUNR`, so those
    /// rows stay empty until `MobileLadderIdentifierFactory` assigns the local
    /// `NEU` identifiers.
    private var headerInfo: NotificationFormHeaderInfo {
        let context = model.draft.context
        return NotificationFormHeaderInfo(
            title: String(localized: "mobileLadder.title"),
            notificationID: model.draft.legacyIdentifiers?.notificationNumber ?? "",
            formCode: context?.legacyContext.template.formCode.uppercased() ?? "TFM5",
            technicalPlace: context?.legacyContext.functionalLocation ?? "",
            address: context.map(formattedAddress) ?? "",
            equipmentID: model.draft.legacyIdentifiers?.equipmentNumber ?? ""
        )
    }

    private var header: some View {
        NotificationFormHeaderBar(
            info: headerInfo,
            backTitleKey: "common.back",
            isClosedLocally: model.draft.isClosedLocally == true,
            back: close
        )
    }

    @ViewBuilder
    private var content: some View {
        switch model.state {
        case .loading:
            ProgressView("mobileLadder.loading")
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        case .unavailable:
            ContentUnavailableView {
                Label("mobileLadder.unavailable.title", systemImage: "tray")
            } description: {
                Text("mobileLadder.unavailable.message")
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        case .ready:
            formContent
        }
    }

    private var formContent: some View {
        ScrollView {
            VStack(spacing: 18) {
                if model.draft.context != nil {
                    NotificationFormHeaderCard(info: headerInfo)
                }
                addressCard
                masterDataCard
                inspectionCard
            }
            .padding(28)
            .frame(maxWidth: 1280, alignment: .leading)
            // Disable only form interactions for a closed ladder. The parent
            // ScrollView must stay enabled so technicians can review all data.
            .disabled(model.isReadOnly)
        }
        .scrollDismissesKeyboard(.interactively)
    }

    private var addressCard: some View {
        VStack(alignment: .leading, spacing: 18) {
            VStack(alignment: .leading, spacing: 4) {
                Text("mobileLadder.address.title")
                    .font(.headline)
                    .foregroundStyle(FacilityTheme.ink)
                Text("mobileLadder.address.subtitle")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }

            LazyVGrid(
                columns: Array(repeating: GridItem(.flexible(), spacing: 14), count: 3),
                spacing: 14
            ) {
                SafetyFormField("mobileLadder.address.businessEntity") {
                    Button {
                        isShowingBusinessEntityEditor = true
                    } label: {
                        HStack(spacing: 12) {
                            Text(model.selectedBusinessEntity ?? String(localized: "briefing.businessEntity.placeholder"))
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
                    "mobileLadder.address.building",
                    placeholder: "briefing.building.placeholder",
                    iconName: "building.2",
                    options: model.buildings,
                    selection: model.selectedBuilding,
                    isEnabled: model.selectedBusinessEntity != nil,
                    isPresented: $isBuildingPickerPresented,
                    onOpen: {
                        isTradePickerPresented = false
                        presentedCatalogField = nil
                    },
                    onSelect: model.selectBuilding
                )

                TechnicalPlaceContextDropdownField(
                    "mobileLadder.address.trade",
                    placeholder: "mobileLadder.address.choose",
                    iconName: "wrench.and.screwdriver",
                    options: model.trades,
                    selection: model.selectedTrade,
                    isEnabled: model.selectedBuilding != nil,
                    isPresented: $isTradePickerPresented,
                    onOpen: {
                        isBuildingPickerPresented = false
                        presentedCatalogField = nil
                    },
                    onSelect: model.selectTrade
                )
            }
        }
        .facilityCard(padding: 22)
    }

    private func formattedAddress(_ context: MobileLadderCreationContext) -> String {
        [
            context.legacyContext.street,
            [context.legacyContext.postalCode, context.legacyContext.city]
                .filter { !$0.isEmpty }
                .joined(separator: " ")
        ]
        .filter { !$0.isEmpty }
        .joined(separator: " · ")
    }

    private var masterDataCard: some View {
        @Bindable var model = model
        return VStack(alignment: .leading, spacing: 18) {
            Text("mobileLadder.masterData.title")
                .font(.headline)
                .foregroundStyle(FacilityTheme.ink)

            LazyVGrid(
                columns: [GridItem(.flexible(), spacing: 14), GridItem(.flexible(), spacing: 14)],
                spacing: 14
            ) {
                catalogDropdownField(.material, selection: $model.draft.material)
                catalogDropdownField(.constructionType, selection: $model.draft.constructionType)
                textField("mobileLadder.field.factoryNumber", text: $model.draft.factoryNumber, required: false)
                catalogDropdownField(.manufacturer, selection: $model.draft.manufacturer)
                textField(
                    "mobileLadder.field.rungCount",
                    text: Binding(
                        get: { model.draft.rungCount },
                        set: { model.setRungCount($0) }
                    ),
                    required: true,
                    number: true
                )
                catalogDropdownField(.clientCompany, selection: $model.draft.clientCompany)
                textField("mobileLadder.field.room", text: $model.draft.room, required: true)
                textField("mobileLadder.field.inventoryNumber", text: $model.draft.inventoryNumber, required: false)
                textField("mobileLadder.field.designation", text: $model.draft.designation, required: true)
            }

            Divider()

            HStack(spacing: 28) {
                DatePicker(
                    "mobileLadder.field.performedOn",
                    selection: $model.draft.performedOn,
                    displayedComponents: .date
                )
                .datePickerStyle(.compact)

                Spacer(minLength: 12)

                disassembledControls
            }
        }
        .facilityCard(padding: 22)
    }

    private var disassembledControls: some View {
        TechnicalPlaceStatusControls(
            title: "mobileLadder.field.disassembled",
            isStatusActive: model.draft.isDisassembled,
            photoCount: model.photoCount(for: MobileLadderDraftPayload.disassembledStatusRowID),
            hasComment: !(model.draft.disassembledComment ?? "").isEmpty,
            isEnabled: !model.isSaving,
            requestStatusChange: {
                disassembledTransition = model.draft.isDisassembled ? .disable : .enable
            },
            openPhotos: openDisassembledPhotos,
            editComment: { editingCommentID = MobileLadderDraftPayload.disassembledStatusRowID }
        )
    }

    private func catalogDropdownField(
        _ field: MobileLadderCatalogField,
        selection: Binding<String>
    ) -> some View {
        SafetyFormField(LocalizedStringKey(field.titleKey), required: true) {
            Button {
                isBuildingPickerPresented = false
                isTradePickerPresented = false
                presentedCatalogField = field
            } label: {
                HStack(spacing: 12) {
                    Text(selection.wrappedValue.isEmpty ? String(localized: "mobileLadder.field.choose") : selection.wrappedValue)
                        .foregroundStyle(selection.wrappedValue.isEmpty ? .secondary : FacilityTheme.ink)
                        .lineLimit(1)

                    Spacer(minLength: 0)

                    Image(systemName: "chevron.up.chevron.down")
                        .font(.caption.weight(.bold))
                        .foregroundStyle(FacilityTheme.blue)
                }
                .briefingFieldChrome(invalid: false)
            }
            .buttonStyle(.plain)
            .facilityPopover(
                isPresented: Binding(
                    get: { presentedCatalogField == field },
                    set: { if !$0 && presentedCatalogField == field { presentedCatalogField = nil } }
                ),
                arrowEdge: .top
            ) {
                catalogPicker(for: field, selection: selection)
            }
        }
    }

    private func catalogPicker(
        for field: MobileLadderCatalogField,
        selection: Binding<String>
    ) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 10) {
                Image(systemName: field.iconName)
                    .foregroundStyle(FacilityTheme.accent)
                Text(LocalizedStringKey(field.titleKey))
                    .font(.headline)
                    .foregroundStyle(FacilityTheme.ink)

                Spacer(minLength: 8)

                Button {
                    proposalTargetField = field
                    proposalInputText = ""
                    presentedCatalogField = nil
                    isProposalAlertPresented = true
                } label: {
                    Image(systemName: "plus.circle")
                        .font(.title3)
                        .foregroundStyle(FacilityTheme.blue)
                }
                .buttonStyle(.plain)
                .accessibilityLabel(Text("vorschlag.new"))
            }
            .padding(.horizontal, 18)
            .padding(.vertical, 16)

            Divider()

            ScrollView {
                LazyVStack(spacing: 0) {
                    let options = model.catalog.options(for: field)
                    ForEach(options, id: \.self) { option in
                        let isSelected = option == selection.wrappedValue

                        Button {
                            if option == "Pflege durch Admin" {
                                proposalTargetField = field
                                proposalInputText = ""
                                presentedCatalogField = nil
                                isProposalAlertPresented = true
                            } else {
                                selection.wrappedValue = option
                                presentedCatalogField = nil
                            }
                        } label: {
                            HStack(spacing: 12) {
                                Text(option)
                                    .font(.body.weight(.medium))
                                    .foregroundStyle(FacilityTheme.ink)
                                    .lineLimit(2)

                                Spacer(minLength: 12)

                                Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                                    .font(.title3)
                                    .foregroundStyle(isSelected ? FacilityTheme.accent : .secondary)
                            }
                            .padding(.horizontal, 18)
                            .frame(minHeight: 52)
                            .background(isSelected ? FacilityTheme.accentSoft : FacilityTheme.surface)
                        }
                        .buttonStyle(.plain)

                        if option != options.last {
                            Divider().padding(.leading, 18)
                        }
                    }
                }
            }
            .frame(maxHeight: 300)
        }
        .frame(width: 340)
        .background(FacilityTheme.surface)
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
    }

    private func textField(
        _ key: LocalizedStringKey,
        text: Binding<String>,
        required: Bool = false,
        number: Bool = false
    ) -> some View {
        SafetyFormField(key, required: required) {
            Group {
                if number {
                    DigitsOnlyTextField(text: text)
                } else {
                    TextField("", text: text)
                }
            }
            .foregroundStyle(FacilityTheme.ink)
            .briefingFieldChrome(invalid: false)
        }
    }

    private var inspectionCard: some View {
        @Bindable var model = model
        return VStack(spacing: 0) {
            HStack(spacing: 12) {
                Text("notifications.detail.numberColumn")
                    .frame(width: 42, alignment: .leading)
                Color.clear.frame(width: 28, height: 1)
                Text("notifications.detail.inspectionPoint")
                    .frame(maxWidth: .infinity, alignment: .leading)
                Text("mobileLadder.column.result")
                    .frame(width: 160, alignment: .leading)
                Text("mobileLadder.column.action")
                    .frame(width: 160, alignment: .leading)
                Text("notifications.detail.photo")
                    .frame(width: 52)
                Text("notifications.detail.comment")
                    .frame(width: 58)
            }
            .font(.subheadline.weight(.bold))
            .foregroundStyle(.secondary)
            .padding(.horizontal, 22)
            .padding(.vertical, 14)

            Divider()

            if model.draft.inspectionItems.isEmpty {
                ContentUnavailableView(
                    "mobileLadder.address.notSelected",
                    systemImage: "list.bullet.clipboard",
                    description: Text("mobileLadder.address.subtitle")
                )
                .frame(maxWidth: .infinity, minHeight: 150)
            } else {
                ForEach($model.draft.inspectionItems) { $item in
                    MobileLadderInspectionRow(
                        item: $item,
                        photoCount: model.photoCount(for: item.id),
                        isEditingEnabled: !model.isReadOnly && !model.draft.isDisassembled && !model.isSaving,
                        openPhotos: { openInspectionPhotos(item) },
                        editComment: { editingCommentID = item.id }
                    )
                    if item.id != model.draft.inspectionItems.last?.id {
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

    @ViewBuilder
    private var actionBar: some View {
        if model.isReadOnly {
            HStack(spacing: 14) {
                Spacer(minLength: 12)
                Button("common.back", action: close)
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
                        if await model.saveTemporarily() {
                            isDraftSavedConfirmationPresented = true
                        }
                    }
                },
                closeNotification: {
                    if demo.isDemoMode {
                        Task { _ = await model.close() }
                    } else {
                        isCloseConfirmationPresented = true
                    }
                },
                isMarkEverythingOkayEnabled: !model.draft.inspectionItems.isEmpty && !model.draft.isDisassembled && !model.isSaving,
                isSaveDraftEnabled: !model.isSaving,
                isCloseNotificationEnabled: !model.isSaving && model.isReadyToClose
            )
            .alert(
                "mobileLadder.feedback.saved.title",
                isPresented: $isDraftSavedConfirmationPresented
            ) {
                Button("common.ok") { close() }
            } message: {
                Text("mobileLadder.feedback.saved.message")
            }
        }
    }

    private func commentBinding(for itemID: String) -> Binding<String> {
        Binding(
            get: {
                if itemID == MobileLadderDraftPayload.disassembledStatusRowID {
                    return model.draft.disassembledComment ?? ""
                }
                return model.draft.inspectionItems.first { $0.id == itemID }?.comment ?? ""
            },
            set: { value in
                if itemID == MobileLadderDraftPayload.disassembledStatusRowID {
                    model.draft.disassembledComment = value
                    return
                }
                guard let index = model.draft.inspectionItems.firstIndex(where: { $0.id == itemID }) else {
                    return
                }
                model.draft.inspectionItems[index].comment = value
            }
        )
    }

    private func closePhotoWorkspace() {
        photoWorkspaceScope = nil
        photoWorkspaceExclusionID = nil
        Task {
            await demo.offlineWorkStore.load()
            model.refreshPhotos()
        }
    }

    private func openInspectionPhotos(_ item: MobileLadderInspectionItem) {
        photoWorkspaceScope = model.photoScope(for: item)
        photoWorkspaceExclusionID = item.id
    }

    private func openDisassembledPhotos() {
        photoWorkspaceScope = model.disassembledPhotoScope()
        photoWorkspaceExclusionID = MobileLadderDraftPayload.disassembledStatusRowID
    }
}

/// Keeps the visible editing buffer in lockstep with a digits-only value.
/// `keyboardType` is only a keyboard preference on iPad, so this also rejects
/// letters from a hardware keyboard and removes them immediately on paste.
private struct DigitsOnlyTextField: View {
    @Binding var text: String
    @State private var editingText: String

    init(text: Binding<String>) {
        _text = text
        _editingText = State(initialValue: Self.digits(in: text.wrappedValue))
    }

    var body: some View {
        TextField("", text: $editingText)
            .keyboardType(.numberPad)
            .textInputAutocapitalization(.never)
            .autocorrectionDisabled()
            .onChange(of: editingText) { _, value in
                applyDigits(from: value)
            }
            .onChange(of: text) { _, value in
                let digits = Self.digits(in: value)
                if editingText != digits {
                    editingText = digits
                }
            }
            .onAppear {
                applyDigits(from: text)
            }
    }

    private func applyDigits(from value: String) {
        let digits = Self.digits(in: value)
        if editingText != digits {
            editingText = digits
        }
        if text != digits {
            text = digits
        }
    }

    private static func digits(in value: String) -> String {
        String(value.filter(\.isNumber))
    }
}

private struct MobileLadderInspectionRow: View {
    @Binding var item: MobileLadderInspectionItem
    let photoCount: Int
    let isEditingEnabled: Bool
    let openPhotos: () -> Void
    let editComment: () -> Void
    @State private var isShowingInformation = false
    @State private var expandedPicker: MobileLadderInspectionCodePickerKind?

    var body: some View {
        HStack(spacing: 12) {
            Text(item.number, format: .number)
                .font(.body.weight(.semibold))
                .foregroundStyle(.secondary)
                .frame(width: 42, alignment: .leading)

            Image(systemName: "exclamationmark.triangle")
                .font(.title3.weight(.semibold))
                .foregroundStyle(FacilityTheme.red)
                .frame(width: 28, height: 52)
                .opacity(item.result == nil ? 1 : 0)
                .accessibilityHidden(item.result != nil)

            HStack(spacing: 10) {
                Button { isShowingInformation = true } label: {
                    Image(systemName: item.information.isEmpty ? "info.circle" : "info.circle.fill")
                        .font(.title2.weight(.semibold))
                        .foregroundStyle(item.information.isEmpty ? Color.secondary.opacity(0.45) : FacilityTheme.blue)
                        .frame(width: 44, height: 44)
                }
                .buttonStyle(.plain)
                .disabled(item.information.isEmpty)
                .popover(isPresented: $isShowingInformation) {
                    Text(item.information)
                        .font(.body)
                        .padding(20)
                        .frame(width: 360, alignment: .leading)
                }

                Text(item.title)
                    .font(.body)
                    .foregroundStyle(FacilityTheme.ink)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }

            MobileLadderInspectionCodePicker(
                picker: .result,
                selection: item.result.map(\.code),
                optionsHeight: 250,
                isEnabled: isEditingEnabled,
                accessibilityLabel: "mobileLadder.column.result",
                expandedPicker: $expandedPicker
            ) {
                ForEach(MobileLadderInspectionResult.allCases) { result in
                    MobileLadderInspectionCodeOption(
                        code: result.code,
                        title: String(localized: String.LocalizationValue(result.titleKey))
                    ) {
                        item.result = result
                        expandedPicker = nil
                    }
                }
            }
            .frame(width: 160)

            MobileLadderInspectionCodePicker(
                picker: .action,
                selection: item.action.map(\.code),
                optionsHeight: 150,
                isEnabled: isEditingEnabled,
                accessibilityLabel: "mobileLadder.column.action",
                expandedPicker: $expandedPicker
            ) {
                ForEach(MobileLadderInspectionAction.allCases) { action in
                    MobileLadderInspectionCodeOption(
                        code: action.code,
                        title: String(localized: String.LocalizationValue(action.titleKey))
                    ) {
                        item.action = action
                        expandedPicker = nil
                    }
                }
            }
            .frame(width: 160)

            Button(action: openPhotos) {
                ZStack(alignment: .topTrailing) {
                    Image(systemName: photoCount == 0 ? "camera" : "camera.fill")
                        .foregroundStyle(photoCount == 0 ? FacilityTheme.ink : FacilityTheme.blue)
                        .frame(width: 44, height: 44)
                        .background(.white, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                        .overlay {
                            RoundedRectangle(cornerRadius: 10, style: .continuous)
                                .stroke(.gray.opacity(0.25))
                        }
                    if photoCount > 0 {
                        Text(photoCount, format: .number)
                            .font(.caption2.bold())
                            .foregroundStyle(.white)
                            .frame(minWidth: 18, minHeight: 18)
                            .background(FacilityTheme.blue, in: Circle())
                            .offset(x: 5, y: -5)
                    }
                }
            }
            .buttonStyle(.plain)
            .disabled(!isEditingEnabled)
            .frame(width: 52)

            Button(action: editComment) {
                Image(systemName: item.comment.isEmpty ? "pencil" : "note.text")
                    .foregroundStyle(item.comment.isEmpty ? FacilityTheme.ink : FacilityTheme.blue)
                    .frame(width: 44, height: 44)
                    .background(.white, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                    .overlay {
                        RoundedRectangle(cornerRadius: 10, style: .continuous)
                            .stroke(.gray.opacity(0.25))
                    }
            }
            .buttonStyle(.plain)
            .disabled(!isEditingEnabled)
            .frame(width: 58)
        }
        .padding(.horizontal, 22)
        .padding(.vertical, 10)
        .frame(minHeight: 68)
        // Keep the active row above its neighbours while its anchored popover
        // is visible, matching the inspection selectors elsewhere in MTFM.
        .zIndex(expandedPicker == nil ? 0 : 1)
    }

}

/// The original Mobile Ladder inspection selector. It is intentionally shared
/// with other SAP-driven inspection forms so all result/action dropdowns keep
/// the same anchored-popover interaction and visual treatment.
enum MobileLadderInspectionCodePickerKind {
    case result, action
}

struct MobileLadderInspectionCodePicker<Options: View>: View {
    let picker: MobileLadderInspectionCodePickerKind
    let selection: String?
    let optionsHeight: CGFloat
    let isEnabled: Bool
    let accessibilityLabel: LocalizedStringKey
    @Binding var expandedPicker: MobileLadderInspectionCodePickerKind?
    let options: () -> Options

    init(
        picker: MobileLadderInspectionCodePickerKind,
        selection: String?,
        optionsHeight: CGFloat,
        isEnabled: Bool,
        accessibilityLabel: LocalizedStringKey,
        expandedPicker: Binding<MobileLadderInspectionCodePickerKind?>,
        @ViewBuilder options: @escaping () -> Options
    ) {
        self.picker = picker
        self.selection = selection
        self.optionsHeight = optionsHeight
        self.isEnabled = isEnabled
        self.accessibilityLabel = accessibilityLabel
        _expandedPicker = expandedPicker
        self.options = options
    }

    var body: some View {
        let isExpanded = expandedPicker == picker
        Button {
            expandedPicker = isExpanded ? nil : picker
        } label: {
            HStack(spacing: 0) {
                Text(selection ?? "")
                    .font(.body)
                    .monospacedDigit()
                    .foregroundStyle(FacilityTheme.ink)
                    .lineLimit(1)
                    .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
                    .padding(.leading, 18)

                Image(systemName: isExpanded ? "chevron.up" : "chevron.down")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(isExpanded ? .white : FacilityTheme.blue)
                    .frame(width: 44, height: 44)
                    .background(isExpanded ? FacilityTheme.blue : .clear)
                    .accessibilityHidden(true)
            }
            .background(FacilityTheme.surface)
            .overlay {
                Rectangle().stroke(isExpanded ? FacilityTheme.blue : .secondary.opacity(0.42))
            }
            .frame(width: 120, height: 44)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(!isEnabled)
        .opacity(isEnabled ? 1 : 0.45)
        .accessibilityLabel(Text(accessibilityLabel))
        .popover(isPresented: pickerPresentationBinding) {
            ScrollView {
                LazyVStack(spacing: 0) { options() }
            }
            .frame(width: 360, height: optionsHeight, alignment: .top)
            .background(FacilityTheme.surface)
            .presentationCompactAdaptation(.popover)
        }
    }

    private var pickerPresentationBinding: Binding<Bool> {
        Binding(
            get: { expandedPicker == picker },
            set: { isPresented in
                if !isPresented, expandedPicker == picker { expandedPicker = nil }
            }
        )
    }
}

struct MobileLadderInspectionCodeOption: View {
    let code: String
    let title: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 12) {
                Text(code).monospacedDigit().frame(width: 46, alignment: .leading)
                Text(verbatim: title).frame(maxWidth: .infinity, alignment: .trailing)
            }
            .font(.body)
            .foregroundStyle(FacilityTheme.ink)
            .padding(.horizontal, 20)
            .frame(maxWidth: .infinity, minHeight: 50)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .combine)
    }
}

private extension MobileLadderCreationViewModel.Feedback {
    var titleKey: LocalizedStringKey {
        switch self {
        case .validation: "mobileLadder.validation.title"
        case .saved: "mobileLadder.feedback.saved.title"
        case .queued: "mobileLadder.feedback.queued.title"
        case .proposalSaved: "vorschlagPopover.title"
        case .failed: "mobileLadder.error.title"
        }
    }

    var messageKey: LocalizedStringKey {
        switch self {
        case .validation: "mobileLadder.validation.message"
        case .saved: "mobileLadder.feedback.saved.message"
        case .queued: "mobileLadder.feedback.queued.message"
        case .proposalSaved: "vorschlag.speichert"
        case .failed: "mobileLadder.error.message"
        }
    }

    var closesForm: Bool {
        switch self {
        case .saved, .queued: true
        default: false
        }
    }
}
