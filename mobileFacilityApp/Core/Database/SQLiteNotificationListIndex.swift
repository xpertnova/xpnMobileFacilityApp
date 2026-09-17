import Foundation

/// App-owned read model for the notification overview. It deliberately lives
/// beside, rather than inside, the exact legacy SAP database: the latter has a
/// validated fixed schema and must not gain app-specific tables or indexes.
actor SQLiteNotificationListIndex {
    private static let schemaVersion: Int32 = 1
    private var database: OpaquePointer?

    init(databaseURL: URL) throws {
        try FileManager.default.createDirectory(
            at: databaseURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        var openedDatabase: OpaquePointer?
        let result = databaseURL.path.withCString {
            SQLiteC.open($0, &openedDatabase, SQLiteC.openCreate | SQLiteC.openReadWrite | SQLiteC.openFullMutex, nil)
        }
        guard result == SQLiteC.ok, let openedDatabase else {
            throw SAPReadError.serviceUnavailable
        }
        database = openedDatabase
        do {
            try Self.migrate(on: openedDatabase)
        } catch {
            _ = SQLiteC.close(openedDatabase)
            database = nil
            throw error
        }
    }

    deinit {
        _ = SQLiteC.close(database)
    }

    func isCurrent(for workerID: String, sourceVersion: String) throws -> Bool {
        guard let database else { throw SAPReadError.serviceUnavailable }
        return try !Self.query(
            on: database,
            """
            SELECT worker_id
            FROM notification_index_metadata
            WHERE worker_id = ? AND source_version = ? AND schema_version = ?
            LIMIT 1
            """,
            bindings: [workerID, sourceVersion, String(Self.schemaVersion)]
        ) { _ in true }.isEmpty
    }

    /// Replaces one worker's list projection atomically after the legacy
    /// inbound cache has committed. Failure leaves the legacy cache usable;
    /// its owner can rebuild this derived index on a later read.
    func replace(
        _ notifications: [SAPNotificationSummary],
        for workerID: String,
        sourceVersion: String
    ) throws {
        guard let database else { throw SAPReadError.serviceUnavailable }
        try Self.execute(on: database, "BEGIN IMMEDIATE TRANSACTION")
        do {
            try Self.execute(
                on: database,
                "DELETE FROM notification_list_items WHERE worker_id = ?",
                bindings: [workerID]
            )

            try Self.insert(notifications, for: workerID, on: database)

            try Self.execute(
                on: database,
                """
                INSERT INTO notification_index_metadata (worker_id, source_version, schema_version)
                VALUES (?, ?, ?)
                ON CONFLICT(worker_id) DO UPDATE SET
                    source_version = excluded.source_version,
                    schema_version = excluded.schema_version
                """,
                bindings: [workerID, sourceVersion, String(Self.schemaVersion)]
            )
            try Self.execute(on: database, "COMMIT")
        } catch {
            try? Self.execute(on: database, "ROLLBACK")
            throw error
        }
    }

    func loadNotifications(
        for workerID: String,
        matching searchText: String,
        structuralFilter: NotificationStructuralFilter,
        limit: Int,
        offset: Int
    ) throws -> SAPNotificationPage {
        guard let database else { throw SAPReadError.serviceUnavailable }
        let predicate = Self.predicate(
            workerID: workerID,
            searchText: searchText,
            structuralFilter: structuralFilter
        )
        let totalCount = Int(try Self.query(
            on: database,
            "SELECT COUNT(*) FROM notification_list_items WHERE \(predicate.sql)",
            bindings: predicate.bindings
        ) { SQLiteC.columnInt($0, 0) }.first ?? 0)
        let start = min(max(offset, 0), totalCount)
        let pageSize = max(limit, 1)
        let rows = try Self.query(
            on: database,
            """
            SELECT notification_id, client, title, functional_location_id,
                   functional_location_name, equipment_id, start_date, end_date,
                   system_status, user_status, raw_payload_json, country_code,
                   location_code, business_entity_code, building_code, trade_code, form_code
            FROM notification_list_items
            WHERE \(predicate.sql)
            ORDER BY start_date, notification_id
            LIMIT ? OFFSET ?
            """,
            bindings: predicate.bindings + [String(pageSize), String(start)]
        ) { statement in
            let country = Self.string(at: 11, from: statement)
            let location = Self.string(at: 12, from: statement)
            let entity = Self.string(at: 13, from: statement)
            let structuralMetadata: NotificationStructuralFilterMetadata? = entity.isEmpty ? nil : .init(
                countryCode: country,
                locationCode: location,
                businessEntityCode: entity,
                buildingCode: Self.string(at: 14, from: statement),
                tradeCode: Self.string(at: 15, from: statement),
                formCode: Self.string(at: 16, from: statement),
                functionalLocationName: Self.string(at: 4, from: statement)
            )
            return SAPNotificationSummary(
                id: Self.string(at: 0, from: statement),
                client: Self.string(at: 1, from: statement),
                title: Self.string(at: 2, from: statement),
                functionalLocationID: Self.string(at: 3, from: statement),
                functionalLocationName: Self.string(at: 4, from: statement),
                equipmentID: Self.string(at: 5, from: statement),
                startDate: Self.string(at: 6, from: statement),
                endDate: Self.string(at: 7, from: statement),
                systemStatus: Self.string(at: 8, from: statement),
                userStatus: Self.string(at: 9, from: statement),
                rawPayloadJSON: Self.string(at: 10, from: statement),
                structuralFilterMetadata: structuralMetadata
            )
        }
        let end = start + rows.count
        return SAPNotificationPage(
            notifications: rows,
            nextOffset: end < totalCount ? end : nil,
            totalCount: totalCount
        )
    }

    func loadFilterMetadata(for workerID: String) throws -> [NotificationStructuralFilterMetadata] {
        guard let database else { throw SAPReadError.serviceUnavailable }
        return try Self.query(
            on: database,
            """
            SELECT DISTINCT country_code, location_code, business_entity_code,
                            building_code, trade_code, form_code, functional_location_name
            FROM notification_list_items
            WHERE worker_id = ? AND business_entity_code <> ''
            ORDER BY country_code, location_code, business_entity_code,
                     building_code, trade_code, form_code, functional_location_name
            """,
            bindings: [workerID]
        ) { statement in
            NotificationStructuralFilterMetadata(
                countryCode: Self.string(at: 0, from: statement),
                locationCode: Self.string(at: 1, from: statement),
                businessEntityCode: Self.string(at: 2, from: statement),
                buildingCode: Self.string(at: 3, from: statement),
                tradeCode: Self.string(at: 4, from: statement),
                formCode: Self.string(at: 5, from: statement),
                functionalLocationName: Self.string(at: 6, from: statement)
            )
        }
    }

    func summary(for workerID: String) throws -> (actionableCount: Int, businessEntityCount: Int, elevatorInspectionCount: Int) {
        guard let database else { throw SAPReadError.serviceUnavailable }
        let counts = try Self.query(
            on: database,
            """
            SELECT COUNT(*),
                   COUNT(DISTINCT NULLIF(business_entity_id, '')),
                   SUM(CASE WHEN form_code = 'TFM2' THEN 1 ELSE 0 END)
            FROM notification_list_items
            WHERE worker_id = ?
            """,
            bindings: [workerID]
        ) {
            (
                Int(SQLiteC.columnInt($0, 0)),
                Int(SQLiteC.columnInt($0, 1)),
                Int(SQLiteC.columnInt($0, 2))
            )
        }.first ?? (0, 0, 0)
        return (counts.0, counts.1, counts.2)
    }

    private static func predicate(
        workerID: String,
        searchText: String,
        structuralFilter: NotificationStructuralFilter
    ) -> (sql: String, bindings: [String]) {
        var clauses = ["worker_id = ?"]
        var bindings = [workerID]
        let search = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        if !search.isEmpty {
            clauses.append("(notification_id LIKE ? COLLATE NOCASE OR title LIKE ? COLLATE NOCASE OR functional_location_id LIKE ? COLLATE NOCASE OR functional_location_name LIKE ? COLLATE NOCASE)")
            let pattern = "%\(search)%"
            bindings.append(contentsOf: [pattern, pattern, pattern, pattern])
        }
        guard structuralFilter.hasBusinessEntity else {
            return (clauses.joined(separator: " AND "), bindings)
        }
        clauses.append("business_entity_id = ?")
        bindings.append(structuralFilter.businessEntityID)
        if !structuralFilter.buildingCode.isEmpty {
            clauses.append("building_code = ?")
            bindings.append(structuralFilter.buildingCode)
        }
        if !structuralFilter.tradeCode.isEmpty {
            clauses.append("trade_code = ?")
            bindings.append(structuralFilter.tradeCode)
        }
        if !structuralFilter.formCode.isEmpty {
            clauses.append("form_code = ?")
            bindings.append(structuralFilter.formCode)
        }
        return (clauses.joined(separator: " AND "), bindings)
    }

    private static func migrate(on database: OpaquePointer) throws {
        let version = try query(on: database, "PRAGMA user_version") {
            SQLiteC.columnInt($0, 0)
        }.first ?? 0
        guard version < schemaVersion else { return }
        try execute(on: database, "BEGIN IMMEDIATE TRANSACTION")
        do {
            try execute(on: database, """
                CREATE TABLE IF NOT EXISTS notification_list_items (
                    worker_id TEXT NOT NULL,
                    notification_id TEXT NOT NULL,
                    client TEXT NOT NULL,
                    title TEXT NOT NULL,
                    functional_location_id TEXT NOT NULL,
                    functional_location_name TEXT NOT NULL,
                    equipment_id TEXT NOT NULL,
                    start_date TEXT NOT NULL,
                    end_date TEXT NOT NULL,
                    system_status TEXT NOT NULL,
                    user_status TEXT NOT NULL,
                    raw_payload_json TEXT NOT NULL,
                    country_code TEXT NOT NULL,
                    location_code TEXT NOT NULL,
                    business_entity_code TEXT NOT NULL,
                    business_entity_id TEXT NOT NULL,
                    building_code TEXT NOT NULL,
                    trade_code TEXT NOT NULL,
                    form_code TEXT NOT NULL,
                    PRIMARY KEY (worker_id, notification_id)
                )
                """)
            try execute(on: database, """
                CREATE TABLE IF NOT EXISTS notification_index_metadata (
                    worker_id TEXT PRIMARY KEY NOT NULL,
                    source_version TEXT NOT NULL,
                    schema_version INTEGER NOT NULL
                )
                """)
            try execute(on: database, """
                CREATE INDEX IF NOT EXISTS notification_list_by_filter
                ON notification_list_items (
                    worker_id, business_entity_id, building_code, trade_code,
                    form_code, start_date, notification_id
                )
                """)
            try execute(on: database, """
                CREATE INDEX IF NOT EXISTS notification_list_by_date
                ON notification_list_items (worker_id, start_date, notification_id)
                """)
            try execute(on: database, "PRAGMA user_version = \(schemaVersion)")
            try execute(on: database, "COMMIT")
        } catch {
            try? execute(on: database, "ROLLBACK")
            throw error
        }
    }

    private static func insert(
        _ notifications: [SAPNotificationSummary],
        for workerID: String,
        on database: OpaquePointer
    ) throws {
        var statement: OpaquePointer?
        let sql = """
            INSERT INTO notification_list_items (
                worker_id, notification_id, client, title,
                functional_location_id, functional_location_name, equipment_id,
                start_date, end_date, system_status, user_status, raw_payload_json,
                country_code, location_code, business_entity_code, business_entity_id,
                building_code, trade_code, form_code
            ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
            """
        let prepared = sql.withCString { SQLiteC.prepare(database, $0, -1, &statement, nil) }
        guard prepared == SQLiteC.ok, let statement else { throw SAPReadError.serviceUnavailable }
        defer { _ = SQLiteC.finalize(statement) }

        for notification in notifications {
            let metadata = notification.structuralFilterMetadata
            try bind(
                [
                    workerID, notification.id, notification.client, notification.title,
                    notification.functionalLocationID, notification.functionalLocationName,
                    notification.equipmentID, notification.startDate, notification.endDate,
                    notification.systemStatus, notification.userStatus, notification.rawPayloadJSON,
                    metadata?.countryCode ?? "", metadata?.locationCode ?? "",
                    metadata?.businessEntityCode ?? "", metadata?.businessEntityID ?? "",
                    metadata?.buildingCode ?? "", metadata?.tradeCode ?? "",
                    metadata?.formCode ?? ""
                ],
                to: statement
            )
            guard SQLiteC.step(statement) == SQLiteC.done,
                  SQLiteC.reset(statement) == SQLiteC.ok else {
                throw SAPReadError.serviceUnavailable
            }
        }
    }

    private static func execute(
        on database: OpaquePointer,
        _ sql: String,
        bindings: [String] = []
    ) throws {
        var statement: OpaquePointer?
        let prepared = sql.withCString { SQLiteC.prepare(database, $0, -1, &statement, nil) }
        guard prepared == SQLiteC.ok else { throw SAPReadError.serviceUnavailable }
        defer { _ = SQLiteC.finalize(statement) }
        try bind(bindings, to: statement)
        guard SQLiteC.step(statement) == SQLiteC.done else { throw SAPReadError.serviceUnavailable }
    }

    private static func query<T>(
        on database: OpaquePointer,
        _ sql: String,
        bindings: [String] = [],
        map: (OpaquePointer) -> T
    ) throws -> [T] {
        var statement: OpaquePointer?
        let prepared = sql.withCString { SQLiteC.prepare(database, $0, -1, &statement, nil) }
        guard prepared == SQLiteC.ok else { throw SAPReadError.serviceUnavailable }
        defer { _ = SQLiteC.finalize(statement) }
        try bind(bindings, to: statement)
        var values: [T] = []
        while true {
            switch SQLiteC.step(statement) {
            case SQLiteC.row:
                if let statement { values.append(map(statement)) }
            case SQLiteC.done:
                return values
            default:
                throw SAPReadError.serviceUnavailable
            }
        }
    }

    private static func bind(_ values: [String], to statement: OpaquePointer?) throws {
        for (index, value) in values.enumerated() {
            let result = value.withCString {
                SQLiteC.bindText(statement, Int32(index + 1), $0, -1, SQLiteC.transient)
            }
            guard result == SQLiteC.ok else { throw SAPReadError.serviceUnavailable }
        }
    }

    private static func string(at index: Int32, from statement: OpaquePointer) -> String {
        guard let text = SQLiteC.columnText(statement, index) else { return "" }
        return String(cString: text)
    }
}
