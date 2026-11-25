import SwiftUI

/// Shared address-context selector used by technical-place creation flows.
/// It keeps the Mobile Ladder's field chrome, anchored popover and selectable
/// list behavior consistent for building, trade and parent-place selection.
/// The chrome and list come from `FacilityDropdownField`.
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
        FacilityDropdownField(
            label: Text(title),
            placeholder: placeholder,
            iconName: iconName,
            options: options.map(FacilityDropdownOption.init),
            selection: selection.map { [$0] } ?? [],
            isRequired: isRequired,
            isEnabled: isEnabled,
            isPresented: $isPresented,
            onOpen: onOpen,
            onSelect: { onSelect($0.id) }
        )
    }
}
