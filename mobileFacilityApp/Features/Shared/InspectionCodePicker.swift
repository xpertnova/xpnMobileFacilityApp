import SwiftUI

/// Represents the active picker column in an inspection row.
enum InspectionPickerField: Hashable, Sendable {
    case result
    case action
}

/// Option model for inspection code dropdowns (used across Mobile Ladder and Elevator Inspections).
struct InspectionCodeOption: Identifiable, Equatable, Sendable {
    let id: String
    let code: String
    let title: String
    let isTitleKey: Bool

    init(code: String, title: String) {
        self.id = code
        self.code = code
        self.title = title
        self.isTitleKey = false
    }

    init(code: String, titleKey: String) {
        self.id = code
        self.code = code
        self.title = titleKey
        self.isTitleKey = true
    }
}

/// Reusable inspection code picker matching the Mobile Ladder design across MTFM.
struct InspectionCodePicker: View {
    @Binding var isExpanded: Bool
    let selection: String?
    let options: [InspectionCodeOption]
    var optionsHeight: CGFloat? = nil
    var isEnabled: Bool = true
    var accessibilityLabel: Text = Text("")
    let onSelect: (String) -> Void

    private var resolvedHeight: CGFloat {
        if let optionsHeight {
            return optionsHeight
        }
        return min(CGFloat(max(options.count, 1)) * 50, 300)
    }

    var body: some View {
        Button {
            isExpanded.toggle()
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
        .accessibilityLabel(accessibilityLabel)
        .popover(
            isPresented: $isExpanded,
            attachmentAnchor: .rect(.bounds)
        ) {
            ScrollView {
                LazyVStack(spacing: 0) {
                    ForEach(options) { option in
                        InspectionCodeOptionRow(option: option) {
                            onSelect(option.code)
                            isExpanded = false
                        }
                    }
                }
            }
            .frame(width: 360, height: resolvedHeight, alignment: .top)
            .background(FacilityTheme.surface)
            .presentationCompactAdaptation(.popover)
        }
    }
}

extension InspectionCodePicker {
    init<PickerID: Hashable>(
        picker: PickerID,
        expandedPicker: Binding<PickerID?>,
        selection: String?,
        options: [InspectionCodeOption],
        optionsHeight: CGFloat? = nil,
        isEnabled: Bool = true,
        accessibilityLabel: Text = Text(""),
        onSelect: @escaping (String) -> Void
    ) {
        let isExpandedBinding = Binding<Bool>(
            get: { expandedPicker.wrappedValue == picker },
            set: { isPresented in
                if !isPresented, expandedPicker.wrappedValue == picker {
                    expandedPicker.wrappedValue = nil
                } else if isPresented {
                    expandedPicker.wrappedValue = picker
                }
            }
        )
        self.init(
            isExpanded: isExpandedBinding,
            selection: selection,
            options: options,
            optionsHeight: optionsHeight,
            isEnabled: isEnabled,
            accessibilityLabel: accessibilityLabel,
            onSelect: onSelect
        )
    }
}

struct InspectionCodeOptionRow: View {
    let option: InspectionCodeOption
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 12) {
                Text(option.code)
                    .monospacedDigit()
                    .frame(width: 46, alignment: .leading)

                if option.isTitleKey {
                    Text(LocalizedStringKey(option.title))
                        .frame(maxWidth: .infinity, alignment: .trailing)
                } else {
                    Text(option.title)
                        .frame(maxWidth: .infinity, alignment: .trailing)
                }
            }
            .font(.body)
            .foregroundStyle(FacilityTheme.ink)
            .padding(.horizontal, 20)
            .frame(maxWidth: .infinity, minHeight: 50)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(accessibilityLabelText)
    }

    private var accessibilityLabelText: Text {
        if option.isTitleKey {
            return Text(verbatim: "\(option.code), \(String(localized: String.LocalizationValue(option.title)))")
        } else {
            return Text(verbatim: "\(option.code), \(option.title)")
        }
    }
}
