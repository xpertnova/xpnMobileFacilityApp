import Foundation

typealias SQLiteDestructor = @convention(c) (UnsafeMutableRawPointer?) -> Void

enum SQLiteC {
    static let ok: Int32 = 0
    static let row: Int32 = 100
    static let done: Int32 = 101
    static let null: Int32 = 5
    static let openReadWrite: Int32 = 0x00000002
    static let openCreate: Int32 = 0x00000004
    static let openFullMutex: Int32 = 0x00010000
    static let transient = unsafeBitCast(-1, to: SQLiteDestructor.self)

    @_silgen_name("sqlite3_open_v2") static func open(_ filename: UnsafePointer<CChar>?, _ database: UnsafeMutablePointer<OpaquePointer?>?, _ flags: Int32, _ vfs: UnsafePointer<CChar>?) -> Int32
    @_silgen_name("sqlite3_close") static func close(_ database: OpaquePointer?) -> Int32
    @_silgen_name("sqlite3_prepare_v2") static func prepare(_ database: OpaquePointer?, _ sql: UnsafePointer<CChar>?, _ length: Int32, _ statement: UnsafeMutablePointer<OpaquePointer?>?, _ tail: UnsafeMutablePointer<UnsafePointer<CChar>?>?) -> Int32
    @_silgen_name("sqlite3_finalize") static func finalize(_ statement: OpaquePointer?) -> Int32
    @_silgen_name("sqlite3_step") static func step(_ statement: OpaquePointer?) -> Int32
    @_silgen_name("sqlite3_bind_text") static func bindText(_ statement: OpaquePointer?, _ index: Int32, _ value: UnsafePointer<CChar>?, _ length: Int32, _ destructor: SQLiteDestructor?) -> Int32
    @_silgen_name("sqlite3_bind_null") static func bindNull(_ statement: OpaquePointer?, _ index: Int32) -> Int32
    @_silgen_name("sqlite3_column_text") static func columnText(_ statement: OpaquePointer?, _ index: Int32) -> UnsafePointer<CChar>?
    @_silgen_name("sqlite3_column_int") static func columnInt(_ statement: OpaquePointer?, _ index: Int32) -> Int32
    @_silgen_name("sqlite3_column_int64") static func columnInt64(_ statement: OpaquePointer?, _ index: Int32) -> Int64
    @_silgen_name("sqlite3_column_type") static func columnType(_ statement: OpaquePointer?, _ index: Int32) -> Int32
}

actor SQLiteOfflineWorkRepository: OfflineWorkRepository {
    private static let currentSchemaVersion: Int32 = 1
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
            url = directory.appendingPathComponent("offline-work.sqlite")
        }

        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        var openedDatabase: OpaquePointer?
        let result = url.path.withCString {
            SQLiteC.open($0, &openedDatabase, SQLiteC.openCreate | SQLiteC.openReadWrite | SQLiteC.openFullMutex, nil)
        }
        guard result == SQLiteC.ok, let openedDatabase else { throw OfflineWorkRepositoryError.unavailable }
        database = openedDatabase
        do {
            try Self.execute(on: openedDatabase, "PRAGMA foreign_keys = ON")
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

    func loadWork(for workerID: String) async throws -> [OfflineWorkItem] {
        guard let database else { throw OfflineWorkRepositoryError.unavailable }
        let rows = try Self.query(
            on: database,
            """
            SELECT id, worker_id, type, status, payload_json, created_at, updated_at, sync_error
            FROM offline_work_items WHERE worker_id = ? ORDER BY updated_at DESC
            """,
            bindings: [workerID]
        ) { statement in
            (
                Self.string(at: 0, from: statement), Self.string(at: 1, from: statement),
                Self.string(at: 2, from: statement), Self.string(at: 3, from: statement),
                Self.string(at: 4, from: statement), Self.string(at: 5, from: statement),
                Self.string(at: 6, from: statement), Self.optionalString(at: 7, from: statement)
            )
        }

        let decoder = JSONDecoder()
        let formatter = ISO8601DateFormatter()
        return try rows.map { row in
            guard let id = UUID(uuidString: row.0), let type = OfflineWorkType(rawValue: row.2),
                  let status = OfflineWorkStatus(rawValue: row.3), let data = row.4.data(using: .utf8),
                  let createdAt = formatter.date(from: row.5), let updatedAt = formatter.date(from: row.6) else {
                throw OfflineWorkRepositoryError.invalidStoredItem
            }
            let payload: OfflineWorkPayload
            switch type {
            case .manualCapture:
                payload = .manualCapture(try decoder.decode(ManualCaptureDraftPayload.self, from: data))
            case .defect:
                payload = .defect(try decoder.decode(DefectDraftPayload.self, from: data))
            case .meterReading:
                payload = .meterReading(try decoder.decode(MeterReadingDraftPayload.self, from: data))
            case .notificationReview:
                payload = .notificationReview(try decoder.decode(NotificationReviewDraftPayload.self, from: data))
            case .briefing:
                payload = .briefing(try decoder.decode(BriefingDraftPayload.self, from: data))
            case .electricalSafety:
                payload = .electricalSafety(try decoder.decode(ElectricalSafetyDraftPayload.self, from: data))
            case .technicalObjectEdit:
                payload = .technicalObjectEdit(try decoder.decode(TechnicalObjectEditPayload.self, from: data))
            case .proofOfQualification:
                payload = .proofOfQualification(try decoder.decode(ProofOfQualificationDraftPayload.self, from: data))
            }
            return OfflineWorkItem(id: id, workerID: row.1, type: type, status: status,
                                   payload: payload, createdAt: createdAt, updatedAt: updatedAt, syncError: row.7)
        }
    }

    func save(_ item: OfflineWorkItem) async throws {
        guard let database else { throw OfflineWorkRepositoryError.unavailable }
        let payloadData: Data?
        switch (item.type, item.payload) {
        case let (.manualCapture, .manualCapture(payload)):
            payloadData = try? JSONEncoder().encode(payload)
        case let (.defect, .defect(payload)):
            payloadData = try? JSONEncoder().encode(payload)
        case let (.meterReading, .meterReading(payload)):
            payloadData = try? JSONEncoder().encode(payload)
        case let (.notificationReview, .notificationReview(payload)):
            payloadData = try? JSONEncoder().encode(payload)
        case let (.briefing, .briefing(payload)):
            payloadData = try? JSONEncoder().encode(payload)
        case let (.electricalSafety, .electricalSafety(payload)):
            payloadData = try? JSONEncoder().encode(payload)
        case let (.technicalObjectEdit, .technicalObjectEdit(payload)):
            payloadData = try? JSONEncoder().encode(payload)
        case let (.proofOfQualification, .proofOfQualification(payload)):
            payloadData = try? JSONEncoder().encode(payload)
        default:
            payloadData = nil
        }
        guard let payloadData, let payloadJSON = String(data: payloadData, encoding: .utf8) else {
            throw OfflineWorkRepositoryError.invalidStoredItem
        }
        let formatter = ISO8601DateFormatter()
        try Self.execute(on: database, """
            INSERT INTO offline_work_items (id, worker_id, type, status, payload_json, created_at, updated_at, sync_error)
            VALUES (?, ?, ?, ?, ?, ?, ?, ?)
            ON CONFLICT(id) DO UPDATE SET worker_id = excluded.worker_id, type = excluded.type,
            status = excluded.status, payload_json = excluded.payload_json, updated_at = excluded.updated_at,
            sync_error = excluded.sync_error
            """, bindings: [item.id.uuidString, item.workerID, item.type.rawValue, item.status.rawValue,
                               payloadJSON, formatter.string(from: item.createdAt), formatter.string(from: item.updatedAt), item.syncError ?? ""])
    }


    func resetWork(for workerID: String) async throws {
        guard let database else { throw OfflineWorkRepositoryError.unavailable }
        try Self.execute(on: database, "DELETE FROM offline_work_items WHERE worker_id = ?", bindings: [workerID])
    }

    private static func migrate(on database: OpaquePointer) throws {
        let version = try query(on: database, "PRAGMA user_version") { SQLiteC.columnInt($0, 0) }.first ?? 0
        guard version < currentSchemaVersion else { return }
        try execute(on: database, "BEGIN IMMEDIATE TRANSACTION")
        do {
            try execute(on: database, """
                CREATE TABLE IF NOT EXISTS offline_work_items (
                    id TEXT PRIMARY KEY NOT NULL, worker_id TEXT NOT NULL, type TEXT NOT NULL,
                    status TEXT NOT NULL, payload_json TEXT NOT NULL, created_at TEXT NOT NULL,
                    updated_at TEXT NOT NULL, sync_error TEXT
                )
                """)
            try execute(on: database, "CREATE INDEX IF NOT EXISTS offline_work_by_worker_updated ON offline_work_items(worker_id, updated_at DESC)")
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
        guard prepared == SQLiteC.ok else { throw OfflineWorkRepositoryError.unavailable }
        defer { _ = SQLiteC.finalize(statement) }
        try bind(bindings, to: statement)
        guard SQLiteC.step(statement) == SQLiteC.done else { throw OfflineWorkRepositoryError.unavailable }
    }

    private static func query<T>(on database: OpaquePointer, _ sql: String, bindings: [String] = [], map: (OpaquePointer) -> T) throws -> [T] {
        var statement: OpaquePointer?
        let prepared = sql.withCString { SQLiteC.prepare(database, $0, -1, &statement, nil) }
        guard prepared == SQLiteC.ok else { throw OfflineWorkRepositoryError.unavailable }
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
            guard result == SQLiteC.ok else { throw OfflineWorkRepositoryError.unavailable }
        }
    }

    private static func string(at index: Int32, from statement: OpaquePointer) -> String {
        guard let text = SQLiteC.columnText(statement, index) else { return "" }
        return String(cString: text)
    }

    private static func optionalString(at index: Int32, from statement: OpaquePointer) -> String? {
        guard SQLiteC.columnType(statement, index) != SQLiteC.null else { return nil }
        let value = string(at: index, from: statement)
        return value.isEmpty ? nil : value
    }
}
