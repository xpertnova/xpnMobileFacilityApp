import SwiftUI

/// One selectable entry of a `FacilityDropdownField`. `id` is the transport
/// value (an SAP code, for example) and `title` is what the technician reads.
struct FacilityDropdownOption: Identifiable, Hashable, Sendable {
    let id: String
    let title: String

    init(id: String, title: String) {
        self.id = id
        self.title = title
    }

    /// An option whose value and text are the same string.
    init(_ title: String) {
        self.init(id: title, title: title)
    }
}

/// Shared anchored dropdown: field chrome, `facilityPopover` and the selectable
/// list used by the technical-place creation flows and the equipment
/// inspection header. Multi-selection keeps the popover open, like the legacy
/// `sap.m.MultiComboBox`.
struct FacilityDropdownField: View {
    let label: Text
    let placeholder: String
    let iconName: String
    let options: [FacilityDropdownOption]
    let selection: Set<String>
    let allowsMultipleSelection: Bool
    let isRequired: Bool
    let isEnabled: Bool
    let isInvalid: Bool
    let labelPlacement: SafetyFormFieldLabelPlacement
    @Binding var isPresented: Bool
    let onOpen: () -> Void
    let onSelect: (FacilityDropdownOption) -> Void

    init(
        label: Text,
        placeholder: String,
        iconName: String,
        options: [FacilityDropdownOption],
        selection: Set<String>,
        allowsMultipleSelection: Bool = false,
        isRequired: Bool = false,
        isEnabled: Bool,
        isInvalid: Bool = false,
        labelPlacement: SafetyFormFieldLabelPlacement = .top,
        isPresented: Binding<Bool>,
        onOpen: @escaping () -> Void = {},
        onSelect: @escaping (FacilityDropdownOption) -> Void
    ) {
        self.label = label
        self.placeholder = placeholder
        self.iconName = iconName
        self.options = options
        self.selection = selection
        self.allowsMultipleSelection = allowsMultipleSelection
        self.isRequired = isRequired
        self.isEnabled = isEnabled
        self.isInvalid = isInvalid
        self.labelPlacement = labelPlacement
        _isPresented = isPresented
        self.onOpen = onOpen
        self.onSelect = onSelect
    }

    private var selectedTitle: String? {
        let titles = options.filter { selection.contains($0.id) }.map(\.title)
        return titles.isEmpty ? nil : titles.joined(separator: "; ")
    }

    var body: some View {
        SafetyFormField(label: label, required: isRequired, labelPlacement: labelPlacement) {
            Button {
                onOpen()
                isPresented = true
            } label: {
                HStack(spacing: 12) {
                    Text(selectedTitle ?? String(localized: String.LocalizationValue(placeholder)))
                        .foregroundStyle(selectedTitle == nil ? .secondary : FacilityTheme.ink)
                        .lineLimit(1)
                    Spacer(minLength: 0)
                    Image(systemName: "chevron.up.chevron.down")
                        .font(.caption.weight(.bold))
                        .foregroundStyle(isEnabled ? FacilityTheme.blue : .secondary)
                }
                .briefingFieldChrome(invalid: isInvalid, isDisabled: !isEnabled)
            }
            .buttonStyle(.plain)
            .facilityPopover(isPresented: $isPresented, arrowEdge: .top) {
                FacilityDropdownOptionsPicker(
                    label: label,
                    iconName: iconName,
                    options: options,
                    selection: selection,
                    onSelect: { option in
                        onSelect(option)
                        if !allowsMultipleSelection {
                            isPresented = false
                        }
                    }
                )
            }
            .disabled(!isEnabled || options.isEmpty)
        }
    }
}

/// The option list of a dropdown. A long list can offer a search field that
/// filters the options by their text.
struct FacilityDropdownOptionsPicker: View {
    let label: Text
    let iconName: String
    let options: [FacilityDropdownOption]
    let selection: Set<String>
    let width: CGFloat
    let searchPrompt: LocalizedStringKey?
    let onSelect: (FacilityDropdownOption) -> Void
    @State private var searchText = ""

    init(
        label: Text,
        iconName: String,
        options: [FacilityDropdownOption],
        selection: Set<String>,
        width: CGFloat = 340,
        searchPrompt: LocalizedStringKey? = nil,
        onSelect: @escaping (FacilityDropdownOption) -> Void
    ) {
        self.label = label
        self.iconName = iconName
        self.options = options
        self.selection = selection
        self.width = width
        self.searchPrompt = searchPrompt
        self.onSelect = onSelect
    }

    private var filteredOptions: [FacilityDropdownOption] {
        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard searchPrompt != nil, !query.isEmpty else { return options }
        return options.filter { $0.title.localizedCaseInsensitiveContains(query) }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 10) {
                Image(systemName: iconName)
                    .foregroundStyle(FacilityTheme.accent)
                label
                    .font(.headline)
                    .foregroundStyle(FacilityTheme.ink)
            }
            .padding(.horizontal, 18)
            .padding(.vertical, 16)

            if let searchPrompt {
                HStack(spacing: 8) {
                    Image(systemName: "magnifyingglass")
                        .foregroundStyle(.secondary)
                    TextField(searchPrompt, text: $searchText)
                        .textFieldStyle(.plain)
                        .autocorrectionDisabled()
                        .textInputAutocapitalization(.never)
                    if !searchText.isEmpty {
                        Button {
                            searchText = ""
                        } label: {
                            Image(systemName: "xmark.circle.fill")
                                .foregroundStyle(.secondary)
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel(Text("places.search.clear"))
                    }
                }
                .padding(.horizontal, 12)
                .frame(height: 38)
                .background(FacilityTheme.canvas, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                .padding(.horizontal, 18)
                .padding(.bottom, 12)
            }

            Divider()

            ScrollView {
                if filteredOptions.isEmpty {
                    Text("dropdown.search.empty")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, minHeight: 80)
                } else {
                    LazyVStack(spacing: 0) {
                        ForEach(filteredOptions) { option in
                            let isSelected = selection.contains(option.id)
                            Button { onSelect(option) } label: {
                                HStack(spacing: 12) {
                                    Text(option.title)
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

                            if option.id != filteredOptions.last?.id {
                                Divider().padding(.leading, 18)
                            }
                        }
                    }
                }
            }
            .frame(maxHeight: 300)
        }
        .frame(width: width)
        .background(FacilityTheme.surface)
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
    }
}
