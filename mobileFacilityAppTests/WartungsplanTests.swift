import Foundation
import XCTest
@testable import mobileFacilityApp

final class WartungsplanTests: XCTestCase {
    func testSAPNotificationDetailParsesAddressAndFormCode() throws {
        let summary = try makeSummary(
            control: "TFM1",
            title: "MTFM_Überprüfung Alarmpläne",
            functionalLocationID: "DE-SAF-11152-10",
            functionalLocationName: "GB10_Rauschermühle_V1 Verwaltungsgebäude",
            street: "Rauschermühle",
            houseNumber: "",
            postalCode: "56648",
            city: "Saffig"
        )
        let detail = SAPNotificationDetail(summary: summary)

        XCTAssertEqual(detail.formCode, "TFM1")
        XCTAssertEqual(detail.address, "Rauschermühle , 56648-Saffig")
        XCTAssertEqual(detail.summary.title, "MTFM_Überprüfung Alarmpläne")
        XCTAssertEqual(detail.summary.functionalLocationID, "DE-SAF-11152-10")
        XCTAssertEqual(detail.summary.functionalLocationName, "GB10_Rauschermühle_V1 Verwaltungsgebäude")
        XCTAssertEqual(detail.inspectionItems.count, 3)

        // Verify snapshot round-trip
        let snapshot = OfflineNotificationSnapshot(detail: detail)
        XCTAssertEqual(snapshot.formCode, "TFM1")
        XCTAssertEqual(snapshot.address, "Rauschermühle , 56648-Saffig")

        let restored = SAPNotificationDetail(offlineSnapshot: snapshot, notificationID: summary.id)
        XCTAssertEqual(restored.formCode, "TFM1")
        XCTAssertEqual(restored.address, "Rauschermühle , 56648-Saffig")
    }

    @MainActor
    func testWartungsplanViewModelEverythingOkayAndValidation() async throws {
        let summary = try makeSummary(
            control: "TFM1",
            title: "MTFM_Überprüfung Alarmpläne",
            functionalLocationID: "DE-SAF-11152-10",
            functionalLocationName: "GB10_Rauschermühle_V1 Verwaltungsgebäude",
            street: "Rauschermühle",
            houseNumber: "",
            postalCode: "56648",
            city: "Saffig"
        )
        let detail = SAPNotificationDetail(summary: summary)
        let repository = InMemoryOfflineWorkRepository()
        let workStore = OfflineWorkStore(repository: repository, workerID: "S50828")
        let photoStore = InMemoryPhotoAttachmentStore()

        let model = WartungsplanViewModel(
            detail: detail,
            offlineWorkStore: workStore,
            photoStore: photoStore
        )
        await model.load()

        // Initially no answers -> canClose is false
        XCTAssertFalse(model.canClose)

        // Mark everything OK -> all items become .no
        model.markEverythingOkay()
        XCTAssertTrue(model.canClose)
        for item in detail.inspectionItems {
            XCTAssertEqual(model.results[item.id], .no)
            XCTAssertFalse(model.isCommentMissing(for: item.id))
        }

        // Change one item to .yes (defect) without comment
        let defectItem = detail.inspectionItems[0]
        model.results[defectItem.id] = .yes
        XCTAssertTrue(model.isCommentMissing(for: defectItem.id))
        XCTAssertFalse(model.canClose)

        // Attempting to close fails with .commentRequired
        let closeAttempt = await model.save(closed: true)
        XCTAssertFalse(closeAttempt)
        XCTAssertEqual(model.feedback, .commentRequired)

        // Add mandatory comment for the defect
        model.comments[defectItem.id] = "Alarmkontakt nicht erreichbar"
        XCTAssertFalse(model.isCommentMissing(for: defectItem.id))
        XCTAssertTrue(model.canClose)

        // Save as draft
        let saveDraft = await model.save(closed: false)
        XCTAssertTrue(saveDraft)
        XCTAssertEqual(model.feedback, .savedLocally)
        XCTAssertEqual(workStore.savedNotificationItems.first?.status, .draft)

        // Reopen from store and verify persisted state
        let reopened = WartungsplanViewModel(
            detail: detail,
            offlineWorkStore: workStore,
            photoStore: photoStore
        )
        await reopened.load()
        XCTAssertEqual(reopened.results[defectItem.id], .yes)
        XCTAssertEqual(reopened.comments[defectItem.id], "Alarmkontakt nicht erreichbar")
        XCTAssertTrue(reopened.canClose)

        // Close notification
        let closed = await reopened.save(closed: true)
        XCTAssertTrue(closed)
        XCTAssertEqual(reopened.feedback, .closedLocally)
        XCTAssertTrue(reopened.isClosedLocally)
        XCTAssertEqual(workStore.savedNotificationItems.first?.status, .pendingSynchronization)
        // The upload sends this report, so it has to be kept at close.
        XCTAssertEqual(
            workStore.notificationReview(notificationID: summary.id)?.pdfData?.isEmpty, false
        )
    }

    @MainActor
    func testWartungsplanPhotosAttachAndLimit() async throws {
        let summary = try makeSummary(
            control: "TFM1",
            title: "MTFM_Überprüfung Alarmpläne",
            functionalLocationID: "DE-SAF-11152-10",
            functionalLocationName: "GB10_Rauschermühle_V1 Verwaltungsgebäude",
            street: "Rauschermühle",
            houseNumber: "",
            postalCode: "56648",
            city: "Saffig"
        )
        let detail = SAPNotificationDetail(summary: summary)
        let item = try XCTUnwrap(detail.inspectionItems.first)
        let repository = InMemoryOfflineWorkRepository()
        let workStore = OfflineWorkStore(repository: repository, workerID: "S50828")
        let photoStore = InMemoryPhotoAttachmentStore()

        let model = WartungsplanViewModel(
            detail: detail,
            offlineWorkStore: workStore,
            photoStore: photoStore
        )
        await model.load()

        let jpeg = Data([0xFF, 0xD8, 0x01, 0x02, 0xFF, 0xD9])
        for _ in 0...WartungsplanViewModel.maximumPhotoCount {
            await model.addPhoto(jpegData: jpeg, to: item)
        }
        XCTAssertEqual(model.photoAttachments.count, 20)
        XCTAssertEqual(model.feedback, .photoLimitReached)

        let attachment = try XCTUnwrap(model.photoAttachments.first)
        await model.removePhoto(attachment)
        XCTAssertEqual(model.photoAttachments.count, 19)
    }

    private func makeSummary(
        control: String,
        title: String,
        functionalLocationID: String,
        functionalLocationName: String,
        street: String,
        houseNumber: String,
        postalCode: String,
        city: String
    ) throws -> SAPNotificationSummary {
        let payload: [String: Any] = [
            "MANDT": "100",
            "QMNUM": "005140055904",
            "QMART": "I1",
            "QMTXT": title,
            "STRNO": functionalLocationID,
            "PLTXT": functionalLocationName,
            "STREET_TO": street,
            "HOUSE_NUM1_TO": houseNumber,
            "POST_CODE1_TO": postalCode,
            "CITY1_TO": city,
            "USTXT": "OPEN",
            "ZZQCODE_CI": "I002",
            "T_PLPOD": [
                [
                    "USR00": "POSITION", "STEUS": control, "VORNR": "0010",
                    "LTXA1": "Sind die Ansprechpartner noch korrekt?",
                    "LTXA2": "Überprüfung der hinterlegten Alarmkontakte und Notfall-Ansprechpartner.",
                    "T_PROPS": [["POSNR": "1", "DFVAL": " ;X", "DFVAL_TXT": "Nein;Ja"]]
                ],
                [
                    "USR00": "POSITION", "STEUS": control, "VORNR": "0020",
                    "LTXA1": "Sind die Kontaktdaten noch korrekt?",
                    "LTXA2": "Prüfung von Telefonnummern, Mobilnummern und E-Mail-Adressen.",
                    "T_PROPS": [["POSNR": "1", "DFVAL": " ;X", "DFVAL_TXT": "Nein;Ja"]]
                ],
                [
                    "USR00": "POSITION", "STEUS": control, "VORNR": "0030",
                    "LTXA1": "Sind die geschalteten Anlagen korrekt?",
                    "LTXA2": "Abgleich der im Alarmplan aufgeführten Brandmelde- und Lüftungsanlagen.",
                    "T_PROPS": [["POSNR": "1", "DFVAL": " ;X", "DFVAL_TXT": "Nein;Ja"]]
                ]
            ]
        ]
        let data = try JSONSerialization.data(withJSONObject: payload, options: [.sortedKeys])
        return SAPNotificationSummary(
            id: "005140055904",
            client: "100",
            title: title,
            functionalLocationID: functionalLocationID,
            functionalLocationName: functionalLocationName,
            startDate: "20260915",
            endDate: "20260915",
            systemStatus: "",
            userStatus: "OPEN",
            rawPayloadJSON: try XCTUnwrap(String(data: data, encoding: .utf8))
        )
    }
}
