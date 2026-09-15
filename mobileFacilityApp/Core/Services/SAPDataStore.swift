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
    private(set) var isLoadingMoreNotifications = false
    private(set) var notificationFilterMetadata: [NotificationStructuralFilterMetadata] = []
    private var nextNotificationOffset: Int?
    private var notificationSearchText = ""
    private var notificationStructuralFilter = NotificationStructuralFilter.empty
    private var notificationLoadID = UUID()
    /// Refresh calls share one set of legacy temporary SQLite tables. Keep an
    /// explicit operation lease rather than deriving exclusivity from the
    /// presentation state alone: a saved-token task can otherwise see
    /// `.refreshing` and start a second transfer.
    private var activeRefreshID: UUID?
    private var preparedTokenRefreshID: UUID?

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

    func technicalObjectCount() async throws -> Int {
        let locations = try await repository.technicalObjectCount(for: localWorkerID, kind: .functionalLocation)
        let equipment = try await repository.technicalObjectCount(for: localWorkerID, kind: .equipment)
        return locations + equipment
    }

    func loadMobileLadderCreationData(for workerID: String) async throws -> MobileLadderCreationData {
        guard !workerID.isEmpty,
              let provider = repository as? any MobileLadderCreationProviding else {
            throw SAPReadError.serviceUnavailable
        }
        return try await provider.loadMobileLadderCreationData(for: workerID)
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
        state = .loadingCache
        do {
            cachedData = try await repository.load(for: localWorkerID)
            guard cachedData.metadata != nil else {
                resetNotificationPage()
                state = .noData
                return
            }
            try await loadTotalNotificationCount()
            try await loadNotificationFilterMetadata()
            try await loadFirstNotificationPage()
            state = .ready
        } catch is CancellationError {
            return
        } catch {
            refreshError = .serviceUnavailable
            state = .failed
        }
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
            cachedData = try await refreshService.refresh(sapPassword: sapPassword) { [weak self] stage in
                self?.refreshStage = stage
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
            cachedData = try await refreshService.refresh(usingToken: token) { [weak self] stage in
                self?.refreshStage = stage
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

    private func beginRefreshOperation() -> UUID? {
        guard activeRefreshID == nil else { return nil }
        let refreshID = UUID()
        activeRefreshID = refreshID
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
        let page = try await repository.loadNotifications(
            for: localWorkerID,
            matching: notificationSearchText,
            structuralFilter: notificationStructuralFilter,
            limit: notificationPageSize,
            offset: 0
        )
        guard notificationLoadID == loadID else { return }
        notifications = page.notifications
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
    }

    private func loadNotificationFilterMetadata() async throws {
        notificationFilterMetadata = try await repository.loadNotificationFilterMetadata(
            for: localWorkerID
        )
    }

    private func resetNotificationPage() {
        notificationLoadID = UUID()
        notifications = []
        matchingNotificationCount = 0
        totalNotificationCount = 0
        notificationFilterMetadata = []
        nextNotificationOffset = nil
    }
}
