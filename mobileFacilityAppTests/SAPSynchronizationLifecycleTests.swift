import Foundation
import XCTest
@testable import mobileFacilityApp

final class SAPSynchronizationLifecycleTests: XCTestCase {
    private var databaseURL: URL!

    override func setUp() {
        super.setUp()
        databaseURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
            .appendingPathComponent("mtfm.db")
    }

    override func tearDown() {
        try? FileManager.default.removeItem(at: databaseURL.deletingLastPathComponent())
        super.tearDown()
    }

    // MARK: - Regular synchronization

    func testSynchronizationRunsTheLegacyStepsAndRemovesTheConfirmedWork() async throws {
        let store = try makeStore()
        try await queueNotificationHeader(in: store)
        let client = ScriptedDataExchangeClient()
        let work = RecordingOutgoingWork(batch: Self.batch)

        _ = try await lifecycle("A", client: client, store: store, work: work).run(progress: { _ in })

        XCTAssertEqual(client.calls, [
            "M0002001 MTFMSYNCTO-A",
            "M0002031 I1 MTFMSYNCTO-A",
            "M0002021 MTFMSYNCTO-A",
            "MMTFM002 MTFMSYNCTO-A",
            "MMTFM008 MTFMSYNCTO-A",
            "MMTFM004 MTFMSYNCFROM-A",
            "MMTFM003 MTFMSYNCFROM-A",
            "M0002003 MTFMSYNCFROM-A"
        ])
        XCTAssertEqual(client.sentPayloads.first?.T_0281.first?["REQID"], "MTFMSYNCTO-A")
        XCTAssertEqual(work.completed, [Self.batch.manifest])
        XCTAssertTrue(work.failed.isEmpty)
        let pending = try await store.pendingSynchronization()
        XCTAssertNil(pending)
        let queuedHeaders = try await store.legacyRowCount(in: "TO_T0281")
        XCTAssertEqual(queuedHeaders, 0)
    }

    /// `synchronizeDocTo._prepareAndSend302` walks every `TO_T0302` row, so a
    /// standard instruction document that SAP already holds goes up as its own
    /// `M0002031` call even though it carries no content.
    func testInstructionDocumentReferencesAreSentLikeEveryOtherDocument() async throws {
        let store = try makeStore()
        try await queueNotificationHeader(in: store)
        var batch = Self.batch
        batch.i3Documents = [
            SAPNotificationOutgoingDocument(metadata: ["DOCID": "D-2"], data: Data([4, 5]))
        ]
        batch.i3DocumentReferences = [
            SAPNotificationOutgoingDocument(
                metadata: ["DOCID": "D-3", "DOKNR": "DOKNR3"],
                data: Data(),
                referencesExistingDocument: true
            )
        ]
        let client = ScriptedDataExchangeClient()

        _ = try await lifecycle(
            "A", client: client, store: store, work: RecordingOutgoingWork(batch: batch)
        ).run(progress: { _ in })

        XCTAssertEqual(
            client.calls.filter { $0.hasPrefix("M0002031") },
            [
                "M0002031 I1 MTFMSYNCTO-A",
                "M0002031 I3 MTFMSYNCTO-A",
                "M0002031 I3 MTFMSYNCTO-A"
            ]
        )
        XCTAssertEqual(
            client.sentDocuments.last?.metadata["DOKNR"], "DOKNR3",
            "the reference is the last document of the request"
        )
        XCTAssertEqual(client.sentDocuments.last?.data, Data())
    }

    @MainActor
    func testPollingContinuesForAsLongAsSAPReportsThatItIsWorking() async throws {
        let store = try makeStore()
        let client = ScriptedDataExchangeClient()
        client.outgoingPostStatuses = Array(repeating: .success(.processing(statusText: nil)), count: 14)
            + [.success(.processing(statusText: "Verbuchung läuft")), .success(.completed)]
        let stages = StageRecorder()

        _ = try await lifecycle("A", client: client, store: store, work: nil).run(progress: { stages.stages.append($0) })

        XCTAssertEqual(client.calls.filter { $0.hasPrefix("MMTFM002") }.count, 16)
        XCTAssertTrue(stages.stages.contains(.waitingForOutgoingAcknowledgement(statusText: "Verbuchung läuft")))
    }

    func testPostSAPDidNotAcceptLeavesTheWorkQueued() async throws {
        let store = try makeStore()
        try await queueNotificationHeader(in: store)
        let client = ScriptedDataExchangeClient()
        client.outgoingPostStatuses = [.success(.notAccepted)]
        let work = RecordingOutgoingWork(batch: Self.batch)

        await XCTAssertThrowsErrorAsync(
            try await lifecycle("A", client: client, store: store, work: work).run(progress: { _ in })
        )

        XCTAssertEqual(work.failed, [Self.batch.manifest])
        XCTAssertTrue(work.completed.isEmpty)
        let pending = try await store.pendingSynchronization()
        XCTAssertNil(pending)
        let queuedHeaders = try await store.legacyRowCount(in: "TO_T0281")
        XCTAssertEqual(queuedHeaders, 1)
    }

    // MARK: - Interrupted TO request

    func testRequestSAPNeverPostedIsClearedBeforeTheWorkIsSentAgain() async throws {
        let store = try makeStore()
        try await queueNotificationHeader(in: store)
        let firstClient = ScriptedDataExchangeClient()
        firstClient.documentError = SAPReadError.httpStatus(500)
        let firstWork = RecordingOutgoingWork(batch: Self.batch)

        await XCTAssertThrowsErrorAsync(
            try await lifecycle("A", client: firstClient, store: store, work: firstWork).run(progress: { _ in })
        )
        let interrupted = try await store.pendingSynchronization()
        XCTAssertEqual(interrupted?.step, .outgoingMetadataSent)
        XCTAssertEqual(interrupted?.requestID, "MTFMSYNCTO-A")
        XCTAssertEqual(firstWork.failed, [Self.batch.manifest])

        let restartedStore = try makeStore()
        let secondClient = ScriptedDataExchangeClient()
        let secondWork = RecordingOutgoingWork(batch: Self.batch)
        _ = try await lifecycle("B", client: secondClient, store: restartedStore, work: secondWork)
            .run(progress: { _ in })

        XCTAssertEqual(Array(secondClient.calls.prefix(2)), [
            "MMTFM001 MTFMSYNCTO-A",
            "M0002001 MTFMSYNCTO-B"
        ])
        XCTAssertEqual(secondClient.sentPayloads.first?.T_0281.count, 1)
        XCTAssertEqual(secondWork.completed, [Self.batch.manifest])
    }

    func testPostedRequestSAPConfirmsLaterIsNotSentASecondTime() async throws {
        let store = try makeStore()
        try await queueNotificationHeader(in: store)
        let firstClient = ScriptedDataExchangeClient()
        firstClient.outgoingPostStatuses = [.success(.processing(statusText: nil))]
            + Array(repeating: .failure(SAPReadError.networkUnavailable), count: 3)
        let firstWork = RecordingOutgoingWork(batch: Self.batch)

        await XCTAssertThrowsErrorAsync(
            try await lifecycle("A", client: firstClient, store: store, work: firstWork).run(progress: { _ in })
        )
        let interrupted = try await store.pendingSynchronization()
        XCTAssertEqual(interrupted, SAPPendingSynchronization(
            step: .outgoingPosted,
            requestID: "MTFMSYNCTO-A",
            outgoingBatch: Self.batch.manifest
        ))
        // SAP may still be posting it: the work is neither failed nor removed.
        XCTAssertTrue(firstWork.failed.isEmpty)
        XCTAssertTrue(firstWork.completed.isEmpty)

        let restartedStore = try makeStore()
        let secondClient = ScriptedDataExchangeClient()
        let secondWork = RecordingOutgoingWork(batch: .empty)
        _ = try await lifecycle("B", client: secondClient, store: restartedStore, work: secondWork)
            .run(progress: { _ in })

        XCTAssertEqual(Array(secondClient.calls.prefix(2)), [
            "MMTFM002 MTFMSYNCTO-A",
            "M0002001 MTFMSYNCTO-B"
        ])
        XCTAssertEqual(secondClient.sentPayloads.first?.T_0281.count, 0)
        XCTAssertEqual(secondWork.completed, [Self.batch.manifest, SAPOutgoingBatchManifest.empty])
        let pending = try await restartedStore.pendingSynchronization()
        XCTAssertNil(pending)
    }

    func testPostedRequestSAPDidNotAcceptIsSentWithTheNewRequest() async throws {
        let store = try makeStore()
        try await queueNotificationHeader(in: store)
        let firstClient = ScriptedDataExchangeClient()
        firstClient.outgoingPostStatuses = Array(repeating: .failure(SAPReadError.requestTimedOut), count: 3)

        await XCTAssertThrowsErrorAsync(
            try await lifecycle("A", client: firstClient, store: store, work: RecordingOutgoingWork(batch: Self.batch))
                .run(progress: { _ in })
        )

        let secondClient = ScriptedDataExchangeClient()
        secondClient.outgoingPostStatuses = [.success(.notAccepted), .success(.completed)]
        let secondWork = RecordingOutgoingWork(batch: Self.batch)
        _ = try await lifecycle("B", client: secondClient, store: store, work: secondWork).run(progress: { _ in })

        XCTAssertEqual(Array(secondClient.calls.prefix(2)), [
            "MMTFM002 MTFMSYNCTO-A",
            "M0002001 MTFMSYNCTO-B"
        ])
        XCTAssertEqual(secondClient.sentPayloads.first?.T_0281.first?["REQID"], "MTFMSYNCTO-B")
        XCTAssertEqual(secondWork.completed, [Self.batch.manifest])
        let queuedHeaders = try await store.legacyRowCount(in: "TO_T0281")
        XCTAssertEqual(queuedHeaders, 0)
    }

    // MARK: - Interrupted FROM request

    func testPreparationStillRunningIsDownloadedWithoutANewUpload() async throws {
        let store = try makeStore()
        let firstClient = ScriptedDataExchangeClient()
        firstClient.incomingPreparationStatuses = Array(repeating: .failure(SAPReadError.networkUnavailable), count: 3)

        await XCTAssertThrowsErrorAsync(
            try await lifecycle("A", client: firstClient, store: store, work: nil).run(progress: { _ in })
        )
        let interrupted = try await store.pendingSynchronization()
        XCTAssertEqual(interrupted?.step, .incomingRequested)
        XCTAssertEqual(interrupted?.requestID, "MTFMSYNCFROM-A")

        let secondClient = ScriptedDataExchangeClient()
        let cachedData = try await lifecycle("B", client: secondClient, store: store, work: nil)
            .run(progress: { _ in })

        XCTAssertEqual(secondClient.calls, ["MMTFM003 MTFMSYNCFROM-A", "M0002003 MTFMSYNCFROM-A"])
        XCTAssertEqual(cachedData.metadata?.sapWorkerID, "S50828")
        let pending = try await store.pendingSynchronization()
        XCTAssertNil(pending)
    }

    func testBrokenOffDownloadIsDiscardedInSAPAndStartedAgain() async throws {
        let store = try makeStore()
        let firstClient = ScriptedDataExchangeClient()
        firstClient.packageError = SAPReadError.networkUnavailable

        await XCTAssertThrowsErrorAsync(
            try await lifecycle("A", client: firstClient, store: store, work: nil).run(progress: { _ in })
        )
        let interrupted = try await store.pendingSynchronization()
        XCTAssertEqual(interrupted?.step, .incomingReceiving)
        XCTAssertEqual(interrupted?.requestID, "MTFMSYNCFROM-A")

        let secondClient = ScriptedDataExchangeClient()
        _ = try await lifecycle("B", client: secondClient, store: store, work: nil).run(progress: { _ in })

        XCTAssertEqual(Array(secondClient.calls.prefix(2)), [
            "MMTFM005 MTFMSYNCFROM-A",
            "M0002001 MTFMSYNCTO-B"
        ])
        XCTAssertEqual(secondClient.calls.last, "M0002003 MTFMSYNCFROM-B")
        let pending = try await store.pendingSynchronization()
        XCTAssertNil(pending)
    }

    // MARK: - Lifecycle answers

    func testLifecycleStatusReadsTheLegacyParameters() throws {
        XCTAssertEqual(
            try SAPLegacyDataExchangeCodec.lifecycleStatus(from: Self.parameterResponse(#"{"PARAMETER2":"X"}"#)),
            .completed
        )
        XCTAssertEqual(
            try SAPLegacyDataExchangeCodec.lifecycleStatus(
                from: Self.parameterResponse(#"{"PARAMETER4":"X","PARAMETER5":"Verbuchung läuft"}"#)
            ),
            .processing(statusText: "Verbuchung läuft")
        )
        XCTAssertEqual(
            try SAPLegacyDataExchangeCodec.lifecycleStatus(from: Self.parameterResponse(#"{"PARAMETER1":""}"#)),
            .notAccepted
        )
        XCTAssertThrowsError(
            try SAPLegacyDataExchangeCodec.lifecycleStatus(from: #"[{"KEY":"TEXT","PAR":"","VALUE":"Unbekannt"}]"#)
        ) { error in
            guard case SAPReadError.backendMessage("Unbekannt") = error else {
                return XCTFail("Expected the SAP text, got \(error)")
            }
        }
    }

    // MARK: - Helpers

    private static let batch = SAPNotificationOutgoingBatch(
        workItemIDs: [UUID(uuidString: "5E1E2C9A-0000-4000-8000-000000000001")!],
        attachmentIDs: ["photo-1"],
        processIDs: ["P-1"],
        equipmentIDs: [],
        headers: [],
        values: [],
        documents: [SAPNotificationOutgoingDocument(metadata: ["DOCID": "D-1"], data: Data([1, 2, 3]))],
        equipment: []
    )

    private static func parameterResponse(_ parameters: String) -> String {
        let envelope: [[String: String]] = [["KEY": "STRUCTURE", "PAR": "LS_PARAMETER", "VALUE": parameters]]
        let data = try! JSONSerialization.data(withJSONObject: envelope)
        return String(decoding: data, as: UTF8.self)
    }

    /// A new instance on the same file stands in for an app restart.
    private func makeStore() throws -> SQLiteSAPDataCacheRepository {
        try SQLiteSAPDataCacheRepository(databaseURL: databaseURL, workerID: "local-1")
    }

    private func queueNotificationHeader(in store: SQLiteSAPDataCacheRepository) async throws {
        try await store.insertLegacyRows([["MANDT": "100", "VORGANGSNR": "P-1", "QMNUM": "N-1"]], into: "TO_T0281")
    }

    private func lifecycle(
        _ run: String,
        client: ScriptedDataExchangeClient,
        store: SQLiteSAPDataCacheRepository,
        work: RecordingOutgoingWork?
    ) -> SAPLegacySynchronizationLifecycle {
        let immediate = SAPLegacyPollingSchedule(initialDelay: .zero, interval: .zero, maximumConsecutiveFailures: 3)
        var lifecycle = SAPLegacySynchronizationLifecycle(
            sapWorkerID: "S50828",
            client: client,
            store: store,
            outgoingWork: work
        )
        lifecycle.outgoingPostSchedule = immediate
        lifecycle.incomingPreparationSchedule = immediate
        lifecycle.makeRequestID = { prefix in "\(prefix)-\(run)" }
        return lifecycle
    }
}

private func XCTAssertThrowsErrorAsync<T>(
    _ expression: @autoclosure () async throws -> T,
    file: StaticString = #filePath,
    line: UInt = #line
) async {
    do {
        _ = try await expression()
        XCTFail("Expected an error", file: file, line: line)
    } catch {}
}

@MainActor
private final class StageRecorder {
    var stages: [SAPReadRefreshStage] = []
}

/// Answers every SAP method as scripted and records the calls in order.
private final class ScriptedDataExchangeClient: SAPLegacyDataExchangeClient, @unchecked Sendable {
    private let lock = NSLock()
    private var recordedCalls: [String] = []
    private var recordedPayloads: [LegacySAPOutgoingPayload] = []
    /// Consumed in order; `completed` once they run out.
    var outgoingPostStatuses: [Result<SAPLegacyRequestStatus, Error>] = []
    var incomingPreparationStatuses: [Result<SAPLegacyRequestStatus, Error>] = []
    var documentError: Error?
    private var recordedDocuments: [SAPNotificationOutgoingDocument] = []
    var packageError: Error?

    var calls: [String] { lock.withLock { recordedCalls } }
    var sentPayloads: [LegacySAPOutgoingPayload] { lock.withLock { recordedPayloads } }
    var sentDocuments: [SAPNotificationOutgoingDocument] { lock.withLock { recordedDocuments } }

    func sendOutgoingMetadata(_ payload: LegacySAPOutgoingPayload, requestID: String) async throws {
        record("M0002001 \(requestID)")
        lock.withLock { recordedPayloads.append(payload) }
    }

    func sendOutgoingDocument(
        _ document: SAPNotificationOutgoingDocument,
        notificationType: String,
        requestID: String
    ) async throws {
        record("M0002031 \(notificationType) \(requestID)")
        lock.withLock { recordedDocuments.append(document) }
        if let documentError { throw documentError }
    }

    func triggerOutgoingPost(requestID: String) throws {
        record("M0002021 \(requestID)")
    }

    func outgoingPostStatus(requestID: String) async throws -> SAPLegacyRequestStatus {
        record("MMTFM002 \(requestID)")
        return try lock.withLock { Self.next(&outgoingPostStatuses) }.get()
    }

    func clearOutgoingRequest(requestID: String) async throws -> Bool {
        record("MMTFM001 \(requestID)")
        return true
    }

    func checkAppVersion(requestID: String) async throws {
        record("MMTFM008 \(requestID)")
    }

    func prepareIncomingData(fromRequestID: String, toRequestID: String) throws {
        record("MMTFM004 \(fromRequestID)")
    }

    func incomingPreparationStatus(requestID: String) async throws -> SAPLegacyRequestStatus {
        record("MMTFM003 \(requestID)")
        return try lock.withLock { Self.next(&incomingPreparationStatuses) }.get()
    }

    func incomingPackage(requestID: String) async throws -> LegacySAPIncomingPackage {
        record("M0002003 \(requestID)")
        if let packageError { throw packageError }
        return LegacySAPIncomingPackage(tables: [:], isLastPackage: true)
    }

    func discardIncomingRequest(requestID: String) async throws {
        record("MMTFM005 \(requestID)")
    }

    private func record(_ call: String) {
        lock.withLock { recordedCalls.append(call) }
    }

    private static func next(
        _ statuses: inout [Result<SAPLegacyRequestStatus, Error>]
    ) -> Result<SAPLegacyRequestStatus, Error> {
        statuses.isEmpty ? .success(.completed) : statuses.removeFirst()
    }
}

private final class RecordingOutgoingWork: SAPOutgoingWorkCoordinating, @unchecked Sendable {
    private let lock = NSLock()
    private let batch: SAPNotificationOutgoingBatch
    private var completedBatches: [SAPOutgoingBatchManifest] = []
    private var failedBatches: [SAPOutgoingBatchManifest] = []

    init(batch: SAPNotificationOutgoingBatch) {
        self.batch = batch
    }

    var completed: [SAPOutgoingBatchManifest] { lock.withLock { completedBatches } }
    var failed: [SAPOutgoingBatchManifest] { lock.withLock { failedBatches } }

    func prepare() async throws -> SAPNotificationOutgoingBatch { batch }

    func complete(_ batch: SAPOutgoingBatchManifest) async throws {
        lock.withLock { completedBatches.append(batch) }
    }

    func fail(_ batch: SAPOutgoingBatchManifest, error: Error) async {
        lock.withLock { failedBatches.append(batch) }
    }
}
