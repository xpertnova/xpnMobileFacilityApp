import Foundation

enum OfflineWorkType: String, Codable, CaseIterable, Sendable {
    case manualCapture
    case notificationReview
    case briefing
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
}

struct NotificationReviewDraftPayload: Codable, Equatable, Sendable {
    var notificationID: String
    var performedOn: Date
    var results: [String: NotificationReviewResult]
    var comments: [String: String]
    var photoItemIDs: [String]
    var isClosedLocally: Bool
    var notificationSnapshot: OfflineNotificationSnapshot? = nil
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
    case notificationReview(NotificationReviewDraftPayload)
    case briefing(BriefingDraftPayload)

    var manualCapture: ManualCaptureDraftPayload? {
        guard case let .manualCapture(payload) = self else { return nil }
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
