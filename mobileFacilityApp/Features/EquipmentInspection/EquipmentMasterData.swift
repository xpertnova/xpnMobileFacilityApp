import Foundation

/// The class-characteristics header of a shared equipment inspection, traced
/// from the legacy `HeaderFormBuilder.js`: `_buildHeaderForm` (controls),
/// `onChangeHeader` (stored values), `validateMasterData` (close validation),
/// `checkMasterDataChange` / `_updateClobData` / `runSetMasterdata4Header`
/// (the `TO_T0266` / `TO_T0265` write) and the `Vorschlag` popover
/// (`TO_T0211` proposals).

/// The two special value-list entries of `util.constanten`
/// (`constSTAMMDATEN_ADMIN`, `constSTAMMDATEN_UNKNOWN`).
enum EquipmentMasterDataCatalog {
    static let adminKey = "PFLEGE DURCH ADMIN"
    static let adminText = "Pflege durch Admin"
    static let unknownText = "nicht bekannt"

    static func isAdmin(_ option: ElevatorInspectionValueOption) -> Bool {
        matches(option.text, adminText) || matches(option.code, adminKey)
    }

    static func isUnknown(_ option: ElevatorInspectionValueOption) -> Bool {
        matches(option.text, unknownText)
    }

    /// `_buildHeaderForm` adds the regular entries in SAP order, then calls
    /// `insertItem(unknown, -1)` and `insertItem(admin, -1)`. UI5 clamps a
    /// negative index to 0, so both land on top: "Pflege durch Admin" first,
    /// "nicht bekannt" second.
    static func ordered(_ options: [ElevatorInspectionValueOption]) -> [ElevatorInspectionValueOption] {
        options.filter(isAdmin)
            + options.filter(isUnknown)
            + options.filter { !isAdmin($0) && !isUnknown($0) }
    }

    private static func matches(_ value: String, _ constant: String) -> Bool {
        value.trimmingCharacters(in: .whitespacesAndNewlines).uppercased() == constant.uppercased()
    }
}

/// The control `_buildHeaderForm` builds for a characteristic.
enum EquipmentMasterDataControl: Equatable, Sendable {
    /// `sap.m.ComboBox` — a value list with `ATEIN == "X"`.
    case singleSelect
    /// `sap.m.MultiComboBox` — a value list without `ATEIN`.
    case multiSelect
    /// `sap.m.DatePicker` — `ATFOR == "DATE"`.
    case date
    /// `NbpmNumberInput` — `ATFOR == "NUM"` with an `ATSCH` template.
    case number
    /// `sap.m.Input`, upper-cased unless `ATKLE == "X"`.
    case text
}

extension ElevatorAssetCharacteristic {
    var control: EquipmentMasterDataControl {
        if !selectableOptions.isEmpty {
            return allowsMultipleValues ? .multiSelect : .singleSelect
        }
        switch format.uppercased() {
        case "DATE": return .date
        case "NUM" where !template.isEmpty: return .number
        default: return .text
        }
    }

    /// `_setIDNUMMERFalse` keeps `…_IDNUMMER` dropdowns read-only.
    var isLockedIdentifier: Bool {
        control == .singleSelect && name.uppercased().hasSuffix("_IDNUMMER")
    }

    /// The value list offers "Pflege durch Admin", so the field carries the
    /// proposal button.
    var offersProposal: Bool {
        selectableOptions.contains(where: EquipmentMasterDataCatalog.isAdmin)
    }

    /// Longest text a field accepts (`ANZST`, `0` = unlimited).
    var maximumLength: Int? {
        digits > 0 ? digits : nil
    }
}

/// Snapshot of the cached master record, kept so an edited header can be
/// written back as the whole `JSOBJECT` like `runSetMasterdata4Header` does.
struct EquipmentMasterRecord: Codable, Equatable, Sendable {
    /// `T0281.EQUNR`. Empty when the notification is on a technical place,
    /// which makes the write a `TO_T0265` row (`isEquip()`).
    let equipmentID: String
    let functionalLocationID: String
    /// Class whose `T_CLOBJDAT` holds the values (`masterDataQuery.CLASS`).
    let className: String
    /// Decoded `FELDWERT` of the `FROM_T0266` / `FROM_T0265` row.
    let payloadJSON: String

    var isEquipment: Bool { !equipmentID.isEmpty }
}

/// A header characteristic as posted to `TO_T0283`
/// (`_addItemToT0283(ATNAM, ATBEZ)` plus `setUIElementValue`).
struct EquipmentMasterDataHeaderValue: Codable, Equatable, Sendable {
    let elementID: String
    let label: String
    let value: String
}

/// Header state saved with the offline inspection draft.
struct EquipmentMasterDataDraft: Codable, Equatable, Sendable {
    /// Current value per `ATNAM` in the transport format of its control.
    var values: [String: String]
    /// `Vorschlag` text per `ATNAM`.
    var proposals: [String: String]
    var headerValues: [EquipmentMasterDataHeaderValue]
    var equipmentID: String
    var functionalLocationID: String
    /// Updated master record for `TO_T0266` / `TO_T0265`. Set only when the
    /// inspection is closed and the characteristics changed
    /// (`checkMasterDataChange`).
    var updatedMasterPayloadJSON: String?
}

enum EquipmentMasterDataRules {
    /// Values the header starts with. `_buildHeaderForm` maps SAP's undefined
    /// marker `?` to an empty value and stores a dropdown by its key even when
    /// the record holds the text.
    static func initialValues(for data: ElevatorAssetData) -> [String: String] {
        data.characteristics.reduce(into: [:]) { result, characteristic in
            var value = data.values[characteristic.name]?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            if value == "?" { value = "" }
            if characteristic.control == .singleSelect,
               let option = option(matching: value, in: characteristic) {
                value = option.code
            }
            result[characteristic.name] = value
        }
    }

    /// Selected option codes of a dropdown value.
    static func selectedCodes(for characteristic: ElevatorAssetCharacteristic, value: String) -> Set<String> {
        let parts = characteristic.control == .multiSelect ? splitValues(value) : [value]
        return Set(parts.compactMap { option(matching: $0, in: characteristic)?.code })
    }

    /// `true` when the dropdown value holds "Pflege durch Admin".
    static func selectsAdmin(_ characteristic: ElevatorAssetCharacteristic, value: String) -> Bool {
        let codes = selectedCodes(for: characteristic, value: value)
        return characteristic.selectableOptions.contains {
            EquipmentMasterDataCatalog.isAdmin($0) && codes.contains($0.code)
        }
    }

    /// Readable value for the screen and the PDF (`addMasterDataToPdf`):
    /// option texts, `dd.MM.yyyy` dates, the stored text otherwise.
    static func displayValue(for characteristic: ElevatorAssetCharacteristic, value rawValue: String) -> String {
        let value = rawValue.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !value.isEmpty, value != "?" else { return "" }
        if characteristic.control == .date, let date = date(fromSAP: value) {
            return displayDateFormatter.string(from: date)
        }
        let parts = characteristic.allowsMultipleValues ? splitValues(value) : [value]
        return parts.map { part in
            (option(matching: part, in: characteristic) ?? characteristic.options.first {
                $0.code.caseInsensitiveCompare(part) == .orderedSame
                    || $0.text.caseInsensitiveCompare(part) == .orderedSame
            })?.text ?? part
        }
        .joined(separator: characteristic.allowsMultipleValues ? "; " : "")
    }

    // MARK: Input normalization (`onChangeHeader`, `onLiveChangeToUpperCase`)

    static func normalizedText(_ text: String, for characteristic: ElevatorAssetCharacteristic) -> String {
        var value = characteristic.isCaseSensitive ? text : text.uppercased()
        if let limit = characteristic.maximumLength, value.count > limit {
            value = String(value.prefix(limit))
        }
        return value
    }

    /// Keeps the typed number in its transport form: digits with a `.`
    /// decimal separator, as `NumberFormat.parse` returns it.
    static func normalizedNumber(_ text: String) -> String {
        var result = ""
        var hasSeparator = false
        for character in text {
            if character.isASCII, character.isNumber {
                result.append(character)
            } else if (character == "," || character == "."), !hasSeparator {
                hasSeparator = true
                result.append(".")
            } else if character == "-", result.isEmpty {
                result.append(character)
            }
        }
        return result
    }

    static func sapDate(_ date: Date) -> String {
        sapDateFormatter.string(from: date)
    }

    /// Reads `yyyyMMdd` (the DatePicker `valueFormat`) and also `dd.MM.yyyy`,
    /// which some cached records carry.
    static func date(fromSAP value: String) -> Date? {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return sapDateFormatter.date(from: trimmed) ?? displayDateFormatter.date(from: trimmed)
    }

    // MARK: Validation (`validateMasterData`)

    /// Characteristics that block closing. A field is only checked while it
    /// is editable; dropdowns always need a valid value, and a
    /// "Pflege durch Admin" selection needs a proposal.
    static func invalidCharacteristicIDs(
        characteristics: [ElevatorAssetCharacteristic],
        values: [String: String],
        proposals: [String: String],
        isEditable: (ElevatorAssetCharacteristic) -> Bool
    ) -> Set<String> {
        Set(characteristics.compactMap { characteristic -> String? in
            guard isEditable(characteristic) else { return nil }
            let value = values[characteristic.name]?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            let hasProposal = !(proposals[characteristic.name]?
                .trimmingCharacters(in: .whitespacesAndNewlines) ?? "").isEmpty
            switch characteristic.control {
            case .number:
                guard characteristic.isRequired else { return nil }
                return value.isEmpty || value == "?" || !isValidNumber(value, for: characteristic)
                    ? characteristic.name : nil
            case .text:
                return characteristic.isRequired && (value.isEmpty || value == "?") ? characteristic.name : nil
            case .date:
                return characteristic.isRequired && date(fromSAP: value) == nil ? characteristic.name : nil
            case .singleSelect, .multiSelect:
                if selectedCodes(for: characteristic, value: value).isEmpty { return characteristic.name }
                if selectsAdmin(characteristic, value: value) && !hasProposal { return characteristic.name }
                return nil
            }
        })
    }

    /// `FormValidator.isNumber`: the integer part fits the `ATSCH` template
    /// (or `ANZST`) and the value parses.
    static func isValidNumber(_ value: String, for characteristic: ElevatorAssetCharacteristic) -> Bool {
        let integerLimit: Int
        if !characteristic.template.isEmpty {
            integerLimit = characteristic.template.split(separator: ".", omittingEmptySubsequences: false)
                .first.map(\.count) ?? characteristic.digits
        } else {
            integerLimit = characteristic.digits
        }
        let integerPart = value.split(separator: ".", omittingEmptySubsequences: false).first ?? ""
        if integerLimit > 0, integerPart.count > integerLimit { return false }
        return Double(value) != nil
    }

    // MARK: Master-data write (`checkMasterDataChange`, `_updateClobData`)

    /// `true` when a characteristic's set of values differs from the record,
    /// compared without case like `checkMasterDataChange`.
    static func hasChanges(original: [String: String], current: [String: String]) -> Bool {
        !changedNames(original: original, current: current).isEmpty
    }

    static func changedNames(original: [String: String], current: [String: String]) -> Set<String> {
        Set(current.compactMap { name, value in
            let old = Set(splitValues(original[name] ?? "").map { $0.uppercased() })
            let new = Set(splitValues(value).map { $0.uppercased() })
            return old == new ? nil : name
        })
    }

    /// The record with the changed characteristics replaced in the class's
    /// `T_CLOBJDAT` and `MANDT_TO` set, or `nil` when nothing changed or the
    /// record cannot be read.
    static func updatedMasterPayloadJSON(
        record: EquipmentMasterRecord,
        characteristics: [ElevatorAssetCharacteristic],
        original: [String: String],
        current: [String: String],
        client: String
    ) -> String? {
        let changed = changedNames(original: original, current: current)
        guard !changed.isEmpty,
              let data = record.payloadJSON.data(using: .utf8),
              var payload = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] else {
            return nil
        }

        let classKey = key(named: record.isEquipment ? "T_CLASS_EQ" : "T_CLASS_TP", in: payload)
        var classes = (payload[classKey] as? [Any])?.compactMap { $0 as? [String: Any] } ?? []
        guard !classes.isEmpty else { return nil }
        let classIndex = classes.firstIndex {
            let name = stringValue($0[key(named: "CLASS", in: $0)])
            return !record.className.isEmpty && name.caseInsensitiveCompare(record.className) == .orderedSame
        } ?? 0

        var classData = classes[classIndex]
        let rowsKey = key(named: "T_CLOBJDAT", in: classData)
        let existingRows = (classData[rowsKey] as? [Any])?.compactMap { $0 as? [String: Any] } ?? []
        let characteristicsByName = Dictionary(
            characteristics.map { ($0.name.uppercased(), $0) },
            uniquingKeysWith: { first, _ in first }
        )

        var rows = existingRows.filter { row in
            !changed.contains { $0.caseInsensitiveCompare(stringValue(row[key(named: "ATNAM", in: row)])) == .orderedSame }
        }
        for name in changed.sorted() {
            let characteristic = characteristicsByName[name.uppercased()]
            let values = current[name].map { $0.split(separator: ";", omittingEmptySubsequences: false).map(String.init) } ?? [""]
            for value in values {
                rows.append([
                    "MANDT": "",
                    "POSNR": characteristic.map { String($0.position) } ?? "",
                    "ATNAM": name,
                    "SMBEZ": characteristic?.title ?? "",
                    "AUSP1": value,
                    "UNIT_T_EXT": characteristic?.unit ?? ""
                ])
            }
        }
        classData[rowsKey] = rows
        classes[classIndex] = classData
        payload[classKey] = classes
        payload["MANDT_TO"] = client

        guard let encoded = try? JSONSerialization.data(withJSONObject: payload, options: [.sortedKeys]) else {
            return nil
        }
        return String(data: encoded, encoding: .utf8)
    }

    // MARK: Helpers

    static func splitValues(_ value: String) -> [String] {
        value.split(separator: ";")
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
    }

    private static func option(
        matching value: String,
        in characteristic: ElevatorAssetCharacteristic
    ) -> ElevatorInspectionValueOption? {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        let options = characteristic.selectableOptions
        return options.first { $0.code == trimmed || $0.text == trimmed }
            ?? options.first {
                $0.code.caseInsensitiveCompare(trimmed) == .orderedSame
                    || $0.text.caseInsensitiveCompare(trimmed) == .orderedSame
            }
    }

    private static func key(named name: String, in dictionary: [String: Any]) -> String {
        dictionary.keys.first { $0.caseInsensitiveCompare(name) == .orderedSame } ?? name
    }

    private static func stringValue(_ value: Any?) -> String {
        switch value {
        case let string as String: string.trimmingCharacters(in: .whitespacesAndNewlines)
        case let number as NSNumber: number.stringValue
        default: ""
        }
    }

    private static let sapDateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = .current
        formatter.dateFormat = "yyyyMMdd"
        formatter.isLenient = false
        return formatter
    }()

    private static let displayDateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = .current
        formatter.dateFormat = "dd.MM.yyyy"
        formatter.isLenient = false
        return formatter
    }()
}
