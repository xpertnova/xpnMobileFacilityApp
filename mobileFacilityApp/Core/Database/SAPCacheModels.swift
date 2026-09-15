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
    let equipmentID: String
    let startDate: String
    let endDate: String
    let systemStatus: String
    let userStatus: String
    let rawPayloadJSON: String

    init(
        id: String,
        client: String,
        title: String,
        functionalLocationID: String,
        functionalLocationName: String,
        equipmentID: String = "",
        startDate: String,
        endDate: String,
        systemStatus: String,
        userStatus: String,
        rawPayloadJSON: String
    ) {
        self.id = id
        self.client = client
        self.title = title
        self.functionalLocationID = functionalLocationID
        self.functionalLocationName = functionalLocationName
        self.equipmentID = equipmentID
        self.startDate = startDate
        self.endDate = endDate
        self.systemStatus = systemStatus
        self.userStatus = userStatus
        self.rawPayloadJSON = rawPayloadJSON
    }

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

/// Partner-company master data supplied by SAP table `T_0298` during the same
/// worker-scoped refresh as notifications. The values remain SAP data rather
/// than localized app copy, because a briefing must reproduce the source row.
struct SAPBriefingPartner: Codable, Equatable, Identifiable, Sendable {
    let id: String
    let client: String
    let function: String
    let name: String
    let contactName: String
    let searchTerm1: String
    let searchTerm2: String
    let street: String
    let houseNumber: String
    let postalCode: String
    let city: String
    let country: String
    let email: String

    var address: String {
        let streetLine = [street, houseNumber]
            .filter { !$0.isEmpty }
            .joined(separator: " ")
        let cityLine = [postalCode, city]
            .filter { !$0.isEmpty }
            .joined(separator: " ")
        return [streetLine, cityLine, country]
            .filter { !$0.isEmpty }
            .joined(separator: "\n")
    }

    var selectionLabel: String {
        [name, contactName, id]
            .filter { !$0.isEmpty }
            .joined(separator: " · ")
    }
}

/// The SAP row type found in `T_0267.FELDWERT.T_PLPOD`. It determines how a
/// briefing row is numbered, not how its SAP-provided text is displayed.
enum SAPBriefingTemplateRowType: String, Codable, Equatable, Sendable {
    case header = "HEADER"
    case position = "POSITION"
    case subposition = "UNTERPOSITION"

    init(sapValue: String) {
        self = Self(rawValue: sapValue.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()) ?? .position
    }
}

struct SAPBriefingAnswerOption: Codable, Equatable, Identifiable, Sendable {
    let key: String
    let title: String

    var id: String { key }
}

struct SAPBriefingTemplateItem: Codable, Equatable, Identifiable, Sendable {
    let id: String
    let orderIdentifier: String
    let rowType: SAPBriefingTemplateRowType
    /// A dynamic SAP row title. Do not localize or rewrite it in the UI.
    let title: String
    let answerOptions: [SAPBriefingAnswerOption]
    let documentSymbolID: String?
    let warningSymbolID: String?
}

struct SAPBriefingTemplateSection: Codable, Equatable, Identifiable, Sendable {
    let id: String
    /// A dynamic SAP section title. Do not localize or rewrite it in the UI.
    let title: String
    var subtitle: String? = nil
    let isOptional: Bool
    let items: [SAPBriefingTemplateItem]
}

/// The complete briefing plan decoded from a `T_0267` row and retained in the
/// local SAP cache. `EQART` and `PLNNR` identify the standard briefing plan
/// (`TFMINSTRUC` / `TFMB_001`) used by the legacy app.
struct SAPBriefingTemplate: Codable, Equatable, Identifiable, Sendable {
    let id: String
    let equipmentType: String
    let plannerGroup: String
    let planType: String
    let planNumber: String
    let sections: [SAPBriefingTemplateSection]

    var isStandardBriefing: Bool {
        equipmentType.caseInsensitiveCompare("TFMINSTRUC") == .orderedSame
            && planNumber.caseInsensitiveCompare("TFMB_001") == .orderedSame
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
    let briefingPartners: [SAPBriefingPartner]
    let briefingTemplates: [SAPBriefingTemplate]
    let technicalObjects: [TechnicalObjectNode]

    init(
        sapWorkerID: String,
        notifications: [SAPNotificationSummary],
        workerProfile: SAPWorkerProfile?,
        briefingPartners: [SAPBriefingPartner] = [],
        briefingTemplates: [SAPBriefingTemplate] = [],
        technicalObjects: [TechnicalObjectNode] = []
    ) {
        self.sapWorkerID = sapWorkerID
        self.notifications = notifications
        self.workerProfile = workerProfile
        self.briefingPartners = briefingPartners
        self.briefingTemplates = briefingTemplates
        self.technicalObjects = technicalObjects
    }
}

struct SAPCachedData: Equatable, Sendable {
    let notifications: [SAPNotificationSummary]
    let workerProfile: SAPWorkerProfile?
    let briefingPartners: [SAPBriefingPartner]
    let briefingTemplates: [SAPBriefingTemplate]
    let technicalObjects: [TechnicalObjectNode]
    let metadata: SAPCacheMetadata?

    static let empty = SAPCachedData(
        notifications: [],
        workerProfile: nil,
        briefingPartners: [],
        briefingTemplates: [],
        technicalObjects: [],
        metadata: nil
    )

    init(
        notifications: [SAPNotificationSummary],
        workerProfile: SAPWorkerProfile?,
        briefingPartners: [SAPBriefingPartner] = [],
        briefingTemplates: [SAPBriefingTemplate] = [],
        technicalObjects: [TechnicalObjectNode] = [],
        metadata: SAPCacheMetadata?
    ) {
        self.notifications = notifications
        self.workerProfile = workerProfile
        self.briefingPartners = briefingPartners
        self.briefingTemplates = briefingTemplates
        self.technicalObjects = technicalObjects
        self.metadata = metadata
    }
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
        let resultElementID: String
        let commentElementID: String
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
            let control = Self.stringValue(named: "STEUS", in: row)
            guard !operation.isEmpty, !control.isEmpty else { return nil }
            let properties = Self.value(named: "T_PROPS", in: row) as? [[String: Any]] ?? []
            let resultPosition = properties.compactMap { property -> Int? in
                let position: Int?
                switch Self.value(named: "POSNR", in: property) {
                case let number as NSNumber where number.intValue > 0:
                    position = number.intValue
                case let string as String:
                    position = Int(string).flatMap { $0 > 0 ? $0 : nil }
                default:
                    position = nil
                }
                guard let position else { return nil }
                let defaultValues = Self.stringValue(named: "DFVAL", in: property)
                guard normalizedRowType == "MEASURE"
                        || (!defaultValues.isEmpty && !defaultValues.contains("ICON_"))
                else { return nil }
                return position
            }
            .sorted()
            .first
            guard let resultPosition else { return nil }
            let cadence = Self.stringValue(named: "KTEX1", in: row)
            let postfix = control == "TFM3"
                ? "-" + cadence.filter { !$0.isNumber }
                : ""
            let resultElementID = "\(control)-\(operation)-\(resultPosition)\(postfix)"
            let commentElementID = "\(control)-\(operation)-9B"
            return InspectionItem(
                id: resultElementID.isEmpty ? "position-\(index)" : resultElementID,
                title: title,
                information: Self.stringValue(named: "LTXA2", in: row),
                resultElementID: resultElementID,
                commentElementID: commentElementID
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
            InspectionItem(
                id: $0.id,
                title: $0.title,
                information: $0.information,
                resultElementID: $0.resultElementID ?? "",
                commentElementID: $0.commentElementID ?? ""
            )
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
            InspectionItem(
                id: $0.id,
                title: $0.title,
                information: $0.information,
                resultElementID: $0.resultElementID,
                commentElementID: $0.commentElementID
            )
        }
    }
}

protocol SAPDataCacheRepository: TechnicalObjectRepository {
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
    func loadUserProfile(for workerID: String) async throws -> SAPUserProfile?
}

typealias LegacySAPRow = [String: String?]

struct LegacySAPIncomingPackage: Sendable {
    let tables: [String: [LegacySAPRow]]
    let isLastPackage: Bool
}

/// A compact, privacy-safe description of the incoming snapshot after it has
/// been committed to the legacy cache. The application intentionally pages
/// notifications from SQLite instead of retaining every decoded notification
/// in `SAPCachedData`, so this summary is the authoritative sync diagnostic.
struct SAPIncomingCacheSummary: Equatable, Sendable {
    let notificationRowCount: Int
    let actionableNotificationCount: Int
    let businessEntityCount: Int
    let elevatorInspectionCount: Int
}

struct LegacySAPOutgoingPayload: Encodable, Sendable {
    let T_0281: [[String: String]]
    let T_0283: [[String: String]]
    let T_0152R: [[String: String]]
    let T_0154R: [[String: String]]
    let T_0211R: [[String: String]]
    let T_0212R: [[String: String]]
    let T_0265: [[String: String]]
    let T_0266: [[String: String]]
    let T_0282: [[String: String]]
    let T_0284: [[String: String]]
    let T_0285: [[String: String]]
    let T_0286: [[String: String]]
    let T_0300: [[String: String]]
    let T_0302: [[String: String]]
}

protocol SAPLegacySynchronizationStore: Sendable {
    func stageOutgoing(requestID: String) async throws -> LegacySAPOutgoingPayload
    func confirmOutgoing(requestID: String) async throws
    func abortOutgoing(requestID: String) async
    func beginIncoming() async throws
    func appendIncoming(_ package: LegacySAPIncomingPackage) async throws
    func commitIncoming(sapWorkerID: String, refreshedAt: Date) async throws -> SAPCachedData
    func incomingCacheSummary() async throws -> SAPIncomingCacheSummary
    func abortIncoming() async
}

protocol SAPNotificationOutgoingStore: Sendable {
    func replaceNotificationOutgoingRows(
        processIDs: [String],
        equipmentIDs: [String],
        headers: [LegacySAPRow],
        values: [LegacySAPRow],
        documents: [LegacySAPRow],
        equipment: [LegacySAPRow]
    ) async throws
}

enum SAPReadRefreshStage: Equatable, Sendable {
    case authenticating
    case uploadingOutgoingMetadata
    case uploadingOutgoingDocuments(current: Int, total: Int)
    case postingOutgoingData
    case waitingForOutgoingAcknowledgement
    case checkingAppVersion
    case preparingIncomingData
    case waitingForIncomingData
    case receivingIncomingPackages(packageNumber: Int = 1)
    case savingSnapshot
}

enum SAPRefreshAuthenticationMethod: Equatable, Sendable {
    /// The separate password entered in the synchronization dialog.
    case password
    /// The short-lived session token stored after a successful password check.
    case savedToken
}

/// Safe, user-visible context for a failed synchronization attempt.
///
/// This deliberately contains neither the password, token, worker ID, endpoint,
/// nor a backend payload. It lets the UI explain which synchronization step
/// failed without exposing credentials or tenant configuration.
struct SAPRefreshFailureContext: Sendable {
    let authenticationMethod: SAPRefreshAuthenticationMethod
    let stage: SAPReadRefreshStage
    let error: SAPReadError
}

typealias SAPReadRefreshProgressHandler = @MainActor @Sendable (SAPReadRefreshStage) -> Void

protocol SAPNotificationRefreshService: Sendable {
    func refresh(
        sapPassword: String,
        progress: @escaping SAPReadRefreshProgressHandler
    ) async throws -> SAPCachedData

    func refresh(
        usingToken token: String,
        progress: @escaping SAPReadRefreshProgressHandler
    ) async throws -> SAPCachedData
}

enum SAPReadError: LocalizedError, Sendable {
    case configurationUnavailable
    case authenticatedConnectionUnavailable
    case passwordRequired
    case invalidCredentials
    case initialPasswordChangeRequired
    case tokenInvalidOrExpired
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
        case .tokenInvalidOrExpired: "The SAP session token is invalid or has expired on another device."
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
        return SAPCachedData(
            notifications: [],
            workerProfile: data.workerProfile,
            briefingPartners: data.briefingPartners,
            briefingTemplates: data.briefingTemplates,
            technicalObjects: data.technicalObjects,
            metadata: data.metadata
        )
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

    func loadUserProfile(for workerID: String) async throws -> SAPUserProfile? {
        guard let profile = dataByWorkerID[workerID]?.workerProfile else { return nil }
        return SAPUserProfile(
            personalNumber: profile.personnelNumber,
            name: profile.lastName,
            firstName: profile.firstName,
            company: profile.organizationUnit,
            email: profile.email,
            canCreateI2: true
        )
    }

    func loadTechnicalObjectRoots(
        for localWorkerID: String,
        limit: Int,
        offset: Int
    ) async throws -> TechnicalObjectPage {
        let all = dataByWorkerID[localWorkerID]?.technicalObjects ?? []
        var roots = all.filter { $0.parent == nil && !$0.isUnassigned }
        let unassignedCount = all.filter(\.isUnassigned).count
        if unassignedCount > 0 {
            var root = TechnicalObjectNode.unassignedRoot
            root.directChildCount = unassignedCount
            roots.append(root)
        }
        return Self.page(roots, limit: limit, offset: offset)
    }

    func loadTechnicalObjectChildren(
        for localWorkerID: String,
        parent: TechnicalObjectReference,
        limit: Int,
        offset: Int
    ) async throws -> TechnicalObjectPage {
        let all = dataByWorkerID[localWorkerID]?.technicalObjects ?? []
        let children = parent == .unassigned
            ? all.filter(\.isUnassigned)
            : all.filter { $0.parent == parent }
        return Self.page(children, limit: limit, offset: offset)
    }

    func searchTechnicalObjects(
        for localWorkerID: String,
        query: String,
        dinGroup: String?
    ) async throws -> [TechnicalObjectNode] {
        let all = dataByWorkerID[localWorkerID]?.technicalObjects ?? []
        let normalizedQuery = query.trimmingCharacters(in: .whitespacesAndNewlines)
        let matches = all.filter { object in
            let matchesDIN = dinGroup == nil || object.dinGroup == dinGroup
            let searchable = [
                object.reference.objectID, object.name, object.cityName,
                object.countryCode, object.locationCode, object.manufacturer,
                object.modelType, object.serialNumber, object.dinGroup ?? ""
            ].joined(separator: " ")
            return matchesDIN && (normalizedQuery.isEmpty || searchable.localizedCaseInsensitiveContains(normalizedQuery))
        }
        var included = Set(matches.map(\.reference))
        let byReference = Dictionary(uniqueKeysWithValues: all.map { ($0.reference, $0) })
        for match in matches {
            var parent = match.parent
            while let reference = parent, let object = byReference[reference] {
                guard included.insert(reference).inserted else { break }
                parent = object.parent
            }
        }
        return all.filter { included.contains($0.reference) }
    }

    func loadTechnicalObjectDINCounts(
        for localWorkerID: String
    ) async throws -> [TechnicalObjectDINCount] {
        let all = dataByWorkerID[localWorkerID]?.technicalObjects ?? []
        let counts = Dictionary(grouping: all.compactMap(\.dinGroup), by: { $0 })
        return TechnicalDIN276.supportedCodes.compactMap { code in
            guard let values = counts[code] else { return nil }
            return TechnicalObjectDINCount(code: code, count: values.count)
        }
    }

    func loadTechnicalObjectDetail(
        for localWorkerID: String,
        reference: TechnicalObjectReference
    ) async throws -> TechnicalObjectDetail? {
        let data = dataByWorkerID[localWorkerID] ?? .empty
        guard let object = data.technicalObjects.first(where: { $0.reference == reference }) else { return nil }
        let byReference = Dictionary(uniqueKeysWithValues: data.technicalObjects.map { ($0.reference, $0) })
        var breadcrumbs: [TechnicalObjectNode] = []
        var parent = object.parent
        var visited = Set<TechnicalObjectReference>()
        while let reference = parent, visited.insert(reference).inserted, let value = byReference[reference] {
            breadcrumbs.insert(value, at: 0)
            parent = value.parent
        }
        let notifications = data.notifications.filter {
            reference.kind == .equipment
                ? $0.equipmentID == reference.objectID
                : $0.functionalLocationID == reference.objectID
        }
        if reference.kind == .functionalLocation {
            return .functionalLocation(FunctionalLocationDetail(
                object: object,
                breadcrumbs: breadcrumbs,
                children: data.technicalObjects.filter { $0.parent == reference },
                linkedNotifications: notifications
            ))
        }
        return .equipment(EquipmentDetail(
            object: object,
            breadcrumbs: breadcrumbs,
            linkedNotifications: notifications
        ))
    }

    func technicalObjectCount(
        for localWorkerID: String,
        kind: TechnicalObjectKind
    ) async throws -> Int {
        dataByWorkerID[localWorkerID]?.technicalObjects.filter { $0.reference.kind == kind }.count ?? 0
    }

    func replace(
        with snapshot: SAPReadSnapshot,
        for localWorkerID: String,
        refreshedAt: Date
    ) async throws -> SAPCachedData {
        let data = SAPCachedData(
            notifications: snapshot.notifications,
            workerProfile: snapshot.workerProfile,
            briefingPartners: snapshot.briefingPartners,
            briefingTemplates: snapshot.briefingTemplates,
            technicalObjects: TechnicalObjectHierarchyNormalizer.normalize(snapshot.technicalObjects),
            metadata: SAPCacheMetadata(
                sapWorkerID: snapshot.sapWorkerID,
                lastSuccessfulRefreshAt: refreshedAt
            )
        )
        dataByWorkerID[localWorkerID] = data
        return SAPCachedData(
            notifications: [],
            workerProfile: data.workerProfile,
            briefingPartners: data.briefingPartners,
            briefingTemplates: data.briefingTemplates,
            technicalObjects: data.technicalObjects,
            metadata: data.metadata
        )
    }

    private static func page(
        _ source: [TechnicalObjectNode],
        limit: Int,
        offset: Int
    ) -> TechnicalObjectPage {
        let sorted = source.sorted {
            if $0.reference.kind != $1.reference.kind {
                return $0.reference.kind == .functionalLocation
            }
            return $0.displayName.localizedStandardCompare($1.displayName) == .orderedAscending
        }
        let boundedOffset = min(max(offset, 0), sorted.count)
        let end = min(boundedOffset + max(limit, 1), sorted.count)
        return TechnicalObjectPage(
            objects: Array(sorted[boundedOffset..<end]),
            nextOffset: end < sorted.count ? end : nil,
            totalCount: sorted.count
        )
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

    func loadUserProfile(for workerID: String) async throws -> SAPUserProfile? {
        throw SAPReadError.serviceUnavailable
    }

    func loadTechnicalObjectRoots(for localWorkerID: String, limit: Int, offset: Int) async throws -> TechnicalObjectPage {
        throw SAPReadError.serviceUnavailable
    }

    func loadTechnicalObjectChildren(for localWorkerID: String, parent: TechnicalObjectReference, limit: Int, offset: Int) async throws -> TechnicalObjectPage {
        throw SAPReadError.serviceUnavailable
    }

    func searchTechnicalObjects(for localWorkerID: String, query: String, dinGroup: String?) async throws -> [TechnicalObjectNode] {
        throw SAPReadError.serviceUnavailable
    }

    func loadTechnicalObjectDINCounts(for localWorkerID: String) async throws -> [TechnicalObjectDINCount] {
        throw SAPReadError.serviceUnavailable
    }

    func loadTechnicalObjectDetail(for localWorkerID: String, reference: TechnicalObjectReference) async throws -> TechnicalObjectDetail? {
        throw SAPReadError.serviceUnavailable
    }

    func technicalObjectCount(for localWorkerID: String, kind: TechnicalObjectKind) async throws -> Int {
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
