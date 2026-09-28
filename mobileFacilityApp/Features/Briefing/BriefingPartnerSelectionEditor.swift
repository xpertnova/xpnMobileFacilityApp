import SwiftUI
import UIKit

/// The partner-company value-help frame matches the established briefing form
/// interaction. Its data and mutations remain feature-local until the SAP
/// partner-master-data contract is available.
struct BriefingPartnerSelectionEditor: View {
    let viewModel: BriefingWorkflowViewModel
    let onDismiss: () -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @Environment(\.briefingEditorKeyboardVisible) private var keyboardVisible
    @Namespace private var panelNamespace
    @State private var session = BriefingPartnerPickerSession()
    @State private var selectedPartnerID: String?
    @State private var isAddingPartner = false
    @State private var partnerDraft = BriefingTemporaryPartner(id: "NEU" + String(UUID().uuidString.replacingOccurrences(of: "-", with: "").prefix(6)), company: "", title: "", contactName: "", email: "", telephone: "", street: "", houseNumber: "", postalCode: "", city: "", country: "")
    @State private var hasAttemptedPartnerAdd = false
    @State private var presentedPartnerDropdown: PartnerDropdown?
    @FocusState private var focusedPartnerField: ValidationIssue?

    init(
        viewModel: BriefingWorkflowViewModel,
        onDismiss: @escaping () -> Void
    ) {
        self.viewModel = viewModel
        self.onDismiss = onDismiss
        _selectedPartnerID = State(initialValue: viewModel.selectedPartnerID.isEmpty ? nil : viewModel.selectedPartnerID)
    }

    var body: some View {
        BriefingPartnerSelectionFrame(
            isConfirmationDisabled: isAddingPartner || selectedPartnerID == nil,
            onCancel: onDismiss,
            onConfirm: selectPartner
        ) {
            VStack(spacing: 16) {
                if !keyboardVisible {
                    panelNavigation
                }
                ZStack {
                    if isAddingPartner {
                        ScrollViewReader { proxy in
                            ScrollView(.vertical) {
                                addPartnerForm
                            }
                            .scrollDismissesKeyboard(.interactively)
                            .onChange(of: focusedPartnerField) { _, _ in
                                scrollFocusedField(in: proxy)
                            }
                            .onChange(of: keyboardVisible) { _, visible in
                                if visible { scrollFocusedField(in: proxy) }
                            }
                        }
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .transition(partnerPanelTransition)
                    } else {
                        partnerList
                            .transition(partnerPanelTransition)
                    }
                }
            }
            .padding(.horizontal, keyboardVisible ? 12 : 24)
            .padding(.vertical, keyboardVisible ? 8 : 20)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .animation(partnerPanelAnimation, value: isAddingPartner)
        }
    }

    private var panelNavigation: some View {
        HStack(spacing: 6) {
            panelTab("briefing.partnerPicker.showList", icon: "building.2", adding: false)
            panelTab("briefing.partnerPicker.add", icon: "plus.circle", adding: true)
        }
        .padding(5)
        .background(FacilityTheme.ink.opacity(0.045), in: RoundedRectangle(cornerRadius: 17))
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func panelTab(_ title: LocalizedStringKey, icon: String, adding: Bool) -> some View {
        Button {
            guard isAddingPartner != adding else { return }
            toggleAddPartner()
        } label: {
            Label(title, systemImage: icon)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(isAddingPartner == adding ? FacilityTheme.accent : FacilityTheme.ink.opacity(0.65))
                .padding(.horizontal, 18)
                .frame(minHeight: 44)
                .background {
                    if isAddingPartner == adding {
                        RoundedRectangle(cornerRadius: 13)
                            .fill(FacilityTheme.surface)
                            .shadow(color: FacilityTheme.ink.opacity(0.08), radius: 5, y: 2)
                            .matchedGeometryEffect(id: "partnerPanel", in: panelNamespace)
                    }
                }
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(isAddingPartner == adding ? .isSelected : [])
    }

    private var partnerList: some View {
        VStack(alignment: .leading, spacing: 14) {
            if session.recentlyAddedPartnerID != nil {
                Label("briefing.partnerPicker.addedNotice", systemImage: "checkmark.circle.fill")
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(FacilityTheme.accent)
                    .padding(14)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(FacilityTheme.accentSoft, in: RoundedRectangle(cornerRadius: 14))
                    .transition(.opacity)
            }
            partnerTable
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    private var partnerPanelAnimation: Animation? {
        reduceMotion ? nil : .snappy(duration: 0.32, extraBounce: 0)
    }

    private var partnerPanelTransition: AnyTransition {
        reduceMotion ? .opacity : .opacity.combined(with: .offset(y: 8))
    }

    private func selectPartner() {
        if let selectedPartnerID {
            viewModel.selectPartner(selectedPartnerID)
        }
        onDismiss()
    }

    private var addPartnerForm: some View {
        VStack(alignment: .leading, spacing: 18) {
            VStack(alignment: .leading, spacing: 6) {
                Text("dlgAddPartner.form.title.add")
                    .font(.title2.weight(.bold))
                    .foregroundStyle(FacilityTheme.ink)
                Text("briefing.partnerPicker.localHint")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }

            // Side by side while each card keeps 340 pt. The layout keeps the
            // text fields' identity when it stacks them, so a field being
            // edited keeps its focus if the dialog changes width.
            FacilityColumnsLayout(
                columnCounts: dynamicTypeSize.isAccessibilitySize ? [1] : [2, 1],
                minimumColumnWidth: 340,
                spacing: 16
            ) {
                contactCard
                addressCard
            }

            HStack(spacing: 12) {
                Button(action: addPartnerDraft) {
                    Label("dlgAddPartner.button.add", systemImage: "plus.circle.fill")
                        .font(.body.weight(.semibold))
                        .padding(.horizontal, 24)
                        .frame(minHeight: 48)
                }
                .buttonStyle(.borderedProminent)
                .buttonBorderShape(.roundedRectangle(radius: 13))
                .tint(FacilityTheme.accent)

                Button("dlgAddPartner.button.reset", action: resetPartnerDraft)
                    .font(.body.weight(.semibold))
                    .frame(minHeight: 48)
                    .padding(.horizontal, 12)
                    .buttonStyle(.plain)
                    .foregroundStyle(FacilityTheme.ink)
                Spacer(minLength: 0)
            }
            if hasAttemptedPartnerAdd,
               partnerDraftIsInvalid(.company) || partnerDraftIsInvalid(.contactName) {
                Label("flEQ.briefing.partner.validation", systemImage: "exclamationmark.circle.fill")
                    .font(.subheadline)
                    .foregroundStyle(FacilityTheme.red)
            }
        }
        .padding(.bottom, 8)
    }

    private var contactCard: some View {
        partnerCard("briefing.partnerPicker.contact", icon: "person.crop.square") {
            partnerDraftRow("dlgAddPartner.form.firma", required: true) {
                partnerDraftTextField("dlgAddPartner.form.firma", text: $partnerDraft.company, issue: .company)
            }
            partnerDraftRow("dlgAddPartner.form.name", required: true) {
                HStack(spacing: 8) {
                    partnerDropdown(
                        .salutation,
                        title: "briefing.partnerPicker.salutation",
                        placeholder: "briefing.partnerPicker.chooseSalutation",
                        iconName: "person.text.rectangle",
                        options: salutationOptions,
                        selection: partnerDraft.title
                    ) { partnerDraft.title = $0 }
                    .frame(width: 156)
                    partnerDraftTextField("dlgAddPartner.form.vorname", text: $partnerDraft.contactName, issue: .contactName)
                }
            }
            partnerDraftRow("dlgAddPartner.form.email") {
                partnerDraftTextField("dlgAddPartner.form.email", text: $partnerDraft.email, issue: .email, keyboardType: .emailAddress)
            }
            partnerDraftRow("dlgAddPartner.form.telephone") {
                partnerDraftTextField("dlgAddPartner.form.telephone", text: $partnerDraft.telephone, issue: .telephone, keyboardType: .phonePad)
            }
        }
    }

    private var addressCard: some View {
        partnerCard("briefing.partnerPicker.address", icon: "mappin.and.ellipse") {
            partnerDraftRow("dlgAddPartner.form.strHnr") {
                HStack(spacing: 8) {
                    partnerDraftTextField("briefing.partnerPicker.street", text: $partnerDraft.street, issue: .street)
                    partnerDraftTextField("briefing.partnerPicker.houseNumber", text: $partnerDraft.houseNumber, issue: .houseNumber)
                        .frame(maxWidth: 100)
                }
            }
            partnerDraftRow("briefing.partnerPicker.postalCode") {
                partnerDraftTextField("briefing.partnerPicker.postalCode", text: Binding(
                    get: { partnerDraft.postalCode },
                    set: { partnerDraft.postalCode = $0.filter(\.isNumber) }
                ), issue: .postalCode, keyboardType: .numberPad)
            }
            partnerDraftRow("briefing.partnerPicker.city") {
                partnerDraftTextField("briefing.partnerPicker.city", text: $partnerDraft.city, issue: .city)
            }
            partnerDraftRow("dlgAddPartner.form.country") {
                partnerDropdown(
                    .country,
                    title: "dlgAddPartner.form.country",
                    placeholder: "briefing.partnerPicker.chooseCountry",
                    iconName: "globe.europe.africa",
                    options: countryOptions,
                    selection: partnerDraft.country
                ) { partnerDraft.country = $0 }
            }
        }
    }

    private var salutationOptions: [FacilityDropdownOption] {
        [
            FacilityDropdownOption(id: "", title: "—"),
            FacilityDropdownOption(id: "0001", title: String(localized: "addUser.title.frau", bundle: .appLanguage)),
            FacilityDropdownOption(id: "0002", title: String(localized: "addUser.title.herr", bundle: .appLanguage))
        ]
    }

    private var countryOptions: [FacilityDropdownOption] {
        let countries = Self.legacyCountryCodes
            .map { FacilityDropdownOption(id: $0, title: countryName(for: $0)) }
            .sorted { $0.title.localizedStandardCompare($1.title) == .orderedAscending }
        return [FacilityDropdownOption(id: "", title: "—")] + countries
    }

    private func partnerDropdown(
        _ field: PartnerDropdown,
        title: LocalizedStringKey,
        placeholder: String,
        iconName: String,
        options: [FacilityDropdownOption],
        selection: String,
        onSelect: @escaping (String) -> Void
    ) -> some View {
        let selectedTitle = options.first { $0.id == selection && !selection.isEmpty }?.title
        let placeholderTitle = String(localized: String.LocalizationValue(placeholder), bundle: .appLanguage)
        return Button {
            focusedPartnerField = nil
            presentedPartnerDropdown = field
        } label: {
            HStack(spacing: 10) {
                Text(verbatim: selectedTitle ?? placeholderTitle)
                    .foregroundStyle(selectedTitle == nil ? .secondary : FacilityTheme.ink)
                    .lineLimit(1)
                Spacer(minLength: 0)
                Image(systemName: "chevron.up.chevron.down")
                    .font(.caption.weight(.bold))
                    .foregroundStyle(FacilityTheme.blue)
            }
            .padding(.horizontal, 14)
            .frame(maxWidth: .infinity, minHeight: 48)
            .background(FacilityTheme.canvas.opacity(0.6))
            .partnerFieldChrome(invalid: false)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(Text(title))
        .accessibilityValue(Text(verbatim: selectedTitle ?? placeholderTitle))
        .facilityPopover(
            isPresented: Binding(
                get: { presentedPartnerDropdown == field },
                set: { if !$0 && presentedPartnerDropdown == field { presentedPartnerDropdown = nil } }
            ),
            arrowEdge: .top
        ) {
            FacilityDropdownOptionsPicker(
                label: Text(title),
                iconName: iconName,
                options: options,
                selection: [selection],
                onSelect: { option in
                    onSelect(option.id)
                    presentedPartnerDropdown = nil
                }
            )
        }
    }

    private func partnerCard<Content: View>(
        _ title: LocalizedStringKey, icon: String,
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            Label(title, systemImage: icon)
                .font(.headline)
                .foregroundStyle(FacilityTheme.accent)
                .padding(.bottom, 2)
            content()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .facilityCard(padding: 20)
        .overlay {
            RoundedRectangle(cornerRadius: 18)
                .stroke(FacilityTheme.accent.opacity(0.12), lineWidth: 1)
        }
    }

    private func partnerDraftRow<Content: View>(
        _ title: LocalizedStringKey, required: Bool = false,
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 3) {
                Text(title)
                    .foregroundStyle(FacilityTheme.ink.opacity(0.72))
                if required {
                    Text(verbatim: "*").foregroundStyle(FacilityTheme.accent)
                        .accessibilityLabel(Text("briefing.partnerPicker.required"))
                }
            }
            .font(.caption.weight(.semibold))
            content().frame(maxWidth: .infinity)
        }
    }

    private func partnerDraftTextField(
        _ title: LocalizedStringKey,
        text: Binding<String>,
        issue: ValidationIssue,
        keyboardType: UIKeyboardType = .default
    ) -> some View {
        TextField(title, text: text)
            .textFieldStyle(.plain)
            .focused($focusedPartnerField, equals: issue)
            .id(issue)
            .keyboardType(keyboardType)
            .textInputAutocapitalization(keyboardType == .emailAddress ? .never : .sentences)
            .autocorrectionDisabled(keyboardType == .emailAddress)
            .padding(.horizontal, 14)
            .frame(maxWidth: .infinity, minHeight: 48)
            .background(FacilityTheme.canvas.opacity(0.6))
            .partnerFieldChrome(invalid: partnerDraftIsInvalid(issue))
    }

    private func scrollFocusedField(in proxy: ScrollViewProxy) {
        guard let field = focusedPartnerField else { return }
        Task { @MainActor in
            try? await Task.sleep(nanoseconds: 180_000_000)
            guard focusedPartnerField == field else { return }
            withAnimation(.easeOut(duration: 0.2)) {
                proxy.scrollTo(field, anchor: .center)
            }
        }
    }

    private func partnerDraftIsInvalid(
        _ issue: ValidationIssue
    ) -> Bool {
        guard hasAttemptedPartnerAdd else { return false }
        switch issue {
        case .company: return partnerDraft.company.isEmpty
        case .contactName: return partnerDraft.contactName.isEmpty
        default: return false
        }
    }

    private func toggleAddPartner() {
        withAnimation(partnerPanelAnimation) {
            if isAddingPartner {
                isAddingPartner = false
                return
            }

            resetPartnerDraft()
            isAddingPartner = true
        }
    }

    private func resetPartnerDraft() {
        partnerDraft = BriefingTemporaryPartner(id: "NEU" + String(UUID().uuidString.replacingOccurrences(of: "-", with: "").prefix(6)), company: "", title: "", contactName: "", email: "", telephone: "", street: "", houseNumber: "", postalCode: "", city: "", country: "")
        hasAttemptedPartnerAdd = false
    }

    private func addPartnerDraft() {
        if partnerDraft.company.isEmpty || partnerDraft.contactName.isEmpty {
            hasAttemptedPartnerAdd = true
            return
        }
        viewModel.addTemporaryPartner(partnerDraft)
        withAnimation(partnerPanelAnimation) {
            session.recentlyAddedPartnerID = partnerDraft.id
            selectedPartnerID = partnerDraft.id
            isAddingPartner = false
            hasAttemptedPartnerAdd = false
        }
    }

    private func countryName(for countryCode: String) -> String {
        Locale.current.localizedString(forRegionCode: countryCode) ?? countryCode
    }

    private var partnerTable: some View {
        let partners = isAddingPartner ? [] : availablePartners
        return BriefingPartnerSelectionTable(
            partners: session.visiblePartners(in: partners.map {
                BriefingPartnerSelection(
                    id: $0.id,
                    client: $0.client,
                    function: $0.function,
                    name: $0.name,
                    searchTerm1: $0.searchTerm1,
                    searchTerm2: $0.searchTerm2
                )
            }),
            selectedPartnerID: $selectedPartnerID,
            searchTerm2: Binding(
                get: { viewModel.partnerSearchTerm2 },
                set: { viewModel.partnerSearchTerm2 = $0 }
            )
        )
    }

    private var availablePartners: [SAPBriefingPartner] {
        guard let selectedPartner = viewModel.selectedPartner,
              !viewModel.partners.contains(where: { $0.id == selectedPartner.id })
        else {
            return viewModel.partners
        }
        return [selectedPartner] + viewModel.partners
    }

    private static let legacyCountryCodes = [
        "AL", "AD", "BE", "BA", "BG", "DE", "DK", "EE", "FI", "FR",
        "GR", "IE", "IS", "IT", "XK", "HR", "LV", "LI", "LT", "LU",
        "MV", "MT", "MK", "MC", "ME", "NL", "NO", "PL", "PT", "RO",
        "SM", "SE", "CH", "XS", "SK", "SI", "ES", "CZ", "UA", "HU",
        "VA", "GB", "AT"
    ]

    private enum ValidationIssue: Hashable {
        case company, contactName, email, telephone, street, houseNumber, postalCode, city, country
    }

    private enum PartnerDropdown: Hashable {
        case salutation, country
    }
}

private extension View {
    func partnerFieldChrome(invalid: Bool) -> some View {
        clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .stroke(
                        invalid ? FacilityTheme.red : Color.black.opacity(0.11),
                        lineWidth: invalid ? 2 : 1
                    )
            }
            .shadow(color: Color.black.opacity(0.025), radius: 3, y: 1)
    }
}
