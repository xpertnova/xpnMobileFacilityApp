import SwiftUI

/// Shared address-context selector used by technical-place creation flows.
/// It keeps the Mobile Ladder's field chrome, anchored popover and selectable
/// list behavior consistent for building, trade and parent-place selection.
struct TechnicalPlaceContextDropdownField: View {
    let title: LocalizedStringKey
    let placeholder: String
    let iconName: String
    let options: [String]
    let selection: String?
    let isRequired: Bool
    let isEnabled: Bool
    @Binding var isPresented: Bool
    let onOpen: () -> Void
    let onSelect: (String) -> Void

    init(
        _ title: LocalizedStringKey,
        placeholder: String,
        iconName: String,
        options: [String],
        selection: String?,
        isRequired: Bool = false,
        isEnabled: Bool,
        isPresented: Binding<Bool>,
        onOpen: @escaping () -> Void = {},
        onSelect: @escaping (String) -> Void
    ) {
        self.title = title
        self.placeholder = placeholder
        self.iconName = iconName
        self.options = options
        self.selection = selection
        self.isRequired = isRequired
        self.isEnabled = isEnabled
        _isPresented = isPresented
        self.onOpen = onOpen
        self.onSelect = onSelect
    }

    var body: some View {
        SafetyFormField(title, required: isRequired) {
            Button {
                onOpen()
                isPresented = true
            } label: {
                HStack(spacing: 12) {
                    Text(selection ?? String(localized: String.LocalizationValue(placeholder)))
                        .foregroundStyle(selection == nil ? .secondary : FacilityTheme.ink)
                        .lineLimit(1)
                    Spacer(minLength: 0)
                    Image(systemName: "chevron.up.chevron.down")
                        .font(.caption.weight(.bold))
                        .foregroundStyle(isEnabled ? FacilityTheme.blue : .secondary)
                }
                .briefingFieldChrome(invalid: false)
            }
            .buttonStyle(.plain)
            .facilityPopover(isPresented: $isPresented, arrowEdge: .top) {
                TechnicalPlaceContextOptionsPicker(
                    title: title,
                    iconName: iconName,
                    options: options,
                    selection: selection,
                    onSelect: { option in
                        onSelect(option)
                        isPresented = false
                    }
                )
            }
            .disabled(!isEnabled || options.isEmpty)
        }
    }
}

private struct TechnicalPlaceContextOptionsPicker: View {
    let title: LocalizedStringKey
    let iconName: String
    let options: [String]
    let selection: String?
    let onSelect: (String) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 10) {
                Image(systemName: iconName)
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
                    ForEach(options, id: \.self) { option in
                        let isSelected = option == selection
                        Button { onSelect(option) } label: {
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
}
