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
    func testViewModelSAPRefreshWithPendingDraftsShowsWarningDialog() async throws {
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

        // Request refresh with pending drafts
        viewModel.requestSAPRefresh()

        // Warning dialog must be presented; sync must NOT have started yet
        XCTAssertTrue(viewModel.shouldPresentDraftWarningBeforeSync)
        XCTAssertFalse(viewModel.shouldPresentSAPRefresh)
        XCTAssertFalse(dataStore.isRefreshing)

        // Dismiss warning via cancel
        viewModel.dismissDraftWarning()
        XCTAssertFalse(viewModel.shouldPresentDraftWarningBeforeSync)
        XCTAssertFalse(viewModel.shouldPresentSAPRefresh)
        XCTAssertEqual(offlineWorkStore.localWorkCount, 1)

        // Request again, then choose "Keep & Review Drafts"
        viewModel.requestSAPRefresh()
        XCTAssertTrue(viewModel.shouldPresentDraftWarningBeforeSync)
        viewModel.keepDraftsAndNavigate()
        XCTAssertFalse(viewModel.shouldPresentDraftWarningBeforeSync)
        XCTAssertFalse(viewModel.shouldPresentSAPRefresh)
        XCTAssertEqual(viewModel.selection, .drafts)
        XCTAssertEqual(offlineWorkStore.localWorkCount, 1)
    }

    @MainActor
    func testViewModelConfirmDiscardDraftsAndSyncResetsDraftsAndProceedsWithSync() async throws {
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

        // Request refresh -> shows warning
        viewModel.requestSAPRefresh()
        XCTAssertTrue(viewModel.shouldPresentDraftWarningBeforeSync)

        // Confirm discard and sync
        viewModel.confirmDiscardDraftsAndSync()
        XCTAssertFalse(viewModel.shouldPresentDraftWarningBeforeSync)

        // Allow async Task (reset and refresh) to complete
        try await Task.sleep(for: .milliseconds(60))

        // Drafts should now be discarded
        XCTAssertEqual(offlineWorkStore.localWorkCount, 0)
        // Token sync was invoked
        XCTAssertEqual(mockService.tokenRefreshCallCount, 1)
    }
}

private final class MockTokenRefreshService: SAPNotificationRefreshService, @unchecked Sendable {
    var shouldSucceedWithToken = true
    var returnedTokenOnPasswordSync: String?
    var tokenRefreshCallCount = 0
    var passwordRefreshCallCount = 0

    func refresh(
        sapPassword: String,
        progress: @escaping SAPReadRefreshProgressHandler
    ) async throws -> SAPCachedData {
        passwordRefreshCallCount += 1
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
}
