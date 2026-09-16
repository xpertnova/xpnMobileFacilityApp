import Foundation

enum OfflineWorkType: String, Codable, CaseIterable, Sendable {
    case manualCapture
    case defect
    case meterReading
    case notificationReview
    case briefing
    case electricalSafety
    case technicalObjectEdit
    case proofOfQualification
    case photoCollection
    case mobileLadder
    case subdistribution
    case elevatorInspection
}

enum LocalPhotoWorkflow: String, Codable, CaseIterable, Sendable {
    case notification
    case defect
    case meterReading
    case briefing
    case electricalSafety
    case firePermit
    case proofOfQualification
    case technicalObject
    case mobileLadder
    case subdistribution

    var titleKey: String {
        switch self {
        case .notification: "notifications.title"
        case .defect: "manual.defect.form.title"
        case .meterReading: "manual.meter.form.title"
        case .briefing: "forms.briefing.title"
        case .electricalSafety: "forms.electrical.title"
        case .firePermit: "forms.fire.title"
        case .proofOfQualification: "forms.qualification.title"
        case .technicalObject: "places.title"
        case .mobileLadder: "mobileLadder.title"
        case .subdistribution: "subdistribution.title"
        }
    }
}

/// Stable, worker-scoped ownership for a local-only photo collection. A row
/// identifier is used only where the business workflow has independent rows,
/// currently maintenance-notification checklist items.
struct LocalPhotoScope: Codable, Equatable, Hashable, Sendable {
    let workflow: LocalPhotoWorkflow
    let ownerID: String
    let rowID: String?
    let displayTitle: String
    let displaySubtitle: String

    init(
        workflow: LocalPhotoWorkflow,
        ownerID: String,
        rowID: String? = nil,
        displayTitle: String,
        displaySubtitle: String = ""
    ) {
        self.workflow = workflow
        self.ownerID = ownerID
        self.rowID = rowID
        self.displayTitle = displayTitle
        self.displaySubtitle = displaySubtitle
    }

    static func == (lhs: Self, rhs: Self) -> Bool {
        lhs.workflow == rhs.workflow && lhs.ownerID == rhs.ownerID && lhs.rowID == rhs.rowID
    }

    func hash(into hasher: inout Hasher) {
        hasher.combine(workflow)
        hasher.combine(ownerID)
        hasher.combine(rowID)
    }
}

struct LocalPhotoAttachment: Codable, Equatable, Identifiable, Sendable {
    let localAttachmentID: String
    let capturedAt: Date
    let name: String
    let description: String

    init(
        localAttachmentID: String,
        capturedAt: Date,
        name: String = "",
        description: String = ""
    ) {
        self.localAttachmentID = localAttachmentID
        self.capturedAt = capturedAt
        self.name = name
        self.description = description
    }

    private enum CodingKeys: String, CodingKey {
        case localAttachmentID
        case capturedAt
        case name
        case description
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        localAttachmentID = try container.decode(String.self, forKey: .localAttachmentID)
        capturedAt = try container.decode(Date.self, forKey: .capturedAt)
        name = try container.decodeIfPresent(String.self, forKey: .name) ?? ""
        description = try container.decodeIfPresent(String.self, forKey: .description) ?? ""
    }

    func updatingMetadata(name: String, description: String) -> Self {
        Self(
            localAttachmentID: localAttachmentID,
            capturedAt: capturedAt,
            name: name,
            description: description
        )
    }

    var id: String { localAttachmentID }
}

struct PhotoCollectionDraftPayload: Codable, Equatable, Sendable {
    let scope: LocalPhotoScope
    var attachments: [LocalPhotoAttachment]
}

enum DefectPriority: String, Codable, CaseIterable, Identifiable, Sendable {
    case low
    case medium
    case high

    var id: String { rawValue }

    var titleKey: String {
        "manual.defect.priority.\(rawValue)"
    }
}

struct DefectDraftPayload: Codable, Equatable, Sendable {
    var technicalObject: TechnicalObjectReference
    var technicalObjectName: String
    var dinGroup: String?
    var priority: DefectPriority
    var shortText: String
    var longText: String
    var attachmentIDs: [String]
}

enum MeterKind: String, Codable, CaseIterable, Identifiable, Sendable {
    case electricity
    case gas
    case water

    var id: String { rawValue }

    var titleKey: String {
        "manual.meter.kind.\(rawValue)"
    }

    var symbol: String {
        switch self {
        case .electricity: "bolt.fill"
        case .gas: "flame.fill"
        case .water: "drop.fill"
        }
    }
}

struct MeterReference: Codable, Equatable, Identifiable, Sendable {
    let id: String
    let kind: MeterKind
    let technicalPlaceID: String
    let technicalPlaceName: String
    let unit: String
    let previousValue: Decimal
    let previousReadingAt: Date
}

struct MeterReadingDraftPayload: Codable, Equatable, Sendable {
    var meter: MeterReference
    var value: Decimal
    var note: String
}

/// A local proposal for editable equipment master data. SAP identifiers are
/// captured once and never exposed as mutable draft fields.
struct TechnicalObjectEditPayload: Codable, Equatable, Sendable {
    let equipmentID: String
    let functionalLocationID: String
    var designation: String
    var manufacturer: String
    var modelType: String
    var serialNumber: String
    var dinGroup: String?
    var nextInspectionDate: Date?
    let sourceFingerprint: String
}

enum OfflineWorkStatus: String, Codable, CaseIterable, Sendable {
    case draft
    case pendingSynchronization
    case synchronizing
    case synchronized
    case failed
    case conflict

    var titleKey: String {
        switch self {
        case .draft: "offline.status.draft"
        case .pendingSynchronization: "offline.status.pending"
        case .synchronizing: "offline.status.synchronizing"
        case .synchronized: "offline.status.synchronized"
        case .failed: "offline.status.failed"
        case .conflict: "offline.status.conflict"
        }
    }
}

struct ManualCaptureDraftPayload: Codable, Equatable, Sendable {
    var categoryKey: String
    var location: String
    var note: String
}

enum NotificationReviewResult: String, Codable, Equatable, Sendable {
    case no
    case yes
}

/// The minimum notification detail required to reopen an inspection without
/// depending on the current SAP cache. It deliberately contains no SAP SDK
/// types or transport payload.
struct OfflineNotificationSnapshot: Codable, Equatable, Sendable {
    struct InspectionItem: Codable, Equatable, Sendable {
        let id: String
        let title: String
        let information: String
        let resultElementID: String?
        let commentElementID: String?
        /// Optional so a draft written before checklist group bands existed
        /// still decodes; a missing key simply means "no group".
        let groupTitle: String?

        init(
            id: String,
            title: String,
            information: String,
            resultElementID: String? = nil,
            commentElementID: String? = nil,
            groupTitle: String? = nil
        ) {
            self.id = id
            self.title = title
            self.information = information
            self.resultElementID = resultElementID
            self.commentElementID = commentElementID
            self.groupTitle = groupTitle
        }
    }

    let title: String
    let functionalLocationID: String
    let functionalLocationName: String
    let startDate: String
    let endDate: String
    let systemStatus: String
    let userStatus: String
    let structure: String
    let equipmentID: String
    let inspectionItems: [InspectionItem]
    let address: String?
    let formCode: String?

    init(
        title: String,
        functionalLocationID: String,
        functionalLocationName: String,
        startDate: String,
        endDate: String,
        systemStatus: String,
        userStatus: String,
        structure: String,
        equipmentID: String,
        inspectionItems: [InspectionItem],
        address: String? = nil,
        formCode: String? = nil
    ) {
        self.title = title
        self.functionalLocationID = functionalLocationID
        self.functionalLocationName = functionalLocationName
        self.startDate = startDate
        self.endDate = endDate
        self.systemStatus = systemStatus
        self.userStatus = userStatus
        self.structure = structure
        self.equipmentID = equipmentID
        self.inspectionItems = inspectionItems
        self.address = address
        self.formCode = formCode
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        title = try container.decode(String.self, forKey: .title)
        functionalLocationID = try container.decode(String.self, forKey: .functionalLocationID)
        functionalLocationName = try container.decode(String.self, forKey: .functionalLocationName)
        startDate = try container.decode(String.self, forKey: .startDate)
        endDate = try container.decode(String.self, forKey: .endDate)
        systemStatus = try container.decode(String.self, forKey: .systemStatus)
        userStatus = try container.decode(String.self, forKey: .userStatus)
        structure = try container.decode(String.self, forKey: .structure)
        equipmentID = try container.decode(String.self, forKey: .equipmentID)
        inspectionItems = try container.decode([InspectionItem].self, forKey: .inspectionItems)
        address = try container.decodeIfPresent(String.self, forKey: .address)
        formCode = try container.decodeIfPresent(String.self, forKey: .formCode)
    }
}

struct NotificationPhotoAttachment: Codable, Equatable, Identifiable, Sendable {
    let localAttachmentID: String
    let checklistItemID: String
    let sapElementID: String
    let capturedAt: Date
    let sapDocumentID: String
    let name: String
    let description: String

    init(
        localAttachmentID: String,
        checklistItemID: String,
        sapElementID: String,
        capturedAt: Date,
        sapDocumentID: String,
        name: String = "",
        description: String = ""
    ) {
        self.localAttachmentID = localAttachmentID
        self.checklistItemID = checklistItemID
        self.sapElementID = sapElementID
        self.capturedAt = capturedAt
        self.sapDocumentID = sapDocumentID
        self.name = name
        self.description = description
    }

    private enum CodingKeys: String, CodingKey {
        case localAttachmentID
        case checklistItemID
        case sapElementID
        case capturedAt
        case sapDocumentID
        case name
        case description
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        localAttachmentID = try container.decode(String.self, forKey: .localAttachmentID)
        checklistItemID = try container.decode(String.self, forKey: .checklistItemID)
        sapElementID = try container.decode(String.self, forKey: .sapElementID)
        capturedAt = try container.decode(Date.self, forKey: .capturedAt)
        sapDocumentID = try container.decode(String.self, forKey: .sapDocumentID)
        name = try container.decodeIfPresent(String.self, forKey: .name) ?? ""
        description = try container.decodeIfPresent(String.self, forKey: .description) ?? ""
    }

    func updatingMetadata(name: String, description: String) -> Self {
        Self(
            localAttachmentID: localAttachmentID,
            checklistItemID: checklistItemID,
            sapElementID: sapElementID,
            capturedAt: capturedAt,
            sapDocumentID: sapDocumentID,
            name: name,
            description: description
        )
    }

    var id: String { sapDocumentID }
}

struct NotificationReviewDraftPayload: Codable, Equatable, Sendable {
    var notificationID: String
    var performedOn: Date
    var results: [String: NotificationReviewResult]
    var comments: [String: String]
    var photoAttachments: [NotificationPhotoAttachment]
    var isClosedLocally: Bool
    var notificationSnapshot: OfflineNotificationSnapshot? = nil
    var outgoingProcessID: String? = nil

    init(
        notificationID: String,
        performedOn: Date,
        results: [String: NotificationReviewResult],
        comments: [String: String],
        photoAttachments: [NotificationPhotoAttachment],
        isClosedLocally: Bool,
        notificationSnapshot: OfflineNotificationSnapshot? = nil,
        outgoingProcessID: String? = nil
    ) {
        self.notificationID = notificationID
        self.performedOn = performedOn
        self.results = results
        self.comments = comments
        self.photoAttachments = photoAttachments
        self.isClosedLocally = isClosedLocally
        self.notificationSnapshot = notificationSnapshot
        self.outgoingProcessID = outgoingProcessID
    }

    private enum CodingKeys: String, CodingKey {
        case notificationID
        case performedOn
        case results
        case comments
        case photoAttachments
        case photoItemIDs
        case isClosedLocally
        case notificationSnapshot
        case outgoingProcessID
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        notificationID = try container.decode(String.self, forKey: .notificationID)
        performedOn = try container.decode(Date.self, forKey: .performedOn)
        results = try container.decode([String: NotificationReviewResult].self, forKey: .results)
        comments = try container.decode([String: String].self, forKey: .comments)
        photoAttachments = try container.decodeIfPresent(
            [NotificationPhotoAttachment].self,
            forKey: .photoAttachments
        ) ?? []
        isClosedLocally = try container.decode(Bool.self, forKey: .isClosedLocally)
        notificationSnapshot = try container.decodeIfPresent(
            OfflineNotificationSnapshot.self,
            forKey: .notificationSnapshot
        )
        outgoingProcessID = try container.decodeIfPresent(String.self, forKey: .outgoingProcessID)
        // Older versions stored only checklist IDs in `photoItemIDs`; those
        // values represented a colored icon and never referred to image data.
        // Decode the key for compatibility, but deliberately do not turn it
        // into an uploadable attachment.
        _ = try container.decodeIfPresent([String].self, forKey: .photoItemIDs)
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(notificationID, forKey: .notificationID)
        try container.encode(performedOn, forKey: .performedOn)
        try container.encode(results, forKey: .results)
        try container.encode(comments, forKey: .comments)
        try container.encode(photoAttachments, forKey: .photoAttachments)
        try container.encode(isClosedLocally, forKey: .isClosedLocally)
        try container.encodeIfPresent(notificationSnapshot, forKey: .notificationSnapshot)
        try container.encodeIfPresent(outgoingProcessID, forKey: .outgoingProcessID)
    }
}

/// Worker-scoped, locally retained briefing data. It preserves SAP answer
/// keys and source identifiers so presentation text never becomes a backend
/// contract. A pending briefing is not considered SAP-synchronized.
struct BriefingDraftPayload: Codable, Equatable, Sendable {
    var templateID: String
    var businessEntityID: String
    var businessEntityTitle: String
    var buildingCode: String
    var buildingTitle: String
    var coordinator: String
    var instructedPerson: String
    var selectedPartnerID: String
    var temporaryPartner: BriefingTemporaryPartner?
    var partnerEmail: String
    var taskDescription: String
    var startDate: Date
    var endDate: Date
    var selectedOptionalSectionIDs: Set<String>
    var answerKeysByItemID: [String: String]
    var commentsByItemID: [String: String]
    var instructorSignature: Data?
    var instructedPersonSignature: Data?
    var completedAt: Date?
}

/// A partner entered for this briefing only. The legacy workflow calls these
/// `NEU…` partners and defers SAP submission until a sanctioned write payload
/// exists, so the complete value-help input stays in the local draft.
struct BriefingTemporaryPartner: Codable, Equatable, Sendable {
    var id: String
    var company: String
    var title: String
    var contactName: String
    var email: String
    var telephone: String
    var street: String
    var houseNumber: String
    var postalCode: String
    var city: String
    var country: String

    var asSAPPartner: SAPBriefingPartner {
        SAPBriefingPartner(
            id: id,
            client: "",
            function: "ZT",
            name: company,
            contactName: contactName,
            searchTerm1: "",
            searchTerm2: "",
            street: street,
            houseNumber: houseNumber,
            postalCode: postalCode,
            city: city,
            country: country,
            email: email
        )
    }
}

enum OfflineWorkPayload: Equatable, Sendable {
    case manualCapture(ManualCaptureDraftPayload)
    case defect(DefectDraftPayload)
    case meterReading(MeterReadingDraftPayload)
    case notificationReview(NotificationReviewDraftPayload)
    case briefing(BriefingDraftPayload)
    case electricalSafety(ElectricalSafetyDraftPayload)
    case technicalObjectEdit(TechnicalObjectEditPayload)
    case proofOfQualification(ProofOfQualificationDraftPayload)
    case photoCollection(PhotoCollectionDraftPayload)
    case mobileLadder(MobileLadderDraftPayload)
    case subdistribution(SubdistributionDraftPayload)
    case elevatorInspection(ElevatorInspectionDraftPayload)

    var manualCapture: ManualCaptureDraftPayload? {
        guard case let .manualCapture(payload) = self else { return nil }
        return payload
    }

    var defect: DefectDraftPayload? {
        guard case let .defect(payload) = self else { return nil }
        return payload
    }

    var meterReading: MeterReadingDraftPayload? {
        guard case let .meterReading(payload) = self else { return nil }
        return payload
    }

    var notificationReview: NotificationReviewDraftPayload? {
        guard case let .notificationReview(payload) = self else { return nil }
        return payload
    }

    var briefing: BriefingDraftPayload? {
        guard case let .briefing(payload) = self else { return nil }
        return payload
    }

    var electricalSafety: ElectricalSafetyDraftPayload? {
        guard case let .electricalSafety(payload) = self else { return nil }
        return payload
    }

    var technicalObjectEdit: TechnicalObjectEditPayload? {
        guard case let .technicalObjectEdit(payload) = self else { return nil }
        return payload
    }

    var proofOfQualification: ProofOfQualificationDraftPayload? {
        guard case let .proofOfQualification(payload) = self else { return nil }
        return payload
    }

    var photoCollection: PhotoCollectionDraftPayload? {
        guard case let .photoCollection(payload) = self else { return nil }
        return payload
    }

    var mobileLadder: MobileLadderDraftPayload? {
        guard case let .mobileLadder(payload) = self else { return nil }
        return payload
    }

    var subdistribution: SubdistributionDraftPayload? {
        guard case let .subdistribution(payload) = self else { return nil }
        return payload
    }

    var elevatorInspection: ElevatorInspectionDraftPayload? {
        guard case let .elevatorInspection(payload) = self else { return nil }
        return payload
    }
}

/// Worker-scoped user profile data cached from the `USER` table.
struct SAPUserProfile: Codable, Equatable, Sendable {
    let personalNumber: String
    let name: String
    let firstName: String
    let company: String
    let email: String
    let canCreateI2: Bool

    init(
        personalNumber: String = "",
        name: String = "",
        firstName: String = "",
        company: String = "",
        email: String = "",
        canCreateI2: Bool = false
    ) {
        self.personalNumber = personalNumber
        self.name = name
        self.firstName = firstName
        self.company = company
        self.email = email
        self.canCreateI2 = canCreateI2
    }
}

struct OfflineWorkItem: Identifiable, Equatable, Sendable {
    let id: UUID
    let workerID: String
    let type: OfflineWorkType
    let status: OfflineWorkStatus
    let payload: OfflineWorkPayload
    let createdAt: Date
    let updatedAt: Date
    let syncError: String?
}

enum OfflineWorkRepositoryError: LocalizedError {
    case unavailable
    case invalidStoredItem

    var errorDescription: String? {
        switch self {
        case .unavailable: "The local work store is unavailable."
        case .invalidStoredItem: "A locally saved work item cannot be read."
        }
    }
}
