import Foundation

/// The SAP-driven equipment inspections that share one screen, view model,
/// offline draft, PDF report and upload.
///
/// Traced from the legacy Cordova client. `Aufzugskontrolle.controller.js`
/// (TFM2) and `MasterDataForm.controller.js` (TFM4 Steigleitern, routed there
/// by `App.controller.navToForm`) both extend `BaseFormController` and
/// `HeaderFormBuilder`: the same class-characteristics header, the same
/// `T_PROPS`-driven dropdown positions, the same "Außer Betrieb" status, the
/// same close rules (`MIAR`/`MMAB`, `Mnot`) and the same document class
/// `D_TFM_Wartung` / `TFM006`. Only what this type describes differs per form.
///
/// Adding the next form code (TFM6, TFM8, …) means adding a case here once its
/// legacy differences are verified — never a copy of the screen.
enum EquipmentInspectionForm: String, CaseIterable, Sendable {
    /// Aufzugskontrolle.
    case elevator = "TFM2"
    /// Steigleitern (equipment type `TFMLEITER`).
    case fixedLadder = "TFM4"
    /// Unterverteilung / FI-Schutzschalter (equipment type `TFMNSPV`).
    case subdistribution = "TFM7"

    init?(formCode: String) {
        self.init(rawValue: formCode.trimmingCharacters(in: .whitespacesAndNewlines).uppercased())
    }

    var formCode: String { rawValue }

    /// Checklist configuration from the shared inspection form.
    var variant: InspectionFormVariant {
        InspectionFormVariant.forFormCode(rawValue)
    }

    /// `true` when the form may post the `T_PROPS` position 3 material flag.
    ///
    /// `MasterDataForm.getSelect` has the position 3 branch commented out and
    /// its `buildPDF` passes `hasMaterial = false`, so TFM4 never shows or
    /// posts a material value even when SAP delivers the property.
    var supportsMaterial: Bool {
        variant.hasMaterialColumn
    }

    // MARK: - Master data (HeaderFormBuilder)

    /// Equipment types (`EQART`) whose cached class characteristics belong to
    /// this form. `constEqartSteusMap` maps `TFMLEITER` to TFM4; TFM2 covers
    /// the passenger, freight and related elevator types.
    var equipmentTypes: Set<String> {
        switch self {
        case .elevator: ["TFMPERS", "TFMLAST", "TFMBEFAHR", "TFMKLGUT"]
        case .fixedLadder: ["TFMLEITER"]
        case .subdistribution: ["TFMNSPV"]
        }
    }

    /// Class name that identifies the form's master record when the record
    /// itself carries no supported equipment type.
    var fallbackClassName: String? {
        switch self {
        case .elevator: "TFMAUFZUG"
        case .fixedLadder: nil
        case .subdistribution: nil
        }
    }

    /// Whether the form can be inspected without class characteristics.
    ///
    /// `HeaderFormBuilder._afterMasterdata4Header` and
    /// `_afterGetKlassenMerkmale` call `showInvalidData` ("Klassenmerkmale
    /// nicht gefunden.") and navigate back for every form except
    /// `Aufzugskontrolle`.
    var requiresMasterData: Bool {
        self != .elevator
    }

    // MARK: - Texts

    var titleKey: String {
        switch self {
        case .elevator: "elevator.inspection.title"
        case .fixedLadder: "fixedLadder.inspection.title"
        case .subdistribution: "subdistribution.title"
        }
    }

    /// Icon of the saved-work row in the drafts list.
    var draftIcon: String {
        switch self {
        case .elevator: "🛗"
        case .fixedLadder: "🪜"
        case .subdistribution: "⚡️"
        }
    }

    var masterDataTitleKey: String {
        switch self {
        case .elevator: "elevator.assetData.title"
        case .fixedLadder: "fixedLadder.masterData.title"
        case .subdistribution: "subdistribution.masterData.title"
        }
    }

    var masterDataSubtitleKey: String {
        switch self {
        case .elevator: "elevator.assetData.subtitle"
        case .fixedLadder: "fixedLadder.masterData.subtitle"
        case .subdistribution: "subdistribution.masterData.subtitle"
        }
    }

    var masterDataLoadingKey: String {
        switch self {
        case .elevator: "elevator.assetData.loading"
        case .fixedLadder: "fixedLadder.masterData.loading"
        case .subdistribution: "subdistribution.masterData.loading"
        }
    }

    var masterDataUnavailableTitleKey: String {
        switch self {
        case .elevator: "elevator.assetData.unavailable.title"
        case .fixedLadder: "fixedLadder.masterData.unavailable.title"
        case .subdistribution: "subdistribution.masterData.unavailable.title"
        }
    }

    var masterDataUnavailableMessageKey: String {
        switch self {
        case .elevator: "elevator.assetData.unavailable.message"
        case .fixedLadder: "fixedLadder.masterData.unavailable.message"
        case .subdistribution: "subdistribution.masterData.unavailable.message"
        }
    }

    var checklistUnavailableTitleKey: String {
        switch self {
        case .elevator: "elevator.unavailable.title"
        case .fixedLadder: "fixedLadder.unavailable.title"
        case .subdistribution: "subdistribution.unavailable.title"
        }
    }

    var defectCloseMessageKey: String {
        switch self {
        case .elevator: "elevator.closeDialog.message"
        case .fixedLadder: "fixedLadder.closeDialog.message"
        case .subdistribution: "subdistribution.closeDialog.message"
        }
    }

    // MARK: - Report and upload

    /// German report title used when the class definition carries no `TXTBZ`.
    /// The PDF is an SAP document and is always German, like the legacy
    /// `PdfBuilder` output. `Aufzugskontrolle.buildPDF` falls back to
    /// "Aufzugskontrolle"; `MasterDataForm.buildPDF` always uses `TXTBZ`.
    var reportTitleFallback: String {
        switch self {
        case .elevator: "Aufzugskontrolle"
        case .fixedLadder: "Steigleitern"
        case .subdistribution: "Unterverteilung"
        }
    }

    /// German heading of the master-data block in the PDF report.
    var reportMasterDataTitle: String {
        switch self {
        case .elevator: "Aufzug Merkmale"
        case .fixedLadder: "Steigleiter Merkmale"
        case .subdistribution: "Unterverteilung Merkmale"
        }
    }

    /// `docClass` / `valueList` of the legacy controller. Both
    /// `Aufzugskontrolle` and `MasterDataForm` declare `D_TFM_Wartung` /
    /// `TFM006`.
    var documentClass: String { "D_TFM_Wartung" }
    var documentValueList: String { "TFM006" }
}

extension SAPNotificationSummary {
    /// The shared equipment inspection this notification opens, if any.
    ///
    /// `FORMNR` wins; otherwise the first plan position (`T_PLPOD[].STEUS`),
    /// read from the payload or from its packed `FELDWERT`, decides — the
    /// same order `App.controller.navToForm` relies on.
    var equipmentInspectionForm: EquipmentInspectionForm? {
        let json = rawPayloadJSON
        let mentionsForm = EquipmentInspectionForm.allCases.contains { json.contains($0.rawValue) }
        // Payloads with a packed FELDWERT do not show the code in plain text.
        guard mentionsForm || json.contains("FELDWERT") else { return nil }

        guard let data = json.data(using: .utf8),
              let dict = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] else {
            return nil
        }
        if let formNumber = dict["FORMNR"] as? String, !formNumber.isEmpty {
            if let form = EquipmentInspectionForm(formCode: formNumber) {
                return form
            }
        }
        if let rows = dict["T_PLPOD"] as? [[String: Any]] {
            return Self.equipmentInspectionForm(in: rows)
        }
        if let feldwert = dict["FELDWERT"] as? String,
           let planData = decodeSAPNotificationPayload(fromFeldwert: feldwert) {
            if let formNumber = planData["FORMNR"] as? String,
               let form = EquipmentInspectionForm(formCode: formNumber) {
                return form
            }
            if let rows = planData["T_PLPOD"] as? [[String: Any]] {
                return Self.equipmentInspectionForm(in: rows)
            }
        }
        return nil
    }

    var isTFM2ElevatorInspection: Bool {
        equipmentInspectionForm == .elevator
    }

    private static func equipmentInspectionForm(in rows: [[String: Any]]) -> EquipmentInspectionForm? {
        for row in rows {
            if let control = row["STEUS"] as? String, let form = EquipmentInspectionForm(formCode: control) {
                return form
            }
        }
        return nil
    }
}

extension SAPNotificationDetail {
    var equipmentInspectionForm: EquipmentInspectionForm? {
        summary.equipmentInspectionForm
    }

    var isTFM2ElevatorInspection: Bool {
        summary.isTFM2ElevatorInspection
    }
}
