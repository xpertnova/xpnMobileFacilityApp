import Foundation

/// The SAP-driven equipment inspections that share one screen, view model,
/// offline draft, PDF report and upload.
///
/// Traced from the legacy Cordova client. `Aufzugskontrolle.controller.js`
/// (TFM2, and TFM6 Feststellanlage, which `App.controller.navToForm` routes to
/// the same controller) and `MasterDataForm.controller.js` (TFM4 Steigleitern,
/// TFM8 Dachanlagen) all extend `BaseFormController` and
/// `HeaderFormBuilder`: the same class-characteristics header, the same
/// `T_PROPS`-driven dropdown positions, the same "Außer Betrieb" status, the
/// same close rules (`MIAR`/`MMAB`, `Mnot`) and the same document class
/// `D_TFM_Wartung` / `TFM006`. Only what this type describes differs per form.
///
/// Adding the next form code means adding a case here once its
/// legacy differences are verified — never a copy of the screen.
enum EquipmentInspectionForm: String, CaseIterable, Sendable {
    /// Aufzugskontrolle.
    case elevator = "TFM2"
    /// Steigleitern (equipment type `TFMLEITER`).
    case fixedLadder = "TFM4"
    /// Unterverteilung / FI-Schutzschalter (equipment type `TFMNSPV`).
    case subdistribution = "TFM7"
    /// Feststellanlage (equipment type `TFMFSA`).
    case holdOpenSystem = "TFM6"
    /// Dachanlagen (equipment type `TFMDACH`).
    case roofSystem = "TFM8"

    init?(formCode: String) {
        self.init(rawValue: formCode.trimmingCharacters(in: .whitespacesAndNewlines).uppercased())
    }

    var formCode: String { rawValue }

    /// Checklist configuration from the shared inspection form.
    var variant: InspectionFormVariant {
        InspectionFormVariant.forFormCode(rawValue)
    }

    /// `true` when the form carries the header "Außer Betrieb" status.
    ///
    /// `BaseFormController.buildDefaultElements` returns before building the
    /// out-of-order box for TFM8, so a roof system can never be set out of
    /// service and its `<form>-0000-1` element keeps an empty value.
    var supportsOutOfService: Bool {
        variant.supportsOutOfService
    }

    /// `true` when the form may post the `T_PROPS` position 3 material flag.
    ///
    /// `MasterDataForm.getSelect` has the position 3 branch commented out and
    /// its `buildPDF` passes `hasMaterial = false`, so TFM4 never shows or
    /// posts a material value even when SAP delivers the property; the same
    /// applies to TFM8, which `navToForm` also routes to `MasterDataForm`. TFM6 runs
    /// on `Aufzugskontrolle`, whose `getCheckBox` binds the position 3 `CBOX`.
    var supportsMaterial: Bool {
        variant.hasMaterialColumn
    }

    // MARK: - Master data (HeaderFormBuilder)

    /// Equipment types (`EQART`) whose cached class characteristics belong to
    /// this form. `constEqartSteusMap` maps `TFMLEITER` to TFM4, `TFMFSA`
    /// to TFM6 and `TFMDACH` to TFM8; TFM2 covers the passenger, freight and related elevator types.
    var equipmentTypes: Set<String> {
        switch self {
        case .elevator: ["TFMPERS", "TFMLAST", "TFMBEFAHR", "TFMKLGUT"]
        case .fixedLadder: ["TFMLEITER"]
        case .subdistribution: ["TFMNSPV"]
        case .holdOpenSystem: ["TFMFSA"]
        case .roofSystem: ["TFMDACH"]
        }
    }

    /// Class name that identifies the form's master record when the record
    /// itself carries no supported equipment type.
    var fallbackClassName: String? {
        switch self {
        case .elevator: "TFMAUFZUG"
        case .fixedLadder, .subdistribution, .holdOpenSystem, .roofSystem: nil
        }
    }

    /// Whether the form can be inspected without class characteristics.
    ///
    /// `HeaderFormBuilder._afterMasterdata4Header` and
    /// `_afterGetKlassenMerkmale` call `showInvalidData` ("Klassenmerkmale
    /// nicht gefunden.") and navigate back unless `T0281.FORMNR` is `TFM2`.
    /// The check is on the form code, not the controller, so TFM6 is blocked
    /// even though it shares the `Aufzugskontrolle` screen.
    var requiresMasterData: Bool {
        self != .elevator
    }

    // MARK: - Texts

    var titleKey: String {
        switch self {
        case .elevator: "elevator.inspection.title"
        case .fixedLadder: "fixedLadder.inspection.title"
        case .subdistribution: "subdistribution.title"
        case .holdOpenSystem: "holdOpenSystem.inspection.title"
        case .roofSystem: "roofSystem.inspection.title"
        }
    }

    /// Icon of the saved-work row in the drafts list.
    var draftIcon: String {
        switch self {
        case .elevator: "🛗"
        case .fixedLadder: "🪜"
        case .subdistribution: "⚡️"
        case .holdOpenSystem: "🚪"
        case .roofSystem: "🏠"
        }
    }

    var masterDataTitleKey: String {
        switch self {
        case .elevator: "elevator.assetData.title"
        case .fixedLadder: "fixedLadder.masterData.title"
        case .subdistribution: "subdistribution.masterData.title"
        case .holdOpenSystem: "holdOpenSystem.masterData.title"
        case .roofSystem: "roofSystem.masterData.title"
        }
    }

    var masterDataSubtitleKey: String {
        switch self {
        case .elevator: "elevator.assetData.subtitle"
        case .fixedLadder: "fixedLadder.masterData.subtitle"
        case .subdistribution: "subdistribution.masterData.subtitle"
        case .holdOpenSystem: "holdOpenSystem.masterData.subtitle"
        case .roofSystem: "roofSystem.masterData.subtitle"
        }
    }

    var masterDataLoadingKey: String {
        switch self {
        case .elevator: "elevator.assetData.loading"
        case .fixedLadder: "fixedLadder.masterData.loading"
        case .subdistribution: "subdistribution.masterData.loading"
        case .holdOpenSystem: "holdOpenSystem.masterData.loading"
        case .roofSystem: "roofSystem.masterData.loading"
        }
    }

    var masterDataUnavailableTitleKey: String {
        switch self {
        case .elevator: "elevator.assetData.unavailable.title"
        case .fixedLadder: "fixedLadder.masterData.unavailable.title"
        case .subdistribution: "subdistribution.masterData.unavailable.title"
        case .holdOpenSystem: "holdOpenSystem.masterData.unavailable.title"
        case .roofSystem: "roofSystem.masterData.unavailable.title"
        }
    }

    var masterDataUnavailableMessageKey: String {
        switch self {
        case .elevator: "elevator.assetData.unavailable.message"
        case .fixedLadder: "fixedLadder.masterData.unavailable.message"
        case .subdistribution: "subdistribution.masterData.unavailable.message"
        case .holdOpenSystem: "holdOpenSystem.masterData.unavailable.message"
        case .roofSystem: "roofSystem.masterData.unavailable.message"
        }
    }

    var checklistUnavailableTitleKey: String {
        switch self {
        case .elevator: "elevator.unavailable.title"
        case .fixedLadder: "fixedLadder.unavailable.title"
        case .subdistribution: "subdistribution.unavailable.title"
        case .holdOpenSystem: "holdOpenSystem.unavailable.title"
        case .roofSystem: "roofSystem.unavailable.title"
        }
    }

    var defectCloseMessageKey: String {
        switch self {
        case .elevator: "elevator.closeDialog.message"
        case .fixedLadder: "fixedLadder.closeDialog.message"
        case .subdistribution: "subdistribution.closeDialog.message"
        case .holdOpenSystem: "holdOpenSystem.closeDialog.message"
        case .roofSystem: "roofSystem.closeDialog.message"
        }
    }

    // MARK: - Report and upload

    /// Whether the report header carries the form's own name instead of the
    /// SAP class description (`klassenMerkmale.TXTBZ`) that legacy `buildPDF`
    /// prints. TFM2 shows "Aufzugskontrolle" rather than the class text
    /// "e.on Aufzug Merkmale"; TFM6 is pinned to "FSA" the same way, so a
    /// class description maintained in SAP cannot reach the header.
    /// It is also what the upload rebuilds when a form was closed before its
    /// report was kept.
    var reportTitleIgnoresClassDescription: Bool {
        self == .elevator || self == .holdOpenSystem
    }

    /// German report title used when the class definition carries no `TXTBZ`,
    /// and the header itself for a form that names itself. The PDF is an SAP
    /// document and is always German, like the legacy `PdfBuilder` output.
    /// `Aufzugskontrolle.buildPDF` falls back to "Aufzugskontrolle";
    /// `MasterDataForm.buildPDF` always uses `TXTBZ`. TFM4, TFM6 and TFM8
    /// cannot open without class characteristics, so their fallback only
    /// covers a class definition with an empty `TXTBZ`.
    var reportTitleFallback: String {
        switch self {
        case .elevator: "Aufzugskontrolle"
        case .fixedLadder: "Steigleitern"
        case .subdistribution: "Unterverteilung"
        case .holdOpenSystem: "FSA"
        case .roofSystem: "Dachanlagen"
        }
    }

    /// German heading of the master-data block in the PDF report.
    var reportMasterDataTitle: String {
        switch self {
        case .elevator: "Aufzug Merkmale"
        case .fixedLadder: "Steigleiter Merkmale"
        case .subdistribution: "Unterverteilung Merkmale"
        case .holdOpenSystem: "Feststellanlage Merkmale"
        case .roofSystem: "Dachanlage Merkmale"
        }
    }

    /// `docClass` / `valueList` of the legacy controller. Both
    /// `Aufzugskontrolle` (TFM2, TFM6) and `MasterDataForm` (TFM4, TFM8) declare `D_TFM_Wartung` /
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
        if !formCode.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return EquipmentInspectionForm(formCode: formCode)
        }
        return summary.equipmentInspectionForm
    }

    var isTFM2ElevatorInspection: Bool {
        equipmentInspectionForm == .elevator
    }
}
