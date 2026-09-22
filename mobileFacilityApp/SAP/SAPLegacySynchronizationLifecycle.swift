import Foundation

/// The answer of the `MMTFM002` and `MMTFM003` lifecycle checks.
enum SAPLegacyRequestStatus: Equatable, Sendable {
    /// `PARAMETER2` is set: ABAP finished the request.
    case completed
    /// `PARAMETER4` is set: ABAP is still working. `PARAMETER5` may carry the
    /// text the legacy busy dialog shows meanwhile.
    case processing(statusText: String?)
    /// Neither is set: ABAP did not accept the request.
    case notAccepted
}

/// One `DATAEXCHANGESet` method per call, as `edata.controller` issues them.
protocol SAPLegacyDataExchangeClient: Sendable {
    /// `M0002001`: the rows staged in `TMP_TO_*`.
    func sendOutgoingMetadata(_ payload: LegacySAPOutgoingPayload, requestID: String) async throws
    /// `M0002031`: one document; `notificationType` is `I1`, `I2` or `I3`.
    func sendOutgoingDocument(
        _ document: SAPNotificationOutgoingDocument,
        notificationType: String,
        requestID: String
    ) async throws
    /// `M0002021`: starts the ABAP post without waiting for it.
    func triggerOutgoingPost(requestID: String) throws
    /// `MMTFM002`
    func outgoingPostStatus(requestID: String) async throws -> SAPLegacyRequestStatus
    /// `MMTFM001`: drops a TO request ABAP never posted. Returns whether SAP
    /// confirmed it.
    func clearOutgoingRequest(requestID: String) async throws -> Bool
    /// `MMTFM008`
    func checkAppVersion(requestID: String) async throws
    /// `MMTFM004`: starts preparing the FROM package without waiting for it.
    func prepareIncomingData(fromRequestID: String, toRequestID: String) throws
    /// `MMTFM003`
    func incomingPreparationStatus(requestID: String) async throws -> SAPLegacyRequestStatus
    /// `M0002003`: the next FROM package.
    func incomingPackage(requestID: String) async throws -> LegacySAPIncomingPackage
    /// `MMTFM005`: drops a FROM request whose download broke off.
    func discardIncomingRequest(requestID: String) async throws
}

/// How often `MMTFM002` and `MMTFM003` are asked. The legacy client repeats
/// a check every 30 seconds for as long as SAP reports that it is working.
struct SAPLegacyPollingSchedule: Sendable {
    var initialDelay: Duration
    var interval: Duration
    /// Transport failures in a row after which the check stops. The request
    /// stays in `TBL_REQUEST`, so the next synchronization continues it.
    var maximumConsecutiveFailures: Int

    /// `synchronize.js` checks the post one second after `M0002021`.
    static let outgoingPost = SAPLegacyPollingSchedule(
        initialDelay: .seconds(1), interval: .seconds(30), maximumConsecutiveFailures: 10
    )
    /// `prepareMetadataFrom.js` checks the package ten seconds after `MMTFM004`.
    static let incomingPreparation = SAPLegacyPollingSchedule(
        initialDelay: .seconds(10), interval: .seconds(30), maximumConsecutiveFailures: 10
    )
}

/// `edata.luw.synchronize`: a TO request uploads the closed local work, then
/// a FROM request downloads the new cache. Every step is recorded in
/// `TBL_REQUEST` before it starts, so a synchronization that broke off is
/// finished or cleared before the next one begins (`checkBeforeSynchronize`).
struct SAPLegacySynchronizationLifecycle: Sendable {
    let sapWorkerID: String
    let client: any SAPLegacyDataExchangeClient
    let store: any SAPLegacySynchronizationStore
    let outgoingWork: (any SAPOutgoingWorkCoordinating)?
    var outgoingPostSchedule = SAPLegacyPollingSchedule.outgoingPost
    var incomingPreparationSchedule = SAPLegacyPollingSchedule.incomingPreparation
    var makeRequestID: @Sendable (_ prefix: String) -> String = { prefix in
        let identifier = UUID().uuidString.replacingOccurrences(of: "-", with: "").prefix(16).uppercased()
        return "\(prefix)-\(identifier)"
    }

    func run(progress: @escaping SAPReadRefreshProgressHandler) async throws -> SAPCachedData {
        if let pending = try await store.pendingSynchronization(),
           let fromRequestID = try await finishInterrupted(pending, progress: progress) {
            return try await receiveIncoming(fromRequestID: fromRequestID, progress: progress)
        }

        // SAP prepares the FROM package only after the regular TO lifecycle,
        // including an otherwise-empty M0002001 payload.
        let toRequestID = makeRequestID("MTFMSYNCTO")
        let fromRequestID = makeRequestID("MTFMSYNCFROM")
        try await upload(requestID: toRequestID, progress: progress)

        SAPSynchronizationDiagnostics.logSynchronizationStep("Checking app version")
        await progress(.checkingAppVersion)
        try await client.checkAppVersion(requestID: toRequestID)

        SAPSynchronizationDiagnostics.logSynchronizationStage(4, "Preparing FROM package")
        await progress(.preparingIncomingData)
        try await store.recordSynchronizationStep(.incomingRequested, requestID: fromRequestID)
        try client.prepareIncomingData(fromRequestID: fromRequestID, toRequestID: toRequestID)
        let preparation = try await awaitIncomingPreparation(
            requestID: fromRequestID,
            initialDelay: incomingPreparationSchedule.initialDelay,
            progress: progress
        )
        if case let .notAccepted(message) = preparation {
            await store.abortIncomingRequest(requestID: fromRequestID)
            throw message.map(SAPReadError.backendMessage) ?? .malformedPayload
        }
        return try await receiveIncoming(fromRequestID: fromRequestID, progress: progress)
    }

    // MARK: - Interrupted synchronization

    /// `checkBeforeSynchronize`. Returns the FROM request whose package can be
    /// read now, or nil when a new synchronization follows.
    private func finishInterrupted(
        _ pending: SAPPendingSynchronization,
        progress: @escaping SAPReadRefreshProgressHandler
    ) async throws -> String? {
        SAPSynchronizationDiagnostics.logSynchronizationStep(
            "Finishing step \(pending.step.rawValue) of an interrupted synchronization"
        )
        switch pending.step {
        case .outgoingStaged, .outgoingMetadataSent:
            // `deleteTempTblsByErrorForSynchTo`: ABAP only holds the rows of a
            // request it never posted. The work is sent again afterwards.
            await progress(.resumingInterruptedSynchronization)
            do {
                let cleared = try await client.clearOutgoingRequest(requestID: pending.requestID)
                if !cleared {
                    SAPSynchronizationDiagnostics.logSynchronizationStep("MMTFM001 did not confirm the cleanup")
                }
            } catch SAPReadError.backendMessage(let message) {
                SAPSynchronizationDiagnostics.logBackendMessage(method: "MMTFM001", message: message)
            }
            await store.abortOutgoing(requestID: pending.requestID)
            return nil

        case .outgoingPosted:
            // `checkPostByAbap4RegSync` for the old request. Unlike the legacy
            // client, work SAP confirmed is not sent a second time.
            let outcome = try await awaitOutgoingPost(
                requestID: pending.requestID,
                initialDelay: .zero,
                progress: progress
            )
            switch outcome {
            case .completed:
                try await settleConfirmedOutgoing(requestID: pending.requestID, batch: pending.outgoingBatch)
            case .notAccepted:
                // The work is still queued and goes with the new request.
                await store.abortOutgoing(requestID: pending.requestID)
            }
            return nil

        case .incomingRequested:
            // `checkByMetadataFrom4RegSync`: SAP may still prepare the package
            // of the old request. Newer local work goes with the next run.
            let outcome = try await awaitIncomingPreparation(
                requestID: pending.requestID,
                initialDelay: .zero,
                progress: progress
            )
            if case .completed = outcome { return pending.requestID }
            await store.abortIncomingRequest(requestID: pending.requestID)
            return nil

        case .incomingReceiving:
            // `deleteFromDataByError`: the download broke off. Unlike the
            // legacy client, the committed cache stays until a new package
            // replaces it.
            await progress(.resumingInterruptedSynchronization)
            do {
                try await client.discardIncomingRequest(requestID: pending.requestID)
            } catch SAPReadError.backendMessage(let message) {
                SAPSynchronizationDiagnostics.logBackendMessage(method: "MMTFM005", message: message)
            }
            await store.abortIncoming()
            await store.abortIncomingRequest(requestID: pending.requestID)
            return nil
        }
    }

    // MARK: - TO request

    private func upload(
        requestID: String,
        progress: @escaping SAPReadRefreshProgressHandler
    ) async throws {
        SAPSynchronizationDiagnostics.logSynchronizationStage(1, "Uploading TO metadata")
        // Preparing the local outgoing queue can fail before any SAP request.
        // Report that work as the upload stage so the dialog never attributes
        // a local queue error to the already-completed password check.
        await progress(.uploadingOutgoingMetadata)
        let batch = try await outgoingWork?.prepare() ?? .empty
        do {
            let payload = try await store.stageOutgoing(requestID: requestID, batch: batch.manifest)
            SAPSynchronizationDiagnostics.logI2(
                "TO request carries T_0281=\(payload.T_0281.count) T_0282=\(payload.T_0282.count) " +
                    "T_0284=\(payload.T_0284.count) T_0285=\(payload.T_0285.count) " +
                    "T_0300=\(payload.T_0300.count) T_0302=\(payload.T_0302.count); " +
                    "batch built \(batch.i2Notifications.count) I2 row(s), " +
                    "\(batch.i2Documents.count) I2 document(s)"
            )
            try await client.sendOutgoingMetadata(payload, requestID: requestID)
            try await store.recordSynchronizationStep(.outgoingMetadataSent, requestID: requestID)
            SAPSynchronizationDiagnostics.logSynchronizationStage(2, "TO rows staged with request ID")

            // `synchronizeDocTo` uploads the `TO_T0282` documents as `I1`, the
            // `TO_T0285` copies of the I2 notifications as `I2`, then the
            // `TO_T0302` reports of the I3 notifications as `I3`.
            // `_prepareAndSend302` walks every `TO_T0302` row, including the
            // reference rows of the standard instruction documents, which go
            // up with an empty `FELDWERT`.
            let documents = batch.documents.map { (document: $0, notificationType: "I1") }
                + batch.i2Documents.map { (document: $0, notificationType: "I2") }
                + batch.i3Documents.map { (document: $0, notificationType: "I3") }
                + batch.i3DocumentReferences.map { (document: $0, notificationType: "I3") }
            for (index, entry) in documents.enumerated() {
                await progress(.uploadingOutgoingDocuments(current: index + 1, total: documents.count))
                try await client.sendOutgoingDocument(
                    entry.document,
                    notificationType: entry.notificationType,
                    requestID: requestID
                )
            }

            SAPSynchronizationDiagnostics.logSynchronizationStage(3, "Triggering TO post")
            await progress(.postingOutgoingData)
            // Recorded before the trigger, as in `synchronize.js`: a post that
            // never reached ABAP is answered as not accepted by MMTFM002.
            try await store.recordSynchronizationStep(.outgoingPosted, requestID: requestID)
        } catch {
            // M0002021 was not triggered. A recorded request is cleared in SAP
            // by the next synchronization (MMTFM001); the work is sent again.
            await outgoingWork?.fail(batch.manifest, error: error)
            throw error
        }

        // From here on SAP may process the request whatever happens on the
        // device. Until MMTFM002 answers, the work stays `synchronizing` and
        // the recorded step lets the next synchronization ask again.
        try client.triggerOutgoingPost(requestID: requestID)
        SAPSynchronizationDiagnostics.logSynchronizationStep("Waiting for TO acknowledgement")
        let outcome = try await awaitOutgoingPost(
            requestID: requestID,
            initialDelay: outgoingPostSchedule.initialDelay,
            progress: progress
        )
        switch outcome {
        case .completed:
            try await settleConfirmedOutgoing(requestID: requestID, batch: batch.manifest)
        case let .notAccepted(message):
            let error = message.map(SAPReadError.backendMessage) ?? .malformedPayload
            await store.abortOutgoing(requestID: requestID)
            await outgoingWork?.fail(batch.manifest, error: error)
            throw error
        }
    }

    /// `deleteAfterSuccessByPost`.
    private func settleConfirmedOutgoing(requestID: String, batch: SAPOutgoingBatchManifest) async throws {
        // The work goes before its rows. Were the rows removed first, a failed
        // removal of the work would queue it, and send it, a second time.
        try await outgoingWork?.complete(batch)
        try await store.confirmOutgoing(requestID: requestID)
    }

    private func awaitOutgoingPost(
        requestID: String,
        initialDelay: Duration,
        progress: @escaping SAPReadRefreshProgressHandler
    ) async throws -> PollOutcome {
        try await poll(
            schedule: outgoingPostSchedule,
            initialDelay: initialDelay,
            stage: { .waitingForOutgoingAcknowledgement(statusText: $0) },
            progress: progress
        ) {
            try await client.outgoingPostStatus(requestID: requestID)
        }
    }

    // MARK: - FROM request

    private func awaitIncomingPreparation(
        requestID: String,
        initialDelay: Duration,
        progress: @escaping SAPReadRefreshProgressHandler
    ) async throws -> PollOutcome {
        try await poll(
            schedule: incomingPreparationSchedule,
            initialDelay: initialDelay,
            stage: { .waitingForIncomingData(statusText: $0) },
            progress: progress
        ) {
            try await client.incomingPreparationStatus(requestID: requestID)
        }
    }

    private func receiveIncoming(
        fromRequestID: String,
        progress: @escaping SAPReadRefreshProgressHandler
    ) async throws -> SAPCachedData {
        try await store.beginIncoming()
        let cachedData: SAPCachedData
        do {
            try await store.recordSynchronizationStep(.incomingReceiving, requestID: fromRequestID)
            var isLastPackage = false
            for packageNumber in 1...256 {
                await progress(.receivingIncomingPackages(packageNumber: packageNumber))
                let package = try await client.incomingPackage(requestID: fromRequestID)
                try await store.appendIncoming(package)
                isLastPackage = package.isLastPackage
                if isLastPackage { break }
            }
            guard isLastPackage else { throw SAPReadError.malformedPayload }
            await progress(.savingSnapshot)
            cachedData = try await store.commitIncoming(sapWorkerID: sapWorkerID, refreshedAt: Date())
        } catch {
            // A recorded step 5 makes the next synchronization discard this
            // FROM request in SAP (MMTFM005) before it asks for a new one.
            await store.abortIncoming()
            throw error
        }
        let cacheSummary = try await store.incomingCacheSummary()
        SAPSynchronizationDiagnostics.logSynchronizationCompleted(cacheSummary)
        return cachedData
    }

    // MARK: - Polling

    private enum PollOutcome {
        case completed
        case notAccepted(message: String?)
    }

    /// `checkPostByAbap4RegSync` / `checkByMetadataFrom4RegSync`: asks again
    /// after every interval for as long as SAP answers that it is working.
    private func poll(
        schedule: SAPLegacyPollingSchedule,
        initialDelay: Duration,
        stage: (String?) -> SAPReadRefreshStage,
        progress: @escaping SAPReadRefreshProgressHandler,
        check: () async throws -> SAPLegacyRequestStatus
    ) async throws -> PollOutcome {
        var delay = initialDelay
        var statusText: String?
        var consecutiveFailures = 0
        while true {
            await progress(stage(statusText))
            if delay > .zero {
                try await Task.sleep(for: delay)
            }
            try Task.checkCancellation()
            do {
                switch try await check() {
                case .completed:
                    return .completed
                case .notAccepted:
                    return .notAccepted(message: nil)
                case let .processing(text):
                    consecutiveFailures = 0
                    if let text, !text.isEmpty { statusText = text }
                }
            } catch SAPReadError.backendMessage(let message) {
                return .notAccepted(message: message)
            } catch let error as SAPReadError where Self.isTransient(error) {
                // The check is authoritative, so it is asked again.
                consecutiveFailures += 1
                guard consecutiveFailures < schedule.maximumConsecutiveFailures else { throw error }
            }
            delay = schedule.interval
        }
    }

    /// SAPURLSession can surface a transient gateway or session interruption
    /// as `serviceUnavailable` instead of a URLError.
    static func isTransient(_ error: SAPReadError) -> Bool {
        switch error {
        case .httpStatus(504), .requestTimedOut, .networkUnavailable, .serviceUnavailable:
            true
        default:
            false
        }
    }
}
