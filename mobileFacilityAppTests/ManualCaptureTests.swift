import Foundation
import XCTest
@testable import mobileFacilityApp

final class ManualCaptureTests: XCTestCase {
    @MainActor
    func testDecimalParsingAcceptsGermanCommaAndEnglishPoint() {
        XCTAssertEqual(
            MeterReadingViewModel.parseDecimal("12,5", locale: Locale(identifier: "de_DE")),
            Decimal(string: "12.5")
        )
        XCTAssertEqual(
            MeterReadingViewModel.parseDecimal("12.5", locale: Locale(identifier: "en_US")),
            Decimal(string: "12.5")
        )
        XCTAssertNil(MeterReadingViewModel.parseDecimal(""))
    }

    func testMeterReadingInputKeepsAtMostFifteenDigits() {
        XCTAssertEqual(MeterReadingViewModel.sanitizeInput("12345678901234567890"), "123456789012345")
        XCTAssertEqual(MeterReadingViewModel.sanitizeInput("1234567890123,4567"), "1234567890123,45")
        XCTAssertEqual(MeterReadingViewModel.sanitizeInput("12.5a"), "12,5")
    }

    func testMeterReadingInputKeepsAtMostDecimFractionDigits() {
        XCTAssertEqual(MeterReadingViewModel.sanitizeInput("1234,5678", maximumFractionDigits: 2), "1234,56")
        XCTAssertEqual(MeterReadingViewModel.sanitizeInput("1234,5", maximumFractionDigits: 0), "1234")
        XCTAssertEqual(MeterReadingViewModel.sanitizeInput("1234,5678", maximumFractionDigits: nil), "1234,5678")
    }

    @MainActor
    func testMeterReadingAllowsAnyValidValueAndSaves() async {
        let store = OfflineWorkStore(repository: InMemoryOfflineWorkRepository(), workerID: "worker")
        let model = MeterReadingViewModel(provider: DemoMeterReferenceProvider(), offlineWorkStore: store)

        await model.load(itemID: nil)
        let previous = try? XCTUnwrap(model.selectedReference?.previousValue)
        XCTAssertNotNil(previous)

        // Reading can be entered as any valid value (such as 11 or lower than previous)
        model.valueText = "11"
        XCTAssertTrue(model.canSave)

        model.valueText = MeterReadingViewModel.displayString(previous ?? 0)
        XCTAssertTrue(model.canSave)

        model.valueText = MeterReadingViewModel.displayString((previous ?? 0) + 1)
        let saved = await model.save(status: .pendingSynchronization)
        XCTAssertTrue(saved)
        XCTAssertEqual(store.meterReadingItems.count, 1)
        XCTAssertEqual(store.meterReadingItems.first?.status, .pendingSynchronization)
    }

    @MainActor
    func testPendingMeterReadingReopensReadOnly() async throws {
        let store = OfflineWorkStore(repository: InMemoryOfflineWorkRepository(), workerID: "worker")
        let editable = MeterReadingViewModel(provider: DemoMeterReferenceProvider(), offlineWorkStore: store)

        await editable.load(itemID: nil)
        editable.valueText = "123,4"
        let didSave = await editable.save(status: .pendingSynchronization)
        XCTAssertTrue(didSave)
        let savedID = try XCTUnwrap(store.meterReadingItems.first?.id)

        let reopened = MeterReadingViewModel(provider: DemoMeterReferenceProvider(), offlineWorkStore: store)
        await reopened.load(itemID: savedID)

        XCTAssertTrue(reopened.isReadOnly)
        XCTAssertFalse(reopened.canSave)
        reopened.valueText = "999"
        let didAttemptSave = await reopened.save(status: .draft)
        XCTAssertFalse(didAttemptSave)
        XCTAssertEqual(store.meterReadingItems.first?.payload.meterReading?.value, Decimal(string: "123.4"))
    }

    @MainActor
    func testChangingMeterKindLoadsMatchingReferenceAndClearsInput() async {
        let store = OfflineWorkStore(repository: InMemoryOfflineWorkRepository(), workerID: "worker")
        let model = MeterReadingViewModel(provider: DemoMeterReferenceProvider(), offlineWorkStore: store)

        await model.load(itemID: nil)
        model.valueText = "99999"
        model.note = "note"
        await model.selectKind(.water)

        XCTAssertEqual(model.kind, .water)
        XCTAssertEqual(model.references.map(\.kind), [.water])
        XCTAssertEqual(model.valueText, "")
        XCTAssertEqual(model.note, "")
    }

    @MainActor
    func testMeterReadingValueTextParsing() {
        let store = OfflineWorkStore(repository: InMemoryOfflineWorkRepository(), workerID: "worker")
        let model = MeterReadingViewModel(provider: DemoMeterReferenceProvider(), offlineWorkStore: store)

        model.valueText = "12.5"
        XCTAssertEqual(model.parsedValue, Decimal(string: "12.5"))

        model.valueText = "12,5"
        XCTAssertEqual(model.parsedValue, Decimal(string: "12.5"))

        model.valueText = "11"
        XCTAssertEqual(model.parsedValue, Decimal(11))

        // Formats display string with German comma
        XCTAssertEqual(MeterReadingViewModel.displayString(Decimal(string: "12.5")!), "12,5")
        XCTAssertEqual(MeterReadingViewModel.displayString(Decimal(string: "12842.75")!), "12842,75")
    }

    @MainActor
    func testMeterReadingValueTextSanitizesNonNumericInput() {
        let store = OfflineWorkStore(repository: InMemoryOfflineWorkRepository(), workerID: "worker")
        let model = MeterReadingViewModel(provider: DemoMeterReferenceProvider(), offlineWorkStore: store)

        model.valueText = "abc"
        XCTAssertEqual(model.valueText, "")

        model.valueText = "12abc34"
        XCTAssertEqual(model.valueText, "1234")

        model.valueText = "12..5"
        XCTAssertEqual(model.valueText, "12,5")

        model.setValueText("45def.67")
        XCTAssertEqual(model.valueText, "45,67")
        XCTAssertEqual(model.parsedValue, Decimal(string: "45.67"))
    }

    @MainActor
    func testFrontendPreviewShowsMeterFormDataWithoutAllowingSAPClaims() async {
        let store = OfflineWorkStore(repository: InMemoryOfflineWorkRepository(), workerID: "worker")
        let model = MeterReadingViewModel(
            provider: FrontendPreviewMeterReferenceProvider(),
            offlineWorkStore: store
        )

        await model.load(itemID: nil)

        XCTAssertTrue(model.isShowingPreviewData)
        XCTAssertEqual(model.state, .loaded)
        XCTAssertEqual(model.references.map(\.kind), [.electricity])
        XCTAssertNotNil(model.selectedReference)
    }

    @MainActor
    func testDefectRequiresObjectAndTrimmedShortTextAndUpdatesSameDraft() async throws {
        let repository = InMemoryOfflineWorkRepository()
        let store = OfflineWorkStore(repository: repository, workerID: "worker")
        let sapStore = SAPDataStore(
            repository: InMemorySAPDataCacheRepository(seed: TechnicalObjectDemoData.cachedData),
            refreshService: nil,
            localWorkerID: "demo"
        )
        let model = DefectCaptureViewModel(
            sapDataStore: sapStore,
            offlineWorkStore: store,
            photoStore: InMemoryPhotoAttachmentStore()
        )

        await model.load(itemID: nil)
        XCTAssertFalse(model.canSave)
        model.selectedObjectID = try XCTUnwrap(model.objects.first?.id)
        model.shortText = "   "
        XCTAssertFalse(model.canSave)
        model.shortText = "  Door sensor delayed  "

        let savedDraft = await model.save(status: .draft)
        let savedPending = await model.save(status: .pendingSynchronization)
        XCTAssertTrue(savedDraft)
        XCTAssertTrue(savedPending)
        XCTAssertEqual(store.defectItems.count, 1)
        XCTAssertEqual(store.defectItems.first?.payload.defect?.shortText, "Door sensor delayed")
        XCTAssertEqual(store.defectItems.first?.status, .pendingSynchronization)
    }

    @MainActor
    func testDefectDraftIsEditableAndQueuedDefectIsReadOnly() async throws {
        let repository = InMemoryOfflineWorkRepository()
        let store = OfflineWorkStore(repository: repository, workerID: "worker")
        let sapStore = SAPDataStore(
            repository: InMemorySAPDataCacheRepository(seed: TechnicalObjectDemoData.cachedData),
            refreshService: nil,
            localWorkerID: "demo"
        )
        let photoStore = InMemoryPhotoAttachmentStore()
        let model = DefectCaptureViewModel(
            sapDataStore: sapStore,
            offlineWorkStore: store,
            photoStore: photoStore
        )

        // 1. Create a draft defect
        await model.load(itemID: nil)
        XCTAssertFalse(model.isReadOnly)
        model.selectedObjectID = try XCTUnwrap(model.objects.first?.id)
        model.shortText = "Broken light"
        let savedDraft = await model.save(status: .draft)
        XCTAssertTrue(savedDraft)
        let draftID = try XCTUnwrap(model.editingID)
        XCTAssertEqual(store.item(id: draftID)?.status, .draft)

        // 2. Re-load the draft defect: it must be editable
        await model.load(itemID: draftID)
        XCTAssertFalse(model.isReadOnly)
        XCTAssertTrue(model.canSave)
        XCTAssertEqual(model.itemStatus, .draft)
        model.shortText = "Broken light repaired proposal"
        model.priority = .high
        await model.addPhoto(jpegData: Data([0xFF, 0xD8, 0xFF, 0xD9]))
        XCTAssertEqual(model.attachmentIDs.count, 1)

        // 3. Queue locally (waiting for synchronization)
        let queued = await model.save(status: .pendingSynchronization)
        XCTAssertTrue(queued)
        XCTAssertEqual(store.item(id: draftID)?.status, .pendingSynchronization)

        // 4. Re-load the queued defect: it must be read-only
        await model.load(itemID: draftID)
        XCTAssertTrue(model.isReadOnly)
        XCTAssertFalse(model.canSave)
        XCTAssertEqual(model.itemStatus, .pendingSynchronization)
        XCTAssertEqual(model.shortText, "Broken light repaired proposal")
        XCTAssertEqual(model.priority, .high)
        XCTAssertEqual(model.attachmentIDs.count, 1)

        // Adding photos or saving while read-only must be blocked
        await model.addPhoto(jpegData: Data([0xFF, 0xD8, 0xFF, 0xD9]))
        XCTAssertEqual(model.attachmentIDs.count, 1)
        let attemptSave = await model.save(status: .draft)
        XCTAssertFalse(attemptSave)
    }

    @MainActor
    func testDefectSaveFailureIsVisible() async throws {
        let store = OfflineWorkStore(repository: FailingOfflineWorkRepository(), workerID: "worker")
        let sapStore = SAPDataStore(
            repository: InMemorySAPDataCacheRepository(seed: TechnicalObjectDemoData.cachedData),
            refreshService: nil,
            localWorkerID: "demo"
        )
        let model = DefectCaptureViewModel(
            sapDataStore: sapStore,
            offlineWorkStore: store,
            photoStore: InMemoryPhotoAttachmentStore()
        )
        await model.load(itemID: nil)
        model.selectedObjectID = try XCTUnwrap(model.objects.first?.id)
        model.shortText = "Failure"

        let saved = await model.save(status: .draft)
        XCTAssertFalse(saved)
        XCTAssertTrue(model.saveFailed)
    }

    @MainActor
    func testDefectBlocksDuplicateSubmissionWhileSaveIsInFlight() async throws {
        let repository = DelayedOfflineWorkRepository()
        let store = OfflineWorkStore(repository: repository, workerID: "worker")
        let sapStore = SAPDataStore(
            repository: InMemorySAPDataCacheRepository(seed: TechnicalObjectDemoData.cachedData),
            refreshService: nil,
            localWorkerID: "demo"
        )
        let model = DefectCaptureViewModel(
            sapDataStore: sapStore,
            offlineWorkStore: store,
            photoStore: InMemoryPhotoAttachmentStore()
        )
        await model.load(itemID: nil)
        model.selectedObjectID = try XCTUnwrap(model.objects.first?.id)
        model.shortText = "Only once"

        let first = Task { await model.save(status: .pendingSynchronization) }
        while !model.isSaving { await Task.yield() }
        let second = await model.save(status: .pendingSynchronization)
        let firstResult = await first.value
        let saveAttempts = await repository.saveAttemptCount()

        XCTAssertFalse(second)
        XCTAssertTrue(firstResult)
        XCTAssertEqual(saveAttempts, 1)
    }

    @MainActor
    func testDefectCancelRemovesUnconfirmedPhoto() async throws {
        let photoStore = InMemoryPhotoAttachmentStore()
        let store = OfflineWorkStore(repository: InMemoryOfflineWorkRepository(), workerID: "worker")
        let sapStore = SAPDataStore(
            repository: InMemorySAPDataCacheRepository(seed: TechnicalObjectDemoData.cachedData),
            refreshService: nil,
            localWorkerID: "demo"
        )
        let model = DefectCaptureViewModel(
            sapDataStore: sapStore,
            offlineWorkStore: store,
            photoStore: photoStore
        )
        await model.load(itemID: nil)
        await model.addPhoto(jpegData: Data([0xFF, 0xD8, 0xFF, 0xD9]))
        let id = try XCTUnwrap(model.attachmentIDs.first)

        await model.cancel()

        await XCTAssertThrowsErrorAsync { _ = try await photoStore.loadJPEG(id: id) }
    }

    @MainActor
    func testMeterSaveFailureIsVisible() async {
        let store = OfflineWorkStore(repository: FailingOfflineWorkRepository(), workerID: "worker")
        let model = MeterReadingViewModel(provider: DemoMeterReferenceProvider(), offlineWorkStore: store)
        await model.load(itemID: nil)
        model.valueText = MeterReadingViewModel.displayString(model.selectedReference?.previousValue ?? 0)
        let saved = await model.save(status: .draft)

        XCTAssertFalse(saved)
        XCTAssertTrue(model.saveFailed)
    }

    @MainActor
    func testTypedManualItemsAreWorkerIsolatedAndCountedInLocalWork() async throws {
        let repository = InMemoryOfflineWorkRepository()
        let workerA = OfflineWorkStore(repository: repository, workerID: "worker-a")
        let workerB = OfflineWorkStore(repository: repository, workerID: "worker-b")
        let object = TechnicalObjectReference(kind: .functionalLocation, objectID: "FL-1")
        let meter = MeterReference(
            id: "MP-E-1", kind: .electricity, technicalPlaceID: "FL-1",
            technicalPlaceName: "Plant", unit: "kWh", previousValue: 10, previousReadingAt: .now
        )

        _ = try await workerA.saveDefect(
            payload: .init(
                technicalObject: object, technicalObjectName: "Plant", dinGroup: "300",
                priority: .medium, shortText: "Door", longText: "", attachmentIDs: []
            ),
            status: .draft
        )
        _ = try await workerA.saveMeterReading(
            payload: .init(meter: meter, value: 10, note: ""),
            status: .pendingSynchronization
        )
        _ = try await workerB.saveDefect(
            payload: .init(
                technicalObject: object, technicalObjectName: "Plant", dinGroup: nil,
                priority: .low, shortText: "Other worker", longText: "", attachmentIDs: []
            ),
            status: .draft
        )

        await workerA.load()
        await workerB.load()
        XCTAssertEqual(workerA.localWorkCount, 2)
        XCTAssertEqual(workerA.defectItems.compactMap(\.payload.defect?.shortText), ["Door"])
        XCTAssertEqual(workerB.localWorkCount, 1)
    }

    func testSQLiteRoundTripKeepsLegacyAndTypedManualWork() async throws {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
            .appendingPathExtension("sqlite")
        defer { try? FileManager.default.removeItem(at: url) }
        let repository = try SQLiteOfflineWorkRepository(databaseURL: url)
        let now = Date()
        let object = TechnicalObjectReference(kind: .functionalLocation, objectID: "FL-1")
        let legacy = OfflineWorkItem(
            id: UUID(), workerID: "worker", type: .manualCapture, status: .draft,
            payload: .manualCapture(.init(categoryKey: "manual.category.issue", location: "Old", note: "Old")),
            createdAt: now, updatedAt: now, syncError: nil
        )
        let defect = OfflineWorkItem(
            id: UUID(), workerID: "worker", type: .defect, status: .pendingSynchronization,
            payload: .defect(.init(
                technicalObject: object, technicalObjectName: "Plant", dinGroup: "420",
                priority: .medium, shortText: "Leak", longText: "", attachmentIDs: []
            )),
            createdAt: now, updatedAt: now, syncError: nil
        )

        try await repository.save(legacy)
        try await repository.save(defect)
        let loaded = try await repository.loadWork(for: "worker")

        XCTAssertEqual(Set(loaded.map(\.type)), Set([.manualCapture, .defect]))
    }

    func testFilePhotoStorePersistsDeletesAndResetsJPEGs() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = try FilePhotoAttachmentStore(directory: directory)
        let data = Data([0xFF, 0xD8, 0xFF, 0xD9])

        let first = try await store.saveJPEG(data)
        let loaded = try await store.loadJPEG(id: first)
        XCTAssertEqual(loaded, data)
        try await store.delete(id: first)
        await XCTAssertThrowsErrorAsync { _ = try await store.loadJPEG(id: first) }

        let second = try await store.saveJPEG(data)
        try await store.reset()
        await XCTAssertThrowsErrorAsync { _ = try await store.loadJPEG(id: second) }
    }
}

private struct FailingOfflineWorkRepository: OfflineWorkRepository {
    func loadWork(for workerID: String) async throws -> [OfflineWorkItem] { [] }
    func save(_ item: OfflineWorkItem) async throws { throw OfflineWorkRepositoryError.unavailable }
    func resetWork(for workerID: String) async throws { throw OfflineWorkRepositoryError.unavailable }
}

private actor DelayedOfflineWorkRepository: OfflineWorkRepository {
    private var items: [UUID: OfflineWorkItem] = [:]
    private var attempts = 0

    func loadWork(for workerID: String) async throws -> [OfflineWorkItem] {
        items.values.filter { $0.workerID == workerID }
    }

    func save(_ item: OfflineWorkItem) async throws {
        attempts += 1
        try await Task.sleep(for: .milliseconds(100))
        items[item.id] = item
    }

    func resetWork(for workerID: String) async throws {
        items = items.filter { $0.value.workerID != workerID }
    }

    func saveAttemptCount() -> Int { attempts }
}

private func XCTAssertThrowsErrorAsync(
    _ expression: () async throws -> Void,
    file: StaticString = #filePath,
    line: UInt = #line
) async {
    do {
        try await expression()
        XCTFail("Expected error", file: file, line: line)
    } catch {}
}
