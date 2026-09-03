import Foundation
import XCTest
@testable import mobileFacilityApp

final class TechnicalObjectsTests: XCTestCase {
    func testSAPDecodingPreservesExplicitParentsAndFields() throws {
        let location = try XCTUnwrap(SAPTechnicalObjectMapper.functionalLocation(from: [
            "STRNO": "SITE-BLDG-420", "TPLMA": "SITE", "PLTXT": "Heating plant",
            "LEVELID": "3", "FLTYP": "A", "TPLKZ": "TPL", "STTXT": "AVLB"
        ]))
        XCTAssertEqual(location.parent, .init(kind: .functionalLocation, objectID: "SITE"))
        XCTAssertEqual(location.dinGroup, "420")
        XCTAssertEqual(location.systemStatus, "AVLB")

        let equipment = try XCTUnwrap(SAPTechnicalObjectMapper.equipment(from: [
            "EQUNR": "EQ-2", "STRNO": "SITE-BLDG-420", "HEQUI": "EQ-1", "EQKTX": "Pump",
            "HERST": "Maker", "TYPBZ": "P-20", "SERGE": "S-9", "EQTYP": "M"
        ]))
        XCTAssertEqual(equipment.parent, .init(kind: .equipment, objectID: "EQ-1"))
        XCTAssertEqual(equipment.functionalLocationID, "SITE-BLDG-420")
        XCTAssertEqual(equipment.manufacturer, "Maker")
    }

    func testSAPInternalFunctionalLocationKeysResolveToDisplayedHierarchy() throws {
        let rows: [[String: Any]] = [
            ["STRNO": "DE-ESS-10748", "TPLNR": "00000000000000000001", "TPLMA": "", "PLTXT": "Site"],
            ["STRNO": "DE-ESS-10748-01", "TPLNR": "00000000000000000002", "TPLMA": "00000000000000000001", "PLTXT": "Building"],
            ["STRNO": "DE-ESS-10748-01-330", "TPLNR": "00000000000000000003", "TPLMA": "00000000000000000002", "PLTXT": "Exterior walls"]
        ]
        let aliases = SAPTechnicalObjectMapper.functionalLocationAliases(from: rows)
        let mapped = rows.compactMap(SAPTechnicalObjectMapper.functionalLocation(from:))
        let resolved = SAPTechnicalObjectMapper.resolveRelationships(
            in: mapped,
            functionalLocationAliases: aliases
        )
        XCTAssertEqual(
            resolved.first { $0.reference.objectID == "DE-ESS-10748-01" }?.parent?.objectID,
            "DE-ESS-10748"
        )
        XCTAssertEqual(
            resolved.first { $0.reference.objectID == "DE-ESS-10748-01-330" }?.parent?.objectID,
            "DE-ESS-10748-01"
        )
        XCTAssertFalse(TechnicalObjectHierarchyNormalizer.normalize(resolved).contains(where: \.isUnassigned))
    }

    func testSAPCityMetadataUsesConfirmedAddressFieldsAndLocationCodes() throws {
        let location = try XCTUnwrap(SAPTechnicalObjectMapper.functionalLocation(from: [
            "STRNO": "DE-ARN-15138-04",
            "TPLND": "DE",
            "TPORT": "ARN",
            "CITY1_TO": "Arnsberg",
            "PLTXT": "Building 04"
        ]))
        XCTAssertEqual(location.countryCode, "DE")
        XCTAssertEqual(location.locationCode, "ARN")
        XCTAssertEqual(location.cityName, "Arnsberg")

        let names = SAPTechnicalObjectMapper.cityNames(from: [[
            "STRNO": "DE-ESS-10748-01",
            "CITY1_TO": "Essen"
        ]])
        let key = try XCTUnwrap(TechnicalLocationKey(countryCode: "DE", locationCode: "ESS"))
        XCTAssertEqual(names[key], "Essen")
    }

    func testCityNameFromNotificationMetadataEnrichesLocationsAndEquipment() throws {
        let location = try XCTUnwrap(SAPTechnicalObjectMapper.functionalLocation(from: [
            "STRNO": "DE-ARN-15138",
            "PLTXT": "Business entity"
        ]))
        let equipment = try XCTUnwrap(SAPTechnicalObjectMapper.equipment(from: [
            "EQUNR": "EQ-1",
            "STRNO": "DE-ARN-15138",
            "EQKTX": "Pump"
        ]))
        let key = try XCTUnwrap(TechnicalLocationKey(countryCode: "DE", locationCode: "ARN"))
        let resolved = SAPTechnicalObjectMapper.resolveRelationships(
            in: [location, equipment],
            functionalLocationAliases: [:],
            cityNames: [key: "Arnsberg"]
        )
        XCTAssertEqual(resolved.first { $0.reference == location.reference }?.cityName, "Arnsberg")
        XCTAssertEqual(resolved.first { $0.reference == equipment.reference }?.cityName, "Arnsberg")
    }

    func testStrictDINDetectionRejectsDescriptionsAndAmbiguity() {
        XCTAssertEqual(TechnicalDIN276.detect(label: "SITE-420-A"), "420")
        XCTAssertEqual(TechnicalDIN276.detect(label: "SITE-330-A"), "330")
        XCTAssertNil(TechnicalDIN276.detect(label: "Heating and water plant"))
        XCTAssertNil(TechnicalDIN276.detect(label: "SITE-420-440"))
        XCTAssertNil(TechnicalDIN276.detect(label: "SITE-1420-A"))
        XCTAssertEqual(TechnicalDIN276.detect(explicitValue: "KG 440", label: "SITE"), "440")
    }

    func testNormalizerKeepsNestedEquipmentAndMovesMissingParentsAndCycles() {
        let root = node("ROOT", kind: .functionalLocation)
        let equipment = node("EQ-1", kind: .equipment, parent: root.reference)
        let nested = node("EQ-2", kind: .equipment, parent: equipment.reference)
        let orphan = node("ORPHAN", kind: .equipment, parent: .init(kind: .equipment, objectID: "MISSING"))
        let cycleA = node("A", kind: .equipment, parent: .init(kind: .equipment, objectID: "B"))
        let cycleB = node("B", kind: .equipment, parent: .init(kind: .equipment, objectID: "A"))
        let normalized = TechnicalObjectHierarchyNormalizer.normalize([root, equipment, nested, orphan, cycleA, cycleB])
        XCTAssertEqual(normalized.first { $0.reference == equipment.reference }?.parent, root.reference)
        XCTAssertEqual(normalized.first { $0.reference == nested.reference }?.parent, equipment.reference)
        XCTAssertTrue(normalized.first { $0.reference == orphan.reference }?.isUnassigned == true)
        XCTAssertTrue(normalized.first { $0.reference == cycleA.reference }?.isUnassigned == true)
        XCTAssertEqual(normalized.first { $0.reference == equipment.reference }?.directChildCount, 1)
    }

    func testNormalizerDeduplicatesByTechnicalObjectIdentity() {
        let first = node("EQ-1", kind: .equipment, name: "First")
        let duplicate = node("EQ-1", kind: .equipment, name: "Duplicate")
        let normalized = TechnicalObjectHierarchyNormalizer.normalize([first, duplicate])
        XCTAssertEqual(normalized.count, 1)
        XCTAssertEqual(normalized.first?.name, "First")
    }

    func testInMemoryPagingSearchAncestorsAndDINCounts() async throws {
        let root = node("ROOT", kind: .functionalLocation)
        let branch = node("BRANCH-420", kind: .functionalLocation, parent: root.reference, din: "420")
        let equipment = node("EQ-1", kind: .equipment, parent: branch.reference, din: "420", name: "Special Pump")
        let seed = cached(objects: TechnicalObjectHierarchyNormalizer.normalize([root, branch, equipment]))
        let repository = InMemorySAPDataCacheRepository(seed: seed, workerID: "w1")
        let roots = try await repository.loadTechnicalObjectRoots(for: "w1", limit: 1, offset: 0)
        XCTAssertEqual(roots.objects.map(\.reference), [root.reference])
        let results = try await repository.searchTechnicalObjects(for: "w1", query: "Special", dinGroup: nil)
        XCTAssertEqual(Set(results.map(\.reference)), Set([root.reference, branch.reference, equipment.reference]))
        let counts = try await repository.loadTechnicalObjectDINCounts(for: "w1")
        let otherWorkerCount = try await repository.technicalObjectCount(for: "other", kind: .equipment)
        XCTAssertEqual(counts, [.init(code: "420", count: 2)])
        XCTAssertEqual(otherWorkerCount, 0)
    }

    func testSQLiteAtomicReplacementWorkerIsolationAndExactNotificationLinks() async throws {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString).appendingPathExtension("sqlite")
        defer { try? FileManager.default.removeItem(at: url) }
        let repository = try SQLiteSAPDataCacheRepository(databaseURL: url)
        let location = node(
            "DE-ESS-FL-420",
            kind: .functionalLocation,
            din: "420",
            city: "Essen",
            country: "DE",
            location: "ESS"
        )
        let equipment = node("EQ-1", kind: .equipment, parent: location.reference, din: "420")
        let note = SAPNotificationSummary(id: "N-1", client: "100", title: "Exact", functionalLocationID: "DE-ESS-FL-420", functionalLocationName: "Plant", equipmentID: "EQ-1", startDate: "", endDate: "", systemStatus: "", userStatus: "", rawPayloadJSON: "{}")
        _ = try await repository.replace(with: .init(sapWorkerID: "1", notifications: [note], workerProfile: nil, technicalObjects: [location, equipment]), for: "w1", refreshedAt: Date())
        let workerCount = try await repository.technicalObjectCount(for: "w1", kind: .equipment)
        let otherWorkerCount = try await repository.technicalObjectCount(for: "w2", kind: .equipment)
        XCTAssertEqual(workerCount, 1)
        XCTAssertEqual(otherWorkerCount, 0)
        let storedRoots = try await repository.loadTechnicalObjectRoots(for: "w1", limit: 10, offset: 0)
        XCTAssertEqual(storedRoots.objects.first?.cityName, "Essen")
        XCTAssertEqual(storedRoots.objects.first?.locationCode, "ESS")
        guard case let .equipment(detail)? = try await repository.loadTechnicalObjectDetail(for: "w1", reference: equipment.reference) else {
            return XCTFail("Missing equipment detail")
        }
        XCTAssertEqual(detail.linkedNotifications.map(\.id), ["N-1"])
        _ = try await repository.replace(with: .init(sapWorkerID: "1", notifications: [], workerProfile: nil, technicalObjects: [location]), for: "w1", refreshedAt: Date())
        let replacedCount = try await repository.technicalObjectCount(for: "w1", kind: .equipment)
        XCTAssertEqual(replacedCount, 0)
    }

    @MainActor
    func testTechnicalPlacesViewModelAddsExpandedCityPresentationNode() async throws {
        let root = node(
            "DE-ESS-10748",
            kind: .functionalLocation,
            city: "Essen",
            country: "DE",
            location: "ESS"
        )
        let seed = cached(objects: TechnicalObjectHierarchyNormalizer.normalize([root]))
        let sapRepository = InMemorySAPDataCacheRepository(seed: seed, workerID: "w1")
        let model = TechnicalPlacesViewModel(
            sapDataStore: SAPDataStore(
                repository: sapRepository,
                refreshService: nil,
                localWorkerID: "w1"
            ),
            offlineWorkStore: OfflineWorkStore(
                repository: InMemoryOfflineWorkRepository(),
                workerID: "w1"
            )
        )

        await model.load()

        XCTAssertEqual(model.visibleRows.count, 2)
        XCTAssertTrue(model.visibleRows[0].node.isCityGroup)
        XCTAssertEqual(model.visibleRows[0].node.displayName, "Essen")
        XCTAssertEqual(model.visibleRows[0].node.locationCode, "ESS")
        XCTAssertEqual(model.visibleRows[1].node.reference, root.reference)
        XCTAssertEqual(model.visibleRows[1].depth, 1)
    }

    func testSQLiteVersionFourMigrationBackfillsEquipmentID() async throws {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString).appendingPathExtension("sqlite")
        defer { try? FileManager.default.removeItem(at: url) }
        try createVersionFourCache(at: url)
        let repository = try SQLiteSAPDataCacheRepository(databaseURL: url)
        let page = try await repository.loadNotifications(for: "w1", matching: "", structuralFilter: .empty, limit: 10, offset: 0)
        XCTAssertEqual(page.notifications.first?.equipmentID, "EQ-BACKFILL")
    }

    @MainActor
    func testPendingEditReopensAndDuplicateSaveUpdatesSameItem() async throws {
        let repository = InMemoryOfflineWorkRepository()
        let store = OfflineWorkStore(repository: repository, workerID: "w1")
        await store.load()
        let payload = TechnicalObjectEditPayload(equipmentID: "EQ-1", functionalLocationID: "FL-1", designation: "Pump", manufacturer: "M", modelType: "T", serialNumber: "S", dinGroup: "420", nextInspectionDate: nil, sourceFingerprint: "source-a")
        let first = try await store.saveTechnicalObjectEdit(payload)
        let second = try await store.saveTechnicalObjectEdit(payload)
        XCTAssertEqual(first.id, second.id)
        XCTAssertEqual(store.technicalObjectEditItems.count, 1)
        XCTAssertEqual(store.technicalObjectEdit(equipmentID: "EQ-1")?.status, .pendingSynchronization)
        await store.reset()
        XCTAssertTrue(store.technicalObjectEditItems.isEmpty)
    }

    func testTenThousandNodeSearchIsBoundedToMatchesAndAncestors() async throws {
        let root = node("ROOT", kind: .functionalLocation)
        let objects = [root] + (0..<10_000).map { index in
            node("EQ-\(index)", kind: .equipment, parent: root.reference, name: index == 9_999 ? "Unique target" : "Equipment \(index)")
        }
        let repository = InMemorySAPDataCacheRepository(seed: cached(objects: TechnicalObjectHierarchyNormalizer.normalize(objects)), workerID: "w")
        let results = try await repository.searchTechnicalObjects(for: "w", query: "Unique target", dinGroup: nil)
        XCTAssertEqual(results.count, 2)
        XCTAssertEqual(Set(results.map(\.reference)), Set([root.reference, .init(kind: .equipment, objectID: "EQ-9999")]))
    }

    private func cached(objects: [TechnicalObjectNode]) -> SAPCachedData {
        SAPCachedData(notifications: [], workerProfile: nil, technicalObjects: objects, metadata: .init(sapWorkerID: "1", lastSuccessfulRefreshAt: Date()))
    }

    private func node(
        _ id: String,
        kind: TechnicalObjectKind,
        parent: TechnicalObjectReference? = nil,
        din: String? = nil,
        name: String? = nil,
        city: String = "",
        country: String = "",
        location: String = ""
    ) -> TechnicalObjectNode {
        TechnicalObjectNode(reference: .init(kind: kind, objectID: id), parent: parent, client: "100", name: name ?? id,
                            functionalLocationID: kind == .functionalLocation ? id : (parent?.objectID ?? ""),
                            countryCode: country, locationCode: location, cityName: city,
                            hierarchyLevel: "", category: "", structureIndicator: "",
                            equipmentCategory: "", equipmentType: "", manufacturer: "", modelType: "", serialNumber: "", systemStatus: "", userStatus: "", dinGroup: din,
                            sourceFingerprint: TechnicalObjectFingerprint.make([id]), directChildCount: 0, directEquipmentCount: 0, isUnassigned: false, isSynthetic: false)
    }

    private func createVersionFourCache(at url: URL) throws {
        var database: OpaquePointer?
        let opened = url.path.withCString {
            SQLiteC.open($0, &database, SQLiteC.openCreate | SQLiteC.openReadWrite | SQLiteC.openFullMutex, nil)
        }
        guard opened == SQLiteC.ok, let database else { throw OfflineWorkRepositoryError.unavailable }
        defer { _ = SQLiteC.close(database) }
        let commands = [
            """
            CREATE TABLE sap_notifications (
                local_worker_id TEXT NOT NULL, notification_id TEXT NOT NULL, client TEXT NOT NULL,
                title TEXT NOT NULL, functional_location_id TEXT NOT NULL, functional_location_name TEXT NOT NULL,
                start_date TEXT NOT NULL, end_date TEXT NOT NULL, system_status TEXT NOT NULL, user_status TEXT NOT NULL,
                raw_payload_json TEXT NOT NULL, country_code TEXT NOT NULL, location_code TEXT NOT NULL,
                business_entity_code TEXT NOT NULL, business_entity_id TEXT NOT NULL, building_code TEXT NOT NULL,
                trade_code TEXT NOT NULL, form_code TEXT NOT NULL, PRIMARY KEY(local_worker_id, notification_id)
            )
            """,
            "INSERT INTO sap_notifications VALUES ('w1','N-1','','','','','','','','','{\"EQUNR\":\"EQ-BACKFILL\"}','','','','','','','')",
            "PRAGMA user_version = 4"
        ]
        for command in commands {
            var statement: OpaquePointer?
            let prepared = command.withCString { SQLiteC.prepare(database, $0, -1, &statement, nil) }
            guard prepared == SQLiteC.ok else { throw OfflineWorkRepositoryError.unavailable }
            defer { _ = SQLiteC.finalize(statement) }
            guard SQLiteC.step(statement) == SQLiteC.done else { throw OfflineWorkRepositoryError.unavailable }
        }
    }
}
