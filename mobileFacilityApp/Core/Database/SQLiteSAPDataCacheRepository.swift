import Foundation

actor SQLiteSAPDataCacheRepository: SAPDataCacheRepository {
    private static let currentSchemaVersion: Int32 = 6
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
        let briefingPartners = try Self.query(
            on: database,
            """
            SELECT partner_id, client, function, name, contact_name, search_term_1,
                   search_term_2, street, house_number, postal_code, city, country, email
            FROM sap_briefing_partners
            WHERE local_worker_id = ?
            ORDER BY name COLLATE NOCASE, partner_id
            """,
            bindings: [localWorkerID]
        ) { statement in
            SAPBriefingPartner(
                id: Self.string(at: 0, from: statement),
                client: Self.string(at: 1, from: statement),
                function: Self.string(at: 2, from: statement),
                name: Self.string(at: 3, from: statement),
                contactName: Self.string(at: 4, from: statement),
                searchTerm1: Self.string(at: 5, from: statement),
                searchTerm2: Self.string(at: 6, from: statement),
                street: Self.string(at: 7, from: statement),
                houseNumber: Self.string(at: 8, from: statement),
                postalCode: Self.string(at: 9, from: statement),
                city: Self.string(at: 10, from: statement),
                country: Self.string(at: 11, from: statement),
                email: Self.string(at: 12, from: statement)
            )
        }
        let briefingTemplateJSON: [String] = try Self.query(
            on: database,
            """
            SELECT template_json
            FROM sap_briefing_templates
            WHERE local_worker_id = ?
            ORDER BY template_id
            """,
            bindings: [localWorkerID]
        ) { statement in
            Self.string(at: 0, from: statement)
        }
        let briefingTemplates: [SAPBriefingTemplate] = briefingTemplateJSON.compactMap { json in
            guard let data = json.data(using: .utf8) else { return nil }
            return try? JSONDecoder().decode(SAPBriefingTemplate.self, from: data)
        }
        return SAPCachedData(
            notifications: [],
            workerProfile: profile,
            briefingPartners: briefingPartners,
            briefingTemplates: briefingTemplates,
            metadata: metadata
        )
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
                   equipment_id, start_date, end_date, system_status, user_status, raw_payload_json
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
                equipmentID: Self.string(at: 5, from: statement),
                startDate: Self.string(at: 6, from: statement),
                endDate: Self.string(at: 7, from: statement),
                systemStatus: Self.string(at: 8, from: statement),
                userStatus: Self.string(at: 9, from: statement),
                rawPayloadJSON: Self.string(at: 10, from: statement)
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

    func loadTechnicalObjectRoots(
        for localWorkerID: String,
        limit: Int,
        offset: Int
    ) async throws -> TechnicalObjectPage {
        guard let database else { throw SAPReadError.serviceUnavailable }
        var roots = try Self.loadTechnicalObjects(
            on: database,
            whereClause: "local_worker_id = ? AND parent_id = '' AND is_unassigned = 0",
            bindings: [localWorkerID]
        )
        let unassignedCount = Int(try Self.query(
            on: database,
            "SELECT COUNT(*) FROM sap_technical_objects WHERE local_worker_id = ? AND is_unassigned = 1",
            bindings: [localWorkerID],
            map: { SQLiteC.columnInt($0, 0) }
        ).first ?? 0)
        if unassignedCount > 0 {
            var unassigned = TechnicalObjectNode.unassignedRoot
            unassigned.directChildCount = unassignedCount
            roots.append(unassigned)
        }
        return Self.technicalObjectPage(roots, limit: limit, offset: offset)
    }

    func loadTechnicalObjectChildren(
        for localWorkerID: String,
        parent: TechnicalObjectReference,
        limit: Int,
        offset: Int
    ) async throws -> TechnicalObjectPage {
        guard let database else { throw SAPReadError.serviceUnavailable }
        let children: [TechnicalObjectNode]
        if parent == .unassigned {
            children = try Self.loadTechnicalObjects(
                on: database,
                whereClause: "local_worker_id = ? AND is_unassigned = 1",
                bindings: [localWorkerID]
            )
        } else {
            children = try Self.loadTechnicalObjects(
                on: database,
                whereClause: "local_worker_id = ? AND parent_kind = ? AND parent_id = ? AND is_unassigned = 0",
                bindings: [localWorkerID, parent.kind.rawValue, parent.objectID]
            )
        }
        return Self.technicalObjectPage(children, limit: limit, offset: offset)
    }

    func searchTechnicalObjects(
        for localWorkerID: String,
        query: String,
        dinGroup: String?
    ) async throws -> [TechnicalObjectNode] {
        guard let database else { throw SAPReadError.serviceUnavailable }
        let all = try Self.loadTechnicalObjects(
            on: database,
            whereClause: "local_worker_id = ?",
            bindings: [localWorkerID]
        )
        let normalizedQuery = query.trimmingCharacters(in: .whitespacesAndNewlines)
        let matches = all.filter { object in
            let dinMatches = dinGroup == nil || object.dinGroup == dinGroup
            let searchText = [
                object.reference.objectID, object.name, object.cityName,
                object.countryCode, object.locationCode, object.manufacturer,
                object.modelType, object.serialNumber, object.dinGroup ?? ""
            ].joined(separator: " ")
            return dinMatches && (normalizedQuery.isEmpty || searchText.localizedCaseInsensitiveContains(normalizedQuery))
        }
        let byReference = Dictionary(uniqueKeysWithValues: all.map { ($0.reference, $0) })
        var included = Set(matches.map(\.reference))
        for match in matches {
            var parent = match.parent
            while let reference = parent, let object = byReference[reference] {
                guard included.insert(reference).inserted else { break }
                parent = object.parent
            }
        }
        return all.filter { included.contains($0.reference) }
    }

    func loadTechnicalObjectDINCounts(
        for localWorkerID: String
    ) async throws -> [TechnicalObjectDINCount] {
        guard let database else { throw SAPReadError.serviceUnavailable }
        return try Self.query(
            on: database,
            """
            SELECT din_group, COUNT(*) FROM sap_technical_objects
            WHERE local_worker_id = ? AND din_group != ''
            GROUP BY din_group ORDER BY din_group
            """,
            bindings: [localWorkerID]
        ) { statement in
            TechnicalObjectDINCount(
                code: Self.string(at: 0, from: statement),
                count: Int(SQLiteC.columnInt(statement, 1))
            )
        }
    }

    func loadTechnicalObjectDetail(
        for localWorkerID: String,
        reference: TechnicalObjectReference
    ) async throws -> TechnicalObjectDetail? {
        guard let database else { throw SAPReadError.serviceUnavailable }
        let all = try Self.loadTechnicalObjects(
            on: database,
            whereClause: "local_worker_id = ?",
            bindings: [localWorkerID]
        )
        guard let object = all.first(where: { $0.reference == reference }) else { return nil }
        let byReference = Dictionary(uniqueKeysWithValues: all.map { ($0.reference, $0) })
        var breadcrumbs: [TechnicalObjectNode] = []
        var parent = object.parent
        var visited = Set<TechnicalObjectReference>()
        while let parentReference = parent,
              visited.insert(parentReference).inserted,
              let parentObject = byReference[parentReference] {
            breadcrumbs.insert(parentObject, at: 0)
            parent = parentObject.parent
        }
        let linkedNotifications = try Self.loadLinkedNotifications(
            on: database,
            for: localWorkerID,
            reference: reference
        )
        if reference.kind == .functionalLocation {
            return .functionalLocation(FunctionalLocationDetail(
                object: object,
                breadcrumbs: breadcrumbs,
                children: all.filter { $0.parent == reference },
                linkedNotifications: linkedNotifications
            ))
        }
        return .equipment(EquipmentDetail(
            object: object,
            breadcrumbs: breadcrumbs,
            linkedNotifications: linkedNotifications
        ))
    }

    func technicalObjectCount(
        for localWorkerID: String,
        kind: TechnicalObjectKind
    ) async throws -> Int {
        guard let database else { throw SAPReadError.serviceUnavailable }
        return Int(try Self.query(
            on: database,
            "SELECT COUNT(*) FROM sap_technical_objects WHERE local_worker_id = ? AND object_kind = ?",
            bindings: [localWorkerID, kind.rawValue],
            map: { SQLiteC.columnInt($0, 0) }
        ).first ?? 0)
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
                        functional_location_name, equipment_id, start_date, end_date, system_status, user_status,
                        raw_payload_json, country_code, location_code, business_entity_code,
                        business_entity_id, building_code, trade_code, form_code
                    ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
                    """, bindings: [
                        localWorkerID, notification.id, notification.client, notification.title,
                        notification.functionalLocationID, notification.functionalLocationName,
                        notification.equipmentID, notification.startDate, notification.endDate, notification.systemStatus,
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
            try Self.execute(
                on: database,
                "DELETE FROM sap_technical_objects WHERE local_worker_id = ?",
                bindings: [localWorkerID]
            )
            for object in TechnicalObjectHierarchyNormalizer.normalize(snapshot.technicalObjects) {
                try Self.insertTechnicalObject(object, for: localWorkerID, on: database)
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
            try Self.execute(
                on: database,
                "DELETE FROM sap_briefing_partners WHERE local_worker_id = ?",
                bindings: [localWorkerID]
            )
            for partner in snapshot.briefingPartners {
                try Self.execute(on: database, """
                    INSERT INTO sap_briefing_partners (
                        local_worker_id, partner_id, client, function, name, contact_name,
                        search_term_1, search_term_2, street, house_number, postal_code,
                        city, country, email
                    ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
                    """, bindings: [
                        localWorkerID, partner.id, partner.client, partner.function, partner.name,
                        partner.contactName, partner.searchTerm1, partner.searchTerm2,
                        partner.street, partner.houseNumber, partner.postalCode, partner.city,
                        partner.country, partner.email
                    ])
            }
            try Self.execute(
                on: database,
                "DELETE FROM sap_briefing_templates WHERE local_worker_id = ?",
                bindings: [localWorkerID]
            )
            let encoder = JSONEncoder()
            for template in snapshot.briefingTemplates {
                guard
                    let encodedTemplate = try? encoder.encode(template),
                    let templateJSON = String(data: encodedTemplate, encoding: .utf8)
                else {
                    throw SAPReadError.malformedPayload
                }
                try Self.execute(on: database, """
                    INSERT INTO sap_briefing_templates (
                        local_worker_id, template_id, equipment_type, planner_group, plan_type,
                        plan_number, template_json
                    ) VALUES (?, ?, ?, ?, ?, ?, ?)
                    """, bindings: [
                        localWorkerID, template.id, template.equipmentType, template.plannerGroup,
                        template.planType, template.planNumber, templateJSON
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
            if version < 4 {
                try execute(on: database, """
                    CREATE TABLE IF NOT EXISTS sap_briefing_partners (
                        local_worker_id TEXT NOT NULL, partner_id TEXT NOT NULL,
                        client TEXT NOT NULL, function TEXT NOT NULL, name TEXT NOT NULL,
                        contact_name TEXT NOT NULL, search_term_1 TEXT NOT NULL,
                        search_term_2 TEXT NOT NULL, street TEXT NOT NULL,
                        house_number TEXT NOT NULL, postal_code TEXT NOT NULL,
                        city TEXT NOT NULL, country TEXT NOT NULL, email TEXT NOT NULL,
                        PRIMARY KEY (local_worker_id, partner_id)
                    )
                    """)
                try execute(on: database, """
                    CREATE TABLE IF NOT EXISTS sap_briefing_templates (
                        local_worker_id TEXT NOT NULL, template_id TEXT NOT NULL,
                        equipment_type TEXT NOT NULL, planner_group TEXT NOT NULL,
                        plan_type TEXT NOT NULL, plan_number TEXT NOT NULL,
                        template_json TEXT NOT NULL,
                        PRIMARY KEY (local_worker_id, template_id)
                    )
                    """)
                try execute(on: database, """
                    CREATE INDEX IF NOT EXISTS sap_briefing_partners_worker_name_index
                    ON sap_briefing_partners (local_worker_id, name, partner_id)
                    """)
                try execute(on: database, """
                    CREATE INDEX IF NOT EXISTS sap_briefing_templates_worker_plan_index
                    ON sap_briefing_templates (local_worker_id, equipment_type, plan_number)
                    """)
            }
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
            if version < 5 {
                try execute(on: database, """
                    ALTER TABLE sap_notifications ADD COLUMN equipment_id TEXT NOT NULL DEFAULT ''
                    """)
                try backfillNotificationEquipmentIDs(on: database)
                try execute(on: database, """
                    CREATE TABLE IF NOT EXISTS sap_technical_objects (
                        local_worker_id TEXT NOT NULL,
                        object_kind TEXT NOT NULL,
                        object_id TEXT NOT NULL,
                        parent_kind TEXT NOT NULL,
                        parent_id TEXT NOT NULL,
                        client TEXT NOT NULL,
                        name TEXT NOT NULL,
                        functional_location_id TEXT NOT NULL,
                        hierarchy_level TEXT NOT NULL,
                        category TEXT NOT NULL,
                        structure_indicator TEXT NOT NULL,
                        equipment_category TEXT NOT NULL,
                        equipment_type TEXT NOT NULL,
                        manufacturer TEXT NOT NULL,
                        model_type TEXT NOT NULL,
                        serial_number TEXT NOT NULL,
                        system_status TEXT NOT NULL,
                        user_status TEXT NOT NULL,
                        din_group TEXT NOT NULL,
                        search_text TEXT NOT NULL,
                        source_fingerprint TEXT NOT NULL,
                        direct_child_count INTEGER NOT NULL,
                        direct_equipment_count INTEGER NOT NULL,
                        is_unassigned INTEGER NOT NULL,
                        PRIMARY KEY (local_worker_id, object_kind, object_id)
                    )
                    """)
                try execute(on: database, """
                    CREATE INDEX IF NOT EXISTS sap_technical_objects_parent_index
                    ON sap_technical_objects (local_worker_id, parent_kind, parent_id, object_kind, name)
                    """)
                try execute(on: database, """
                    CREATE INDEX IF NOT EXISTS sap_technical_objects_din_index
                    ON sap_technical_objects (local_worker_id, din_group, object_kind, name)
                    """)
                try execute(on: database, """
                    CREATE INDEX IF NOT EXISTS sap_notifications_worker_object_index
                    ON sap_notifications (local_worker_id, functional_location_id, equipment_id)
                    """)
            }
            if version < 6 {
                try execute(on: database, """
                    ALTER TABLE sap_technical_objects ADD COLUMN country_code TEXT NOT NULL DEFAULT ''
                    """)
                try execute(on: database, """
                    ALTER TABLE sap_technical_objects ADD COLUMN location_code TEXT NOT NULL DEFAULT ''
                    """)
                try execute(on: database, """
                    ALTER TABLE sap_technical_objects ADD COLUMN city_name TEXT NOT NULL DEFAULT ''
                    """)
                try execute(on: database, """
                    CREATE INDEX IF NOT EXISTS sap_technical_objects_location_index
                    ON sap_technical_objects (local_worker_id, country_code, location_code, object_kind, name)
                    """)
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

    private static func insertTechnicalObject(
        _ object: TechnicalObjectNode,
        for localWorkerID: String,
        on database: OpaquePointer
    ) throws {
        let searchText = [
            object.reference.objectID, object.name, object.functionalLocationID,
            object.countryCode, object.locationCode, object.cityName,
            object.manufacturer, object.modelType, object.serialNumber,
            object.dinGroup ?? ""
        ]
        .joined(separator: " ")
        .folding(options: [.caseInsensitive, .diacriticInsensitive], locale: .current)
        try execute(on: database, """
            INSERT INTO sap_technical_objects (
                local_worker_id, object_kind, object_id, parent_kind, parent_id,
                client, name, functional_location_id, hierarchy_level, category,
                structure_indicator, equipment_category, equipment_type, manufacturer,
                model_type, serial_number, system_status, user_status, din_group,
                search_text, source_fingerprint, direct_child_count, direct_equipment_count,
                is_unassigned, country_code, location_code, city_name
            ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
            """, bindings: [
                localWorkerID,
                object.reference.kind.rawValue,
                object.reference.objectID,
                object.parent?.kind.rawValue ?? "",
                object.parent?.objectID ?? "",
                object.client,
                object.name,
                object.functionalLocationID,
                object.hierarchyLevel,
                object.category,
                object.structureIndicator,
                object.equipmentCategory,
                object.equipmentType,
                object.manufacturer,
                object.modelType,
                object.serialNumber,
                object.systemStatus,
                object.userStatus,
                object.dinGroup ?? "",
                searchText,
                object.sourceFingerprint,
                String(object.directChildCount),
                String(object.directEquipmentCount),
                object.isUnassigned ? "1" : "0",
                object.countryCode,
                object.locationCode,
                object.cityName
            ])
    }

    private static func loadTechnicalObjects(
        on database: OpaquePointer,
        whereClause clause: String,
        bindings: [String]
    ) throws -> [TechnicalObjectNode] {
        try query(on: database, """
            SELECT object_kind, object_id, parent_kind, parent_id, client, name,
                   functional_location_id, hierarchy_level, category, structure_indicator,
                   equipment_category, equipment_type, manufacturer, model_type, serial_number,
                   system_status, user_status, din_group, source_fingerprint,
                   direct_child_count, direct_equipment_count, is_unassigned,
                   country_code, location_code, city_name
            FROM sap_technical_objects
            WHERE \(clause)
            ORDER BY CASE object_kind WHEN 'functionalLocation' THEN 0 ELSE 1 END,
                     name COLLATE NOCASE, object_id
            """, bindings: bindings) { statement in
            let kind = TechnicalObjectKind(rawValue: string(at: 0, from: statement)) ?? .functionalLocation
            let parentKindValue = string(at: 2, from: statement)
            let parentID = string(at: 3, from: statement)
            let parentKind = TechnicalObjectKind(rawValue: parentKindValue)
            return TechnicalObjectNode(
                reference: TechnicalObjectReference(
                    kind: kind,
                    objectID: string(at: 1, from: statement)
                ),
                parent: parentID.isEmpty || parentKind == nil
                    ? nil
                    : TechnicalObjectReference(kind: parentKind!, objectID: parentID),
                client: string(at: 4, from: statement),
                name: string(at: 5, from: statement),
                functionalLocationID: string(at: 6, from: statement),
                countryCode: string(at: 22, from: statement),
                locationCode: string(at: 23, from: statement),
                cityName: string(at: 24, from: statement),
                hierarchyLevel: string(at: 7, from: statement),
                category: string(at: 8, from: statement),
                structureIndicator: string(at: 9, from: statement),
                equipmentCategory: string(at: 10, from: statement),
                equipmentType: string(at: 11, from: statement),
                manufacturer: string(at: 12, from: statement),
                modelType: string(at: 13, from: statement),
                serialNumber: string(at: 14, from: statement),
                systemStatus: string(at: 15, from: statement),
                userStatus: string(at: 16, from: statement),
                dinGroup: optionalString(at: 17, from: statement),
                sourceFingerprint: string(at: 18, from: statement),
                directChildCount: Int(SQLiteC.columnInt(statement, 19)),
                directEquipmentCount: Int(SQLiteC.columnInt(statement, 20)),
                isUnassigned: SQLiteC.columnInt(statement, 21) != 0,
                isSynthetic: false
            )
        }
    }

    private static func technicalObjectPage(
        _ source: [TechnicalObjectNode],
        limit: Int,
        offset: Int
    ) -> TechnicalObjectPage {
        let sorted = source.sorted {
            if $0.isSynthetic != $1.isSynthetic { return !$0.isSynthetic }
            if $0.reference.kind != $1.reference.kind {
                return $0.reference.kind == .functionalLocation
            }
            let order = $0.displayName.localizedStandardCompare($1.displayName)
            return order == .orderedSame
                ? $0.reference.objectID < $1.reference.objectID
                : order == .orderedAscending
        }
        let boundedOffset = min(max(offset, 0), sorted.count)
        let end = min(boundedOffset + max(limit, 1), sorted.count)
        return TechnicalObjectPage(
            objects: Array(sorted[boundedOffset..<end]),
            nextOffset: end < sorted.count ? end : nil,
            totalCount: sorted.count
        )
    }

    private static func loadLinkedNotifications(
        on database: OpaquePointer,
        for localWorkerID: String,
        reference: TechnicalObjectReference
    ) throws -> [SAPNotificationSummary] {
        let field = reference.kind == .equipment ? "equipment_id" : "functional_location_id"
        return try query(on: database, """
            SELECT notification_id, client, title, functional_location_id,
                   functional_location_name, equipment_id, start_date, end_date,
                   system_status, user_status, raw_payload_json
            FROM sap_notifications
            WHERE local_worker_id = ? AND \(field) = ?
            ORDER BY start_date, notification_id
            """, bindings: [localWorkerID, reference.objectID]) { statement in
            SAPNotificationSummary(
                id: string(at: 0, from: statement),
                client: string(at: 1, from: statement),
                title: string(at: 2, from: statement),
                functionalLocationID: string(at: 3, from: statement),
                functionalLocationName: string(at: 4, from: statement),
                equipmentID: string(at: 5, from: statement),
                startDate: string(at: 6, from: statement),
                endDate: string(at: 7, from: statement),
                systemStatus: string(at: 8, from: statement),
                userStatus: string(at: 9, from: statement),
                rawPayloadJSON: string(at: 10, from: statement)
            )
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

    private static func backfillNotificationEquipmentIDs(on database: OpaquePointer) throws {
        let notifications = try query(
            on: database,
            "SELECT local_worker_id, notification_id, raw_payload_json FROM sap_notifications"
        ) { statement in
            (
                workerID: string(at: 0, from: statement),
                notificationID: string(at: 1, from: statement),
                rawPayloadJSON: string(at: 2, from: statement)
            )
        }
        for notification in notifications {
            let summary = SAPNotificationSummary(
                id: notification.notificationID,
                client: "",
                title: "",
                functionalLocationID: "",
                functionalLocationName: "",
                startDate: "",
                endDate: "",
                systemStatus: "",
                userStatus: "",
                rawPayloadJSON: notification.rawPayloadJSON
            )
            let equipmentID = SAPNotificationDetail(summary: summary).equipmentID
            guard !equipmentID.isEmpty else { continue }
            try execute(on: database, """
                UPDATE sap_notifications SET equipment_id = ?
                WHERE local_worker_id = ? AND notification_id = ?
                """, bindings: [equipmentID, notification.workerID, notification.notificationID])
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

    private static func optionalString(at index: Int32, from statement: OpaquePointer) -> String? {
        guard SQLiteC.columnType(statement, index) != SQLiteC.null else { return nil }
        let value = string(at: index, from: statement)
        return value.isEmpty ? nil : value
    }
}
