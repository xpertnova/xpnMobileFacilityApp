import Foundation
import Observation

@MainActor
@Observable
final class SAPDataStore: MobileLadderCreationProviding, ElevatorAssetDataProviding, SubdistributionCreationProviding {
    enum State: Equatable {
        case loadingCache
        case noData
        case ready
        case refreshing
        case failed
    }

    private let repository: any SAPDataCacheRepository
    private let refreshService: (any SAPNotificationRefreshService)?
    private let tokenStore: (any SAPSyncTokenStore)?
    private let notificationPageSize = 40
    let localWorkerID: String
    let synchronizationUserID: String
    private let tokenStoreAccountID: String
    private(set) var state: State = .loadingCache
    private(set) var cachedData: SAPCachedData = .empty
    private(set) var refreshError: SAPReadError?
    private(set) var refreshStage: SAPReadRefreshStage?
    private(set) var refreshFailureContext: SAPRefreshFailureContext?
    private(set) var notifications: [SAPNotificationSummary] = []
    private(set) var matchingNotificationCount = 0
    private(set) var totalNotificationCount = 0
    /// `totalNotificationCount` is only meaningful once this is true; before
    /// that its `0` means "not counted yet", not "no notifications".
    private(set) var hasLoadedNotificationCount = false
    private(set) var isLoadingMoreNotifications = false
    /// True while the first page is rebuilt after the structural filter, the
    /// search text or the cache itself changed. The list keeps its previous
    /// rows meanwhile, so this is what the busy frame over the list binds to.
    private(set) var isReloadingNotifications = false
    private(set) var notificationFilterMetadata: [NotificationStructuralFilterMetadata] = []
    private(set) var notificationFilterOptions = NotificationStructuralFilterOptions.empty
    private(set) var functionalLocationDirectory = FunctionalLocationDirectory.empty
    private(set) var notificationPageRevision = 0
    private var nextNotificationOffset: Int?
    private var notificationSearchText = ""
    private var notificationStructuralFilter = NotificationStructuralFilter.empty
    private var notificationLoadID = UUID()
    private var cacheLoadIsInFlight = false
    private var initialCacheLoadCompleted = false
    /// Refresh calls share one set of legacy temporary SQLite tables. Keep an
    /// explicit operation lease rather than deriving exclusivity from the
    /// presentation state alone: a saved-token task can otherwise see
    /// `.refreshing` and start a second transfer.
    private var activeRefreshID: UUID?
    private var preparedTokenRefreshID: UUID?
    @ObservationIgnored private var runningRefresh: Task<SAPCachedData, Error>?
    /// Set when the technician cancels before the SAP task has started.
    @ObservationIgnored private var isCancellationRequested = false

    init(
        repository: any SAPDataCacheRepository,
        refreshService: (any SAPNotificationRefreshService)?,
        tokenStore: (any SAPSyncTokenStore)? = nil,
        localWorkerID: String,
        synchronizationUserID: String? = nil,
        tokenStoreAccountID: String? = nil
    ) {
        self.repository = repository
        self.refreshService = refreshService
        self.tokenStore = tokenStore
        self.localWorkerID = localWorkerID
        self.synchronizationUserID = synchronizationUserID ?? localWorkerID
        self.tokenStoreAccountID = tokenStoreAccountID ?? self.synchronizationUserID
    }

    var hasValidSavedToken: Bool {
        guard let tokenStore else { return false }
        let token = tokenStore.token(for: tokenStoreAccountID)
        return token != nil && !(token?.isEmpty ?? true)
    }

    var workerProfile: SAPWorkerProfile? { cachedData.workerProfile }
    func loadUserProfile() async -> SAPUserProfile? {
        try? await repository.loadUserProfile(for: localWorkerID)
    }
    var lastSuccessfulRefreshAt: Date? { cachedData.metadata?.lastSuccessfulRefreshAt }
    var isRefreshAvailable: Bool { refreshService != nil }
    var isRefreshing: Bool { state == .refreshing }
    var hasCache: Bool { cachedData.metadata != nil }
    var hasMoreNotifications: Bool { nextNotificationOffset != nil }

    /// Looks up one notification directly in the persisted cache without
    /// replacing the list currently shown in the notifications screen.
    func cachedNotification(id: String) async -> SAPNotificationSummary? {
        do {
            let page = try await repository.loadNotifications(
                for: localWorkerID,
                matching: id,
                structuralFilter: .empty,
                limit: 1,
                offset: 0
            )
            return page.notifications.first { $0.id == id }
        } catch {
            return nil
        }
    }

    func technicalObjectRoots(limit: Int, offset: Int) async throws -> TechnicalObjectPage {
        try await repository.loadTechnicalObjectRoots(for: localWorkerID, limit: limit, offset: offset)
    }

    func technicalObjectChildren(of parent: TechnicalObjectReference, limit: Int, offset: Int) async throws -> TechnicalObjectPage {
        try await repository.loadTechnicalObjectChildren(for: localWorkerID, parent: parent, limit: limit, offset: offset)
    }

    func searchTechnicalObjects(_ query: String, dinGroup: String?, limit: Int) async throws -> [TechnicalObjectNode] {
        Array(try await repository.searchTechnicalObjects(for: localWorkerID, query: query, dinGroup: dinGroup).prefix(limit))
    }

    func technicalObjectDINCounts() async throws -> [TechnicalObjectDINCount] {
        try await repository.loadTechnicalObjectDINCounts(for: localWorkerID)
    }

    func technicalObjectDetail(_ reference: TechnicalObjectReference) async throws -> TechnicalObjectDetail? {
        try await repository.loadTechnicalObjectDetail(for: localWorkerID, reference: reference)
    }

    func technicalObjectCounts() async throws -> TechnicalObjectCounts {
        TechnicalObjectCounts(
            functionalLocations: try await repository.technicalObjectCount(for: localWorkerID, kind: .functionalLocation),
            equipment: try await repository.technicalObjectCount(for: localWorkerID, kind: .equipment)
        )
    }

    func technicalObjectCount() async throws -> Int {
        try await technicalObjectCounts().total
    }

    func resolveQRCode(_ payload: LegacyQRCodePayload) async throws -> [SAPNotificationSummary] {
        guard hasCache else { throw QRCodeResolutionError.synchronizationRequired }
        return try await repository.resolveQRCode(payload, for: localWorkerID)
    }

    func loadMobileLadderCreationData(for workerID: String) async throws -> MobileLadderCreationData {
        guard !workerID.isEmpty,
              let provider = repository as? any MobileLadderCreationProviding else {
            throw SAPReadError.serviceUnavailable
        }
        return try await provider.loadMobileLadderCreationData(for: workerID)
    }

    /// The downloaded I2 notifications of the notification's technical
    /// object. Empty when the repository has none or cannot read them; the
    /// per-position lookup is informational and never blocks a form.
    /// The open I1s a defect can be reported under; empty when the cache
    /// holds none or cannot read them.
    func loadDefectParentNotifications() async -> [DefectParentNotification] {
        guard let provider = repository as? any DefectParentNotificationProviding else { return [] }
        return (try? await provider.loadDefectParentNotifications(for: localWorkerID)) ?? []
    }

    func loadI2Notifications(for detail: SAPNotificationDetail) async -> [SAPI2NotificationSummary] {
        guard let reader = repository as? any I2NotificationReading else { return [] }
        let notification = detail.summary
        let payload = notification.rawPayloadJSON.data(using: .utf8)
            .flatMap { try? JSONSerialization.jsonObject(with: $0) as? [String: Any] } ?? [:]
        // `select.getItemMeldung` filters by the I1's `TPLNR`; I2 rows carry
        // the parent `STRNO` there, which is also the fallback for a
        // notification reopened from its offline snapshot.
        let locationID = (payload["TPLNR"] as? String).flatMap { $0.isEmpty ? nil : $0 }
            ?? notification.functionalLocationID
        let object = I2NotificationObjectReference(
            client: notification.client,
            equipmentID: notification.equipmentID.isEmpty ? detail.equipmentID : notification.equipmentID,
            functionalLocationID: locationID
        )
        return (try? await reader.loadI2Notifications(for: object)) ?? []
    }

    /// The measuring points of the notification's technical place, as the
    /// legacy screen reads them for `T0281.STRNO`. `nil` when they cannot be
    /// read, which is different from a place that has none.
    func loadMeasuringPoints(for detail: SAPNotificationDetail) async -> [SAPMeasuringPoint]? {
        guard let provider = repository as? any MeasuringPointProviding else { return nil }
        let notification = detail.summary
        let payload = notification.rawPayloadJSON.data(using: .utf8)
            .flatMap { try? JSONSerialization.jsonObject(with: $0) as? [String: Any] } ?? [:]
        let locationID = (payload["STRNO"] as? String).flatMap { $0.isEmpty ? nil : $0 }
            ?? notification.functionalLocationID
        return try? await provider.loadMeasuringPoints(functionalLocationID: locationID)
    }

    /// Every measuring point the SAP package delivered, keyed by `STRNO`.
    func loadAllMeasuringPoints() async throws -> [String: [SAPMeasuringPoint]] {
        guard let provider = repository as? any MeasuringPointProviding else {
            throw SAPReadError.serviceUnavailable
        }
        return try await provider.loadAllMeasuringPoints()
    }

    func loadElevatorAssetData(for notification: SAPNotificationSummary) async throws -> ElevatorAssetData {
        guard let provider = repository as? any ElevatorAssetDataProviding else {
            throw SAPReadError.serviceUnavailable
        }
        return try await provider.loadElevatorAssetData(for: notification)
    }

    func loadSubdistributionCreationData(for workerID: String) async throws -> SubdistributionCreationData {
        guard !workerID.isEmpty,
              let provider = repository as? any SubdistributionCreationProviding else {
            throw SAPReadError.serviceUnavailable
        }
        return try await provider.loadSubdistributionCreationData(for: workerID)
    }

    func loadCachedData() async {
        guard !cacheLoadIsInFlight, !initialCacheLoadCompleted else { return }
        cacheLoadIsInFlight = true
        defer { cacheLoadIsInFlight = false }
        setCacheLoadState(.loadingCache)
        do {
            cachedData = try await repository.load(for: localWorkerID)
            guard cachedData.metadata != nil else {
                resetNotificationPage()
                // No cache yet: zero notifications is the actual answer.
                hasLoadedNotificationCount = true
                setCacheLoadState(.noData)
                initialCacheLoadCompleted = true
                return
            }
            try await loadTotalNotificationCount()
            try await loadNotificationFilterMetadata()
            try await loadFirstNotificationPage()
            setCacheLoadState(.ready)
            initialCacheLoadCompleted = true
        } catch is CancellationError {
            return
        } catch {
            guard activeRefreshID == nil else { return }
            refreshError = .serviceUnavailable
            state = .failed
        }
    }

    /// The cache is read at launch while a synchronization may already have
    /// started from the dialog. The synchronization owns `state` until it
    /// ends; letting the cache load overwrite `.refreshing` dropped the busy
    /// dialog back to the password form while SAP was still being called.
    private func setCacheLoadState(_ newState: State) {
        guard activeRefreshID == nil else { return }
        state = newState
    }

    func updateNotificationSearch(_ searchText: String) async {
        let normalizedSearchText = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard normalizedSearchText != notificationSearchText else { return }
        notificationSearchText = normalizedSearchText
        guard hasCache else { return }
        do {
            try await loadFirstNotificationPage()
        } catch is CancellationError {
            return
        } catch {
            refreshError = .serviceUnavailable
        }
    }

    func updateNotificationStructuralFilter(_ filter: NotificationStructuralFilter) async {
        guard filter != notificationStructuralFilter else { return }
        notificationStructuralFilter = filter
        guard hasCache else { return }
        do {
            try await loadFirstNotificationPage()
        } catch is CancellationError {
            return
        } catch {
            refreshError = .serviceUnavailable
        }
    }

    func loadMoreNotifications() async {
        guard !isLoadingMoreNotifications, let offset = nextNotificationOffset else { return }
        let loadID = notificationLoadID
        isLoadingMoreNotifications = true
        defer { isLoadingMoreNotifications = false }
        do {
            let page = try await repository.loadNotifications(
                for: localWorkerID,
                matching: notificationSearchText,
                structuralFilter: notificationStructuralFilter,
                limit: notificationPageSize,
                offset: offset
            )
            guard notificationLoadID == loadID else { return }
            notifications.append(contentsOf: page.notifications)
            notificationPageRevision &+= 1
            matchingNotificationCount = page.totalCount
            nextNotificationOffset = page.nextOffset
        } catch is CancellationError {
            return
        } catch {
            refreshError = .serviceUnavailable
        }
    }

    func refresh(sapPassword: String) async {
        guard let refreshService else {
            refreshFailureContext = nil
            refreshError = .authenticatedConnectionUnavailable
            state = cachedData.metadata == nil ? .failed : .ready
            return
        }
        guard let refreshID = beginRefreshOperation() else { return }
        defer { finishRefreshOperation(refreshID) }
        do {
            cachedData = try await runRefresh {
                try await refreshService.refresh(sapPassword: sapPassword) { [weak self] stage in
                    self?.refreshStage = stage
                }
            }
            try await loadTotalNotificationCount()
            try await loadNotificationFilterMetadata()
            try await loadFirstNotificationPage()
            refreshStage = nil
            state = .ready
        } catch is CancellationError {
            refreshStage = nil
            refreshFailureContext = nil
            state = cachedData.metadata == nil ? .noData : .ready
        } catch let error as SAPReadError {
            recordRefreshFailure(error, authenticationMethod: .password)
            refreshStage = nil
            refreshError = error
            state = cachedData.metadata == nil ? .failed : .ready
        } catch {
            recordRefreshFailure(.serviceUnavailable, authenticationMethod: .password)
            refreshStage = nil
            refreshError = .serviceUnavailable
            state = cachedData.metadata == nil ? .failed : .ready
        }
    }

    /// Synchronously prepares the store state for token refresh so that UI observers
    /// immediately see `isRefreshing == true` and `refreshStage == .authenticating`.
    @discardableResult
    func beginTokenRefresh() -> Bool {
        guard hasValidSavedToken, refreshService != nil,
              let refreshID = beginRefreshOperation()
        else {
            return false
        }
        preparedTokenRefreshID = refreshID
        return true
    }

    /// Attempts to synchronize using the saved SAP token.
    /// Returns `true` if synchronization succeeded.
    /// Returns `false` if no token exists, connection is unavailable, or token was rejected by SAP (calling code can prompt for password).
    @discardableResult
    func refreshWithSavedToken() async -> Bool {
        let refreshID: UUID
        if let preparedID = preparedTokenRefreshID {
            guard activeRefreshID == preparedID else { return false }
            preparedTokenRefreshID = nil
            refreshID = preparedID
        } else {
            guard activeRefreshID == nil else { return false }
            guard hasValidSavedToken else { return false }
            guard refreshService != nil else {
                refreshFailureContext = nil
                refreshError = .authenticatedConnectionUnavailable
                state = cachedData.metadata == nil ? .failed : .ready
                return false
            }
            guard let startedRefreshID = beginRefreshOperation() else { return false }
            refreshID = startedRefreshID
        }
        defer { finishRefreshOperation(refreshID) }
        guard let tokenStore, let token = tokenStore.token(for: tokenStoreAccountID), !token.isEmpty else {
            refreshStage = nil
            state = cachedData.metadata == nil ? .noData : .ready
            return false
        }
        guard let refreshService else {
            refreshStage = nil
            refreshFailureContext = nil
            refreshError = .authenticatedConnectionUnavailable
            state = cachedData.metadata == nil ? .failed : .ready
            return false
        }
        do {
            cachedData = try await runRefresh {
                try await refreshService.refresh(usingToken: token) { [weak self] stage in
                    self?.refreshStage = stage
                }
            }
            try await loadTotalNotificationCount()
            try await loadNotificationFilterMetadata()
            try await loadFirstNotificationPage()
            refreshStage = nil
            state = .ready
            return true
        } catch is CancellationError {
            refreshStage = nil
            refreshFailureContext = nil
            state = cachedData.metadata == nil ? .noData : .ready
            return false
        } catch let error as SAPReadError {
            if shouldDiscardSavedToken(for: error) {
                tokenStore.deleteToken(for: tokenStoreAccountID)
                refreshStage = nil
                refreshFailureContext = nil
                refreshError = nil
                state = cachedData.metadata == nil ? .noData : .ready
                return false
            } else {
                recordRefreshFailure(error, authenticationMethod: .savedToken)
                refreshStage = nil
                refreshError = error
                state = cachedData.metadata == nil ? .failed : .ready
                return false
            }
        } catch {
            recordRefreshFailure(.serviceUnavailable, authenticationMethod: .savedToken)
            refreshStage = nil
            refreshError = .serviceUnavailable
            state = cachedData.metadata == nil ? .failed : .ready
            return false
        }
    }

    /// Stops the running synchronization. A request SAP may already hold
    /// stays recorded, so the next synchronization settles it first and
    /// nothing is sent twice.
    func cancelRefresh() {
        guard isRefreshing else { return }
        isCancellationRequested = true
        runningRefresh?.cancel()
    }

    func deleteSavedToken() {
        tokenStore?.deleteToken(for: tokenStoreAccountID)
    }

    func dismissError() {
        refreshError = nil
        refreshFailureContext = nil
        if state == .failed {
            state = cachedData.metadata == nil ? .noData : .ready
        }
    }

    private func shouldDiscardSavedToken(for error: SAPReadError) -> Bool {
        switch error {
        case .tokenInvalidOrExpired, .httpStatus(401), .httpStatus(403):
            true
        default:
            false
        }
    }

    private func recordRefreshFailure(
        _ error: SAPReadError,
        authenticationMethod: SAPRefreshAuthenticationMethod
    ) {
        refreshFailureContext = SAPRefreshFailureContext(
            authenticationMethod: authenticationMethod,
            stage: refreshStage ?? .authenticating,
            error: error
        )
    }

    private func runRefresh(
        _ operation: @escaping @Sendable () async throws -> SAPCachedData
    ) async throws -> SAPCachedData {
        if isCancellationRequested { throw CancellationError() }
        let task = Task { try await operation() }
        runningRefresh = task
        defer { runningRefresh = nil }
        return try await task.value
    }

    private func beginRefreshOperation() -> UUID? {
        guard activeRefreshID == nil else { return nil }
        let refreshID = UUID()
        activeRefreshID = refreshID
        isCancellationRequested = false
        state = .refreshing
        refreshError = nil
        refreshStage = .authenticating
        refreshFailureContext = nil
        return refreshID
    }

    private func finishRefreshOperation(_ refreshID: UUID) {
        guard activeRefreshID == refreshID else { return }
        activeRefreshID = nil
        preparedTokenRefreshID = nil
    }

    private func loadFirstNotificationPage() async throws {
        let loadID = UUID()
        notificationLoadID = loadID
        isReloadingNotifications = true
        defer { isReloadingNotifications = false }
        let page = try await repository.loadNotifications(
            for: localWorkerID,
            matching: notificationSearchText,
            structuralFilter: notificationStructuralFilter,
            limit: notificationPageSize,
            offset: 0
        )
        guard notificationLoadID == loadID else { return }
        notifications = page.notifications
        notificationPageRevision &+= 1
        matchingNotificationCount = page.totalCount
        nextNotificationOffset = page.nextOffset
    }

    private func loadTotalNotificationCount() async throws {
        let page = try await repository.loadNotifications(
            for: localWorkerID,
            matching: "",
            structuralFilter: .empty,
            limit: 1,
            offset: 0
        )
        totalNotificationCount = page.totalCount
        hasLoadedNotificationCount = true
    }

    private func loadNotificationFilterMetadata() async throws {
        let metadata = try await repository.loadNotificationFilterMetadata(
            for: localWorkerID
        )
        let directory = try await repository.loadFunctionalLocationDirectory(for: localWorkerID)
        let options = await Task.detached(priority: .utility) {
            NotificationStructuralFilterOptions(metadata: metadata, directory: directory)
        }.value
        notificationFilterMetadata = metadata
        notificationFilterOptions = options
        functionalLocationDirectory = directory
    }

    private func resetNotificationPage() {
        notificationLoadID = UUID()
        notifications = []
        notificationPageRevision &+= 1
        matchingNotificationCount = 0
        totalNotificationCount = 0
        notificationFilterMetadata = []
        notificationFilterOptions = .empty
        functionalLocationDirectory = .empty
        nextNotificationOffset = nil
    }
}
