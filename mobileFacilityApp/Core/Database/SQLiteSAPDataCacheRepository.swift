import CryptoKit
import Foundation

/// The legacy synchronization protocol uses shared `TMP_FROM_*` tables. More
/// than one repository can be composed for the same worker cache while the app
/// changes roots, so the lease is process-wide rather than actor-local.
private actor LegacyIncomingSynchronizationRegistry {
    private var activeDatabasePaths: Set<String> = []

    func acquire(databasePath: String) -> Bool {
        activeDatabasePaths.insert(databasePath).inserted
    }

    func release(databasePath: String) {
        activeDatabasePaths.remove(databasePath)
    }
}

private let legacyIncomingSynchronizationRegistry = LegacyIncomingSynchronizationRegistry()

actor SQLiteSAPDataCacheRepository: SAPDataCacheRepository, SAPLegacySynchronizationStore, SAPNotificationOutgoingStore, MobileLadderCreationProviding, ElevatorAssetDataProviding, SubdistributionCreationProviding {
    private static let metadataCategory = "MOBILE_FACILITY_APP"
    private static let refreshParameter = "LAST_SUCCESSFUL_REFRESH_AT"
    private static let workerParameter = "SAP_WORKER_ID"

    private static let outgoingMappings: [(source: String, temporary: String, payload: String)] = [
        ("TO_T0281", "TMP_TO_T0281", "T_0281"),
        ("TO_T0283", "TMP_TO_T0283", "T_0283"),
        ("TO_LOGGER", "TMP_TO_LOGGER", "T_0152R"),
        ("TO_USER_PUK", "TMP_TO_USER_PUK", "T_0154R"),
        ("TO_T0211", "TMP_TO_T0211", "T_0211R"),
        ("TO_T0212", "TMP_TO_T0212", "T_0212R"),
        ("TO_T0265", "TMP_TO_T0265", "T_0265"),
        ("TO_T0266", "TMP_TO_T0266", "T_0266"),
        ("TO_T0282", "TMP_TO_T0282", "T_0282"),
        ("TO_T0284", "TMP_TO_T0284", "T_0284"),
        ("TO_T0285", "TMP_TO_T0285", "T_0285"),
        ("TO_T0286", "TMP_TO_T0286", "T_0286"),
        ("TO_T0300", "TMP_TO_T0300", "T_0300"),
        ("TO_T0302", "TMP_TO_T0302", "T_0302")
    ]

    nonisolated let databaseURL: URL
    private let localWorkerID: String?
    private let notificationListIndex: SQLiteNotificationListIndex?
    private var database: OpaquePointer?
    private var stagedOutgoingRowIDs: [String: [Int64]] = [:]
    private var stagedOutgoingRequestID: String?
    private var incomingUserRows: [LegacySAPRow] = []
    private var incomingSawUserTable = false
    private var incomingSawLastPackage = false
    private var incomingSynchronizationIsActive = false

    init(databaseURL: URL, workerID: String? = nil) throws {
        self.databaseURL = databaseURL
        localWorkerID = workerID
        notificationListIndex = try? SQLiteNotificationListIndex(
            databaseURL: databaseURL
                .deletingLastPathComponent()
                .appendingPathComponent("notification-list-index.sqlite")
        )
        try FileManager.default.createDirectory(
            at: databaseURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        var openedDatabase: OpaquePointer?
        let result = databaseURL.path.withCString {
            SQLiteC.open($0, &openedDatabase, SQLiteC.openCreate | SQLiteC.openReadWrite | SQLiteC.openFullMutex, nil)
        }
        guard result == SQLiteC.ok, let openedDatabase else { throw SAPReadError.serviceUnavailable }
        database = openedDatabase
        do {
            try Self.initialize(on: openedDatabase)
        } catch {
            _ = SQLiteC.close(openedDatabase)
            database = nil
            throw error
        }
    }

    static func production(workerID: String) throws -> SQLiteSAPDataCacheRepository {
        try SQLiteSAPDataCacheRepository(
            databaseURL: productionDatabaseURL(workerID: workerID),
            workerID: workerID
        )
    }

    static func productionDatabaseURL(workerID: String) throws -> URL {
        let directory = try FileManager.default.url(
            for: .applicationSupportDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: true
        )
        let identity = workerID
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .uppercased(with: Locale(identifier: "en_US_POSIX"))
        guard !identity.isEmpty else { throw SAPReadError.serviceUnavailable }
        let digest = SHA256.hash(data: Data(identity.utf8))
            .map { String(format: "%02x", $0) }
            .joined()
        return directory
            .appendingPathComponent(digest, isDirectory: true)
            .appendingPathComponent(LegacySQLiteSchema.databaseFileName)
    }

    deinit {
        _ = SQLiteC.close(database)
    }

    func load(for localWorkerID: String) async throws -> SAPCachedData {
        try validateWorker(localWorkerID)
        guard let database else { throw SAPReadError.serviceUnavailable }
        let metadata = try Self.metadata(on: database)
        if let metadata {
            await rebuildNotificationListIndexIfNeeded(
                for: localWorkerID,
                metadata: metadata,
                on: database
            )
        }
        let profile = try Self.rows(in: "USER", on: database)
            .compactMap(SAPLegacyDataExchangeCodec.workerProfile(from:))
            .first
        let partners = try Self.rows(in: "FROM_T0298", on: database)
            .compactMap(SAPLegacyDataExchangeCodec.briefingPartner(from:))
            .sorted { ($0.name, $0.id) < ($1.name, $1.id) }
        let templates = try Self.rows(in: "FROM_T0267", on: database)
            .compactMap(SAPLegacyDataExchangeCodec.briefingTemplate(from:))
            .sorted { $0.id < $1.id }
        return SAPCachedData(
            notifications: [],
            workerProfile: profile,
            briefingPartners: partners,
            briefingTemplates: templates,
            technicalObjects: [],
            metadata: metadata
        )
    }

    func loadUserProfile(for workerID: String) async throws -> SAPUserProfile? {
        try validateWorker(workerID)
        guard let database else { throw SAPReadError.serviceUnavailable }
        return try Self.rows(in: "USER", on: database)
            .compactMap(SAPLegacyDataExchangeCodec.userProfile(from:))
            .first
    }

    func loadMobileLadderCreationData(for workerID: String) async throws -> MobileLadderCreationData {
        try validateWorker(workerID)
        guard let database else { throw SAPReadError.serviceUnavailable }
        let templates = SAPLegacyDataExchangeCodec.mobileLadderTemplates(
            planRows: try Self.rows(in: "FROM_T0267", on: database),
            classRows: try Self.rows(in: "FROM_T0263", on: database),
            equipmentRows: try Self.rows(in: "FROM_T0268", on: database)
        )
        guard !templates.isEmpty else { return .empty }

        let contexts = try Self.rows(in: "FROM_T0272", on: database).compactMap { row -> MobileLadderCreationContext? in
            func string(_ key: String) -> String { row[key] as? String ?? "" }
            let deletionFlag = string("LVORM").uppercased()
            let userStatus = string("USTXT")
            guard deletionFlag != "X", userStatus.isEmpty || userStatus.localizedCaseInsensitiveContains("iBet") else {
                return nil
            }
            let functionalLocation = string("STRNO").isEmpty ? string("TPLNR") : string("STRNO")
            let trade = string("TPGSG")
            guard !functionalLocation.isEmpty, !trade.isEmpty else { return nil }
            let template = templates.first {
                ($0.plant.isEmpty || $0.plant == string("IWERK"))
                    && ($0.plannerGroup.isEmpty || $0.plannerGroup == string("INGRP"))
            } ?? templates.first
            guard let template,
                  let sourceData = try? JSONSerialization.data(withJSONObject: row, options: [.sortedKeys]),
                  let sourceJSON = String(data: sourceData, encoding: .utf8) else { return nil }

            let cityLine = [string("POST_CODE1"), string("CITY1")].filter { !$0.isEmpty }.joined(separator: " ")
            let businessCode = [string("TPLND"), string("TPORT"), string("TPWEH")]
                .filter { !$0.isEmpty }.joined(separator: "-")
            let businessTitle = [businessCode, cityLine, string("STREET")].filter { !$0.isEmpty }.joined(separator: " · ")
            let buildingTitle = [string("TPGEB"), string("PLTXT")].filter { !$0.isEmpty }.joined(separator: " · ")
            let tradeTitle = [trade, functionalLocation].filter { !$0.isEmpty }.joined(separator: " · ")
            return MobileLadderCreationContext(
                businessEntity: businessTitle.isEmpty ? string("TPWEH") : businessTitle,
                building: buildingTitle.isEmpty ? functionalLocation : buildingTitle,
                trade: tradeTitle,
                legacyContext: MobileLadderLegacyContext(
                    client: string("MANDT"), functionalLocation: functionalLocation,
                    country: string("TPLND"), location: string("TPORT"), businessEntity: string("TPWEH"),
                    building: string("TPGEB"), trade: trade, plant: string("IWERK"),
                    plannerGroup: string("INGRP"), workCenter: string("GEWRK").isEmpty ? string("ARBPL") : string("GEWRK"),
                    addressNumber: string("ADRNR"), contactName: string("NAME_LIST"), city: string("CITY1"),
                    postalCode: string("POST_CODE1"), street: string("STREET"),
                    sourceNotificationJSON: sourceJSON, template: template
                )
            )
        }
        let uniqueContexts = Dictionary(grouping: contexts, by: \MobileLadderCreationContext.id)
            .compactMap { $0.value.first }
            .sorted { ($0.businessEntity, $0.building, $0.trade) < ($1.businessEntity, $1.building, $1.trade) }
        let catalogPairs: [(MobileLadderCatalogField, String)] = [
            (.material, "TFMMOBLEITER_WERKSTOFF"),
            (.constructionType, "TFMMOBLEITER_BAUART"),
            (.manufacturer, "TFMMOBLEITER_HERSTELLER"),
            (.clientCompany, "TFMMOBLEITER_GESELLSCHAFT")
        ]
        var catalog: [MobileLadderCatalogField: [String]] = [:]
        for (field, characteristicName) in catalogPairs {
            var values = templates
                .flatMap(\.characteristics)
                .filter { $0.name.caseInsensitiveCompare(characteristicName) == .orderedSame }
                .flatMap(\.values)
                .map { $0.title.isEmpty ? $0.value : $0.title }
                .uniquedAndSorted()

            if field == .clientCompany {
                if let userRows = try? Self.rows(in: "USER", on: database) {
                    for row in userRows {
                        if let company = (row["GESELLSCHAFT"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines),
                           !company.isEmpty,
                           !values.contains(where: { $0.caseInsensitiveCompare(company) == .orderedSame }) {
                            values.append(company)
                        }
                    }
                }
                if !values.contains(where: { $0.caseInsensitiveCompare("Pflege durch Admin") == .orderedSame }) {
                    values.insert("Pflege durch Admin", at: 0)
                }
            }

            catalog[field] = values.isEmpty ? MobileLadderCatalog.legacyReference.options(for: field) : values
        }
        return MobileLadderCreationData(contexts: uniqueContexts, catalog: MobileLadderCatalog(options: catalog))
    }

    /// Rebuilds the read-only TFM2 header section from the same legacy cache
    /// tables used by Cordova: T0263 describes the class, while T0266 (or
    /// T0265 for a technical-place assignment) supplies the asset values.
    func loadElevatorAssetData(for notification: SAPNotificationSummary) async throws -> ElevatorAssetData {
        try validateWorker(localWorkerID ?? "")
        guard let database else { throw SAPReadError.serviceUnavailable }

        func value(named key: String, in row: [String: Any]) -> Any? {
            row.first { $0.key.caseInsensitiveCompare(key) == .orderedSame }?.value
        }

        func string(named key: String, in row: [String: Any]) -> String {
            switch value(named: key, in: row) {
            case let value as String:
                value.trimmingCharacters(in: .whitespacesAndNewlines)
            case let value as NSNumber:
                value.stringValue
            default:
                ""
            }
        }

        func dictionaries(named key: String, in dictionary: [String: Any]) -> [[String: Any]] {
            guard let rawValue = value(named: key, in: dictionary) else { return [] }
            if let dicts = rawValue as? [[String: Any]] { return dicts }
            if let list = rawValue as? [Any] { return list.compactMap { $0 as? [String: Any] } }
            return []
        }

        func decodedPayload(from row: [String: Any]) -> [String: Any]? {
            let fieldValue = string(named: "FELDWERT", in: row)
            guard !fieldValue.isEmpty else { return nil }
            return SAPLegacyDataExchangeCodec.decodedFeldwertObject(fieldValue)
        }

        func elevatorType(row: [String: Any], payload: [String: Any]) -> String {
            string(named: "EQART", in: row)
                .ifEmpty(string(named: "EQART_TO", in: row))
                .ifEmpty(string(named: "EQART", in: payload))
                .ifEmpty(string(named: "EQART_TO", in: payload))
                .uppercased()
        }

        let equipmentRows = try Self.rows(in: "FROM_T0266", on: database)
        let locationRows = try Self.rows(in: "FROM_T0265", on: database)
        var masterRow: [String: Any]?
        if !notification.equipmentID.isEmpty {
            masterRow = equipmentRows.first {
                string(named: "EQUNR", in: $0) == notification.equipmentID
            }
        }
        if masterRow == nil && !notification.functionalLocationID.isEmpty {
            masterRow = locationRows.first {
                let locationID = string(named: "STRNO", in: $0).ifEmpty(string(named: "TPLNR", in: $0))
                return locationID.caseInsensitiveCompare(notification.functionalLocationID) == .orderedSame
            }
        }
        if masterRow == nil && !notification.equipmentID.isEmpty {
            masterRow = locationRows.first {
                string(named: "EQUNR", in: $0) == notification.equipmentID
            }
        }
        guard let masterRow else {
            SAPSynchronizationDiagnostics.logElevatorAssetCacheResolution("no matching master record")
            return .empty
        }
        guard let masterPayload = decodedPayload(from: masterRow) else {
            SAPSynchronizationDiagnostics.logElevatorAssetCacheResolution("matching master record has no readable FELDWERT")
            return .empty
        }

        let type = elevatorType(row: masterRow, payload: masterPayload)
        let supportedTypes: Set<String> = ["TFMPERS", "TFMLAST", "TFMBEFAHR", "TFMKLGUT"]
        let masterClassNames = Set(
            (dictionaries(named: "T_CLASS_EQ", in: masterPayload) + dictionaries(named: "T_CLASS_TP", in: masterPayload))
                .compactMap {
                    let name = string(named: "CLASS", in: $0).ifEmpty(string(named: "KLASSE", in: $0)).uppercased()
                    return name.isEmpty ? nil : name
                }
        )

        let resolvedType: String
        if supportedTypes.contains(type) {
            resolvedType = type
        } else if masterClassNames.contains("TFMAUFZUG") {
            resolvedType = type.isEmpty ? "TFMPERS" : type
        } else {
            SAPSynchronizationDiagnostics.logElevatorAssetCacheResolution("master record is not a supported elevator type")
            return .empty
        }

        let classRows = try Self.rows(in: "FROM_T0263", on: database)
        let classRow = classRows.first { row in
            guard let payload = decodedPayload(from: row) else { return false }
            return elevatorType(row: row, payload: payload) == resolvedType
        } ?? classRows.first { row in
            guard let payload = decodedPayload(from: row) else { return false }
            let rowClass = string(named: "CLASS", in: row).ifEmpty(string(named: "CLASS", in: payload)).uppercased()
            return rowClass == resolvedType || masterClassNames.contains(rowClass) || rowClass == "TFMAUFZUG"
        }
        guard let classRow else {
            SAPSynchronizationDiagnostics.logElevatorAssetCacheResolution("no matching class definition")
            return .empty
        }
        guard let classPayload = decodedPayload(from: classRow) else {
            SAPSynchronizationDiagnostics.logElevatorAssetCacheResolution("matching class definition has no readable FELDWERT")
            return .empty
        }

        guard let assetData = ElevatorAssetDataDecoder.decode(
            equipmentType: resolvedType,
            classDefinition: classPayload,
            masterData: masterPayload
        ) else {
            SAPSynchronizationDiagnostics.logElevatorAssetCacheResolution("class definition has no usable characteristics")
            return .empty
        }
        SAPSynchronizationDiagnostics.logElevatorAssetCacheResolution(
            "loaded \(assetData.characteristics.count) classification characteristics"
        )
        return assetData
    }

    func loadSubdistributionCreationData(for workerID: String) async throws -> SubdistributionCreationData {
        try validateWorker(workerID)
        guard let database else { throw SAPReadError.serviceUnavailable }
        let templates = SAPLegacyDataExchangeCodec.subdistributionTemplates(
            planRows: try Self.rows(in: "FROM_T0267", on: database),
            classRows: try Self.rows(in: "FROM_T0263", on: database),
            equipmentRows: try Self.rows(in: "FROM_T0268", on: database)
        )
        guard !templates.isEmpty else { return .empty }

        let contexts = try Self.rows(in: "FROM_T0272", on: database).compactMap { row -> SubdistributionCreationContext? in
            func string(_ key: String) -> String { row[key] as? String ?? "" }
            let deletionFlag = string("LVORM").uppercased()
            let userStatus = string("USTXT")
            let parentType = string("EQART").uppercased()
            // Cordova allows only an active existing subdistribution or
            // subdistribution distributor as the parent of TFMNSPV.
            guard deletionFlag != "X", parentType == "TFMNSPV" || parentType == "TFMNSPVER",
                  userStatus.localizedCaseInsensitiveContains("iBet")
            else { return nil }
            let functionalLocation = string("STRNO").isEmpty ? string("TPLNR") : string("STRNO")
            let building = string("TPGEB")
            let segment = string("TPGSG")
            guard !functionalLocation.isEmpty, !building.isEmpty, !segment.isEmpty else { return nil }
            guard let template = templates.first(where: {
                ($0.plant.isEmpty || $0.plant == string("IWERK"))
                    && ($0.plannerGroup.isEmpty || $0.plannerGroup == string("INGRP"))
            }) ?? templates.first,
            let sourceData = try? JSONSerialization.data(withJSONObject: row, options: [.sortedKeys]),
            let sourceJSON = String(data: sourceData, encoding: .utf8)
            else { return nil }

            let cityLine = [string("POST_CODE1"), string("CITY1")].filter { !$0.isEmpty }.joined(separator: " ")
            let businessCode = [string("TPLND"), string("TPORT"), string("TPWEH")]
                .filter { !$0.isEmpty }.joined(separator: "-")
            let businessTitle = [businessCode, cityLine, string("STREET")].filter { !$0.isEmpty }.joined(separator: " · ")
            let buildingTitle = [building, string("PLTXT")].filter { !$0.isEmpty }.joined(separator: " · ")
            let parentTitle = [functionalLocation, string("EQKTX"), string("PLTXT")]
                .filter { !$0.isEmpty }.joined(separator: " · ")
            return SubdistributionCreationContext(
                businessEntity: businessTitle.isEmpty ? string("TPWEH") : businessTitle,
                building: buildingTitle.isEmpty ? functionalLocation : buildingTitle,
                parentLocation: parentTitle,
                legacyContext: SubdistributionLegacyContext(
                    client: string("MANDT"), functionalLocation: functionalLocation, parentEquipmentType: parentType,
                    country: string("TPLND"), location: string("TPORT"), businessEntity: string("TPWEH"),
                    building: building, segment: segment, plant: string("IWERK"), plannerGroup: string("INGRP"),
                    workCenter: string("GEWRK").isEmpty ? string("ARBPL") : string("GEWRK"),
                    addressNumber: string("ADRNR"), contactName: string("NAME_LIST"), city: string("CITY1"),
                    postalCode: string("POST_CODE1"), street: string("STREET"), sourceNotificationJSON: sourceJSON,
                    template: template
                )
            )
        }
        let uniqueContexts = Dictionary(grouping: contexts, by: \SubdistributionCreationContext.id)
            .compactMap { $0.value.first }
            .sorted { ($0.businessEntity, $0.building, $0.parentLocation) < ($1.businessEntity, $1.building, $1.parentLocation) }
        return SubdistributionCreationData(contexts: uniqueContexts)
    }

    func loadNotifications(
        for localWorkerID: String,
        matching searchText: String,
        structuralFilter: NotificationStructuralFilter,
        limit: Int,
        offset: Int
    ) async throws -> SAPNotificationPage {
        try validateWorker(localWorkerID)
        guard let database else { throw SAPReadError.serviceUnavailable }
        if let indexedPage = await indexedNotificationPage(
            for: localWorkerID,
            matching: searchText,
            structuralFilter: structuralFilter,
            limit: limit,
            offset: offset,
            on: database
        ) {
            return indexedPage
        }
        let search = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        let matching = try Self.notifications(on: database)
            .filter { notification in
                let textMatches = search.isEmpty || [
                    notification.id,
                    notification.title,
                    notification.functionalLocationID,
                    notification.functionalLocationName
                ].contains { $0.localizedCaseInsensitiveContains(search) }
                return textMatches && structuralFilter.matches(notification.structuralFilterMetadata)
            }
            .sorted { ($0.startDate, $0.id) < ($1.startDate, $1.id) }
        let start = min(max(offset, 0), matching.count)
        let end = min(start + max(limit, 1), matching.count)
        return SAPNotificationPage(
            notifications: Array(matching[start..<end]),
            nextOffset: end < matching.count ? end : nil,
            totalCount: matching.count
        )
    }

    func loadNotificationFilterMetadata(
        for localWorkerID: String
    ) async throws -> [NotificationStructuralFilterMetadata] {
        try validateWorker(localWorkerID)
        guard let database else { throw SAPReadError.serviceUnavailable }
        if let indexedMetadata = await indexedNotificationFilterMetadata(
            for: localWorkerID,
            on: database
        ) {
            return indexedMetadata
        }
        let values = try Self.notifications(on: database).compactMap(\.structuralFilterMetadata)
        return Array(Set(values)).sorted { $0.id < $1.id }
    }

    func loadTechnicalObjectRoots(
        for localWorkerID: String,
        limit: Int,
        offset: Int
    ) async throws -> TechnicalObjectPage {
        let all = try technicalObjects(for: localWorkerID)
        var roots = all.filter { $0.parent == nil && !$0.isUnassigned }
        let unassignedCount = all.filter(\.isUnassigned).count
        if unassignedCount > 0 {
            var root = TechnicalObjectNode.unassignedRoot
            root.directChildCount = unassignedCount
            roots.append(root)
        }
        return Self.page(roots, limit: limit, offset: offset)
    }

    func loadTechnicalObjectChildren(
        for localWorkerID: String,
        parent: TechnicalObjectReference,
        limit: Int,
        offset: Int
    ) async throws -> TechnicalObjectPage {
        let all = try technicalObjects(for: localWorkerID)
        let children = parent == .unassigned
            ? all.filter(\.isUnassigned)
            : all.filter { $0.parent == parent }
        return Self.page(children, limit: limit, offset: offset)
    }

    func searchTechnicalObjects(
        for localWorkerID: String,
        query: String,
        dinGroup: String?
    ) async throws -> [TechnicalObjectNode] {
        let all = try technicalObjects(for: localWorkerID)
        let search = query.trimmingCharacters(in: .whitespacesAndNewlines)
        let matches = all.filter { object in
            let dinMatches = dinGroup == nil || object.dinGroup == dinGroup
            let searchable = [
                object.reference.objectID, object.name, object.cityName,
                object.countryCode, object.locationCode, object.manufacturer,
                object.modelType, object.serialNumber, object.dinGroup ?? ""
            ].joined(separator: " ")
            return dinMatches && (search.isEmpty || searchable.localizedCaseInsensitiveContains(search))
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
        let counts = Dictionary(
            grouping: try technicalObjects(for: localWorkerID).compactMap(\.dinGroup),
            by: { $0 }
        )
        return TechnicalDIN276.supportedCodes.compactMap { code in
            counts[code].map { TechnicalObjectDINCount(code: code, count: $0.count) }
        }
    }

    func loadTechnicalObjectDetail(
        for localWorkerID: String,
        reference: TechnicalObjectReference
    ) async throws -> TechnicalObjectDetail? {
        let all = try technicalObjects(for: localWorkerID)
        guard let object = all.first(where: { $0.reference == reference }) else { return nil }
        let byReference = Dictionary(uniqueKeysWithValues: all.map { ($0.reference, $0) })
        var breadcrumbs: [TechnicalObjectNode] = []
        var parent = object.parent
        var visited = Set<TechnicalObjectReference>()
        while let reference = parent,
              visited.insert(reference).inserted,
              let parentObject = byReference[reference] {
            breadcrumbs.insert(parentObject, at: 0)
            parent = parentObject.parent
        }
        guard let database else { throw SAPReadError.serviceUnavailable }
        let notifications = try Self.notifications(on: database).filter {
            reference.kind == .equipment
                ? $0.equipmentID == reference.objectID
                : $0.functionalLocationID == reference.objectID
        }
        if reference.kind == .functionalLocation {
            return .functionalLocation(FunctionalLocationDetail(
                object: object,
                breadcrumbs: breadcrumbs,
                children: all.filter { $0.parent == reference },
                linkedNotifications: notifications
            ))
        }
        return .equipment(EquipmentDetail(
            object: object,
            breadcrumbs: breadcrumbs,
            linkedNotifications: notifications
        ))
    }

    func technicalObjectCount(
        for localWorkerID: String,
        kind: TechnicalObjectKind
    ) async throws -> Int {
        try technicalObjects(for: localWorkerID).filter { $0.reference.kind == kind }.count
    }

    func stageOutgoing(requestID: String) async throws -> LegacySAPOutgoingPayload {
        guard let database, !requestID.isEmpty else { throw SAPReadError.serviceUnavailable }
        try Self.execute(on: database, "BEGIN IMMEDIATE TRANSACTION")
        do {
            stagedOutgoingRowIDs = [:]
            for mapping in Self.outgoingMappings {
                let sourceSchema = try Self.schema(named: mapping.source)
                let temporarySchema = try Self.schema(named: mapping.temporary)
                let rowIDs = try Self.query(on: database, "SELECT rowid FROM \(sourceSchema.name)") {
                    SQLiteC.columnInt64($0, 0)
                }
                stagedOutgoingRowIDs[sourceSchema.name] = rowIDs
                try Self.execute(on: database, "DELETE FROM \(temporarySchema.name)")
                let columns = sourceSchema.columns.map(\.name).joined(separator: ", ")
                try Self.execute(
                    on: database,
                    "INSERT INTO \(temporarySchema.name) (\(columns)) SELECT \(columns) FROM \(sourceSchema.name)"
                )
                if temporarySchema.columns.contains(where: { $0.name == "REQID" }) {
                    try Self.execute(
                        on: database,
                        "UPDATE \(temporarySchema.name) SET REQID = ?",
                        bindings: [requestID]
                    )
                }
            }
            try Self.execute(on: database, "DELETE FROM TBL_REQUEST")
            try Self.execute(
                on: database,
                "INSERT INTO TBL_REQUEST (STEP, REQID) VALUES (?, ?)",
                bindings: ["1", requestID]
            )
            try Self.execute(on: database, "COMMIT")
            stagedOutgoingRequestID = requestID
        } catch {
            try? Self.execute(on: database, "ROLLBACK")
            stagedOutgoingRowIDs = [:]
            stagedOutgoingRequestID = nil
            throw error
        }

        let pairs = try Self.outgoingMappings.map { mapping in
            (mapping.payload, try Self.nonNullRows(in: mapping.temporary, on: database))
        }
        let values = Dictionary(uniqueKeysWithValues: pairs)
        return LegacySAPOutgoingPayload(
            T_0281: values["T_0281"] ?? [],
            T_0283: values["T_0283"] ?? [],
            T_0152R: values["T_0152R"] ?? [],
            T_0154R: values["T_0154R"] ?? [],
            T_0211R: values["T_0211R"] ?? [],
            T_0212R: values["T_0212R"] ?? [],
            T_0265: values["T_0265"] ?? [],
            T_0266: values["T_0266"] ?? [],
            T_0282: values["T_0282"] ?? [],
            T_0284: values["T_0284"] ?? [],
            T_0285: values["T_0285"] ?? [],
            T_0286: values["T_0286"] ?? [],
            T_0300: values["T_0300"] ?? [],
            T_0302: values["T_0302"] ?? []
        )
    }

    func confirmOutgoing(requestID: String) async throws {
        guard let database, stagedOutgoingRequestID == requestID else {
            throw SAPReadError.serviceUnavailable
        }
        try Self.execute(on: database, "BEGIN IMMEDIATE TRANSACTION")
        do {
            for mapping in Self.outgoingMappings {
                let rowIDs = stagedOutgoingRowIDs[mapping.source] ?? []
                for start in stride(from: 0, to: rowIDs.count, by: 500) {
                    let batch = Array(rowIDs[start..<min(start + 500, rowIDs.count)])
                    let placeholders = Array(repeating: "?", count: batch.count).joined(separator: ",")
                    try Self.execute(
                        on: database,
                        "DELETE FROM \(mapping.source) WHERE rowid IN (\(placeholders))",
                        bindings: batch.map(String.init)
                    )
                }
                try Self.execute(on: database, "DELETE FROM \(mapping.temporary)")
            }
            try Self.execute(
                on: database,
                "DELETE FROM TBL_REQUEST WHERE REQID = ?",
                bindings: [requestID]
            )
            try Self.execute(on: database, "COMMIT")
            stagedOutgoingRowIDs = [:]
            stagedOutgoingRequestID = nil
        } catch {
            try? Self.execute(on: database, "ROLLBACK")
            throw error
        }
    }

    func abortOutgoing(requestID: String) async {
        guard let database else { return }
        for mapping in Self.outgoingMappings {
            try? Self.execute(on: database, "DELETE FROM \(mapping.temporary)")
        }
        try? Self.execute(
            on: database,
            "DELETE FROM TBL_REQUEST WHERE REQID = ?",
            bindings: [requestID]
        )
        stagedOutgoingRowIDs = [:]
        stagedOutgoingRequestID = nil
    }

    func beginIncoming() async throws {
        guard !incomingSynchronizationIsActive else { throw SAPReadError.serviceUnavailable }
        guard let database else { throw SAPReadError.serviceUnavailable }
        let databasePath = databaseURL.standardizedFileURL.path
        guard await legacyIncomingSynchronizationRegistry.acquire(databasePath: databasePath) else {
            throw SAPReadError.serviceUnavailable
        }
        try Self.execute(on: database, "BEGIN IMMEDIATE TRANSACTION")
        do {
            for table in LegacySQLiteSchema.temporaryInbound {
                try Self.execute(on: database, "DELETE FROM \(table.name)")
            }
            try Self.execute(on: database, "COMMIT")
            incomingUserRows = []
            incomingSawUserTable = false
            incomingSawLastPackage = false
            incomingSynchronizationIsActive = true
        } catch {
            try? Self.execute(on: database, "ROLLBACK")
            await legacyIncomingSynchronizationRegistry.release(databasePath: databasePath)
            throw error
        }
    }

    func appendIncoming(_ package: LegacySAPIncomingPackage) async throws {
        guard incomingSynchronizationIsActive, let database else { throw SAPReadError.malformedPayload }
        var appendedUserRows = incomingUserRows
        var sawUserTable = incomingSawUserTable
        try Self.execute(on: database, "BEGIN IMMEDIATE TRANSACTION")
        do {
            for (rawName, rows) in package.tables {
                let name = rawName.uppercased()
                if Self.isExcludedT025(name) { continue }
                if ["T_0153", "T0153"].contains(name) {
                    let schema = try Self.schema(named: "USER")
                    for row in rows {
                        try Self.validate(row: row, for: schema)
                        appendedUserRows.append(row)
                    }
                    sawUserTable = true
                    continue
                }
                guard let digits = Self.inboundDigits(from: name),
                      let schema = LegacySQLiteSchema.byName["TMP_FROM_T\(digits)"] else {
                    continue
                }
                for row in rows {
                    try Self.insert(row: row, into: schema, on: database)
                }
            }
            try Self.execute(on: database, "COMMIT")
            incomingUserRows = appendedUserRows
            incomingSawUserTable = sawUserTable
            incomingSawLastPackage = incomingSawLastPackage || package.isLastPackage
        } catch {
            try? Self.execute(on: database, "ROLLBACK")
            throw error
        }
    }

    func commitIncoming(sapWorkerID: String, refreshedAt: Date) async throws -> SAPCachedData {
        guard let database, incomingSynchronizationIsActive, incomingSawLastPackage else {
            throw SAPReadError.malformedPayload
        }
        try Self.execute(on: database, "BEGIN IMMEDIATE TRANSACTION")
        do {
            for permanent in LegacySQLiteSchema.permanentInbound {
                let temporaryName = "TMP_\(permanent.name)"
                let columns = permanent.columns.map(\.name).joined(separator: ", ")
                try Self.execute(on: database, "DELETE FROM \(permanent.name)")
                try Self.execute(
                    on: database,
                    "INSERT INTO \(permanent.name) (\(columns)) SELECT \(columns) FROM \(temporaryName)"
                )
                try Self.execute(on: database, "DELETE FROM \(temporaryName)")
            }
            if incomingSawUserTable {
                try Self.execute(on: database, "DELETE FROM USER")
                let userSchema = try Self.schema(named: "USER")
                for row in incomingUserRows {
                    try Self.insert(row: row, into: userSchema, on: database)
                }
            }
            let timestamp = ISO8601DateFormatter().string(from: refreshedAt)
            try Self.setParameter(Self.refreshParameter, value: timestamp, on: database)
            try Self.setParameter(Self.workerParameter, value: sapWorkerID, on: database)
            try Self.execute(on: database, "COMMIT")
            incomingUserRows = []
            incomingSawUserTable = false
            incomingSawLastPackage = false
            incomingSynchronizationIsActive = false
            await legacyIncomingSynchronizationRegistry.release(
                databasePath: databaseURL.standardizedFileURL.path
            )
        } catch {
            try? Self.execute(on: database, "ROLLBACK")
            incomingSynchronizationIsActive = false
            await legacyIncomingSynchronizationRegistry.release(
                databasePath: databaseURL.standardizedFileURL.path
            )
            throw error
        }
        if let metadata = try? Self.metadata(on: database) {
            await rebuildNotificationListIndexIfNeeded(
                for: localWorkerID ?? sapWorkerID,
                metadata: metadata,
                on: database
            )
        }
        return try await load(for: localWorkerID ?? sapWorkerID)
    }

    func incomingCacheSummary() async throws -> SAPIncomingCacheSummary {
        guard let database else { throw SAPReadError.serviceUnavailable }
        let notificationRowCount = Int(try Self.query(on: database, "SELECT COUNT(*) FROM FROM_T0271") {
            SQLiteC.columnInt($0, 0)
        }.first ?? 0)
        if let metadata = try? Self.metadata(on: database),
           let notificationListIndex,
           (try? await notificationListIndex.isCurrent(
                for: localWorkerID ?? metadata.sapWorkerID,
                sourceVersion: Self.notificationIndexSourceVersion(metadata)
           )) == true,
           let summary = try? await notificationListIndex.summary(
                for: localWorkerID ?? metadata.sapWorkerID
           ) {
            return SAPIncomingCacheSummary(
                notificationRowCount: notificationRowCount,
                actionableNotificationCount: summary.actionableCount,
                businessEntityCount: summary.businessEntityCount,
                elevatorInspectionCount: summary.elevatorInspectionCount
            )
        }
        let notificationRows = try Self.rows(in: "FROM_T0271", on: database)
        let notifications = notificationRows.compactMap(SAPLegacyDataExchangeCodec.notification(from:))
        let businessEntityCount = Set(
            notifications
                .compactMap(\.structuralFilterMetadata)
                .map(\.businessEntityID)
        ).count
        return SAPIncomingCacheSummary(
            notificationRowCount: notificationRows.count,
            actionableNotificationCount: notifications.count,
            businessEntityCount: businessEntityCount,
            elevatorInspectionCount: notifications.filter(\.isTFM2ElevatorInspection).count
        )
    }

    func abortIncoming() async {
        guard let database else { return }
        let wasActive = incomingSynchronizationIsActive
        for table in LegacySQLiteSchema.temporaryInbound {
            try? Self.execute(on: database, "DELETE FROM \(table.name)")
        }
        incomingUserRows = []
        incomingSawUserTable = false
        incomingSawLastPackage = false
        incomingSynchronizationIsActive = false
        if wasActive {
            await legacyIncomingSynchronizationRegistry.release(
                databasePath: databaseURL.standardizedFileURL.path
            )
        }
    }

    func insertLegacyRows(_ rows: [LegacySAPRow], into tableName: String) async throws {
        guard let database else { throw SAPReadError.serviceUnavailable }
        let schema = try Self.schema(named: tableName.uppercased())
        for row in rows {
            try Self.insert(row: row, into: schema, on: database)
        }
    }

    func replaceNotificationOutgoingRows(
        processIDs: [String],
        equipmentIDs: [String],
        headers: [LegacySAPRow],
        values: [LegacySAPRow],
        documents: [LegacySAPRow],
        equipment: [LegacySAPRow]
    ) async throws {
        guard let database else { throw SAPReadError.serviceUnavailable }
        let headerSchema = try Self.schema(named: "TO_T0281")
        let valueSchema = try Self.schema(named: "TO_T0283")
        let documentSchema = try Self.schema(named: "TO_T0282")
        let equipmentSchema = try Self.schema(named: "TO_T0266")
        try Self.execute(on: database, "BEGIN IMMEDIATE TRANSACTION")
        do {
            for processID in Set(processIDs) where !processID.isEmpty {
                for table in [headerSchema.name, valueSchema.name, documentSchema.name] {
                    try Self.execute(
                        on: database,
                        "DELETE FROM \(table) WHERE VORGANGSNR = ?",
                        bindings: [processID]
                    )
                }
            }
            for equipmentID in Set(equipmentIDs) where !equipmentID.isEmpty {
                try Self.execute(
                    on: database,
                    "DELETE FROM \(equipmentSchema.name) WHERE EQUNR = ?",
                    bindings: [equipmentID]
                )
            }
            for row in headers { try Self.insert(row: row, into: headerSchema, on: database) }
            for row in values { try Self.insert(row: row, into: valueSchema, on: database) }
            for row in documents { try Self.insert(row: row, into: documentSchema, on: database) }
            for row in equipment { try Self.insert(row: row, into: equipmentSchema, on: database) }
            try Self.execute(on: database, "COMMIT")
        } catch {
            try? Self.execute(on: database, "ROLLBACK")
            throw error
        }
    }

    func legacyRowCount(in tableName: String) async throws -> Int {
        guard let database else { throw SAPReadError.serviceUnavailable }
        let schema = try Self.schema(named: tableName.uppercased())
        return Int(try Self.query(on: database, "SELECT COUNT(*) FROM \(schema.name)") {
            SQLiteC.columnInt($0, 0)
        }.first ?? 0)
    }

    private func validateWorker(_ workerID: String) throws {
        guard let localWorkerID else { return }
        let expected = localWorkerID.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
        let actual = workerID.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
        guard expected == actual else { throw SAPReadError.serviceUnavailable }
    }

    private func technicalObjects(for workerID: String) throws -> [TechnicalObjectNode] {
        try validateWorker(workerID)
        guard let database else { throw SAPReadError.serviceUnavailable }
        return try Self.technicalObjects(on: database)
    }

    private func rebuildNotificationListIndexIfNeeded(
        for workerID: String,
        metadata: SAPCacheMetadata,
        on database: OpaquePointer
    ) async {
        guard let notificationListIndex else { return }
        let sourceVersion = Self.notificationIndexSourceVersion(metadata)
        guard (try? await notificationListIndex.isCurrent(
            for: workerID,
            sourceVersion: sourceVersion
        )) != true else {
            return
        }
        guard let notifications = try? Self.notifications(on: database) else { return }
        try? await notificationListIndex.replace(
            notifications,
            for: workerID,
            sourceVersion: sourceVersion
        )
    }

    private func indexedNotificationPage(
        for workerID: String,
        matching searchText: String,
        structuralFilter: NotificationStructuralFilter,
        limit: Int,
        offset: Int,
        on database: OpaquePointer
    ) async -> SAPNotificationPage? {
        guard let metadata = try? Self.metadata(on: database),
              let notificationListIndex,
              (try? await notificationListIndex.isCurrent(
                for: workerID,
                sourceVersion: Self.notificationIndexSourceVersion(metadata)
              )) == true
        else {
            return nil
        }
        return try? await notificationListIndex.loadNotifications(
            for: workerID,
            matching: searchText,
            structuralFilter: structuralFilter,
            limit: limit,
            offset: offset
        )
    }

    private func indexedNotificationFilterMetadata(
        for workerID: String,
        on database: OpaquePointer
    ) async -> [NotificationStructuralFilterMetadata]? {
        guard let metadata = try? Self.metadata(on: database),
              let notificationListIndex,
              (try? await notificationListIndex.isCurrent(
                for: workerID,
                sourceVersion: Self.notificationIndexSourceVersion(metadata)
              )) == true
        else {
            return nil
        }
        return try? await notificationListIndex.loadFilterMetadata(for: workerID)
    }

    private static func initialize(on database: OpaquePointer) throws {
        try execute(on: database, "BEGIN IMMEDIATE TRANSACTION")
        do {
            for table in LegacySQLiteSchema.tables {
                try execute(on: database, table.createSQL)
            }
            try execute(
                on: database,
                "INSERT INTO APPVERSION (IDCHECK, DBVERSION) SELECT 1, ? WHERE NOT EXISTS (SELECT 1 FROM APPVERSION WHERE IDCHECK = 1)",
                bindings: [LegacySQLiteSchema.appDatabaseVersion]
            )
            try execute(
                on: database,
                "INSERT INTO PARVALUE (CATEGORY, PARAMETER, VALUE) SELECT ?, ?, ? WHERE NOT EXISTS (SELECT 1 FROM PARVALUE WHERE CATEGORY = ? AND PARAMETER = ?)",
                bindings: ["ACTIVESYSTEM", "PSYSTEM", "X", "ACTIVESYSTEM", "PSYSTEM"]
            )
            try validateSchema(on: database)
            try execute(on: database, "COMMIT")
        } catch {
            try? execute(on: database, "ROLLBACK")
            throw error
        }
    }

    private static func validateSchema(on database: OpaquePointer) throws {
        let names = try query(
            on: database,
            "SELECT name FROM sqlite_master WHERE type = 'table' AND name NOT LIKE 'sqlite_%' ORDER BY name"
        ) { string(at: 0, from: $0) }
        guard names == LegacySQLiteSchema.tables.map(\.name).sorted() else {
            throw SAPReadError.serviceUnavailable
        }
        for table in LegacySQLiteSchema.tables {
            let columns = try query(on: database, "PRAGMA table_info(\(table.name))") {
                LegacySQLiteColumn(
                    name: string(at: 1, from: $0),
                    declaredType: string(at: 2, from: $0)
                )
            }
            guard columns == table.columns else { throw SAPReadError.serviceUnavailable }
        }
        let indexes = try query(
            on: database,
            "SELECT name FROM sqlite_master WHERE type = 'index' AND name NOT LIKE 'sqlite_%'"
        ) { string(at: 0, from: $0) }
        guard indexes.isEmpty else { throw SAPReadError.serviceUnavailable }
    }

    private static func notifications(on database: OpaquePointer) throws -> [SAPNotificationSummary] {
        try rows(in: "FROM_T0271", on: database)
            .compactMap(SAPLegacyDataExchangeCodec.notification(from:))
    }

    private static func technicalObjects(on database: OpaquePointer) throws -> [TechnicalObjectNode] {
        let functionalRows = try rows(in: "FROM_T0261", on: database)
        let equipmentRows = try rows(in: "FROM_T0262", on: database)
        let notificationRows = try rows(in: "FROM_T0271", on: database)
        let aliases = SAPTechnicalObjectMapper.functionalLocationAliases(from: functionalRows)
        let cityNames = SAPTechnicalObjectMapper.cityNames(
            from: notificationRows + functionalRows + equipmentRows
        )
        let mapped = functionalRows.compactMap(SAPTechnicalObjectMapper.functionalLocation(from:))
            + equipmentRows.compactMap(SAPTechnicalObjectMapper.equipment(from:))
        var unique: [TechnicalObjectReference: TechnicalObjectNode] = [:]
        for object in mapped { unique[object.reference] = object }
        return TechnicalObjectHierarchyNormalizer.normalize(
            SAPTechnicalObjectMapper.resolveRelationships(
                in: Array(unique.values),
                functionalLocationAliases: aliases,
                cityNames: cityNames
            )
        )
    }

    private static func metadata(on database: OpaquePointer) throws -> SAPCacheMetadata? {
        let pairs = try query(
            on: database,
            "SELECT PARAMETER, VALUE FROM PARVALUE WHERE CATEGORY = ?",
            bindings: [metadataCategory]
        ) { (string(at: 0, from: $0), string(at: 1, from: $0)) }
        let values = pairs.reduce(into: [String: String]()) { result, pair in
            result[pair.0] = pair.1
        }
        guard let worker = values[workerParameter],
              let timestamp = values[refreshParameter],
              let date = ISO8601DateFormatter().date(from: timestamp) else {
            return nil
        }
        return SAPCacheMetadata(sapWorkerID: worker, lastSuccessfulRefreshAt: date)
    }

    private static func notificationIndexSourceVersion(_ metadata: SAPCacheMetadata) -> String {
        ISO8601DateFormatter().string(from: metadata.lastSuccessfulRefreshAt)
    }

    private static func setParameter(
        _ parameter: String,
        value: String,
        on database: OpaquePointer
    ) throws {
        try execute(
            on: database,
            "DELETE FROM PARVALUE WHERE CATEGORY = ? AND PARAMETER = ?",
            bindings: [metadataCategory, parameter]
        )
        try execute(
            on: database,
            "INSERT INTO PARVALUE (CATEGORY, PARAMETER, VALUE) VALUES (?, ?, ?)",
            bindings: [metadataCategory, parameter, value]
        )
    }

    private static func inboundDigits(from name: String) -> String? {
        let compact = name.replacingOccurrences(of: "_", with: "")
        guard compact.hasPrefix("T"), compact.dropFirst().allSatisfy(\.isNumber) else { return nil }
        return String(compact.dropFirst())
    }

    private static func isExcludedT025(_ name: String) -> Bool {
        guard let digits = inboundDigits(from: name) else { return false }
        return digits.hasPrefix("025")
    }

    private static func schema(named name: String) throws -> LegacySQLiteTable {
        guard let schema = LegacySQLiteSchema.byName[name] else {
            throw SAPReadError.malformedPayload
        }
        return schema
    }

    private static func validate(row: LegacySAPRow, for schema: LegacySQLiteTable) throws {
        let allowed = Set(schema.columns.map(\.name))
        guard row.keys.allSatisfy({ allowed.contains($0.uppercased()) }) else {
            throw SAPReadError.malformedPayload
        }
    }

    private static func insert(
        row: LegacySAPRow,
        into schema: LegacySQLiteTable,
        on database: OpaquePointer
    ) throws {
        var normalized: LegacySAPRow = [:]
        for (key, value) in row { normalized[key.uppercased()] = value }
        try validate(row: normalized, for: schema)
        let columns = schema.columns.map(\.name)
        let placeholders = Array(repeating: "?", count: columns.count).joined(separator: ", ")
        let bindings: [String?] = columns.map { normalized[$0] ?? nil }
        try execute(
            on: database,
            "INSERT INTO \(schema.name) (\(columns.joined(separator: ", "))) VALUES (\(placeholders))",
            bindings: bindings
        )
    }

    private static func rows(in tableName: String, on database: OpaquePointer) throws -> [[String: Any]] {
        let schema = try schema(named: tableName)
        return try query(
            on: database,
            "SELECT \(schema.columns.map(\.name).joined(separator: ", ")) FROM \(schema.name)"
        ) { statement in
            var row: [String: Any] = [:]
            for (index, column) in schema.columns.enumerated()
                where SQLiteC.columnType(statement, Int32(index)) != SQLiteC.null {
                row[column.name] = string(at: Int32(index), from: statement)
            }
            return row
        }
    }

    private static func nonNullRows(
        in tableName: String,
        on database: OpaquePointer
    ) throws -> [[String: String]] {
        try rows(in: tableName, on: database).map { row in
            row.reduce(into: [String: String]()) { result, pair in
                if let value = pair.value as? String { result[pair.key] = value }
            }
        }
    }

    private static func page(
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
        let start = min(max(offset, 0), sorted.count)
        let end = min(start + max(limit, 1), sorted.count)
        return TechnicalObjectPage(
            objects: Array(sorted[start..<end]),
            nextOffset: end < sorted.count ? end : nil,
            totalCount: sorted.count
        )
    }

    private static func execute(
        on database: OpaquePointer,
        _ sql: String,
        bindings: [String?] = []
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
        bindings: [String?] = [],
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

    private static func bind(_ values: [String?], to statement: OpaquePointer?) throws {
        for (index, value) in values.enumerated() {
            let result: Int32
            if let value {
                result = value.withCString {
                    SQLiteC.bindText(statement, Int32(index + 1), $0, -1, SQLiteC.transient)
                }
            } else {
                result = SQLiteC.bindNull(statement, Int32(index + 1))
            }
            guard result == SQLiteC.ok else { throw SAPReadError.serviceUnavailable }
        }
    }

    private static func string(at index: Int32, from statement: OpaquePointer) -> String {
        guard let text = SQLiteC.columnText(statement, index) else { return "" }
        return String(cString: text)
    }
}
