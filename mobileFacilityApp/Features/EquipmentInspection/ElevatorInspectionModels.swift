import Foundation

/// Value option representing an SAP selection item from DBOX metadata.
struct ElevatorInspectionValueOption: Codable, Equatable, Hashable, Identifiable, Sendable {
    let code: String
    let text: String

    var id: String { code }

    init(code: String, text: String) {
        self.code = code
        self.text = text
    }
}

/// A read-only SAP classification characteristic for the inspected elevator.
///
/// The Cordova TFM2 form renders these above the inspection table from the
/// equipment or functional-location master-data cache. Passenger and freight
/// elevators are deliberately read-only in that form, so this model does not
/// imply an SAP master-data write.
struct ElevatorAssetCharacteristic: Codable, Equatable, Hashable, Identifiable, Sendable {
    let position: Int
    let name: String
    let title: String
    let unit: String
    let isRequired: Bool
    let isNumeric: Bool
    let allowsMultipleValues: Bool
    /// Every known spelling of a value, including BAPI descriptions and
    /// yes/no synonyms, used to show a stored value as text.
    let options: [ElevatorInspectionValueOption]
    /// The `T_CHARVAL` value list the header dropdown offers, in legacy order.
    var selectableOptions: [ElevatorInspectionValueOption] = []
    /// `ATFOR` (`CHAR`, `NUM`, `DATE`, …).
    var format: String = ""
    /// `ANZST` — number of characters or digits.
    var digits: Int = 0
    /// `ANZDZ` — decimal places.
    var decimals: Int = 0
    /// `ATSCH` — number template such as `____.__`.
    var template: String = ""
    /// `ATKLE == "X"` — text is kept as typed instead of upper-cased.
    var isCaseSensitive: Bool = false

    var id: String { name }
}

/// The cached master-data classification associated with a shared equipment
/// inspection (TFM2 elevator, TFM4 fixed ladder, TFM6 hold-open system, TFM8
/// roof system).
struct ElevatorAssetData: Equatable, Sendable {
    let equipmentType: String
    let className: String
    /// Class description (`TXTBZ`). The legacy report uses it as the form
    /// title (`klassenMerkmale.TXTBZ` in `buildPDF`).
    var classTitle: String = ""
    let characteristics: [ElevatorAssetCharacteristic]
    let values: [String: String]
    /// Cached master record the header was read from. `nil` when there is
    /// nothing to write back to (demo data without a record, for example).
    var masterRecord: EquipmentMasterRecord?

    static let empty = Self(equipmentType: "", className: "", characteristics: [], values: [:])

    /// `HeaderFormBuilder._isEditable`: passenger and freight elevators keep
    /// their characteristics read-only; every other equipment type can be
    /// maintained during the inspection.
    var isEditable: Bool {
        !["TFMPERS", "TFMLAST"].contains(equipmentType.uppercased())
    }
}

/// Narrow, read-only boundary for the legacy T0263/T0265/T0266 cache data.
///
/// Implementations resolve the class for the notification's
/// `equipmentInspectionForm`, so one provider serves every shared equipment
/// inspection.
protocol ElevatorAssetDataProviding: Sendable {
    func loadElevatorAssetData(for notification: SAPNotificationSummary) async throws -> ElevatorAssetData
}

struct UnavailableElevatorAssetDataProvider: ElevatorAssetDataProviding {
    func loadElevatorAssetData(for notification: SAPNotificationSummary) async throws -> ElevatorAssetData {
        throw SAPReadError.serviceUnavailable
    }
}

/// Isolated, deterministic source used only by the app's Demo composition.
struct DemoElevatorAssetDataProvider: ElevatorAssetDataProviding {
    func loadElevatorAssetData(for notification: SAPNotificationSummary) async throws -> ElevatorAssetData {
        switch notification.equipmentInspectionForm {
        case .fixedLadder: return Self.fixedLadderData
        case .holdOpenSystem: return Self.holdOpenSystemData
        case .roofSystem: return Self.roofSystemData
        case .elevator, nil: break
        }
        if notification.equipmentInspectionForm == .subdistribution {
            return Self.subdistributionData
        }
        let yes = ElevatorInspectionValueOption(code: "X", text: String(localized: "elevator.assetData.demo.yes"))
        let passengerLift = ElevatorInspectionValueOption(
            code: "PERS",
            text: String(localized: "elevator.assetData.demo.passengerLift")
        )
        let characteristics = [
            ElevatorAssetCharacteristic(
                position: 1, name: "DEMO_ELEVATOR_STOPS",
                title: String(localized: "elevator.assetData.field.stops"), unit: "ST",
                isRequired: false, isNumeric: true, allowsMultipleValues: false, options: []
            ),
            ElevatorAssetCharacteristic(
                position: 2, name: "DEMO_ELEVATOR_ACCESS_POINTS",
                title: String(localized: "elevator.assetData.field.accessPoints"), unit: "ST",
                isRequired: false, isNumeric: true, allowsMultipleValues: false, options: []
            ),
            ElevatorAssetCharacteristic(
                position: 3, name: "DEMO_ELEVATOR_FIRE_CONTROL",
                title: String(localized: "elevator.assetData.field.fireControl"), unit: "",
                isRequired: false, isNumeric: false, allowsMultipleValues: false, options: [yes]
            ),
            ElevatorAssetCharacteristic(
                position: 4, name: "DEMO_ELEVATOR_USAGE",
                title: String(localized: "elevator.assetData.field.usage"), unit: "",
                isRequired: false, isNumeric: false, allowsMultipleValues: false, options: []
            ),
            ElevatorAssetCharacteristic(
                position: 5, name: "DEMO_ELEVATOR_NUMBER",
                title: String(localized: "elevator.assetData.field.number"), unit: "",
                isRequired: false, isNumeric: false, allowsMultipleValues: false, options: []
            ),
            ElevatorAssetCharacteristic(
                position: 6, name: "DEMO_ELEVATOR_EMERGENCY_CALL",
                title: String(localized: "elevator.assetData.field.emergencyCall"), unit: "",
                isRequired: false, isNumeric: false, allowsMultipleValues: false, options: [yes]
            ),
            ElevatorAssetCharacteristic(
                position: 7, name: "DEMO_ELEVATOR_TYPE",
                title: String(localized: "elevator.assetData.field.type"), unit: "",
                isRequired: false, isNumeric: false, allowsMultipleValues: false, options: [passengerLift]
            ),
            ElevatorAssetCharacteristic(
                position: 8, name: "DEMO_ELEVATOR_CAPACITY",
                title: String(localized: "elevator.assetData.field.capacity"), unit: "kg",
                isRequired: false, isNumeric: true, allowsMultipleValues: false, options: []
            ),
            ElevatorAssetCharacteristic(
                position: 9, name: "DEMO_ELEVATOR_TRAVEL_HEIGHT",
                title: String(localized: "elevator.assetData.field.travelHeight"), unit: "m",
                isRequired: false, isNumeric: true, allowsMultipleValues: false, options: []
            )
        ]
        return ElevatorAssetData(
            equipmentType: "TFMPERS",
            className: "TFMPERS",
            characteristics: characteristics,
            values: [
                "DEMO_ELEVATOR_STOPS": "5",
                "DEMO_ELEVATOR_ACCESS_POINTS": "5",
                "DEMO_ELEVATOR_FIRE_CONTROL": "X",
                "DEMO_ELEVATOR_USAGE": String(localized: "elevator.assetData.demo.passengerTransport"),
                "DEMO_ELEVATOR_NUMBER": "?",
                "DEMO_ELEVATOR_EMERGENCY_CALL": "X",
                "DEMO_ELEVATOR_TYPE": "PERS",
                "DEMO_ELEVATOR_CAPACITY": "630",
                "DEMO_ELEVATOR_TRAVEL_HEIGHT": "165.0"
            ]
        )
    }

    private static var fixedLadderData: ElevatorAssetData {
        let yesNo = [
            ElevatorInspectionValueOption(code: "X", text: String(localized: "elevator.assetData.demo.yes")),
            ElevatorInspectionValueOption(code: "N", text: String(localized: "holdOpenSystem.masterData.demo.no"))
        ]
        let characteristics = [
            ElevatorAssetCharacteristic(
                position: 1, name: "DEMO_LADDER_HEIGHT",
                title: String(localized: "fixedLadder.masterData.demo.height"), unit: "m",
                isRequired: true, isNumeric: true, allowsMultipleValues: false, options: [],
                format: "NUM", digits: 5, decimals: 2, template: "___.__"
            ),
            ElevatorAssetCharacteristic(
                position: 2, name: "DEMO_LADDER_MATERIAL",
                title: String(localized: "fixedLadder.masterData.demo.material"), unit: "",
                isRequired: false, isNumeric: false, allowsMultipleValues: false, options: [],
                format: "CHAR", digits: 30
            ),
            ElevatorAssetCharacteristic(
                position: 3, name: "DEMO_LADDER_FALL_PROTECTION",
                title: String(localized: "fixedLadder.masterData.demo.fallProtection"), unit: "",
                isRequired: false, isNumeric: false, allowsMultipleValues: false, options: yesNo,
                selectableOptions: yesNo, format: "CHAR"
            ),
            ElevatorAssetCharacteristic(
                position: 4, name: "DEMO_LADDER_BACK_PROTECTION",
                title: String(localized: "fixedLadder.masterData.demo.backProtection"), unit: "",
                isRequired: false, isNumeric: false, allowsMultipleValues: false, options: yesNo,
                selectableOptions: yesNo, format: "CHAR"
            )
        ]
        return ElevatorAssetData(
            equipmentType: "TFMLEITER",
            className: "TFMLEITER",
            classTitle: String(localized: "fixedLadder.inspection.title"),
            characteristics: characteristics,
            values: [
                "DEMO_LADDER_HEIGHT": "12.5",
                "DEMO_LADDER_MATERIAL": String(localized: "fixedLadder.masterData.demo.steel"),
                "DEMO_LADDER_FALL_PROTECTION": "X",
                "DEMO_LADDER_BACK_PROTECTION": "X"
            ]
        )
    }

    private static var subdistributionData: ElevatorAssetData {
        let characteristics = [
            ElevatorAssetCharacteristic(position: 1, name: "DEMO_SUBDISTRIBUTION_NAME", title: String(localized: "subdistribution.masterData.demo.name"), unit: "", isRequired: true, isNumeric: false, allowsMultipleValues: false, options: []),
            ElevatorAssetCharacteristic(position: 2, name: "DEMO_SUBDISTRIBUTION_RCD", title: String(localized: "subdistribution.masterData.demo.rcd"), unit: "", isRequired: false, isNumeric: false, allowsMultipleValues: false, options: []),
            ElevatorAssetCharacteristic(position: 3, name: "DEMO_SUBDISTRIBUTION_CIRCUITS", title: String(localized: "subdistribution.masterData.demo.circuits"), unit: "ST", isRequired: false, isNumeric: true, allowsMultipleValues: false, options: [])
        ]
        return ElevatorAssetData(
            equipmentType: "TFMNSPV", className: "TFMNSPV",
            classTitle: String(localized: "subdistribution.title"),
            characteristics: characteristics,
            values: [
                "DEMO_SUBDISTRIBUTION_NAME": "UV Bürotrakt 1. OG",
                "DEMO_SUBDISTRIBUTION_RCD": "FI-Schutzschalter 30 mA",
                "DEMO_SUBDISTRIBUTION_CIRCUITS": "12"
            ]
        )
    }
}

extension DemoElevatorAssetDataProvider {
    /// TFM6 header shaped like a Feststellanlage class: a date, value lists
    /// that start with "Pflege durch Admin" / "nicht bekannt", and one value
    /// list without a stored value.
    fileprivate static var holdOpenSystemData: ElevatorAssetData {
        let unknown = ElevatorInspectionValueOption(code: "NICHT VORHN.", text: EquipmentMasterDataCatalog.unknownText)
        let admin = ElevatorInspectionValueOption(
            code: EquipmentMasterDataCatalog.adminKey,
            text: EquipmentMasterDataCatalog.adminText
        )
        func list(_ entries: [(String, String)]) -> [ElevatorInspectionValueOption] {
            [admin, unknown] + entries.map { ElevatorInspectionValueOption(code: $0.0, text: $0.1) }
        }
        let manufacturers = list([("HERST_A", "Hersteller A"), ("HERST_B", "Hersteller B")])
        let types = list([("RSZ1", "RSZ1"), ("RSZ2", "RSZ2")])
        let approvals = list([("Z-6.5-1001", "Z-6.5-1001"), ("Z-6.5-1002", "Z-6.5-1002")])
        let yesNo = [
            ElevatorInspectionValueOption(code: "X", text: String(localized: "elevator.assetData.demo.yes")),
            ElevatorInspectionValueOption(code: "N", text: String(localized: "holdOpenSystem.masterData.demo.no"))
        ]
        let characteristics = [
            ElevatorAssetCharacteristic(
                position: 1, name: "DEMO_FSA_BUILD_DATE",
                title: String(localized: "holdOpenSystem.masterData.demo.buildDate"), unit: "",
                isRequired: false, isNumeric: false, allowsMultipleValues: false, options: [],
                format: "DATE", digits: 8
            ),
            ElevatorAssetCharacteristic(
                position: 2, name: "DEMO_FSA_MANUFACTURER",
                title: String(localized: "holdOpenSystem.masterData.demo.manufacturer"), unit: "",
                isRequired: true, isNumeric: false, allowsMultipleValues: false, options: manufacturers,
                selectableOptions: manufacturers, format: "CHAR", digits: 30
            ),
            ElevatorAssetCharacteristic(
                position: 3, name: "DEMO_FSA_MANUAL_RELEASE",
                title: String(localized: "holdOpenSystem.masterData.demo.manualRelease"), unit: "",
                isRequired: false, isNumeric: false, allowsMultipleValues: false, options: yesNo,
                selectableOptions: yesNo, format: "CHAR", digits: 1
            ),
            ElevatorAssetCharacteristic(
                position: 4, name: "DEMO_FSA_TYPE",
                title: String(localized: "holdOpenSystem.masterData.demo.type"), unit: "",
                isRequired: false, isNumeric: false, allowsMultipleValues: false, options: types,
                selectableOptions: types, format: "CHAR", digits: 30
            ),
            ElevatorAssetCharacteristic(
                position: 5, name: "DEMO_FSA_APPROVAL",
                title: String(localized: "holdOpenSystem.masterData.demo.approval"), unit: "",
                isRequired: false, isNumeric: false, allowsMultipleValues: false, options: approvals,
                selectableOptions: approvals, format: "CHAR", digits: 30
            )
        ]
        let values = [
            "DEMO_FSA_BUILD_DATE": "19931209",
            "DEMO_FSA_MANUFACTURER": "HERST_A",
            "DEMO_FSA_MANUAL_RELEASE": "",
            "DEMO_FSA_TYPE": "RSZ1",
            "DEMO_FSA_APPROVAL": "Z-6.5-1001"
        ]
        let record: [String: Any] = [
            "EQUNR_TO": "EQ-100036",
            "EQART_TO": "TFMFSA",
            "T_CLASS_EQ": [[
                "CLASS": "TFMFSA",
                "T_CLOBJDAT": values.map { ["ATNAM": $0.key, "AUSP1": $0.value] }
            ]]
        ]
        let recordJSON = (try? JSONSerialization.data(withJSONObject: record, options: [.sortedKeys]))
            .flatMap { String(data: $0, encoding: .utf8) } ?? "{}"
        return ElevatorAssetData(
            equipmentType: "TFMFSA",
            className: "TFMFSA",
            classTitle: String(localized: "holdOpenSystem.inspection.title"),
            characteristics: characteristics,
            values: values,
            masterRecord: EquipmentMasterRecord(
                equipmentID: "EQ-100036",
                functionalLocationID: "UN01-ST01-BG01-TECH-480-FSA1",
                className: "TFMFSA",
                payloadJSON: recordJSON
            )
        )
    }
}

extension DemoElevatorAssetDataProvider {
    /// TFM8 header shaped like a Dachanlagen class: a count, a value list with
    /// "Pflege durch Admin" / "nicht bekannt" and a date.
    fileprivate static var roofSystemData: ElevatorAssetData {
        let unknown = ElevatorInspectionValueOption(code: "NICHT VORHN.", text: EquipmentMasterDataCatalog.unknownText)
        let admin = ElevatorInspectionValueOption(
            code: EquipmentMasterDataCatalog.adminKey,
            text: EquipmentMasterDataCatalog.adminText
        )
        let anchorTypes = [admin, unknown] + [
            ElevatorInspectionValueOption(code: "EINZEL", text: String(localized: "roofSystem.masterData.demo.singleAnchor")),
            ElevatorInspectionValueOption(code: "SEIL", text: String(localized: "roofSystem.masterData.demo.cableSystem"))
        ]
        let characteristics = [
            ElevatorAssetCharacteristic(
                position: 1, name: "DEMO_DACH_ANCHOR_TYPE",
                title: String(localized: "roofSystem.masterData.demo.anchorType"), unit: "",
                isRequired: true, isNumeric: false, allowsMultipleValues: false, options: anchorTypes,
                selectableOptions: anchorTypes, format: "CHAR", digits: 30
            ),
            ElevatorAssetCharacteristic(
                position: 2, name: "DEMO_DACH_ANCHOR_COUNT",
                title: String(localized: "roofSystem.masterData.demo.anchorCount"), unit: "ST",
                isRequired: false, isNumeric: true, allowsMultipleValues: false, options: [],
                format: "NUM", digits: 3, decimals: 0, template: "___"
            ),
            ElevatorAssetCharacteristic(
                position: 3, name: "DEMO_DACH_INSTALLED_ON",
                title: String(localized: "roofSystem.masterData.demo.installedOn"), unit: "",
                isRequired: false, isNumeric: false, allowsMultipleValues: false, options: [],
                format: "DATE", digits: 8
            )
        ]
        let values = [
            "DEMO_DACH_ANCHOR_TYPE": "SEIL",
            "DEMO_DACH_ANCHOR_COUNT": "6",
            "DEMO_DACH_INSTALLED_ON": "20180412"
        ]
        let record: [String: Any] = [
            "EQUNR_TO": "EQ-100048",
            "EQART_TO": "TFMDACH",
            "T_CLASS_EQ": [[
                "CLASS": "TFMDACH",
                "T_CLOBJDAT": values.map { ["ATNAM": $0.key, "AUSP1": $0.value] }
            ]]
        ]
        let recordJSON = (try? JSONSerialization.data(withJSONObject: record, options: [.sortedKeys]))
            .flatMap { String(data: $0, encoding: .utf8) } ?? "{}"
        return ElevatorAssetData(
            equipmentType: "TFMDACH",
            className: "TFMDACH",
            classTitle: String(localized: "roofSystem.inspection.title"),
            characteristics: characteristics,
            values: values,
            masterRecord: EquipmentMasterRecord(
                equipmentID: "EQ-100048",
                functionalLocationID: "UN01-ST01-BG01-TECH-490-DACH1",
                className: "TFMDACH",
                payloadJSON: recordJSON
            )
        )
    }
}

/// Converts the decoded legacy classification and master-data objects into a
/// UI-neutral representation. The caller is responsible for unpacking the
/// `FELDWERT` cache column before calling this method.
enum ElevatorAssetDataDecoder {
    static func decode(
        equipmentType: String,
        classDefinition: [String: Any],
        masterData: [String: Any]
    ) -> ElevatorAssetData? {
        let rawCharacteristics = dictionaries(named: "T_CHARA", in: classDefinition)
        guard !rawCharacteristics.isEmpty else { return nil }

        let className = string(named: "CLASS", in: classDefinition)
            .ifEmpty(string(named: "KLASSE", in: classDefinition))
        let classValues = dictionaries(named: "T_CLASS_EQ", in: masterData)
            + dictionaries(named: "T_CLASS_TP", in: masterData)
        let matchingClass = classValues.first {
            let candidate = string(named: "CLASS", in: $0).ifEmpty(string(named: "KLASSE", in: $0))
            return !className.isEmpty && candidate.caseInsensitiveCompare(className) == .orderedSame
        } ?? classValues.first

        let rawValues = matchingClass.map { dictionaries(named: "T_CLOBJDAT", in: $0) } ?? []
        // `_getHeaderValue` joins the unique, non-empty values of a
        // characteristic with ";", which is how multi-value fields arrive.
        let groupedValues = rawValues.reduce(into: [String: [String]]()) { result, row in
            let name = string(named: "ATNAM", in: row)
            guard !name.isEmpty else { return }
            var value = string(named: "AUSP1", in: row).ifEmpty(string(named: "ATWRT", in: row))
            let unit = string(named: "UNIT_T_EXT", in: row).ifEmpty(string(named: "MSEHI", in: row))
            if !unit.isEmpty, value.hasSuffix(unit) {
                value = String(value.dropLast(unit.count)).trimmingCharacters(in: .whitespaces)
            }
            var existing = result[name] ?? []
            if !value.isEmpty, !existing.contains(value) { existing.append(value) }
            result[name] = existing
        }
        let values = groupedValues.mapValues { $0.joined(separator: ";") }

        let bapiCharRows = matchingClass.map { dictionaries(named: "T_BAPI_CHAR", in: $0) } ?? []
        let rawUnitsByName: [String: String] = rawValues.reduce(into: [:]) { result, row in
            let name = string(named: "ATNAM", in: row)
            let unit = string(named: "UNIT_T_EXT", in: row).ifEmpty(string(named: "UNIT", in: row))
            if !name.isEmpty && !unit.isEmpty {
                result[name.uppercased()] = unit
            }
        }
        let bapiUnitsByName: [String: String] = bapiCharRows.reduce(into: [:]) { result, row in
            let name = string(named: "NAME_CHAR", in: row).ifEmpty(string(named: "ATNAM", in: row))
            let unit = string(named: "UNIT_T_EXT", in: row).ifEmpty(string(named: "UNIT", in: row))
            if !name.isEmpty && !unit.isEmpty {
                result[name.uppercased()] = unit
            }
        }

        let bapiCharValRows = matchingClass.map { dictionaries(named: "T_BAPI_CHAR_VAL", in: $0) } ?? []
        let topLevelOptions = dictionaries(named: "T_CHARVAL", in: classDefinition)

        let characteristics = rawCharacteristics.enumerated().compactMap { index, row -> ElevatorAssetCharacteristic? in
            let name = string(named: "ATNAM", in: row).ifEmpty(string(named: "CHARACTERISTIC", in: row))
            guard !name.isEmpty else { return nil }
            let nestedOptions = dictionaries(named: "T_CHARVAL", in: row)
            let optionRows = nestedOptions.isEmpty
                ? topLevelOptions.filter {
                    string(named: "ATNAM", in: $0).ifEmpty(string(named: "CHARACTERISTIC", in: $0)) == name
                }
                : nestedOptions
            var options = optionRows.compactMap { option -> ElevatorInspectionValueOption? in
                let code = string(named: "ATWRT", in: option).ifEmpty(string(named: "VALUE", in: option))
                guard !code.isEmpty else { return nil }
                let title = string(named: "ATWTB", in: option)
                    .ifEmpty(string(named: "VALUE_TEXT", in: option))
                    .ifEmpty(code)
                return ElevatorInspectionValueOption(code: code, text: title)
            }
            let selectableOptions = EquipmentMasterDataCatalog.ordered(options)

            // Map BAPI value descriptions (e.g., "ROPE" -> "Seil", "PASSENGER ELEVATOR" -> "Personenaufzug")
            let bapiForChar = bapiCharValRows.filter {
                let charName = string(named: "NAME_CHAR", in: $0).ifEmpty(string(named: "ATNAM", in: $0))
                return !charName.isEmpty && charName.caseInsensitiveCompare(name) == .orderedSame
            }
            for bapi in bapiForChar {
                let charValue = string(named: "CHAR_VALUE", in: bapi)
                let descr = string(named: "DESCR_CVAL", in: bapi)
                guard !descr.isEmpty else { continue }
                if let matchedOption = options.first(where: { $0.code.caseInsensitiveCompare(charValue) == .orderedSame }) {
                    if !options.contains(where: { $0.code.caseInsensitiveCompare(descr) == .orderedSame }) {
                        options.append(ElevatorInspectionValueOption(code: descr, text: matchedOption.text))
                    }
                }
            }

            // Map boolean synonyms if available
            if let jaOption = options.first(where: { $0.code.caseInsensitiveCompare("J") == .orderedSame || $0.text.caseInsensitiveCompare("Ja") == .orderedSame }) {
                if !options.contains(where: { $0.code.caseInsensitiveCompare("Yes") == .orderedSame }) {
                    options.append(ElevatorInspectionValueOption(code: "Yes", text: jaOption.text))
                }
            }
            if let neinOption = options.first(where: { $0.code.caseInsensitiveCompare("N") == .orderedSame || $0.text.caseInsensitiveCompare("Nein") == .orderedSame }) {
                if !options.contains(where: { $0.code.caseInsensitiveCompare("No") == .orderedSame }) {
                    options.append(ElevatorInspectionValueOption(code: "No", text: neinOption.text))
                }
            }

            let unit = string(named: "MSEHI", in: row)
                .ifEmpty(string(named: "UNIT", in: row))
                .ifEmpty(rawUnitsByName[name.uppercased()] ?? "")
                .ifEmpty(bapiUnitsByName[name.uppercased()] ?? "")

            return ElevatorAssetCharacteristic(
                position: Int(string(named: "POSNR", in: row)) ?? Int(string(named: "ATINN", in: row)) ?? index,
                name: name,
                title: string(named: "ATBEZ", in: row).ifEmpty(string(named: "TITLE", in: row)).ifEmpty(name),
                unit: unit,
                isRequired: string(named: "ATERF", in: row).ifEmpty(string(named: "PFLICHT", in: row)).uppercased() == "X",
                isNumeric: string(named: "ATFOR", in: row).uppercased() == "NUM",
                allowsMultipleValues: !options.isEmpty && string(named: "ATEIN", in: row).uppercased() != "X",
                options: options,
                selectableOptions: selectableOptions,
                format: string(named: "ATFOR", in: row),
                digits: Int(string(named: "ANZST", in: row)) ?? 0,
                decimals: Int(string(named: "ANZDZ", in: row)) ?? 0,
                template: string(named: "ATSCH", in: row),
                isCaseSensitive: string(named: "ATKLE", in: row).uppercased() == "X"
            )
        }
        guard !characteristics.isEmpty else { return nil }
        return ElevatorAssetData(
            equipmentType: equipmentType,
            className: className,
            classTitle: string(named: "TXTBZ", in: classDefinition),
            characteristics: characteristics.sorted { $0.position < $1.position },
            values: values
        )
    }

    private static func dictionaries(named key: String, in dictionary: [String: Any]) -> [[String: Any]] {
        guard let value = value(named: key, in: dictionary) else { return [] }
        if let dictionaries = value as? [[String: Any]] { return dictionaries }
        if let values = value as? [Any] { return values.compactMap { $0 as? [String: Any] } }
        return []
    }

    private static func string(named key: String, in dictionary: [String: Any]) -> String {
        switch value(named: key, in: dictionary) {
        case let value as String:
            value.trimmingCharacters(in: .whitespacesAndNewlines)
        case let value as NSNumber:
            value.stringValue
        default:
            ""
        }
    }

    private static func value(named key: String, in dictionary: [String: Any]) -> Any? {
        dictionary.first { $0.key.caseInsensitiveCompare(key) == .orderedSame }?.value
    }
}

/// Represents an inspection row derived strictly from SAP `T_PLPOD` and `T_PROPS`.
struct ElevatorInspectionItem: Identifiable, Equatable, Sendable {
    let id: String
    let vornr: String
    let steus: String
    let positionNumber: Int
    let title: String
    let information: String
    let resultElementID: String
    let resultOptions: [ElevatorInspectionValueOption]
    let actionElementID: String?
    let actionOptions: [ElevatorInspectionValueOption]
    let materialElementID: String?
    let commentElementID: String
    /// `USR00 == "FOTO"` rows have no value help but must carry a JPEG before
    /// the notification can be closed (`HeaderFormBuilder.validateFormValues`).
    var requiresPhoto: Bool = false
    /// TFM7's photo documentation must additionally retain its linked note.
    /// Cordova provides that note affordance for every `FOTO` row; the native
    /// TFM7 close contract requires both pieces of documentation.
    var requiresPhotoAndComment: Bool = false
    /// Photo rows have no `Befund` selector and must not be treated as
    /// unanswered inspection results.
    var requiresResult: Bool = true
    /// `LTXA1` of the preceding `USR00 == "HEADER"` / `"U1"` row, rendered as
    /// a group band above this position — the legacy
    /// `Aufzugskontrolle.getGroupHeaderListItem`.
    var groupTitle: String = ""

    var hasAction: Bool { actionElementID != nil && !actionOptions.isEmpty }
    var hasMaterial: Bool { materialElementID != nil }

    /// Returns whether this item's result options represent an exact binary No / Yes choice.
    var isBinaryYesNo: Bool {
        guard resultOptions.count == 2 else { return false }
        let lowerTexts = resultOptions.map { $0.text.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() }
        let lowerCodes = resultOptions.map { $0.code.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() }
        let isGermanNoYes = lowerTexts == ["nein", "ja"] || lowerTexts == ["ja", "nein"]
        let isEnglishNoYes = lowerTexts == ["no", "yes"] || lowerTexts == ["yes", "no"]
        let isCodeNoYes = lowerCodes == ["nein", "ja"] || lowerCodes == ["no", "yes"]
        return isGermanNoYes || isEnglishNoYes || isCodeNoYes
    }
}

/// Status choices for a deficient equipment inspection when closing.
enum ElevatorInspectionStatusDecision: String, Codable, CaseIterable, Identifiable, Sendable {
    case leaveOpen = "MIAR"
    case close = "MMAB"

    var id: String { rawValue }

    var systemStatus: String { rawValue }

    var titleKey: String {
        switch self {
        case .leaveOpen: "elevator.closeDialog.leaveOpen"
        case .close: "elevator.closeDialog.close"
        }
    }
}

/// Defect position representation for the I2 defect handoff flow.
struct ElevatorDefectPosition: Identifiable, Equatable, Sendable {
    let id: String
    let itemNr: Int
    let operation: String
    let title: String
    let longText: String
    let resultCode: String
    let resultText: String
    let actionCode: String
    let actionText: String
    let comment: String
}

/// Offline draft payload of a shared equipment inspection (TFM2, TFM4, TFM6).
///
/// The type and its `.elevatorInspection` work-item case keep their original
/// names because both are persisted in the offline queue.
struct ElevatorInspectionDraftPayload: Codable, Equatable, Sendable {
    var notificationID: String
    /// `EquipmentInspectionForm` code. `nil` for drafts saved before TFM4
    /// existed, which were always TFM2.
    var formCode: String?
    var performedOn: Date
    var elementValues: [String: String]
    var comments: [String: String]
    var materialFlags: [String: Bool]
    var photoAttachments: [NotificationPhotoAttachment]
    var pdfDocumentID: String
    var pdfBytes: Data?
    var outgoingProcessID: String?
    var isClosedLocally: Bool
    var closingSystemStatus: String
    var closingUserStatus: String
    var statusNumber: String
    var isOutOfOperation: Bool?
    var outOfOperationComment: String?
    var notificationSnapshot: OfflineNotificationSnapshot?
    /// Class-characteristics header. `nil` for drafts saved before the header
    /// became editable.
    var masterData: EquipmentMasterDataDraft?

    init(
        notificationID: String,
        performedOn: Date = .now,
        elementValues: [String: String] = [:],
        comments: [String: String] = [:],
        materialFlags: [String: Bool] = [:],
        photoAttachments: [NotificationPhotoAttachment] = [],
        pdfDocumentID: String = UUID().uuidString.uppercased(),
        pdfBytes: Data? = nil,
        outgoingProcessID: String? = nil,
        isClosedLocally: Bool = false,
        closingSystemStatus: String = "MMAB",
        closingUserStatus: String = "",
        statusNumber: String = "1",
        isOutOfOperation: Bool? = nil,
        outOfOperationComment: String? = nil,
        notificationSnapshot: OfflineNotificationSnapshot? = nil,
        formCode: String? = nil,
        masterData: EquipmentMasterDataDraft? = nil
    ) {
        self.notificationID = notificationID
        self.masterData = masterData
        self.formCode = formCode
        self.performedOn = performedOn
        self.elementValues = elementValues
        self.comments = comments
        self.materialFlags = materialFlags
        self.photoAttachments = photoAttachments
        self.pdfDocumentID = pdfDocumentID
        self.pdfBytes = pdfBytes
        self.outgoingProcessID = outgoingProcessID
        self.isClosedLocally = isClosedLocally
        self.closingSystemStatus = closingSystemStatus
        self.closingUserStatus = closingUserStatus
        self.statusNumber = statusNumber
        self.isOutOfOperation = isOutOfOperation
        self.outOfOperationComment = outOfOperationComment
        self.notificationSnapshot = notificationSnapshot
    }
}

/// Cordova-equivalent business logic rules shared by TFM2 and TFM4
/// (`BaseFormController` / `HeaderFormBuilder`).
enum ElevatorInspectionLogic {
    /// Determines whether a position's result/action combination constitutes a defect.
    /// Cordova rules:
    /// - Code "2": Defect
    /// - Code "4": Defect
    /// - Code "3": Defect UNLESS Action code is "8" (resolved on site)
    /// - All other codes ("1", "5", etc.): Normal / Not a defect
    static func isDefective(resultCode: String?, actionCode: String?) -> Bool {
        guard let resultCode = resultCode?.trimmingCharacters(in: .whitespacesAndNewlines),
              !resultCode.isEmpty else { return false }
        switch resultCode {
        case "2", "4":
            return true
        case "3":
            let action = actionCode?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            return action != "8"
        default:
            return false
        }
    }

    static func isDefect(resultCode: String?, actionCode: String?) -> Bool {
        isDefective(resultCode: resultCode, actionCode: actionCode)
    }

    /// Checks if any position in the notification has a defect according to SAP metadata.
    static func hasAnyDefect(
        items: [ElevatorInspectionItem],
        elementValues: [String: String]
    ) -> Bool {
        items.contains { item in
            let result = elementValues[item.resultElementID]
            let action = item.actionElementID.flatMap { elementValues[$0] }
            return isDefective(resultCode: result, actionCode: action)
        }
    }

    /// Checks whether the "All good" action is supported by the SAP metadata.
    /// Returns true only if every checklist position has a valid SAP "1" code in its result options.
    static func canPerformAllGood(items: [ElevatorInspectionItem]) -> Bool {
        guard !items.isEmpty else { return false }
        return items.allSatisfy { item in
            item.resultOptions.contains { $0.code == "1" }
        }
    }

    /// Sets empty result controls to the Cordova OK SAP code ("1").
    /// Never overwrites existing results, actions, material flags, notes, or photos.
    static func applyAllGood(
        items: [ElevatorInspectionItem],
        elementValues: inout [String: String]
    ) {
        guard canPerformAllGood(items: items) else { return }
        for item in items {
            let current = elementValues[item.resultElementID]?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            if current.isEmpty {
                elementValues[item.resultElementID] = "1"
            }
        }
    }

    /// Returns the set of item IDs that lack a valid result value.
    static func unansweredItemIDs(
        items: [ElevatorInspectionItem],
        elementValues: [String: String]
    ) -> Set<String> {
        var missing: Set<String> = []
        for item in items {
            guard item.requiresResult else { continue }
            let val = elementValues[item.id] ?? elementValues[item.resultElementID] ?? ""
            if val.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                missing.insert(item.id)
            }
        }
        return missing
    }

    /// Computes updated user status according to Cordova rules:
    /// - Deficient result adds "Mnot" (unique words)
    /// - Normal result removes "Mnot"
    static func updatedUserStatus(current: String, hasDefect: Bool) -> String {
        var statuses = current.split(whereSeparator: \.isWhitespace).map(String.init)
        statuses.removeAll { $0 == "Mnot" }
        if hasDefect {
            statuses.append("Mnot")
        }
        return statuses.joined(separator: " ")
    }
}

/// Decodes SAP notification payload into structured `ElevatorInspectionItem` list.
enum ElevatorInspectionDecoder {
    static func decodeItems(from rawPayloadJSON: String) -> [ElevatorInspectionItem] {
        guard let data = rawPayloadJSON.data(using: .utf8),
              var payload = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
        else { return [] }

        if value(named: "T_PLPOD", in: payload) == nil {
            let feldwert = stringValue(value(named: "FELDWERT", in: payload))
            if !feldwert.isEmpty, let planData = decodeSAPNotificationPayload(fromFeldwert: feldwert) {
                payload.merge(planData) { _, planValue in planValue }
            }
        }

        let rows = value(named: "T_PLPOD", in: payload) as? [[String: Any]] ?? []
        return decodeItems(fromRows: rows)
    }

    static func decodeItems(fromRows rows: [[String: Any]]) -> [ElevatorInspectionItem] {
        var result: [ElevatorInspectionItem] = []
        var itemNumber = 1
        var currentGroupTitle = ""

        for row in rows {
            let rowType = stringValue(value(named: "USR00", in: row)).uppercased()
            let fallbackType = stringValue(value(named: "DNAME", in: row)).uppercased()
            let normalizedType = rowType.isEmpty ? fallbackType : rowType

            // Header and subheader rows are group bands, not positions. They
            // carry no controls and do not advance the position number.
            if ["HEADER", "U1"].contains(normalizedType) {
                currentGroupTitle = stringValue(value(named: "LTXA1", in: row))
                continue
            }
            let title = stringValue(value(named: "LTXA1", in: row))
            let operation = stringValue(value(named: "VORNR", in: row))
            let control = stringValue(value(named: "STEUS", in: row))
            guard !title.isEmpty, !operation.isEmpty, !control.isEmpty else { continue }

            let properties = value(named: "T_PROPS", in: row) as? [[String: Any]] ?? []

            let isPhotoRow = normalizedType == "FOTO"
            let requiresPhotoAndComment = isPhotoRow && control.uppercased() == "TFM7"
            // A regular position needs its result value help. A photo-only
            // row intentionally has none and is kept as an evidence row.
            let resultOptions = property(position: 1, in: properties).map(parseOptions) ?? []
            guard isPhotoRow || !resultOptions.isEmpty else { continue }

            // Find property 2: Maßnahme / Action (optional)
            var actionElementID: String? = nil
            var actionOptions: [ElevatorInspectionValueOption] = []
            if !isPhotoRow, let prop2 = property(position: 2, in: properties) {
                let options = parseOptions(from: prop2)
                if !options.isEmpty {
                    actionElementID = "\(control)-\(operation)-2"
                    actionOptions = options
                }
            }

            // Find property 3: Material flag (optional)
            var materialElementID: String? = nil
            if !isPhotoRow, property(position: 3, in: properties) != nil {
                materialElementID = "\(control)-\(operation)-3"
            }

            let resultElementID = "\(control)-\(operation)-1"
            let commentElementID = "\(control)-\(operation)-9B"
            let information = stringValue(value(named: "LTXA2", in: row))

            result.append(ElevatorInspectionItem(
                id: resultElementID,
                vornr: operation,
                steus: control,
                positionNumber: itemNumber,
                title: title,
                information: information,
                resultElementID: resultElementID,
                resultOptions: resultOptions,
                actionElementID: actionElementID,
                actionOptions: actionOptions,
                materialElementID: materialElementID,
                commentElementID: commentElementID,
                requiresPhoto: isPhotoRow,
                requiresPhotoAndComment: requiresPhotoAndComment,
                requiresResult: !isPhotoRow,
                groupTitle: currentGroupTitle
            ))
            itemNumber += 1
        }

        return result
    }

    private static func property(position: Int, in properties: [[String: Any]]) -> [String: Any]? {
        properties.first { prop in
            switch value(named: "POSNR", in: prop) {
            case let number as NSNumber:
                return number.intValue == position
            case let str as String:
                return Int(str) == position
            default:
                return false
            }
        }
    }

    private static func parseOptions(from property: [String: Any]) -> [ElevatorInspectionValueOption] {
        let rawKeys = stringValue(value(named: "DFVAL", in: property))
        let rawValues = stringValue(value(named: "DFVAL_TXT", in: property))

        var keys = rawKeys.split(separator: ";").map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
        var values = rawValues.split(separator: ";").map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }

        // Remove empty strings resulting from trailing semicolons
        keys.removeAll { $0.isEmpty }
        values.removeAll { $0.isEmpty }

        guard !keys.isEmpty else { return [] }

        return keys.enumerated().map { index, key in
            let text = index < values.count ? values[index] : key
            return ElevatorInspectionValueOption(code: key, text: text)
        }
    }

    private static func value(named key: String, in dict: [String: Any]) -> Any? {
        dict.first { $0.key.caseInsensitiveCompare(key) == .orderedSame }?.value
    }

    private static func stringValue(_ value: Any?) -> String {
        switch value {
        case let str as String:
            return str.trimmingCharacters(in: .whitespacesAndNewlines)
        case let num as NSNumber:
            return num.stringValue
        default:
            return ""
        }
    }
}

extension ElevatorInspectionDraftPayload {
    /// The form this draft belongs to. Drafts without a stored code predate
    /// TFM4 and are TFM2.
    var form: EquipmentInspectionForm {
        formCode.flatMap(EquipmentInspectionForm.init(formCode:)) ?? .elevator
    }
}
