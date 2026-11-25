import Foundation
import XCTest
@testable import mobileFacilityApp

/// The QR lookup the device runs against the downloaded SAP cache
/// (`SQLiteSAPDataCacheRepository.resolveQRCode`), traced from the Cordova
/// scan in `edata/select.js`.
final class SQLiteQRCodeResolutionTests: XCTestCase {
    private var directory: URL!
    private var repository: SQLiteSAPDataCacheRepository!

    override func setUpWithError() throws {
        try super.setUpWithError()
        directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        repository = try SQLiteSAPDataCacheRepository(databaseURL: directory.appendingPathComponent("cache.sqlite"))
    }

    override func tearDownWithError() throws {
        repository = nil
        try? FileManager.default.removeItem(at: directory)
        try super.tearDownWithError()
    }

    // MARK: - MTFM codes

    /// `EQUNR LIKE '%{0}'`: the label carries the equipment number without
    /// SAP's leading zeros.
    func testEquipmentCodeFindsTheNotificationsOfThatEquipment() async throws {
        try await insertNotifications([
            notification("1", location: "FL-1", equipment: "000000004711"),
            notification("2", location: "FL-1", equipment: "000000004712"),
            notification("3", location: "FL-1"),
            notification("4", location: "FL-2", equipment: "000000004711")
        ])

        let matches = try await resolve(.mtfm(controlKey: nil, functionalLocationID: "FL-1", equipmentID: "4711"))

        XCTAssertEqual(matches, ["1"])
    }

    func testLocationCodeSkipsTheNotificationsOfItsEquipment() async throws {
        try await insertNotifications([
            notification("1", location: "FL-1", equipment: "000000004711"),
            notification("2", location: "FL-1"),
            notification("3", location: "FL-2")
        ])

        let matches = try await resolve(.mtfm(controlKey: nil, functionalLocationID: "FL-1", equipmentID: nil))

        XCTAssertEqual(matches, ["2"])
    }

    func testControlKeyNarrowsToThatForm() async throws {
        try await insertNotifications([
            notification("1", location: "FL-1", controlKey: "TFM5"),
            notification("2", location: "FL-1", controlKey: "TFM7")
        ])

        let tfm5 = try await resolve(.mtfm(controlKey: "TFM5", functionalLocationID: "FL-1", equipmentID: nil))
        let any = try await resolve(.mtfm(controlKey: nil, functionalLocationID: "FL-1", equipmentID: nil))

        XCTAssertEqual(tfm5, ["1"])
        XCTAssertEqual(any, ["1", "2"])
    }

    func testMatchesAreSortedByStartDate() async throws {
        try await insertNotifications([
            notification("B", location: "FL-1", start: "2026-09-10"),
            notification("C", location: "FL-1", start: "2026-09-01"),
            notification("A", location: "FL-1", start: "2026-09-10")
        ])

        let matches = try await resolve(.mtfm(controlKey: nil, functionalLocationID: "FL-1", equipmentID: nil))

        XCTAssertEqual(matches, ["C", "A", "B"])
    }

    // MARK: - Local work

    /// A notification closed on this iPad is waiting for SAP and must not
    /// open again from its label.
    func testNotificationClosedOnThisDeviceIsNotOfferedAgain() async throws {
        try await insertNotifications([
            notification("1", location: "FL-1"),
            notification("2", location: "FL-1"),
            notification("3", location: "FL-1")
        ])
        try await repository.insertLegacyRows([
            ["MANDT": "100", "VORGANGSNR": "P-1", "QMNUM": "1", "STTXT": "MABG",
             "CREATEDDATE": "20260930", "CREATEDTIME": "100000"],
            ["MANDT": "100", "VORGANGSNR": "P-2", "QMNUM": "2", "STTXT": "MIAR",
             "CREATEDDATE": "20260930", "CREATEDTIME": "100000"]
        ], into: "TO_T0281")

        let matches = try await resolve(.mtfm(controlKey: nil, functionalLocationID: "FL-1", equipmentID: nil))

        XCTAssertEqual(matches, ["2", "3"])
    }

    func testTheLatestLocalProcessDecides() async throws {
        try await insertNotifications([notification("1", location: "FL-1")])
        try await repository.insertLegacyRows([
            ["MANDT": "100", "VORGANGSNR": "P-1", "QMNUM": "1", "STTXT": "MIAR",
             "CREATEDDATE": "20260929", "CREATEDTIME": "235959"],
            ["MANDT": "100", "VORGANGSNR": "P-2", "QMNUM": "1", "STTXT": "MABG",
             "CREATEDDATE": "20260930", "CREATEDTIME": "080000"]
        ], into: "TO_T0281")

        let matches = try await resolve(.mtfm(controlKey: nil, functionalLocationID: "FL-1", equipmentID: nil))

        XCTAssertEqual(matches, [])
    }

    // MARK: - S/4 identifiers

    /// Labels printed before the S/4 migration carry the old identifiers;
    /// `FROM_T0213` maps them to the new ones.
    func testOldLocationLabelFindsTheMigratedLocation() async throws {
        try await insertNotifications([notification("1", location: "FL-NEW")])
        try await repository.insertLegacyRows([
            ["MANDT": "100", "STRNO_S4I": "FL-OLD", "STRNO_S4U": "FL-NEW"]
        ], into: "FROM_T0213")

        let matches = try await resolve(.mtfm(controlKey: nil, functionalLocationID: "FL-OLD", equipmentID: nil))

        XCTAssertEqual(matches, ["1"])
    }

    func testOldEquipmentLabelFindsTheMigratedEquipmentAndItsLocation() async throws {
        try await insertNotifications([notification("1", location: "FL-NEW", equipment: "000000009999")])
        try await repository.insertLegacyRows([
            ["MANDT": "100", "EQUNR_S4I": "4711", "EQUNR_S4U": "000000009999"]
        ], into: "FROM_T0213")
        try await repository.insertLegacyRows([
            ["MANDT": "100", "STRNO": "FL-NEW", "EQUNR": "000000009999"]
        ], into: "FROM_T0273")

        let matches = try await resolve(.mtfm(controlKey: nil, functionalLocationID: "FL-OLD", equipmentID: "4711"))

        XCTAssertEqual(matches, ["1"])
    }

    // MARK: - MIHM codes

    func testMIHMCodeFindsNotificationsByObjectAndReference() async throws {
        try await insertNotifications([
            notification("1", location: "FL-1", extra: ["TPWEH": "11152", "EQFNR": "AZ-01"]),
            notification("2", location: "FL-1", extra: ["TPWEH": "11152", "EQFNR": "AZ-02"])
        ])

        let matches = try await resolve(.mihm(objectNumber: "11152", technicalReference: "AZ-01"))

        XCTAssertEqual(matches, ["1"])
    }

    /// Without a direct hit the equipment list names the object the label
    /// belongs to.
    func testMIHMCodeFallsBackToTheEquipmentList() async throws {
        try await insertNotifications([
            notification("1", location: "DE-11152-10", equipment: "000000005555"),
            notification("2", location: "DE-11152-10")
        ])
        try await repository.insertLegacyRows([
            ["MANDT": "100", "STRNO": "DE-11152-10", "EQUNR": "000000005555", "EQFNR": "AZ-01"]
        ], into: "FROM_T0273")

        let matches = try await resolve(.mihm(objectNumber: "11152", technicalReference: "AZ-01"))

        XCTAssertEqual(matches, ["1"])
    }

    func testUnknownMIHMCodeFindsNothing() async throws {
        try await insertNotifications([notification("1", location: "FL-1")])

        let matches = try await resolve(.mihm(objectNumber: "99999", technicalReference: "AZ-99"))

        XCTAssertEqual(matches, [])
    }

    // MARK: - Worker

    func testCacheOfAnotherWorkerDoesNotAnswer() async throws {
        let workerRepository = try SQLiteSAPDataCacheRepository(
            databaseURL: directory.appendingPathComponent("worker.sqlite"),
            workerID: "S50828"
        )

        do {
            _ = try await workerRepository.resolveQRCode(
                .mtfm(controlKey: nil, functionalLocationID: "FL-1", equipmentID: nil),
                for: "S99999"
            )
            XCTFail("Expected the cache to refuse another worker")
        } catch SAPReadError.serviceUnavailable {
        }
    }

    // MARK: - Helpers

    private func resolve(_ payload: LegacyQRCodePayload) async throws -> [String] {
        try await repository.resolveQRCode(payload, for: "S50828").map(\.id)
    }

    private func insertNotifications(_ rows: [LegacySAPRow]) async throws {
        try await repository.insertLegacyRows(rows, into: "FROM_T0271")
    }

    private func notification(
        _ id: String,
        location: String,
        equipment: String = "",
        controlKey: String? = nil,
        start: String = "2026-09-01",
        extra: [String: String] = [:]
    ) -> LegacySAPRow {
        var row: [String: String] = [
            "MANDT": "100", "QMNUM": id, "QMART": "I1", "QMTXT": "Prüfung \(id)",
            "STRNO": location, "EQUNR": equipment, "STRMN": start, "STTXT": "MOFN"
        ]
        if let controlKey {
            row["FELDWERT"] = try! SAPLegacyDataExchangeCodec.packedFeldwert(
                ["T_PLPOD": [["VORNR": "0010", "STEUS": controlKey]]]
            )
        }
        row.merge(extra) { _, value in value }
        return row.mapValues { Optional($0) }
    }
}
