import Foundation
import XCTest
@testable import mobileFacilityApp

final class ElevatorInspectionTests: XCTestCase {

    // MARK: - 1. Routing & Detection

    func testTFM2DetectionByFormnr() throws {
        let payload: [String: Any] = [
            "MANDT": "100",
            "QMNUM": "4710000012",
            "QMART": "I1",
            "FORMNR": "TFM2",
            "T_PLPOD": []
        ]
        let data = try JSONSerialization.data(withJSONObject: payload)
        let summary = SAPNotificationSummary(
            id: "4710000012",
            client: "100",
            title: "Aufzugsprüfung",
            functionalLocationID: "FL-1",
            functionalLocationName: "Aufzug A",
            equipmentID: "EQ-100010",
            startDate: "20260914",
            endDate: "20260914",
            systemStatus: "MMAB",
            userStatus: "OPEN",
            rawPayloadJSON: String(data: data, encoding: .utf8)!
        )
        XCTAssertTrue(summary.isTFM2ElevatorInspection)

        let detail = SAPNotificationDetail(summary: summary)
        XCTAssertTrue(detail.isTFM2ElevatorInspection)
    }

    func testTFM2DetectionBySteusInPositions() throws {
        let payload: [String: Any] = [
            "MANDT": "100",
            "QMNUM": "4710000013",
            "QMART": "I1",
            "T_PLPOD": [
                [
                    "USR00": "POSITION",
                    "STEUS": "TFM2",
                    "VORNR": "0010",
                    "LTXA1": "Triebwerksraum prüfen"
                ]
            ]
        ]
        let data = try JSONSerialization.data(withJSONObject: payload)
        let summary = SAPNotificationSummary(
            id: "4710000013",
            client: "100",
            title: "Aufzugsprüfung Position",
            functionalLocationID: "FL-1",
            functionalLocationName: "Aufzug B",
            equipmentID: "EQ-100011",
            startDate: "20260914",
            endDate: "20260914",
            systemStatus: "",
            userStatus: "",
            rawPayloadJSON: String(data: data, encoding: .utf8)!
        )
        XCTAssertTrue(summary.isTFM2ElevatorInspection)
    }

    func testNonTFM2NotificationIsNotDetectedAsElevatorInspection() throws {
        let payload: [String: Any] = [
            "MANDT": "100",
            "QMNUM": "4710000014",
            "QMART": "I1",
            "FORMNR": "TFM1",
            "T_PLPOD": [
                [
                    "USR00": "POSITION",
                    "STEUS": "TFM1",
                    "VORNR": "0010",
                    "LTXA1": "Tür prüfen"
                ]
            ]
        ]
        let data = try JSONSerialization.data(withJSONObject: payload)
        let summary = SAPNotificationSummary(
            id: "4710000014",
            client: "100",
            title: "Standard Prüfung",
            functionalLocationID: "FL-1",
            functionalLocationName: "Gebäude C",
            equipmentID: "",
            startDate: "20260914",
            endDate: "20260914",
            systemStatus: "",
            userStatus: "",
            rawPayloadJSON: String(data: data, encoding: .utf8)!
        )
        XCTAssertFalse(summary.isTFM2ElevatorInspection)
        let detail = SAPNotificationDetail(summary: summary)
        XCTAssertFalse(detail.isTFM2ElevatorInspection)
    }

    // MARK: - 2. Decoder Tests

    func testDecoderParsesTFM2PositionsWithAllProperties() {
        let positions: [[String: Any]] = [
            [
                "USR00": "POSITION",
                "STEUS": "TFM2",
                "VORNR": "0010",
                "LTXA1": "Triebwerksraum",
                "LTXA2": "Sauberkeit und Beleuchtung",
                "T_PROPS": [
                    [
                        "POSNR": "1",
                        "DFVAL": "1;2;3;4",
                        "DFVAL_TXT": "in Ordnung;Mangel;Geringfügig;Schwer"
                    ]
                ]
            ],
            [
                "USR00": "POSITION",
                "STEUS": "TFM2",
                "VORNR": "0020",
                "LTXA1": "Fahrkorb und Notruf",
                "LTXA2": "Funktion der Notrufeinrichtung testen",
                "T_PROPS": [
                    [
                        "POSNR": "1",
                        "DFVAL": "Nein;Ja",
                        "DFVAL_TXT": "Nein;Ja"
                    ],
                    [
                        "POSNR": "2",
                        "DFVAL": "1;8",
                        "DFVAL_TXT": "Behoben;Vor Ort erledigt"
                    ],
                    [
                        "POSNR": "3",
                        "DFVAL": "1;2",
                        "DFVAL_TXT": "Ja;Nein"
                    ],
                    [
                        "POSNR": "9B",
                        "DFVAL": ""
                    ]
                ]
            ]
        ]

        let items = ElevatorInspectionDecoder.decodeItems(fromRows: positions)
        XCTAssertEqual(items.count, 2)

        // Item 1: 0010
        XCTAssertEqual(items[0].vornr, "0010")
        XCTAssertEqual(items[0].title, "Triebwerksraum")
        XCTAssertEqual(items[0].information, "Sauberkeit und Beleuchtung")
        XCTAssertEqual(items[0].resultElementID, "TFM2-0010-1")
        XCTAssertNil(items[0].actionElementID)
        XCTAssertNil(items[0].materialElementID)
        XCTAssertFalse(items[0].isBinaryYesNo)
        XCTAssertEqual(items[0].resultOptions.count, 4)
        XCTAssertEqual(items[0].resultOptions[0].code, "1")
        XCTAssertEqual(items[0].resultOptions[0].text, "in Ordnung")

        // Item 2: 0020
        XCTAssertEqual(items[1].vornr, "0020")
        XCTAssertEqual(items[1].title, "Fahrkorb und Notruf")
        XCTAssertEqual(items[1].information, "Funktion der Notrufeinrichtung testen")
        XCTAssertEqual(items[1].resultElementID, "TFM2-0020-1")
        XCTAssertEqual(items[1].actionElementID, "TFM2-0020-2")
        XCTAssertEqual(items[1].materialElementID, "TFM2-0020-3")
        XCTAssertTrue(items[1].isBinaryYesNo)
        XCTAssertEqual(items[1].actionOptions.count, 2)
        XCTAssertEqual(items[1].commentElementID, "TFM2-0020-9B")
    }

    func testElevatorAssetDataDecoderBuildsReadOnlyClassification() throws {
        let classDefinition: [String: Any] = [
            "CLASS": "TFMPERS",
            "T_CHARA": [
                [
                    "POSNR": "1", "ATNAM": "ELEVATOR_STOPS", "ATBEZ": "Anzahl Haltestellen",
                    "ATFOR": "NUM", "MSEHI": "ST", "ATERF": "X"
                ],
                [
                    "POSNR": "2", "ATNAM": "ELEVATOR_FIRE", "ATBEZ": "Brandfallsteuerung vorhanden",
                    "ATEIN": "X", "T_CHARVAL": [
                        ["ATWRT": "X", "ATWTB": "Ja"],
                        ["ATWRT": "", "ATWTB": "Nein"]
                    ]
                ]
            ]
        ]
        let masterData: [String: Any] = [
            "T_CLASS_EQ": [[
                "CLASS": "TFMPERS",
                "T_CLOBJDAT": [
                    ["ATNAM": "ELEVATOR_STOPS", "AUSP1": "5"],
                    ["ATNAM": "ELEVATOR_FIRE", "AUSP1": "X"]
                ]
            ]]
        ]

        let data = try XCTUnwrap(ElevatorAssetDataDecoder.decode(
            equipmentType: "TFMPERS",
            classDefinition: classDefinition,
            masterData: masterData
        ))

        XCTAssertEqual(data.equipmentType, "TFMPERS")
        XCTAssertEqual(data.characteristics.map(\.name), ["ELEVATOR_STOPS", "ELEVATOR_FIRE"])
        XCTAssertTrue(data.characteristics[0].isNumeric)
        XCTAssertTrue(data.characteristics[0].isRequired)
        XCTAssertEqual(data.characteristics[1].options.first?.text, "Ja")
        XCTAssertEqual(data.values["ELEVATOR_STOPS"], "5")
        XCTAssertEqual(data.values["ELEVATOR_FIRE"], "X")
    }

    func testSQLiteCacheLoadsTFM2ClassificationAfterIncomingCommit() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let databaseURL = directory.appendingPathComponent("mtfm.db")
        defer { try? FileManager.default.removeItem(at: directory) }
        let repository = try SQLiteSAPDataCacheRepository(databaseURL: databaseURL, workerID: "technician-1")

        let notificationPayload = try SAPLegacyDataExchangeCodec.packedFeldwert([
            "FORMNR": "TFM2",
            "T_PLPOD": [["USR00": "POSITION", "STEUS": "TFM2", "VORNR": "0010"]]
        ])
        let classPayload = try SAPLegacyDataExchangeCodec.packedFeldwert([
            "CLASS": "ELEVATOR_CLASS",
            "T_CHARA": [[
                "POSNR": "1", "ATNAM": "ELEVATOR_STOPS", "ATBEZ": "Anzahl Haltestellen",
                "ATFOR": "NUM", "MSEHI": "ST"
            ]]
        ])
        let equipmentPayload = try SAPLegacyDataExchangeCodec.packedFeldwert([
            "EQART_TO": "TFMPERS",
            "T_CLASS_EQ": [[
                "CLASS": "ELEVATOR_CLASS",
                "T_CLOBJDAT": [["ATNAM": "ELEVATOR_STOPS", "AUSP1": "5"]]
            ]]
        ])

        try await repository.beginIncoming()
        try await repository.appendIncoming(.init(tables: [
            "T_0271": [[
                "MANDT": "100", "QMNUM": "N-TFM2-1", "QMART": "I1", "QMTXT": "Elevator inspection",
                "STTXT": "OSNO", "STRNO": "FL-1", "PLTXT": "Elevator A", "EQUNR": "EQ-1",
                "FELDWERT": notificationPayload
            ]],
            "T_0263": [[
                "MANDT": "100", "EQART": "TFMPERS", "CLASS": "ELEVATOR_CLASS", "FELDWERT": classPayload
            ]],
            "T_0266": [[
                "MANDT": "100", "STRNO": "FL-1", "EQUNR": "EQ-1", "FELDWERT": equipmentPayload
            ]]
        ], isLastPackage: true))

        let committed = try await repository.commitIncoming(sapWorkerID: "technician-1", refreshedAt: .now)
        XCTAssertTrue(committed.notifications.isEmpty, "The production store pages notifications rather than retaining a full snapshot.")
        let cacheSummary = try await repository.incomingCacheSummary()
        XCTAssertEqual(cacheSummary.notificationRowCount, 1)
        XCTAssertEqual(cacheSummary.actionableNotificationCount, 1)
        XCTAssertEqual(cacheSummary.elevatorInspectionCount, 1)

        let page = try await repository.loadNotifications(
            for: "technician-1",
            matching: "",
            structuralFilter: .empty,
            limit: 10,
            offset: 0
        )
        let notification = try XCTUnwrap(page.notifications.first)
        XCTAssertTrue(notification.isTFM2ElevatorInspection)

        let assetData = try await repository.loadElevatorAssetData(for: notification)
        XCTAssertEqual(assetData.equipmentType, "TFMPERS")
        XCTAssertEqual(assetData.characteristics.map(\.name), ["ELEVATOR_STOPS"])
        XCTAssertEqual(assetData.values["ELEVATOR_STOPS"], "5")
    }

    func testSQLiteCacheLoadsTFM2ClassificationWithArrayFeldwertAndAufzugClass() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let databaseURL = directory.appendingPathComponent("mtfm.db")
        defer { try? FileManager.default.removeItem(at: directory) }
        let repository = try SQLiteSAPDataCacheRepository(databaseURL: databaseURL, workerID: "technician-1")

        let notificationPayload = try SAPLegacyDataExchangeCodec.packedFeldwert([
            "FORMNR": "TFM2",
            "T_PLPOD": [["USR00": "POSITION", "STEUS": "TFM2", "VORNR": "0010"]]
        ])
        // Real SAP FROM_T0263 format: JSON array with class definition
        let classPayload = try SAPLegacyDataExchangeCodec.packedFeldwert([[
            "CLINT": 1087,
            "KLART": "003",
            "CLASS": "TFMAUFZUG",
            "EQART": "TFMPERS",
            "T_CHARA": [
                [
                    "POSNR": 1, "ATNAM": "TFMANZ_HALTESTELLEN", "ATBEZ": "Anzahl Haltestellen",
                    "ATFOR": "NUM", "MSEHI": "ST"
                ],
                [
                    "POSNR": 2, "ATNAM": "TFMAUFZUGSART", "ATBEZ": "Aufzugsart",
                    "ATFOR": "CHAR", "T_CHARVAL": [["ATWRT": "SEIL", "ATWTB": "Seil"]]
                ],
                [
                    "POSNR": 3, "ATNAM": "TFMBRANDFALLSTEUERUNG", "ATBEZ": "Brandfallsteuerung",
                    "ATFOR": "CHAR", "T_CHARVAL": [["ATWRT": "J", "ATWTB": "Ja"], ["ATWRT": "N", "ATWTB": "Nein"]]
                ],
                [
                    "POSNR": 4, "ATNAM": "TFMTRAGKRAFT", "ATBEZ": "Tragkraft",
                    "ATFOR": "NUM", "MSEHI": ""
                ]
            ]
        ]])
        // Real SAP FROM_T0265 format: Technical place / functional location
        let locationPayload = try SAPLegacyDataExchangeCodec.packedFeldwert([
            "STRNO": "DE-SAF-11152-10-460-002",
            "EQART_TO": "TFMPERS",
            "T_CLASS_TP": [
                [
                    "CLASS": "TFMAUFZUG",
                    "T_CLOBJDAT": [
                        ["POSNR": 1, "ATNAM": "TFMANZ_HALTESTELLEN", "AUSP1": "5"],
                        ["POSNR": 2, "ATNAM": "TFMAUFZUGSART", "AUSP1": "ROPE"],
                        ["POSNR": 3, "ATNAM": "TFMBRANDFALLSTEUERUNG", "AUSP1": "Yes"],
                        ["POSNR": 4, "ATNAM": "TFMTRAGKRAFT", "AUSP1": "1.005", "UNIT_T_EXT": "kg"]
                    ],
                    "T_BAPI_CHAR": [
                        ["NAME_CHAR": "TFMTRAGKRAFT", "UNIT": "KG", "UNIT_T_EXT": "kg"]
                    ],
                    "T_BAPI_CHAR_VAL": [
                        ["NAME_CHAR": "TFMAUFZUGSART", "CHAR_VALUE": "SEIL", "DESCR_CVAL": "ROPE"],
                        ["NAME_CHAR": "TFMBRANDFALLSTEUERUNG", "CHAR_VALUE": "J", "DESCR_CVAL": "Yes"]
                    ]
                ]
            ]
        ])

        try await repository.beginIncoming()
        try await repository.appendIncoming(.init(tables: [
            "T_0271": [[
                "MANDT": "100", "QMNUM": "N-TFM2-FL", "QMART": "I1", "QMTXT": "Elevator inspection FL",
                "STTXT": "OSNO", "STRNO": "DE-SAF-11152-10-460-002", "PLTXT": "Elevator Facility", "EQUNR": "",
                "FELDWERT": notificationPayload
            ]],
            "T_0263": [[
                "MANDT": "100", "EQART": "TFMPERS", "KLART": "003", "CLASS": "TFMAUFZUG", "FELDWERT": classPayload
            ]],
            "T_0265": [[
                "MANDT": "100", "STRNO": "DE-SAF-11152-10-460-002", "FELDWERT": locationPayload
            ]]
        ], isLastPackage: true))

        _ = try await repository.commitIncoming(sapWorkerID: "technician-1", refreshedAt: .now)

        let page = try await repository.loadNotifications(
            for: "technician-1",
            matching: "",
            structuralFilter: .empty,
            limit: 10,
            offset: 0
        )
        let notification = try XCTUnwrap(page.notifications.first)
        XCTAssertTrue(notification.isTFM2ElevatorInspection)

        let assetData = try await repository.loadElevatorAssetData(for: notification)
        XCTAssertEqual(assetData.equipmentType, "TFMPERS")
        XCTAssertEqual(assetData.className, "TFMAUFZUG")
        XCTAssertEqual(assetData.characteristics.count, 4)

        // Characteristics and values
        XCTAssertEqual(assetData.values["TFMANZ_HALTESTELLEN"], "5")
        XCTAssertEqual(assetData.values["TFMAUFZUGSART"], "ROPE")
        XCTAssertEqual(assetData.values["TFMBRANDFALLSTEUERUNG"], "Yes")
        XCTAssertEqual(assetData.values["TFMTRAGKRAFT"], "1.005")

        // Units fallback from master data
        let tragkraftChar = try XCTUnwrap(assetData.characteristics.first { $0.name == "TFMTRAGKRAFT" })
        XCTAssertEqual(tragkraftChar.unit, "kg")

        // Value options mapping through BAPI descriptions
        let aufzugsartChar = try XCTUnwrap(assetData.characteristics.first { $0.name == "TFMAUFZUGSART" })
        let ropeOption = aufzugsartChar.options.first { $0.code.caseInsensitiveCompare("ROPE") == .orderedSame }
        XCTAssertEqual(ropeOption?.text, "Seil")

        let brandfallChar = try XCTUnwrap(assetData.characteristics.first { $0.name == "TFMBRANDFALLSTEUERUNG" })
        let yesOption = brandfallChar.options.first { $0.code.caseInsensitiveCompare("Yes") == .orderedSame }
        XCTAssertEqual(yesOption?.text, "Ja")
    }

    // MARK: - 3. Defect Evaluation Logic

    func testDefectEvaluationRules() {
        // Code "1": normal
        XCTAssertFalse(ElevatorInspectionLogic.isDefective(resultCode: "1", actionCode: nil))
        XCTAssertFalse(ElevatorInspectionLogic.isDefective(resultCode: "1", actionCode: "8"))

        // Code "2": defect
        XCTAssertTrue(ElevatorInspectionLogic.isDefective(resultCode: "2", actionCode: nil))
        XCTAssertTrue(ElevatorInspectionLogic.isDefective(resultCode: "2", actionCode: "8"))

        // Code "4": defect
        XCTAssertTrue(ElevatorInspectionLogic.isDefective(resultCode: "4", actionCode: nil))
        XCTAssertTrue(ElevatorInspectionLogic.isDefective(resultCode: "4", actionCode: "8"))

        // Code "3": defect UNLESS action is "8"
        XCTAssertTrue(ElevatorInspectionLogic.isDefective(resultCode: "3", actionCode: nil))
        XCTAssertTrue(ElevatorInspectionLogic.isDefective(resultCode: "3", actionCode: "1"))
        XCTAssertTrue(ElevatorInspectionLogic.isDefective(resultCode: "3", actionCode: ""))
        XCTAssertFalse(ElevatorInspectionLogic.isDefective(resultCode: "3", actionCode: "8"))

        // Empty / nil
        XCTAssertFalse(ElevatorInspectionLogic.isDefective(resultCode: nil, actionCode: nil))
        XCTAssertFalse(ElevatorInspectionLogic.isDefective(resultCode: "", actionCode: nil))
    }

    func testHasAnyDefect() {
        let item1 = ElevatorInspectionItem(
            id: "TFM2-0010-1",
            vornr: "0010",
            steus: "TFM2",
            positionNumber: 1,
            title: "Item 1",
            information: "",
            resultElementID: "TFM2-0010-1",
            resultOptions: [
                ElevatorInspectionValueOption(code: "1", text: "OK"),
                ElevatorInspectionValueOption(code: "2", text: "Mangel")
            ],
            actionElementID: "TFM2-0010-2",
            actionOptions: [ElevatorInspectionValueOption(code: "8", text: "Resolved")],
            materialElementID: nil,
            commentElementID: "TFM2-0010-9B"
        )
        let item2 = ElevatorInspectionItem(
            id: "TFM2-0020-1",
            vornr: "0020",
            steus: "TFM2",
            positionNumber: 2,
            title: "Item 2",
            information: "",
            resultElementID: "TFM2-0020-1",
            resultOptions: [
                ElevatorInspectionValueOption(code: "1", text: "OK"),
                ElevatorInspectionValueOption(code: "2", text: "Mangel")
            ],
            actionElementID: nil,
            actionOptions: [],
            materialElementID: nil,
            commentElementID: "TFM2-0020-9B"
        )

        // All OK
        var values = ["TFM2-0010-1": "1", "TFM2-0020-1": "1"]
        XCTAssertFalse(ElevatorInspectionLogic.hasAnyDefect(items: [item1, item2], elementValues: values))

        // Item 2 defective
        values["TFM2-0020-1"] = "2"
        XCTAssertTrue(ElevatorInspectionLogic.hasAnyDefect(items: [item1, item2], elementValues: values))

        // Item 1 code 3 but action 8 -> NOT a defect
        values["TFM2-0010-1"] = "3"
        values["TFM2-0010-2"] = "8"
        values["TFM2-0020-1"] = "1"
        XCTAssertFalse(ElevatorInspectionLogic.hasAnyDefect(items: [item1, item2], elementValues: values))

        // Item 1 code 3 without action 8 -> Defect
        values["TFM2-0010-2"] = ""
        XCTAssertTrue(ElevatorInspectionLogic.hasAnyDefect(items: [item1, item2], elementValues: values))
    }

    // MARK: - 4. All Good Behavior

    func testAllGoodSetsOnlyBlankItemsAndPreservesExistingValues() {
        let item1 = ElevatorInspectionItem(
            id: "TFM2-0010-1",
            vornr: "0010",
            steus: "TFM2",
            positionNumber: 1,
            title: "Item 1",
            information: "",
            resultElementID: "TFM2-0010-1",
            resultOptions: [ElevatorInspectionValueOption(code: "1", text: "OK")],
            actionElementID: nil,
            actionOptions: [],
            materialElementID: nil,
            commentElementID: "TFM2-0010-9B"
        )
        let item2 = ElevatorInspectionItem(
            id: "TFM2-0020-1",
            vornr: "0020",
            steus: "TFM2",
            positionNumber: 2,
            title: "Item 2",
            information: "",
            resultElementID: "TFM2-0020-1",
            resultOptions: [ElevatorInspectionValueOption(code: "1", text: "OK")],
            actionElementID: nil,
            actionOptions: [],
            materialElementID: nil,
            commentElementID: "TFM2-0020-9B"
        )

        XCTAssertTrue(ElevatorInspectionLogic.canPerformAllGood(items: [item1, item2]))

        // item 1 is already set to "2" (defect), item 2 is unset
        var values = ["TFM2-0010-1": "2"]
        ElevatorInspectionLogic.applyAllGood(items: [item1, item2], elementValues: &values)

        // item 1 must retain "2", item 2 must be set to "1"
        XCTAssertEqual(values["TFM2-0010-1"], "2")
        XCTAssertEqual(values["TFM2-0020-1"], "1")
    }

    func testAllGoodDisabledIfOption1Missing() {
        let item = ElevatorInspectionItem(
            id: "TFM2-0010-1",
            vornr: "0010",
            steus: "TFM2",
            positionNumber: 1,
            title: "Item 1",
            information: "",
            resultElementID: "TFM2-0010-1",
            resultOptions: [ElevatorInspectionValueOption(code: "A", text: "Option A")],
            actionElementID: nil,
            actionOptions: [],
            materialElementID: nil,
            commentElementID: "TFM2-0010-9B"
        )
        XCTAssertFalse(ElevatorInspectionLogic.canPerformAllGood(items: [item]))
    }

    // MARK: - 5. Validation

    func testValidationRequiresAllResultsAnswered() {
        let item1 = ElevatorInspectionItem(
            id: "TFM2-0010-1",
            vornr: "0010",
            steus: "TFM2",
            positionNumber: 1,
            title: "Item 1",
            information: "",
            resultElementID: "TFM2-0010-1",
            resultOptions: [],
            actionElementID: nil,
            actionOptions: [],
            materialElementID: nil,
            commentElementID: "TFM2-0010-9B"
        )
        let item2 = ElevatorInspectionItem(
            id: "TFM2-0020-1",
            vornr: "0020",
            steus: "TFM2",
            positionNumber: 2,
            title: "Item 2",
            information: "",
            resultElementID: "TFM2-0020-1",
            resultOptions: [],
            actionElementID: nil,
            actionOptions: [],
            materialElementID: nil,
            commentElementID: "TFM2-0020-9B"
        )

        // Empty values
        XCTAssertEqual(
            ElevatorInspectionLogic.unansweredItemIDs(items: [item1, item2], elementValues: [:]),
            Set(["TFM2-0010-1", "TFM2-0020-1"])
        )

        // Partially filled
        XCTAssertEqual(
            ElevatorInspectionLogic.unansweredItemIDs(items: [item1, item2], elementValues: ["TFM2-0010-1": "1"]),
            Set(["TFM2-0020-1"])
        )

        // Fully filled
        XCTAssertTrue(
            ElevatorInspectionLogic.unansweredItemIDs(
                items: [item1, item2],
                elementValues: ["TFM2-0010-1": "1", "TFM2-0020-1": "2"]
            ).isEmpty
        )
    }

    // MARK: - 6. Status Transitions

    func testUserStatusTransitions() {
        // Adding Mnot when defect is present
        let statusWithDefect = ElevatorInspectionLogic.updatedUserStatus(current: "FREI INAR", hasDefect: true)
        XCTAssertTrue(statusWithDefect.contains("Mnot"))
        XCTAssertTrue(statusWithDefect.contains("FREI"))

        // Ensuring no duplicate Mnot
        let statusAlreadyMnot = ElevatorInspectionLogic.updatedUserStatus(current: "FREI Mnot INAR", hasDefect: true)
        let countMnot = statusAlreadyMnot.components(separatedBy: " ").filter { $0 == "Mnot" }.count
        XCTAssertEqual(countMnot, 1)

        // Removing Mnot when no defects
        let statusWithoutDefect = ElevatorInspectionLogic.updatedUserStatus(current: "FREI Mnot INAR", hasDefect: false)
        XCTAssertFalse(statusWithoutDefect.contains("Mnot"))
        XCTAssertTrue(statusWithoutDefect.contains("FREI"))
        XCTAssertTrue(statusWithoutDefect.contains("INAR"))
    }

    // MARK: - 7. Offline Store Round-Trip

    @MainActor
    func testElevatorInspectionDraftPersistenceRoundTrip() async throws {
        let repo = InMemoryOfflineWorkRepository()
        let store = OfflineWorkStore(repository: repo, workerID: "S50828")

        let draft = ElevatorInspectionDraftPayload(
            notificationID: "4710000012",
            performedOn: Date(timeIntervalSince1970: 1773489600),
            elementValues: [
                "TFM2-0010-1": "1",
                "TFM2-0020-1": "2",
                "TFM2-0020-2": "1"
            ],
            comments: ["TFM2-0020": "Beleuchtung defekt"],
            materialFlags: ["TFM2-0020-3": true],
            photoAttachments: [
                NotificationPhotoAttachment(
                    localAttachmentID: "photo-1",
                    checklistItemID: "TFM2-0020-1",
                    sapElementID: "TFM2-0020-9B",
                    capturedAt: Date(timeIntervalSince1970: 1773489600),
                    sapDocumentID: "DOC-1"
                )
            ],
            pdfDocumentID: "PDF-DOC-1",
            pdfBytes: "Sample PDF".data(using: .utf8),
            outgoingProcessID: "PROC-1",
            isClosedLocally: true,
            closingSystemStatus: "MMAB",
            closingUserStatus: "FREI Mnot",
            statusNumber: "1"
        )

        let saved = try await store.saveElevatorInspection(draft)
        XCTAssertEqual(saved.type, .elevatorInspection)
        XCTAssertEqual(saved.status, .pendingSynchronization)

        let loaded = store.elevatorInspection(notificationID: "4710000012")
        XCTAssertNotNil(loaded)
        XCTAssertEqual(loaded?.notificationID, "4710000012")
        XCTAssertEqual(loaded?.elementValues["TFM2-0010-1"], "1")
        XCTAssertEqual(loaded?.elementValues["TFM2-0020-1"], "2")
        XCTAssertEqual(loaded?.comments["TFM2-0020"], "Beleuchtung defekt")
        XCTAssertEqual(loaded?.materialFlags["TFM2-0020-3"], true)
        XCTAssertEqual(loaded?.photoAttachments.count, 1)
        XCTAssertEqual(loaded?.pdfDocumentID, "PDF-DOC-1")
        XCTAssertEqual(loaded?.pdfBytes, "Sample PDF".data(using: .utf8))
        XCTAssertEqual(loaded?.isClosedLocally, true)
        XCTAssertEqual(loaded?.closingSystemStatus, "MMAB")
        XCTAssertEqual(loaded?.closingUserStatus, "FREI Mnot")

        // Deletion
        try await store.deleteElevatorInspection(notificationID: "4710000012")
        XCTAssertNil(store.elevatorInspection(notificationID: "4710000012"))
    }

    // MARK: - 8. Photo Limit Enforcement

    @MainActor
    func testPhotoLimitEnforcedAt20() async throws {
        let payload: [String: Any] = [
            "MANDT": "100",
            "QMNUM": "4710000012",
            "QMART": "I1",
            "FORMNR": "TFM2",
            "T_PLPOD": [
                [
                    "USR00": "POSITION",
                    "STEUS": "TFM2",
                    "VORNR": "0010",
                    "LTXA1": "Triebwerksraum",
                    "T_PROPS": [
                        ["POSNR": "1", "DFVAL": "1;2", "DFVAL_TXT": "OK;Defect"],
                        ["POSNR": "9B", "DFVAL": ""]
                    ]
                ]
            ]
        ]
        let data = try JSONSerialization.data(withJSONObject: payload)
        let summary = SAPNotificationSummary(
            id: "4710000012",
            client: "100",
            title: "Aufzugskontrolle",
            functionalLocationID: "FL-1",
            functionalLocationName: "Aufzug",
            equipmentID: "EQ-100010",
            startDate: "20260914",
            endDate: "20260914",
            systemStatus: "",
            userStatus: "",
            rawPayloadJSON: String(data: data, encoding: .utf8)!
        )
        let detail = SAPNotificationDetail(summary: summary)
        let repo = InMemoryOfflineWorkRepository()
        let workStore = OfflineWorkStore(repository: repo, workerID: "S50828")
        let photoStore = InMemoryPhotoAttachmentStore()

        let viewModel = EquipmentInspectionViewModel(
            detail: detail,
            offlineWorkStore: workStore,
            photoStore: photoStore
        )
        await viewModel.load()

        guard let item = viewModel.items.first else {
            XCTFail("Missing item")
            return
        }

        let jpeg = Data([0xFF, 0xD8, 0x01, 0x02, 0xFF, 0xD9])
        for _ in 0..<20 {
            await viewModel.addPhoto(jpegData: jpeg, to: item)
        }
        XCTAssertEqual(viewModel.photoAttachments.count, 20)

        // 21st photo
        await viewModel.addPhoto(jpegData: jpeg, to: item)
        XCTAssertEqual(viewModel.photoAttachments.count, 20)
        if case .photoLimitReached? = viewModel.feedback {
            // Expected
        } else {
            XCTFail("Expected photoLimitReached feedback")
        }
    }

    // MARK: - 9. PDF Generation

    func testPDFGenerationMatchesCordovaFormat() throws {
        let item1 = ElevatorInspectionItem(
            id: "TFM2-0010-1",
            vornr: "0010",
            steus: "TFM2",
            positionNumber: 1,
            title: "Triebwerksraum prüfen",
            information: "Prüfen ob alles sauber ist",
            resultElementID: "TFM2-0010-1",
            resultOptions: [
                ElevatorInspectionValueOption(code: "1", text: "in Ordnung"),
                ElevatorInspectionValueOption(code: "2", text: "Mangel")
            ],
            actionElementID: nil,
            actionOptions: [],
            materialElementID: nil,
            commentElementID: "TFM2-0010-9B"
        )
        let item2 = ElevatorInspectionItem(
            id: "TFM2-0020-1",
            vornr: "0020",
            steus: "TFM2",
            positionNumber: 2,
            title: "Fahrkorbbeleuchtung",
            information: "",
            resultElementID: "TFM2-0020-1",
            resultOptions: [
                ElevatorInspectionValueOption(code: "1", text: "in Ordnung"),
                ElevatorInspectionValueOption(code: "2", text: "Mangel")
            ],
            actionElementID: "TFM2-0020-2",
            actionOptions: [
                ElevatorInspectionValueOption(code: "1", text: "Behoben")
            ],
            materialElementID: "TFM2-0020-3",
            commentElementID: "TFM2-0020-9B"
        )

        let payload = ElevatorInspectionPDFPayload(
            notificationID: "4710000012",
            notificationTitle: "Aufzugskontrolle Personenaufzug",
            functionalLocation: "UN01-ST01-BG01-TECH-460-AUF1",
            equipmentID: "EQ-100010",
            equipmentName: "Aufzug Personen",
            locationCity: "Berlin",
            locationStreet: "Alexanderstr. 1",
            weGe: "WE 1 / GE 2",
            workerName: "Max Mustermann",
            workerID: "S50828",
            company: "XPN Facility",
            orgUnit: "FM",
            plant: "1501",
            performedAt: Date(timeIntervalSince1970: 1773489600),
            items: [item1, item2],
            results: ["TFM2-0010-1": "1", "TFM2-0020-1": "2"],
            actions: ["TFM2-0020-2": "1"],
            materials: ["TFM2-0020-3": true],
            notes: ["TFM2-0020-1": "Leuchtmittel getauscht"],
            hasMaterialColumn: true,
            assetCharacteristics: [
                ElevatorAssetCharacteristic(
                    position: 1,
                    name: "ELEVATOR_STOPS",
                    title: "Anzahl Haltestellen",
                    unit: "ST",
                    isRequired: false,
                    isNumeric: true,
                    allowsMultipleValues: false,
                    options: []
                )
            ],
            assetValues: ["ELEVATOR_STOPS": "5"]
        )

        let artifact = try ElevatorInspectionPDFRenderer.render(payload)
        XCTAssertFalse(artifact.data.isEmpty)
        let headerString = String(data: artifact.data.prefix(4), encoding: .ascii)
        XCTAssertEqual(headerString, "%PDF")
        XCTAssertTrue(artifact.fileName.hasPrefix("Bericht_"))
        XCTAssertTrue(artifact.fileName.hasSuffix(".pdf"))
    }

    // MARK: - 10. SAP Upload Payload Builder

    func testUploadBuilderProducesCorrectT0281T0283T0282() throws {
        let payloadDict: [String: Any] = [
            "MANDT": "100",
            "QMNUM": "4710000012",
            "QMART": "I1",
            "FORMNR": "TFM2",
            "T_PLPOD": [
                [
                    "USR00": "POSITION",
                    "STEUS": "TFM2",
                    "VORNR": "0010",
                    "LTXA1": "Triebwerksraum",
                    "T_PROPS": [
                        ["POSNR": "1", "DFVAL": "1;2", "DFVAL_TXT": "OK;Defect"]
                    ]
                ],
                [
                    "USR00": "POSITION",
                    "STEUS": "TFM2",
                    "VORNR": "0020",
                    "LTXA1": "Fahrkorbbeleuchtung",
                    "T_PROPS": [
                        ["POSNR": "1", "DFVAL": "1;2", "DFVAL_TXT": "OK;Defect"],
                        ["POSNR": "2", "DFVAL": "1;8", "DFVAL_TXT": "Behoben;Erledigt"],
                        ["POSNR": "3", "DFVAL": "1;2", "DFVAL_TXT": "Ja;Nein"],
                        ["POSNR": "9B", "DFVAL": ""]
                    ]
                ]
            ]
        ]
        let data = try JSONSerialization.data(withJSONObject: payloadDict)
        let sourceSummary = SAPNotificationSummary(
            id: "4710000012",
            client: "100",
            title: "Aufzugskontrolle",
            functionalLocationID: "FL-1",
            functionalLocationName: "Aufzug",
            equipmentID: "EQ-100010",
            startDate: "20260914",
            endDate: "20260914",
            systemStatus: "MMAB",
            userStatus: "OPEN",
            rawPayloadJSON: String(data: data, encoding: .utf8)!
        )

        let draft = ElevatorInspectionDraftPayload(
            notificationID: "4710000012",
            performedOn: Date(timeIntervalSince1970: 1773489600),
            elementValues: [
                "TFM2-0010-1": "1",
                "TFM2-0020-1": "2",
                "TFM2-0020-2": "1"
            ],
            comments: ["TFM2-0020-1": "Leuchtmittel getauscht"],
            materialFlags: ["TFM2-0020-3": true],
            photoAttachments: [
                NotificationPhotoAttachment(
                    localAttachmentID: "photo-1",
                    checklistItemID: "TFM2-0020-1",
                    sapElementID: "TFM2-0020-9B",
                    capturedAt: Date(timeIntervalSince1970: 1773489600),
                    sapDocumentID: "DOC-1"
                )
            ],
            pdfDocumentID: "PDF-UUID-12345",
            pdfBytes: "Fake PDF content".data(using: .utf8),
            outgoingProcessID: "PROC-100",
            isClosedLocally: true,
            closingSystemStatus: "MMAB",
            closingUserStatus: "FREI Mnot",
            statusNumber: "1"
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

        let photos = ["photo-1": Data([0xFF, 0xD8, 0xFF])]
        let batch = try SAPEquipmentInspectionUploadBuilder.build(
            workItem: workItem,
            source: sourceSummary,
            syncUserID: "S50828",
            photoData: photos
        )

        // 1. T0281 Header
        XCTAssertEqual(batch.headers.count, 1)
        let header = batch.headers[0]
        XCTAssertEqual(header["QMNUM"], "4710000012")
        XCTAssertEqual(header["VORGANGSNR"], "PROC-100")
        XCTAssertEqual(header["STTXT"], "MMAB")
        XCTAssertEqual(header["USTXT"], "FREI Mnot")

        // 2. T0283 Values
        let elementIDs = Set(batch.values.compactMap { $0["ELEMENTNR"] })
        XCTAssertTrue(elementIDs.contains("TFM2-0010-1"))
        XCTAssertTrue(elementIDs.contains("TFM2-0020-1"))
        XCTAssertTrue(elementIDs.contains("TFM2-0020-2"))
        XCTAssertTrue(elementIDs.contains("TFM2-0020-3"))

        // Check material flag row
        let matRow = batch.values.first { $0["ELEMENTNR"] == "TFM2-0020-3" }
        XCTAssertEqual(matRow?["ELEMENTWERT"], "1")

        // 3. Documents (PDF + Photo)
        XCTAssertEqual(batch.documents.count, 2)
        let pdfDoc = batch.documents.first { $0.metadata["ELEMENTNR"] == "TFM2-pdf" }
        XCTAssertNotNil(pdfDoc)
        XCTAssertEqual(pdfDoc?.metadata["DOCID"], "PDF-UUID-12345")
        XCTAssertEqual(pdfDoc?.metadata["MIMETYPE"], "application/pdf")
        XCTAssertEqual(pdfDoc?.metadata["DOKAR"], "D_TFM_Wartung")
        XCTAssertEqual(pdfDoc?.metadata["DOKTL"], "TFM006")

        let photoDoc = batch.documents.first { $0.metadata["ELEMENTNR"] == "TFM2-0020-9B" }
        XCTAssertNotNil(photoDoc)
        XCTAssertEqual(photoDoc?.metadata["DOCID"], "DOC-1")
        XCTAssertEqual(photoDoc?.metadata["MIMETYPE"], "image/jpeg")
    }

    // MARK: - 11. Demo Fixture Isolation

    @MainActor
    func testDemoFixtureContainsTFM2AndRoutesProperly() {
        let demoFixture = MockFacilityData.notifications.first { $0.id == "4710000012" }
        XCTAssertNotNil(demoFixture, "Demo fixture 4710000012 must exist")
        XCTAssertEqual(demoFixture?.equipment, "EQ-100010")

        let sapFixture = MockFacilityData.sapNotifications.first { $0.id == "4710000012" }
        XCTAssertNotNil(sapFixture)
        XCTAssertEqual(sapFixture?.equipmentID, "EQ-100010")
        XCTAssertTrue(sapFixture?.isTFM2ElevatorInspection == true)

        let detail = SAPNotificationDetail(summary: sapFixture!)
        XCTAssertTrue(detail.isTFM2ElevatorInspection)
        XCTAssertEqual(detail.inspectionItems.count, 5)
    }
}
