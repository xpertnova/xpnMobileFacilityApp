import Foundation

enum OfflineWorkType: String, Codable, CaseIterable, Sendable {
    case manualCapture
    case notificationReview
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

struct NotificationReviewDraftPayload: Codable, Equatable, Sendable {
    var notificationID: String
    var performedOn: Date
    var results: [String: NotificationReviewResult]
    var comments: [String: String]
    var photoItemIDs: [String]
    var isClosedLocally: Bool
}

enum OfflineWorkPayload: Equatable, Sendable {
    case manualCapture(ManualCaptureDraftPayload)
    case notificationReview(NotificationReviewDraftPayload)

    var manualCapture: ManualCaptureDraftPayload? {
        guard case let .manualCapture(payload) = self else { return nil }
        return payload
    }

    var notificationReview: NotificationReviewDraftPayload? {
        guard case let .notificationReview(payload) = self else { return nil }
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
