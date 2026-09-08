import Foundation
import XCTest
@testable import mobileFacilityApp

final class LegacySQLiteSchemaTests: XCTestCase {
    private struct Manifest: Decodable {
        struct Table: Decodable {
            struct Column: Decodable {
                let name: String
                let type: String
            }
            let name: String
            let columns: [Column]
        }
        let tables: [Table]
    }

    func testDatabaseMatchesGoldenManifestExactly() throws {
        let url = temporaryDatabaseURL()
        defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }
        _ = try SQLiteSAPDataCacheRepository(databaseURL: url)
        let manifest = try goldenManifest()

        var database: OpaquePointer?
        XCTAssertEqual(url.path.withCString {
            SQLiteC.open($0, &database, SQLiteC.openReadWrite | SQLiteC.openFullMutex, nil)
        }, SQLiteC.ok)
        let openedDatabase = try XCTUnwrap(database)
        defer { _ = SQLiteC.close(openedDatabase) }

        let actualNames = try queryStrings(
            "SELECT name FROM sqlite_master WHERE type = 'table' AND name NOT LIKE 'sqlite_%' ORDER BY name",
            on: openedDatabase
        )
        XCTAssertEqual(actualNames, manifest.tables.map(\.name).sorted())
        XCTAssertEqual(actualNames.count, 86)
        XCTAssertFalse(actualNames.contains { $0.contains("T025") })

        for table in manifest.tables {
            var statement: OpaquePointer?
            XCTAssertEqual("PRAGMA table_info(\(table.name))".withCString {
                SQLiteC.prepare(openedDatabase, $0, -1, &statement, nil)
            }, SQLiteC.ok)
            let prepared = try XCTUnwrap(statement)
            defer { _ = SQLiteC.finalize(prepared) }
            var columns: [(String, String)] = []
            while SQLiteC.step(prepared) == SQLiteC.row {
                columns.append((string(prepared, 1), string(prepared, 2)))
                XCTAssertEqual(SQLiteC.columnInt(prepared, 3), 0, "\(table.name) unexpectedly has NOT NULL")
                XCTAssertEqual(SQLiteC.columnInt(prepared, 5), 0, "\(table.name) unexpectedly has a primary key")
            }
            XCTAssertEqual(columns.map(\.0), table.columns.map(\.name), table.name)
            XCTAssertEqual(columns.map(\.1), table.columns.map(\.type), table.name)
        }
        XCTAssertTrue(try queryStrings(
            "SELECT name FROM sqlite_master WHERE type = 'index' AND name NOT LIKE 'sqlite_%'",
            on: openedDatabase
        ).isEmpty)
        XCTAssertEqual(try queryStrings("SELECT DBVERSION FROM APPVERSION WHERE IDCHECK = 1", on: openedDatabase), ["358"])
        XCTAssertEqual(
            try queryStrings("SELECT VALUE FROM PARVALUE WHERE CATEGORY = 'ACTIVESYSTEM' AND PARAMETER = 'PSYSTEM'", on: openedDatabase),
            ["X"]
        )
    }

    func testWorkersUseDifferentHashedMtfmPaths() throws {
        let first = try SQLiteSAPDataCacheRepository.productionDatabaseURL(workerID: "worker-a")
        let sameIdentity = try SQLiteSAPDataCacheRepository.productionDatabaseURL(workerID: " WORKER-A ")
        let second = try SQLiteSAPDataCacheRepository.productionDatabaseURL(workerID: "worker-b")
        XCTAssertEqual(first, sameIdentity)
        XCTAssertNotEqual(first.deletingLastPathComponent(), second.deletingLastPathComponent())
        XCTAssertEqual(first.lastPathComponent, "mtfm.db")
        XCTAssertEqual(second.lastPathComponent, "mtfm.db")
        XCTAssertEqual(first.deletingLastPathComponent().lastPathComponent.count, 64)
    }

    func testMultiPackageInboundCommitMapsUserAndPreservesCacheAfterMalformedRows() async throws {
        let url = temporaryDatabaseURL()
        defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }
        let repository = try SQLiteSAPDataCacheRepository(databaseURL: url, workerID: "local-1")
        try await repository.beginIncoming()
        try await repository.appendIncoming(.init(tables: [
            "T_0271": [[
                "MANDT": "100", "QMNUM": "N-1", "QMART": "I1", "QMTXT": "Pump",
                "STTXT": "OSNO", "STRNO": "DE-ESS-100", "PLTXT": "Plant",
                "TPWEH": "100", "TPGEB": "01", "TPGSG": "420"
            ], [
                "MANDT": "100", "QMNUM": "N-2", "QMART": "I1", "QMTXT": "Door",
                "STTXT": "OSNO", "STRNO": "DE-ESS-200", "PLTXT": "Office",
                "TPLND": "DE", "TPORT": "ESS", "TPWEH": "200", "TPGEB": "02", "TPGSG": "330"
            ]],
            "T_0251": [[ "UNKNOWN": "ignored" ]],
            "T_UNKNOWN": [[ "ANYTHING": "ignored" ]]
        ], isLastPackage: false))
        try await repository.appendIncoming(.init(tables: [
            "T_0153": [[
                "MANDT": "100", "PERSNR": "4711", "VORNAME": "Alex", "NAME": "Morgan",
                "ROLLE": "Technician", "AKTIV": "X"
            ]]
        ], isLastPackage: true))
        let committed = try await repository.commitIncoming(
            sapWorkerID: "SAP-4711",
            refreshedAt: Date(timeIntervalSince1970: 1_700_000_000)
        )
        XCTAssertEqual(committed.workerProfile?.personnelNumber, "4711")
        XCTAssertEqual(committed.metadata?.sapWorkerID, "SAP-4711")
        let firstPage = try await repository.loadNotifications(
            for: "local-1",
            matching: "pump",
            structuralFilter: .empty,
            limit: 10,
            offset: 0
        )
        XCTAssertEqual(firstPage.notifications.map(\.id), ["N-1"])
        let paged = try await repository.loadNotifications(
            for: "local-1",
            matching: "",
            structuralFilter: .empty,
            limit: 1,
            offset: 0
        )
        XCTAssertEqual(paged.notifications.map(\.id), ["N-1"])
        XCTAssertEqual(paged.nextOffset, 1)
        XCTAssertEqual(paged.totalCount, 2)
        let filtered = try await repository.loadNotifications(
            for: "local-1",
            matching: "",
            structuralFilter: .init(businessEntityID: "DE-ESS-200"),
            limit: 10,
            offset: 0
        )
        XCTAssertEqual(filtered.notifications.map(\.id), ["N-2"])

        try await repository.beginIncoming()
        do {
            try await repository.appendIncoming(.init(
                tables: ["T_0271": [[ "QMNUM": "N-2", "INVALID_COLUMN": "bad" ]]],
                isLastPackage: true
            ))
            XCTFail("Malformed recognized row must be rejected")
        } catch {
            await repository.abortIncoming()
        }
        let preserved = try await repository.loadNotifications(
            for: "local-1",
            matching: "",
            structuralFilter: .empty,
            limit: 10,
            offset: 0
        )
        XCTAssertEqual(preserved.notifications.map(\.id), ["N-1", "N-2"])
    }

    func testSAPTransportUsesVerifiedLegacyUserProjectionOnly() throws {
        let userSchema = try XCTUnwrap(LegacySQLiteSchema.byName["USER"])
        let projected = try SAPLegacyDataExchangeCodec.legacyRow(
            from: [
                "persnr": "4711",
                "VORNAME": "Alex",
                "SERVER_ONLY_FIELD": ["future": "metadata"]
            ],
            for: userSchema,
            ignoringUnknownColumns: true,
            sourceTableName: "T_0153"
        )

        XCTAssertEqual(projected["PERSNR"]!, "4711")
        XCTAssertEqual(projected["VORNAME"]!, "Alex")
        XCTAssertFalse(projected.keys.contains("SERVER_ONLY_FIELD"))

        let notificationSchema = try XCTUnwrap(LegacySQLiteSchema.byName["FROM_T0271"])
        XCTAssertThrowsError(try SAPLegacyDataExchangeCodec.legacyRow(from: [
            "QMNUM": "N-1", "SERVER_ONLY_FIELD": "invalid"
        ], for: notificationSchema))
        XCTAssertThrowsError(try SAPLegacyDataExchangeCodec.legacyRow(from: [
            "QMNUM": ["invalid", "known", "column", "value"]
        ], for: notificationSchema))
    }

    func testOutgoingAliasesAcknowledgementAndUnsupportedRows() async throws {
        let url = temporaryDatabaseURL()
        defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }
        let repository = try SQLiteSAPDataCacheRepository(databaseURL: url)
        try await repository.insertLegacyRows([[
            "MANDT": "100", "PTID": "LOG-1", "TYPE": "INFO"
        ]], into: "TO_LOGGER")
        try await repository.insertLegacyRows([[
            "MANDT": "100", "PERSNR": "4711", "PUK": "1234"
        ]], into: "TO_USER_PUK")
        try await repository.insertLegacyRows([[
            "MANDT": "100", "VORGANGSNR": "OP-1"
        ]], into: "TO_T0211")
        try await repository.insertLegacyRows([[
            "MANDT": "100", "EQART": "X"
        ]], into: "TO_T0263")
        try await repository.insertLegacyRows([[:]], into: "TO_T0271")
        try await repository.insertLegacyRows([[:]], into: "TO_T0292")
        try await repository.insertLegacyRows([[:]], into: "TO_T0298")

        let payload = try await repository.stageOutgoing(requestID: "REQ-1")
        XCTAssertEqual(payload.T_0152R.first?["PTID"], "LOG-1")
        XCTAssertEqual(payload.T_0152R.first?["REQID"], "REQ-1")
        XCTAssertEqual(payload.T_0154R.first?["PERSNR"], "4711")
        XCTAssertEqual(payload.T_0211R.first?["VORGANGSNR"], "OP-1")
        XCTAssertTrue(payload.T_0265.isEmpty)
        XCTAssertTrue(payload.T_0281.isEmpty)

        try await repository.insertLegacyRows([[
            "MANDT": "100", "PTID": "LOG-LATE", "TYPE": "INFO"
        ]], into: "TO_LOGGER")
        try await repository.confirmOutgoing(requestID: "REQ-1")
        let loggerCount = try await repository.legacyRowCount(in: "TO_LOGGER")
        let pukCount = try await repository.legacyRowCount(in: "TO_USER_PUK")
        let unsupportedT0263Count = try await repository.legacyRowCount(in: "TO_T0263")
        let unsupportedT0271Count = try await repository.legacyRowCount(in: "TO_T0271")
        let unsupportedT0292Count = try await repository.legacyRowCount(in: "TO_T0292")
        let unsupportedT0298Count = try await repository.legacyRowCount(in: "TO_T0298")
        XCTAssertEqual(loggerCount, 1)
        XCTAssertEqual(pukCount, 0)
        XCTAssertEqual(
            [unsupportedT0263Count, unsupportedT0271Count, unsupportedT0292Count, unsupportedT0298Count],
            [1, 1, 1, 1]
        )

        let retryPayload = try await repository.stageOutgoing(requestID: "REQ-2")
        XCTAssertEqual(retryPayload.T_0152R.map { $0["PTID"] }, ["LOG-LATE"])
        await repository.abortOutgoing(requestID: "REQ-2")
        let preservedLoggerCount = try await repository.legacyRowCount(in: "TO_LOGGER")
        XCTAssertEqual(preservedLoggerCount, 1)
    }

    func testLegacyBriefingAndTechnicalObjectQueries() async throws {
        let url = temporaryDatabaseURL()
        defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }
        let repository = try SQLiteSAPDataCacheRepository(databaseURL: url)
        let templateJSON = """
        {"EQART":"TFMINSTRUC","PLNNR":"TFMB_001","T_PLPOD":[
          {"USR00":"HEADER","VORNR":"0010","LTXA1":"Safety"},
          {"USR00":"POSITION","VORNR":"0020","LTXA1":"Wear PPE"}
        ]}
        """
        let partnerJSON = """
        {"NAME1":"Partner GmbH","NAME2":"Pat Person","CITY1":"Essen","COUNTRY":"DE"}
        """
        try await repository.beginIncoming()
        try await repository.appendIncoming(.init(tables: [
            "T_0298": [[ "ADDRNUMBER": "P-1", "FELDWERT": partnerJSON ]],
            "T_0267": [[ "EQART": "TFMINSTRUC", "PLNNR": "TFMB_001", "FELDWERT": templateJSON ]],
            "T_0261": [[ "STRNO": "DE-ESS-420", "PLTXT": "Heating", "TPLND": "DE", "TPORT": "ESS" ]],
            "T_0262": [[ "EQUNR": "EQ-1", "STRNO": "DE-ESS-420", "EQKTX": "Pump" ]]
        ], isLastPackage: true))
        let cached = try await repository.commitIncoming(sapWorkerID: "SAP-1", refreshedAt: Date())
        XCTAssertEqual(cached.briefingPartners.first?.name, "Partner GmbH")
        XCTAssertEqual(cached.briefingTemplates.first?.sections.first?.items.first?.title, "Wear PPE")
        let equipmentCount = try await repository.technicalObjectCount(for: "any", kind: .equipment)
        XCTAssertEqual(equipmentCount, 1)
        let results = try await repository.searchTechnicalObjects(for: "any", query: "Pump", dinGroup: nil)
        XCTAssertEqual(results.last?.reference.objectID, "EQ-1")
    }

    private func temporaryDatabaseURL() -> URL {
        FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
            .appendingPathComponent("mtfm.db")
    }

    private func goldenManifest() throws -> Manifest {
        let bundleURL = Bundle(for: Self.self).url(forResource: "legacy-schema", withExtension: "json")
        let sourceURL = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .appendingPathComponent("Fixtures/legacy-schema.json")
        return try JSONDecoder().decode(Manifest.self, from: Data(contentsOf: bundleURL ?? sourceURL))
    }

    private func queryStrings(_ sql: String, on database: OpaquePointer) throws -> [String] {
        var statement: OpaquePointer?
        XCTAssertEqual(sql.withCString {
            SQLiteC.prepare(database, $0, -1, &statement, nil)
        }, SQLiteC.ok)
        let prepared = try XCTUnwrap(statement)
        defer { _ = SQLiteC.finalize(prepared) }
        var values: [String] = []
        while SQLiteC.step(prepared) == SQLiteC.row {
            values.append(string(prepared, 0))
        }
        return values
    }

    private func string(_ statement: OpaquePointer, _ column: Int32) -> String {
        SQLiteC.columnText(statement, column).map(String.init(cString:)) ?? ""
    }
}
