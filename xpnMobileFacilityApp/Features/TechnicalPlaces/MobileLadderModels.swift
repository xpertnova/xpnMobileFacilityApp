import Foundation

struct MobileLadderCreationData: Equatable, Sendable {
    let contexts: [MobileLadderCreationContext]
    let catalog: MobileLadderCatalog

    static let empty = Self(contexts: [], catalog: .empty)
}

protocol MobileLadderCreationProviding: Sendable {
    func loadMobileLadderCreationData(for workerID: String) async throws -> MobileLadderCreationData
}

struct UnavailableMobileLadderCreationProvider: MobileLadderCreationProviding {
    func loadMobileLadderCreationData(for workerID: String) async throws -> MobileLadderCreationData {
        throw SAPReadError.serviceUnavailable
    }
}

struct MobileLadderCreationContext: Codable, Equatable, Identifiable, Sendable {
    let businessEntity: String
    let building: String
    let trade: String
    let legacyContext: MobileLadderLegacyContext

    var id: String {
        [legacyContext.functionalLocation, businessEntity, building, trade].joined(separator: "|")
    }
}

struct MobileLadderLegacyContext: Codable, Equatable, Sendable {
    let client: String
    let functionalLocation: String
    let country: String
    let location: String
    let businessEntity: String
    let building: String
    let trade: String
    let plant: String
    let plannerGroup: String
    let workCenter: String
    let addressNumber: String
    let contactName: String
    let city: String
    let postalCode: String
    let street: String
    let sourceNotificationJSON: String
    let template: MobileLadderLegacyTemplate
}

struct MobileLadderLegacyTemplate: Codable, Equatable, Identifiable, Sendable {
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
    let characteristics: [MobileLadderLegacyCharacteristic]
    let inspectionItems: [MobileLadderLegacyInspectionDefinition]
    /// The `T0267` plan row without `T_PLPOD`. Optional to keep drafts saved
    /// before it was captured readable.
    var planDataJSON: String? = nil
}

struct MobileLadderLegacyCharacteristic: Codable, Equatable, Identifiable, Sendable {
    let position: Int
    let name: String
    let title: String
    let unit: String
    let required: Bool
    let values: [MobileLadderLegacyValue]

    var id: String { name }
}

struct MobileLadderLegacyValue: Codable, Equatable, Identifiable, Sendable {
    let value: String
    let title: String

    var id: String { value }
}

struct MobileLadderLegacyInspectionDefinition: Codable, Equatable, Identifiable, Sendable {
    let operation: String
    let title: String
    let information: String
    let resultElementID: String
    let actionElementID: String
    let commentElementID: String

    var id: String { operation }
}

struct MobileLadderLegacyIdentifiers: Codable, Equatable, Sendable {
    let notificationNumber: String
    let equipmentNumber: String
    let processNumber: String
}

enum MobileLadderCatalogField: String, CaseIterable, Codable, Identifiable, Sendable {
    case material
    case constructionType
    case manufacturer
    case clientCompany

    var id: Self { self }

    var titleKey: String {
        switch self {
        case .material: "mobileLadder.field.material"
        case .constructionType: "mobileLadder.field.type"
        case .manufacturer: "mobileLadder.field.manufacturer"
        case .clientCompany: "mobileLadder.field.clientCompany"
        }
    }

    /// SAP class characteristic (`ATNAM`) the field is stored in. It is also
    /// the element of the field's `TO_T0211` proposal.
    var characteristicName: String {
        switch self {
        case .material: "TFMMOBLEITER_WERKSTOFF"
        case .constructionType: "TFMMOBLEITER_BAUART"
        case .manufacturer: "TFMMOBLEITER_HERSTELLER"
        case .clientCompany: "TFMMOBLEITER_GESELLSCHAFT"
        }
    }

    var iconName: String {
        switch self {
        case .material: "cube.box"
        case .constructionType: "hammer"
        case .manufacturer: "wrench.and.screwdriver"
        case .clientCompany: "building.2"
        }
    }
}

struct MobileLadderCatalog: Equatable, Sendable {
    var options: [MobileLadderCatalogField: [String]]

    func options(for field: MobileLadderCatalogField) -> [String] {
        let current = options[field, default: []]
        if !current.isEmpty {
            return current
        }
        return Self.legacyReference.options[field, default: []]
    }

    /// Values retained locally while the SAP value-help contract is not yet available.
    /// The material options are transcribed from the legacy picker. The remaining
    /// lookups remain editable and will be replaced by the captured SAP lists.
    static let legacyReference = Self(options: [
        .material: [
            "Pflege durch Admin",
            "nicht bekannt",
            "Aluminium",
            "Edelstahl",
            "Glasfaser",
            "Holz",
            "Kunststoff",
            "Stahl"
        ],
        .constructionType: ["Anlegeleiter", "Stehleiter", "Podestleiter"],
        .manufacturer: ["ZARGES", "HYMER", "KRAUSE"],
        .clientCompany: [
            "Pflege durch Admin"
        ]
    ])

    static let demo = legacyReference
    static let empty = Self(options: [:])
}

enum MobileLadderInspectionResult: String, Codable, CaseIterable, Identifiable, Sendable {
    case okay = "1"
    case cleaningRequired = "2"
    case minorDefect = "3"
    case majorDefect = "4"
    case notPresent = "5"

    var id: Self { self }

    /// SAP's TFM5 result code, shown in the inspection selector and persisted
    /// independently of the localized title.
    var code: String { rawValue }

    var titleKey: String {
        switch self {
        case .okay: "mobileLadder.result.okay"
        case .cleaningRequired: "mobileLadder.result.cleaningRequired"
        case .minorDefect: "mobileLadder.result.minorDefect"
        case .majorDefect: "mobileLadder.result.majorDefect"
        case .notPresent: "mobileLadder.result.notPresent"
        }
    }
}

enum MobileLadderInspectionAction: String, Codable, CaseIterable, Identifiable, Sendable {
    case repair = "7"
    case repaired = "8"
    case outOfService = "9"

    var id: Self { self }

    /// SAP's optional TFM5 action code, shown in the inspection selector.
    var code: String { rawValue }

    var titleKey: String {
        switch self {
        case .repair: "mobileLadder.action.repairRequired"
        case .repaired: "mobileLadder.action.repaired"
        case .outOfService: "mobileLadder.action.outOfService"
        }
    }
}

struct MobileLadderInspectionItem: Codable, Equatable, Identifiable, Sendable {
    let id: String
    let number: Int
    let title: String
    let information: String
    let resultElementID: String
    let actionElementID: String
    let commentElementID: String
    var result: MobileLadderInspectionResult?
    var action: MobileLadderInspectionAction?
    var comment: String

    init(definition: MobileLadderLegacyInspectionDefinition, number: Int) {
        id = definition.operation
        self.number = number
        title = definition.title
        information = definition.information
        resultElementID = definition.resultElementID
        actionElementID = definition.actionElementID
        commentElementID = definition.commentElementID
        result = nil
        action = nil
        comment = ""
    }
}

struct MobileLadderPhotoAttachment: Codable, Equatable, Identifiable, Sendable {
    let localAttachmentID: String
    let inspectionItemID: String
    let sapElementID: String
    let capturedAt: Date
    let sapDocumentID: String

    var id: String { sapDocumentID }
}

struct MobileLadderDraftPayload: Codable, Equatable, Sendable {
    static let currentVersion = 1
    /// The legacy TFM5 header row that carries the Demontiert status, its
    /// remark, and its optional documentation photos.
    static let disassembledStatusRowID = "0000"

    let version: Int
    let localDraftID: String
    var material: String
    var constructionType: String
    var factoryNumber: String
    var manufacturer: String
    var rungCount: String
    var clientCompany: String
    var room: String
    var inventoryNumber: String
    var designation: String
    var context: MobileLadderCreationContext?
    var performedOn: Date
    var isDisassembled: Bool
    /// Optional to keep previously saved version-1 drafts readable.
    var disassembledComment: String?
    /// Mirrors notification review closure: a locally closed ladder is
    /// immutable while it waits for the next synchronization.
    var isClosedLocally: Bool?
    var inspectionItems: [MobileLadderInspectionItem]
    var photoAttachments: [MobileLadderPhotoAttachment]
    var legacyIdentifiers: MobileLadderLegacyIdentifiers?
    /// `Vorschlag` text per catalog characteristic (`ATNAM`) that holds
    /// "Pflege durch Admin". Optional to keep earlier version-1 drafts
    /// readable.
    var proposals: [String: String]?
    /// The `TFM5-pdf` report, rendered once when the ladder is closed.
    /// Optional to keep drafts closed before it existed readable.
    var reportPDF: Data?
    var pdfDocumentID: String?
    /// When the report was rendered, i.e. the form was closed: its
    /// `Bericht_<dd_MM_yyyy_HH_mm_ss_SSS>` document name.
    var reportCreatedAt: Date?

    init(localDraftID: String = UUID().uuidString, now: Date = .now) {
        version = Self.currentVersion
        self.localDraftID = localDraftID
        material = ""
        constructionType = ""
        factoryNumber = ""
        manufacturer = ""
        rungCount = ""
        clientCompany = ""
        room = ""
        inventoryNumber = ""
        designation = ""
        context = nil
        performedOn = now
        isDisassembled = false
        disassembledComment = nil
        isClosedLocally = false
        inspectionItems = []
        photoAttachments = []
        legacyIdentifiers = nil
        proposals = [:]
        reportPDF = nil
        pdfDocumentID = nil
        reportCreatedAt = nil
    }

    func value(for field: MobileLadderCatalogField) -> String {
        switch field {
        case .material: material
        case .constructionType: constructionType
        case .manufacturer: manufacturer
        case .clientCompany: clientCompany
        }
    }

    mutating func setValue(_ value: String, for field: MobileLadderCatalogField) {
        switch field {
        case .material: material = value
        case .constructionType: constructionType = value
        case .manufacturer: manufacturer = value
        case .clientCompany: clientCompany = value
        }
    }

    func selectsAdmin(_ field: MobileLadderCatalogField) -> Bool {
        MasterDataProposalRules.isAdmin(text: value(for: field))
    }

    func proposal(for field: MobileLadderCatalogField) -> String {
        proposals?[field.characteristicName] ?? ""
    }

    /// Proposals of the fields that still hold "Pflege durch Admin", which
    /// are the ones sent as `TO_T0211` rows.
    var outgoingProposals: [String: String] {
        MobileLadderCatalogField.allCases.reduce(into: [:]) { result, field in
            let proposal = MasterDataProposalRules.normalized(self.proposal(for: field))
            if selectsAdmin(field), !proposal.isEmpty {
                result[field.characteristicName] = proposal
            }
        }
    }
}

enum MobileLadderIdentifierFactory {
    static func make() -> MobileLadderLegacyIdentifiers {
        MobileLadderLegacyIdentifiers(
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

struct DemoMobileLadderCreationProvider: MobileLadderCreationProviding {
    func loadMobileLadderCreationData(for workerID: String) async throws -> MobileLadderCreationData {
        let template = MobileLadderLegacyTemplate(
            id: "TFMLEITERN|A|00040015", equipmentType: "TFMLEITERN", formCode: "TFM5",
            planType: "A", planNumber: "00040015", planVersion: "", title: "Mobile ladder",
            plant: "1000", plannerGroup: "001", workCenter: "FM-WORKER",
            className: "TFMMOBLEITER", classType: "002", classGroup: "TFM",
            classDataJSON: "{}", equipmentDataJSON: "{}", characteristics: [],
            inspectionItems: [
                ("0010", "Rails", "Check rails for damage"),
                ("0020", "Rungs", "Check rungs and steps"),
                ("0030", "Spreaders", "Check spreaders and locks"),
                ("0040", "Fittings", "Check fittings"),
                ("0050", "Rollers", "Check rollers"),
                ("0060", "Accessories", "Check accessories"),
                ("0070", "Marking", "Check safety marking")
            ].map { operation, title, information in
                MobileLadderLegacyInspectionDefinition(
                    operation: operation, title: title, information: information,
                    resultElementID: "TFM5-\(operation)-1",
                    actionElementID: "TFM5-\(operation)-2",
                    commentElementID: "TFM5-\(operation)-9B"
                )
            }
        )
        let source: [String: Any] = [
            "MANDT": "100", "STRNO": "UN01-ST01-BG01-TECH-350", "TPLND": "DE",
            "TPORT": "ST01", "TPWEH": "UN01", "TPGEB": "BG01", "TPGSG": "350",
            "IWERK": "1000", "INGRP": "001", "GEWRK": "FM-WORKER"
        ]
        let data = try JSONSerialization.data(withJSONObject: source, options: [.sortedKeys])
        let context = MobileLadderCreationContext(
            businessEntity: "Musterunternehmen · Essen",
            building: "Bürogebäude",
            trade: "350 Leitern und Tritte",
            legacyContext: MobileLadderLegacyContext(
                client: "100", functionalLocation: "UN01-ST01-BG01-TECH-350",
                country: "DE", location: "ST01", businessEntity: "UN01", building: "BG01", trade: "350",
                plant: "1000", plannerGroup: "001", workCenter: "FM-WORKER", addressNumber: "DEMO-1",
                contactName: "", city: "Essen", postalCode: "45127", street: "Musterstraße 1",
                sourceNotificationJSON: String(data: data, encoding: .utf8) ?? "{}", template: template
            )
        )
        return MobileLadderCreationData(contexts: [context], catalog: .demo)
    }
}

/// A new form carries the place it was opened from in the route itself, so
/// the form reads it on every load instead of taking a one-shot value that a
/// restarted `.task` would already have consumed.
enum TechnicalPlacesRoute: Equatable {
    case hierarchy
    case createMobileLadder(TechnicalPlaceCreationAnchor?)
    case mobileLadderDraft(UUID)
    case createSubdistribution(TechnicalPlaceCreationAnchor?)
    case subdistributionDraft(UUID)
}

extension String {
    func ifEmpty(_ fallback: String) -> String { isEmpty ? fallback : self }
}

extension Sequence where Element == String {
    func uniquedAndSorted() -> [String] {
        Array(Set(filter { !$0.isEmpty })).sorted { $0.localizedStandardCompare($1) == .orderedAscending }
    }
}
