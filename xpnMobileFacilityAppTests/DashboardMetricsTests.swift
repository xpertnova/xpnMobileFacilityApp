import Foundation
import XCTest
@testable import mobileFacilityApp

/// The dashboard counters must never show an unread source as `0`, and in
/// production they start from the counters saved at the previous launch.
final class DashboardMetricsTests: XCTestCase {
    private var workerIDs: [String] = []

    override func tearDown() {
        workerIDs.forEach(DashboardMetricsSnapshot.reset(workerID:))
        workerIDs = []
        super.tearDown()
    }

    /// Snapshots live in `UserDefaults.standard`; a fresh worker per test keeps
    /// them apart from real data and from each other.
    private func uniqueWorkerID() -> String {
        let workerID = "TEST-\(UUID().uuidString)"
        workerIDs.append(workerID)
        return workerID
    }

    @MainActor
    private func makeViewModel(isDemoMode: Bool, workerID: String) -> FacilityDemoViewModel {
        FacilityDemoViewModel(
            isDemoMode: isDemoMode,
            offlineWorkStore: OfflineWorkStore(
                repository: InMemoryOfflineWorkRepository(),
                workerID: workerID
            ),
            sapDataStore: SAPDataStore(
                repository: InMemorySAPDataCacheRepository(
                    seed: TechnicalObjectDemoData.cachedData,
                    workerID: workerID
                ),
                refreshService: nil,
                localWorkerID: workerID
            ),
            meterReferenceProvider: DemoMeterReferenceProvider(),
            photoAttachmentStore: InMemoryPhotoAttachmentStore()
        )
    }

    func testFilledTakesKnownCountersAndFallsBackForTheRest() {
        let fresh = DashboardMetrics(notifications: 405, defects: nil, drafts: 5, technicalPlaces: nil)
        let saved = DashboardMetrics(notifications: 400, defects: 3, drafts: 4, technicalPlaces: 624)

        XCTAssertEqual(
            fresh.filled(from: saved),
            DashboardMetrics(notifications: 405, defects: 3, drafts: 5, technicalPlaces: 624)
        )
    }

    func testSnapshotIsKeptPerWorker() {
        let first = uniqueWorkerID()
        let second = uniqueWorkerID()
        let metrics = DashboardMetrics(notifications: 1, defects: 2, drafts: 3, technicalPlaces: 4)

        DashboardMetricsSnapshot.save(metrics, workerID: first)

        XCTAssertEqual(DashboardMetricsSnapshot.load(workerID: first), metrics)
        XCTAssertEqual(DashboardMetricsSnapshot.load(workerID: second), .unknown)
    }

    @MainActor
    func testCountersStayUnknownUntilTheirSourceIsRead() async {
        let viewModel = makeViewModel(isDemoMode: false, workerID: uniqueWorkerID())
        XCTAssertEqual(
            viewModel.freshDashboardMetrics,
            .unknown,
            "nothing has been read yet, so nothing may show as zero"
        )

        await viewModel.offlineWorkStore.load()
        XCTAssertEqual(viewModel.freshDashboardMetrics.defects, 0)
        XCTAssertEqual(viewModel.freshDashboardMetrics.drafts, 0)
        XCTAssertNil(viewModel.freshDashboardMetrics.notifications)
        XCTAssertNil(viewModel.freshDashboardMetrics.technicalPlaces)

        await viewModel.sapDataStore.loadCachedData()
        XCTAssertNotNil(viewModel.freshDashboardMetrics.notifications)

        await viewModel.technicalPlacesStore.load()
        XCTAssertNotNil(viewModel.freshDashboardMetrics.technicalPlaces)
    }

    @MainActor
    func testProductionShowsSavedCountersUntilFreshOnesArrive() async {
        let workerID = uniqueWorkerID()
        let saved = DashboardMetrics(notifications: 405, defects: 3, drafts: 5, technicalPlaces: 624)
        DashboardMetricsSnapshot.save(saved, workerID: workerID)

        let viewModel = makeViewModel(isDemoMode: false, workerID: workerID)
        XCTAssertEqual(viewModel.dashboardMetrics, saved, "the first frame shows the previous launch's counters")

        await viewModel.offlineWorkStore.load()
        XCTAssertEqual(viewModel.dashboardMetrics.defects, 0, "a fresh counter replaces the saved one")
        XCTAssertEqual(viewModel.dashboardMetrics.notifications, 405, "the cache has not been read yet")

        viewModel.rememberDashboardMetrics()
        let stored = DashboardMetricsSnapshot.load(workerID: workerID)
        XCTAssertEqual(stored.defects, 0)
        XCTAssertEqual(stored.notifications, 405, "an unread counter keeps its saved value")
    }

    /// Demo data is in memory; it must neither show nor overwrite what a
    /// production worker saw.
    @MainActor
    func testDemoModeNeitherReadsNorWritesTheSnapshot() async {
        let workerID = uniqueWorkerID()
        DashboardMetricsSnapshot.save(.init(notifications: 999, defects: 42), workerID: workerID)

        let viewModel = makeViewModel(isDemoMode: true, workerID: workerID)
        XCTAssertEqual(viewModel.dashboardMetrics.notifications, MockFacilityData.notifications.count)
        XCTAssertNil(viewModel.dashboardMetrics.defects)

        await viewModel.offlineWorkStore.load()
        viewModel.rememberDashboardMetrics()

        XCTAssertEqual(
            DashboardMetricsSnapshot.load(workerID: workerID),
            DashboardMetrics(notifications: 999, defects: 42)
        )
    }
}
