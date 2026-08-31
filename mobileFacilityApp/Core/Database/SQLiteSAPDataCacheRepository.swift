import Foundation

actor SQLiteSAPDataCacheRepository: SAPDataCacheRepository {
    private static let currentSchemaVersion: Int32 = 2
    private var database: OpaquePointer?

    init(databaseURL: URL? = nil) throws {
        let url: URL
        if let databaseURL {
            url = databaseURL
        } else {
            let directory = try FileManager.default.url(
                for: .applicationSupportDirectory,
                in: .userDomainMask,
                appropriateFor: nil,
                create: true
            )
            url = directory.appendingPathComponent("sap-data-cache.sqlite")
        }

        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        var openedDatabase: OpaquePointer?
        let result = url.path.withCString {
            SQLiteC.open($0, &openedDatabase, SQLiteC.openCreate | SQLiteC.openReadWrite | SQLiteC.openFullMutex, nil)
        }
        guard result == SQLiteC.ok, let openedDatabase else { throw SAPReadError.serviceUnavailable }
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

    func load(for localWorkerID: String) async throws -> SAPCachedData {
        guard let database else { throw SAPReadError.serviceUnavailable }
        let profile = try Self.query(
            on: database,
            """
            SELECT personnel_number, first_name, last_name, organization_unit,
                   role, email, is_active, role_code
            FROM sap_worker_profiles WHERE local_worker_id = ? LIMIT 1
            """,
            bindings: [localWorkerID]
        ) { statement in
            SAPWorkerProfile(
                personnelNumber: Self.string(at: 0, from: statement),
                firstName: Self.string(at: 1, from: statement),
                lastName: Self.string(at: 2, from: statement),
                organizationUnit: Self.string(at: 3, from: statement),
                role: Self.string(at: 4, from: statement),
                email: Self.string(at: 5, from: statement),
                isActive: Self.string(at: 6, from: statement),
                roleCode: Self.string(at: 7, from: statement)
            )
        }.first
        let metadataRow = try Self.query(
            on: database,
            """
            SELECT sap_worker_id, last_successful_refresh_at
            FROM sap_refresh_metadata WHERE local_worker_id = ? LIMIT 1
            """,
            bindings: [localWorkerID]
        ) { statement in
            (Self.string(at: 0, from: statement), Self.string(at: 1, from: statement))
        }.first
        let metadata: SAPCacheMetadata?
        if let metadataRow, let date = Self.dateFormatter.date(from: metadataRow.1) {
            metadata = SAPCacheMetadata(sapWorkerID: metadataRow.0, lastSuccessfulRefreshAt: date)
        } else {
            metadata = nil
        }
        return SAPCachedData(notifications: [], workerProfile: profile, metadata: metadata)
    }

    func loadNotifications(
        for localWorkerID: String,
        matching searchText: String,
        limit: Int,
        offset: Int
    ) async throws -> SAPNotificationPage {
        guard let database else { throw SAPReadError.serviceUnavailable }
        let filter = Self.notificationFilter(for: localWorkerID, matching: searchText)
        let totalCount = try Self.query(
            on: database,
            "SELECT COUNT(*) FROM sap_notifications WHERE \(filter.clause)",
            bindings: filter.bindings
        ) { statement in
            Int(SQLiteC.columnInt(statement, 0))
        }.first ?? 0
        let boundedOffset = min(max(offset, 0), totalCount)
        let notifications = try Self.query(
            on: database,
            """
            SELECT notification_id, client, title, functional_location_id, functional_location_name,
                   start_date, end_date, system_status, user_status, raw_payload_json
            FROM sap_notifications
            WHERE \(filter.clause)
            ORDER BY start_date, notification_id
            LIMIT ? OFFSET ?
            """,
            bindings: filter.bindings + [String(max(limit, 1)), String(boundedOffset)]
        ) { statement in
            SAPNotificationSummary(
                id: Self.string(at: 0, from: statement),
                client: Self.string(at: 1, from: statement),
                title: Self.string(at: 2, from: statement),
                functionalLocationID: Self.string(at: 3, from: statement),
                functionalLocationName: Self.string(at: 4, from: statement),
                startDate: Self.string(at: 5, from: statement),
                endDate: Self.string(at: 6, from: statement),
                systemStatus: Self.string(at: 7, from: statement),
                userStatus: Self.string(at: 8, from: statement),
                rawPayloadJSON: Self.string(at: 9, from: statement)
            )
        }
        let nextOffset = boundedOffset + notifications.count
        return SAPNotificationPage(
            notifications: notifications,
            nextOffset: nextOffset < totalCount ? nextOffset : nil,
            totalCount: totalCount
        )
    }

    func replace(
        with snapshot: SAPReadSnapshot,
        for localWorkerID: String,
        refreshedAt: Date
    ) async throws -> SAPCachedData {
        guard let database else { throw SAPReadError.serviceUnavailable }
        try Self.execute(on: database, "BEGIN IMMEDIATE TRANSACTION")
        do {
            try Self.execute(on: database, "DELETE FROM sap_notifications WHERE local_worker_id = ?", bindings: [localWorkerID])
            for notification in snapshot.notifications {
                try Self.execute(on: database, """
                    INSERT INTO sap_notifications (
                        local_worker_id, notification_id, client, title, functional_location_id,
                        functional_location_name, start_date, end_date, system_status, user_status,
                        raw_payload_json
                    ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
                    """, bindings: [
                        localWorkerID, notification.id, notification.client, notification.title,
                        notification.functionalLocationID, notification.functionalLocationName,
                        notification.startDate, notification.endDate, notification.systemStatus,
                        notification.userStatus, notification.rawPayloadJSON
                    ])
            }
            try Self.execute(on: database, "DELETE FROM sap_worker_profiles WHERE local_worker_id = ?", bindings: [localWorkerID])
            if let profile = snapshot.workerProfile {
                try Self.execute(on: database, """
                    INSERT INTO sap_worker_profiles (
                        local_worker_id, personnel_number, first_name, last_name, organization_unit,
                        role, email, is_active, role_code
                    ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?)
                    """, bindings: [
                        localWorkerID, profile.personnelNumber, profile.firstName, profile.lastName,
                        profile.organizationUnit, profile.role, profile.email, profile.isActive,
                        profile.roleCode
                    ])
            }
            try Self.execute(on: database, """
                INSERT INTO sap_refresh_metadata (
                    local_worker_id, sap_worker_id, last_successful_refresh_at
                ) VALUES (?, ?, ?)
                ON CONFLICT(local_worker_id) DO UPDATE SET
                    sap_worker_id = excluded.sap_worker_id,
                    last_successful_refresh_at = excluded.last_successful_refresh_at
                """, bindings: [
                    localWorkerID, snapshot.sapWorkerID,
                    Self.dateFormatter.string(from: refreshedAt)
                ])
            try Self.execute(on: database, "COMMIT")
        } catch {
            try? Self.execute(on: database, "ROLLBACK")
            throw error
        }
        return try await load(for: localWorkerID)
    }

    private static let dateFormatter = ISO8601DateFormatter()

    private static func migrate(on database: OpaquePointer) throws {
        let version = try query(on: database, "PRAGMA user_version") { SQLiteC.columnInt($0, 0) }.first ?? 0
        guard version < currentSchemaVersion else { return }
        try execute(on: database, "BEGIN IMMEDIATE TRANSACTION")
        do {
            try execute(on: database, """
                CREATE TABLE IF NOT EXISTS sap_notifications (
                    local_worker_id TEXT NOT NULL, notification_id TEXT NOT NULL,
                    client TEXT NOT NULL, title TEXT NOT NULL,
                    functional_location_id TEXT NOT NULL, functional_location_name TEXT NOT NULL,
                    start_date TEXT NOT NULL, end_date TEXT NOT NULL, system_status TEXT NOT NULL,
                    user_status TEXT NOT NULL, raw_payload_json TEXT NOT NULL,
                    PRIMARY KEY (local_worker_id, notification_id)
                )
                """)
            try execute(on: database, """
                CREATE TABLE IF NOT EXISTS sap_worker_profiles (
                    local_worker_id TEXT PRIMARY KEY, personnel_number TEXT NOT NULL,
                    first_name TEXT NOT NULL, last_name TEXT NOT NULL,
                    organization_unit TEXT NOT NULL, role TEXT NOT NULL, email TEXT NOT NULL,
                    is_active TEXT NOT NULL, role_code TEXT NOT NULL
                )
                """)
            try execute(on: database, """
                CREATE TABLE IF NOT EXISTS sap_refresh_metadata (
                    local_worker_id TEXT PRIMARY KEY, sap_worker_id TEXT NOT NULL,
                    last_successful_refresh_at TEXT NOT NULL
                )
                """)
            try execute(on: database, """
                CREATE INDEX IF NOT EXISTS sap_notifications_worker_date_index
                ON sap_notifications (local_worker_id, start_date, notification_id)
                """)
            try execute(on: database, "PRAGMA user_version = \(currentSchemaVersion)")
            try execute(on: database, "COMMIT")
        } catch {
            try? execute(on: database, "ROLLBACK")
            throw error
        }
    }

    private static func execute(on database: OpaquePointer, _ sql: String, bindings: [String] = []) throws {
        var statement: OpaquePointer?
        let prepared = sql.withCString { SQLiteC.prepare(database, $0, -1, &statement, nil) }
        guard prepared == SQLiteC.ok else { throw SAPReadError.serviceUnavailable }
        defer { _ = SQLiteC.finalize(statement) }
        try bind(bindings, to: statement)
        guard SQLiteC.step(statement) == SQLiteC.done else { throw SAPReadError.serviceUnavailable }
    }

    private static func query<T>(on database: OpaquePointer, _ sql: String, bindings: [String] = [], map: (OpaquePointer) -> T) throws -> [T] {
        var statement: OpaquePointer?
        let prepared = sql.withCString { SQLiteC.prepare(database, $0, -1, &statement, nil) }
        guard prepared == SQLiteC.ok else { throw SAPReadError.serviceUnavailable }
        defer { _ = SQLiteC.finalize(statement) }
        try bind(bindings, to: statement)
        var values: [T] = []
        while SQLiteC.step(statement) == SQLiteC.row {
            if let statement { values.append(map(statement)) }
        }
        return values
    }

    private static func bind(_ values: [String], to statement: OpaquePointer?) throws {
        for (index, value) in values.enumerated() {
            let result = value.withCString { SQLiteC.bindText(statement, Int32(index + 1), $0, -1, SQLiteC.transient) }
            guard result == SQLiteC.ok else { throw SAPReadError.serviceUnavailable }
        }
    }

    private static func notificationFilter(for localWorkerID: String, matching searchText: String) -> (clause: String, bindings: [String]) {
        let normalizedSearchText = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalizedSearchText.isEmpty else {
            return ("local_worker_id = ?", [localWorkerID])
        }
        let escapedSearchText = normalizedSearchText
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "%", with: "\\%")
            .replacingOccurrences(of: "_", with: "\\_")
        let pattern = "%\(escapedSearchText)%"
        return (
            """
            local_worker_id = ? AND (
                notification_id LIKE ? ESCAPE '\\' COLLATE NOCASE OR
                title LIKE ? ESCAPE '\\' COLLATE NOCASE OR
                functional_location_id LIKE ? ESCAPE '\\' COLLATE NOCASE OR
                functional_location_name LIKE ? ESCAPE '\\' COLLATE NOCASE
            )
            """,
            [localWorkerID, pattern, pattern, pattern, pattern]
        )
    }

    private static func string(at index: Int32, from statement: OpaquePointer) -> String {
        guard let text = SQLiteC.columnText(statement, index) else { return "" }
        return String(cString: text)
    }
}
