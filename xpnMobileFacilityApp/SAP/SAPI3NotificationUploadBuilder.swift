import CryptoKit
import Foundation

enum I3NotificationUploadError: LocalizedError {
    case missingFunctionalLocation(String)
    case missingPlan(String)
    case missingPDF
    case contextUnavailable

    var errorDescription: String? {
        switch self {
        case let .missingFunctionalLocation(id):
            "Technischer Platz \(id) nicht gefunden."
        case let .missingPlan(planNumber):
            "Anleitung \(planNumber) nicht gefunden."
        case .missingPDF:
            "PDF-Bericht fehlt. Bitte das Formular erneut abschließen."
        case .contextUnavailable:
            "SAP-Stammdaten für das Formular sind nicht verfügbar."
        }
    }
}

/// The legacy rows a new I3 notification is built from
/// (`edata/select.js getItemNewMeldung`), as JSON so they cross actors.
struct I3NotificationLegacyContext: Sendable {
    /// `FROM_T0268` `MELDUNG`: the notification template.
    let templateJSON: String?
    /// The last `FROM_T0272` row of the building (`funcLoc`).
    let functionalLocationJSON: String
    /// The positions of the `FROM_T0267` plan with `EQART = TFMINSTRUC`.
    let planPositionsJSON: String?
    /// The chosen `FROM_T0298` partner as `getAllItemFrom_T0298` lists it;
    /// nil for none or a partner entered on the device.
    let partnerJSON: String?
    /// The `USER` row: `PERSNR` and the `RCDEX` partner roles.
    let userJSON: String
}

protocol I3NotificationContextProviding: Sendable {
    func loadI3NotificationContext(
        functionalLocationID: String,
        planNumber: String,
        partnerAddressNumber: String
    ) async throws -> I3NotificationLegacyContext
}

/// The Cordova forms that close as a new I3 notification (`insertI3Meldung`).
enum I3NotificationForm: Sendable {
    /// `InstructFormCreate`, plan `TFMB_001`.
    case briefing
    /// `InstructFormCreate`, opened with plan `TFMQ_001`.
    case qualification
    /// `FeuererlaubnisscheinFormCreate`.
    case firePermit
    /// `ElektrischenFormCreate`.
    case electricalSafety

    static let documentClass = "D_TFM_Einweisung"

    /// `SelectionCreate` defaults every instruction form to `TFMB_001`; only
    /// the qualification check is opened with `TFMQ_001`.
    var planNumber: String { self == .qualification ? "TFMQ_001" : "TFMB_001" }

    /// `ElektrischenFormCreate` gets its notification with no positions.
    var usesPlanPositions: Bool { self != .electricalSafety }

    /// Only `InstructFormCreate` offers the optional sections.
    var offersOptionalSections: Bool { self == .briefing || self == .qualification }

    /// `util.datatypes.TypePLKO4InstrucForm` / `typePLKO4Qualifikation`.
    var planHeader: [String: Any] {
        let isQualification = self == .qualification
        let title = isQualification ? "Qualifikationsnachweis" : "Unterweisungsformular"
        return [
            "MANDT": "", "ABRHO": 3, "ARBID": 10000104, "ARBPL": "", "EARTX": title,
            "EQART": "TFMINSTRUCFORM", "HUNIT": "", "INGRP": "", "INNAM": "", "IWERK": "",
            "KTEXT": title, "MPTYP": "", "PLAN_SORT": isQualification ? "TFMQ" : "TFM9",
            "PLNAL": "01", "PLNNR": planNumber, "PLNTY": "A", "QMART": "I3", "STRAT": ""
        ]
    }

    /// `_updateDiffFields4Qmel`: `QMTXT` is this prefix and the instructed person.
    var notificationTitlePrefix: String {
        switch self {
        case .briefing: "Einweisung"
        case .qualification: "Qualifikationsnachweis"
        case .firePermit: "Feuererlaubnisschein"
        case .electricalSafety: "Elektrische Anlage"
        }
    }

    /// `closeProcess`: the `DESCRIPTION` of the PDF document.
    var documentDescription: String {
        switch self {
        case .briefing: "Einweisung"
        case .qualification: "Qualifikationsnachweis"
        case .firePermit: "Feuererlaubnisschein"
        case .electricalSafety: "Elektrischen"
        }
    }

    /// The `valueList` of each controller (`DMS_DOCID`).
    var documentValueList: String {
        switch self {
        case .briefing: "TFM012"
        case .qualification: "TFM016"
        case .firePermit: "TFM013"
        case .electricalSafety: "TFM014"
        }
    }

    /// `ElektrischenFormCreate` assigns `EMNAM = oUser.PERSN` (sic) instead of
    /// `QMNAM`, so its notification keeps the template's notifier.
    var setsNotifier: Bool { self != .electricalSafety }
}

/// `currPartnerComp`: the partner company of the form.
enum I3NotificationPartner: Sendable {
    /// No partner was chosen; the empty `type4PartnerItem`.
    case none
    /// A `FROM_T0298` partner, loaded by its address number.
    case existing(addressNumber: String)
    /// A `NEU…` partner entered on the device (`getNewPartnerItem`).
    case new(Fields)

    struct Fields: Sendable {
        var addressNumber: String
        var title = ""
        var company = ""
        var contactName = ""
        var email = ""
        var telephone = ""
        var street = ""
        var houseNumber = ""
        var postalCode = ""
        var city = ""
        var country = ""
    }

    var addressNumber: String {
        switch self {
        case .none: ""
        case let .existing(addressNumber): addressNumber
        case let .new(fields): fields.addressNumber
        }
    }
}

struct I3NotificationInput: Sendable {
    let form: I3NotificationForm
    let workItemID: UUID
    /// `STRNO` of the building the form was created for.
    let functionalLocationID: String
    /// `nameEmployeePC`.
    let instructedPerson: String
    /// `coordiantor` (sic).
    let coordinator: String
    /// `task`.
    let task: String
    let start: Date
    let end: Date
    let partner: I3NotificationPartner
    /// The partner e-mail shown on the form; replaces the partner's `SMTP_ADDR`.
    let partnerEmail: String
    /// `STEUS` + `VORNR` of the optional section headers the user chose.
    let selectedOptionalSectionIDs: Set<String>
    let pdfData: Data
    let completedAt: Date
    /// `USR02` symbols of the positions answered "Ja" that point at a standard
    /// SAP document (legacy `_additionalDocs`). Each becomes a `TO_T0302`
    /// reference row; SAP already holds the file, so no bytes are sent.
    var additionalDocumentSymbolIDs: [String] = []
}

/// Builds the `TO_T0300` I3 notification and its `TO_T0302` PDF document of a
/// closed instruction form, as the Cordova forms do:
/// - `getItemNewMeldung` starts from the `FROM_T0268` template, fills it from
///   the building (`FROM_T0272`) and the plan header, and snapshots `T0281`;
/// - the form's `_updateT0271` copies its inputs and the partner into
///   same-named keys and derives `QMTXT`, the long text and the partner roles;
/// - `onProcessClose`, `prepareForClose` and `closeProcess` set the closing
///   status and pack the notification into `FELDWERT`;
/// - `insertI3Meldung` stores the `T0281` columns `TO_T0300` has, and the PDF.
///
/// The identifiers derive from the work item, so a retried upload replaces
/// its own rows instead of queueing a second notification.
enum SAPI3NotificationUploadBuilder {
    static func build(
        input: I3NotificationInput,
        context: I3NotificationLegacyContext,
        syncUserID: String
    ) throws -> SAPNotificationOutgoingBatch {
        guard !input.pdfData.isEmpty else { throw I3NotificationUploadError.missingPDF }
        guard let functionalLocation = object(from: context.functionalLocationJSON) else {
            throw I3NotificationUploadError.missingFunctionalLocation(input.functionalLocationID)
        }
        let planPositions = sortedPositions(context.planPositionsJSON.flatMap(array(from:)) ?? [])
        if input.form.usesPlanPositions, planPositions.isEmpty {
            throw I3NotificationUploadError.missingPlan(input.form.planNumber)
        }
        let user = object(from: context.userJSON) ?? [:]
        let userID = syncUserID.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
        let ids = identifiers(for: input.workItemID)
        let closedOn = abapDate(input.completedAt)

        // `getItemNewMeldung`
        var notification = context.templateJSON.flatMap(object(from:)) ?? [:]
        assignDefinedValues(from: functionalLocation, into: &notification)
        let client = string(named: "MANDT2", in: functionalLocation)
        notification["MANDT"] = client
        notification["QMNUM"] = ids.notificationID
        notification["STRNO"] = input.functionalLocationID
        for key in ["PLTXT", "TPLNR", "STTXT", "IWERK", "INGRP", "USTXT", "AENAM"] {
            notification[key] = ""
        }
        notification["AEDAT"] = "0000-00-00"
        for suffix in ["TO", "AP"] {
            notification["ADDRNUMBER_\(suffix)"] = string(named: "ADRNR", in: functionalLocation)
            notification["NAME1_\(suffix)"] = string(named: "NAME_LIST", in: functionalLocation)
            notification["CITY1_\(suffix)"] = string(named: "CITY1", in: functionalLocation)
            notification["CITY2_\(suffix)"] = string(named: "CITY2", in: functionalLocation)
            notification["POST_CODE1_\(suffix)"] = string(named: "POST_CODE1", in: functionalLocation)
            notification["STREET_\(suffix)"] = string(named: "STREET", in: functionalLocation)
            notification["TEL_NUMBER_\(suffix)"] = string(named: "TEL_NUMBER", in: functionalLocation)
        }
        var planHeader = input.form.planHeader
        planHeader["T_PLPOD"] = input.form.usesPlanPositions ? planPositions : []
        assignDefinedValues(from: planHeader, into: &notification)
        notification["MANDT"] = client
        notification["T_PLPOD"] = planHeader["T_PLPOD"]
        let planText = string(named: "KTEXT", in: planHeader)
        notification["PLTXT"] = planText.isEmpty ? string(named: "EARTX", in: planHeader) : planText
        notification["QMTXT"] = notification["PLTXT"]

        var process = emptyRow(of: "TO_T0281")
        assignDefinedValues(from: notification, into: &process)
        process["VORGANGSNR"] = ids.processID
        let formNumber = input.form == .electricalSafety
            ? "TFM9"
            : string(named: "STEUS", in: planPositions.last ?? [:])
        process["FORMNR"] = formNumber

        notification["IWERK"] = string(named: "IWERK", in: functionalLocation)
        notification["INGRP"] = string(named: "INGRP", in: functionalLocation)
        notification["GEWRK"] = string(named: "GEWRK", in: functionalLocation)
        notification["EQUNR"] = ""
        process["EQUNR"] = ""

        // `_afterSelectInfo4Form` / `onSelecInstrucForm`: the positions of the
        // required sections and of the optional sections the user chose.
        notification["T_PLPOD"] = input.form.usesPlanPositions
            ? activePositions(
                planPositions,
                optionalSectionIDs: input.form.offersOptionalSections ? input.selectedOptionalSectionIDs : []
            )
            : []

        // `_updateT0271`
        let inputInfo: [String: Any] = [
            "coordiantor": input.coordinator,
            "TPLNR": "",
            "task": input.task,
            "STRMN": input.start,
            "LTRMN": input.end,
            "nameEmployeePC": input.instructedPerson
        ]
        let partnerCompany = partnerObject(input.partner, context: context, email: input.partnerEmail,
                                           client: string(named: "MANDT", in: functionalLocation))
        var remaining = copySameKeys(from: inputInfo, into: &notification)
        remaining.merge(copySameKeys(from: partnerCompany, into: &notification)) { _, partner in partner }

        // `_updateDiffFields4Qmel`
        let instructedPerson = remaining["nameEmployeePC"] as? String ?? input.instructedPerson
        notification["QMTXT"] = "\(input.form.notificationTitlePrefix), \(instructedPerson)"
        if input.form.setsNotifier {
            notification["QMNAM"] = string(named: "PERSNR", in: user)
        }
        let task = (remaining["task"] as? String ?? input.task).trimmingCharacters(in: .whitespacesAndNewlines)
        notification["T_LTXT_QM"] = longTextLines(task).map { ["TDFORMAT": "", "TDLINE": $0] }
        notification["STRMN"] = abapDate(notification["STRMN"], fallback: input.completedAt)
        notification["LTRMN"] = abapDate(notification["LTRMN"], fallback: input.completedAt)
        notification["QMDAT"] = closedOn
        notification["MZEIT"] = abapTime(input.completedAt)
        notification["USTXT"] = "MAPP LTXT"
        notification["STTXT"] = "MMAB"
        notification["STSMA"] = "ZPMNI3"
        notification["SMTP_ADDR_AP"] = remaining["SMTP_ADDR"]
        notification["NAME1_AP"] = instructedPerson
        let partnerAddressNumber = remaining["ADDRNUMBER"] as? String ?? ""
        var partnerRoles: [[String: Any]] = [[
            "PARVW": "Z7",
            "PARNR": userAddressNumber(role: "Z7", client: client, user: user) ?? NSNull(),
            "XDELE": ""
        ]]
        if !partnerAddressNumber.contains("NEU") {
            partnerRoles.append([
                "PARVW": remaining["PARVW"] as? String ?? "",
                "PARNR": partnerAddressNumber,
                "XDELE": ""
            ])
        }
        notification["T_PARTNER_QM"] = partnerRoles

        // `onProcessClose` for an I3, then `prepareForClose`.
        notification["EQUNR"] = ""
        process["USTXT"] = "MAPP LTXT"
        process["STTXT"] = "MMAB"
        process["STSMA"] = "ZPMNI3"
        process["AENAM"] = userID
        process["AEDAT"] = closedOn
        notification["USTXT"] = process["USTXT"]
        notification["STTXT"] = process["STTXT"]
        notification["AENAM"] = process["AENAM"]
        notification["AEDAT"] = process["AEDAT"]

        // `closeProcess`
        process["CREATEDBY"] = userID
        notification["FELDWERT"] = nil
        let feldwert = try SAPLegacyDataExchangeCodec.packedFeldwert(notification)
        process["FELDWERT"] = feldwert
        if partnerAddressNumber.contains("NEU") {
            process["FELDWERT2"] = try SAPLegacyDataExchangeCodec.packedFeldwert(
                partnerCreation(from: partnerCompany)
            )
        }

        // `insertI3Meldung`
        var row = emptyRow(of: "TO_T0300")
        assignDefinedValues(from: process, into: &row)
        row["REQID"] = ""
        row["EQUNR"] = ""

        let closedAt = abapTime(input.completedAt)
        var document = Dictionary(uniqueKeysWithValues:
            (LegacySQLiteSchema.byName["TO_T0302"]?.columns ?? []).map { ($0.name, "") }
        )
        document.merge([
            // `_insertDocument`: the document belongs to the notification's
            // client, which these transfer tables carry in `MANDT2`.
            "REQID": "", "MANDT2": client,
            "VORGANGSNR": ids.processID, "QMNUM": ids.notificationID,
            "DOCID": ids.documentID, "ELEMENTNR": "\(formNumber)-pdf",
            "NAME": "\(input.form.documentDescription)_\(documentTimestamp(input.completedAt))",
            "DESCRIPTION": input.form.documentDescription,
            "DMS_CONTENTTYPE": I3NotificationForm.documentClass,
            "DMS_DOCID": input.form.documentValueList,
            "DOC_TYPE": "PDF", "DOC_MIMETYPE": "application/pdf",
            "CREATEDBY": userID, "CREATEDDATE": closedOn, "CREATEDTIME": closedAt,
            "MODIFIEDBY": userID, "MODIFIEDDATE": closedOn, "MODIFIEDTIME": closedAt,
            "DOKOB": "SMQMEL", "DOKAR": "FMD", "OBJKY": ids.notificationID
        ]) { _, value in value }

        var batch = SAPNotificationOutgoingBatch(
            workItemIDs: [input.workItemID], attachmentIDs: [], processIDs: [ids.processID],
            equipmentIDs: [], headers: [], values: [], documents: [], equipment: []
        )
        batch.i3Notifications = [row.mapValues { Optional($0) }]
        batch.i3Documents = [SAPNotificationOutgoingDocument(metadata: document, data: input.pdfData)]
        batch.i3DocumentReferences = referenceDocumentRows(
            input: input, ids: ids, formNumber: formNumber, client: client,
            userID: userID, closedOn: closedOn, closedAt: closedAt
        )
        return batch
    }

    /// `_insertDocument` of `InstructFormCreate`: one `TO_T0302` row per
    /// standard document the closed form points at. It carries `DOKNR` and no
    /// content, because SAP resolves the file from its own DMS.
    private static func referenceDocumentRows(
        input: I3NotificationInput,
        ids: Identifiers,
        formNumber: String,
        client: String,
        userID: String,
        closedOn: String,
        closedAt: String
    ) -> [SAPNotificationOutgoingDocument] {
        input.additionalDocumentSymbolIDs.enumerated().compactMap { index, symbolID in
            guard let reference = BriefingReferenceDocument(symbolID: symbolID) else { return nil }
            var row = Dictionary(uniqueKeysWithValues:
                (LegacySQLiteSchema.byName["TO_T0302"]?.columns ?? []).map { ($0.name, "") }
            )
            row.merge([
                "REQID": "", "MANDT2": client,
                "VORGANGSNR": ids.processID, "QMNUM": ids.notificationID,
                "DOCID": documentID(ids.processID, index: index),
                "ELEMENTNR": "\(formNumber)-pdf",
                "NAME": "\(reference.documentNumber)_\(documentTimestamp(input.completedAt))",
                "DESCRIPTION": reference.sapDescription,
                "DOKNR": reference.documentNumber,
                "DOC_TYPE": "PDF", "DOC_MIMETYPE": "application/pdf",
                "CREATEDBY": userID, "CREATEDDATE": closedOn, "CREATEDTIME": closedAt,
                "MODIFIEDBY": userID, "MODIFIEDDATE": closedOn, "MODIFIEDTIME": closedAt,
                "DOKOB": "SMQMEL", "DOKAR": "FMD", "OBJKY": ids.notificationID
            ]) { _, value in value }
            return SAPNotificationOutgoingDocument(
                metadata: row, data: Data(), referencesExistingDocument: true
            )
        }
    }

    /// A stable `DOCID` per reference, so a retried upload replaces its own
    /// rows instead of adding a second copy of the same document.
    private static func documentID(_ processID: String, index: Int) -> String {
        let digest = SHA256.hash(data: Data("\(processID)|doc|\(index)".utf8))
            .map { String(format: "%02X", $0) }
            .joined()
        return String(digest.prefix(32))
    }

    // MARK: - Identifiers

    struct Identifiers: Equatable {
        /// `getUIID()`: 32 upper-case hexadecimal digits.
        let processID: String
        /// `randomId(8, "NEU")`.
        let notificationID: String
        let documentID: String
    }

    static func identifiers(for workItemID: UUID) -> Identifiers {
        let hex = workItemID.uuidString.replacingOccurrences(of: "-", with: "").uppercased()
        let documentDigest = SHA256.hash(data: Data("\(hex)|pdf".utf8))
            .map { String(format: "%02X", $0) }
            .joined()
        return Identifiers(
            processID: hex,
            notificationID: "NEU-\(hex.prefix(8))",
            documentID: String(documentDigest.prefix(32))
        )
    }

    // MARK: - Positions

    /// `getItemNewMeldung` sorts the plan by `VORNR` and every position's
    /// `T_PROPS` by `POSNR`.
    private static func sortedPositions(_ positions: [[String: Any]]) -> [[String: Any]] {
        positions.enumerated().sorted { left, right in
            let leftNumber = Double(string(named: "VORNR", in: left.element)) ?? .infinity
            let rightNumber = Double(string(named: "VORNR", in: right.element)) ?? .infinity
            return leftNumber == rightNumber ? left.offset < right.offset : leftNumber < rightNumber
        }
        .map { entry in
            var position = entry.element
            if let properties = value(named: "T_PROPS", in: position) as? [[String: Any]], properties.count > 1 {
                position["T_PROPS"] = properties.enumerated().sorted { left, right in
                    let leftNumber = Double(string(named: "POSNR", in: left.element)) ?? .infinity
                    let rightNumber = Double(string(named: "POSNR", in: right.element)) ?? .infinity
                    return leftNumber == rightNumber ? left.offset < right.offset : leftNumber < rightNumber
                }
                .map(\.element)
            }
            return position
        }
    }

    /// `_maintainHeaderPosition` groups the positions under their header;
    /// headers with `USR10 = X` are optional.
    private static func activePositions(
        _ positions: [[String: Any]],
        optionalSectionIDs: Set<String>
    ) -> [[String: Any]] {
        var active: [[String: Any]] = []
        var includesSection = false
        var hasHeader = false
        for position in positions {
            if string(named: "USR00", in: position) == "HEADER" {
                hasHeader = true
                let sectionID = string(named: "STEUS", in: position) + string(named: "VORNR", in: position)
                includesSection = string(named: "USR10", in: position) != "X"
                    || optionalSectionIDs.contains(sectionID)
            }
            if hasHeader, includesSection {
                active.append(position)
            }
        }
        return active
    }

    // MARK: - Partner

    private static func partnerObject(
        _ partner: I3NotificationPartner,
        context: I3NotificationLegacyContext,
        email: String,
        client: String
    ) -> [String: Any] {
        var company: [String: Any]
        switch partner {
        case .none:
            company = ["ADDRNUMBER": "", "PARVW": "ZT", "ADDR_GROUP": "ZFMT", "SMTP_ADDR": ""]
        case .existing:
            company = context.partnerJSON.flatMap(object(from:)) ?? [:]
            company["ADDRNUMBER"] = partner.addressNumber
            if company["PARVW"] == nil { company["PARVW"] = "ZT" }
        case let .new(fields):
            company = [
                "ADDRNUMBER": fields.addressNumber, "ADDR_GROUP": "ZFMT", "PARVW": "ZT",
                "CLIENT": client, "LANGU": "D", "LANGU_CREA": "D",
                "TITLE": fields.title, "NAME1": fields.company, "NAME2": fields.contactName,
                "SMTP_ADDR": fields.email, "TEL_NUMBER": fields.telephone,
                "STREET": fields.street, "HOUSE_NUM1": fields.houseNumber,
                "POST_CODE1": fields.postalCode, "CITY1": fields.city, "COUNTRY": fields.country,
                "SORT1": "", "SORT2": ""
            ]
        }
        if !email.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            company["SMTP_ADDR"] = email
        }
        return company
    }

    /// `getData4PartnerCreate`: the `type4PartnerCreate` keys of the partner.
    private static func partnerCreation(from partner: [String: Any]) -> [String: Any] {
        let keys = [
            "ADDRNUMBER", "TITLE", "NAME1", "NAME2", "CITY1", "CITY2", "POST_CODE1", "STREET",
            "HOUSE_NUM1", "TEL_NUMBER", "TELNR_LONG", "MOB_NUMBER", "BUILDING", "FLOOR",
            "ROOMNUMBER", "R3_USER", "SMTP_ADDR", "COUNTRY", "SORT1", "SORT2"
        ]
        var creation = Dictionary(uniqueKeysWithValues: keys.map { ($0, "" as Any) })
        assignDefinedValues(from: partner, into: &creation)
        return creation
    }

    /// `getUserAddrNumber`: the user's address number for a partner role.
    private static func userAddressNumber(role: String, client: String, user: [String: Any]) -> String? {
        SAPLegacyDataExchangeCodec.decodedFeldwertObjects(string(named: "RCDEX", in: user))
            .first { string(named: "PARVW", in: $0) == role && string(named: "MANDT", in: $0) == client }
            .map { string(named: "ADDRNUMBER", in: $0) }
    }

    // MARK: - Legacy object helpers

    /// `objectAssign`: only keys the target has, only defined source values.
    private static func assignDefinedValues(from source: [String: Any], into target: inout [String: Any]) {
        for key in target.keys {
            guard let value = source[key], !(value is NSNull) else { continue }
            target[key] = value
        }
    }

    private static func assignDefinedValues(from source: [String: Any], into target: inout [String: String]) {
        for key in target.keys {
            guard let value = source[key], let text = text(value) else { continue }
            target[key] = text
        }
    }

    /// `_updateSimFields4Qmel`: moves every key the notification has into it
    /// and returns the others.
    private static func copySameKeys(
        from source: [String: Any],
        into target: inout [String: Any]
    ) -> [String: Any] {
        var remaining: [String: Any] = [:]
        for (key, value) in source {
            if target.keys.contains(key) {
                target[key] = value
            } else {
                remaining[key] = value
            }
        }
        return remaining
    }

    private static func emptyRow(of tableName: String) -> [String: String] {
        Dictionary(uniqueKeysWithValues: (LegacySQLiteSchema.byName[tableName]?.columns ?? []).map { ($0.name, "") })
    }

    /// `getLongTextArray(task.trim().substring(0, 300))`.
    private static func longTextLines(_ text: String) -> [String] {
        let limited = (text as NSString).substring(to: min((text as NSString).length, 300))
        return I2NotificationRules.splitToLength(limited, length: 128)
    }

    private static func object(from json: String) -> [String: Any]? {
        guard let data = json.data(using: .utf8) else { return nil }
        return (try? JSONSerialization.jsonObject(with: data)) as? [String: Any]
    }

    private static func array(from json: String) -> [[String: Any]]? {
        guard let data = json.data(using: .utf8) else { return nil }
        return (try? JSONSerialization.jsonObject(with: data)) as? [[String: Any]]
    }

    private static func value(named name: String, in dictionary: [String: Any]) -> Any? {
        dictionary[name] ?? dictionary.first { $0.key.caseInsensitiveCompare(name) == .orderedSame }?.value
    }

    private static func string(named name: String, in dictionary: [String: Any]) -> String {
        value(named: name, in: dictionary).flatMap(text) ?? ""
    }

    private static func text(_ value: Any) -> String? {
        switch value {
        case let string as String: string
        case let number as NSNumber: number.stringValue
        default: nil
        }
    }

    /// `getNewDateABAPString`: a date is formatted, a string kept, and
    /// anything else is the current date.
    private static func abapDate(_ value: Any?, fallback: Date) -> String {
        switch value {
        case let date as Date: abapDate(date)
        case let string as String: string
        default: abapDate(fallback)
        }
    }

    private static func abapDate(_ date: Date) -> String { format(date, "yyyyMMdd") }
    private static func abapTime(_ date: Date) -> String { format(date, "HHmmss") }
    /// `getNewDateTimeName`.
    private static func documentTimestamp(_ date: Date) -> String { format(date, "dd_MM_yyyy_HH_mm_ss_SSS") }

    private static func format(_ date: Date, _ pattern: String) -> String {
        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = pattern
        return formatter.string(from: date)
    }
}
