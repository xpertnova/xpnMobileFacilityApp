import SwiftUI
import UIKit

/// The partner-company value-help frame matches the established briefing form
/// interaction. Its data and mutations remain feature-local until the SAP
/// partner-master-data contract is available.
struct BriefingPartnerSelectionEditor: View {
    let viewModel: BriefingWorkflowViewModel
    let onDismiss: () -> Void

    @State private var selectedPartnerID: String?
    @State private var isAddingPartner = false
    @State private var partnerDraft = BriefingTemporaryPartner(id: "NEU" + String(UUID().uuidString.replacingOccurrences(of: "-", with: "").prefix(6)), company: "", title: "", contactName: "", email: "", telephone: "", street: "", houseNumber: "", postalCode: "", city: "", country: "")
    @State private var hasAttemptedPartnerAdd = false

    init(
        viewModel: BriefingWorkflowViewModel,
        onDismiss: @escaping () -> Void
    ) {
        self.viewModel = viewModel
        self.onDismiss = onDismiss
        _selectedPartnerID = State(initialValue: viewModel.selectedPartnerID)
    }

    var body: some View {
        BriefingPartnerSelectionFrame(
            isConfirmationDisabled: selectedPartnerID == nil,
            onCancel: onDismiss,
            onConfirm: selectPartner
        ) {
            ZStack {
                if isAddingPartner {
                    ScrollView(.vertical) {
                        addPartnerForm
                    }
                    .scrollDismissesKeyboard(.interactively)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .transition(partnerPanelTransition)
                } else {
                    partnerList
                        .transition(partnerPanelTransition)
                }
            }
            .padding(.horizontal, 28)
            .padding(.vertical, 20)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .animation(partnerPanelAnimation, value: isAddingPartner)
        }
    }

    private var partnerList: some View {
        VStack(spacing: 16) {
            HStack {
                Spacer()
                addPartnerButton
            }

            partnerTable
                .frame(height: 458)

            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var partnerPanelAnimation: Animation {
        .easeInOut(duration: 0.24)
    }

    private var partnerPanelTransition: AnyTransition {
        .opacity.combined(with: .scale(scale: 0.985, anchor: .top))
    }

    private var addPartnerButton: some View {
        Button(action: toggleAddPartner) {
            Label("briefing.partnerPicker.add", systemImage: "plus")
                .font(.subheadline.weight(.semibold))
                .frame(minHeight: 44)
                .padding(.horizontal, 14)
        }
        .buttonStyle(.borderedProminent)
        .buttonBorderShape(.roundedRectangle(radius: 12))
        .tint(FacilityTheme.accent)
        .accessibilityLabel(Text("briefing.partnerPicker.add"))
    }

    private func selectPartner() {
        if let selectedPartnerID {
            viewModel.selectPartner(selectedPartnerID)
        }
        onDismiss()
    }

    private var addPartnerForm: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 16) {
                Text("dlgAddPartner.form.title.add")
                    .font(.title2.weight(.semibold))

                Spacer(minLength: 0)

                Button(action: toggleAddPartner) {
                    Label("briefing.partnerPicker.showList", systemImage: "list.bullet")
                        .font(.subheadline.weight(.semibold))
                        .frame(minHeight: 44)
                        .padding(.horizontal, 14)
                }
                .buttonStyle(.bordered)
                .buttonBorderShape(.roundedRectangle(radius: 12))
                .tint(FacilityTheme.ink)
                .accessibilityLabel(Text("briefing.partnerPicker.showList"))
            }
            .padding(.bottom, 2)

            partnerDraftRow("dlgAddPartner.form.firma") {
                partnerDraftTextField(
                    "dlgAddPartner.form.firma",
                    text: $partnerDraft.company,
                    issue: .company
                )
            }

            partnerDraftRow("dlgAddPartner.form.name") {
                HStack(spacing: 8) {
                    Picker("", selection: $partnerDraft.title) {
                        Text(verbatim: "—").tag("")
                        Text("addUser.title.frau").tag("0001")
                        Text("addUser.title.herr").tag("0002")
                    }
                    .labelsHidden()
                    .pickerStyle(.menu)
                    .tint(FacilityTheme.blue)
                    .padding(.horizontal, 14)
                    .frame(width: 92, height: 48)
                    .background(Color(uiColor: .systemBackground))
                    .partnerFieldChrome(invalid: false)

                    partnerDraftTextField(
                        "dlgAddPartner.form.vorname",
                        text: $partnerDraft.contactName,
                        issue: .contactName
                    )
                }
            }

            partnerDraftRow("dlgAddPartner.form.email") {
                partnerDraftTextField(
                    "dlgAddPartner.form.email",
                    text: $partnerDraft.email,
                    issue: .email,
                    keyboardType: .emailAddress
                )
            }

            partnerDraftRow("dlgAddPartner.form.telephone") {
                partnerDraftTextField(
                    "dlgAddPartner.form.telephone",
                    text: $partnerDraft.telephone,
                    issue: .telephone,
                    keyboardType: .phonePad
                )
            }

            partnerDraftRow("dlgAddPartner.form.strHnr") {
                HStack(spacing: 10) {
                    partnerDraftTextField(
                        "dlgAddPartner.form.strHnr",
                        text: $partnerDraft.street,
                        issue: .street
                    )
                    .frame(maxWidth: .infinity)

                    partnerDraftTextField(
                        "",
                        text: $partnerDraft.houseNumber,
                        issue: .houseNumber
                    )
                    .frame(width: 182)
                }
            }

            partnerDraftRow("dlgAddPartner.form.plzCity") {
                HStack(spacing: 10) {
                    partnerDraftTextField(
                        "",
                        text: Binding(
                            get: { partnerDraft.postalCode },
                            set: { partnerDraft.postalCode = $0.filter(\.isNumber) }
                        ),
                        issue: .postalCode,
                        keyboardType: .numberPad
                    )
                    .frame(width: 182)

                    partnerDraftTextField(
                        "dlgAddPartner.form.plzCity",
                        text: $partnerDraft.city,
                        issue: .city
                    )
                }
            }

            partnerDraftRow("dlgAddPartner.form.country") {
                Picker("", selection: $partnerDraft.country) {
                    Text(verbatim: "—").tag("")
                    ForEach(Self.legacyCountryCodes, id: \.self) { countryCode in
                        Text(verbatim: countryName(for: countryCode)).tag(countryCode)
                    }
                }
                .labelsHidden()
                .pickerStyle(.menu)
                .tint(FacilityTheme.blue)
                .padding(.horizontal, 14)
                .frame(maxWidth: .infinity, minHeight: 48, alignment: .leading)
                .background(Color(uiColor: .systemBackground))
                .partnerFieldChrome(invalid: partnerDraftIsInvalid(.country))
            }

            HStack(spacing: 10) {
                Button(action: addPartnerDraft) {
                    Text("dlgAddPartner.button.add")
                        .font(.body.weight(.semibold))
                        .frame(minWidth: 220, minHeight: 52)
                }
                .buttonStyle(.borderedProminent)
                .buttonBorderShape(.roundedRectangle(radius: 12))
                .tint(FacilityTheme.accent)

                Button(action: resetPartnerDraft) {
                    Text("dlgAddPartner.button.reset")
                        .font(.body.weight(.semibold))
                        .frame(minWidth: 220, minHeight: 52)
                }
                .buttonStyle(.bordered)
                .buttonBorderShape(.roundedRectangle(radius: 12))
                .tint(FacilityTheme.ink)
            }

            if hasAttemptedPartnerAdd,
               partnerDraftIsInvalid(.company) || partnerDraftIsInvalid(.contactName) {
                Label(
                    "flEQ.briefing.partner.validation",
                    systemImage: "exclamationmark.circle.fill"
                )
                .font(.caption)
                .foregroundStyle(.red)
                .padding(.leading, 212)
            }
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 18)
        .background(Color(uiColor: .systemBackground))
        .overlay(alignment: .bottom) { Divider() }
    }

    private func partnerDraftRow<Content: View>(
        _ title: LocalizedStringKey,
        @ViewBuilder content: () -> Content
    ) -> some View {
        HStack(alignment: .center, spacing: 14) {
            HStack(spacing: 0) {
                Text(verbatim: "*")
                    .foregroundStyle(.red)
                    .accessibilityHidden(true)
                Text(title)
                    .foregroundStyle(.secondary)
            }
            .frame(width: 192, alignment: .trailing)

            content()
                .frame(maxWidth: .infinity)
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
            .keyboardType(keyboardType)
            .textInputAutocapitalization(keyboardType == .emailAddress ? .never : .sentences)
            .autocorrectionDisabled(keyboardType == .emailAddress)
            .padding(.horizontal, 14)
            .frame(maxWidth: .infinity, minHeight: 48)
            .background(Color(uiColor: .systemBackground))
            .partnerFieldChrome(invalid: partnerDraftIsInvalid(issue))
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

            selectedPartnerID = nil
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

    private enum ValidationIssue {
        case company, contactName, email, telephone, street, houseNumber, postalCode, city, country
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
