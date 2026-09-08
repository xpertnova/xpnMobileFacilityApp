import XCTest
@testable import mobileFacilityApp

final class SidebarPresentationTests: XCTestCase {
    @MainActor
    func testSidebarStartsExpanded() {
        let viewModel = FacilityDemoViewModel(
            isDemoMode: true,
            offlineWorkStore: OfflineWorkStore(
                repository: InMemoryOfflineWorkRepository(),
                workerID: "demo"
            ),
            sapDataStore: SAPDataStore(
                repository: InMemorySAPDataCacheRepository(seed: TechnicalObjectDemoData.cachedData),
                refreshService: nil,
                localWorkerID: "demo"
            ),
            meterReferenceProvider: DemoMeterReferenceProvider(),
            photoAttachmentStore: InMemoryPhotoAttachmentStore()
        )

        XCTAssertTrue(viewModel.isSidebarExpanded)
    }

    func testCompactBadgeDisplaysZero() {
        XCTAssertEqual(CompactSidebarBadgeFormatter.text(for: 0), "0")
    }

    func testCompactBadgeDisplaysTwoDigits() {
        XCTAssertEqual(CompactSidebarBadgeFormatter.text(for: 42), "42")
    }

    func testCompactBadgeCapsAtNinetyNinePlus() {
        XCTAssertEqual(CompactSidebarBadgeFormatter.text(for: 100), "99+")
    }
}
