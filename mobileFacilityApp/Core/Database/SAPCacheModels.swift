import Foundation

/// The confirmed legacy hierarchy embedded in a notification's cached SAP
/// payload. It is intentionally read-only and remains entirely local.
struct NotificationStructuralFilter: Codable, Equatable, Hashable, Sendable {
    var businessEntityID: String = ""
    var buildingCode: String = ""
    var tradeCode: String = ""
    var formCode: String = ""

    static let empty = NotificationStructuralFilter()

    var hasBusinessEntity: Bool {
        !businessEntityID.isEmpty
    }

    func matches(_ metadata: NotificationStructuralFilterMetadata?) -> Bool {
        guard hasBusinessEntity else { return true }
        guard let metadata, metadata.businessEntityID == businessEntityID else { return false }
        return (buildingCode.isEmpty || metadata.buildingCode == buildingCode)
            && (tradeCode.isEmpty || metadata.tradeCode == tradeCode)
            && (formCode.isEmpty || metadata.formCode == formCode)
    }
}

struct NotificationStructuralFilterMetadata: Codable, Equatable, Hashable, Sendable, Identifiable {
    let countryCode: String
    let locationCode: String
    let businessEntityCode: String
    let buildingCode: String
    let tradeCode: String
    let formCode: String
    let functionalLocationName: String

    var id: String {
        [countryCode, locationCode, businessEntityCode, buildingCode, tradeCode, formCode]
            .joined(separator: "-")
    }

    var businessEntityID: String {
        [countryCode, locationCode, businessEntityCode]
            .filter { !$0.isEmpty }
            .joined(separator: "-")
    }
}

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

    var structuralFilterMetadata: NotificationStructuralFilterMetadata? {
        guard
            let data = rawPayloadJSON.data(using: .utf8),
            var payload = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
        else {
            return nil
        }

        // Older caches can contain the original FELDWERT rather than its
        // decoded contents. Preserve their usefulness without a cache reset.
        if value(named: "T_PLPOD", in: payload) == nil,
           let feldwert = value(named: "FELDWERT", in: payload) as? String,
           let planData = decodeSAPNotificationPayload(fromFeldwert: feldwert) {
            payload.merge(planData) { _, planValue in planValue }
        }

        let businessEntityCode = stringValue(named: "TPWEH", in: payload)
        guard !businessEntityCode.isEmpty else { return nil }
        let positions = value(named: "T_PLPOD", in: payload) as? [Any]
        let firstPosition = positions?.first as? [String: Any]
        let directFormCode = stringValue(named: "STEUS", in: payload)

        return NotificationStructuralFilterMetadata(
            countryCode: stringValue(named: "TPLND", in: payload),
            locationCode: stringValue(named: "TPORT", in: payload),
            businessEntityCode: businessEntityCode,
            buildingCode: stringValue(named: "TPGEB", in: payload),
            tradeCode: stringValue(named: "TPGSG", in: payload),
            formCode: directFormCode.isEmpty
                ? stringValue(named: "STEUS", in: firstPosition ?? [:])
                : directFormCode,
            functionalLocationName: functionalLocationName
        )
    }

    private func value(named key: String, in dictionary: [String: Any]) -> Any? {
        dictionary.first { $0.key.caseInsensitiveCompare(key) == .orderedSame }?.value
    }

    private func stringValue(named key: String, in dictionary: [String: Any]) -> String {
        switch value(named: key, in: dictionary) {
        case let value as String:
            value.trimmingCharacters(in: .whitespacesAndNewlines)
        case let value as NSNumber:
            value.stringValue
        default:
            ""
        }
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

struct SAPNotificationPage: Equatable, Sendable {
    let notifications: [SAPNotificationSummary]
    let nextOffset: Int?
    let totalCount: Int

    static let empty = SAPNotificationPage(notifications: [], nextOffset: nil, totalCount: 0)
}

/// Read-only notification detail rebuilt from the SAP `T_0271` row and its
/// decoded `FELDWERT.T_PLPOD` inspection positions.
struct SAPNotificationDetail: Equatable, Sendable {
    struct InspectionItem: Identifiable, Equatable, Sendable {
        let id: String
        let title: String
        let information: String
    }

    let summary: SAPNotificationSummary
    let structure: String
    let equipmentID: String
    let inspectionItems: [InspectionItem]

    init(summary: SAPNotificationSummary) {
        self.summary = summary
        guard
            let data = summary.rawPayloadJSON.data(using: .utf8),
            var payload = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
        else {
            structure = ""
            equipmentID = ""
            inspectionItems = []
            return
        }

        // Caches created before the detail screen retained the original SAP
        // `FELDWERT`; decode it on demand so users do not have to lose their
        // current offline cache before the next refresh.
        if Self.value(named: "T_PLPOD", in: payload) == nil,
           let feldwert = Self.value(named: "FELDWERT", in: payload) as? String,
           let planData = decodeSAPNotificationPayload(fromFeldwert: feldwert) {
            payload.merge(planData) { _, planValue in planValue }
        }

        structure = Self.stringValue(named: "STRUR", in: payload)
        equipmentID = Self.stringValue(named: "EQUNR", in: payload)
        let rows = Self.value(named: "T_PLPOD", in: payload) as? [[String: Any]] ?? []
        inspectionItems = rows.enumerated().compactMap { index, row in
            let rowType = Self.stringValue(named: "USR00", in: row)
            let fallbackRowType = Self.stringValue(named: "DNAME", in: row)
            let normalizedRowType = (rowType.isEmpty ? fallbackRowType : rowType).uppercased()
            guard !["HEADER", "U1", "FOTO"].contains(normalizedRowType) else { return nil }
            let title = Self.stringValue(named: "LTXA1", in: row)
            guard !title.isEmpty else { return nil }
            let operation = Self.stringValue(named: "VORNR", in: row)
            return InspectionItem(
                id: operation.isEmpty ? "position-\(index)" : operation,
                title: title,
                information: Self.stringValue(named: "LTXA2", in: row)
            )
        }
    }

    init(offlineSnapshot: OfflineNotificationSnapshot, notificationID: String) {
        summary = SAPNotificationSummary(
            id: notificationID,
            client: "",
            title: offlineSnapshot.title,
            functionalLocationID: offlineSnapshot.functionalLocationID,
            functionalLocationName: offlineSnapshot.functionalLocationName,
            startDate: offlineSnapshot.startDate,
            endDate: offlineSnapshot.endDate,
            systemStatus: offlineSnapshot.systemStatus,
            userStatus: offlineSnapshot.userStatus,
            rawPayloadJSON: ""
        )
        structure = offlineSnapshot.structure
        equipmentID = offlineSnapshot.equipmentID
        inspectionItems = offlineSnapshot.inspectionItems.map {
            InspectionItem(id: $0.id, title: $0.title, information: $0.information)
        }
    }

    private static func value(named key: String, in dictionary: [String: Any]) -> Any? {
        dictionary.first { $0.key.caseInsensitiveCompare(key) == .orderedSame }?.value
    }

    private static func stringValue(named key: String, in dictionary: [String: Any]) -> String {
        switch value(named: key, in: dictionary) {
        case let value as String:
            value.trimmingCharacters(in: .whitespacesAndNewlines)
        case let value as NSNumber:
            value.stringValue
        default:
            ""
        }
    }
}

extension OfflineNotificationSnapshot {
    init(detail: SAPNotificationDetail) {
        title = detail.summary.title
        functionalLocationID = detail.summary.functionalLocationID
        functionalLocationName = detail.summary.functionalLocationName
        startDate = detail.summary.startDate
        endDate = detail.summary.endDate
        systemStatus = detail.summary.systemStatus
        userStatus = detail.summary.userStatus
        structure = detail.structure
        equipmentID = detail.equipmentID
        inspectionItems = detail.inspectionItems.map {
            InspectionItem(id: $0.id, title: $0.title, information: $0.information)
        }
    }
}

protocol SAPDataCacheRepository: Sendable {
    func load(for localWorkerID: String) async throws -> SAPCachedData
    func loadNotifications(
        for localWorkerID: String,
        matching searchText: String,
        structuralFilter: NotificationStructuralFilter,
        limit: Int,
        offset: Int
    ) async throws -> SAPNotificationPage
    func loadNotificationFilterMetadata(
        for localWorkerID: String
    ) async throws -> [NotificationStructuralFilterMetadata]
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
        guard let data = dataByWorkerID[localWorkerID] else { return .empty }
        return SAPCachedData(notifications: [], workerProfile: data.workerProfile, metadata: data.metadata)
    }

    func loadNotifications(
        for localWorkerID: String,
        matching searchText: String,
        structuralFilter: NotificationStructuralFilter,
        limit: Int,
        offset: Int
    ) async throws -> SAPNotificationPage {
        let allNotifications = dataByWorkerID[localWorkerID]?.notifications ?? []
        let normalizedSearchText = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        let matchingNotifications = (normalizedSearchText.isEmpty ? allNotifications : allNotifications.filter {
            $0.id.localizedCaseInsensitiveContains(normalizedSearchText) ||
            $0.title.localizedCaseInsensitiveContains(normalizedSearchText) ||
            $0.functionalLocationID.localizedCaseInsensitiveContains(normalizedSearchText) ||
            $0.functionalLocationName.localizedCaseInsensitiveContains(normalizedSearchText)
        })
        .filter { structuralFilter.matches($0.structuralFilterMetadata) }
        .sorted { ($0.startDate, $0.id) < ($1.startDate, $1.id) }
        let boundedOffset = min(max(offset, 0), matchingNotifications.count)
        let endIndex = min(boundedOffset + max(limit, 1), matchingNotifications.count)
        let notifications = Array(matchingNotifications[boundedOffset..<endIndex])
        return SAPNotificationPage(
            notifications: notifications,
            nextOffset: endIndex < matchingNotifications.count ? endIndex : nil,
            totalCount: matchingNotifications.count
        )
    }

    func loadNotificationFilterMetadata(
        for localWorkerID: String
    ) async throws -> [NotificationStructuralFilterMetadata] {
        dataByWorkerID[localWorkerID]?.notifications.compactMap(\.structuralFilterMetadata) ?? []
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
        return SAPCachedData(notifications: [], workerProfile: data.workerProfile, metadata: data.metadata)
    }
}

struct UnavailableSAPDataCacheRepository: SAPDataCacheRepository {
    func load(for localWorkerID: String) async throws -> SAPCachedData {
        throw SAPReadError.serviceUnavailable
    }

    func loadNotifications(
        for localWorkerID: String,
        matching searchText: String,
        structuralFilter: NotificationStructuralFilter,
        limit: Int,
        offset: Int
    ) async throws -> SAPNotificationPage {
        throw SAPReadError.serviceUnavailable
    }

    func loadNotificationFilterMetadata(
        for localWorkerID: String
    ) async throws -> [NotificationStructuralFilterMetadata] {
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
