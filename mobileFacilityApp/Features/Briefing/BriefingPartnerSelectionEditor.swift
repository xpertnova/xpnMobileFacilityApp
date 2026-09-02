import SwiftUI
import UIKit

/// The partner-company value-help frame matches the established briefing form
/// interaction. Its data and mutations remain feature-local until the SAP
/// partner-master-data contract is available.
struct BriefingPartnerSelectionEditor: View {
    let viewModel: BriefingWorkflowViewModel
    let onDismiss: () -> Void

    @State private var selectedPartnerID: String?
    @State private var sort = Sort.nameAscending
    @State private var activeColumnMenu: PartnerColumn?
    @State private var columnFilters: [PartnerColumn: String] = [:]
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
            VStack(spacing: 16) {
                HStack {
                    Spacer()

                    Button(action: toggleAddPartner) {
                        Label(
                            isAddingPartner ? "briefing.partnerPicker.showList" : "briefing.partnerPicker.add",
                            systemImage: isAddingPartner ? "list.bullet" : "plus"
                        )
                        .font(.subheadline.weight(.semibold))
                        .frame(minHeight: 44)
                        .padding(.horizontal, 14)
                    }
                    .buttonStyle(.borderedProminent)
                    .buttonBorderShape(.capsule)
                    .tint(FacilityTheme.accent)
                    .accessibilityLabel(
                        isAddingPartner
                            ? Text("briefing.partnerPicker.showList")
                            : Text("briefing.partnerPicker.add")
                    )
                }

                if isAddingPartner {
                    addPartnerForm
                }

                partnerTable
                    .frame(height: isAddingPartner ? 105 : 458)

                Spacer(minLength: 0)
            }
            .padding(.horizontal, 28)
            .padding(.vertical, 20)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    private func selectPartner() {
        if let selectedPartnerID {
            viewModel.selectPartner(selectedPartnerID)
        }
        onDismiss()
    }

    private var addPartnerForm: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("dlgAddPartner.form.title.add")
                .font(.title2.weight(.semibold))
                .padding(.bottom, 8)

            partnerDraftRow("dlgAddPartner.form.firma", issue: .company) {
                partnerDraftTextField(
                    "dlgAddPartner.form.firma",
                    text: $partnerDraft.company,
                    issue: .company
                )
            }

            partnerDraftRow("dlgAddPartner.form.name", issue: .contactName) {
                HStack(spacing: 8) {
                    Picker("", selection: $partnerDraft.title) {
                        Text(verbatim: "—").tag("")
                        Text("addUser.title.frau").tag("0001")
                        Text("addUser.title.herr").tag("0002")
                    }
                    .labelsHidden()
                    .pickerStyle(.menu)
                    .tint(Color.accentColor)
                    .frame(width: 92, height: 44)
                    .background(Color(uiColor: .systemBackground))
                    .partnerFieldChrome(invalid: false)

                    partnerDraftTextField(
                        "dlgAddPartner.form.vorname",
                        text: $partnerDraft.contactName,
                        issue: .contactName
                    )
                }
            }

            partnerDraftRow("dlgAddPartner.form.email", issue: .email) {
                partnerDraftTextField(
                    "dlgAddPartner.form.email",
                    text: $partnerDraft.email,
                    issue: .email,
                    keyboardType: .emailAddress
                )
            }

            partnerDraftRow("dlgAddPartner.form.telephone", issue: .telephone) {
                partnerDraftTextField(
                    "dlgAddPartner.form.telephone",
                    text: $partnerDraft.telephone,
                    issue: .telephone,
                    keyboardType: .phonePad
                )
            }

            partnerDraftRow("dlgAddPartner.form.strHnr", issue: .street) {
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

            partnerDraftRow("dlgAddPartner.form.plzCity", issue: .postalCode) {
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

            partnerDraftRow("dlgAddPartner.form.country", issue: .country) {
                Picker("", selection: $partnerDraft.country) {
                    Text(verbatim: "—").tag("")
                    ForEach(Self.legacyCountryCodes, id: \.self) { countryCode in
                        Text(verbatim: countryName(for: countryCode)).tag(countryCode)
                    }
                }
                .labelsHidden()
                .pickerStyle(.menu)
                .tint(Color.accentColor)
                .padding(.horizontal, 10)
                .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
                .background(Color(uiColor: .systemBackground))
                .partnerFieldChrome(invalid: partnerDraftIsInvalid(.country))
            }

            HStack(spacing: 10) {
                Button(action: addPartnerDraft) {
                    Text("dlgAddPartner.button.add")
                        .frame(minWidth: 182, minHeight: 52)
                }
                    .buttonStyle(.borderedProminent)
                    .buttonBorderShape(.capsule)
                    .tint(FacilityTheme.accent)

                Button(action: resetPartnerDraft) {
                    Text("dlgAddPartner.button.reset")
                        .frame(minWidth: 182, minHeight: 52)
                }
                    .buttonStyle(.bordered)
                    .buttonBorderShape(.capsule)
                    .tint(FacilityTheme.accent)
            }
            .padding(.leading, 212)

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
        issue: ValidationIssue,
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
            .padding(.horizontal, 11)
            .frame(maxWidth: .infinity, minHeight: 44)
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
        if isAddingPartner {
            isAddingPartner = false
            return
        }

        selectedPartnerID = nil
        columnFilters = [:]
        activeColumnMenu = nil
        resetPartnerDraft()
        isAddingPartner = true
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
        selectedPartnerID = partnerDraft.id
        isAddingPartner = false
        hasAttemptedPartnerAdd = false
    }

    private func countryName(for countryCode: String) -> String {
        Locale.current.localizedString(forRegionCode: countryCode) ?? countryCode
    }

    private var partnerTable: some View {
        BriefingPartnerSelectionTable(
            partners: displayedPartners.map {
                BriefingPartnerSelection(
                    id: $0.id,
                    client: $0.client,
                    function: $0.function,
                    name: $0.name,
                    searchTerm1: $0.searchTerm1,
                    searchTerm2: $0.searchTerm2
                )
            },
            selectedPartnerID: $selectedPartnerID,
            emptyRowCount: emptyGridRowCount
        )
    }

    private func partnerColumnHeader(
        _ title: Text,
        width: CGFloat,
        column: PartnerColumn
    ) -> some View {
        HStack(spacing: 6) {
            title.lineLimit(1)
            Spacer(minLength: 4)

            Button {
                activeColumnMenu = activeColumnMenu == column ? nil : column
            } label: {
                Image(systemName: "line.3.horizontal.decrease")
                    .foregroundStyle(hasFilter(for: column) ? Color.accentColor : .secondary)
                    .frame(width: 28, height: 44)
            }
            .buttonStyle(.plain)
            .popover(
                isPresented: columnMenuBinding(for: column),
                attachmentAnchor: .rect(.bounds),
                arrowEdge: .top
            ) {
                partnerColumnMenu(column)
                    .presentationCompactAdaptation(.popover)
            }
        }
        .padding(.leading, 12)
        .frame(width: width)
        .frame(minHeight: 45)
        .overlay(alignment: .trailing) {
            Rectangle().fill(Color(uiColor: .separator)).frame(width: 0.5)
        }
        .overlay(alignment: .bottom) {
            Rectangle().fill(Color(uiColor: .separator)).frame(height: 0.5)
        }
    }

    private func partnerColumnMenu(_ column: PartnerColumn) -> some View {
        VStack(spacing: 0) {
            columnMenuButton("notifications.sort.ascending", systemImage: "line.3.horizontal.decrease") {
                sort = column.ascendingSort
                activeColumnMenu = nil
            }

            Divider()

            columnMenuButton("notifications.sort.descending", systemImage: "line.3.horizontal.decrease") {
                sort = column.ascendingSort.descending
                activeColumnMenu = nil
            }

            Divider()

            HStack(spacing: 10) {
                Image(systemName: "line.3.horizontal.decrease")
                    .foregroundStyle(.secondary)

                Text("flEQ.briefing.partner.filter")
                    .foregroundStyle(.primary)

                TextField("", text: filterBinding(for: column))
                    .textFieldStyle(.plain)
                    .padding(.horizontal, 8)
                    .frame(width: 170, height: 32)
                    .background(Color(uiColor: .systemBackground))
                    .partnerFieldChrome(invalid: false)
            }
            .padding(.horizontal, 12)
            .frame(minHeight: 48)
        }
        .font(.body)
        .frame(width: 350)
        .background(Color(uiColor: .systemBackground))
    }

    private func columnMenuButton(
        _ title: LocalizedStringKey,
        systemImage: String,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Label(title, systemImage: systemImage)
                .foregroundStyle(.primary)
                .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
                .padding(.horizontal, 12)
        }
        .buttonStyle(.plain)
    }

    private func columnMenuBinding(for column: PartnerColumn) -> Binding<Bool> {
        Binding(
            get: { activeColumnMenu == column },
            set: { isPresented in
                if !isPresented, activeColumnMenu == column {
                    activeColumnMenu = nil
                }
            }
        )
    }

    private func filterBinding(for column: PartnerColumn) -> Binding<String> {
        Binding(
            get: { columnFilters[column, default: ""] },
            set: { columnFilters[column] = $0 }
        )
    }

    private func hasFilter(for column: PartnerColumn) -> Bool {
        !columnFilters[column, default: ""]
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .isEmpty
    }

    private func partnerCell(_ value: String, width: CGFloat) -> some View {
        Text(value)
            .foregroundStyle(.primary)
            .lineLimit(2)
            .padding(.horizontal, 12)
            .frame(width: width, alignment: .leading)
            .frame(minHeight: 41)
            .overlay(alignment: .trailing) {
                Rectangle().fill(Color(uiColor: .separator)).frame(width: 0.5)
            }
            .overlay(alignment: .bottom) {
                Rectangle().fill(Color(uiColor: .separator)).frame(height: 0.5)
            }
    }

    private func partnerRow(
        _ partner: SAPBriefingPartner,
        widths: PartnerColumnWidths
    ) -> some View {
        HStack(spacing: 0) {
            partnerCell(partner.client, width: widths.client)
            partnerCell(partner.function, width: widths.function)
            partnerCell(partner.name, width: widths.name)
            partnerCell(partner.searchTerm1, width: widths.searchTerm1)
            partnerCell(partner.searchTerm2, width: widths.searchTerm2)
        }
    }

    private func emptyPartnerRow(widths: PartnerColumnWidths) -> some View {
        HStack(spacing: 0) {
            partnerCell("", width: widths.client)
            partnerCell("", width: widths.function)
            partnerCell("", width: widths.name)
            partnerCell("", width: widths.searchTerm1)
            partnerCell("", width: widths.searchTerm2)
        }
        .accessibilityHidden(true)
    }

    private var availablePartners: [SAPBriefingPartner] {
        guard let selectedPartner = viewModel.selectedPartner,
              !viewModel.partners.contains(where: { $0.id == selectedPartner.id })
        else {
            return viewModel.partners
        }
        return [selectedPartner] + viewModel.partners
    }

    private var displayedPartners: [SAPBriefingPartner] {
        if isAddingPartner { return [] }

        return availablePartners
            .filter { partner in
                PartnerColumn.allCases.allSatisfy { column in
                    let query = columnFilters[column, default: ""]
                        .trimmingCharacters(in: .whitespacesAndNewlines)
                    return query.isEmpty
                        || column.value(from: partner).localizedCaseInsensitiveContains(query)
                }
            }
            .sorted(by: sort.areInIncreasingOrder)
    }

    private var emptyGridRowCount: Int {
        isAddingPartner ? 1 : max(0, 9 - displayedPartners.count)
    }

    private static let legacyCountryCodes = [
        "AL", "AD", "BE", "BA", "BG", "DE", "DK", "EE", "FI", "FR",
        "GR", "IE", "IS", "IT", "XK", "HR", "LV", "LI", "LT", "LU",
        "MV", "MT", "MK", "MC", "ME", "NL", "NO", "PL", "PT", "RO",
        "SM", "SE", "CH", "XS", "SK", "SI", "ES", "CZ", "UA", "HU",
        "VA", "GB", "AT"
    ]

    private struct PartnerColumnWidths {
        let client: CGFloat
        let function: CGFloat
        let name: CGFloat
        let searchTerm1: CGFloat
        let searchTerm2: CGFloat

        init(totalWidth: CGFloat) {
            client = totalWidth * 0.13
            function = totalWidth * 0.085
            name = totalWidth * 0.26
            searchTerm1 = totalWidth * 0.2625
            searchTerm2 = totalWidth - client - function - name - searchTerm1
        }
    }

    
    private enum ValidationIssue {
        case company, contactName, email, telephone, street, houseNumber, postalCode, city, country
    }

    private enum PartnerColumn: CaseIterable, Hashable {
        case client
        case function
        case name
        case searchTerm1
        case searchTerm2

        var ascendingSort: Sort {
            switch self {
            case .client: .clientAscending
            case .function: .functionAscending
            case .name: .nameAscending
            case .searchTerm1: .searchTerm1Ascending
            case .searchTerm2: .searchTerm2Ascending
            }
        }

        func value(from partner: SAPBriefingPartner) -> String {
            switch self {
            case .client: partner.client
            case .function: partner.function
            case .name: partner.name
            case .searchTerm1: partner.searchTerm1
            case .searchTerm2: partner.searchTerm2
            }
        }
    }

    private enum Sort: Equatable {
        case clientAscending
        case clientDescending
        case functionAscending
        case functionDescending
        case nameAscending
        case nameDescending
        case searchTerm1Ascending
        case searchTerm1Descending
        case searchTerm2Ascending
        case searchTerm2Descending

        var descending: Self {
            switch self {
            case .clientAscending: .clientDescending
            case .functionAscending: .functionDescending
            case .nameAscending: .nameDescending
            case .searchTerm1Ascending: .searchTerm1Descending
            case .searchTerm2Ascending: .searchTerm2Descending
            case .clientDescending, .functionDescending, .nameDescending,
                 .searchTerm1Descending, .searchTerm2Descending:
                self
            }
        }

        func areInIncreasingOrder(
            _ lhs: SAPBriefingPartner,
            _ rhs: SAPBriefingPartner
        ) -> Bool {
            let comparison: ComparisonResult
            let isDescending: Bool
            switch self {
            case .clientAscending, .clientDescending:
                comparison = lhs.client.localizedStandardCompare(rhs.client)
                isDescending = self == .clientDescending
            case .functionAscending, .functionDescending:
                comparison = lhs.function.localizedStandardCompare(rhs.function)
                isDescending = self == .functionDescending
            case .nameAscending, .nameDescending:
                comparison = lhs.name.localizedStandardCompare(rhs.name)
                isDescending = self == .nameDescending
            case .searchTerm1Ascending, .searchTerm1Descending:
                comparison = lhs.searchTerm1.localizedStandardCompare(rhs.searchTerm1)
                isDescending = self == .searchTerm1Descending
            case .searchTerm2Ascending, .searchTerm2Descending:
                comparison = lhs.searchTerm2.localizedStandardCompare(rhs.searchTerm2)
                isDescending = self == .searchTerm2Descending
            }
            return isDescending ? comparison == .orderedDescending : comparison == .orderedAscending
        }
    }
}

private extension View {
    func partnerFieldChrome(invalid: Bool) -> some View {
        clipShape(RoundedRectangle(cornerRadius: 2, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 2, style: .continuous)
                    .stroke(
                        invalid ? Color.red : Color(uiColor: .separator),
                        lineWidth: invalid ? 2 : 1
                    )
            }
    }
}
