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
    private static let proposalButtonWidth: CGFloat = 56

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
                        Color.clear.frame(width: Self.proposalButtonWidth, height: 1)
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
                    Text(displayValue.isEmpty ? String(localized: "inspection.masterData.datePlaceholder") : displayValue)
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
        let isEnabled = model.isProposalAvailable(for: characteristic)
        let hasProposal = !model.proposal(for: characteristic).isEmpty
        return Button {
            model.proposalCharacteristicID = characteristic.name
        } label: {
            Image(systemName: hasProposal ? "square.and.pencil.circle.fill" : "square.and.pencil")
                .font(.title3)
                .foregroundStyle(isEnabled ? FacilityTheme.blue : .secondary)
                .frame(width: Self.proposalButtonWidth, height: 48)
                .briefingFieldChrome(invalid: false, isDisabled: !isEnabled)
        }
        .buttonStyle(.plain)
        .disabled(!isEnabled)
        .accessibilityLabel(Text("inspection.masterData.proposal.edit"))
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

/// `VorschlagPopover.fragment.xml` as a centered, modal editor: the title
/// bar, the read-only "Vorgeschlagene Werte" token box (tapping the token
/// copies it into the input), the required "Neuer Vorschlag" input (at most
/// 80 characters) and the Cancel / Save footer. Presented over the whole
/// inspection screen like `NotificationCommentEditorOverlay`.
struct EquipmentMasterDataProposalOverlay: View {
    let fieldTitle: String
    /// The last proposal for this field, if any. The legacy `Tokenizer` is
    /// hidden when there is nothing to show.
    let lastProposal: String?
    let cancel: () -> Void
    let save: (String) -> Void
    @State private var text: String
    @FocusState private var isFocused: Bool

    init(
        fieldTitle: String,
        initialText: String,
        lastProposal: String?,
        cancel: @escaping () -> Void,
        save: @escaping (String) -> Void
    ) {
        self.fieldTitle = fieldTitle
        self.lastProposal = lastProposal
        self.cancel = cancel
        self.save = save
        _text = State(initialValue: String(initialText.prefix(80)))
    }

    var body: some View {
        ZStack {
            Color.black.opacity(0.14)
                .ignoresSafeArea()
                .onTapGesture(perform: cancel)

            VStack(spacing: 0) {
                VStack(spacing: 3) {
                    Text("vorschlagPopover.title")
                        .font(.headline)
                        .foregroundStyle(FacilityTheme.ink)
                    Text(verbatim: fieldTitle)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 16)
                .padding(.horizontal, 22)

                Divider()

                VStack(alignment: .leading, spacing: 16) {
                    if let lastProposal, !lastProposal.isEmpty {
                        SafetyFormField("vorschlag.history") {
                            HStack(spacing: 8) {
                                Button { text = String(lastProposal.prefix(80)) } label: {
                                    Text(verbatim: lastProposal)
                                        .font(.body)
                                        .foregroundStyle(FacilityTheme.ink)
                                        .lineLimit(1)
                                        .padding(.horizontal, 10)
                                        .frame(minHeight: 34)
                                        .background(Color(white: 0.96), in: RoundedRectangle(cornerRadius: 6, style: .continuous))
                                        .overlay {
                                            RoundedRectangle(cornerRadius: 6, style: .continuous)
                                                .stroke(.gray.opacity(0.4))
                                        }
                                }
                                .buttonStyle(.plain)
                                .accessibilityHint(Text("vorschlag.new"))
                                Spacer(minLength: 0)
                            }
                            .briefingFieldChrome(invalid: false, isDisabled: true)
                        }
                    }

                    SafetyFormField("vorschlag.new", required: true) {
                        TextField("", text: Binding(get: { text }, set: { text = String($0.prefix(80)) }))
                            .focused($isFocused)
                            .foregroundStyle(FacilityTheme.ink)
                            .briefingFieldChrome(invalid: false)
                    }
                }
                .padding(22)

                Divider()

                HStack(spacing: 28) {
                    Spacer()
                    Button("common.cancel", action: cancel)
                        .frame(minHeight: 44)
                    Button("inspection.masterData.proposal.save") { save(text) }
                        .fontWeight(.semibold)
                        .frame(minHeight: 44)
                }
                .foregroundStyle(FacilityTheme.blue)
                .padding(.horizontal, 22)
                .padding(.vertical, 8)
            }
            .facilityDialogFrame(width: 560, padding: 0)
            .background(.white, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .stroke(.gray.opacity(0.28))
            }
            .shadow(color: Color.black.opacity(0.20), radius: 26, y: 12)
            .accessibilityAddTraits(.isModal)
        }
        .onAppear { isFocused = true }
    }
}
