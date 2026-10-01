import Foundation
import XCTest
@testable import mobileFacilityApp

/// `SAPNotificationReviewOutgoingCoordinator.prepare()` builds the `TO_*`
/// rows of the waiting work at every synchronization. One item that cannot
/// be built must not hold back the others, and rows of work that is gone
/// must not reach SAP.
final class OutgoingWorkIsolationTests: XCTestCase {
    private var directory: URL!

    override func setUpWithError() throws {
        directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: directory)
    }

    func testWorkThatCannotBeBuiltFailsAloneAndTheRestIsSent() async throws {
        let offline = InMemoryOfflineWorkRepository()
        let cache = try SQLiteSAPDataCacheRepository(
            databaseURL: directory.appendingPathComponent("cache.sqlite"), workerID: "worker"
        )
        // The cache holds no notification, so the review cannot be built.
        let review = Self.closedReview(notificationID: "4711")
        let reading = Self.meterReading()
        try await offline.save(review)
        try await offline.save(reading)

        let batch = try await Self.coordinator(offline: offline, cache: cache).prepare()

        XCTAssertEqual(batch.workItemIDs, [reading.id])
        XCTAssertEqual(batch.meterReadings.count, 1)
        let rowCount = try await cache.legacyRowCount(in: "TO_T0286")
        XCTAssertEqual(rowCount, 1)

        let saved = Dictionary(uniqueKeysWithValues: try await offline.loadWork(for: "worker").map { ($0.id, $0) })
        XCTAssertEqual(saved[review.id]?.status, .failed)
        XCTAssertEqual(saved[review.id]?.syncError, "Quellmeldung 4711 nicht gefunden.")
        XCTAssertEqual(saved[reading.id]?.status, .synchronizing)
        XCTAssertNil(saved[reading.id]?.syncError)
    }

    func testRowsOfWorkDeletedAfterAnEarlierAttemptAreNotSent() async throws {
        let offline = InMemoryOfflineWorkRepository()
        let cache = try SQLiteSAPDataCacheRepository(
            databaseURL: directory.appendingPathComponent("cache.sqlite"), workerID: "worker"
        )
        let coordinator = Self.coordinator(offline: offline, cache: cache)
        let reading = Self.meterReading()
        try await offline.save(reading)

        // The first attempt stages the reading, then breaks off before SAP
        // confirms it; the technician clears the reading afterwards.
        _ = try await coordinator.prepare()
        let stagedCount = try await cache.legacyRowCount(in: "TO_T0286")
        XCTAssertEqual(stagedCount, 1)
        try await offline.delete(ids: [reading.id])

        let batch = try await coordinator.prepare()

        XCTAssertTrue(batch.workItemIDs.isEmpty)
        let remainingCount = try await cache.legacyRowCount(in: "TO_T0286")
        XCTAssertEqual(remainingCount, 0)
        let payload = try await cache.stageOutgoing(requestID: "REQUEST", batch: .empty)
        XCTAssertTrue(payload.T_0286.isEmpty)
        await cache.abortOutgoing(requestID: "REQUEST")
    }

    func testReviewUploadErrorsExplainThemselves() {
        XCTAssertEqual(
            SAPNotificationReviewUploadError.missingPhoto("ABC").localizedDescription,
            "Foto ABC nicht gefunden."
        )
        XCTAssertEqual(
            SAPNotificationReviewUploadError.missingDocumentMapping("TFM9").localizedDescription,
            "Keine Dokumentklasse für Formular TFM9."
        )
    }

    private static func coordinator(
        offline: any OfflineWorkRepository,
        cache: SQLiteSAPDataCacheRepository
    ) -> SAPNotificationReviewOutgoingCoordinator {
        SAPNotificationReviewOutgoingCoordinator(
            workerID: "worker",
            syncUserID: "S50828",
            offlineRepository: offline,
            cacheRepository: cache,
            outgoingStore: cache,
            photoStore: InMemoryPhotoAttachmentStore()
        )
    }

    private static func closedReview(notificationID: String) -> OfflineWorkItem {
        let draft = NotificationReviewDraftPayload(
            notificationID: notificationID, performedOn: Date(timeIntervalSince1970: 1_700_000_000),
            results: ["TFM1-0010-1": .no], comments: [:],
            photoAttachments: [], isClosedLocally: true
        )
        return OfflineWorkItem(
            id: UUID(), workerID: "worker", type: .notificationReview, status: .pendingSynchronization,
            payload: .notificationReview(draft), createdAt: .now, updatedAt: .now, syncError: nil
        )
    }

    private static func meterReading() -> OfflineWorkItem {
        var meter = MeterReference(
            id: "000000000017", kind: .electricity, technicalPlaceID: "D1-HAM-40012-02",
            technicalPlaceName: "Hamburg", unit: "KWH", previousValue: 10, previousReadingAt: nil
        )
        meter.client = "100"
        let reading = MeterReadingDraftPayload(
            meter: meter, value: 12.5, note: "", recordedAt: Date(timeIntervalSince1970: 1_700_000_000)
        )
        return OfflineWorkItem(
            id: UUID(), workerID: "worker", type: .meterReading, status: .pendingSynchronization,
            payload: .meterReading(reading), createdAt: .now, updatedAt: .now, syncError: nil
        )
    }
}
