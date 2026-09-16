import Foundation
import XCTest
@testable import mobileFacilityApp

/// TFM4 Steigleitern runs on the shared equipment inspection (screen, view
/// model, draft, PDF and upload) that TFM2 uses. Every expectation is traced
/// to the legacy `MasterDataForm.controller.js` / `HeaderFormBuilder.js`.
final class FixedLadderInspectionTests: XCTestCase {

    // MARK: - Routing

    func testFormCodeResolvesFromFormNumberPlanPositionsAndPackedPayload() throws {
        XCTAssertEqual(try makeLadderSummary().equipmentInspectionForm, .fixedLadder)
        XCTAssertFalse(try makeLadderSummary().isTFM2ElevatorInspection)

        let positionsOnly = try makeLadderSummary(formNumber: nil)
        XCTAssertEqual(positionsOnly.equipmentInspectionForm, .fixedLadder)

        let other = try makeLadderSummary(formNumber: "TFM1", control: "TFM1")
        XCTAssertNil(other.equipmentInspectionForm)
    }

    func testFormCodeParsingIsCaseAndWhitespaceInsensitive() {
        XCTAssertEqual(EquipmentInspectionForm(formCode: " tfm4 "), .fixedLadder)
        XCTAssertEqual(EquipmentInspectionForm(formCode: "TFM2"), .elevator)
        XCTAssertNil(EquipmentInspectionForm(formCode: "TFM5"))
    }

    // MARK: - Form configuration

    /// `buildDefaultElements` gives TFM4 the "Außer Betrieb" box, and
    /// `MasterDataForm.getSelect` has no material branch.
    func testLadderUsesTheSharedDropdownVariantWithoutMaterial() {
        let form = EquipmentInspectionForm.fixedLadder
        XCTAssertEqual(form.variant.formCode, "TFM4")
        XCTAssertEqual(form.variant.resultStyle, .dropdown)
        XCTAssertTrue(form.variant.hasActionColumn)
        XCTAssertEqual(form.variant.outOfServiceTitleKey, "inspection.outOfService")
        XCTAssertFalse(form.supportsMaterial)
        XCTAssertTrue(EquipmentInspectionForm.elevator.supportsMaterial)
    }

    /// `showInvalidData` blocks every form except `Aufzugskontrolle`.
    func testOnlyTheElevatorMayRunWithoutClassCharacteristics() {
        XCTAssertFalse(EquipmentInspectionForm.elevator.requiresMasterData)
        XCTAssertTrue(EquipmentInspectionForm.fixedLadder.requiresMasterData)
        XCTAssertEqual(EquipmentInspectionForm.fixedLadder.equipmentTypes, ["TFMLEITER"])
    }

    /// Both legacy controllers declare `D_TFM_Wartung` / `TFM006`.
    func testLadderSharesTheElevatorDocumentMapping() {
        XCTAssertEqual(EquipmentInspectionForm.fixedLadder.documentClass, "D_TFM_Wartung")
        XCTAssertEqual(EquipmentInspectionForm.fixedLadder.documentValueList, "TFM006")
    }

    // MARK: - View model

    @MainActor
    func testMissingClassCharacteristicsBlockTheLadderInspection() async throws {
        let model = EquipmentInspectionViewModel(
            detail: SAPNotificationDetail(summary: try makeLadderSummary()),
            offlineWorkStore: makeStore(),
            photoStore: InMemoryPhotoAttachmentStore()
        )
        await model.load()

        XCTAssertEqual(model.form, .fixedLadder)
        XCTAssertTrue(model.isMasterDataMissing)
        XCTAssertTrue(model.isEditingDisabled)
        XCTAssertFalse(model.arePositionsEditable)
    }

    @MainActor
    func testLadderWithCharacteristicsIsEditableAndIgnoresMaterial() async throws {
        let model = EquipmentInspectionViewModel(
            detail: SAPNotificationDetail(summary: try makeLadderSummary()),
            offlineWorkStore: makeStore(),
            photoStore: InMemoryPhotoAttachmentStore(),
            elevatorAssetDataProvider: DemoElevatorAssetDataProvider()
        )
        await model.load()

        XCTAssertFalse(model.isMasterDataMissing)
        XCTAssertTrue(model.arePositionsEditable)
        XCTAssertEqual(model.items.count, 1)
        XCTAssertTrue(model.items[0].hasMaterial, "SAP delivered position 3")
        XCTAssertFalse(model.hasMaterialColumn, "TFM4 never shows it")
        XCTAssertEqual(model.outOfServiceRowID, "TFM4-0000")
        XCTAssertEqual(model.outOfServiceValueElementID, "TFM4-0000-1")
        XCTAssertEqual(model.outOfServiceCommentElementID, "TFM4-0000-9B")
        XCTAssertEqual(model.reportTitle, String(localized: "fixedLadder.inspection.title"))
    }

    @MainActor
    func testSavedLadderDraftRemembersItsFormCode() async throws {
        let store = makeStore()
        let model = EquipmentInspectionViewModel(
            detail: SAPNotificationDetail(summary: try makeLadderSummary()),
            offlineWorkStore: store,
            photoStore: InMemoryPhotoAttachmentStore(),
            elevatorAssetDataProvider: DemoElevatorAssetDataProvider()
        )
        await model.load()
        let item = try XCTUnwrap(model.items.first)
        model.results[item.id] = "1"
        model.materials[item.id] = true

        await model.save(closed: false)

        let draft = try XCTUnwrap(store.elevatorInspection(notificationID: "4710000024"))
        XCTAssertEqual(draft.formCode, "TFM4")
        XCTAssertEqual(draft.form, .fixedLadder)
        XCTAssertEqual(draft.elementValues["TFM4-0010-1"], "1")
        XCTAssertTrue(draft.materialFlags.isEmpty)
    }

    func testDraftsWithoutAFormCodeAreElevatorInspections() {
        XCTAssertEqual(ElevatorInspectionDraftPayload(notificationID: "1").form, .elevator)
    }

    // MARK: - Upload

    func testLadderUploadPostsTFM4ElementsWithoutMaterial() throws {
        let source = try makeLadderSummary()
        let draft = ElevatorInspectionDraftPayload(
            notificationID: source.id,
            performedOn: Date(timeIntervalSince1970: 1_773_489_600),
            elementValues: ["TFM4-0010-1": "4", "TFM4-0010-2": "7"],
            comments: ["TFM4-0010-9B": "Sprosse verbogen"],
            materialFlags: ["TFM4-0010-3": true],
            pdfDocumentID: "PDF-1",
            pdfBytes: Data("PDF".utf8),
            outgoingProcessID: "PROC-1",
            isClosedLocally: true,
            closingSystemStatus: "MIAR",
            formCode: "TFM4"
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
        XCTAssertEqual(header["FORMNR"], "TFM4")
        XCTAssertEqual(header["STTXT"], "MIAR")
        XCTAssertEqual(header["STATUSNR"], "2")

        let elementIDs = Set(batch.values.compactMap { $0["ELEMENTNR"] ?? nil })
        XCTAssertTrue(elementIDs.isSuperset(of: [
            "TFM4-0010-1", "TFM4-0010-2", "TFM4-0010-9B", "TFM4-0000-1", "TFM4-0000-9B"
        ]))
        XCTAssertFalse(elementIDs.contains("TFM4-0010-3"))
        XCTAssertFalse(elementIDs.contains { $0.hasPrefix("TFM2") })

        let pdf = try XCTUnwrap(batch.documents.first)
        XCTAssertEqual(pdf.metadata["ELEMENTNR"], "TFM4-pdf")
        XCTAssertEqual(pdf.metadata["DMS_CONTENTTYPE"], "D_TFM_Wartung")
        XCTAssertEqual(pdf.metadata["DMS_DOCID"], "TFM006")
    }

    // MARK: - Report

    func testLadderReportRendersWithItsOwnTitle() throws {
        let summary = try makeLadderSummary()
        let items = ElevatorInspectionDecoder.decodeItems(from: summary.rawPayloadJSON)
        let payload = ElevatorInspectionPDFPayload(
            formTitle: EquipmentInspectionForm.fixedLadder.reportTitleFallback,
            masterDataTitle: EquipmentInspectionForm.fixedLadder.reportMasterDataTitle,
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
            materials: [:],
            notes: [:],
            hasMaterialColumn: false
        )

        let artifact = try ElevatorInspectionPDFRenderer.render(payload)
        XCTAssertFalse(artifact.data.isEmpty)
        XCTAssertEqual(payload.formTitle, "Steigleitern")
    }

    // MARK: - Demo

    func testDemoDataContainsALadderInspection() {
        let ladder = MockFacilityData.sapNotifications.first { $0.id == "4710000024" }
        XCTAssertEqual(ladder?.equipmentInspectionForm, .fixedLadder)
        XCTAssertFalse(ElevatorInspectionDecoder.decodeItems(from: ladder?.rawPayloadJSON ?? "").isEmpty)
    }

    // MARK: - Helpers

    @MainActor
    private func makeStore() -> OfflineWorkStore {
        OfflineWorkStore(repository: InMemoryOfflineWorkRepository(), workerID: "S50828")
    }

    private func makeLadderSummary(
        formNumber: String? = "TFM4",
        control: String = "TFM4"
    ) throws -> SAPNotificationSummary {
        var payload: [String: Any] = [
            "MANDT": "100",
            "QMNUM": "4710000024",
            "QMART": "I1",
            "USTXT": "OPEN",
            "T_PLPOD": [
                [
                    "USR00": "POSITION", "STEUS": control, "VORNR": "0010",
                    "LTXA1": "Holme und Sprossen", "LTXA2": "",
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
            id: "4710000024",
            client: "100",
            title: "Steigleiter",
            functionalLocationID: "FL-2",
            functionalLocationName: "Steigleiter Nord",
            equipmentID: "EQ-100024",
            startDate: "20260914",
            endDate: "20260914",
            systemStatus: "MMAB",
            userStatus: "OPEN",
            rawPayloadJSON: try XCTUnwrap(String(data: data, encoding: .utf8))
        )
    }
}
