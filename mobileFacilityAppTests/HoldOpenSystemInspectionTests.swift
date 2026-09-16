import Foundation
import XCTest
@testable import mobileFacilityApp

/// TFM6 Feststellanlage runs on the shared equipment inspection (screen, view
/// model, draft, PDF and upload). Every expectation is traced to the legacy
/// `App.controller.navToForm` (TFM6 → `Aufzugskontrolle`),
/// `Aufzugskontrolle.controller.js` and `HeaderFormBuilder.js`.
final class HoldOpenSystemInspectionTests: XCTestCase {

    // MARK: - Routing

    func testFormCodeResolvesFromFormNumberAndPlanPositions() throws {
        XCTAssertEqual(try makeSummary().equipmentInspectionForm, .holdOpenSystem)
        XCTAssertFalse(try makeSummary().isTFM2ElevatorInspection)

        let positionsOnly = try makeSummary(formNumber: nil)
        XCTAssertEqual(positionsOnly.equipmentInspectionForm, .holdOpenSystem)
    }

    func testFormCodeParsingIsCaseAndWhitespaceInsensitive() {
        XCTAssertEqual(EquipmentInspectionForm(formCode: " tfm6 "), .holdOpenSystem)
    }

    // MARK: - Form configuration

    /// TFM6 shares the `Aufzugskontrolle` controller: dropdowns, action,
    /// the position 3 material checkbox and the "Außer Betrieb" box.
    func testHoldOpenSystemUsesTheElevatorVariantWithMaterial() {
        let form = EquipmentInspectionForm.holdOpenSystem
        XCTAssertEqual(form.variant.formCode, "TFM6")
        XCTAssertEqual(form.variant.resultStyle, .dropdown)
        XCTAssertTrue(form.variant.hasActionColumn)
        XCTAssertEqual(form.variant.outOfServiceTitleKey, "inspection.outOfService")
        XCTAssertTrue(form.supportsMaterial)
    }

    /// `showInvalidData` checks `FORMNR !== TFM2`, so TFM6 is blocked without
    /// class characteristics even though it uses the elevator screen.
    func testHoldOpenSystemRequiresClassCharacteristics() {
        let form = EquipmentInspectionForm.holdOpenSystem
        XCTAssertTrue(form.requiresMasterData)
        XCTAssertEqual(form.equipmentTypes, ["TFMFSA"])
        XCTAssertNil(form.fallbackClassName)
        XCTAssertEqual(form.documentClass, "D_TFM_Wartung")
        XCTAssertEqual(form.documentValueList, "TFM006")
    }

    // MARK: - View model

    @MainActor
    func testMissingClassCharacteristicsBlockTheInspection() async throws {
        let model = EquipmentInspectionViewModel(
            detail: SAPNotificationDetail(summary: try makeSummary()),
            offlineWorkStore: makeStore(),
            photoStore: InMemoryPhotoAttachmentStore()
        )
        await model.load()

        XCTAssertEqual(model.form, .holdOpenSystem)
        XCTAssertTrue(model.isMasterDataMissing)
        XCTAssertTrue(model.isEditingDisabled)
        XCTAssertFalse(model.arePositionsEditable)
    }

    @MainActor
    func testInspectionWithCharacteristicsIsEditableAndShowsMaterial() async throws {
        let model = EquipmentInspectionViewModel(
            detail: SAPNotificationDetail(summary: try makeSummary()),
            offlineWorkStore: makeStore(),
            photoStore: InMemoryPhotoAttachmentStore(),
            elevatorAssetDataProvider: DemoElevatorAssetDataProvider()
        )
        await model.load()

        XCTAssertFalse(model.isMasterDataMissing)
        XCTAssertTrue(model.arePositionsEditable)
        XCTAssertEqual(model.items.count, 1)
        XCTAssertTrue(model.hasMaterialColumn)
        XCTAssertEqual(model.outOfServiceRowID, "TFM6-0000")
        XCTAssertEqual(model.outOfServiceValueElementID, "TFM6-0000-1")
        XCTAssertEqual(model.outOfServiceCommentElementID, "TFM6-0000-9B")
        XCTAssertEqual(model.reportTitle, String(localized: "holdOpenSystem.inspection.title"))
    }

    @MainActor
    func testSavedDraftRemembersFormCodeAndMaterial() async throws {
        let store = makeStore()
        let model = EquipmentInspectionViewModel(
            detail: SAPNotificationDetail(summary: try makeSummary()),
            offlineWorkStore: store,
            photoStore: InMemoryPhotoAttachmentStore(),
            elevatorAssetDataProvider: DemoElevatorAssetDataProvider()
        )
        await model.load()
        let item = try XCTUnwrap(model.items.first)
        model.results[item.id] = "1"
        model.materials[item.id] = true

        await model.save(closed: false)

        let draft = try XCTUnwrap(store.elevatorInspection(notificationID: "4710000036"))
        XCTAssertEqual(draft.formCode, "TFM6")
        XCTAssertEqual(draft.form, .holdOpenSystem)
        XCTAssertEqual(draft.elementValues["TFM6-0010-1"], "1")
        XCTAssertFalse(draft.materialFlags.isEmpty)
    }

    // MARK: - Upload

    func testUploadPostsTFM6ElementsWithMaterial() throws {
        let source = try makeSummary()
        let draft = ElevatorInspectionDraftPayload(
            notificationID: source.id,
            performedOn: Date(timeIntervalSince1970: 1_773_489_600),
            elementValues: ["TFM6-0010-1": "4", "TFM6-0010-2": "7"],
            comments: ["TFM6-0010-9B": "Haftmagnet lose"],
            materialFlags: ["TFM6-0010-3": true],
            pdfDocumentID: "PDF-1",
            pdfBytes: Data("PDF".utf8),
            outgoingProcessID: "PROC-1",
            isClosedLocally: true,
            closingSystemStatus: "MIAR",
            formCode: "TFM6"
        )
        let workItem = OfflineWorkItem(
            id: UUID(),
            workerID: "S50828",
            type: .elevatorInspection,
            status: .pendingSynchronization,
            payload: .elevatorInspection(draft),
            createdAt: .now,
            updatedAt: .now,
            syncError: nil
        )

        let batch = try SAPEquipmentInspectionUploadBuilder.build(
            workItem: workItem,
            source: source,
            syncUserID: "S50828",
            photoData: [:]
        )

        let header = try XCTUnwrap(batch.headers.first)
        XCTAssertEqual(header["FORMNR"], "TFM6")
        XCTAssertEqual(header["STTXT"], "MIAR")

        let elementIDs = Set(batch.values.compactMap { $0["ELEMENTNR"] ?? nil })
        XCTAssertTrue(elementIDs.isSuperset(of: [
            "TFM6-0010-1", "TFM6-0010-2", "TFM6-0010-3", "TFM6-0010-9B", "TFM6-0000-1", "TFM6-0000-9B"
        ]))
        XCTAssertFalse(elementIDs.contains { $0.hasPrefix("TFM2") })

        let pdf = try XCTUnwrap(batch.documents.first)
        XCTAssertEqual(pdf.metadata["ELEMENTNR"], "TFM6-pdf")
        XCTAssertEqual(pdf.metadata["DMS_CONTENTTYPE"], "D_TFM_Wartung")
        XCTAssertEqual(pdf.metadata["DMS_DOCID"], "TFM006")
    }

    // MARK: - Report

    func testReportRendersWithMaterialLegend() throws {
        let summary = try makeSummary()
        let items = ElevatorInspectionDecoder.decodeItems(from: summary.rawPayloadJSON)
        let payload = ElevatorInspectionPDFPayload(
            formTitle: EquipmentInspectionForm.holdOpenSystem.reportTitleFallback,
            masterDataTitle: EquipmentInspectionForm.holdOpenSystem.reportMasterDataTitle,
            notificationID: summary.id,
            notificationTitle: summary.title,
            functionalLocation: summary.functionalLocationID,
            equipmentID: summary.equipmentID,
            equipmentName: nil,
            locationCity: "",
            locationStreet: "",
            weGe: "",
            workerName: "",
            workerID: "S50828",
            company: "",
            orgUnit: "",
            plant: "",
            performedAt: .now,
            items: items,
            results: [items[0].id: "1"],
            actions: [:],
            materials: [items[0].id: true],
            notes: [:],
            hasMaterialColumn: true
        )

        let artifact = try ElevatorInspectionPDFRenderer.render(payload)
        XCTAssertFalse(artifact.data.isEmpty)
        XCTAssertEqual(payload.formTitle, "Feststellanlage")
    }

    // MARK: - Demo

    func testDemoDataContainsAHoldOpenSystemInspection() {
        let notification = MockFacilityData.sapNotifications.first { $0.id == "4710000036" }
        XCTAssertEqual(notification?.equipmentInspectionForm, .holdOpenSystem)
        let items = ElevatorInspectionDecoder.decodeItems(from: notification?.rawPayloadJSON ?? "")
        XCTAssertEqual(items.count, 4)
        XCTAssertTrue(items.contains(where: \.hasMaterial))
    }

    // MARK: - Helpers

    @MainActor
    private func makeStore() -> OfflineWorkStore {
        OfflineWorkStore(repository: InMemoryOfflineWorkRepository(), workerID: "S50828")
    }

    private func makeSummary(formNumber: String? = "TFM6") throws -> SAPNotificationSummary {
        var payload: [String: Any] = [
            "MANDT": "100",
            "QMNUM": "4710000036",
            "QMART": "I1",
            "USTXT": "OPEN",
            "T_PLPOD": [
                [
                    "USR00": "POSITION", "STEUS": "TFM6", "VORNR": "0010",
                    "LTXA1": "Haftmagnet", "LTXA2": "",
                    "T_PROPS": [
                        ["POSNR": "1", "DFVAL": "1;2;3;4;5", "DFVAL_TXT": "OK;Beseitigt;Behoben;Mangel;Entfällt"],
                        ["POSNR": "2", "DFVAL": "7;8;9", "DFVAL_TXT": "Reparatur;Weiterer Einsatz;Keine"],
                        ["POSNR": "3", "DFVAL": "X", "DFVAL_TXT": "Material bestellen"]
                    ]
                ]
            ]
        ]
        if let formNumber {
            payload["FORMNR"] = formNumber
        }
        let data = try JSONSerialization.data(withJSONObject: payload, options: [.sortedKeys])
        return SAPNotificationSummary(
            id: "4710000036",
            client: "100",
            title: "Feststellanlage",
            functionalLocationID: "FL-6",
            functionalLocationName: "Feststellanlage Flur",
            equipmentID: "EQ-100036",
            startDate: "20260914",
            endDate: "20260914",
            systemStatus: "MMAB",
            userStatus: "OPEN",
            rawPayloadJSON: try XCTUnwrap(String(data: data, encoding: .utf8))
        )
    }
}
