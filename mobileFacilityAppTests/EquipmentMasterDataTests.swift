import Foundation
import XCTest
@testable import mobileFacilityApp

/// The editable class-characteristics header of the shared equipment
/// inspection. Every expectation is traced to the legacy
/// `HeaderFormBuilder.js` (`_buildHeaderForm`, `onChangeHeader`,
/// `validateMasterData`, `checkMasterDataChange`, `_updateClobData`,
/// `runSetMasterdata4Header`) and the `Vorschlag` popover.
final class EquipmentMasterDataTests: XCTestCase {

    // MARK: - Decoding and controls

    func testDecoderBuildsTheLegacyControlsAndOrdersSpecialValuesFirst() throws {
        let data = try XCTUnwrap(ElevatorAssetDataDecoder.decode(
            equipmentType: "TFMFSA",
            classDefinition: classDefinition,
            masterData: masterRecordPayload(values: [
                ("FSA_BAUJAHR", "19931209"),
                ("FSA_HERSTELLER", "Hersteller A"),
                ("FSA_EXTRAS", "A"),
                ("FSA_EXTRAS", "B"),
                ("FSA_EXTRAS", "A")
            ])
        ))
        let byName = Dictionary(uniqueKeysWithValues: data.characteristics.map { ($0.name, $0) })

        XCTAssertEqual(byName["FSA_BAUJAHR"]?.control, .date)
        XCTAssertEqual(byName["FSA_HERSTELLER"]?.control, .singleSelect)
        XCTAssertEqual(byName["FSA_EXTRAS"]?.control, .multiSelect)
        XCTAssertEqual(byName["FSA_ANZAHL"]?.control, .number)
        XCTAssertEqual(byName["FSA_BEMERKUNG"]?.control, .text)
        XCTAssertEqual(byName["FSA_IDNUMMER"]?.isLockedIdentifier, true)

        XCTAssertEqual(
            byName["FSA_HERSTELLER"]?.selectableOptions.map(\.text),
            ["Pflege durch Admin", "nicht bekannt", "Hersteller A"]
        )
        XCTAssertEqual(byName["FSA_HERSTELLER"]?.offersProposal, true)
        XCTAssertEqual(data.values["FSA_EXTRAS"], "A;B", "`_getHeaderValue` joins unique values")
        XCTAssertTrue(data.isEditable)
    }

    func testPassengerAndFreightElevatorsStayReadOnly() {
        XCTAssertFalse(ElevatorAssetData(equipmentType: "TFMPERS", className: "", characteristics: [], values: [:]).isEditable)
        XCTAssertFalse(ElevatorAssetData(equipmentType: "tfmlast", className: "", characteristics: [], values: [:]).isEditable)
        XCTAssertTrue(ElevatorAssetData(equipmentType: "TFMBEFAHR", className: "", characteristics: [], values: [:]).isEditable)
    }

    func testInitialValuesStoreDropdownKeysAndDropTheUndefinedMarker() throws {
        let data = try XCTUnwrap(ElevatorAssetDataDecoder.decode(
            equipmentType: "TFMFSA",
            classDefinition: classDefinition,
            masterData: masterRecordPayload(values: [
                ("FSA_HERSTELLER", "Hersteller A"),
                ("FSA_BEMERKUNG", "?")
            ])
        ))
        let values = EquipmentMasterDataRules.initialValues(for: data)
        XCTAssertEqual(values["FSA_HERSTELLER"], "HERST_A")
        XCTAssertEqual(values["FSA_BEMERKUNG"], "")
    }

    func testDisplayValuesUseOptionTextsAndGermanDates() throws {
        let data = try XCTUnwrap(ElevatorAssetDataDecoder.decode(
            equipmentType: "TFMFSA", classDefinition: classDefinition, masterData: masterRecordPayload(values: [])
        ))
        let byName = Dictionary(uniqueKeysWithValues: data.characteristics.map { ($0.name, $0) })
        XCTAssertEqual(EquipmentMasterDataRules.displayValue(for: try XCTUnwrap(byName["FSA_BAUJAHR"]), value: "19931209"), "09.12.1993")
        XCTAssertEqual(EquipmentMasterDataRules.displayValue(for: try XCTUnwrap(byName["FSA_HERSTELLER"]), value: "HERST_A"), "Hersteller A")
        XCTAssertEqual(EquipmentMasterDataRules.displayValue(for: try XCTUnwrap(byName["FSA_EXTRAS"]), value: "A;B"), "Extra A; Extra B")
    }

    func testTextIsUpperCasedAndLimitedUnlessCaseSensitive() {
        let upper = characteristic(name: "T", format: "CHAR", digits: 4)
        XCTAssertEqual(EquipmentMasterDataRules.normalizedText("abcdef", for: upper), "ABCD")
        var keep = upper
        keep.isCaseSensitive = true
        XCTAssertEqual(EquipmentMasterDataRules.normalizedText("abc", for: keep), "abc")
        XCTAssertEqual(EquipmentMasterDataRules.normalizedNumber("12,50x"), "12.50")
    }

    // MARK: - Validation

    func testDropdownsNeedAValueAndAdminNeedsAProposal() throws {
        let data = try XCTUnwrap(ElevatorAssetDataDecoder.decode(
            equipmentType: "TFMFSA", classDefinition: classDefinition, masterData: masterRecordPayload(values: [])
        ))
        let characteristics = data.characteristics
        var values = [
            "FSA_HERSTELLER": "", "FSA_EXTRAS": "A", "FSA_BAUJAHR": "", "FSA_ANZAHL": "3",
            "FSA_BEMERKUNG": "", "FSA_IDNUMMER": ""
        ]

        var invalid = EquipmentMasterDataRules.invalidCharacteristicIDs(
            characteristics: characteristics, values: values, proposals: [:],
            isEditable: { !$0.isLockedIdentifier }
        )
        XCTAssertEqual(invalid, ["FSA_HERSTELLER", "FSA_BEMERKUNG"],
                       "empty dropdown always fails, required text fails, locked ID number is skipped")

        values["FSA_HERSTELLER"] = EquipmentMasterDataCatalog.adminKey
        values["FSA_BEMERKUNG"] = "OK"
        invalid = EquipmentMasterDataRules.invalidCharacteristicIDs(
            characteristics: characteristics, values: values, proposals: [:],
            isEditable: { !$0.isLockedIdentifier }
        )
        XCTAssertEqual(invalid, ["FSA_HERSTELLER"])

        invalid = EquipmentMasterDataRules.invalidCharacteristicIDs(
            characteristics: characteristics, values: values, proposals: ["FSA_HERSTELLER": "Neuer Hersteller"],
            isEditable: { !$0.isLockedIdentifier }
        )
        XCTAssertTrue(invalid.isEmpty)
    }

    func testRequiredNumberMustFitItsTemplate() {
        let number = characteristic(name: "N", format: "NUM", digits: 4, template: "__.__", isRequired: true)
        XCTAssertTrue(EquipmentMasterDataRules.isValidNumber("12.5", for: number))
        XCTAssertFalse(EquipmentMasterDataRules.isValidNumber("123.5", for: number))
    }

    // MARK: - Master-data write

    func testUnchangedValuesProduceNoMasterDataWrite() throws {
        let record = try makeRecord(equipmentID: "EQ-1")
        let original = ["FSA_HERSTELLER": "HERST_A"]
        XCTAssertNil(EquipmentMasterDataRules.updatedMasterPayloadJSON(
            record: record, characteristics: [], original: original,
            current: ["FSA_HERSTELLER": "herst_a"], client: "100"
        ), "`checkMasterDataChange` compares upper-cased")
    }

    func testChangedValuesReplaceTheClassValuesAndSetTheClient() throws {
        let record = try makeRecord(equipmentID: "EQ-1")
        let data = try XCTUnwrap(ElevatorAssetDataDecoder.decode(
            equipmentType: "TFMFSA", classDefinition: classDefinition, masterData: masterRecordPayload(values: [])
        ))
        let json = try XCTUnwrap(EquipmentMasterDataRules.updatedMasterPayloadJSON(
            record: record,
            characteristics: data.characteristics,
            original: ["FSA_HERSTELLER": "HERST_A", "FSA_BAUJAHR": "19931209"],
            current: ["FSA_HERSTELLER": "HERST_B", "FSA_BAUJAHR": "19931209", "FSA_EXTRAS": "A;B"],
            client: "100"
        ))
        let payload = try XCTUnwrap(try JSONSerialization.jsonObject(with: Data(json.utf8)) as? [String: Any])
        XCTAssertEqual(payload["MANDT_TO"] as? String, "100")

        let classes = try XCTUnwrap(payload["T_CLASS_EQ"] as? [[String: Any]])
        let other = try XCTUnwrap(classes.first { $0["CLASS"] as? String == "OTHER" })
        XCTAssertEqual((other["T_CLOBJDAT"] as? [[String: Any]])?.count, 1, "other classes stay untouched")

        let rows = try XCTUnwrap(classes.first { $0["CLASS"] as? String == "TFMFSA" }?["T_CLOBJDAT"] as? [[String: Any]])
        let manufacturer = rows.filter { $0["ATNAM"] as? String == "FSA_HERSTELLER" }
        XCTAssertEqual(manufacturer.map { $0["AUSP1"] as? String }, ["HERST_B"])
        XCTAssertEqual(manufacturer.first?["SMBEZ"] as? String, "FSA Hersteller")
        XCTAssertEqual(rows.filter { $0["ATNAM"] as? String == "FSA_EXTRAS" }.count, 2)
        XCTAssertEqual(rows.filter { $0["ATNAM"] as? String == "FSA_BAUJAHR" }.first?["AUSP1"] as? String, "19931209")
    }

    // MARK: - View model

    @MainActor
    func testHoldOpenSystemHeaderIsEditableAndAdminAsksForAProposal() async throws {
        let model = try await makeDemoModel()
        XCTAssertTrue(model.isMasterDataRecordEditable)
        let manufacturer = try XCTUnwrap(model.elevatorAssetCharacteristics.first { $0.name == "DEMO_FSA_MANUFACTURER" })
        XCTAssertEqual(model.masterDataSelection(for: manufacturer), ["HERST_A"])
        XCTAssertFalse(model.isProposalAvailable(for: manufacturer))

        model.selectMasterDataOption(EquipmentMasterDataCatalog.adminKey, for: manufacturer)
        XCTAssertEqual(model.proposalCharacteristicID, "DEMO_FSA_MANUFACTURER")
        XCTAssertTrue(model.isProposalAvailable(for: manufacturer))

        model.saveProposal("  Neuer Hersteller  ", for: manufacturer)
        XCTAssertEqual(model.proposal(for: manufacturer), "Neuer Hersteller")
        XCTAssertNil(model.proposalCharacteristicID)

        model.selectMasterDataOption("HERST_B", for: manufacturer)
        XCTAssertEqual(model.proposal(for: manufacturer), "", "`deleteVorschlag` when admin is left")
    }

    @MainActor
    func testLastProposalIsSuggestedButNotPrefilled() async throws {
        let store = OfflineWorkStore(repository: InMemoryOfflineWorkRepository(), workerID: "S50828")
        let first = try await makeDemoModel(store: store)
        let manufacturer = try XCTUnwrap(first.elevatorAssetCharacteristics.first { $0.name == "DEMO_FSA_MANUFACTURER" })
        XCTAssertNil(first.lastProposal(for: manufacturer))

        first.selectMasterDataOption(EquipmentMasterDataCatalog.adminKey, for: manufacturer)
        first.saveProposal("Hersteller X", for: manufacturer)
        XCTAssertEqual(first.lastProposal(for: manufacturer), "Hersteller X", "shown before the draft is saved")
        await first.save(closed: false)
        XCTAssertEqual(first.proposal(for: manufacturer), "Hersteller X")

        // Another inspection of the same equipment sees it only as the suggestion.
        let draft = try XCTUnwrap(store.elevatorInspection(notificationID: "4710000036"))
        var other = draft
        other.notificationID = "4710000099"
        other.masterData?.proposals = [:]
        _ = try await store.saveElevatorInspection(other)
        let otherSummary = try XCTUnwrap(MockFacilityData.sapNotifications.first { $0.id == "4710000036" })
        let otherModel = EquipmentInspectionViewModel(
            detail: SAPNotificationDetail(summary: SAPNotificationSummary(
                id: "4710000099", client: otherSummary.client, title: otherSummary.title,
                functionalLocationID: otherSummary.functionalLocationID,
                functionalLocationName: otherSummary.functionalLocationName,
                equipmentID: otherSummary.equipmentID,
                startDate: otherSummary.startDate, endDate: otherSummary.endDate,
                systemStatus: otherSummary.systemStatus, userStatus: otherSummary.userStatus,
                rawPayloadJSON: otherSummary.rawPayloadJSON
            )),
            offlineWorkStore: store,
            photoStore: InMemoryPhotoAttachmentStore(),
            elevatorAssetDataProvider: DemoElevatorAssetDataProvider()
        )
        await otherModel.load()
        XCTAssertEqual(otherModel.proposal(for: manufacturer), "")
        XCTAssertEqual(otherModel.lastProposal(for: manufacturer), "Hersteller X")
    }

    @MainActor
    func testElevatorHeaderStaysReadOnly() async throws {
        let summary = try XCTUnwrap(MockFacilityData.sapNotifications.first { $0.id == "4710000012" })
        let model = EquipmentInspectionViewModel(
            detail: SAPNotificationDetail(summary: summary),
            offlineWorkStore: OfflineWorkStore(repository: InMemoryOfflineWorkRepository(), workerID: "S50828"),
            photoStore: InMemoryPhotoAttachmentStore(),
            elevatorAssetDataProvider: DemoElevatorAssetDataProvider()
        )
        await model.load()
        XCTAssertFalse(model.isMasterDataRecordEditable)
        let first = try XCTUnwrap(model.elevatorAssetCharacteristics.first)
        XCTAssertFalse(model.canEditCharacteristic(first))
    }

    @MainActor
    func testClosingIsBlockedByAnEmptyDropdownAndSavesTheChangedRecord() async throws {
        let model = try await makeDemoModel()
        for item in model.items { model.results[item.id] = "1" }

        model.handleCloseTapped()
        XCTAssertEqual(model.masterDataValidationErrors, ["DEMO_FSA_MANUAL_RELEASE"])
        XCTAssertFalse(model.isCloseConfirmationPresented)

        let manualRelease = try XCTUnwrap(model.elevatorAssetCharacteristics.first { $0.name == "DEMO_FSA_MANUAL_RELEASE" })
        let buildDate = try XCTUnwrap(model.elevatorAssetCharacteristics.first { $0.name == "DEMO_FSA_BUILD_DATE" })
        model.selectMasterDataOption("X", for: manualRelease)
        model.setMasterDataDate(
            try XCTUnwrap(EquipmentMasterDataRules.date(fromSAP: "20000101")),
            for: buildDate
        )
        XCTAssertTrue(model.masterDataValidationErrors.isEmpty)

        model.handleCloseTapped()
        XCTAssertTrue(model.isCloseConfirmationPresented)
        await model.confirmClose()

        let draft = try XCTUnwrap(model.offlineWorkStore.elevatorInspection(notificationID: "4710000036"))
        let masterData = try XCTUnwrap(draft.masterData)
        XCTAssertEqual(masterData.values["DEMO_FSA_BUILD_DATE"], "20000101")
        XCTAssertEqual(masterData.equipmentID, "EQ-100036")
        XCTAssertEqual(masterData.headerValues.count, 5)
        XCTAssertEqual(
            masterData.headerValues.first { $0.elementID == "DEMO_FSA_MANUAL_RELEASE" }?.value, "X"
        )
        let updated = try XCTUnwrap(masterData.updatedMasterPayloadJSON)
        XCTAssertTrue(updated.contains("20000101"))
    }

    @MainActor
    func testTemporarySaveKeepsHeaderEditsWithoutAMasterDataWrite() async throws {
        let store = OfflineWorkStore(repository: InMemoryOfflineWorkRepository(), workerID: "S50828")
        let model = try await makeDemoModel(store: store)
        let type = try XCTUnwrap(model.elevatorAssetCharacteristics.first { $0.name == "DEMO_FSA_TYPE" })
        model.selectMasterDataOption("RSZ2", for: type)
        await model.save(closed: false)

        let draft = try XCTUnwrap(store.elevatorInspection(notificationID: "4710000036"))
        XCTAssertEqual(draft.masterData?.values["DEMO_FSA_TYPE"], "RSZ2")
        XCTAssertNil(draft.masterData?.updatedMasterPayloadJSON)

        let reopened = try await makeDemoModel(store: store)
        XCTAssertEqual(reopened.masterDataSelection(for: type), ["RSZ2"])
    }

    // MARK: - Upload

    func testUploadPostsHeaderValuesProposalsAndTheEquipmentRecord() throws {
        let batch = try buildBatch(equipmentID: "EQ-100036", locationID: "")

        let header = try XCTUnwrap(batch.values.first { ($0["ELEMENTNR"] ?? nil) == "FSA_HERSTELLER" })
        XCTAssertEqual(header["FELDWERT"] ?? nil, EquipmentMasterDataCatalog.adminKey)
        XCTAssertEqual(header["FELDBEZEICHNUNG"] ?? nil, "FSA Hersteller")

        let proposal = try XCTUnwrap(batch.proposals.first)
        XCTAssertEqual(proposal["ELEMENTNR"] ?? nil, "FSA_HERSTELLER")
        XCTAssertEqual(proposal["FELDWERT"] ?? nil, "Neuer Hersteller")
        XCTAssertEqual(proposal["VORGANGSNR"] ?? nil, "PROC-1")
        XCTAssertEqual(proposal["EQUNR"] ?? nil, "EQ-100036")
        XCTAssertEqual(proposal["STRNO"] ?? nil, "")
        XCTAssertEqual(proposal["AKTIV"] ?? nil, "X")

        let equipment = try XCTUnwrap(batch.equipment.first)
        XCTAssertEqual(equipment["EQUNR"] ?? nil, "EQ-100036")
        XCTAssertEqual(batch.equipmentIDs, ["EQ-100036"])
        XCTAssertTrue(batch.functionalLocations.isEmpty)
        let feldwert = try XCTUnwrap(equipment["FELDWERT"] ?? nil)
        let decoded = try XCTUnwrap(SAPLegacyDataExchangeCodec.decodedFeldwertObject(feldwert))
        XCTAssertEqual(decoded["MANDT_TO"] as? String, "100")
    }

    func testTechnicalPlaceHeaderWritesTheLocationRecord() throws {
        let batch = try buildBatch(equipmentID: "", locationID: "FL-6")
        XCTAssertTrue(batch.equipment.isEmpty)
        XCTAssertEqual(batch.functionalLocations.first?["STRNO"] ?? nil, "FL-6")
        XCTAssertEqual(batch.proposals.first?["STRNO"] ?? nil, "FL-6")
    }

    func testOutgoingStoreStagesProposalsAndLocationsOnce() async throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let repository = try SQLiteSAPDataCacheRepository(databaseURL: directory.appendingPathComponent("cache.sqlite"))
        let batch = try buildBatch(equipmentID: "", locationID: "FL-6")

        for _ in 0..<2 {
            try await repository.replaceNotificationOutgoingRows(
                processIDs: batch.processIDs, equipmentIDs: batch.equipmentIDs,
                headers: batch.headers, values: batch.values, documents: [],
                equipment: batch.equipment,
                functionalLocations: batch.functionalLocations,
                proposals: batch.proposals
            )
        }

        let proposalCount = try await repository.legacyRowCount(in: "TO_T0211")
        let locationCount = try await repository.legacyRowCount(in: "TO_T0265")
        XCTAssertEqual(proposalCount, 1)
        XCTAssertEqual(locationCount, 1)
    }

    // MARK: - Helpers

    private var classDefinition: [String: Any] {
        func values(_ name: String, _ entries: [(String, String)]) -> [[String: Any]] {
            entries.map { ["ATNAM": name, "ATWRT": $0.0, "ATWTB": $0.1] }
        }
        return [
            "CLASS": "TFMFSA",
            "TXTBZ": "Feststellanlage",
            "T_CHARA": [
                ["POSNR": "1", "ATNAM": "FSA_BAUJAHR", "ATBEZ": "FSA Baujahr", "ATFOR": "DATE", "ANZST": "8", "T_CHARVAL": []],
                [
                    "POSNR": "2", "ATNAM": "FSA_HERSTELLER", "ATBEZ": "FSA Hersteller", "ATFOR": "CHAR",
                    "ATEIN": "X", "ANZST": "30",
                    "T_CHARVAL": values("FSA_HERSTELLER", [
                        ("PFLEGE DURCH ADMIN", "Pflege durch Admin"),
                        ("HERST_A", "Hersteller A"),
                        ("NICHT VORHN.", "nicht bekannt")
                    ])
                ],
                [
                    "POSNR": "3", "ATNAM": "FSA_EXTRAS", "ATBEZ": "Extras", "ATFOR": "CHAR",
                    "T_CHARVAL": values("FSA_EXTRAS", [("A", "Extra A"), ("B", "Extra B")])
                ],
                ["POSNR": "4", "ATNAM": "FSA_ANZAHL", "ATBEZ": "Anzahl", "ATFOR": "NUM", "ANZST": "4", "ATSCH": "____", "T_CHARVAL": []],
                ["POSNR": "5", "ATNAM": "FSA_BEMERKUNG", "ATBEZ": "Bemerkung", "ATFOR": "CHAR", "ATERF": "X", "T_CHARVAL": []],
                [
                    "POSNR": "6", "ATNAM": "FSA_IDNUMMER", "ATBEZ": "ID", "ATFOR": "CHAR", "ATEIN": "X",
                    "T_CHARVAL": values("FSA_IDNUMMER", [("1", "1")])
                ]
            ]
        ]
    }

    private func masterRecordPayload(values: [(String, String)], classKey: String = "T_CLASS_EQ") -> [String: Any] {
        [
            "EQUNR_TO": "EQ-1",
            classKey: [
                ["CLASS": "OTHER", "T_CLOBJDAT": [["ATNAM": "X", "AUSP1": "1"]]],
                ["CLASS": "TFMFSA", "T_CLOBJDAT": values.map { ["ATNAM": $0.0, "AUSP1": $0.1] }]
            ]
        ]
    }

    private func makeRecord(equipmentID: String) throws -> EquipmentMasterRecord {
        let payload = masterRecordPayload(
            values: [("FSA_HERSTELLER", "HERST_A"), ("FSA_BAUJAHR", "19931209")],
            classKey: equipmentID.isEmpty ? "T_CLASS_TP" : "T_CLASS_EQ"
        )
        let data = try JSONSerialization.data(withJSONObject: payload, options: [.sortedKeys])
        return EquipmentMasterRecord(
            equipmentID: equipmentID,
            functionalLocationID: equipmentID.isEmpty ? "FL-6" : "",
            className: "TFMFSA",
            payloadJSON: try XCTUnwrap(String(data: data, encoding: .utf8))
        )
    }

    private func characteristic(
        name: String, format: String, digits: Int = 0, template: String = "", isRequired: Bool = false
    ) -> ElevatorAssetCharacteristic {
        ElevatorAssetCharacteristic(
            position: 1, name: name, title: name, unit: "",
            isRequired: isRequired, isNumeric: format == "NUM", allowsMultipleValues: false, options: [],
            format: format, digits: digits, template: template
        )
    }

    @MainActor
    private func makeDemoModel(
        store: OfflineWorkStore? = nil
    ) async throws -> EquipmentInspectionViewModel {
        let summary = try XCTUnwrap(MockFacilityData.sapNotifications.first { $0.id == "4710000036" })
        let model = EquipmentInspectionViewModel(
            detail: SAPNotificationDetail(summary: summary),
            offlineWorkStore: store ?? OfflineWorkStore(repository: InMemoryOfflineWorkRepository(), workerID: "S50828"),
            photoStore: InMemoryPhotoAttachmentStore(),
            elevatorAssetDataProvider: DemoElevatorAssetDataProvider()
        )
        await model.load()
        return model
    }

    private func buildBatch(equipmentID: String, locationID: String) throws -> SAPNotificationOutgoingBatch {
        let source = try XCTUnwrap(MockFacilityData.sapNotifications.first { $0.id == "4710000036" })
        let record = try makeRecord(equipmentID: equipmentID)
        let draft = ElevatorInspectionDraftPayload(
            notificationID: source.id,
            elementValues: Dictionary(uniqueKeysWithValues:
                ElevatorInspectionDecoder.decodeItems(from: source.rawPayloadJSON).map { ($0.resultElementID, "1") }
            ),
            pdfDocumentID: "PDF-1",
            pdfBytes: Data("PDF".utf8),
            outgoingProcessID: "PROC-1",
            isClosedLocally: true,
            formCode: "TFM6",
            masterData: EquipmentMasterDataDraft(
                values: ["FSA_HERSTELLER": EquipmentMasterDataCatalog.adminKey],
                proposals: ["FSA_HERSTELLER": "Neuer Hersteller"],
                headerValues: [
                    EquipmentMasterDataHeaderValue(
                        elementID: "FSA_HERSTELLER",
                        label: "FSA Hersteller",
                        value: EquipmentMasterDataCatalog.adminKey
                    )
                ],
                equipmentID: equipmentID,
                functionalLocationID: locationID,
                updatedMasterPayloadJSON: EquipmentMasterDataRules.updatedMasterPayloadJSON(
                    record: record, characteristics: [],
                    original: ["FSA_HERSTELLER": "HERST_A"],
                    current: ["FSA_HERSTELLER": EquipmentMasterDataCatalog.adminKey],
                    client: source.client
                )
            )
        )
        let workItem = OfflineWorkItem(
            id: UUID(), workerID: "S50828", type: .elevatorInspection, status: .pendingSynchronization,
            payload: .elevatorInspection(draft), createdAt: .now, updatedAt: .now, syncError: nil
        )
        return try SAPEquipmentInspectionUploadBuilder.build(
            workItem: workItem, source: source, syncUserID: "S50828", photoData: [:]
        )
    }
}
