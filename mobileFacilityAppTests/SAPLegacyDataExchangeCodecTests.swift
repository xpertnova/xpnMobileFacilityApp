import Foundation
import XCTest
@testable import mobileFacilityApp

/// What the app reads from the legacy MTFM data exchange: SAP's error texts,
/// the version check, the notifications of the worker list and the user row.
final class SAPLegacyDataExchangeCodecTests: XCTestCase {
    // MARK: - Backend messages

    func testSAPTextIsRaisedAsItsMessage() {
        XCTAssertThrowsError(
            try SAPLegacyDataExchangeCodec.validateNoBackendError(Self.textResponse("Benutzer gesperrt"))
        ) { error in
            Self.assertBackendMessage(error, "Benutzer gesperrt")
        }
    }

    func testBlankSAPTextIsNoError() {
        XCTAssertNoThrow(try SAPLegacyDataExchangeCodec.validateNoBackendError(Self.textResponse("  ")))
    }

    func testParameterAnswerIsNoError() {
        XCTAssertNoThrow(
            try SAPLegacyDataExchangeCodec.validateNoBackendError(Self.parameterResponse(["PARAMETER2": "X"]))
        )
    }

    // MARK: - App version

    func testNoVersionAnswerLetsTheAppContinue() {
        XCTAssertNoThrow(try SAPLegacyDataExchangeCodec.validateAppVersion(nil))
        XCTAssertNoThrow(try SAPLegacyDataExchangeCodec.validateAppVersion(""))
    }

    func testAcceptedVersionLetsTheAppContinue() {
        XCTAssertNoThrow(
            try SAPLegacyDataExchangeCodec.validateAppVersion(Self.parameterResponse(["PARAMETER1": ""]))
        )
    }

    func testRejectedVersionStopsWithTheTextSAPSent() {
        let response = Self.parameterResponse(["PARAMETER1": "Bitte die App aktualisieren"])

        XCTAssertThrowsError(try SAPLegacyDataExchangeCodec.validateAppVersion(response)) { error in
            Self.assertBackendMessage(error, "Bitte die App aktualisieren")
        }
    }

    func testVersionCheckAlsoRaisesSAPText() {
        XCTAssertThrowsError(try SAPLegacyDataExchangeCodec.validateAppVersion(Self.textResponse("Mandant gesperrt"))) {
            Self.assertBackendMessage($0, "Mandant gesperrt")
        }
    }

    // MARK: - Notifications

    func testI1RowBecomesANotification() throws {
        let notification = try XCTUnwrap(SAPLegacyDataExchangeCodec.notification(from: Self.notificationRow()))

        XCTAssertEqual(notification.id, "000010001234")
        XCTAssertEqual(notification.client, "100")
        XCTAssertEqual(notification.title, "Aufzug prüfen")
        XCTAssertEqual(notification.functionalLocationID, "DE-11152-10")
        XCTAssertEqual(notification.functionalLocationName, "Gebäude 10")
        XCTAssertEqual(notification.equipmentID, "000000004711")
        XCTAssertEqual(notification.startDate, "2026-09-01")
        XCTAssertEqual(notification.endDate, "2026-09-30")
        XCTAssertEqual(notification.systemStatus, "MOFN")
        XCTAssertEqual(notification.userStatus, "OFFN")
    }

    func testOnlyI1NotificationsAreListed() {
        for type in ["I2", "I3", ""] {
            XCTAssertNil(
                SAPLegacyDataExchangeCodec.notification(from: Self.notificationRow(["QMART": type])),
                "\(type) is not a maintenance notification"
            )
        }
        XCTAssertNotNil(SAPLegacyDataExchangeCodec.notification(from: Self.notificationRow(["QMART": "i1"])))
    }

    func testDeactivatedNotificationIsNotListed() {
        for status in ["MMAB", "mmab"] {
            XCTAssertNil(SAPLegacyDataExchangeCodec.notification(from: Self.notificationRow(["STTXT": status])))
        }
    }

    func testRowWithoutNumberIsNotListed() {
        for number in ["", "   "] {
            XCTAssertNil(SAPLegacyDataExchangeCodec.notification(from: Self.notificationRow(["QMNUM": number])))
        }
    }

    func testColumnNamesAreReadWithoutCase() throws {
        let row: [String: Any] = ["qmart": "I1", "qmnum": "4711", "qmtxt": "Klein geschrieben", "sttxt": "MOFN"]

        let notification = try XCTUnwrap(SAPLegacyDataExchangeCodec.notification(from: row))

        XCTAssertEqual(notification.id, "4711")
        XCTAssertEqual(notification.title, "Klein geschrieben")
    }

    /// The plan in `FELDWERT` is the newer copy of the notification.
    func testPlanPayloadOverridesTheRowValues() throws {
        let feldwert = try SAPLegacyDataExchangeCodec.packedFeldwert([
            "T_PLPOD": [["VORNR": "0010", "STEUS": "TFM2"]],
            "QMTXT": "Aus dem Plan"
        ])

        let notification = try XCTUnwrap(
            SAPLegacyDataExchangeCodec.notification(from: Self.notificationRow(["FELDWERT": feldwert]))
        )

        XCTAssertEqual(notification.title, "Aus dem Plan")
        XCTAssertEqual(notification.legacyControlKey, "TFM2")
    }

    func testPayloadWithoutPlanDoesNotOverrideTheRow() throws {
        let feldwert = try SAPLegacyDataExchangeCodec.packedFeldwert(["QMTXT": "Kein Plan"])

        let notification = try XCTUnwrap(
            SAPLegacyDataExchangeCodec.notification(from: Self.notificationRow(["FELDWERT": feldwert]))
        )

        XCTAssertEqual(notification.title, "Aufzug prüfen")
    }

    // MARK: - User

    func testUserRowBecomesTheProfile() {
        let row: [String: Any] = [
            "PERSNR": " S50828 ", "NAME": "Muster", "VORNAME": "Max",
            "GESELLSCHAFT": "XPN", "EMAIL": "max.muster@example.com", "I2": "X"
        ]

        XCTAssertEqual(
            SAPLegacyDataExchangeCodec.userProfile(from: row),
            SAPUserProfile(
                personalNumber: "S50828", name: "Muster", firstName: "Max",
                company: "XPN", email: "max.muster@example.com", canCreateI2: true
            )
        )
    }

    func testI2RightIsGrantedOnlyByX() {
        for (flag, canCreate) in [("X", true), ("x", true), ("", false), ("N", false)] {
            let profile = SAPLegacyDataExchangeCodec.userProfile(from: ["PERSNR": "S50828", "I2": flag])
            XCTAssertEqual(profile?.canCreateI2, canCreate, "I2 = \"\(flag)\"")
        }
        XCTAssertEqual(SAPLegacyDataExchangeCodec.userProfile(from: ["PERSNR": "S50828"])?.canCreateI2, false)
    }

    func testUserWithoutPersonnelNumberIsIgnored() {
        XCTAssertNil(SAPLegacyDataExchangeCodec.userProfile(from: ["NAME": "Muster", "I2": "X"]))
        XCTAssertNil(SAPLegacyDataExchangeCodec.userProfile(from: ["PERSNR": "  "]))
    }

    func testWorkerRowBecomesTheWorkerProfile() throws {
        let worker = try XCTUnwrap(SAPLegacyDataExchangeCodec.workerProfile(from: [
            "PERSNR": "S50828", "VORNAME": "Max", "NAME": "Muster",
            "GESELLSCHAFT": "XPN", "ROLLE": "Techniker", "EMAIL": "max.muster@example.com",
            "AKTIV": "X", "RCDEX": "ZT"
        ]))

        XCTAssertEqual(worker.personnelNumber, "S50828")
        XCTAssertEqual(worker.firstName, "Max")
        XCTAssertEqual(worker.lastName, "Muster")
        XCTAssertEqual(worker.organizationUnit, "XPN")
        XCTAssertEqual(worker.role, "Techniker")
        XCTAssertEqual(worker.roleCode, "ZT")
        XCTAssertNil(SAPLegacyDataExchangeCodec.workerProfile(from: ["NAME": "Muster"]))
    }

    // MARK: - Helpers

    private static func notificationRow(_ overrides: [String: Any] = [:]) -> [String: Any] {
        let row: [String: Any] = [
            "MANDT": "100", "QMNUM": "000010001234", "QMART": "I1", "QMTXT": "Aufzug prüfen",
            "STRNO": "DE-11152-10", "PLTXT": "Gebäude 10", "EQUNR": "000000004711",
            "STRMN": "2026-09-01", "LTRMN": "2026-09-30", "STTXT": "MOFN", "USTXT": "OFFN"
        ]
        return row.merging(overrides) { _, override in override }
    }

    private static func textResponse(_ text: String) -> String {
        envelopeJSON([["KEY": "TEXT", "PAR": "", "VALUE": text]])
    }

    private static func parameterResponse(_ parameters: [String: String]) -> String {
        let value = String(decoding: try! JSONSerialization.data(withJSONObject: parameters), as: UTF8.self)
        return envelopeJSON([["KEY": "STRUCTURE", "PAR": "/EZO/MTFMS_PARAMETER", "VALUE": value]])
    }

    private static func envelopeJSON(_ envelopes: [[String: String]]) -> String {
        String(decoding: try! JSONSerialization.data(withJSONObject: envelopes), as: UTF8.self)
    }

    private static func assertBackendMessage(
        _ error: Error,
        _ expected: String,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        guard case let SAPReadError.backendMessage(message) = error else {
            return XCTFail("Expected the SAP text, got \(error)", file: file, line: line)
        }
        XCTAssertEqual(message, expected, file: file, line: line)
    }
}
