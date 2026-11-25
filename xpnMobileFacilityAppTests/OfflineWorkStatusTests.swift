import XCTest
@testable import mobileFacilityApp

/// The status vocabulary (draft / pending / synchronizing / synchronized /
/// failed / conflict) must never collapse into a single "complete" state:
/// only work SAP confirmed may leave the local queue.
@MainActor
final class OfflineWorkStatusTests: XCTestCase {
    private let workerID = "S50828"

    private func item(status: OfflineWorkStatus, syncError: String? = nil) -> OfflineWorkItem {
        OfflineWorkItem(
            id: UUID(), workerID: workerID, type: .manualCapture, status: status,
            payload: .manualCapture(.init(categoryKey: "manual.category.issue", location: status.rawValue, note: "")),
            createdAt: .now, updatedAt: .now, syncError: syncError
        )
    }

    func testOnlySynchronizedWorkLeavesTheActiveQueue() async throws {
        let repository = InMemoryOfflineWorkRepository()
        for status in OfflineWorkStatus.allCases {
            try await repository.save(item(status: status))
        }
        let store = OfflineWorkStore(repository: repository, workerID: workerID)

        await store.load()

        XCTAssertEqual(
            Set(store.activeQueueItems.map(\.status)),
            Set(OfflineWorkStatus.allCases).subtracting([.synchronized])
        )
        XCTAssertEqual(store.activeQueueCount, OfflineWorkStatus.allCases.count - 1)
    }

    func testFailedAndConflictWorkIsKeptLikeAnyOtherUnconfirmedWork() async throws {
        let repository = InMemoryOfflineWorkRepository()
        try await repository.save(item(status: .failed, syncError: "SAP rejected"))
        try await repository.save(item(status: .conflict))
        let store = OfflineWorkStore(repository: repository, workerID: workerID)

        await store.load()

        XCTAssertEqual(store.activeQueueCount, 2)
    }

    func testEveryStatusHasItsOwnTitle() {
        let titles = OfflineWorkStatus.allCases.map(\.titleKey)

        XCTAssertEqual(Set(titles).count, titles.count)
    }

    func testClosedMobileLadderIsQueuedForSAPWhateverStatusIsPassed() async throws {
        let store = OfflineWorkStore(repository: InMemoryOfflineWorkRepository(), workerID: workerID)
        var payload = MobileLadderDraftPayload(localDraftID: "closed")
        payload.isClosedLocally = true

        let saved = try await store.saveMobileLadder(payload: payload, status: .draft)

        XCTAssertEqual(saved.status, .pendingSynchronization)
    }

    func testOpenMobileLadderKeepsThePassedStatus() async throws {
        let store = OfflineWorkStore(repository: InMemoryOfflineWorkRepository(), workerID: workerID)

        let saved = try await store.saveMobileLadder(payload: MobileLadderDraftPayload(localDraftID: "open"), status: .draft)

        XCTAssertEqual(saved.status, .draft)
    }

    // MARK: - SQLite

    func testSQLiteKeepsEveryStatusAndItsSyncError() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let repository = try SQLiteOfflineWorkRepository(databaseURL: directory.appendingPathComponent("offline.sqlite"))
        let saved = OfflineWorkStatus.allCases.map { item(status: $0, syncError: "error \($0.rawValue)") }
        for item in saved {
            try await repository.save(item)
        }

        let loaded = try await repository.loadWork(for: workerID)

        XCTAssertEqual(loaded.count, saved.count)
        let loadedByID = Dictionary(uniqueKeysWithValues: loaded.map { ($0.id, $0) })
        for item in saved {
            XCTAssertEqual(loadedByID[item.id]?.status, item.status)
            XCTAssertEqual(loadedByID[item.id]?.syncError, item.syncError)
        }
    }

    func testSQLiteStatusUpdateReplacesTheItemInsteadOfAddingOne() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let repository = try SQLiteOfflineWorkRepository(databaseURL: directory.appendingPathComponent("offline.sqlite"))
        let pending = item(status: .pendingSynchronization)
        try await repository.save(pending)

        let failed = OfflineWorkItem(
            id: pending.id, workerID: workerID, type: pending.type, status: .failed,
            payload: pending.payload, createdAt: pending.createdAt, updatedAt: .now, syncError: "SAP rejected"
        )
        try await repository.save(failed)

        let loaded = try await repository.loadWork(for: workerID)
        XCTAssertEqual(loaded.map(\.status), [.failed])
        XCTAssertEqual(loaded.first?.syncError, "SAP rejected")
    }

    func testSQLiteKeepsWorkPerWorker() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let repository = try SQLiteOfflineWorkRepository(databaseURL: directory.appendingPathComponent("offline.sqlite"))
        try await repository.save(item(status: .draft))

        let otherWorker = try await repository.loadWork(for: "S99999")

        XCTAssertTrue(otherWorker.isEmpty)
    }
}
