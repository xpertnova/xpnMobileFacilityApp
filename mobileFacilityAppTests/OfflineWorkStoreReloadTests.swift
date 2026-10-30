import Foundation
import XCTest
@testable import mobileFacilityApp

/// Saves find their existing row in `OfflineWorkStore.items`, so a failed
/// reload must not turn the next save of the same work into a second row.
@MainActor
final class OfflineWorkStoreReloadTests: XCTestCase {
    func testSavingAReviewTwiceKeepsOneRowWhenTheReloadFails() async throws {
        let repository = ReloadFailingRepository()
        let store = OfflineWorkStore(repository: repository, workerID: "worker")
        await store.load()
        await repository.failLoads(true)

        let first = try await store.saveNotificationReview(Self.review(closed: false))
        let second = try await store.saveNotificationReview(Self.review(closed: true))

        XCTAssertEqual(store.state, .failed)
        XCTAssertEqual(first.id, second.id)
        let savedCount = await repository.savedCount()
        XCTAssertEqual(savedCount, 1)
        XCTAssertEqual(store.notificationReview(notificationID: "4711")?.isClosedLocally, true)
    }

    func testAReviewIsNotSavedBlindBeforeTheFirstSuccessfulRead() async {
        let repository = ReloadFailingRepository()
        await repository.failLoads(true)
        let store = OfflineWorkStore(repository: repository, workerID: "worker")

        do {
            _ = try await store.saveNotificationReview(Self.review(closed: false))
            XCTFail("Expected the save to be refused")
        } catch {
            XCTAssertEqual(error as? OfflineWorkRepositoryError, .unavailable)
        }
        let savedCount = await repository.savedCount()
        XCTAssertEqual(savedCount, 0)
    }

    func testTheSaveReadsTheListItselfWhenItWasNeverLoaded() async throws {
        let repository = ReloadFailingRepository()
        let earlier = OfflineWorkStore(repository: repository, workerID: "worker")
        let saved = try await earlier.saveNotificationReview(Self.review(closed: false))

        let store = OfflineWorkStore(repository: repository, workerID: "worker")
        let next = try await store.saveNotificationReview(Self.review(closed: true))

        XCTAssertEqual(next.id, saved.id)
    }

    private static func review(closed: Bool) -> NotificationReviewDraftPayload {
        NotificationReviewDraftPayload(
            notificationID: "4711", performedOn: Date(timeIntervalSince1970: 1_700_000_000),
            results: [:], comments: [:], photoAttachments: [], isClosedLocally: closed
        )
    }
}

private actor ReloadFailingRepository: OfflineWorkRepository {
    private var items: [UUID: OfflineWorkItem] = [:]
    private var failsLoads = false

    func failLoads(_ fails: Bool) { failsLoads = fails }
    func savedCount() -> Int { items.count }

    func loadWork(for workerID: String) async throws -> [OfflineWorkItem] {
        if failsLoads { throw OfflineWorkRepositoryError.invalidStoredItem }
        return Array(items.values)
    }

    func save(_ item: OfflineWorkItem) async throws { items[item.id] = item }
    func resetWork(for workerID: String) async throws { items = [:] }
}
