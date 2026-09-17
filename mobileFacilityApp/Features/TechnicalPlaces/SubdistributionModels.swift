import Foundation

/// The TFM7 creation contract is deliberately separate from TFM5.  They use
/// the same visual language and offline infrastructure, but SAP supplies a
/// different plan, equipment type and characteristic schema.
struct SubdistributionCreationData: Equatable, Sendable {
    let contexts: [SubdistributionCreationContext]

    static let empty = Self(contexts: [])
}

protocol SubdistributionCreationProviding: Sendable {
    func loadSubdistributionCreationData(for workerID: String) async throws -> SubdistributionCreationData
}

struct UnavailableSubdistributionCreationProvider: SubdistributionCreationProviding {
    func loadSubdistributionCreationData(for workerID: String) async throws -> SubdistributionCreationData {
        throw SAPReadError.serviceUnavailable
    }
}

struct SubdistributionCreationContext: Codable, Equatable, Identifiable, Sendable {
    let businessEntity: String
    let building: String
    let parentLocation: String
    let legacyContext: SubdistributionLegacyContext

    var id: String {
        [legacyContext.functionalLocation, businessEntity, building, parentLocation].joined(separator: "|")
    }
}

/// Values are copied from the `FROM_T0272` parent record.  Retaining the raw
/// SAP row lets the upload builder reproduce Cordova's header relation without
/// making the UI depend on a live SAP connection.
struct SubdistributionLegacyContext: Codable, Equatable, Sendable {
    let client: String
    let functionalLocation: String
    let parentEquipmentType: String
    let country: String
    let location: String
    let businessEntity: String
    let building: String
    let segment: String
    let plant: String
    let plannerGroup: String
    let workCenter: String
    let addressNumber: String
    let contactName: String
    let city: String
    let postalCode: String
    let street: String
    let sourceNotificationJSON: String
    let template: SubdistributionLegacyTemplate
}

struct SubdistributionLegacyTemplate: Codable, Equatable, Identifiable, Sendable {
    let id: String
    let equipmentType: String
    let formCode: String
    let planType: String
    let planNumber: String
    let planVersion: String
    let title: String
    let plant: String
    let plannerGroup: String
    let workCenter: String
    let className: String
    let classType: String
    let classGroup: String
    let classDataJSON: String
    let equipmentDataJSON: String
    let characteristics: [SubdistributionCharacteristic]
    let inspectionItems: [SubdistributionInspectionDefinition]
}

enum SubdistributionCharacteristicKind: String, Codable, Sendable {
    case text
    case numeric
    case choice
}

struct SubdistributionCharacteristic: Codable, Equatable, Identifiable, Sendable {
    let position: Int
    /// SAP characteristic identifier (`ATNAM`); this is the outgoing element
    /// identifier, never a localized visible title.
    let name: String
    let title: String
    let kind: SubdistributionCharacteristicKind
    let maximumLength: Int
    let unit: String
    let required: Bool
    let values: [SubdistributionValue]

    var id: String { name }
}

struct SubdistributionValue: Codable, Equatable, Identifiable, Sendable {
    let value: String
    let title: String

    var id: String { value }
}

struct SubdistributionInspectionDefinition: Codable, Equatable, Identifiable, Sendable {
    let operation: String
    let title: String
    let information: String
    let resultElementID: String
    let actionElementID: String
    let commentElementID: String
    let resultValues: [SubdistributionValue]
    let actionValues: [SubdistributionValue]
    /// SAP photo-only positions have no result/action selector.
    let requiresResult: Bool
    /// `nil` keeps drafts saved before this requirement decodable.  `true`
    /// means the inspection point must retain both a JPEG and a comment
    /// before a normal notification may be closed.
    let requiresPhotoAndComment: Bool?

    var requiresDocumentation: Bool { requiresPhotoAndComment == true }

    var id: String { operation }
}

struct SubdistributionInspectionItem: Codable, Equatable, Identifiable, Sendable {
    let id: String
    let number: Int
    let title: String
    let information: String
    let resultElementID: String
    let actionElementID: String
    let commentElementID: String
    let resultValues: [SubdistributionValue]
    let actionValues: [SubdistributionValue]
    let requiresResult: Bool
    let requiresPhotoAndComment: Bool?
    var result: String?
    var action: String?
    var comment: String

    var requiresDocumentation: Bool { requiresPhotoAndComment == true }

    init(definition: SubdistributionInspectionDefinition, number: Int) {
        id = definition.operation
        self.number = number
        title = definition.title
        information = definition.information
        resultElementID = definition.resultElementID
        actionElementID = definition.actionElementID
        commentElementID = definition.commentElementID
        resultValues = definition.resultValues
        actionValues = definition.actionValues
        requiresResult = definition.requiresResult
        requiresPhotoAndComment = definition.requiresPhotoAndComment
        result = nil
        action = nil
        comment = ""
    }

    var isDefective: Bool {
        // Cordova's value help marks code 1 as good.  Other SAP-supplied
        // result values retain their exact code and are treated as a defect.
        guard let result else { return false }
        return result != "1"
    }
}

struct SubdistributionPhotoAttachment: Codable, Equatable, Identifiable, Sendable {
    let localAttachmentID: String
    let inspectionItemID: String
    let sapElementID: String
    let capturedAt: Date
    let sapDocumentID: String

    var id: String { sapDocumentID }
}

struct SubdistributionLegacyIdentifiers: Codable, Equatable, Sendable {
    let notificationNumber: String
    let equipmentNumber: String
    let processNumber: String
}

enum SubdistributionCloseAction: String, Codable, CaseIterable, Identifiable, Sendable {
    case leaveOpen
    case close

    var id: Self { self }
    var sapStatus: String { self == .leaveOpen ? "MIAR" : "MMAB" }
}

struct SubdistributionDraftPayload: Codable, Equatable, Sendable {
    static let currentVersion = 1
    static let statusRowID = "0000"
    static let outOfOperationCommentElementID = "TFM7-0000-9B"

    let version: Int
    let localDraftID: String
    var context: SubdistributionCreationContext?
    /// Keyed by `ATNAM`, so a characteristic keeps its SAP identity after a
    /// draft is reopened, even if its title is translated during a new sync.
    var characteristicValues: [String: String]
    var performedOn: Date
    var isOutOfOperation: Bool
    /// The legacy status row (`TFM7-0000-9B`) has its own documentation.
    /// It is deliberately separate from regular inspection comments because
    /// switching to `aBet` clears only normal inspection evidence.
    var outOfOperationComment: String?
    var defectCloseAction: SubdistributionCloseAction?
    var isClosedLocally: Bool
    var inspectionItems: [SubdistributionInspectionItem]
    var photoAttachments: [SubdistributionPhotoAttachment]
    var legacyIdentifiers: SubdistributionLegacyIdentifiers?
    /// The report is not a photo collection: it is one stable PDF document
    /// attached at close time and sent with `TFM7-pdf`.
    var reportPDF: Data?
    var pdfDocumentID: String?
    /// A pre-TFM7 draft may not conform to the structured payload introduced
    /// here. Preserve that valid JSON unchanged so an old local record cannot
    /// prevent the worker's complete offline queue from loading.
    var legacyJSONData: Data?

    var jsonData: Data {
        legacyJSONData ?? (try? JSONEncoder().encode(self)) ?? Data()
    }

    init(localDraftID: String = UUID().uuidString, now: Date = .now) {
        version = Self.currentVersion
        self.localDraftID = localDraftID
        context = nil
        characteristicValues = [:]
        performedOn = now
        isOutOfOperation = false
        outOfOperationComment = nil
        defectCloseAction = nil
        isClosedLocally = false
        inspectionItems = []
        photoAttachments = []
        legacyIdentifiers = nil
        reportPDF = nil
        pdfDocumentID = nil
        legacyJSONData = nil
    }

    init(jsonData: Data) {
        version = Self.currentVersion
        localDraftID = UUID().uuidString
        context = nil
        characteristicValues = [:]
        performedOn = .now
        isOutOfOperation = false
        outOfOperationComment = nil
        defectCloseAction = nil
        isClosedLocally = false
        inspectionItems = []
        photoAttachments = []
        legacyIdentifiers = nil
        reportPDF = nil
        pdfDocumentID = nil
        legacyJSONData = jsonData
    }
}

enum SubdistributionIdentifierFactory {
    static func make() -> SubdistributionLegacyIdentifiers {
        SubdistributionLegacyIdentifiers(
            notificationNumber: temporaryIdentifier(length: 8),
            equipmentNumber: temporaryIdentifier(length: 14),
            processNumber: UUID().uuidString.uppercased()
        )
    }

    private static func temporaryIdentifier(length: Int) -> String {
        let alphabet = Array("0A1B2C3D4E5F6879")
        return "NEU-" + String((0..<length).compactMap { _ in alphabet.randomElement() })
    }
}

/// Demo intentionally has its own deterministic data source.  Production
/// never falls back to it if the SAP cache is incomplete.
struct DemoSubdistributionCreationProvider: SubdistributionCreationProviding {
    func loadSubdistributionCreationData(for workerID: String) async throws -> SubdistributionCreationData {
        let resultValues = [
            SubdistributionValue(value: "1", title: "OK"),
            SubdistributionValue(value: "2", title: "Cleaning required"),
            SubdistributionValue(value: "3", title: "Minor defect"),
            SubdistributionValue(value: "4", title: "Major defect"),
            SubdistributionValue(value: "5", title: "Not present")
        ]
        let actionValues = [
            SubdistributionValue(value: "7", title: "Repair required"),
            SubdistributionValue(value: "8", title: "Repaired"),
            SubdistributionValue(value: "9", title: "Out of service")
        ]
        let template = SubdistributionLegacyTemplate(
            id: "TFMNSPV|A|TFM7_001", equipmentType: "TFMNSPV", formCode: "TFM7",
            planType: "A", planNumber: "TFM7_001", planVersion: "", title: "Unterverteilung",
            plant: "1000", plannerGroup: "001", workCenter: "FM-WORKER",
            className: "TFMUNTERVERT", classType: "002", classGroup: "TFM",
            classDataJSON: "{}", equipmentDataJSON: "{}",
            characteristics: [
                .init(position: 10, name: "TFMSCHUTZSCH_ANZAHL_RCD", title: "Anzahl RCD/FI-Schutzschalter", kind: .numeric, maximumLength: 4, unit: "ST", required: true, values: []),
                .init(position: 20, name: "TFMUNTERVERT_BEZUNTERVERT", title: "Bezeichnung Unterverteilung", kind: .text, maximumLength: 40, unit: "", required: true, values: [])
            ],
            inspectionItems: [
                .init(operation: "0010", title: "Prüfung durch Betätigen der Prüftasten", information: "", resultElementID: "TFM7-0010-1", actionElementID: "TFM7-0010-2", commentElementID: "TFM7-0010-9B", resultValues: resultValues, actionValues: actionValues, requiresResult: true, requiresPhotoAndComment: nil),
                .init(operation: "0020", title: "Sichtkontrolle", information: "", resultElementID: "TFM7-0020-1", actionElementID: "TFM7-0020-2", commentElementID: "TFM7-0020-9B", resultValues: resultValues, actionValues: actionValues, requiresResult: true, requiresPhotoAndComment: nil),
                // The demo flow presents every inspection point as a complete
                // Mobile-Ladder-style row.  Production remains cache-driven:
                // a selector is shown there only when SAP supplies its value
                // help for the corresponding T_PLPOD position.
                .init(operation: "0030", title: "Foto Anlagentechnik (Verteilung)", information: "", resultElementID: "TFM7-0030-1", actionElementID: "TFM7-0030-2", commentElementID: "TFM7-0030-9B", resultValues: resultValues, actionValues: actionValues, requiresResult: true, requiresPhotoAndComment: true)
            ]
        )
        let source: [String: String] = [
            "MANDT": "100", "STRNO": "UN01-ST01-BG01-NSPV-001", "TPLND": "DE", "TPORT": "ST01",
            "TPWEH": "UN01", "TPGEB": "BG01", "TPGSG": "440", "IWERK": "1000", "INGRP": "001", "GEWRK": "FM-WORKER", "EQART": "TFMNSPV"
        ]
        let json = try JSONSerialization.data(withJSONObject: source, options: [.sortedKeys])
        let context = SubdistributionCreationContext(
            businessEntity: "Musterunternehmen · Essen", building: "Bürogebäude",
            parentLocation: "Unterverteilung EG", legacyContext: .init(
                client: "100", functionalLocation: "UN01-ST01-BG01-NSPV-001", parentEquipmentType: "TFMNSPV",
                country: "DE", location: "ST01", businessEntity: "UN01", building: "BG01", segment: "440",
                plant: "1000", plannerGroup: "001", workCenter: "FM-WORKER", addressNumber: "",
                contactName: "", city: "Essen", postalCode: "45127", street: "Musterstraße 27",
                sourceNotificationJSON: String(decoding: json, as: UTF8.self), template: template
            )
        )
        return .init(contexts: [context])
    }
}
