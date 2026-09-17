import Foundation
import XCTest
@testable import mobileFacilityApp

final class SubdistributionTests: XCTestCase {
    @MainActor
    func testMasterDataSchemaIsAvailableBeforeAParentIsSelected() async {
        let store = OfflineWorkStore(repository: InMemoryOfflineWorkRepository(), workerID: "demo")
        let model = SubdistributionCreationViewModel(
            provider: DemoSubdistributionCreationProvider(), offlineWorkStore: store, isDemo: true, item: nil
        )

        await model.load()

        XCTAssertFalse(model.isContextSelected)
        XCTAssertEqual(model.masterDataTemplate?.characteristics.count, 2)
        XCTAssertNil(model.template)
    }

    func testDemoPhotoInspectionPointUsesTheSharedResultAndActionFields() async throws {
        let data = try await DemoSubdistributionCreationProvider()
            .loadSubdistributionCreationData(for: "demo")
        let photoInspection = try XCTUnwrap(data.contexts.first?.legacyContext.template.inspectionItems.last)

        XCTAssertEqual(photoInspection.operation, "0030")
        XCTAssertTrue(photoInspection.requiresResult)
        XCTAssertEqual(photoInspection.resultElementID, "TFM7-0030-1")
        XCTAssertEqual(photoInspection.actionElementID, "TFM7-0030-2")
        XCTAssertFalse(photoInspection.resultValues.isEmpty)
        XCTAssertFalse(photoInspection.actionValues.isEmpty)
        XCTAssertTrue(photoInspection.requiresDocumentation)
    }

    @MainActor
    func testTemporarySavePersistsIncompleteDraftAsLocalWork() async throws {
        let store = OfflineWorkStore(repository: InMemoryOfflineWorkRepository(), workerID: "demo")
        let model = SubdistributionCreationViewModel(
            provider: DemoSubdistributionCreationProvider(), offlineWorkStore: store,
            isDemo: true, item: nil
        )
        await model.load()
        model.draft.characteristicValues["TFMUNTERVERT_BEZUNTERVERT"] = "Temporary UV"

        let didSave = await model.saveTemporarily()

        XCTAssertTrue(didSave)
        let saved = try XCTUnwrap(store.subdistributionItems.first)
        XCTAssertEqual(saved.status, .draft)
        XCTAssertEqual(
            saved.payload.subdistribution?.characteristicValues["TFMUNTERVERT_BEZUNTERVERT"],
            "Temporary UV"
        )
        XCTAssertNil(model.feedback)
    }

    @MainActor
    func testPhotoAndCommentAreRequiredBeforeTheNotificationCanClose() async throws {
        let store = OfflineWorkStore(repository: InMemoryOfflineWorkRepository(), workerID: "demo")
        let photoStore = InMemoryPhotoAttachmentStore()
        let model = SubdistributionCreationViewModel(
            provider: DemoSubdistributionCreationProvider(), offlineWorkStore: store,
            photoStore: photoStore, isDemo: true, item: nil
        )
        await model.load()
        complete(model)

        XCTAssertFalse(model.isReadyForCloseAction)

        try await attachRequiredDocumentation(to: model, store: store, photoStore: photoStore)

        XCTAssertTrue(model.isReadyForCloseAction)
    }

    @MainActor
    func testCloseActionIsAvailableWhenRequiredInspectionPointsAreComplete() async throws {
        let store = OfflineWorkStore(repository: InMemoryOfflineWorkRepository(), workerID: "demo")
        let photoStore = InMemoryPhotoAttachmentStore()
        let model = SubdistributionCreationViewModel(
            provider: DemoSubdistributionCreationProvider(), offlineWorkStore: store,
            photoStore: photoStore, isDemo: true, item: nil
        )
        await model.load()
        complete(model)
        try await attachRequiredDocumentation(to: model, store: store, photoStore: photoStore)
        model.draft.inspectionItems[0].result = "4"

        XCTAssertTrue(model.isReadyForCloseAction)
        XCTAssertFalse(model.isReadyToClose)

        model.selectDefectCloseAction(.close)
        XCTAssertTrue(model.isReadyToClose)
    }

    @MainActor
    func testOutOfOperationClearsAnswersAndLocksNormalInspectionRows() async throws {
        let photoStore = InMemoryPhotoAttachmentStore()
        let store = OfflineWorkStore(repository: InMemoryOfflineWorkRepository(), workerID: "demo")
        let model = SubdistributionCreationViewModel(
            provider: DemoSubdistributionCreationProvider(), offlineWorkStore: store,
            photoStore: photoStore, isDemo: true, item: nil
        )
        await model.load()
        complete(model)
        model.draft.inspectionItems[0].action = "7"
        model.draft.inspectionItems[0].comment = "Needs repair"
        let first = try XCTUnwrap(model.draft.inspectionItems.first)
        let photoID = try await photoStore.saveJPEG(Data([0xFF, 0xD8, 0xFF, 0xD9]))
        let scope = model.photoScope(for: first)
        _ = try await store.savePhotoCollection(
            scope: scope, attachments: [.init(localAttachmentID: photoID, capturedAt: .now)]
        )
        model.refreshPhotos()
        XCTAssertEqual(model.totalPhotoCount, 1)

        let didChange = await model.confirmOutOfOperationChange(to: true)
        XCTAssertTrue(didChange)
        XCTAssertTrue(model.draft.isOutOfOperation)
        XCTAssertEqual(model.draft.defectCloseAction, .leaveOpen)
        XCTAssertTrue(model.draft.inspectionItems.allSatisfy {
            $0.result == nil && $0.action == nil && $0.comment.isEmpty
        })
        XCTAssertTrue(model.draft.photoAttachments.isEmpty)
        XCTAssertNil(store.photoCollection(for: scope))
        do {
            _ = try await photoStore.loadJPEG(id: photoID)
            XCTFail("aBet must remove ordinary inspection JPEG evidence")
        } catch { }
        XCTAssertTrue(model.isReadyToClose)
    }

    @MainActor
    func testOutOfOperationKeepsItsOwnDocumentationSeparateFromInspectionRows() async throws {
        let photoStore = InMemoryPhotoAttachmentStore()
        let store = OfflineWorkStore(repository: InMemoryOfflineWorkRepository(), workerID: "demo")
        let model = SubdistributionCreationViewModel(
            provider: DemoSubdistributionCreationProvider(), offlineWorkStore: store,
            photoStore: photoStore, isDemo: true, item: nil
        )
        await model.load()
        complete(model)
        let didMarkOutOfOperation = await model.confirmOutOfOperationChange(to: true)
        XCTAssertTrue(didMarkOutOfOperation)

        model.draft.outOfOperationComment = "Locked pending repair"
        let photoID = try await photoStore.saveJPEG(Data([0xFF, 0xD8, 0xFF, 0xD9]))
        let scope = model.outOfOperationPhotoScope()
        _ = try await store.savePhotoCollection(
            scope: scope, attachments: [.init(localAttachmentID: photoID, capturedAt: .now)]
        )
        model.refreshPhotos()

        let attachment = try XCTUnwrap(model.draft.photoAttachments.first)
        XCTAssertEqual(attachment.inspectionItemID, SubdistributionDraftPayload.statusRowID)
        XCTAssertEqual(attachment.sapElementID, SubdistributionDraftPayload.outOfOperationCommentElementID)
        XCTAssertEqual(model.photoCount(for: SubdistributionDraftPayload.statusRowID), 1)
        XCTAssertEqual(model.draft.outOfOperationComment, "Locked pending repair")

        let didReturnToOperation = await model.confirmOutOfOperationChange(to: false)
        XCTAssertTrue(didReturnToOperation)
        XCTAssertFalse(model.draft.isOutOfOperation)
        XCTAssertNil(model.draft.outOfOperationComment)
        XCTAssertTrue(model.draft.photoAttachments.isEmpty)
        XCTAssertNil(store.photoCollection(for: scope))
        do {
            _ = try await photoStore.loadJPEG(id: photoID)
            XCTFail("Status JPEG must not remain after returning to iBet")
        } catch { }
    }

    @MainActor
    func testPhotoLimitExcludesPDFReport() async throws {
        let store = OfflineWorkStore(repository: InMemoryOfflineWorkRepository(), workerID: "demo")
        let model = SubdistributionCreationViewModel(
            provider: DemoSubdistributionCreationProvider(), offlineWorkStore: store, isDemo: true, item: nil
        )
        await model.load()
        complete(model)
        let documentationIndex = try XCTUnwrap(model.draft.inspectionItems.firstIndex(where: \.requiresDocumentation))
        let row = model.draft.inspectionItems[documentationIndex]
        model.draft.inspectionItems[documentationIndex].comment = "System photo recorded"
        model.draft.photoAttachments = (0..<20).map { index in
            .init(localAttachmentID: "photo-\(index)", inspectionItemID: row.id, sapElementID: row.commentElementID,
                  capturedAt: .now, sapDocumentID: "document-\(index)")
        }
        model.draft.reportPDF = Data("%PDF".utf8)
        XCTAssertEqual(model.remainingPhotoCapacity(excluding: row.id), 20)
        XCTAssertTrue(model.isReadyToClose)
        model.draft.photoAttachments.append(.init(
            localAttachmentID: "overflow", inspectionItemID: row.id, sapElementID: row.commentElementID,
            capturedAt: .now, sapDocumentID: "overflow"
        ))
        XCTAssertFalse(model.isReadyToClose)
    }

    @MainActor
    func testProductionCloseCreatesStableIdentifiersAndReport() async throws {
        let store = OfflineWorkStore(repository: InMemoryOfflineWorkRepository(), workerID: "S50828")
        let photoStore = InMemoryPhotoAttachmentStore()
        let model = SubdistributionCreationViewModel(
            provider: DemoSubdistributionCreationProvider(), offlineWorkStore: store,
            photoStore: photoStore, isDemo: false, item: nil
        )
        await model.load()
        complete(model)
        try await attachRequiredDocumentation(to: model, store: store, photoStore: photoStore)

        let didClose = await model.close()
        XCTAssertTrue(didClose)
        let identifiers = try XCTUnwrap(model.draft.legacyIdentifiers)
        let report = try XCTUnwrap(model.draft.reportPDF)
        XCTAssertTrue(report.starts(with: Data("%PDF".utf8)))
        XCTAssertNotNil(model.draft.pdfDocumentID)
        let saved = try XCTUnwrap(store.subdistributionItems.first)
        XCTAssertEqual(saved.status, .pendingSynchronization)
        XCTAssertTrue(model.isReadOnly)
        XCTAssertEqual(saved.payload.subdistribution?.legacyIdentifiers, identifiers)
    }

    func testTFM7OutgoingRowsContainPDFCharacteristicsAndOutOfOperationStatus() async throws {
        let data = try await DemoSubdistributionCreationProvider().loadSubdistributionCreationData(for: "S50828")
        var draft = SubdistributionDraftPayload(localDraftID: "sub-1", now: Date(timeIntervalSince1970: 1_700_000_000))
        draft.context = try XCTUnwrap(data.contexts.first)
        draft.characteristicValues = [
            "TFMSCHUTZSCH_ANZAHL_RCD": "4",
            "TFMUNTERVERT_BEZUNTERVERT": "UV-01"
        ]
        draft.isOutOfOperation = true
        draft.outOfOperationComment = "Locked pending repair"
        draft.defectCloseAction = .leaveOpen
        draft.inspectionItems = draft.context!.legacyContext.template.inspectionItems.enumerated().map {
            SubdistributionInspectionItem(definition: $0.element, number: $0.offset + 1)
        }
        draft.legacyIdentifiers = .init(
            notificationNumber: "NEU-12345678", equipmentNumber: "NEU-12345678901234", processNumber: "PROCESS-1"
        )
        draft.reportPDF = Data("%PDF-1.4 test".utf8)
        draft.pdfDocumentID = "PDF-1"
        draft.photoAttachments = [.init(
            localAttachmentID: "status-photo",
            inspectionItemID: SubdistributionDraftPayload.statusRowID,
            sapElementID: SubdistributionDraftPayload.outOfOperationCommentElementID,
            capturedAt: Date(timeIntervalSince1970: 1_700_000_000),
            sapDocumentID: "STATUS-PHOTO-1"
        )]
        draft.isClosedLocally = true
        let work = OfflineWorkItem(
            id: UUID(), workerID: "S50828", type: .subdistribution, status: .pendingSynchronization,
            payload: .subdistribution(draft), createdAt: .now, updatedAt: .now, syncError: nil
        )

        let batch = try SAPSubdistributionUploadBuilder.build(
            workItem: work,
            draft: draft,
            syncUserID: "S50828",
            photoData: ["status-photo": Data([0xFF, 0xD8, 0xFF, 0xD9])],
            now: Date(timeIntervalSince1970: 1_700_000_000)
        )
        let header = try XCTUnwrap(batch.headers.first)
        XCTAssertEqual(header["QMART"], "I1")
        XCTAssertEqual(header["FORMNR"], "TFM7")
        XCTAssertEqual(header["STTXT"], "MIAR")
        XCTAssertEqual(header["USTXT"], "aBet Mnot")
        XCTAssertEqual(batch.values.first { $0["ELEMENTNR"] == "TFMSCHUTZSCH_ANZAHL_RCD" }?["FELDWERT"], "4")
        XCTAssertEqual(batch.values.first { $0["ELEMENTNR"] == "TFM7-0000-1" }?["FELDWERT"], "aBet")
        XCTAssertEqual(
            batch.values.first { $0["ELEMENTNR"] == SubdistributionDraftPayload.outOfOperationCommentElementID }?["FELDWERT"],
            "Locked pending repair"
        )
        let statusPhoto = try XCTUnwrap(batch.documents.first { $0.metadata["DOCID"] == "STATUS-PHOTO-1" })
        XCTAssertEqual(statusPhoto.metadata["ELEMENTNR"], SubdistributionDraftPayload.outOfOperationCommentElementID)
        XCTAssertEqual(statusPhoto.metadata["DOC_MIMETYPE"], "image/jpeg")
        let pdf = try XCTUnwrap(batch.documents.first { $0.metadata["DOCID"] == "PDF-1" })
        XCTAssertEqual(pdf.metadata["ELEMENTNR"], "TFM7-pdf")
        XCTAssertEqual(pdf.metadata["DOC_MIMETYPE"], "application/pdf")
        XCTAssertEqual(pdf.metadata["DMS_CONTENTTYPE"], "D_TFM_Dokumentation")
        let equipment = try XCTUnwrap(batch.equipment.first)
        let packed = try XCTUnwrap(equipment["FELDWERT"] ?? nil)
        let payload = try XCTUnwrap(SAPLegacyDataExchangeCodec.decodedFeldwertObject(packed))
        XCTAssertEqual(payload["EQART_TO"] as? String, "TFMNSPV")
        XCTAssertEqual(payload["ANW_STATUS"] as? String, "aBet")
        XCTAssertEqual(payload["SYS_STATUS"] as? String, "INAK")
    }

    func testDefectMayBeClosedWithLegacyMMABAndMnot() async throws {
        let data = try await DemoSubdistributionCreationProvider().loadSubdistributionCreationData(for: "S50828")
        var draft = SubdistributionDraftPayload(localDraftID: "sub-defect")
        draft.context = try XCTUnwrap(data.contexts.first)
        draft.characteristicValues = ["TFMSCHUTZSCH_ANZAHL_RCD": "4", "TFMUNTERVERT_BEZUNTERVERT": "UV-01"]
        draft.inspectionItems = draft.context!.legacyContext.template.inspectionItems.enumerated().map {
            var item = SubdistributionInspectionItem(definition: $0.element, number: $0.offset + 1)
            if item.requiresResult { item.result = item.id == "0010" ? "4" : "1" }
            return item
        }
        let documentationIndex = try XCTUnwrap(draft.inspectionItems.firstIndex(where: \.requiresDocumentation))
        let documentationItem = draft.inspectionItems[documentationIndex]
        draft.inspectionItems[documentationIndex].comment = "System photo recorded"
        draft.photoAttachments = [.init(
            localAttachmentID: "system-photo", inspectionItemID: documentationItem.id,
            sapElementID: documentationItem.commentElementID, capturedAt: .now, sapDocumentID: "SYSTEM-PHOTO"
        )]
        draft.defectCloseAction = .close
        draft.legacyIdentifiers = .init(notificationNumber: "NEU-1", equipmentNumber: "NEU-2", processNumber: "PROCESS-2")
        draft.reportPDF = Data("%PDF".utf8)
        draft.pdfDocumentID = "PDF-2"
        let work = OfflineWorkItem(
            id: UUID(), workerID: "S50828", type: .subdistribution, status: .pendingSynchronization,
            payload: .subdistribution(draft), createdAt: .now, updatedAt: .now, syncError: nil
        )

        let batch = try SAPSubdistributionUploadBuilder.build(
            workItem: work, draft: draft, syncUserID: "S50828",
            photoData: ["system-photo": Data([0xFF, 0xD8, 0xFF, 0xD9])]
        )
        let header = try XCTUnwrap(batch.headers.first)
        XCTAssertEqual(header["STTXT"], "MMAB")
        XCTAssertEqual(header["USTXT"], "iBet Mnot")
    }

    func testTFM7UploadRejectsMissingPhotoOrCommentForDocumentationPoint() async throws {
        let data = try await DemoSubdistributionCreationProvider().loadSubdistributionCreationData(for: "S50828")
        var draft = SubdistributionDraftPayload(localDraftID: "sub-required-documentation")
        draft.context = try XCTUnwrap(data.contexts.first)
        draft.characteristicValues = [
            "TFMSCHUTZSCH_ANZAHL_RCD": "4",
            "TFMUNTERVERT_BEZUNTERVERT": "UV-01"
        ]
        draft.inspectionItems = draft.context!.legacyContext.template.inspectionItems.enumerated().map {
            var item = SubdistributionInspectionItem(definition: $0.element, number: $0.offset + 1)
            if item.requiresResult { item.result = "1" }
            return item
        }
        draft.legacyIdentifiers = .init(notificationNumber: "NEU-1", equipmentNumber: "NEU-2", processNumber: "PROCESS-3")
        draft.reportPDF = Data("%PDF".utf8)
        draft.pdfDocumentID = "PDF-3"
        let work = OfflineWorkItem(
            id: UUID(), workerID: "S50828", type: .subdistribution, status: .pendingSynchronization,
            payload: .subdistribution(draft), createdAt: .now, updatedAt: .now, syncError: nil
        )

        XCTAssertThrowsError(
            try SAPSubdistributionUploadBuilder.build(
                workItem: work, draft: draft, syncUserID: "S50828", photoData: [:]
            )
        )

        let documentationIndex = try XCTUnwrap(draft.inspectionItems.firstIndex(where: \.requiresDocumentation))
        draft.inspectionItems[documentationIndex].comment = "System photo recorded"

        XCTAssertThrowsError(
            try SAPSubdistributionUploadBuilder.build(
                workItem: work, draft: draft, syncUserID: "S50828", photoData: [:]
            )
        )
    }

    func testSQLiteRoundTripsSubdistributionDraftAndPDF() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let url = directory.appendingPathComponent("offline.sqlite")
        defer { try? FileManager.default.removeItem(at: directory) }
        let repository = try SQLiteOfflineWorkRepository(databaseURL: url)
        var draft = SubdistributionDraftPayload(localDraftID: "sub-roundtrip")
        draft.characteristicValues = ["TFMUNTERVERT_BEZUNTERVERT": "UV-01"]
        draft.reportPDF = Data([0x25, 0x50, 0x44, 0x46])
        draft.pdfDocumentID = "PDF-1"
        let item = OfflineWorkItem(
            id: UUID(), workerID: "S50828", type: .subdistribution, status: .draft,
            payload: .subdistribution(draft), createdAt: .now, updatedAt: .now, syncError: nil
        )
        try await repository.save(item)
        let stored = try await repository.loadWork(for: "S50828")
        let restored = try XCTUnwrap(stored.first)
        XCTAssertEqual(restored.payload.subdistribution?.localDraftID, "sub-roundtrip")
        XCTAssertEqual(restored.payload.subdistribution?.reportPDF, draft.reportPDF)
    }

    func testProductionProviderHasNoStaticFallbackWithoutSAPRows() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let url = directory.appendingPathComponent("cache.sqlite")
        defer { try? FileManager.default.removeItem(at: directory) }
        let repository = try SQLiteSAPDataCacheRepository(databaseURL: url, workerID: "S50828")
        let data = try await repository.loadSubdistributionCreationData(for: "S50828")
        XCTAssertEqual(data, .empty)
    }

    func testSQLiteProviderDecodesTFM7AndFiltersInvalidParents() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let url = directory.appendingPathComponent("cache.sqlite")
        defer { try? FileManager.default.removeItem(at: directory) }
        let repository = try SQLiteSAPDataCacheRepository(databaseURL: url, workerID: "S50828")
        let plan = try SAPLegacyDataExchangeCodec.packedFeldwert(["T_PLPOD": [[
            "USR00": "POSITION", "STEUS": "TFM7", "VORNR": "0010", "LTXA1": "Test button",
            "T_PROPS": [
                ["DFVAL": "1;2;", "DFVAL_TXT": "OK;Defect;"],
                ["DFVAL": "7;8;", "DFVAL_TXT": "Repair;Repaired;"]
            ]
        ]]])
        let classData = try SAPLegacyDataExchangeCodec.packedFeldwert([
            "KLART": "002", "KLASSE": "TFMUNTERVERT", "KLAGR": "TFM",
            "T_CHARA": [
                [
                    "POSNR": "1", "ATINN": "20000",
                    "ATNAM": "TFMUNTERVERT_BEZUNTERVERT", "ATBEZ": "Designation",
                    "ATFOR": "CHAR", "ANZST": "40", "ATERF": "X"
                ],
                [
                    // The shape SAP delivers: the value list nested in its
                    // characteristic. `POSNR`, not `ATINN`, sets the order.
                    "POSNR": "2", "ATINN": "10000",
                    "ATNAM": "TFMUNTERVERT_TYP", "ATBEZ": "Type", "ATFOR": "CHAR",
                    "T_CHARVAL": [["ATWRT": "AUFPUTZ", "ATWTB": "Aufputz"]]
                ]
            ],
            "T_CHARVAL": [[
                "ATNAM": "TFMUNTERVERT_BEZUNTERVERT", "ATWRT": "UV-A", "ATWTB": "UV A"
            ]]
        ])
        let equipment = try SAPLegacyDataExchangeCodec.packedFeldwert(["EQART_TO": "TFMNSPV"])
        try await repository.insertLegacyRows([[
            "EQART": "TFMNSPV", "PLNTY": "A", "PLNNR": "TFM7_001", "IWERK": "1000", "INGRP": "001", "FELDWERT": plan
        ]], into: "FROM_T0267")
        try await repository.insertLegacyRows([[
            "EQART": "TFMNSPV", "KLART": "002", "CLASS": "TFMUNTERVERT", "FELDWERT": classData
        ]], into: "FROM_T0263")
        try await repository.insertLegacyRows([[
            "LKEY": "EQUIPMENT", "LPAR": "TFMNSPV", "FELDWERT": equipment
        ]], into: "FROM_T0268")
        try await repository.insertLegacyRows([
            ["MANDT": "100", "STRNO": "DE-ESS-100", "TPLND": "DE", "TPORT": "ESS", "TPWEH": "100", "PLTXT": "Site", "USTXT": "iBet"],
            [
                "MANDT": "100", "STRNO": "DE-ESS-100-01", "TPLND": "DE", "TPORT": "ESS", "TPWEH": "100",
                "TPGEB": "01", "PLTXT": "GB01 Office", "USTXT": "iBet"
            ],
            [
                "MANDT": "100", "STRNO": "DE-ESS-100-01-440", "TPLND": "DE", "TPORT": "ESS",
                "TPWEH": "100", "TPGEB": "01", "TPGSG": "440", "PLTXT": "Distributor NSHV",
                "IWERK": "1000", "INGRP": "001", "GEWRK": "FM", "USTXT": "iBet", "EQART": "TFMNSPV"
            ],
            [
                "MANDT": "100", "STRNO": "DE-ESS-100-01-441", "TPLND": "DE", "TPORT": "ESS",
                "TPWEH": "100", "TPGEB": "01", "TPGSG": "441", "IWERK": "1000", "INGRP": "001",
                "USTXT": "aBet", "EQART": "TFMNSPVER"
            ]
        ], into: "FROM_T0272")

        let data = try await repository.loadSubdistributionCreationData(for: "S50828")
        XCTAssertEqual(data.contexts.count, 1)
        let context = try XCTUnwrap(data.contexts.first)
        XCTAssertEqual(context.legacyContext.parentEquipmentType, "TFMNSPV")
        XCTAssertEqual(context.building, "01 · GB01 Office", "the building location's text, not the distributor's")
        XCTAssertEqual(context.legacyContext.template.planNumber, "TFM7_001")
        XCTAssertEqual(context.legacyContext.template.inspectionItems.first?.resultValues.map(\.value), ["1", "2"])
        let characteristic = try XCTUnwrap(context.legacyContext.template.characteristics.first)
        XCTAssertTrue(characteristic.required)
        XCTAssertEqual(characteristic.maximumLength, 40)
        XCTAssertEqual(characteristic.values.first?.title, "UV A")
        let type = try XCTUnwrap(context.legacyContext.template.characteristics.last)
        XCTAssertEqual(type.name, "TFMUNTERVERT_TYP")
        XCTAssertEqual(type.kind, .choice)
        XCTAssertEqual(type.values.map(\.value), ["AUFPUTZ"])
    }

    func testSQLiteProviderDecodesCurrentSAPTFM7CacheShape() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let url = directory.appendingPathComponent("cache.sqlite")
        defer { try? FileManager.default.removeItem(at: directory) }
        let repository = try SQLiteSAPDataCacheRepository(databaseURL: url, workerID: "S50828")
        let plan = try SAPLegacyDataExchangeCodec.packedFeldwert([
            "EQART": "TFMNSPV", "PLNTY": "A", "PLNNR": "00040430", "PLNAL": "01",
            "T_PLPOD": [
                [
                    "USR00": "POSITION", "STEUS": "TFM7", "VORNR": "0010", "LTXA1": "Test button",
                    "T_PROPS": [
                        ["DFVAL": "1;2;", "DFVAL_TXT": "OK;Defect;"],
                        ["DFVAL": "7;8;", "DFVAL_TXT": "Repair;Repaired;"]
                    ]
                ],
                ["USR00": "FOTO", "STEUS": "TFM7", "VORNR": "0030", "LTXA1": "Photo"]
            ]
        ])
        let classData = try SAPLegacyDataExchangeCodec.packedFeldwert([[
            "EQART": "TFMNSPV", "KLART": "002", "CLASS": "TFMUNTERVERTEILUNG",
            "T_CHARA": [
                ["ATNAM": "TFMUNTERVERT_ANZAHLRCDFI", "ATBEZ": "RCD count", "ATFOR": "NUM", "ANZST": 3, "MSEHI": "ST", "ATERF": "X"],
                ["ATNAM": "TFMUNTERVERT_BEZUNTERVERT", "ATBEZ": "Designation", "ATFOR": "CHAR", "ANZST": 30, "ATERF": "X"]
            ]
        ]])
        let equipment = try SAPLegacyDataExchangeCodec.packedFeldwert(["EQKTX": ""])
        try await repository.insertLegacyRows([[
            "EQART": "TFMNSPV", "PLNTY": "A", "PLNNR": "00040430", "IWERK": "1000", "INGRP": "001", "FELDWERT": plan
        ]], into: "FROM_T0267")
        try await repository.insertLegacyRows([[
            "EQART": "TFMNSPV", "KLART": "002", "CLASS": "TFMUNTERVERTEILUNG", "FELDWERT": classData
        ]], into: "FROM_T0263")
        try await repository.insertLegacyRows([[
            "LKEY": "EQUIPMENT", "LPAR": "EQUIPMENT", "FELDWERT": equipment
        ]], into: "FROM_T0268")
        try await repository.insertLegacyRows([
            ["MANDT": "100", "STRNO": "DE-ESS-100", "TPLND": "DE", "TPORT": "ESS", "TPWEH": "100", "PLTXT": "Site", "USTXT": "iBet"],
            [
                "MANDT": "100", "STRNO": "DE-ESS-100-01", "TPLND": "DE", "TPORT": "ESS", "TPWEH": "100",
                "TPGEB": "01", "PLTXT": "GB01 Office", "USTXT": "iBet"
            ],
            [
                "MANDT": "100", "STRNO": "DE-ESS-100-01-440", "TPLND": "DE", "TPORT": "ESS",
                "TPWEH": "100", "TPGEB": "01", "TPGSG": "440", "PLTXT": "Building 01",
                "IWERK": "1000", "INGRP": "001", "GEWRK": "FM", "USTXT": "iBet", "EQART": "TFMNSPV"
            ]
        ], into: "FROM_T0272")

        let data = try await repository.loadSubdistributionCreationData(for: "S50828")
        let template = try XCTUnwrap(data.contexts.first?.legacyContext.template)
        XCTAssertEqual(template.planNumber, "00040430")
        XCTAssertEqual(template.characteristics.count, 2)
        XCTAssertEqual(template.inspectionItems.count, 2)
        XCTAssertTrue(template.inspectionItems.last?.requiresResult == false)
        XCTAssertTrue(template.inspectionItems.last?.requiresDocumentation == true)
    }

    @MainActor
    private func complete(_ model: SubdistributionCreationViewModel) {
        model.selectBusinessEntity(model.businessEntities[0])
        model.selectBuilding(model.buildings[0])
        model.selectParentLocation(model.parentLocations[0])
        model.draft.characteristicValues["TFMSCHUTZSCH_ANZAHL_RCD"] = "4"
        model.draft.characteristicValues["TFMUNTERVERT_BEZUNTERVERT"] = "UV-01"
        model.markEverythingOkay()
    }

    @MainActor
    private func attachRequiredDocumentation(
        to model: SubdistributionCreationViewModel,
        store: OfflineWorkStore,
        photoStore: InMemoryPhotoAttachmentStore
    ) async throws {
        let index = try XCTUnwrap(model.draft.inspectionItems.firstIndex(where: \.requiresDocumentation))
        let item = model.draft.inspectionItems[index]
        model.draft.inspectionItems[index].comment = "System photo recorded"
        let localAttachmentID = try await photoStore.saveJPEG(Data([0xFF, 0xD8, 0xFF, 0xD9]))
        _ = try await store.savePhotoCollection(
            scope: model.photoScope(for: item),
            attachments: [.init(localAttachmentID: localAttachmentID, capturedAt: .now)]
        )
        model.refreshPhotos()
    }
}
