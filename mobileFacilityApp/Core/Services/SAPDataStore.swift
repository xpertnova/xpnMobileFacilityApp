import Foundation
import Observation

@MainActor
@Observable
final class SAPDataStore {
    enum State: Equatable {
        case loadingCache
        case noData
        case ready
        case refreshing
        case failed
    }

    private let repository: any SAPDataCacheRepository
    private let refreshService: (any SAPNotificationRefreshService)?
    let localWorkerID: String
    private(set) var state: State = .loadingCache
    private(set) var cachedData: SAPCachedData = .empty
    private(set) var refreshError: SAPReadError?
    private(set) var refreshStage: SAPReadRefreshStage?

    init(
        repository: any SAPDataCacheRepository,
        refreshService: (any SAPNotificationRefreshService)?,
        localWorkerID: String
    ) {
        self.repository = repository
        self.refreshService = refreshService
        self.localWorkerID = localWorkerID
    }

    var notifications: [SAPNotificationSummary] { cachedData.notifications }
    var workerProfile: SAPWorkerProfile? { cachedData.workerProfile }
    var lastSuccessfulRefreshAt: Date? { cachedData.metadata?.lastSuccessfulRefreshAt }
    var isRefreshAvailable: Bool { refreshService != nil }
    var isRefreshing: Bool { state == .refreshing }
    var hasCache: Bool { cachedData.metadata != nil }

    func loadCachedData() async {
        state = .loadingCache
        do {
            cachedData = try await repository.load(for: localWorkerID)
            state = cachedData.metadata == nil ? .noData : .ready
        } catch is CancellationError {
            return
        } catch {
            refreshError = .serviceUnavailable
            state = .failed
        }
    }

    func refresh(sapPassword: String) async {
        guard state != .refreshing else { return }
        guard let refreshService else {
            refreshError = .authenticatedConnectionUnavailable
            state = cachedData.metadata == nil ? .failed : .ready
            return
        }
        state = .refreshing
        refreshError = nil
        refreshStage = .authenticating
        do {
            let snapshot = try await refreshService.refresh(sapPassword: sapPassword) { [weak self] stage in
                self?.refreshStage = stage
            }
            refreshStage = .savingSnapshot
            cachedData = try await repository.replace(
                with: snapshot,
                for: localWorkerID,
                refreshedAt: Date()
            )
            refreshStage = nil
            state = .ready
        } catch is CancellationError {
            refreshStage = nil
            state = cachedData.metadata == nil ? .noData : .ready
        } catch let error as SAPReadError {
            refreshStage = nil
            refreshError = error
            state = cachedData.metadata == nil ? .failed : .ready
        } catch {
            refreshStage = nil
            refreshError = .serviceUnavailable
            state = cachedData.metadata == nil ? .failed : .ready
        }
    }

    func dismissError() {
        refreshError = nil
        if state == .failed {
            state = cachedData.metadata == nil ? .noData : .ready
        }
    }
}
