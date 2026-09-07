import SwiftUI

struct SafetyFormPageHeader: View {
    let title: LocalizedStringKey
    let subtitle: LocalizedStringKey
    let isSidebarVisible: Bool
    let onClose: () -> Void

    var body: some View {
        HStack(alignment: .top, spacing: 20) {
            VStack(alignment: .leading, spacing: 7) {
                Button(action: onClose) {
                    Label("forms.title", systemImage: "chevron.left")
                        .font(.subheadline.weight(.semibold))
                }
                .buttonStyle(.plain)
                .foregroundStyle(FacilityTheme.blue)
                .frame(minHeight: 44, alignment: .leading)
                .padding(.leading, isSidebarVisible ? 0 : 50)

                Text(title)
                    .font(.system(size: 29, weight: .bold))
                    .foregroundStyle(FacilityTheme.ink)
                Text(subtitle)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            Spacer(minLength: 12)
        }
        .padding(.horizontal, 28)
        .padding(.vertical, 18)
        .background(FacilityTheme.surface)
        .overlay(alignment: .bottom) { Divider() }
    }
}

struct SafetyFormCard<Content: View>: View {
    let title: LocalizedStringKey?
    @ViewBuilder let content: Content

    init(_ title: LocalizedStringKey? = nil, @ViewBuilder content: () -> Content) {
        self.title = title
        self.content = content()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            if let title {
                Text(title)
                    .font(.title3.weight(.semibold))
                    .foregroundStyle(FacilityTheme.ink)
            }
            content
        }
        .padding(20)
        .background(FacilityTheme.surface, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .stroke(Color.black.opacity(0.055))
        }
        .shadow(color: Color.black.opacity(0.045), radius: 12, y: 5)
    }
}

struct SafetyFormField<Content: View>: View {
    let title: LocalizedStringKey
    let required: Bool
    @ViewBuilder let content: Content

    init(_ title: LocalizedStringKey, required: Bool = false, @ViewBuilder content: () -> Content) {
        self.title = title
        self.required = required
        self.content = content()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            HStack(spacing: 0) {
                Text(title)
                if required { Text(verbatim: " *").foregroundStyle(FacilityTheme.red) }
            }
            .font(.subheadline.weight(.semibold))
            .foregroundStyle(.secondary)
            content.frame(maxWidth: .infinity)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

struct SafetyFormFieldPair<Leading: View, Trailing: View>: View {
    @ViewBuilder let leading: Leading
    @ViewBuilder let trailing: Trailing

    init(@ViewBuilder leading: () -> Leading, @ViewBuilder trailing: () -> Trailing) {
        self.leading = leading()
        self.trailing = trailing()
    }

    var body: some View {
        ViewThatFits(in: .horizontal) {
            HStack(alignment: .top, spacing: 16) {
                leading.frame(maxWidth: .infinity, alignment: .topLeading)
                trailing.frame(maxWidth: .infinity, alignment: .topLeading)
            }
            VStack(alignment: .leading, spacing: 14) { leading; trailing }
        }
    }
}

enum StandardFormHeaderField: CaseIterable, Equatable {
    case instructorFirstName
    case instructorLastName
    case context
    case coordinator
    case partnerCompany
    case instructedPerson
    case partnerAddress
    case workDescription
    case executionStart
    case executionEnd
}

/// Kept as a visible, testable contract because this header is shared by four
/// independently evolving workflows.
let standardFormHeaderFieldOrder: [StandardFormHeaderField] = [
    .instructorFirstName,
    .instructorLastName,
    .context,
    .coordinator,
    .partnerCompany,
    .instructedPerson,
    .partnerAddress,
    .workDescription,
    .executionStart,
    .executionEnd
]

/// The common business header used by every briefing/safety workflow. Feature
/// views provide their own bindings and context selector, while field order and
/// presentation stay identical.
struct StandardFormHeader<ContextFields: View>: View {
    let partner: SAPBriefingPartner?
    let partnerInvalid: Bool
    let partnerID: AnyHashable
    let isPartnerSelectionEnabled: Bool
    let selectPartner: () -> Void
    let instructorFirstName: String
    let instructorLastName: String
    @ViewBuilder let contextFields: ContextFields
    @Binding var coordinator: String
    let coordinatorRequired: Bool
    let coordinatorInvalid: Bool
    let coordinatorID: AnyHashable?
    @Binding var dateFrom: Date
    @Binding var dateTo: Date
    let dateRangeInvalid: Bool
    let dateRangeID: AnyHashable
    @Binding var workDescription: String
    let workDescriptionInvalid: Bool
    let workDescriptionID: AnyHashable
    @Binding var instructedPerson: String
    let instructedPersonInvalid: Bool
    let instructedPersonID: AnyHashable

    private var singleLineAddress: String {
        (partner?.address ?? "")
            .split(whereSeparator: \.isNewline)
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
            .joined(separator: ", ")
    }

    init(
        partner: SAPBriefingPartner?,
        partnerInvalid: Bool,
        partnerID: AnyHashable,
        isPartnerSelectionEnabled: Bool,
        selectPartner: @escaping () -> Void,
        instructorFirstName: String,
        instructorLastName: String,
        coordinator: Binding<String>,
        coordinatorRequired: Bool,
        coordinatorInvalid: Bool,
        coordinatorID: AnyHashable?,
        dateFrom: Binding<Date>,
        dateTo: Binding<Date>,
        dateRangeInvalid: Bool,
        dateRangeID: AnyHashable,
        workDescription: Binding<String>,
        workDescriptionInvalid: Bool,
        workDescriptionID: AnyHashable,
        instructedPerson: Binding<String>,
        instructedPersonInvalid: Bool,
        instructedPersonID: AnyHashable,
        @ViewBuilder contextFields: () -> ContextFields
    ) {
        self.partner = partner
        self.partnerInvalid = partnerInvalid
        self.partnerID = partnerID
        self.isPartnerSelectionEnabled = isPartnerSelectionEnabled
        self.selectPartner = selectPartner
        self.instructorFirstName = instructorFirstName
        self.instructorLastName = instructorLastName
        self._coordinator = coordinator
        self.coordinatorRequired = coordinatorRequired
        self.coordinatorInvalid = coordinatorInvalid
        self.coordinatorID = coordinatorID
        self._dateFrom = dateFrom
        self._dateTo = dateTo
        self.dateRangeInvalid = dateRangeInvalid
        self.dateRangeID = dateRangeID
        self._workDescription = workDescription
        self.workDescriptionInvalid = workDescriptionInvalid
        self.workDescriptionID = workDescriptionID
        self._instructedPerson = instructedPerson
        self.instructedPersonInvalid = instructedPersonInvalid
        self.instructedPersonID = instructedPersonID
        self.contextFields = contextFields()
    }

    var body: some View {
        SafetyFormCard {
            SafetyFormFieldPair {
                SafetyFormField("safetyInstrucForm.firstName") {
                    Text(instructorFirstName)
                        .lineLimit(2)
                        .briefingReadOnlyValue()
                }
            } trailing: {
                SafetyFormField("safetyInstrucForm.lastName") {
                    Text(instructorLastName)
                        .lineLimit(2)
                        .briefingReadOnlyValue()
                }
            }

            contextFields

            SafetyFormField("safetyInstrucForm.coordinator", required: coordinatorRequired) {
                TextField("safetyInstrucForm.coordinator", text: $coordinator)
                    .briefingFieldChrome(invalid: coordinatorInvalid)
                    .id(coordinatorID)
            }

            SafetyFormFieldPair {
                SafetyFormField("externalCompany.name", required: true) {
                    SafetyFormPartnerField(
                        partner: partner,
                        isInvalid: partnerInvalid,
                        isEnabled: isPartnerSelectionEnabled,
                        action: selectPartner
                    )
                    .id(partnerID)
                }
            } trailing: {
                SafetyFormField("safetyInstrucForm.instructedEmployee", required: true) {
                    TextField("safetyInstrucForm.instructedEmployee", text: $instructedPerson)
                        .briefingFieldChrome(invalid: instructedPersonInvalid)
                        .id(instructedPersonID)
                }
            }

            SafetyFormField("externalCompany.address") {
                Text(singleLineAddress)
                    .font(.footnote)
                    .lineLimit(1)
                    .minimumScaleFactor(0.01)
                    .allowsTightening(true)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .briefingReadOnlyValue()
                    .accessibilityLabel("externalCompany.address")
                    .accessibilityValue(partner?.address ?? "")
            }

            SafetyFormField("safetyInstrucForm.workOrder", required: true) {
                TextField("safetyInstrucForm.workOrder", text: $workDescription)
                    .briefingFieldChrome(invalid: workDescriptionInvalid)
                    .id(workDescriptionID)
            }

            SafetyFormFieldPair {
                SafetyFormField("safetyInstrucForm.workOrder.timeSpan1", required: true) {
                    DatePicker(
                        "safetyInstrucForm.workOrder.timeSpan1",
                        selection: $dateFrom,
                        displayedComponents: [.date, .hourAndMinute]
                    )
                    .labelsHidden()
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .briefingFieldChrome(invalid: dateRangeInvalid)
                    .id(dateRangeID)
                }
            } trailing: {
                SafetyFormField("safetyInstrucForm.workOrder.timeSpan2", required: true) {
                    DatePicker(
                        "safetyInstrucForm.workOrder.timeSpan2",
                        selection: $dateTo,
                        in: dateFrom...,
                        displayedComponents: [.date, .hourAndMinute]
                    )
                    .labelsHidden()
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .briefingFieldChrome(invalid: dateRangeInvalid)
                }
            }

        }
    }
}

struct SafetyFormContextCard: View {
    let businessEntities: [SafetyFormContext]
    let buildings: [SafetyFormContext]
    let functionalLocations: [SafetyFormContext]
    let selectedBusinessEntityID: String?
    let selectedBuildingCode: String?
    let selectedContext: SafetyFormContext?
    let isInvalid: Bool
    let showBusinessEntityPicker: () -> Void
    let selectBuilding: (String) -> Void
    let selectContext: (SafetyFormContext) -> Void

    @State private var isBuildingPickerPresented = false
    @State private var isFunctionalLocationPickerPresented = false

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            SafetyFormField("briefing.businessEntity", required: true) {
                Button(action: showBusinessEntityPicker) {
                    valueHelpLabel(
                        title: selectedContext?.businessEntityTitle
                            ?? businessEntities.first(where: { $0.businessEntityID == selectedBusinessEntityID })?.businessEntityTitle,
                        placeholder: "briefing.businessEntity.placeholder",
                        enabled: !businessEntities.isEmpty,
                        symbol: "rectangle.on.rectangle"
                    )
                    .briefingFieldChrome(invalid: isInvalid)
                }
                .buttonStyle(.plain)
                .disabled(businessEntities.isEmpty)
            }

            SafetyFormField("firePermit.building", required: true) {
                Button {
                    isBuildingPickerPresented = true
                } label: {
                    valueHelpLabel(
                        title: selectedContext?.buildingTitle
                            ?? buildings.first(where: { $0.buildingCode == selectedBuildingCode })?.buildingTitle,
                        placeholder: "briefing.building.placeholder",
                        enabled: selectedBusinessEntityID != nil && !buildings.isEmpty
                    )
                    .briefingFieldChrome(invalid: isInvalid)
                }
                .buttonStyle(.plain)
                .facilityPopover(
                    isPresented: $isBuildingPickerPresented,
                    arrowEdge: .top
                ) {
                    buildingPicker
                }
                .disabled(selectedBusinessEntityID == nil || buildings.isEmpty)

                if selectedBusinessEntityID != nil && buildings.isEmpty {
                    SafetyFormNoBuildingsNotice()
                }
            }

            SafetyFormField("firePermit.functionalLocation", required: true) {
                Button {
                    isFunctionalLocationPickerPresented = true
                } label: {
                    valueHelpLabel(
                        title: selectedContext?.functionalLocationTitle,
                        placeholder: "safetyForms.functionalLocation.placeholder",
                        enabled: selectedBuildingCode != nil && !functionalLocations.isEmpty
                    )
                    .briefingFieldChrome(invalid: isInvalid)
                }
                .buttonStyle(.plain)
                .facilityPopover(
                    isPresented: $isFunctionalLocationPickerPresented,
                    arrowEdge: .top
                ) {
                    functionalLocationPicker
                }
                .disabled(selectedBuildingCode == nil || functionalLocations.isEmpty)
            }
        }
    }

    private func valueHelpLabel(
        title: String?,
        placeholder: LocalizedStringKey,
        enabled: Bool,
        symbol: String = "chevron.up.chevron.down"
    ) -> some View {
        HStack(spacing: 12) {
            if let title, !title.isEmpty {
                Text(title).foregroundStyle(.primary).lineLimit(1)
            } else {
                Text(placeholder).foregroundStyle(.secondary).lineLimit(1)
            }
            Spacer(minLength: 0)
            Image(systemName: symbol)
                .font(.caption.weight(.bold))
                .foregroundStyle(enabled ? FacilityTheme.blue : .secondary)
        }
    }

    private var buildingPicker: some View {
        SafetyFormContextOptionPicker(
            title: "briefing.building.placeholder",
            symbol: "building.2",
            contexts: buildings,
            selectedID: selectedBuildingCode,
            primaryText: \SafetyFormContext.buildingTitle,
            secondaryText: \SafetyFormContext.buildingCode
        ) { context in
            selectBuilding(context.buildingCode)
            isBuildingPickerPresented = false
        }
    }

    private var functionalLocationPicker: some View {
        SafetyFormContextOptionPicker(
            title: "safetyForms.functionalLocation.placeholder",
            symbol: "mappin.and.ellipse",
            contexts: functionalLocations,
            selectedID: selectedContext?.id,
            primaryText: \SafetyFormContext.functionalLocationTitle,
            secondaryText: \SafetyFormContext.functionalLocationID
        ) { context in
            selectContext(context)
            isFunctionalLocationPickerPresented = false
        }
    }
}

/// Makes an empty building result actionable instead of looking like a broken
/// value-help control. The form cannot infer a building when SAP returns none.
private struct SafetyFormNoBuildingsNotice: View {
    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: "building.2.crop.circle.badge.exclamationmark")
                .font(.title3.weight(.semibold))
                .foregroundStyle(FacilityTheme.orange)
                .frame(width: 38, height: 38)
                .background(FacilityTheme.orange.opacity(0.12), in: Circle())

            VStack(alignment: .leading, spacing: 3) {
                Text("safetyForms.buildings.empty.title")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(FacilityTheme.ink)
                Text("safetyForms.buildings.empty.message")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(FacilityTheme.orange.opacity(0.08), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .stroke(FacilityTheme.orange.opacity(0.25))
        }
        .accessibilityElement(children: .combine)
    }
}

private struct SafetyFormContextOptionPicker: View {
    let title: LocalizedStringKey
    let symbol: String
    let contexts: [SafetyFormContext]
    let selectedID: String?
    let primaryText: KeyPath<SafetyFormContext, String>
    let secondaryText: KeyPath<SafetyFormContext, String>
    let onSelect: (SafetyFormContext) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 10) {
                Image(systemName: symbol)
                    .foregroundStyle(FacilityTheme.accent)
                Text(title)
                    .font(.headline)
                    .foregroundStyle(FacilityTheme.ink)
            }
            .padding(.horizontal, 18)
            .padding(.vertical, 16)

            Divider()

            ScrollView {
                LazyVStack(spacing: 0) {
                    ForEach(contexts) { context in
                        let optionID = optionID(for: context)
                        let primary = context[keyPath: primaryText]
                        let secondary = context[keyPath: secondaryText]
                        let isSelected = optionID == selectedID

                        Button {
                            onSelect(context)
                        } label: {
                            HStack(spacing: 12) {
                                VStack(alignment: .leading, spacing: 3) {
                                    Text(primary)
                                        .font(.body.weight(.medium))
                                        .foregroundStyle(FacilityTheme.ink)
                                    if primary != secondary {
                                        Text(secondary)
                                            .font(.caption.monospaced())
                                            .foregroundStyle(.secondary)
                                    }
                                }

                                Spacer(minLength: 12)

                                Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                                    .font(.title3)
                                    .foregroundStyle(isSelected ? FacilityTheme.accent : .secondary)
                            }
                            .padding(.horizontal, 18)
                            .frame(minHeight: 58)
                            .background(isSelected ? FacilityTheme.accentSoft : FacilityTheme.surface)
                        }
                        .buttonStyle(.plain)

                        if context.id != contexts.last?.id {
                            Divider().padding(.leading, 18)
                        }
                    }
                }
            }
            .frame(maxHeight: 300)
        }
        .frame(width: 360)
        .background(FacilityTheme.surface)
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
    }

    private func optionID(for context: SafetyFormContext) -> String {
        if primaryText == \SafetyFormContext.buildingTitle {
            context.buildingCode
        } else {
            context.id
        }
    }
}

struct SafetyFormBusinessEntityPicker: View {
    let contexts: [SafetyFormContext]
    let selectedBusinessEntityID: String?
    let onCancel: () -> Void
    let onSelect: (String) -> Void

    @State private var pendingBusinessEntityID: String?
    @State private var searchText = ""

    init(
        contexts: [SafetyFormContext],
        selectedBusinessEntityID: String?,
        onCancel: @escaping () -> Void,
        onSelect: @escaping (String) -> Void
    ) {
        self.contexts = contexts
        self.selectedBusinessEntityID = selectedBusinessEntityID
        self.onCancel = onCancel
        self.onSelect = onSelect
        _pendingBusinessEntityID = State(initialValue: selectedBusinessEntityID)
    }

    var body: some View {
        BriefingPartnerSelectionFrame(
            title: "briefing.businessEntity.dialog.title",
            confirmationTitle: "safetyInstrucForm.addPartnerCompany.dialog.title.add",
            isConfirmationDisabled: pendingBusinessEntityID == nil,
            onCancel: onCancel,
            onConfirm: confirmSelection
        ) {
            VStack(alignment: .leading, spacing: 16) {
                searchField
                entityTable
            }
            .padding(.horizontal, 40)
            .padding(.vertical, 24)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        }
    }

    private var searchField: some View {
        HStack(spacing: 10) {
            Image(systemName: "magnifyingglass")
                .foregroundStyle(.secondary)
            TextField("briefing.businessEntity.search", text: $searchText)
                .textFieldStyle(.plain)
                .autocorrectionDisabled()
        }
        .padding(.horizontal, 14)
        .frame(maxWidth: .infinity, minHeight: 48)
        .background(FacilityTheme.canvas, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .stroke(Color.black.opacity(0.10))
        }
    }

    private var entityTable: some View {
        VStack(spacing: 0) {
            HStack(spacing: 16) {
                Text("briefing.businessEntity.column")
                    .frame(maxWidth: .infinity, alignment: .leading)
                Text("briefing.buildings.column")
                    .frame(width: 150, alignment: .leading)
            }
            .font(.subheadline.weight(.bold))
            .foregroundStyle(.secondary)
            .padding(.horizontal, 18)
            .frame(minHeight: 48)
            .background(FacilityTheme.canvas)

            Divider()

            if filteredEntities.isEmpty {
                ContentUnavailableView(
                    "briefing.businessEntity.empty.title",
                    systemImage: "building.2",
                    description: Text("briefing.businessEntity.empty.message")
                )
                .frame(maxWidth: .infinity, minHeight: 260)
            } else {
                ScrollView {
                    LazyVStack(spacing: 0) {
                        ForEach(filteredEntities) { entity in
                            Button {
                                pendingBusinessEntityID = entity.businessEntityID
                            } label: {
                                HStack(spacing: 16) {
                                    VStack(alignment: .leading, spacing: 3) {
                                        Text(entity.businessEntityTitle)
                                            .font(.body.weight(.medium))
                                            .foregroundStyle(FacilityTheme.ink)
                                        if entity.businessEntityTitle != entity.businessEntityID {
                                            Text(entity.businessEntityID)
                                                .font(.caption.monospaced())
                                                .foregroundStyle(.secondary)
                                        }
                                    }
                                    .frame(maxWidth: .infinity, alignment: .leading)

                                    Text("\(buildingCount(for: entity.businessEntityID))")
                                        .font(.body.monospacedDigit())
                                        .foregroundStyle(.secondary)
                                        .frame(width: 150, alignment: .leading)

                                    Image(systemName: pendingBusinessEntityID == entity.businessEntityID ? "checkmark.circle.fill" : "circle")
                                        .font(.title3)
                                        .foregroundStyle(pendingBusinessEntityID == entity.businessEntityID ? FacilityTheme.accent : .secondary)
                                        .frame(width: 32)
                                }
                                .padding(.horizontal, 18)
                                .frame(minHeight: 62)
                                .background(
                                    pendingBusinessEntityID == entity.businessEntityID
                                        ? FacilityTheme.accent.opacity(0.09)
                                        : FacilityTheme.surface
                                )
                            }
                            .buttonStyle(.plain)

                            Divider().padding(.leading, 18)
                        }
                    }
                }
            }
        }
        .background(FacilityTheme.surface, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .stroke(Color.black.opacity(0.10))
        }
    }

    private var businessEntities: [SafetyFormContext] {
        Dictionary(grouping: contexts, by: \SafetyFormContext.businessEntityID)
            .values.compactMap(\.first)
            .sorted { $0.businessEntityTitle < $1.businessEntityTitle }
    }

    private var filteredEntities: [SafetyFormContext] {
        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else { return businessEntities }
        return businessEntities.filter {
            $0.businessEntityTitle.localizedCaseInsensitiveContains(query)
                || $0.businessEntityID.localizedCaseInsensitiveContains(query)
        }
    }

    private func buildingCount(for businessEntityID: String) -> Int {
        Set(
            contexts
                .filter { $0.businessEntityID == businessEntityID }
                .map(\.buildingCode)
        ).count
    }

    private func confirmSelection() {
        guard let pendingBusinessEntityID else { return }
        onSelect(pendingBusinessEntityID)
    }
}

struct SafetyFormPartnerField: View {
    let partner: SAPBriefingPartner?
    let isInvalid: Bool
    let isEnabled: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 12) {
                Text(partner?.selectionLabel ?? String(localized: "electricalSafety.partner.select"))
                    .foregroundStyle(partner == nil ? .secondary : .primary)
                    .lineLimit(1)
                Spacer(minLength: 0)
                Image(systemName: "rectangle.on.rectangle")
                    .foregroundStyle(isEnabled ? FacilityTheme.blue : .secondary)
            }
            .briefingFieldChrome(invalid: isInvalid)
        }
        .buttonStyle(.plain)
        .disabled(!isEnabled)
    }
}

struct SafetyFormPartnerPicker: View {
    let partners: [SAPBriefingPartner]
    let onCancel: () -> Void
    let onSelect: (SAPBriefingPartner) -> Void
    @State private var selectedPartnerID: String?

    var body: some View {
        BriefingPartnerSelectionFrame(
            isConfirmationDisabled: selectedPartnerID == nil,
            onCancel: onCancel,
            onConfirm: confirm
        ) {
            BriefingPartnerSelectionTable(
                partners: partners.map {
                    BriefingPartnerSelection(
                        id: $0.id,
                        client: $0.client,
                        function: $0.function,
                        name: $0.name,
                        searchTerm1: $0.searchTerm1,
                        searchTerm2: $0.searchTerm2
                    )
                },
                selectedPartnerID: $selectedPartnerID
            )
            .padding(.horizontal, 40)
            .padding(.vertical, 22)
        }
    }

    private func confirm() {
        guard let partner = partners.first(where: { $0.id == selectedPartnerID }) else { return }
        onSelect(partner)
    }
}

struct SafetyFormTextEditor: View {
    @Binding var text: String
    var minimumHeight: CGFloat = 96
    var invalid = false

    var body: some View {
        TextEditor(text: $text)
            .scrollContentBackground(.hidden)
            .padding(10)
            .frame(minHeight: minimumHeight)
            .background(Color(uiColor: .systemBackground))
            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .stroke(invalid ? FacilityTheme.red : Color.black.opacity(0.11), lineWidth: invalid ? 2 : 1)
            }
    }
}

struct SafetyFormActionBar: View {
    let canSaveDraft: Bool
    var canComplete = true
    let isBusy: Bool
    let saveDraft: (() -> Void)?
    let complete: () -> Void

    var body: some View {
        HStack(spacing: 14) {
            Spacer(minLength: 12)
            if let saveDraft {
                Button("app.button.tempSave", action: saveDraft)
                    .buttonStyle(.bordered)
                    .disabled(!canSaveDraft || isBusy)
            }
            Button("app.btn.instrucClose", action: complete)
                .buttonStyle(.borderedProminent)
                .tint(FacilityTheme.accent)
                .disabled(!canComplete || isBusy)
        }
        .padding(.horizontal, 28)
        .padding(.vertical, 12)
        .background(.ultraThinMaterial)
        .overlay(alignment: .top) { Divider() }
    }
}
