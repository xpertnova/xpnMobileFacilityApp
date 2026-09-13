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

    private var header: some View {
        HStack(alignment: .top, spacing: 20) {
            VStack(alignment: .leading, spacing: 7) {
                Button(action: close) {
                    Label("common.back", systemImage: "chevron.left")
                        .font(.subheadline.weight(.semibold))
                }
                .buttonStyle(.plain)
                .foregroundStyle(FacilityTheme.blue)
                .frame(minHeight: 44, alignment: .leading)

                Text("mobileLadder.title")
                    .font(.system(size: 29, weight: .bold))
                    .foregroundStyle(FacilityTheme.ink)

                Text(demo.isDemoMode ? "mobileLadder.mode.demo" : "mobileLadder.mode.production")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }

            Spacer(minLength: 12)
        }
        .padding(.horizontal, 28)
        .padding(.vertical, 18)
        .background(FacilityTheme.surface)
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

                SafetyFormField("mobileLadder.address.building") {
                    Button {
                        isTradePickerPresented = false
                        presentedCatalogField = nil
                        isBuildingPickerPresented = true
                    } label: {
                        HStack(spacing: 12) {
                            Text(model.selectedBuilding ?? String(localized: "briefing.building.placeholder"))
                                .foregroundStyle(model.selectedBuilding == nil ? .secondary : FacilityTheme.ink)
                                .lineLimit(1)
                            Spacer(minLength: 0)
                            Image(systemName: "chevron.up.chevron.down")
                                .font(.caption.weight(.bold))
                                .foregroundStyle(model.selectedBusinessEntity == nil ? .secondary : FacilityTheme.blue)
                        }
                        .briefingFieldChrome(invalid: false)
                    }
                    .buttonStyle(.plain)
                    .facilityPopover(
                        isPresented: $isBuildingPickerPresented,
                        arrowEdge: .top
                    ) {
                        buildingPicker
                    }
                    .disabled(model.selectedBusinessEntity == nil || model.buildings.isEmpty)
                }

                SafetyFormField("mobileLadder.address.trade") {
                    Button {
                        isBuildingPickerPresented = false
                        presentedCatalogField = nil
                        isTradePickerPresented = true
                    } label: {
                        HStack(spacing: 12) {
                            Text(model.selectedTrade ?? String(localized: "mobileLadder.address.choose"))
                                .foregroundStyle(model.selectedTrade == nil ? .secondary : FacilityTheme.ink)
                                .lineLimit(1)
                            Spacer(minLength: 0)
                            Image(systemName: "chevron.up.chevron.down")
                                .font(.caption.weight(.bold))
                                .foregroundStyle(model.selectedBuilding == nil ? .secondary : FacilityTheme.blue)
                        }
                        .briefingFieldChrome(invalid: false)
                    }
                    .buttonStyle(.plain)
                    .facilityPopover(
                        isPresented: $isTradePickerPresented,
                        arrowEdge: .top
                    ) {
                        tradePicker
                    }
                    .disabled(model.selectedBuilding == nil || model.trades.isEmpty)
                }
            }

            if let context = model.draft.context {
                Divider()
                HStack(alignment: .firstTextBaseline, spacing: 30) {
                    metadataValue(
                        "notifications.detail.technicalPlace",
                        context.legacyContext.functionalLocation,
                        monospaced: true
                    )
                    metadataValue("externalCompany.address", formattedAddress(context))
                }
            }
        }
        .facilityCard(padding: 22)
    }

    private var buildingPicker: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 10) {
                Image(systemName: "building.2")
                    .foregroundStyle(FacilityTheme.accent)
                Text("briefing.building.placeholder")
                    .font(.headline)
                    .foregroundStyle(FacilityTheme.ink)
            }
            .padding(.horizontal, 18)
            .padding(.vertical, 16)

            Divider()

            ScrollView {
                LazyVStack(spacing: 0) {
                    ForEach(model.buildings, id: \.self) { building in
                        let isSelected = building == model.selectedBuilding

                        Button {
                            model.selectBuilding(building)
                            isBuildingPickerPresented = false
                        } label: {
                            HStack(spacing: 12) {
                                Text(building)
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

                        if building != model.buildings.last {
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

    private var tradePicker: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 10) {
                Image(systemName: "wrench.and.screwdriver")
                    .foregroundStyle(FacilityTheme.accent)
                Text("mobileLadder.address.trade")
                    .font(.headline)
                    .foregroundStyle(FacilityTheme.ink)
            }
            .padding(.horizontal, 18)
            .padding(.vertical, 16)

            Divider()

            ScrollView {
                LazyVStack(spacing: 0) {
                    ForEach(model.trades, id: \.self) { trade in
                        let isSelected = trade == model.selectedTrade

                        Button {
                            model.selectTrade(trade)
                            isTradePickerPresented = false
                        } label: {
                            HStack(spacing: 12) {
                                Text(trade)
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

                        if trade != model.trades.last {
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

    private func metadataValue(_ title: LocalizedStringKey, _ value: String, monospaced: Bool = false) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(title)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.secondary)
            Text(value)
                .font(monospaced ? .subheadline.monospaced() : .body)
                .foregroundStyle(FacilityTheme.ink)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
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
        HStack(spacing: 10) {
            Toggle(
                "mobileLadder.field.disassembled",
                isOn: Binding(
                    get: { model.draft.isDisassembled },
                    set: { requestedValue in
                        guard requestedValue != model.draft.isDisassembled else { return }
                        disassembledTransition = requestedValue ? .enable : .disable
                    }
                )
            )
            .fixedSize()
            .disabled(model.isSaving)

            Button(action: openDisassembledPhotos) {
                ZStack(alignment: .topTrailing) {
                    Image(systemName: model.photoCount(for: MobileLadderDraftPayload.disassembledStatusRowID) == 0 ? "camera" : "camera.fill")
                        .foregroundStyle(
                            model.draft.isDisassembled
                                ? FacilityTheme.blue
                                : Color.secondary.opacity(0.45)
                        )
                        .frame(width: 44, height: 44)
                        .background(.white, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                        .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous).stroke(.gray.opacity(0.25)))
                    let count = model.photoCount(for: MobileLadderDraftPayload.disassembledStatusRowID)
                    if count > 0 {
                        Text(count, format: .number)
                            .font(.caption2.bold())
                            .foregroundStyle(.white)
                            .frame(minWidth: 18, minHeight: 18)
                            .background(FacilityTheme.blue, in: Circle())
                            .offset(x: 5, y: -5)
                    }
                }
            }
            .buttonStyle(.plain)
            .disabled(!model.draft.isDisassembled || model.isSaving)
            .accessibilityLabel(Text("notifications.detail.photo"))
            .accessibilityValue(Text(String(format: String(localized: "notifications.detail.photo.count"), model.photoCount(for: MobileLadderDraftPayload.disassembledStatusRowID))))

            Button { editingCommentID = MobileLadderDraftPayload.disassembledStatusRowID } label: {
                Image(systemName: (model.draft.disassembledComment ?? "").isEmpty ? "pencil" : "note.text")
                    .foregroundStyle(
                        model.draft.isDisassembled
                            ? FacilityTheme.blue
                            : Color.secondary.opacity(0.45)
                    )
                    .frame(width: 44, height: 44)
                    .background(.white, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                    .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous).stroke(.gray.opacity(0.25)))
            }
            .buttonStyle(.plain)
            .disabled(!model.draft.isDisassembled || model.isSaving)
            .accessibilityLabel(Text("notifications.detail.comment"))
        }
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

    private var actionBar: some View {
        HStack(spacing: 14) {
            Spacer(minLength: 12)

            if model.isReadOnly {
                Button("common.back", action: close)
                    .buttonStyle(.bordered)
                    .tint(FacilityTheme.ink)
            } else {
                Button("mobileLadder.action.allOkay") { model.markEverythingOkay() }
                    .buttonStyle(.plain)
                    .foregroundStyle(FacilityTheme.blue)
                    .disabled(model.draft.inspectionItems.isEmpty || model.draft.isDisassembled || model.isSaving)

                Button("mobileLadder.action.temporarySave") {
                    Task {
                        if await model.saveTemporarily() {
                            isDraftSavedConfirmationPresented = true
                        }
                    }
                }
                .buttonStyle(.bordered)
                .tint(FacilityTheme.ink)
                .disabled(model.isSaving)
                .alert(
                    "mobileLadder.feedback.saved.title",
                    isPresented: $isDraftSavedConfirmationPresented
                ) {
                    Button("common.ok") { close() }
                } message: {
                    Text("mobileLadder.feedback.saved.message")
                }

                Button(demo.isDemoMode ? "mobileLadder.action.saveDemo" : "mobileLadder.action.close") {
                    if demo.isDemoMode {
                        Task { _ = await model.close() }
                    } else {
                        isCloseConfirmationPresented = true
                    }
                }
                .buttonStyle(.borderedProminent)
                .tint(FacilityTheme.accent)
                .disabled(model.isSaving || !model.isReadyToClose)
            }
        }
        .padding(.horizontal, 28)
        .padding(.vertical, 12)
        .background(.ultraThinMaterial)
        .overlay(alignment: .top) { Divider() }
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
    private enum ExpandedPicker { case result, action }

    @Binding var item: MobileLadderInspectionItem
    let photoCount: Int
    let isEditingEnabled: Bool
    let openPhotos: () -> Void
    let editComment: () -> Void
    @State private var isShowingInformation = false
    @State private var expandedPicker: ExpandedPicker?

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

            inspectionCodePicker(
                picker: .result,
                selection: item.result.map(\.code),
                optionsHeight: 250,
                isEnabled: isEditingEnabled
            ) {
                ForEach(MobileLadderInspectionResult.allCases) { result in
                    inspectionCodeOption(code: result.code, titleKey: result.titleKey) {
                        item.result = result
                        expandedPicker = nil
                    }
                }
            }
            .frame(width: 160)

            inspectionCodePicker(
                picker: .action,
                selection: item.action.map(\.code),
                optionsHeight: 150,
                isEnabled: isEditingEnabled
            ) {
                ForEach(MobileLadderInspectionAction.allCases) { action in
                    inspectionCodeOption(code: action.code, titleKey: action.titleKey) {
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

    private func inspectionCodePicker<Options: View>(
        picker: ExpandedPicker,
        selection: String?,
        optionsHeight: CGFloat,
        isEnabled: Bool,
        @ViewBuilder options: @escaping () -> Options
    ) -> some View {
        let isExpanded = expandedPicker == picker

        return Button {
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
                Rectangle()
                    .stroke(isExpanded ? FacilityTheme.blue : .secondary.opacity(0.42))
            }
            .frame(width: 120, height: 44)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(!isEnabled)
        .opacity(isEnabled ? 1 : 0.45)
        .accessibilityLabel(
            picker == .result
                ? Text("mobileLadder.column.result")
                : Text("mobileLadder.column.action")
        )
        .popover(
            isPresented: pickerPresentationBinding(for: picker),
            attachmentAnchor: .rect(.bounds)
        ) {
            ScrollView {
                LazyVStack(spacing: 0) { options() }
            }
            .frame(width: 360, height: optionsHeight, alignment: .top)
            .background(FacilityTheme.surface)
            .presentationCompactAdaptation(.popover)
        }
    }

    private func pickerPresentationBinding(for picker: ExpandedPicker) -> Binding<Bool> {
        Binding(
            get: { expandedPicker == picker },
            set: { isPresented in
                if !isPresented, expandedPicker == picker {
                    expandedPicker = nil
                }
            }
        )
    }

    private func inspectionCodeOption(
        code: String,
        titleKey: String,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            HStack(spacing: 12) {
                Text(code)
                    .monospacedDigit()
                    .frame(width: 46, alignment: .leading)
                Text(LocalizedStringKey(titleKey))
                    .frame(maxWidth: .infinity, alignment: .trailing)
            }
            .font(.body)
            .foregroundStyle(FacilityTheme.ink)
            .padding(.horizontal, 20)
            .frame(maxWidth: .infinity, minHeight: 50)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(Text(verbatim: "\(code), \(String(localized: String.LocalizationValue(titleKey)))"))
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
