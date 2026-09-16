import SwiftUI

/// The one control every inspection form uses to record a result or an action.
///
/// It renders the variant the form's SAP metadata calls for — side-by-side
/// buttons for a two-value decision (legacy `sap.m.SegmentedButton`) or an
/// anchored code list for a longer value help (legacy `sap.m.Select`) — so
/// TFM2's five-code dropdown and TFM3's yes/no buttons are the same component
/// with the same touch targets, disabled treatment and accessibility wiring.
struct InspectionResultControl: View {
    /// Which column of a row this control belongs to. Only one popover in a
    /// row may be open at a time, so the row owns the expansion state.
    enum Field: Hashable, Sendable {
        case result
        case action
    }

    let field: Field
    let style: InspectionControlStyle
    let options: [InspectionFormOption]
    /// The selected option's `id`, not its SAP code — TFM1/TFM3 post an empty
    /// string for "in Ordnung", which cannot double as "nothing selected".
    let selectionID: String?
    let isEnabled: Bool
    let accessibilityLabelKey: String
    @Binding var expandedField: Field?
    let select: (InspectionFormOption) -> Void

    var body: some View {
        switch style {
        case .segmented:
            segmentedControl
        case .dropdown:
            dropdownControl
        }
    }

    private var selectedOption: InspectionFormOption? {
        options.first { $0.id == selectionID }
    }

    // MARK: - Segmented

    /// Matches the MFM reference template's `.jn` control: a translucent track
    /// with the selected value filled in the colour of its outcome.
    private var segmentedControl: some View {
        HStack(spacing: 2) {
            ForEach(options) { option in
                segmentedButton(for: option)
            }
        }
        .padding(2)
        .background(Color(red: 118 / 255, green: 118 / 255, blue: 128 / 255).opacity(0.12))
        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
        .accessibilityLabel(Text(LocalizedStringKey(accessibilityLabelKey)))
    }

    private func segmentedButton(for option: InspectionFormOption) -> some View {
        let isSelected = option.id == selectionID
        return Button {
            select(option)
        } label: {
            Text(option.title)
                .font(.subheadline.weight(.semibold))
                .lineLimit(1)
                .minimumScaleFactor(0.85)
                .foregroundStyle(isSelected ? Color.white : Color.secondary)
                .frame(maxWidth: .infinity, minHeight: 38)
                .background(
                    isSelected ? tint(for: option) : .clear,
                    in: RoundedRectangle(cornerRadius: 8, style: .continuous)
                )
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(!isEnabled)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }

    private func tint(for option: InspectionFormOption) -> Color {
        switch option.tint {
        case .satisfactory: FacilityTheme.accent
        case .defect: FacilityTheme.red
        case .neutral: FacilityTheme.blue
        }
    }

    // MARK: - Dropdown

    private var dropdownControl: some View {
        InspectionCodePicker(
            picker: field,
            expandedPicker: $expandedField,
            selection: selectedOption?.code,
            options: options.map { InspectionCodeOption(code: $0.code, title: $0.title) },
            optionsHeight: min(CGFloat(max(options.count, 1)) * 50, 300),
            isEnabled: isEnabled,
            accessibilityLabel: Text(LocalizedStringKey(accessibilityLabelKey))
        ) { code in
            guard let option = options.first(where: { $0.code == code }) else { return }
            select(option)
        }
    }
}

/// Placeholder shown where a column exists for the form but SAP delivered no
/// values for this particular position. The legacy controllers substitute a
/// `"NO_PROP"` text cell in the same spot.
struct InspectionControlPlaceholder: View {
    var body: some View {
        Text(verbatim: "–")
            .foregroundStyle(.tertiary)
            .frame(maxWidth: .infinity, minHeight: 44, alignment: .center)
            .accessibilityHidden(true)
    }
}

/// The material checkbox of the dropdown forms (legacy `T_PROPS` `CBOX`).
struct InspectionMaterialCheckbox: View {
    let isSelected: Bool
    let isEnabled: Bool
    let toggle: () -> Void

    var body: some View {
        Button(action: toggle) {
            Image(systemName: isSelected ? "checkmark.square.fill" : "square")
                .font(.title2)
                .foregroundStyle(isSelected ? FacilityTheme.blue : .secondary)
                .frame(width: 44, height: 44)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(!isEnabled)
        .accessibilityLabel(Text("elevator.column.material"))
        .accessibilityValue(Text(isSelected ? "notifications.detail.result.yes" : "notifications.detail.result.no"))
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }
}
