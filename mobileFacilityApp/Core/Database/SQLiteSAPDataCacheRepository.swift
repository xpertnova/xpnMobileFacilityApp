import Foundation

actor SQLiteSAPDataCacheRepository: SAPDataCacheRepository {
    private static let currentSchemaVersion: Int32 = 3
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
        structuralFilter: NotificationStructuralFilter,
        limit: Int,
        offset: Int
    ) async throws -> SAPNotificationPage {
        guard let database else { throw SAPReadError.serviceUnavailable }
        let filter = Self.notificationFilter(
            for: localWorkerID,
            matching: searchText,
            structuralFilter: structuralFilter
        )
        let totalCount = Int(try Self.query(
            on: database,
            "SELECT COUNT(*) FROM sap_notifications WHERE \(filter.clause)",
            bindings: filter.bindings,
            map: { SQLiteC.columnInt($0, 0) }
        ).first ?? 0)
        let boundedOffset = min(max(offset, 0), totalCount)
        let pageBindings = filter.bindings + [String(max(limit, 1)), String(boundedOffset)]
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
            bindings: pageBindings
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

    func loadNotificationFilterMetadata(
        for localWorkerID: String
    ) async throws -> [NotificationStructuralFilterMetadata] {
        guard let database else { throw SAPReadError.serviceUnavailable }
        return try Self.query(
            on: database,
            """
            SELECT country_code, location_code, business_entity_code, building_code,
                   trade_code, form_code, MIN(functional_location_name)
            FROM sap_notifications
            WHERE local_worker_id = ? AND business_entity_id != ''
            GROUP BY country_code, location_code, business_entity_code, building_code,
                     trade_code, form_code
            """,
            bindings: [localWorkerID]
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
                let structuralMetadata = notification.structuralFilterMetadata
                try Self.execute(on: database, """
                    INSERT INTO sap_notifications (
                        local_worker_id, notification_id, client, title, functional_location_id,
                        functional_location_name, start_date, end_date, system_status, user_status,
                        raw_payload_json, country_code, location_code, business_entity_code,
                        business_entity_id, building_code, trade_code, form_code
                    ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
                    """, bindings: [
                        localWorkerID, notification.id, notification.client, notification.title,
                        notification.functionalLocationID, notification.functionalLocationName,
                        notification.startDate, notification.endDate, notification.systemStatus,
                        notification.userStatus, notification.rawPayloadJSON,
                        structuralMetadata?.countryCode ?? "",
                        structuralMetadata?.locationCode ?? "",
                        structuralMetadata?.businessEntityCode ?? "",
                        structuralMetadata?.businessEntityID ?? "",
                        structuralMetadata?.buildingCode ?? "",
                        structuralMetadata?.tradeCode ?? "",
                        structuralMetadata?.formCode ?? ""
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
            if version < 3 {
                try execute(on: database, """
                    ALTER TABLE sap_notifications ADD COLUMN country_code TEXT NOT NULL DEFAULT ''
                    """)
                try execute(on: database, """
                    ALTER TABLE sap_notifications ADD COLUMN location_code TEXT NOT NULL DEFAULT ''
                    """)
                try execute(on: database, """
                    ALTER TABLE sap_notifications ADD COLUMN business_entity_code TEXT NOT NULL DEFAULT ''
                    """)
                try execute(on: database, """
                    ALTER TABLE sap_notifications ADD COLUMN business_entity_id TEXT NOT NULL DEFAULT ''
                    """)
                try execute(on: database, """
                    ALTER TABLE sap_notifications ADD COLUMN building_code TEXT NOT NULL DEFAULT ''
                    """)
                try execute(on: database, """
                    ALTER TABLE sap_notifications ADD COLUMN trade_code TEXT NOT NULL DEFAULT ''
                    """)
                try execute(on: database, """
                    ALTER TABLE sap_notifications ADD COLUMN form_code TEXT NOT NULL DEFAULT ''
                    """)
                try backfillStructuralFilterColumns(on: database)
            }
            try execute(on: database, """
                CREATE INDEX IF NOT EXISTS sap_notifications_worker_hierarchy_date_index
                ON sap_notifications (
                    local_worker_id, business_entity_id, building_code, trade_code, form_code,
                    start_date, notification_id
                )
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

    private static func backfillStructuralFilterColumns(on database: OpaquePointer) throws {
        let notifications = try query(
            on: database,
            """
            SELECT local_worker_id, notification_id, functional_location_name, raw_payload_json
            FROM sap_notifications
            WHERE business_entity_id = ''
            """
        ) { statement in
            (
                localWorkerID: string(at: 0, from: statement),
                notificationID: string(at: 1, from: statement),
                functionalLocationName: string(at: 2, from: statement),
                rawPayloadJSON: string(at: 3, from: statement)
            )
        }
        for notification in notifications {
            let summary = SAPNotificationSummary(
                id: notification.notificationID,
                client: "",
                title: "",
                functionalLocationID: "",
                functionalLocationName: notification.functionalLocationName,
                startDate: "",
                endDate: "",
                systemStatus: "",
                userStatus: "",
                rawPayloadJSON: notification.rawPayloadJSON
            )
            guard let metadata = summary.structuralFilterMetadata else { continue }
            try execute(on: database, """
                UPDATE sap_notifications
                SET country_code = ?, location_code = ?, business_entity_code = ?,
                    business_entity_id = ?, building_code = ?, trade_code = ?, form_code = ?
                WHERE local_worker_id = ? AND notification_id = ?
                """, bindings: [
                    metadata.countryCode,
                    metadata.locationCode,
                    metadata.businessEntityCode,
                    metadata.businessEntityID,
                    metadata.buildingCode,
                    metadata.tradeCode,
                    metadata.formCode,
                    notification.localWorkerID,
                    notification.notificationID
                ])
        }
    }

    private static func notificationFilter(
        for localWorkerID: String,
        matching searchText: String,
        structuralFilter: NotificationStructuralFilter
    ) -> (clause: String, bindings: [String]) {
        var conditions = ["local_worker_id = ?"]
        var bindings = [localWorkerID]
        if structuralFilter.hasBusinessEntity {
            conditions.append("business_entity_id = ?")
            bindings.append(structuralFilter.businessEntityID)
        }
        if !structuralFilter.buildingCode.isEmpty {
            conditions.append("building_code = ?")
            bindings.append(structuralFilter.buildingCode)
        }
        if !structuralFilter.tradeCode.isEmpty {
            conditions.append("trade_code = ?")
            bindings.append(structuralFilter.tradeCode)
        }
        if !structuralFilter.formCode.isEmpty {
            conditions.append("form_code = ?")
            bindings.append(structuralFilter.formCode)
        }
        let normalizedSearchText = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalizedSearchText.isEmpty else {
            return (conditions.joined(separator: " AND "), bindings)
        }
        let escapedSearchText = normalizedSearchText
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "%", with: "\\%")
            .replacingOccurrences(of: "_", with: "\\_")
        let pattern = "%\(escapedSearchText)%"
        conditions.append(
            """
            (
                notification_id LIKE ? ESCAPE '\\' COLLATE NOCASE OR
                title LIKE ? ESCAPE '\\' COLLATE NOCASE OR
                functional_location_id LIKE ? ESCAPE '\\' COLLATE NOCASE OR
                functional_location_name LIKE ? ESCAPE '\\' COLLATE NOCASE
            )
            """,
        )
        bindings.append(contentsOf: [pattern, pattern, pattern, pattern])
        return (conditions.joined(separator: " AND "), bindings)
    }

    private static func string(at index: Int32, from statement: OpaquePointer) -> String {
        guard let text = SQLiteC.columnText(statement, index) else { return "" }
        return String(cString: text)
    }
}
