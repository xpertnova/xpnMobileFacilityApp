import Foundation
import XCTest
@testable import mobileFacilityApp

/// `FacilityDemoViewModel.visibleNotifications` is cached, because one SwiftUI
/// pass asks for it several times and rebuilding a few hundred rows each time
/// was what made opening the notifications tab feel stuck. These tests pin the
/// invalidation: a cache that outlives its inputs would silently freeze the
/// list.
final class NotificationRowCacheTests: XCTestCase {
    @MainActor
    private func makeViewModel(isDemoMode: Bool) -> FacilityDemoViewModel {
        FacilityDemoViewModel(
            isDemoMode: isDemoMode,
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
    }

    @MainActor
    func testRepeatedReadsReturnTheSameRows() {
        let viewModel = makeViewModel(isDemoMode: true)

        let first = viewModel.visibleNotifications
        let second = viewModel.visibleNotifications

        XCTAssertEqual(first, second)
        XCTAssertFalse(first.isEmpty)
    }

    @MainActor
    func testDemoRowsFollowDemoDataMutatedInPlace() throws {
        let viewModel = makeViewModel(isDemoMode: true)
        let target = try XCTUnwrap(viewModel.visibleNotifications.first { $0.status == .open })
        let index = try XCTUnwrap(viewModel.notifications.firstIndex { $0.id == target.id })

        viewModel.notifications[index].status = .attention

        let updated = try XCTUnwrap(viewModel.visibleNotifications.first { $0.id == target.id })
        XCTAssertEqual(updated.status, .attention, "a cached row must not survive the demo mutation")
    }

    @MainActor
    func testRowsFollowOfflineWorkChanges() async throws {
        let viewModel = makeViewModel(isDemoMode: true)
        let target = try XCTUnwrap(viewModel.visibleNotifications.first { $0.status == .open })
        XCTAssertFalse(target.isTemporarilySaved)

        _ = try await viewModel.offlineWorkStore.saveNotificationReview(
            NotificationReviewDraftPayload(
                notificationID: target.id,
                performedOn: Date(),
                results: [:],
                comments: [:],
                photoAttachments: [],
                isClosedLocally: false
            )
        )

        let updated = try XCTUnwrap(viewModel.visibleNotifications.first { $0.id == target.id })
        XCTAssertTrue(updated.isTemporarilySaved, "a saved draft has to reach the cached rows")
        XCTAssertEqual(updated.status, .draft)
    }
}
