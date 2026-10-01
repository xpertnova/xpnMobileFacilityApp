import Foundation
import XCTest
@testable import mobileFacilityApp

final class SAPSyncTokenTests: XCTestCase {
    func testInMemoryTokenStore() throws {
        let store = InMemorySAPSyncTokenStore()
        let workerID = "s500128"

        XCTAssertNil(store.token(for: workerID))

        try store.save(token: "token-abc-123", for: workerID)
        XCTAssertEqual(store.token(for: workerID), "token-abc-123")
        // Case-insensitive / normalized lookup
        XCTAssertEqual(store.token(for: "  S500128  "), "token-abc-123")

        // Overwrite token
        try store.save(token: "token-xyz-789", for: "S500128")
        XCTAssertEqual(store.token(for: workerID), "token-xyz-789")

        // Delete token
        store.deleteToken(for: "s500128")
        XCTAssertNil(store.token(for: workerID))
    }

    func testLandscapeScopedAccountsDoNotReuseTokens() throws {
        let store = InMemorySAPSyncTokenStore()
        let qaAccount = SAPSyncTokenScope.account(
            synchronizationUserID: "S500128",
            landscapeFingerprint: "qa-landscape"
        )
        let productionAccount = SAPSyncTokenScope.account(
            synchronizationUserID: "S500128",
            landscapeFingerprint: "production-landscape"
        )

        XCTAssertNotEqual(qaAccount, productionAccount)
        try store.save(token: "QA-TOKEN", for: qaAccount)
        XCTAssertEqual(store.token(for: qaAccount), "QA-TOKEN")
        XCTAssertNil(store.token(for: productionAccount))
    }

    func testHTTPFailureDiagnosticKeepsOnlySafeResponseMetadata() throws {
        let response = try XCTUnwrap(HTTPURLResponse(
            url: XCTUnwrap(URL(string: "https://example.invalid/hidden")),
            statusCode: 403,
            httpVersion: nil,
            headerFields: [
                "X-Correlation-ID": "gateway-trace-123",
                "WWW-Authenticate": "Bearer realm=protected-resource",
                "Set-Cookie": "must-not-appear"
            ]
        ))

        let summary = SAPSynchronizationDiagnostics.httpFailureSummary(
            method: "M0153003",
            response: response
        )

        XCTAssertEqual(
            summary,
            "[SAP Sync Debug] M0153003 received HTTP 403; correlation ID=gateway-trace-123; authentication challenge=Bearer."
        )
        XCTAssertFalse(summary.contains("Set-Cookie"))
        XCTAssertFalse(summary.contains("protected-resource"))
        XCTAssertFalse(summary.contains("example.invalid"))
    }

    func testHTTPFailureDiagnosticIncludesSafeODataErrorDetails() throws {
        let response = try XCTUnwrap(HTTPURLResponse(
            url: XCTUnwrap(URL(string: "https://example.invalid/hidden")),
            statusCode: 403,
            httpVersion: nil,
            headerFields: nil
        ))
        let responseBody = Data("""
        {"error":{"code":"/IWFND/CM_COS/004","message":{"value":"No authorization for this request."}}}
        """.utf8)

        let summary = SAPSynchronizationDiagnostics.httpFailureSummary(
            method: "M0153003",
            response: response,
            responseBody: responseBody
        )

        XCTAssertEqual(
            summary,
            "[SAP Sync Debug] M0153003 received HTTP 403; SAP error code=/IWFND/CM_COS/004; SAP reason=No authorization for this request."
        )
    }

    func testCodecTokenExtractionFromDictionary() throws {
        let envelopeJSON = """
        [
            {
                "KEY": "STRUCTURE",
                "PAR": "/EZO/MTFMS_PARAMETER",
                "VALUE": "{\\"CHECKPW\\":\\"X\\",\\"PWINITIAL\\":\\"\\",\\"0155\\":{\\"TOKEN\\":\\"SEC-TOKEN-42\\",\\"DEVICEID\\":\\"DEV-01\\",\\"PERSNR\\":\\"S5001\\"}}"
            }
        ]
        """
        let authorization = try SAPLegacyDataExchangeCodec.authorization(from: envelopeJSON)
        XCTAssertTrue(authorization.isAccepted)
        XCTAssertFalse(authorization.requiresInitialPasswordChange)
        XCTAssertEqual(authorization.token, "SEC-TOKEN-42")
    }

    func testCodecTokenExtractionFromJsonString() throws {
        let innerDict = ["TOKEN": "STRING-TOKEN-99", "DEVICEID": "DEV-01"]
        let innerData = try JSONSerialization.data(withJSONObject: innerDict)
        let innerString = String(data: innerData, encoding: .utf8)!

        let valueDict: [String: Any] = [
            "CHECKPW": "X",
            "PWINITIAL": "",
            "0155": innerString
        ]
        let valueData = try JSONSerialization.data(withJSONObject: valueDict)
        let valueString = String(data: valueData, encoding: .utf8)!

        let envelope: [[String: String]] = [
            [
                "KEY": "STRUCTURE",
                "PAR": "/EZO/MTFMS_PARAMETER",
                "VALUE": valueString
            ]
        ]
        let envelopeData = try JSONSerialization.data(withJSONObject: envelope)
        let envelopeJSON = String(data: envelopeData, encoding: .utf8)!

        let authorization = try SAPLegacyDataExchangeCodec.authorization(from: envelopeJSON)
        XCTAssertTrue(authorization.isAccepted)
        XCTAssertEqual(authorization.token, "STRING-TOKEN-99")
    }

    func testCodecTokenExtractionFromRawTokenString() throws {
        let valueDict: [String: Any] = [
            "CHECKPW": "X",
            "PWINITIAL": "",
            "0155": "RAW-TOKEN-12345"
        ]
        let valueData = try JSONSerialization.data(withJSONObject: valueDict)
        let valueString = String(data: valueData, encoding: .utf8)!

        let envelope: [[String: String]] = [
            [
                "KEY": "STRUCTURE",
                "PAR": "/EZO/MTFMS_PARAMETER",
                "VALUE": valueString
            ]
        ]
        let envelopeData = try JSONSerialization.data(withJSONObject: envelope)
        let envelopeJSON = String(data: envelopeData, encoding: .utf8)!

        let authorization = try SAPLegacyDataExchangeCodec.authorization(from: envelopeJSON)
        XCTAssertTrue(authorization.isAccepted)
        XCTAssertEqual(authorization.token, "RAW-TOKEN-12345")
    }

    func testCodecAuthorizationWithoutToken() throws {
        let envelopeJSON = """
        [
            {
                "KEY": "STRUCTURE",
                "PAR": "/EZO/MTFMS_PARAMETER",
                "VALUE": "{\\"CHECKPW\\":\\"X\\",\\"PWINITIAL\\":\\"\\"}"
            }
        ]
        """
        let authorization = try SAPLegacyDataExchangeCodec.authorization(from: envelopeJSON)
        XCTAssertTrue(authorization.isAccepted)
        XCTAssertNil(authorization.token)
    }

    func testCodecTokenAuthorizationSuccess() throws {
        let envelopeJSON = """
        [
            {
                "KEY": "STRUCTURE",
                "PAR": "/EZO/MTFMS_PARAMETER",
                "VALUE": "{\\"CHECKPW\\":\\"X\\"}"
            }
        ]
        """
        let isValid = try SAPLegacyDataExchangeCodec.tokenAuthorization(from: envelopeJSON)
        XCTAssertTrue(isValid)
    }

    func testCodecTokenAuthorizationRejection() throws {
        let envelopeJSON = """
        [
            {
                "KEY": "STRUCTURE",
                "PAR": "/EZO/MTFMS_PARAMETER",
                "VALUE": "{\\"CHECKPW\\":\\"\\"}"
            }
        ]
        """
        let isValid = try SAPLegacyDataExchangeCodec.tokenAuthorization(from: envelopeJSON)
        XCTAssertFalse(isValid)
    }

    func testCodecTokenAuthorizationWithBackendErrorMessage() throws {
        let envelopeJSON = """
        [
            {
                "KEY": "TEXT",
                "PAR": "",
                "VALUE": "Session expired or active on another device"
            }
        ]
        """
        let isValid = try SAPLegacyDataExchangeCodec.tokenAuthorization(from: envelopeJSON)
        XCTAssertFalse(isValid)
    }

    @MainActor
    func testDataStoreTokenRefreshAndFallback() async throws {
        let tokenStore = InMemorySAPSyncTokenStore()
        let workerID = "TEST_WORKER"
        try tokenStore.save(token: "SAVED_TOKEN", for: workerID)

        let mockService = MockTokenRefreshService()
        let dataStore = SAPDataStore(
            repository: InMemorySAPDataCacheRepository(workerID: workerID),
            refreshService: mockService,
            tokenStore: tokenStore,
            localWorkerID: workerID,
            synchronizationUserID: workerID
        )

        XCTAssertTrue(dataStore.hasValidSavedToken)

        // 1. Successful token refresh
        mockService.shouldSucceedWithToken = true
        let success = await dataStore.refreshWithSavedToken()
        XCTAssertTrue(success)
        XCTAssertEqual(mockService.tokenRefreshCallCount, 1)
        XCTAssertTrue(dataStore.hasValidSavedToken)

        // 2. Token rejected on another device (throws tokenInvalidOrExpired)
        mockService.shouldSucceedWithToken = false
        let fallbackNeeded = await dataStore.refreshWithSavedToken()
        XCTAssertFalse(fallbackNeeded)
        // Stored token should have been purged on rejection
        XCTAssertFalse(dataStore.hasValidSavedToken)
        XCTAssertNil(tokenStore.token(for: workerID))
        XCTAssertNil(dataStore.refreshError) // Silent fallback to password prompt

        // 3. Password refresh stores new token
        mockService.returnedTokenOnPasswordSync = "NEW_SAVED_TOKEN"
        await dataStore.refresh(sapPassword: "valid_password")
        XCTAssertEqual(mockService.passwordRefreshCallCount, 1)
        // Store updated with new token
        try tokenStore.save(token: "NEW_SAVED_TOKEN", for: workerID)
        XCTAssertTrue(dataStore.hasValidSavedToken)
    }

    @MainActor
    func testForbiddenSavedTokenIsDiscardedBeforePasswordFallback() async throws {
        let tokenStore = InMemorySAPSyncTokenStore()
        let workerID = "TEST_WORKER"
        try tokenStore.save(token: "STALE_TOKEN", for: workerID)

        let mockService = MockTokenRefreshService()
        mockService.tokenRefreshError = .httpStatus(403)
        let dataStore = SAPDataStore(
            repository: InMemorySAPDataCacheRepository(workerID: workerID),
            refreshService: mockService,
            tokenStore: tokenStore,
            localWorkerID: workerID,
            synchronizationUserID: workerID
        )

        let didRefresh = await dataStore.refreshWithSavedToken()
        XCTAssertFalse(didRefresh)
        XCTAssertFalse(dataStore.hasValidSavedToken)
        XCTAssertNil(tokenStore.token(for: workerID))
        XCTAssertNil(dataStore.refreshError)
    }

    func testOnlyAnInvalidTokenAnswerDiscardsTheSavedToken() {
        XCTAssertTrue(SAPInboundNotificationRefreshService.discardsSavedToken(after: SAPReadError.tokenInvalidOrExpired))

        let keptAfter: [Error] = [
            SAPReadError.networkUnavailable,
            SAPReadError.requestTimedOut,
            SAPReadError.serviceUnavailable,
            SAPReadError.httpStatus(503),
            SAPReadError.httpStatus(504),
            SAPReadError.malformedPayload,
            CancellationError()
        ]
        for error in keptAfter {
            XCTAssertFalse(
                SAPInboundNotificationRefreshService.discardsSavedToken(after: error),
                "\(error) must not discard the saved token"
            )
        }
    }

    @MainActor
    func testNetworkFailureDuringTokenRefreshKeepsTheSavedToken() async throws {
        let tokenStore = InMemorySAPSyncTokenStore()
        let workerID = "TEST_WORKER"
        try tokenStore.save(token: "SAVED_TOKEN", for: workerID)

        let mockService = MockTokenRefreshService()
        mockService.tokenRefreshError = .networkUnavailable
        let dataStore = SAPDataStore(
            repository: InMemorySAPDataCacheRepository(workerID: workerID),
            refreshService: mockService,
            tokenStore: tokenStore,
            localWorkerID: workerID,
            synchronizationUserID: workerID
        )

        let didRefresh = await dataStore.refreshWithSavedToken()
        XCTAssertFalse(didRefresh)
        XCTAssertEqual(tokenStore.token(for: workerID), "SAVED_TOKEN")
        XCTAssertTrue(dataStore.hasValidSavedToken)
        guard case .networkUnavailable = dataStore.refreshError else {
            return XCTFail("Expected the network failure to be shown")
        }
    }

    @MainActor
    func testPasswordRefreshFailureKeepsSafeFailureContextForTheDialog() async throws {
        let workerID = "TEST_WORKER"
        let mockService = MockTokenRefreshService()
        mockService.passwordRefreshError = .httpStatus(403)
        let dataStore = SAPDataStore(
            repository: InMemorySAPDataCacheRepository(workerID: workerID),
            refreshService: mockService,
            localWorkerID: workerID,
            synchronizationUserID: workerID
        )

        await dataStore.refresh(sapPassword: "not-stored")

        guard let failureContext = dataStore.refreshFailureContext else {
            return XCTFail("Expected the dialog to receive a failure context")
        }
        XCTAssertEqual(failureContext.authenticationMethod, .password)
        XCTAssertEqual(failureContext.stage, .authenticating)
        guard case .httpStatus(403) = failureContext.error else {
            return XCTFail("Expected the dialog context to retain HTTP 403")
        }
    }

    @MainActor
    func testPasswordRefreshFailureAfterPostUsesThePostAcknowledgementStage() async throws {
        let workerID = "TEST_WORKER"
        let mockService = MockTokenRefreshService()
        mockService.passwordFailureStage = .waitingForOutgoingAcknowledgement()
        mockService.passwordRefreshError = .serviceUnavailable
        let dataStore = SAPDataStore(
            repository: InMemorySAPDataCacheRepository(workerID: workerID),
            refreshService: mockService,
            localWorkerID: workerID,
            synchronizationUserID: workerID
        )

        await dataStore.refresh(sapPassword: "not-stored")

        guard let failureContext = dataStore.refreshFailureContext else {
            return XCTFail("Expected the dialog to retain the post failure stage")
        }
        XCTAssertEqual(failureContext.stage, .waitingForOutgoingAcknowledgement())
        guard case .serviceUnavailable = failureContext.error else {
            return XCTFail("Expected the original service-unavailable error")
        }
    }

    @MainActor
    func testViewModelSAPRefreshWithSavedTokenShowsProgressAndCompletes() async throws {
        let tokenStore = InMemorySAPSyncTokenStore()
        let workerID = "TEST_WORKER"
        try tokenStore.save(token: "SAVED_TOKEN", for: workerID)
        let mockService = MockTokenRefreshService()
        let dataStore = SAPDataStore(
            repository: InMemorySAPDataCacheRepository(workerID: workerID),
            refreshService: mockService,
            tokenStore: tokenStore,
            localWorkerID: workerID,
            synchronizationUserID: workerID
        )
        let viewModel = FacilityDemoViewModel(
            isDemoMode: false,
            offlineWorkStore: OfflineWorkStore(
                repository: InMemoryOfflineWorkRepository(),
                workerID: workerID
            ),
            sapDataStore: dataStore,
            meterReferenceProvider: DemoMeterReferenceProvider(),
            photoAttachmentStore: InMemoryPhotoAttachmentStore(),
            workerDisplayName: "Test User",
            workerRole: .technician
        )

        XCTAssertFalse(viewModel.shouldPresentSAPRefresh)
        XCTAssertFalse(dataStore.isRefreshing)

        viewModel.requestSAPRefresh()

        // shouldPresentSAPRefresh MUST be true immediately so user sees progress dialog
        XCTAssertTrue(viewModel.shouldPresentSAPRefresh)
        XCTAssertTrue(dataStore.isRefreshing)
        XCTAssertEqual(dataStore.refreshStage, .authenticating)

        // Wait for async task to complete
        try await Task.sleep(for: .milliseconds(50))

        XCTAssertFalse(dataStore.isRefreshing)
        XCTAssertFalse(viewModel.shouldPresentSAPRefresh)
        XCTAssertEqual(mockService.tokenRefreshCallCount, 1)
    }

    @MainActor
    func testViewModelSAPRefreshWithRejectedTokenTransitionsToPasswordPrompt() async throws {
        let tokenStore = InMemorySAPSyncTokenStore()
        let workerID = "TEST_WORKER"
        try tokenStore.save(token: "EXPIRED_TOKEN", for: workerID)
        let mockService = MockTokenRefreshService()
        mockService.shouldSucceedWithToken = false
        let dataStore = SAPDataStore(
            repository: InMemorySAPDataCacheRepository(workerID: workerID),
            refreshService: mockService,
            tokenStore: tokenStore,
            localWorkerID: workerID,
            synchronizationUserID: workerID
        )
        let viewModel = FacilityDemoViewModel(
            isDemoMode: false,
            offlineWorkStore: OfflineWorkStore(
                repository: InMemoryOfflineWorkRepository(),
                workerID: workerID
            ),
            sapDataStore: dataStore,
            meterReferenceProvider: DemoMeterReferenceProvider(),
            photoAttachmentStore: InMemoryPhotoAttachmentStore(),
            workerDisplayName: "Test User",
            workerRole: .technician
        )

        viewModel.requestSAPRefresh()

        // Immediately presents dialog in authenticating progress mode
        XCTAssertTrue(viewModel.shouldPresentSAPRefresh)
        XCTAssertTrue(dataStore.isRefreshing)

        // Wait for async token check to complete and fail
        try await Task.sleep(for: .milliseconds(50))

        // When token is rejected, isRefreshing turns false, but shouldPresentSAPRefresh remains true,
        // transitioning smoothly to the password input form!
        XCTAssertFalse(dataStore.isRefreshing)
        XCTAssertTrue(viewModel.shouldPresentSAPRefresh)
        XCTAssertFalse(dataStore.hasValidSavedToken)
        XCTAssertNil(dataStore.refreshError)
    }

    @MainActor
    func testViewModelSAPRefreshWithoutTokenShowsPasswordPromptImmediately() {
        let tokenStore = InMemorySAPSyncTokenStore()
        let workerID = "TEST_WORKER"
        let mockService = MockTokenRefreshService()
        let dataStore = SAPDataStore(
            repository: InMemorySAPDataCacheRepository(workerID: workerID),
            refreshService: mockService,
            tokenStore: tokenStore,
            localWorkerID: workerID,
            synchronizationUserID: workerID
        )
        let viewModel = FacilityDemoViewModel(
            isDemoMode: false,
            offlineWorkStore: OfflineWorkStore(
                repository: InMemoryOfflineWorkRepository(),
                workerID: workerID
            ),
            sapDataStore: dataStore,
            meterReferenceProvider: DemoMeterReferenceProvider(),
            photoAttachmentStore: InMemoryPhotoAttachmentStore(),
            workerDisplayName: "Test User",
            workerRole: .technician
        )

        viewModel.requestSAPRefresh()

        // Directly presents password dialog without progress state
        XCTAssertTrue(viewModel.shouldPresentSAPRefresh)
        XCTAssertFalse(dataStore.isRefreshing)
    }

    @MainActor
    func testViewModelSAPRefreshWithPendingDraftsPreservesDraftAndShowsPasswordPrompt() async throws {
        let workerID = "TEST_WORKER"
        let repo = InMemoryOfflineWorkRepository()
        let offlineWorkStore = OfflineWorkStore(repository: repo, workerID: workerID)
        let draftItem = OfflineWorkItem(
            id: UUID(),
            workerID: workerID,
            type: .defect,
            status: .draft,
            payload: .defect(DefectDraftPayload(
                technicalObject: .init(kind: .equipment, objectID: "EQ-1"),
                technicalObjectName: "Door",
                dinGroup: nil,
                priority: .medium,
                shortText: "Draft Defect",
                longText: "",
                attachmentIDs: []
            )),
            createdAt: Date(),
            updatedAt: Date(),
            syncError: nil
        )
        try await repo.save(draftItem)
        await offlineWorkStore.load()
        XCTAssertEqual(offlineWorkStore.localWorkCount, 1)

        let mockService = MockTokenRefreshService()
        let dataStore = SAPDataStore(
            repository: InMemorySAPDataCacheRepository(workerID: workerID),
            refreshService: mockService,
            localWorkerID: workerID,
            synchronizationUserID: workerID
        )
        let viewModel = FacilityDemoViewModel(
            isDemoMode: false,
            offlineWorkStore: offlineWorkStore,
            sapDataStore: dataStore,
            meterReferenceProvider: DemoMeterReferenceProvider(),
            photoAttachmentStore: InMemoryPhotoAttachmentStore(),
            workerDisplayName: "Test User",
            workerRole: .technician
        )

        viewModel.requestSAPRefresh()

        XCTAssertFalse(viewModel.shouldConfirmSynchronization)
        XCTAssertTrue(viewModel.shouldPresentSAPRefresh)
        XCTAssertFalse(dataStore.isRefreshing)
        XCTAssertEqual(offlineWorkStore.localWorkCount, 1)
    }

    /// Like the legacy `DialogBeforeSync`: temporarily saved forms are deleted
    /// with their photos only after the worker confirms, then the
    /// synchronization starts. Other local work is left alone.
    @MainActor
    func testSynchronizationDeletesTemporarilySavedFormsOnlyAfterConfirmation() async throws {
        let workerID = "TEST_WORKER"
        let repo = InMemoryOfflineWorkRepository()
        let offlineWorkStore = OfflineWorkStore(repository: repo, workerID: workerID)
        let photoStore = InMemoryPhotoAttachmentStore()

        func defect(_ status: OfflineWorkStatus) -> OfflineWorkItem {
            OfflineWorkItem(
                id: UUID(), workerID: workerID, type: .defect, status: status,
                payload: .defect(DefectDraftPayload(
                    technicalObject: .init(kind: .equipment, objectID: "EQ-1"),
                    technicalObjectName: "Door",
                    dinGroup: nil,
                    priority: .medium,
                    shortText: "Defect",
                    longText: "",
                    attachmentIDs: []
                )),
                createdAt: Date(), updatedAt: Date(), syncError: nil
            )
        }
        let reportedDefect = defect(.pendingSynchronization)
        let draftDefect = defect(.draft)
        try await repo.save(reportedDefect)
        try await repo.save(draftDefect)

        let ladder = MobileLadderDraftPayload()
        let ladderItem = try await offlineWorkStore.saveMobileLadder(payload: ladder, status: .draft)
        let photoID = try await photoStore.saveJPEG(Data([1]))
        let photoCollection = try await offlineWorkStore.savePhotoCollection(
            scope: LocalPhotoScope(workflow: .mobileLadder, ownerID: ladder.localDraftID, rowID: "1"),
            attachments: [LocalPhotoAttachment(localAttachmentID: photoID, capturedAt: Date())]
        )
        XCTAssertEqual(offlineWorkStore.temporarilySavedFormItems.map(\.id), [ladderItem.id])

        let tokenStore = InMemorySAPSyncTokenStore()
        try tokenStore.save(token: "SAVED_TOKEN", for: workerID)
        let mockService = MockTokenRefreshService()
        let viewModel = FacilityDemoViewModel(
            isDemoMode: false,
            offlineWorkStore: offlineWorkStore,
            sapDataStore: SAPDataStore(
                repository: InMemorySAPDataCacheRepository(workerID: workerID),
                refreshService: mockService,
                tokenStore: tokenStore,
                localWorkerID: workerID,
                synchronizationUserID: workerID
            ),
            meterReferenceProvider: DemoMeterReferenceProvider(),
            photoAttachmentStore: photoStore,
            workerDisplayName: "Test User",
            workerRole: .technician
        )

        viewModel.requestSAPRefresh()
        XCTAssertTrue(viewModel.shouldConfirmSynchronization)
        XCTAssertEqual(viewModel.synchronizationDeletionCount, 1)

        viewModel.cancelSynchronization()
        try await Task.sleep(for: .milliseconds(60))
        XCTAssertFalse(viewModel.shouldConfirmSynchronization)
        XCTAssertEqual(mockService.tokenRefreshCallCount, 0)
        XCTAssertNotNil(offlineWorkStore.item(id: ladderItem.id))

        viewModel.requestSAPRefresh()
        viewModel.confirmSynchronization()
        try await Task.sleep(for: .milliseconds(60))

        XCTAssertNil(offlineWorkStore.item(id: ladderItem.id))
        XCTAssertNil(offlineWorkStore.item(id: photoCollection?.id))
        let photoAfterSync = try? await photoStore.loadJPEG(id: photoID)
        XCTAssertNil(photoAfterSync)
        XCTAssertNotNil(offlineWorkStore.item(id: reportedDefect.id))
        XCTAssertNotNil(offlineWorkStore.item(id: draftDefect.id))
        XCTAssertEqual(mockService.tokenRefreshCallCount, 1)
    }

    @MainActor
    func testConfirmedSynchronizationPreservesDraftsAndProceedsWithSync() async throws {
        let workerID = "TEST_WORKER"
        let repo = InMemoryOfflineWorkRepository()
        let offlineWorkStore = OfflineWorkStore(repository: repo, workerID: workerID)
        let draftItem = OfflineWorkItem(
            id: UUID(),
            workerID: workerID,
            type: .defect,
            status: .draft,
            payload: .defect(DefectDraftPayload(
                technicalObject: .init(kind: .equipment, objectID: "EQ-1"),
                technicalObjectName: "Door",
                dinGroup: nil,
                priority: .medium,
                shortText: "Draft Defect",
                longText: "",
                attachmentIDs: []
            )),
            createdAt: Date(),
            updatedAt: Date(),
            syncError: nil
        )
        try await repo.save(draftItem)
        await offlineWorkStore.load()
        XCTAssertEqual(offlineWorkStore.localWorkCount, 1)

        let tokenStore = InMemorySAPSyncTokenStore()
        try tokenStore.save(token: "SAVED_TOKEN", for: workerID)
        let mockService = MockTokenRefreshService()
        let dataStore = SAPDataStore(
            repository: InMemorySAPDataCacheRepository(workerID: workerID),
            refreshService: mockService,
            tokenStore: tokenStore,
            localWorkerID: workerID,
            synchronizationUserID: workerID
        )
        let viewModel = FacilityDemoViewModel(
            isDemoMode: false,
            offlineWorkStore: offlineWorkStore,
            sapDataStore: dataStore,
            meterReferenceProvider: DemoMeterReferenceProvider(),
            photoAttachmentStore: InMemoryPhotoAttachmentStore(),
            workerDisplayName: "Test User",
            workerRole: .technician
        )

        viewModel.confirmSynchronization()
        XCTAssertFalse(viewModel.shouldConfirmSynchronization)

        // Allow async Task (reset and refresh) to complete
        try await Task.sleep(for: .milliseconds(60))

        XCTAssertEqual(offlineWorkStore.localWorkCount, 1)
        // Token sync was invoked
        XCTAssertEqual(mockService.tokenRefreshCallCount, 1)
    }

    @MainActor
    func testDataStoreDoesNotStartSecondTokenRefreshWhileFirstIsInFlight() async throws {
        let workerID = "TEST_WORKER"
        let tokenStore = InMemorySAPSyncTokenStore()
        try tokenStore.save(token: "SAVED_TOKEN", for: workerID)
        let mockService = MockTokenRefreshService()
        mockService.suspendsTokenRefresh = true
        let dataStore = SAPDataStore(
            repository: InMemorySAPDataCacheRepository(workerID: workerID),
            refreshService: mockService,
            tokenStore: tokenStore,
            localWorkerID: workerID,
            synchronizationUserID: workerID
        )

        XCTAssertTrue(dataStore.beginTokenRefresh())
        let firstRefresh = Task { await dataStore.refreshWithSavedToken() }
        try await Task.sleep(for: .milliseconds(20))
        XCTAssertEqual(mockService.tokenRefreshCallCount, 1)

        let concurrentRefreshResult = await dataStore.refreshWithSavedToken()
        XCTAssertFalse(concurrentRefreshResult)
        await dataStore.refresh(sapPassword: "password")
        XCTAssertEqual(mockService.tokenRefreshCallCount, 1)
        XCTAssertEqual(mockService.passwordRefreshCallCount, 0)

        mockService.finishSuspendedTokenRefresh()
        let firstRefreshResult = await firstRefresh.value
        XCTAssertTrue(firstRefreshResult)
        XCTAssertFalse(dataStore.isRefreshing)
    }
}

private final class MockTokenRefreshService: SAPNotificationRefreshService, @unchecked Sendable {
    var shouldSucceedWithToken = true
    var tokenRefreshError: SAPReadError?
    var passwordRefreshError: SAPReadError?
    var passwordFailureStage: SAPReadRefreshStage?
    var returnedTokenOnPasswordSync: String?
    var tokenRefreshCallCount = 0
    var passwordRefreshCallCount = 0
    var suspendsTokenRefresh = false
    private var tokenRefreshContinuation: CheckedContinuation<Void, Never>?

    func refresh(
        sapPassword: String,
        progress: @escaping SAPReadRefreshProgressHandler
    ) async throws -> SAPCachedData {
        passwordRefreshCallCount += 1
        if let passwordFailureStage {
            await progress(passwordFailureStage)
        }
        if let passwordRefreshError {
            throw passwordRefreshError
        }
        return SAPCachedData(
            notifications: [],
            workerProfile: nil,
            briefingPartners: [],
            briefingTemplates: [],
            technicalObjects: [],
            metadata: SAPCacheMetadata(sapWorkerID: "TEST_WORKER", lastSuccessfulRefreshAt: Date())
        )
    }

    func refresh(
        usingToken token: String,
        progress: @escaping SAPReadRefreshProgressHandler
    ) async throws -> SAPCachedData {
        tokenRefreshCallCount += 1
        if suspendsTokenRefresh {
            await withCheckedContinuation { continuation in
                tokenRefreshContinuation = continuation
            }
        }
        if let tokenRefreshError {
            throw tokenRefreshError
        }
        if shouldSucceedWithToken {
            return SAPCachedData(
                notifications: [],
                workerProfile: nil,
                briefingPartners: [],
                briefingTemplates: [],
                technicalObjects: [],
                metadata: SAPCacheMetadata(sapWorkerID: "TEST_WORKER", lastSuccessfulRefreshAt: Date())
            )
        } else {
            throw SAPReadError.tokenInvalidOrExpired
        }
    }

    func finishSuspendedTokenRefresh() {
        tokenRefreshContinuation?.resume()
        tokenRefreshContinuation = nil
    }
}
