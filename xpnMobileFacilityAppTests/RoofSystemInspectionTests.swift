import Foundation
import XCTest
@testable import mobileFacilityApp

/// TFM8 Dachanlagen runs on the shared equipment inspection (screen, view
/// model, draft, PDF and upload). Every expectation is traced to the legacy
/// `App.controller.navToForm` (TFM8 → `MasterDataForm`),
/// `BaseFormController.buildDefaultElements` (no out-of-order box for TFM8)
/// and `HeaderFormBuilder.js`.
final class RoofSystemInspectionTests: XCTestCase {

    // MARK: - Routing

    func testFormCodeResolvesFromFormNumberAndPlanPositions() throws {
        XCTAssertEqual(try makeSummary().equipmentInspectionForm, .roofSystem)
        XCTAssertFalse(try makeSummary().isTFM2ElevatorInspection)

        let positionsOnly = try makeSummary(formNumber: nil)
        XCTAssertEqual(positionsOnly.equipmentInspectionForm, .roofSystem)
    }

    func testFormCodeParsingIsCaseAndWhitespaceInsensitive() {
        XCTAssertEqual(EquipmentInspectionForm(formCode: " tfm8 "), .roofSystem)
    }

    // MARK: - Form configuration

    /// `MasterDataForm`: dropdowns and action, no material, and
    /// `buildDefaultElements` returns before building "Außer Betrieb".
    func testRoofSystemHasNoOutOfServiceStatusAndNoMaterial() {
        let form = EquipmentInspectionForm.roofSystem
        XCTAssertEqual(form.variant.formCode, "TFM8")
        XCTAssertEqual(form.variant.resultStyle, .dropdown)
        XCTAssertTrue(form.variant.hasActionColumn)
        XCTAssertNil(form.variant.outOfServiceTitleKey)
        XCTAssertFalse(form.supportsOutOfService)
        XCTAssertFalse(form.supportsMaterial)
    }

    func testRoofSystemRequiresClassCharacteristics() {
        let form = EquipmentInspectionForm.roofSystem
        XCTAssertTrue(form.requiresMasterData)
        XCTAssertEqual(form.equipmentTypes, ["TFMDACH"])
        XCTAssertNil(form.fallbackClassName)
        XCTAssertEqual(form.documentClass, "D_TFM_Wartung")
        XCTAssertEqual(form.documentValueList, "TFM006")
        XCTAssertEqual(form.reportTitleFallback, "Dachanlagen")
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

        XCTAssertEqual(model.form, .roofSystem)
        XCTAssertTrue(model.isMasterDataMissing)
        XCTAssertTrue(model.isEditingDisabled)
    }

    @MainActor
    func testOutOfServiceCannotBeSet() async throws {
        let model = EquipmentInspectionViewModel(
            detail: SAPNotificationDetail(summary: try makeSummary()),
            offlineWorkStore: makeStore(),
            photoStore: InMemoryPhotoAttachmentStore(),
            elevatorAssetDataProvider: DemoElevatorAssetDataProvider()
        )
        await model.load()

        XCTAssertTrue(model.arePositionsEditable)
        XCTAssertFalse(model.hasMaterialColumn)

        model.requestOutOfServiceChange()
        XCTAssertNil(model.outOfServiceTransition)

        await model.confirmOutOfServiceChange(to: true)
        XCTAssertFalse(model.isOutOfService)
    }

    @MainActor
    func testSavedDraftRemembersFormCodeWithoutMaterial() async throws {
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

        let draft = try XCTUnwrap(store.elevatorInspection(notificationID: "4710000048"))
        XCTAssertEqual(draft.formCode, "TFM8")
        XCTAssertEqual(draft.form, .roofSystem)
        XCTAssertEqual(draft.elementValues["TFM8-0010-1"], "1")
        XCTAssertTrue(draft.materialFlags.isEmpty)
        XCTAssertEqual(draft.isOutOfOperation, false)
    }

    // MARK: - Upload

    func testUploadPostsTFM8ElementsWithoutMaterialAndEmptyStatus() throws {
        let source = try makeSummary()
        let batch = try SAPEquipmentInspectionUploadBuilder.build(
            workItem: makeWorkItem(draft: makeDraft(source: source)),
            source: source,
            syncUserID: "S50828",
            photoData: [:]
        )

        let header = try XCTUnwrap(batch.headers.first)
        XCTAssertEqual(header["FORMNR"], "TFM8")
        XCTAssertEqual(header["STTXT"], "MIAR")
        XCTAssertEqual(header["STATUSNR"], "2")

        let values = Dictionary(
            batch.values.compactMap { row -> (String, String)? in
                guard let id = row["ELEMENTNR"] ?? nil, let value = row["FELDWERT"] ?? nil else { return nil }
                return (id, value)
            },
            uniquingKeysWith: { first, _ in first }
        )
        XCTAssertEqual(values["TFM8-0010-1"], "4")
        XCTAssertEqual(values["TFM8-0010-2"], "7")
        XCTAssertEqual(values["TFM8-0010-9B"], "Anschlagpunkt korrodiert")
        XCTAssertNil(values["TFM8-0010-3"])
        XCTAssertEqual(values["TFM8-0000-1"], "")
        XCTAssertEqual(values["TFM8-0000-9B"], "")
        XCTAssertFalse(values.keys.contains { $0.hasPrefix("TFM2") })

        let pdf = try XCTUnwrap(batch.documents.first)
        XCTAssertEqual(pdf.metadata["ELEMENTNR"], "TFM8-pdf")
        XCTAssertEqual(pdf.metadata["DMS_CONTENTTYPE"], "D_TFM_Wartung")
        XCTAssertEqual(pdf.metadata["DMS_DOCID"], "TFM006")
    }

    /// A draft cannot smuggle in an out-of-service status the form never offers.
    func testUploadIgnoresOutOfServiceFlagOnDraft() throws {
        let source = try makeSummary()
        var draft = makeDraft(source: source)
        draft.isOutOfOperation = true
        draft.outOfOperationComment = "Gesperrt"

        let batch = try SAPEquipmentInspectionUploadBuilder.build(
            workItem: makeWorkItem(draft: draft),
            source: source,
            syncUserID: "S50828",
            photoData: [:]
        )

        let status = try XCTUnwrap(batch.values.first { ($0["ELEMENTNR"] ?? nil) == "TFM8-0000-1" })
        XCTAssertEqual(status["FELDWERT"], "")
        let comment = try XCTUnwrap(batch.values.first { ($0["ELEMENTNR"] ?? nil) == "TFM8-0000-9B" })
        XCTAssertEqual(comment["FELDWERT"], "")
        XCTAssertEqual(batch.headers.first?["STTXT"], "MIAR")
    }

    // MARK: - Demo

    func testDemoDataContainsARoofSystemInspection() {
        let notification = MockFacilityData.sapNotifications.first { $0.id == "4710000048" }
        XCTAssertEqual(notification?.equipmentInspectionForm, .roofSystem)
        let items = ElevatorInspectionDecoder.decodeItems(from: notification?.rawPayloadJSON ?? "")
        XCTAssertEqual(items.count, 4)
    }

    // MARK: - Helpers

    @MainActor
    private func makeStore() -> OfflineWorkStore {
        OfflineWorkStore(repository: InMemoryOfflineWorkRepository(), workerID: "S50828")
    }

    private func makeDraft(source: SAPNotificationSummary) -> ElevatorInspectionDraftPayload {
        ElevatorInspectionDraftPayload(
            notificationID: source.id,
            performedOn: Date(timeIntervalSince1970: 1_773_489_600),
            elementValues: ["TFM8-0010-1": "4", "TFM8-0010-2": "7"],
            comments: ["TFM8-0010-9B": "Anschlagpunkt korrodiert"],
            materialFlags: ["TFM8-0010-3": true],
            pdfDocumentID: "PDF-1",
            pdfBytes: Data("PDF".utf8),
            outgoingProcessID: "PROC-1",
            isClosedLocally: true,
            closingSystemStatus: "MIAR",
            formCode: "TFM8"
        )
    }

    private func makeWorkItem(draft: ElevatorInspectionDraftPayload) -> OfflineWorkItem {
        OfflineWorkItem(
            id: UUID(),
            workerID: "S50828",
            type: .elevatorInspection,
            status: .pendingSynchronization,
            payload: .elevatorInspection(draft),
            createdAt: .now,
            updatedAt: .now,
            syncError: nil
        )
    }

    private func makeSummary(formNumber: String? = "TFM8") throws -> SAPNotificationSummary {
        var payload: [String: Any] = [
            "MANDT": "100",
            "QMNUM": "4710000048",
            "QMART": "I1",
            "USTXT": "OPEN",
            "T_PLPOD": [
                [
                    "USR00": "POSITION", "STEUS": "TFM8", "VORNR": "0010",
                    "LTXA1": "Anschlagpunkte", "LTXA2": "",
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
            id: "4710000048",
            client: "100",
            title: "Dachanlage",
            functionalLocationID: "FL-8",
            functionalLocationName: "Dachanlage Nord",
            equipmentID: "EQ-100048",
            startDate: "20260914",
            endDate: "20260914",
            systemStatus: "MMAB",
            userStatus: "OPEN",
            rawPayloadJSON: try XCTUnwrap(String(data: data, encoding: .utf8))
        )
    }
}
