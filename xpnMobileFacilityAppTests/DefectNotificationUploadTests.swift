import Foundation
import XCTest
@testable import mobileFacilityApp

/// A defect from the defect form goes to SAP as an I2 under the I1 the
/// technician chose.
final class DefectNotificationUploadTests: XCTestCase {
    private let workItemID = UUID(uuidString: "0A1B2C3D-0000-4000-8000-000000000001")!
    private let savedAt = Date(timeIntervalSince1970: 1_789_041_600) // 2026-09-10 12:00 UTC

    func testBuilderCreatesI2UnderTheChosenI1() throws {
        let photo = Data([0xFF, 0xD8, 0xFF, 0xD9])
        let defect = makeDefect(attachmentIDs: ["PHOTO-1"])

        let batch = try SAPDefectNotificationUploadBuilder.build(
            workItem: makeItem(defect), defect: defect, parentNotification: parent,
            template: template, photoData: ["PHOTO-1": photo], syncUserID: "s50828", now: savedAt
        )

        XCTAssertEqual(batch.workItemIDs, [workItemID])
        XCTAssertEqual(batch.attachmentIDs, ["PHOTO-1"])
        XCTAssertEqual(batch.processIDs, ["0A1B2C3D000040008000000000000001"])
        XCTAssertTrue(batch.headers.isEmpty)
        XCTAssertTrue(batch.documents.isEmpty)

        let row = try XCTUnwrap(batch.i2Notifications.first)
        XCTAssertEqual(batch.i2Notifications.count, 1)
        XCTAssertEqual(row["QMNUM"], "NEU-0A1B2C3D")
        XCTAssertEqual(row["QMART"], "I2")
        XCTAssertEqual(row["REFNUM"], "005140058979")
        XCTAssertEqual(row["MANDT"], "100")
        XCTAssertEqual(row["STRNO"], "D1-SCZ-40036-03-330")
        XCTAssertEqual(row["TPLNR"], "D1-SCZ-40036-03-330")
        XCTAssertEqual(row["STSMA"], "ZPMTFM")
        XCTAssertEqual(row["QMTXT"], "Tür klemmt")
        XCTAssertEqual(row["QMCOD"], "003")
        XCTAssertEqual(row["QMGRP"], "ZPMI0001")
        XCTAssertEqual(row["PRIOK"], "1")
        XCTAssertEqual(row["USTXT"], "MTFM")
        XCTAssertEqual(row["QMNAM"], "S50828")

        let object = try XCTUnwrap(SAPLegacyDataExchangeCodec.decodedFeldwertObject(try XCTUnwrap(row["FELDWERT"] ?? nil)))
        XCTAssertEqual(object["REFNUM"] as? String, "005140058979")
        XCTAssertEqual(object["PRIOK"] as? String, "1")
        let lines = try XCTUnwrap(object["T_LTXT_QM"] as? [[String: Any]])
        XCTAssertEqual(lines.map { $0["TDLINE"] as? String }, ["Schließt nicht mehr"])

        let document = try XCTUnwrap(batch.i2Documents.first)
        XCTAssertEqual(batch.i2Documents.count, 1)
        XCTAssertEqual(document.metadata["MANDT"], "100")
        XCTAssertEqual(document.metadata["QMNUM"], "NEU-0A1B2C3D")
        XCTAssertEqual(document.metadata["OBJKY"], "NEU-0A1B2C3D")
        XCTAssertEqual(document.metadata["VORGANGSNR"], "0A1B2C3D000040008000000000000001")
        XCTAssertEqual(document.metadata["DMS_CONTENTTYPE"], "D_TFM_AllgemeineDokumente")
        XCTAssertEqual(document.metadata["DMS_DOCID"], "TFM009")
        XCTAssertEqual(document.data, photo)
    }

    func testPriorityMapsToSAPPriority() throws {
        XCTAssertEqual(DefectPriority.low.sapPriority, "3")
        XCTAssertEqual(DefectPriority.medium.sapPriority, "2")
        XCTAssertEqual(DefectPriority.high.sapPriority, "1")
        for priority in DefectPriority.allCases {
            var defect = makeDefect(attachmentIDs: [])
            defect.priority = priority
            let row = try XCTUnwrap(SAPDefectNotificationUploadBuilder.build(
                workItem: makeItem(defect), defect: defect, parentNotification: parent,
                template: template, photoData: [:], syncUserID: "S1"
            ).i2Notifications.first)
            XCTAssertEqual(row["PRIOK"], priority.sapPriority)
        }
    }

    func testBuilderRejectsDefectWithoutCategoryOrI1() {
        var withoutCategory = makeDefect(attachmentIDs: [])
        withoutCategory.category = nil
        XCTAssertThrowsError(try SAPDefectNotificationUploadBuilder.build(
            workItem: makeItem(withoutCategory), defect: withoutCategory, parentNotification: parent,
            template: template, photoData: [:], syncUserID: "S1"
        ))

        var withoutParent = makeDefect(attachmentIDs: [])
        withoutParent.parentNotificationID = nil
        XCTAssertThrowsError(try SAPDefectNotificationUploadBuilder.build(
            workItem: makeItem(withoutParent), defect: withoutParent, parentNotification: parent,
            template: template, photoData: [:], syncUserID: "S1"
        ))
    }

    func testParentBelongsOnlyToItsOwnObject() {
        let onPlace = DefectParentNotification(
            id: "1", title: "", functionalLocationID: "FL-1", equipmentID: "", startDate: ""
        )
        let onEquipment = DefectParentNotification(
            id: "2", title: "", functionalLocationID: "FL-1", equipmentID: "EQ-1", startDate: ""
        )
        let place = TechnicalObjectReference(kind: .functionalLocation, objectID: "FL-1")
        let equipment = TechnicalObjectReference(kind: .equipment, objectID: "EQ-1")
        XCTAssertTrue(onPlace.belongs(to: place))
        XCTAssertFalse(onEquipment.belongs(to: place))
        XCTAssertTrue(onEquipment.belongs(to: equipment))
        XCTAssertFalse(onPlace.belongs(to: equipment))
    }

    func testDefectsSavedBeforeUploadStillDecode() throws {
        let json = """
        {"technicalObject":{"kind":"functionalLocation","objectID":"FL-1"},"technicalObjectName":"Haus",
         "priority":"high","shortText":"Alt","longText":"","attachmentIDs":[]}
        """
        let defect = try JSONDecoder().decode(DefectDraftPayload.self, from: Data(json.utf8))
        XCTAssertNil(defect.category)
        XCTAssertNil(defect.parentNotificationID)
        XCTAssertFalse(OfflineWorkType.defect.staysLocal)
    }

    // MARK: - Fixtures

    private let parent: [String: Any] = [
        "MANDT": "100", "QMNUM": "005140058979", "QMART": "I1", "QMTXT": "Rundgang",
        "STRNO": "D1-SCZ-40036-03-330", "TPLNR": "INTERNAL", "EQUNR": "", "STSMA": "ZPMTFM",
        "STTXT": "MOFN", "USTXT": "OPEN", "PRIOK": "4"
    ]

    private let template: [String: Any] = [
        "MANDT": "", "QMART": "", "STSMA": "", "T_LTXT_QM": []
    ]

    private func makeDefect(attachmentIDs: [String]) -> DefectDraftPayload {
        DefectDraftPayload(
            technicalObject: TechnicalObjectReference(kind: .functionalLocation, objectID: "D1-SCZ-40036-03-330"),
            technicalObjectName: "Raum 330",
            dinGroup: nil,
            priority: .high,
            shortText: "Tür klemmt",
            longText: "  Schließt nicht mehr ",
            attachmentIDs: attachmentIDs,
            category: .technical,
            parentNotificationID: "005140058979",
            parentNotificationTitle: "Rundgang"
        )
    }

    private func makeItem(_ defect: DefectDraftPayload) -> OfflineWorkItem {
        OfflineWorkItem(
            id: workItemID, workerID: "S50828", type: .defect, status: .pendingSynchronization,
            payload: .defect(defect), createdAt: savedAt, updatedAt: savedAt, syncError: nil
        )
    }
}
