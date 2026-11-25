import Foundation
import XCTest
@testable import mobileFacilityApp

/// Incoming TFM7 notifications share the legacy `MasterDataForm` behavior
/// with TFM4, but retain their mandatory `USR00 == "FOTO"` evidence row.
final class TFM7NotificationTests: XCTestCase {

    func testTFM7RoutesToTheSharedEquipmentInspectionAndKeepsPhotoRows() throws {
        let summary = try XCTUnwrap(MockFacilityData.sapNotifications.first { $0.id == "4710000031" })

        XCTAssertEqual(summary.equipmentInspectionForm, .subdistribution)
        XCTAssertEqual(EquipmentInspectionForm.subdistribution.equipmentTypes, ["TFMNSPV"])
        XCTAssertFalse(EquipmentInspectionForm.subdistribution.supportsMaterial)
        XCTAssertTrue(EquipmentInspectionForm.subdistribution.requiresMasterData)

        let items = ElevatorInspectionDecoder.decodeItems(from: summary.rawPayloadJSON)
        XCTAssertEqual(items.count, 3)
        XCTAssertEqual(items[0].resultElementID, "TFM7-0010-1")
        XCTAssertEqual(items[0].actionElementID, "TFM7-0010-2")
        XCTAssertEqual(items[2].commentElementID, "TFM7-0030-9B")
        XCTAssertTrue(items[2].requiresPhoto)
        XCTAssertTrue(items[2].requiresPhotoAndComment)
        XCTAssertFalse(items[2].requiresResult)
        XCTAssertTrue(items[2].resultOptions.isEmpty)
        XCTAssertNil(items[2].actionElementID)
        XCTAssertTrue(items[2].actionOptions.isEmpty)

        let photoFormItem = items[2].inspectionFormItem
        XCTAssertFalse(photoFormItem.requiresResult)
        XCTAssertTrue(photoFormItem.resultOptions.isEmpty)
        XCTAssertTrue(photoFormItem.actionOptions.isEmpty)
        XCTAssertTrue(photoFormItem.requiresPhoto)
        XCTAssertTrue(photoFormItem.requiresPhotoAndComment)
    }

    @MainActor
    func testPhotoOnlyTFM7RowBlocksCloseUntilPhotoAndCommentAreStored() async throws {
        let summary = try XCTUnwrap(MockFacilityData.sapNotifications.first { $0.id == "4710000031" })
        let photoStore = InMemoryPhotoAttachmentStore()
        let model = EquipmentInspectionViewModel(
            detail: SAPNotificationDetail(summary: summary),
            offlineWorkStore: OfflineWorkStore(repository: InMemoryOfflineWorkRepository(), workerID: "S50828"),
            photoStore: photoStore,
            elevatorAssetDataProvider: DemoElevatorAssetDataProvider()
        )
        await model.load()
        model.applyAllGood()

        XCTAssertFalse(model.isChecklistValid)
        let photoRow = try XCTUnwrap(model.items.first { $0.requiresPhoto })
        await model.addPhoto(jpegData: Data([0xFF, 0xD8, 0xFF, 0xD9]), to: photoRow)

        XCTAssertFalse(model.isChecklistValid)
        model.comments[photoRow.id] = "Übersichtsaufnahme der Verteilung"

        XCTAssertTrue(model.isChecklistValid)
    }

    @MainActor
    func testMissingTFM7ClassCharacteristicsBlockTheInspection() async throws {
        let summary = try XCTUnwrap(MockFacilityData.sapNotifications.first { $0.id == "4710000031" })
        let model = EquipmentInspectionViewModel(
            detail: SAPNotificationDetail(summary: summary),
            offlineWorkStore: OfflineWorkStore(repository: InMemoryOfflineWorkRepository(), workerID: "S50828"),
            photoStore: InMemoryPhotoAttachmentStore()
        )

        await model.load()

        XCTAssertTrue(model.isMasterDataMissing)
        XCTAssertTrue(model.isEditingDisabled)
    }

    @MainActor
    func testMissingMasterDataAcknowledgementReturnsToNotifications() throws {
        let workspace = FacilityDemoViewModel(
            isDemoMode: true,
            offlineWorkStore: OfflineWorkStore(
                repository: InMemoryOfflineWorkRepository(), workerID: "demo"
            ),
            sapDataStore: SAPDataStore(
                repository: InMemorySAPDataCacheRepository(seed: TechnicalObjectDemoData.cachedData),
                refreshService: nil,
                localWorkerID: "demo"
            ),
            meterReferenceProvider: DemoMeterReferenceProvider(),
            photoAttachmentStore: InMemoryPhotoAttachmentStore()
        )
        let summary = try XCTUnwrap(MockFacilityData.sapNotifications.first { $0.id == "4710000031" })
        workspace.selection = .drafts
        workspace.selectedOfflineNotificationDetail = SAPNotificationDetail(summary: summary)

        workspace.dismissOfflineNotificationDetail(returningTo: .notifications)

        XCTAssertNil(workspace.selectedOfflineNotificationDetail)
        XCTAssertEqual(workspace.selection, .notifications)
    }

    @MainActor
    func testReopeningTheSameNotificationCreatesANewDetailPresentation() {
        let workspace = FacilityDemoViewModel(
            isDemoMode: true,
            offlineWorkStore: OfflineWorkStore(
                repository: InMemoryOfflineWorkRepository(), workerID: "demo"
            ),
            sapDataStore: SAPDataStore(
                repository: InMemorySAPDataCacheRepository(seed: TechnicalObjectDemoData.cachedData),
                refreshService: nil,
                localWorkerID: "demo"
            ),
            meterReferenceProvider: DemoMeterReferenceProvider(),
            photoAttachmentStore: InMemoryPhotoAttachmentStore()
        )

        workspace.selectedNotificationID = "4710000031"
        let firstPresentationID = workspace.notificationDetailPresentationID
        workspace.selectedNotificationID = nil
        workspace.selectedNotificationID = "4710000031"

        XCTAssertNotEqual(firstPresentationID, workspace.notificationDetailPresentationID)
    }

    func testTFM7UploadOmitsResultForPhotoOnlyRowAndPostsItsEvidence() throws {
        let source = try XCTUnwrap(MockFacilityData.sapNotifications.first { $0.id == "4710000031" })
        let photo = NotificationPhotoAttachment(
            localAttachmentID: "photo-1",
            checklistItemID: "TFM7-0030-1",
            sapElementID: "TFM7-0030-9B",
            capturedAt: Date(timeIntervalSince1970: 1_773_489_600),
            sapDocumentID: "PHOTO-1"
        )
        let draft = ElevatorInspectionDraftPayload(
            notificationID: source.id,
            elementValues: ["TFM7-0010-1": "1", "TFM7-0020-1": "1"],
            comments: ["TFM7-0030-9B": "Übersichtsaufnahme"],
            photoAttachments: [photo],
            pdfDocumentID: "PDF-1",
            pdfBytes: Data("PDF".utf8),
            outgoingProcessID: "PROC-1",
            isClosedLocally: true,
            formCode: "TFM7"
        )
        let workItem = OfflineWorkItem(
            id: UUID(), workerID: "S50828", type: .elevatorInspection,
            status: .pendingSynchronization, payload: .elevatorInspection(draft),
            createdAt: .now, updatedAt: .now, syncError: nil
        )

        let batch = try SAPEquipmentInspectionUploadBuilder.build(
            workItem: workItem, source: source, syncUserID: "S50828",
            photoData: ["photo-1": Data([0xFF, 0xD8, 0xFF, 0xD9])]
        )

        XCTAssertEqual(batch.headers.first?["FORMNR"], "TFM7")
        let elementIDs = Set(batch.values.compactMap { $0["ELEMENTNR"] })
        XCTAssertFalse(elementIDs.contains("TFM7-0030-1"))
        XCTAssertTrue(elementIDs.contains("TFM7-0030-9B"))
        XCTAssertEqual(batch.documents.count, 2)
    }
}
