import Foundation

struct SAPNotificationSummary: Codable, Equatable, Identifiable, Sendable {
    let id: String
    let client: String
    let title: String
    let functionalLocationID: String
    let functionalLocationName: String
    let startDate: String
    let endDate: String
    let systemStatus: String
    let userStatus: String
    let rawPayloadJSON: String

    var displayLocation: String {
        functionalLocationName.isEmpty ? functionalLocationID : functionalLocationName
    }

    var displayDateRange: String {
        switch (startDate.isEmpty, endDate.isEmpty) {
        case (true, true): ""
        case (false, true): startDate
        case (true, false): endDate
        case (false, false) where startDate == endDate: startDate
        case (false, false): "\(startDate) – \(endDate)"
        }
    }

    var displayStatus: String {
        [systemStatus, userStatus]
            .filter { !$0.isEmpty }
            .joined(separator: " · ")
    }
}

struct SAPWorkerProfile: Codable, Equatable, Sendable {
    let personnelNumber: String
    let firstName: String
    let lastName: String
    let organizationUnit: String
    let role: String
    let email: String
    let isActive: String
    let roleCode: String

    var displayName: String {
        [firstName, lastName]
            .filter { !$0.isEmpty }
            .joined(separator: " ")
    }
}

struct SAPCacheMetadata: Codable, Equatable, Sendable {
    let sapWorkerID: String
    let lastSuccessfulRefreshAt: Date
}

struct SAPReadSnapshot: Equatable, Sendable {
    let sapWorkerID: String
    let notifications: [SAPNotificationSummary]
    let workerProfile: SAPWorkerProfile?
}

struct SAPCachedData: Equatable, Sendable {
    let notifications: [SAPNotificationSummary]
    let workerProfile: SAPWorkerProfile?
    let metadata: SAPCacheMetadata?

    static let empty = SAPCachedData(notifications: [], workerProfile: nil, metadata: nil)
}

protocol SAPDataCacheRepository: Sendable {
    func load(for localWorkerID: String) async throws -> SAPCachedData
    func replace(
        with snapshot: SAPReadSnapshot,
        for localWorkerID: String,
        refreshedAt: Date
    ) async throws -> SAPCachedData
}

enum SAPReadRefreshStage: Equatable, Sendable {
    case authenticating
    case uploadingOutgoingMetadata
    case postingOutgoingData
    case waitingForOutgoingAcknowledgement
    case checkingAppVersion
    case preparingIncomingData
    case waitingForIncomingData
    case receivingIncomingPackages
    case savingSnapshot
}

typealias SAPReadRefreshProgressHandler = @MainActor @Sendable (SAPReadRefreshStage) -> Void

protocol SAPNotificationRefreshService: Sendable {
    func refresh(
        sapPassword: String,
        progress: @escaping SAPReadRefreshProgressHandler
    ) async throws -> SAPReadSnapshot
}

enum SAPReadError: LocalizedError {
    case configurationUnavailable
    case authenticatedConnectionUnavailable
    case passwordRequired
    case invalidCredentials
    case initialPasswordChangeRequired
    case preparationTimedOut
    case malformedPayload
    case networkUnavailable
    case requestTimedOut
    case httpStatus(Int)
    case serviceUnavailable
    case backendMessage(String)

    var errorDescription: String? {
        switch self {
        case .configurationUnavailable: "SAP data configuration is unavailable."
        case .authenticatedConnectionUnavailable: "The authenticated SAP connection is unavailable."
        case .passwordRequired: "A SAP synchronization password is required."
        case .invalidCredentials: "The SAP synchronization password is invalid."
        case .initialPasswordChangeRequired: "The SAP synchronization password must be changed before use."
        case .preparationTimedOut: "SAP did not finish preparing the notification data in time."
        case .malformedPayload: "SAP returned data in an unsupported format."
        case .networkUnavailable: "The device could not reach SAP."
        case .requestTimedOut: "The SAP request timed out."
        case let .httpStatus(status): "SAP returned HTTP status \(status)."
        case .serviceUnavailable: "SAP data is unavailable on this device."
        case let .backendMessage(message): message
        }
    }
}

actor InMemorySAPDataCacheRepository: SAPDataCacheRepository {
    private var dataByWorkerID: [String: SAPCachedData] = [:]

    init(seed: SAPCachedData? = nil, workerID: String = "demo") {
        if let seed {
            dataByWorkerID[workerID] = seed
        }
    }

    func load(for localWorkerID: String) async throws -> SAPCachedData {
        dataByWorkerID[localWorkerID] ?? .empty
    }

    func replace(
        with snapshot: SAPReadSnapshot,
        for localWorkerID: String,
        refreshedAt: Date
    ) async throws -> SAPCachedData {
        let data = SAPCachedData(
            notifications: snapshot.notifications,
            workerProfile: snapshot.workerProfile,
            metadata: SAPCacheMetadata(
                sapWorkerID: snapshot.sapWorkerID,
                lastSuccessfulRefreshAt: refreshedAt
            )
        )
        dataByWorkerID[localWorkerID] = data
        return data
    }
}

struct UnavailableSAPDataCacheRepository: SAPDataCacheRepository {
    func load(for localWorkerID: String) async throws -> SAPCachedData {
        throw SAPReadError.serviceUnavailable
    }

    func replace(
        with snapshot: SAPReadSnapshot,
        for localWorkerID: String,
        refreshedAt: Date
    ) async throws -> SAPCachedData {
        throw SAPReadError.serviceUnavailable
    }
}
