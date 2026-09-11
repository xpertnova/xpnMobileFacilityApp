import Foundation
import XCTest
@testable import mobileFacilityApp

final class NotificationPhotoUploadTests: XCTestCase {
    @MainActor
    func testReviewPhotosPersistReopenRespectLimitAndBecomeReadOnlyOnClosure() async throws {
        let source = try makeSummary(control: "TFM1", cadence: "", category: "I002")
        let detail = SAPNotificationDetail(summary: source)
        let item = try XCTUnwrap(detail.inspectionItems.first)
        let repository = InMemoryOfflineWorkRepository()
        let workStore = OfflineWorkStore(repository: repository, workerID: "S50828")
        let photoStore = InMemoryPhotoAttachmentStore()
        let model = NotificationReviewViewModel(
            detail: detail, offlineWorkStore: workStore, photoStore: photoStore
        )
        await model.load()
        model.results[item.id] = .no

        let jpeg = Data([0xFF, 0xD8, 0x01, 0x02, 0xFF, 0xD9])
        for _ in 0...NotificationReviewViewModel.maximumPhotoCount {
            await model.addPhoto(jpegData: jpeg, to: item)
        }
        XCTAssertEqual(model.photoAttachments.count, 20)
        XCTAssertEqual(workStore.savedNotificationItems.first?.payload.notificationReview?.photoAttachments.count, 20)
        XCTAssertTrue(workStore.savedNotificationItems.first?.payload.notificationReview?.results.isEmpty == true)
        if case .photoLimitReached? = model.feedback { } else {
            XCTFail("Expected the Cordova-compatible 20-photo limit")
        }

        await model.save(closed: false)
        XCTAssertEqual(workStore.savedNotificationItems.first?.status, .draft)

        let reopened = NotificationReviewViewModel(
            detail: detail, offlineWorkStore: workStore, photoStore: photoStore
        )
        await reopened.load()
        XCTAssertEqual(reopened.photoAttachments.count, 20)
        XCTAssertEqual(reopened.photoData.count, 20)
        XCTAssertEqual(reopened.results[item.id], .no)

        await reopened.save(closed: true)
        XCTAssertTrue(reopened.isClosedLocally)
        XCTAssertEqual(workStore.savedNotificationItems.first?.status, .pendingSynchronization)
        let attachment = try XCTUnwrap(reopened.photoAttachments.first)
        await reopened.removePhoto(attachment)
        XCTAssertEqual(reopened.photoAttachments.count, 20)
    }

    @MainActor
    func testLocalPhotoCollectionsPersistImmediatelyAndRemainScopeIsolated() async throws {
        let repository = InMemoryOfflineWorkRepository()
        let workStore = OfflineWorkStore(repository: repository, workerID: "S50828")
        let photoStore = InMemoryPhotoAttachmentStore()
        let firstScope = LocalPhotoScope(
            workflow: .defect,
            ownerID: "draft-1",
            displayTitle: "Photos",
            displaySubtitle: "Pump"
        )
        let secondScope = LocalPhotoScope(
            workflow: .defect,
            ownerID: "draft-2",
            displayTitle: "Photos",
            displaySubtitle: "Door"
        )
        let model = LocalPhotoCollectionViewModel(
            scope: firstScope,
            offlineWorkStore: workStore,
            photoStore: photoStore
        )
        await model.load()
        await model.addPhoto(jpegData: Data([0xFF, 0xD8, 0xFF, 0xD9]))

        XCTAssertEqual(workStore.photoCollection(for: firstScope)?.payload.photoCollection?.attachments.count, 1)
        XCTAssertNil(workStore.photoCollection(for: secondScope))

        let reopened = LocalPhotoCollectionViewModel(
            scope: firstScope,
            offlineWorkStore: workStore,
            photoStore: photoStore
        )
        await reopened.load()
        XCTAssertEqual(reopened.entries.count, 1)
        XCTAssertEqual(reopened.photoData.count, 1)

        await reopened.removePhoto(id: try XCTUnwrap(reopened.entries.first?.id))
        XCTAssertNil(workStore.photoCollection(for: firstScope))
    }

    func testLegacyInspectionIDsKeepCadenceOffCommentAndPhotoElement() throws {
        let source = try makeSummary(control: "TFM3", cadence: "1M", category: "I006")
        let detail = SAPNotificationDetail(summary: source)

        XCTAssertEqual(detail.inspectionItems.count, 1)
        XCTAssertEqual(detail.inspectionItems[0].resultElementID, "TFM3-0010-1-M")
        XCTAssertEqual(detail.inspectionItems[0].commentElementID, "TFM3-0010-9B")
    }

    func testBuilderCreatesExactPhotoMetadataAndRawBase64Input() throws {
        let source = try makeSummary(control: "TFM3", cadence: "1M", category: "I006")
        let detail = SAPNotificationDetail(summary: source)
        let item = try XCTUnwrap(detail.inspectionItems.first)
        let capturedAt = Date(timeIntervalSince1970: 1_725_186_896.789)
        let jpeg = Data([0xFF, 0xD8, 0x01, 0x02, 0xFF, 0xD9])
        let attachment = NotificationPhotoAttachment(
            localAttachmentID: "local-photo", checklistItemID: item.id,
            sapElementID: item.commentElementID, capturedAt: capturedAt,
            sapDocumentID: "STABLE-DOC-ID"
        )
        let review = NotificationReviewDraftPayload(
            notificationID: source.id, performedOn: capturedAt,
            results: [item.id: .yes], comments: [item.id: "Broken"],
            photoAttachments: [attachment], isClosedLocally: true,
            notificationSnapshot: OfflineNotificationSnapshot(detail: detail),
            outgoingProcessID: "STABLE-PROCESS-ID"
        )
        let work = OfflineWorkItem(
            id: UUID(), workerID: "S50828", type: .notificationReview,
            status: .pendingSynchronization, payload: .notificationReview(review),
            createdAt: capturedAt, updatedAt: capturedAt, syncError: nil
        )

        let batch = try SAPNotificationReviewUploadBuilder.build(
            workItem: work, source: source, syncUserID: "s50828",
            photoData: [attachment.localAttachmentID: jpeg], now: capturedAt
        )

        XCTAssertEqual(batch.headers.count, 1)
        XCTAssertEqual(batch.headers[0]["VORGANGSNR"]!, "STABLE-PROCESS-ID")
        XCTAssertEqual(batch.headers[0]["STATUSNR"]!, "2")
        XCTAssertEqual(batch.values.count, 4)
        XCTAssertEqual(batch.documents.count, 1)
        let metadata = batch.documents[0].metadata
        XCTAssertEqual(metadata["DOCID"], "STABLE-DOC-ID")
        XCTAssertEqual(metadata["MANDT"], "100")
        XCTAssertEqual(metadata["ELEMENTNR"], "TFM3-0010-9B")
        XCTAssertEqual(metadata["DOC_TYPE"], "JPG")
        XCTAssertEqual(metadata["DOC_MIMETYPE"], "image/jpeg")
        XCTAssertEqual(metadata["DOKOB"], "SMQMEL")
        XCTAssertEqual(metadata["DOKAR"], "FMD")
        XCTAssertEqual(metadata["OBJKY"], source.id)
        XCTAssertEqual(metadata["DMS_CONTENTTYPE"], "D_TFM_Wartung")
        XCTAssertEqual(metadata["DMS_DOCID"], "TFM007")
        XCTAssertEqual(metadata["FELDWERT"], "")
        XCTAssertTrue(metadata["NAME", default: ""].hasPrefix("Foto_"))
        XCTAssertFalse(jpeg.base64EncodedString().hasPrefix("data:image"))
        XCTAssertEqual(Data(base64Encoded: jpeg.base64EncodedString()), jpeg)

        let resultRow = try XCTUnwrap(batch.values.first { $0["ELEMENTNR"]! == item.resultElementID })
        XCTAssertEqual(resultRow["MANDT"], "100")
        XCTAssertEqual(resultRow["FELDWERT"]!, "X")
        let commentRow = try XCTUnwrap(batch.values.first { $0["ELEMENTNR"]! == item.commentElementID })
        XCTAssertEqual(commentRow["FELDWERT"]!, "Broken")
    }

    func testBuilderRejectsAttachmentWithoutVerifiedSAPElementID() throws {
        let source = try makeSummary(control: "TFM1", cadence: "", category: "I002")
        let detail = SAPNotificationDetail(summary: source)
        let item = try XCTUnwrap(detail.inspectionItems.first)
        let attachment = NotificationPhotoAttachment(
            localAttachmentID: "local-photo", checklistItemID: item.id,
            sapElementID: "UNVERIFIED", capturedAt: .now,
            sapDocumentID: "STABLE-DOC-ID"
        )
        let review = NotificationReviewDraftPayload(
            notificationID: source.id, performedOn: .now,
            results: [item.id: .no], comments: [:],
            photoAttachments: [attachment], isClosedLocally: true,
            notificationSnapshot: OfflineNotificationSnapshot(detail: detail),
            outgoingProcessID: "STABLE-PROCESS-ID"
        )
        let work = OfflineWorkItem(
            id: UUID(), workerID: "S50828", type: .notificationReview,
            status: .pendingSynchronization, payload: .notificationReview(review),
            createdAt: .now, updatedAt: .now, syncError: nil
        )

        XCTAssertThrowsError(try SAPNotificationReviewUploadBuilder.build(
            workItem: work, source: source, syncUserID: "S50828",
            photoData: [attachment.localAttachmentID: Data([0xFF, 0xD8, 0xFF, 0xD9])]
        ))
    }

    func testOlderMarkerOnlyDraftDecodesWithoutUploadableAttachments() throws {
        let current = NotificationReviewDraftPayload(
            notificationID: "100", performedOn: Date(timeIntervalSince1970: 1_700_000_000),
            results: ["row": .no], comments: [:], photoAttachments: [],
            isClosedLocally: false
        )
        let encoded = try JSONEncoder().encode(current)
        var object = try XCTUnwrap(JSONSerialization.jsonObject(with: encoded) as? [String: Any])
        object.removeValue(forKey: "photoAttachments")
        object["photoItemIDs"] = ["row"]
        let legacy = try JSONSerialization.data(withJSONObject: object)

        let decoded = try JSONDecoder().decode(NotificationReviewDraftPayload.self, from: legacy)
        XCTAssertTrue(decoded.photoAttachments.isEmpty)
    }

    func testReplacingOutgoingRowsDoesNotDuplicateStableRetryIdentifiers() async throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let repository = try SQLiteSAPDataCacheRepository(
            databaseURL: directory.appendingPathComponent("cache.sqlite")
        )
        let header: LegacySAPRow = ["VORGANGSNR": "PROCESS", "QMNUM": "100"]
        let value: LegacySAPRow = ["VORGANGSNR": "PROCESS", "QMNUM": "100", "ELEMENTNR": "TFM1-1-1"]
        let document: LegacySAPRow = ["VORGANGSNR": "PROCESS", "QMNUM": "100", "DOCID": "DOC"]

        try await repository.replaceNotificationOutgoingRows(
            processIDs: ["PROCESS"], headers: [header], values: [value], documents: [document]
        )
        try await repository.replaceNotificationOutgoingRows(
            processIDs: ["PROCESS"], headers: [header], values: [value], documents: [document]
        )

        let headerCount = try await repository.legacyRowCount(in: "TO_T0281")
        let valueCount = try await repository.legacyRowCount(in: "TO_T0283")
        let documentCount = try await repository.legacyRowCount(in: "TO_T0282")
        XCTAssertEqual(headerCount, 1)
        XCTAssertEqual(valueCount, 1)
        XCTAssertEqual(documentCount, 1)
    }

    private func makeSummary(control: String, cadence: String, category: String) throws -> SAPNotificationSummary {
        let payload: [String: Any] = [
            "MANDT": "100", "QMNUM": "47100001", "QMART": "I1",
            "USTXT": "OPEN", "ZZQCODE_CI": category,
            "T_PLPOD": [[
                "USR00": "POSITION", "STEUS": control, "VORNR": "0010",
                "KTEX1": cadence, "LTXA1": "Inspect door", "LTXA2": "Check visually",
                "T_PROPS": [["POSNR": "1", "DFVAL": " ;X"]]
            ]]
        ]
        let data = try JSONSerialization.data(withJSONObject: payload, options: [.sortedKeys])
        return SAPNotificationSummary(
            id: "47100001", client: "100", title: "Door inspection",
            functionalLocationID: "FL-1", functionalLocationName: "Building A",
            startDate: "20260910", endDate: "20260910",
            systemStatus: "", userStatus: "OPEN",
            rawPayloadJSON: try XCTUnwrap(String(data: data, encoding: .utf8))
        )
    }
}
