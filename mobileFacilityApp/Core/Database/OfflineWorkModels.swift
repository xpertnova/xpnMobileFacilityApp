import Foundation

enum OfflineWorkType: String, Codable, CaseIterable, Sendable {
    case manualCapture
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

struct OfflineWorkItem: Identifiable, Equatable, Sendable {
    let id: UUID
    let workerID: String
    let type: OfflineWorkType
    let status: OfflineWorkStatus
    let payload: ManualCaptureDraftPayload
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
