import Foundation
import XCTest
@testable import mobileFacilityApp

final class MobileLadderTests: XCTestCase {
    func testInspectionPickerUsesVerifiedTFM5ResultAndActionCodes() {
        XCTAssertEqual(MobileLadderInspectionResult.allCases.map(\.code), ["1", "2", "3", "4", "5"])
        XCTAssertEqual(MobileLadderInspectionAction.allCases.map(\.code), ["7", "8", "9"])
    }

    @MainActor
    func testRungCountRetainsDigitsOnly() {
        let model = MobileLadderCreationViewModel(
            provider: DemoMobileLadderCreationProvider(),
            offlineWorkStore: OfflineWorkStore(repository: InMemoryOfflineWorkRepository(), workerID: "demo"),
            isDemo: true,
            item: nil
        )

        model.setRungCount("12 steps-3")

        XCTAssertEqual(model.draft.rungCount, "123")
    }

    @MainActor
    func testProductionCloseQueuesCompleteDraftAndKeepsStableIdentifiers() async throws {
        let repository = InMemoryOfflineWorkRepository()
        let store = OfflineWorkStore(repository: repository, workerID: "S50828")
        let model = MobileLadderCreationViewModel(
            provider: DemoMobileLadderCreationProvider(),
            offlineWorkStore: store,
            isDemo: false,
            item: nil
        )
        await model.load()
        complete(model)

        XCTAssertTrue(model.isReadyToClose)
        let didClose = await model.close()
        XCTAssertTrue(didClose)
        let firstIdentifiers = try XCTUnwrap(model.draft.legacyIdentifiers)
        let saved = try XCTUnwrap(store.mobileLadderItems.first)
        XCTAssertEqual(saved.status, .pendingSynchronization)
        XCTAssertTrue(saved.payload.mobileLadder?.isClosedLocally == true)
        XCTAssertEqual(saved.payload.mobileLadder?.legacyIdentifiers, firstIdentifiers)

        let reopened = MobileLadderCreationViewModel(
            provider: DemoMobileLadderCreationProvider(),
            offlineWorkStore: store,
            isDemo: false,
            item: saved
        )
        await reopened.load()
        XCTAssertTrue(reopened.isReadOnly)
        XCTAssertFalse(reopened.isReadyToClose)
        let didCloseAgain = await reopened.close()
        XCTAssertFalse(didCloseAgain)
        XCTAssertEqual(reopened.draft.legacyIdentifiers, firstIdentifiers)
    }

    @MainActor
    func testDemoCloseLocksLocalLadderWithoutAllocatingSAPIdentifiers() async throws {
        let repository = InMemoryOfflineWorkRepository()
        let store = OfflineWorkStore(repository: repository, workerID: "demo")
        let model = MobileLadderCreationViewModel(
            provider: DemoMobileLadderCreationProvider(),
            offlineWorkStore: store,
            isDemo: true,
            item: nil
        )
        await model.load()
        complete(model)

        let didClose = await model.close()
        XCTAssertTrue(didClose)
        XCTAssertEqual(store.mobileLadderItems.first?.status, .pendingSynchronization)
        XCTAssertTrue(store.mobileLadderItems.first?.payload.mobileLadder?.isClosedLocally == true)
        XCTAssertTrue(model.isReadOnly)
        XCTAssertNil(store.mobileLadderItems.first?.payload.mobileLadder?.legacyIdentifiers)
    }

    @MainActor
    func testTemporarySavePersistsIncompleteDraftAsLocalWork() async throws {
        let store = OfflineWorkStore(repository: InMemoryOfflineWorkRepository(), workerID: "demo")
        let model = MobileLadderCreationViewModel(
            provider: DemoMobileLadderCreationProvider(),
            offlineWorkStore: store,
            isDemo: true,
            item: nil
        )
        await model.load()
        model.draft.designation = "Temporary workshop ladder"

        let didSave = await model.saveTemporarily()
        XCTAssertTrue(didSave)
        let saved = try XCTUnwrap(store.mobileLadderItems.first)
        XCTAssertEqual(saved.status, .draft)
        XCTAssertEqual(saved.payload.mobileLadder?.designation, "Temporary workshop ladder")
        XCTAssertNil(model.feedback)
    }

    @MainActor
    func testCloseValidationRequiresPositiveRungCountAndEveryInspectionResult() async {
        let store = OfflineWorkStore(repository: InMemoryOfflineWorkRepository(), workerID: "demo")
        let model = MobileLadderCreationViewModel(
            provider: DemoMobileLadderCreationProvider(),
            offlineWorkStore: store,
            isDemo: true,
            item: nil
        )
        await model.load()
        complete(model)
        XCTAssertNotNil(model.draft.context)

        model.draft.rungCount = "0"
        XCTAssertFalse(model.isReadyToClose)

        model.draft.rungCount = "8"
        model.draft.inspectionItems[0].result = nil
        XCTAssertFalse(model.isReadyToClose)

        model.draft.inspectionItems[0].result = .okay
        XCTAssertTrue(model.isReadyToClose)
    }

    @MainActor
    func testSavingProposalAddsItToCatalogAndSelectsIt() async {
        let store = OfflineWorkStore(repository: InMemoryOfflineWorkRepository(), workerID: "demo")
        let model = MobileLadderCreationViewModel(
            provider: DemoMobileLadderCreationProvider(),
            offlineWorkStore: store,
            isDemo: true,
            item: nil
        )
        await model.load()

        XCTAssertTrue(model.saveProposal("Custom Ladder Material", for: .material))
        XCTAssertEqual(model.draft.material, "Custom Ladder Material")
        XCTAssertTrue(model.catalog.options(for: .material).contains("Custom Ladder Material"))
        XCTAssertEqual(model.feedback?.id, "proposalSaved")
    }

    @MainActor
    func testPhotoCapacityIsTwentyAcrossAllInspectionItems() async {
        let store = OfflineWorkStore(repository: InMemoryOfflineWorkRepository(), workerID: "demo")
        let model = MobileLadderCreationViewModel(
            provider: DemoMobileLadderCreationProvider(),
            offlineWorkStore: store,
            isDemo: true,
            item: nil
        )
        await model.load()
        complete(model)
        let first = model.draft.inspectionItems[0]
        let second = model.draft.inspectionItems[1]
        model.draft.photoAttachments = (0..<12).map { index in
            MobileLadderPhotoAttachment(
                localAttachmentID: "photo-\(index)",
                inspectionItemID: second.id,
                sapElementID: second.commentElementID,
                capturedAt: .now,
                sapDocumentID: "document-\(index)"
            )
        }

        XCTAssertEqual(model.remainingPhotoCapacity(excluding: first.id), 8)
        XCTAssertEqual(model.remainingPhotoCapacity(excluding: second.id), 20)

        model.draft.photoAttachments += (12..<21).map { index in
            MobileLadderPhotoAttachment(
                localAttachmentID: "photo-\(index)",
                inspectionItemID: first.id,
                sapElementID: first.commentElementID,
                capturedAt: .now,
                sapDocumentID: "document-\(index)"
            )
        }
        XCTAssertFalse(model.isReadyToClose)
    }

    @MainActor
    func testConfirmingDisassembledClearsInspectionWorkAndLocalPhotos() async throws {
        let photoStore = InMemoryPhotoAttachmentStore()
        let store = OfflineWorkStore(repository: InMemoryOfflineWorkRepository(), workerID: "demo")
        let model = MobileLadderCreationViewModel(
            provider: DemoMobileLadderCreationProvider(),
            offlineWorkStore: store,
            photoStore: photoStore,
            isDemo: true,
            item: nil
        )
        await model.load()
        complete(model)

        let first = try XCTUnwrap(model.draft.inspectionItems.first)
        model.draft.inspectionItems[0].action = .repair
        model.draft.inspectionItems[0].comment = "Rails need attention"
        let localPhotoID = try await photoStore.saveJPEG(Data([0xFF, 0xD8, 0xFF, 0xD9]))
        let scope = model.photoScope(for: first)
        _ = try await store.savePhotoCollection(
            scope: scope,
            attachments: [LocalPhotoAttachment(localAttachmentID: localPhotoID, capturedAt: .now)]
        )
        model.refreshPhotos()
        XCTAssertEqual(model.draft.photoAttachments.count, 1)

        let didConfirm = await model.confirmDisassembledChange(to: true)

        XCTAssertTrue(didConfirm)
        XCTAssertTrue(model.draft.isDisassembled)
        XCTAssertTrue(model.draft.inspectionItems.allSatisfy {
            $0.result == nil && $0.action == nil && $0.comment.isEmpty
        })
        XCTAssertTrue(model.draft.photoAttachments.isEmpty)
        XCTAssertNil(store.photoCollection(for: scope))
        XCTAssertTrue(model.isReadyToClose)
        do {
            _ = try await photoStore.loadJPEG(id: localPhotoID)
            XCTFail("The confirmed status transition must remove the local photo file")
        } catch { }
    }

    func testOfflineRepositoryRoundTripsVersionedMobileLadderPayload() async throws {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
            .appendingPathComponent("offline.sqlite")
        defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }
        let repository = try SQLiteOfflineWorkRepository(databaseURL: url)
        var payload = MobileLadderDraftPayload(localDraftID: "draft-1")
        payload.designation = "Warehouse ladder"
        let item = OfflineWorkItem(
            id: UUID(), workerID: "S50828", type: .mobileLadder, status: .draft,
            payload: .mobileLadder(payload), createdAt: .now, updatedAt: .now, syncError: nil
        )

        try await repository.save(item)
        let storedItems = try await repository.loadWork(for: "S50828")
        let restored = try XCTUnwrap(storedItems.first)
        XCTAssertEqual(restored.payload.mobileLadder?.version, MobileLadderDraftPayload.currentVersion)
        XCTAssertEqual(restored.payload.mobileLadder?.designation, "Warehouse ladder")
    }

    func testOfflineRepositoryKeepsHistoricalSubdistributionJSONReadable() async throws {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
            .appendingPathComponent("offline.sqlite")
        defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }
        let repository = try SQLiteOfflineWorkRepository(databaseURL: url)
        let rawJSON = Data(#"{"version":1,"localDraftID":"legacy-tfm7","characteristicValues":{"TFMUNTERVERT_BEZUNTERVERT":"Distribution board"},"performedOn":"2026-09-15T08:00:00Z","isOutOfOperation":false,"isClosedLocally":true,"inspectionItems":[],"photoAttachments":[]}"#.utf8)
        let item = OfflineWorkItem(
            id: UUID(), workerID: "S50828", type: .subdistribution,
            status: .pendingSynchronization,
            payload: .subdistribution(.init(jsonData: rawJSON)),
            createdAt: .now, updatedAt: .now, syncError: nil
        )

        try await repository.save(item)
        let loadedItems = try await repository.loadWork(for: "S50828")
        let restored = try XCTUnwrap(loadedItems.first)

        XCTAssertEqual(restored.type, .subdistribution)
        XCTAssertEqual(restored.payload.subdistribution?.jsonData, rawJSON)
    }

    func testSAPBuilderCreatesTFM5HeaderValuesAndEquipmentMasterRow() async throws {
        let creationData = try await DemoMobileLadderCreationProvider()
            .loadMobileLadderCreationData(for: "S50828")
        var draft = MobileLadderDraftPayload(localDraftID: "draft-2")
        draft.context = try XCTUnwrap(creationData.contexts.first)
        draft.material = "Aluminium"
        draft.constructionType = "Stehleiter"
        draft.manufacturer = "ZARGES"
        draft.rungCount = "8"
        draft.clientCompany = "Westnetz GmbH"
        draft.room = "Workshop"
        draft.designation = "ML-01"
        draft.isDisassembled = true
        draft.disassembledComment = "Removed for repair"
        draft.inspectionItems = draft.context!.legacyContext.template.inspectionItems.enumerated().map {
            var item = MobileLadderInspectionItem(definition: $0.element, number: $0.offset + 1)
            item.result = .okay
            return item
        }
        let firstInspection = try XCTUnwrap(draft.inspectionItems.first)
        draft.photoAttachments = [MobileLadderPhotoAttachment(
            localAttachmentID: "photo-1",
            inspectionItemID: firstInspection.id,
            sapElementID: firstInspection.commentElementID,
            capturedAt: Date(timeIntervalSince1970: 1_700_000_000),
            sapDocumentID: "DOCUMENT-1"
        ), MobileLadderPhotoAttachment(
            localAttachmentID: "status-photo-1",
            inspectionItemID: MobileLadderDraftPayload.disassembledStatusRowID,
            sapElementID: "TFM5-0000-9B",
            capturedAt: Date(timeIntervalSince1970: 1_700_000_000),
            sapDocumentID: "STATUS-DOCUMENT-1"
        )]
        draft.legacyIdentifiers = MobileLadderLegacyIdentifiers(
            notificationNumber: "NEU-12345678", equipmentNumber: "NEU-12345678901234", processNumber: "PROCESS-1"
        )
        let work = OfflineWorkItem(
            id: UUID(), workerID: "S50828", type: .mobileLadder, status: .pendingSynchronization,
            payload: .mobileLadder(draft), createdAt: .now, updatedAt: .now, syncError: nil
        )

        let batch = try SAPMobileLadderUploadBuilder.build(
            workItem: work, draft: draft, syncUserID: "S50828", photoData: [
                "photo-1": Data([0xFF, 0xD8, 0xFF]),
                "status-photo-1": Data([0xFF, 0xD8, 0xFF])
            ],
            now: Date(timeIntervalSince1970: 1_700_000_000)
        )
        let header = try XCTUnwrap(batch.headers.first)
        XCTAssertEqual(header["QMART"], "I1")
        XCTAssertEqual(header["FORMNR"], "TFM5")
        XCTAssertEqual(header["QMNUM"], "NEU-12345678")
        XCTAssertEqual(header["USTXT"], "dem")
        XCTAssertEqual(batch.values.filter { ($0["ELEMENTNR"] ?? nil)?.hasSuffix("-1") == true }.count, 8)
        let disassembledComment = try XCTUnwrap(batch.values.first { $0["ELEMENTNR"] == "TFM5-0000-9B" })
        XCTAssertEqual(disassembledComment["FELDWERT"], "Removed for repair")
        let equipment = try XCTUnwrap(batch.equipment.first)
        XCTAssertEqual(equipment["EQUNR"], "NEU-12345678901234")
        let packed = try XCTUnwrap(equipment["FELDWERT"] ?? nil)
        let equipmentPayload = try XCTUnwrap(SAPLegacyDataExchangeCodec.decodedFeldwertObject(packed))
        XCTAssertEqual(equipmentPayload["EQART_TO"] as? String, "TFMLEITERN")
        let classData = try XCTUnwrap(equipmentPayload["T_CLASS_EQ"] as? [String: Any])
        XCTAssertEqual(classData["KLASSE"] as? String, "TFMMOBLEITER")
        let document = try XCTUnwrap(batch.documents.first)
        XCTAssertEqual(document.metadata["ELEMENTNR"], firstInspection.commentElementID)
        XCTAssertEqual(document.metadata["DMS_CONTENTTYPE"], "D_TFM_Dokumentation")
        XCTAssertEqual(document.metadata["DMS_DOCID"], "TFM001")
        let statusDocument = try XCTUnwrap(batch.documents.first { $0.metadata["DOCID"] == "STATUS-DOCUMENT-1" })
        XCTAssertEqual(statusDocument.metadata["ELEMENTNR"], "TFM5-0000-9B")
    }

    func testSQLiteProviderDecodesAddressTemplateAndValueHelp() async throws {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
            .appendingPathComponent("cache.sqlite")
        defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }
        let repository = try SQLiteSAPDataCacheRepository(databaseURL: url, workerID: "S50828")
        let plan = try SAPLegacyDataExchangeCodec.packedFeldwert(["T_PLPOD": [[
            "USR00": "POSITION", "STEUS": "TFM5", "VORNR": "0010",
            "LTXA1": "Rails", "LTXA2": "Visual check"
        ]]])
        let classData = try SAPLegacyDataExchangeCodec.packedFeldwert([
            "KLART": "002", "KLASSE": "TFMMOBLEITER", "KLAGR": "TFM",
            "T_CHARA": [["ATNAM": "TFMMOBLEITER_WERKSTOFF", "ATBEZ": "Material"]],
            "T_CHARVAL": [["ATNAM": "TFMMOBLEITER_WERKSTOFF", "ATWRT": "AL", "ATWTB": "Aluminium"]]
        ])
        let equipment = try SAPLegacyDataExchangeCodec.packedFeldwert(["EQART_TO": "TFMLEITERN"])
        try await repository.insertLegacyRows([["EQART": "TFMLEITERN", "PLNTY": "A", "PLNNR": "00040015", "IWERK": "1000", "INGRP": "001", "FELDWERT": plan]], into: "FROM_T0267")
        try await repository.insertLegacyRows([["EQART": "TFMLEITERN", "KLART": "002", "CLASS": "TFMMOBLEITER", "FELDWERT": classData]], into: "FROM_T0263")
        try await repository.insertLegacyRows([["LKEY": "EQUIPMENT", "LPAR": "TFMLEITERN", "FELDWERT": equipment]], into: "FROM_T0268")
        try await repository.insertLegacyRows([[
            "MANDT": "100", "STRNO": "DE-ESS-100-01-350", "TPLND": "DE", "TPORT": "ESS",
            "TPWEH": "100", "TPGEB": "01", "TPGSG": "350", "PLTXT": "Building 01",
            "IWERK": "1000", "INGRP": "001", "GEWRK": "FM", "USTXT": "iBet"
        ]], into: "FROM_T0272")

        try await repository.insertLegacyRows([[
            "MANDT": "100", "REQID": "1", "PERSNR": "S50828", "GESELLSCHAFT": "Custom Client Org"
        ]], into: "USER")

        let data = try await repository.loadMobileLadderCreationData(for: "S50828")
        XCTAssertEqual(data.contexts.first?.legacyContext.functionalLocation, "DE-ESS-100-01-350")
        XCTAssertEqual(data.contexts.first?.legacyContext.template.formCode, "TFM5")
        XCTAssertEqual(data.catalog.options(for: .material), ["Aluminium"])
        XCTAssertTrue(data.catalog.options(for: .clientCompany).contains("Custom Client Org"))
    }

    func testCatalogMaterialOptionsFallbackToLegacyReferenceMatchingOlderApp() {
        let catalog = MobileLadderCatalog.empty
        let materialOptions = catalog.options(for: .material)
        let expected = [
            "Pflege durch Admin",
            "nicht bekannt",
            "Aluminium",
            "Edelstahl",
            "Glasfaser",
            "Holz",
            "Kunststoff",
            "Stahl"
        ]
        XCTAssertEqual(materialOptions, expected)
        XCTAssertEqual(catalog.options(for: .constructionType), ["Anlegeleiter", "Stehleiter", "Podestleiter"])
        XCTAssertEqual(catalog.options(for: .manufacturer), ["ZARGES", "HYMER", "KRAUSE"])
        XCTAssertEqual(catalog.options(for: .clientCompany), ["Pflege durch Admin"])
    }

    @MainActor
    private func complete(_ model: MobileLadderCreationViewModel) {
        let business = model.businessEntities[0]
        model.selectBusinessEntity(business)
        model.selectBuilding(model.buildings[0])
        model.selectTrade(model.trades[0])
        model.draft.material = "Aluminium"
        model.draft.constructionType = "Stehleiter"
        model.draft.manufacturer = "ZARGES"
        model.draft.rungCount = "8"
        model.draft.clientCompany = "Westnetz GmbH"
        model.draft.room = "Workshop"
        model.draft.designation = "ML-01"
        model.markEverythingOkay()
    }
}
