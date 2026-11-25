import SwiftUI

/// The class-characteristics rows of a shared equipment inspection: one
/// labelled row per characteristic with the control `_buildHeaderForm` builds
/// for it, plus the proposal button next to value lists that offer
/// "Pflege durch Admin". Controls come from the shared form components.
struct EquipmentMasterDataFields: View {
    @Bindable var model: EquipmentInspectionViewModel
    @State private var presentedDropdownID: String?
    @State private var presentedDateID: String?
    @Environment(\.facilityLayout) private var layout

    /// Narrower on a compact window, where the value controls need the room.
    private var labelWidth: CGFloat { layout.isCompact ? 170 : 220 }

    private var reservesProposalColumn: Bool {
        model.elevatorAssetCharacteristics.contains(where: \.offersProposal)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            ForEach(model.elevatorAssetCharacteristics) { characteristic in
                HStack(alignment: .center, spacing: 10) {
                    field(for: characteristic)
                    if characteristic.offersProposal {
                        proposalButton(for: characteristic)
                    } else if reservesProposalColumn {
                        Color.clear.frame(width: MasterDataProposalButton.width, height: 1)
                    }
                }
            }
        }
        .frame(maxWidth: 880, alignment: .leading)
    }

    @ViewBuilder
    private func field(for characteristic: ElevatorAssetCharacteristic) -> some View {
        switch characteristic.control {
        case .singleSelect, .multiSelect:
            FacilityDropdownField(
                label: Text(verbatim: characteristic.title),
                placeholder: "inspection.masterData.choose",
                iconName: "list.bullet",
                options: characteristic.selectableOptions.map {
                    FacilityDropdownOption(id: $0.code, title: $0.text)
                },
                selection: model.masterDataSelection(for: characteristic),
                allowsMultipleSelection: characteristic.control == .multiSelect,
                isRequired: characteristic.isRequired,
                isEnabled: model.canEditCharacteristic(characteristic),
                isInvalid: model.isMasterDataInvalid(characteristic),
                labelPlacement: .leading(width: labelWidth),
                isPresented: presentation($presentedDropdownID, for: characteristic),
                onSelect: { model.selectMasterDataOption($0.id, for: characteristic) }
            )
        case .date:
            dateField(for: characteristic)
        case .number:
            textField(for: characteristic, isNumber: true)
        case .text:
            textField(for: characteristic, isNumber: false)
        }
    }

    private func textField(for characteristic: ElevatorAssetCharacteristic, isNumber: Bool) -> some View {
        let isEnabled = model.canEditCharacteristic(characteristic)
        return SafetyFormField(
            label: Text(verbatim: characteristic.title),
            required: characteristic.isRequired,
            labelPlacement: .leading(width: labelWidth)
        ) {
            HStack(spacing: 8) {
                TextField(
                    "",
                    text: Binding(
                        get: { model.masterDataValue(for: characteristic) },
                        set: { newValue in
                            if isNumber {
                                model.setMasterDataNumber(newValue, for: characteristic)
                            } else {
                                model.setMasterDataText(newValue, for: characteristic)
                            }
                        }
                    )
                )
                .keyboardType(isNumber ? .decimalPad : .default)
                .textInputAutocapitalization(characteristic.isCaseSensitive ? .sentences : .characters)
                .autocorrectionDisabled()
                .foregroundStyle(FacilityTheme.ink)
                .disabled(!isEnabled)

                if !characteristic.unit.isEmpty {
                    Text(verbatim: characteristic.unit)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
            }
            .briefingFieldChrome(invalid: model.isMasterDataInvalid(characteristic), isDisabled: !isEnabled)
        }
    }

    private func dateField(for characteristic: ElevatorAssetCharacteristic) -> some View {
        let isEnabled = model.canEditCharacteristic(characteristic)
        let displayValue = EquipmentMasterDataRules.displayValue(
            for: characteristic,
            value: model.masterDataValue(for: characteristic)
        )
        let isPresented = presentation($presentedDateID, for: characteristic)
        return SafetyFormField(
            label: Text(verbatim: characteristic.title),
            required: characteristic.isRequired,
            labelPlacement: .leading(width: labelWidth)
        ) {
            Button {
                isPresented.wrappedValue = true
            } label: {
                HStack(spacing: 12) {
                    Text(displayValue.isEmpty ? String(localized: "inspection.masterData.datePlaceholder", bundle: .appLanguage) : displayValue)
                        .foregroundStyle(displayValue.isEmpty ? .secondary : FacilityTheme.ink)
                    Spacer(minLength: 0)
                    Image(systemName: "calendar")
                        .foregroundStyle(isEnabled ? FacilityTheme.blue : .secondary)
                }
                .briefingFieldChrome(invalid: model.isMasterDataInvalid(characteristic), isDisabled: !isEnabled)
            }
            .buttonStyle(.plain)
            .disabled(!isEnabled)
            .facilityPopover(isPresented: isPresented, arrowEdge: .top) {
                VStack(alignment: .leading, spacing: 12) {
                    DatePicker(
                        "",
                        selection: Binding(
                            get: { model.masterDataDate(for: characteristic) ?? .now },
                            set: { model.setMasterDataDate($0, for: characteristic) }
                        ),
                        displayedComponents: .date
                    )
                    .datePickerStyle(.graphical)
                    .labelsHidden()

                    HStack {
                        Button("inspection.masterData.date.clear", role: .destructive) {
                            model.setMasterDataDate(nil, for: characteristic)
                            isPresented.wrappedValue = false
                        }
                        Spacer()
                        Button("inspection.masterData.date.done") {
                            if model.masterDataDate(for: characteristic) == nil {
                                model.setMasterDataDate(.now, for: characteristic)
                            }
                            isPresented.wrappedValue = false
                        }
                        .buttonStyle(.borderedProminent)
                        .tint(FacilityTheme.accent)
                    }
                    .frame(minHeight: 44)
                }
                .padding(16)
                .frame(width: 360)
                .background(FacilityTheme.surface)
            }
        }
    }

    private func proposalButton(for characteristic: ElevatorAssetCharacteristic) -> some View {
        MasterDataProposalButton(
            isEnabled: model.isProposalAvailable(for: characteristic),
            hasProposal: !model.proposal(for: characteristic).isEmpty
        ) {
            model.proposalCharacteristicID = characteristic.name
        }
    }

    private func presentation(
        _ state: Binding<String?>,
        for characteristic: ElevatorAssetCharacteristic
    ) -> Binding<Bool> {
        Binding(
            get: { state.wrappedValue == characteristic.name },
            set: { isPresented in
                if isPresented {
                    state.wrappedValue = characteristic.name
                } else if state.wrappedValue == characteristic.name {
                    state.wrappedValue = nil
                }
            }
        )
    }
}
