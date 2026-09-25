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

    /// The creation forms address a building by `TPLND` / `TPWEH` / `TPGEB`,
    /// so those have to survive mapping and normalization; equipment rows
    /// carry none of them.
    func testFunctionalLocationCarriesBuildingClassificationForCreationForms() throws {
        let location = try XCTUnwrap(SAPTechnicalObjectMapper.functionalLocation(from: [
            "STRNO": "DE-ESS-10748-01-420-HZG1", "TPLMA": "DE-ESS-10748-01-420",
            "PLTXT": "Heating", "TPLND": "DE", "TPORT": "ESS",
            "TPWEH": "10748", "TPGEB": "01", "TPGSG": "420"
        ]))
        XCTAssertEqual(location.businessEntityCode, "10748")
        XCTAssertEqual(location.buildingCode, "01")
        XCTAssertEqual(location.tradeCode, "420")

        let normalized = TechnicalObjectHierarchyNormalizer.normalize([location])
        XCTAssertEqual(normalized.first?.buildingCode, "01")

        let equipment = try XCTUnwrap(SAPTechnicalObjectMapper.equipment(from: [
            "EQUNR": "EQ-2", "STRNO": "DE-ESS-10748-01-420-HZG1", "EQKTX": "Pump"
        ]))
        XCTAssertEqual(equipment.buildingCode, "")
    }

    /// The anchor matches the building, never the place's own trade: the
    /// ladder contexts sit under their own `TPGSG`.
    func testCreationAnchorMatchesBuildingAndIgnoresTrade() throws {
        let place = try XCTUnwrap(SAPTechnicalObjectMapper.functionalLocation(from: [
            "STRNO": "DE-ESS-10748-01-420-HZG1", "PLTXT": "Heating", "TPLND": "DE",
            "TPORT": "ESS", "TPWEH": "10748", "TPGEB": "01", "TPGSG": "420"
        ]))
        let anchor = try XCTUnwrap(TechnicalPlaceCreationAnchor(place))
        XCTAssertTrue(anchor.matches(countryCode: "DE", businessEntity: "10748", building: "01"))
        // A cache without TPLND still matches on the building.
        XCTAssertTrue(anchor.matches(countryCode: "", businessEntity: "10748", building: "01"))
        XCTAssertFalse(anchor.matches(countryCode: "DE", businessEntity: "10748", building: "02"))
        XCTAssertFalse(anchor.matches(countryCode: "AT", businessEntity: "10748", building: "01"))

        // An outdoor place that never reaches a building still anchors its
        // business entity, but no building.
        let outdoor = try XCTUnwrap(SAPTechnicalObjectMapper.functionalLocation(from: [
            "STRNO": "DE-ESS-10748-AUSS", "PLTXT": "Outdoor", "TPLND": "DE",
            "TPORT": "ESS", "TPWEH": "10748"
        ]))
        let outdoorAnchor = try XCTUnwrap(TechnicalPlaceCreationAnchor(outdoor))
        XCTAssertTrue(outdoorAnchor.matches(countryCode: "DE", businessEntity: "10748"))
        XCTAssertFalse(outdoorAnchor.matches(countryCode: "DE", businessEntity: "10748", building: ""))

        // Without a business entity there is nothing to anchor.
        let site = try XCTUnwrap(SAPTechnicalObjectMapper.functionalLocation(from: [
            "STRNO": "DE-ESS", "PLTXT": "Site", "TPLND": "DE", "TPORT": "ESS"
        ]))
        XCTAssertNil(TechnicalPlaceCreationAnchor(site))
    }

    /// "Equipment einbauen" fills the TFM5 form from the place it was opened
    /// on: the whole address when the building matches, the business entity
    /// alone when the place's building has no ladder context.
    @MainActor
    func testMobileLadderFormIsFilledFromTheAnchoredPlace() async throws {
        let full = try await ladderModel(anchoredAt: ["TPWEH": "UN01", "TPGEB": "BG01"])
        XCTAssertEqual(full.selectedBusinessEntity, "Musterunternehmen · Essen")
        XCTAssertEqual(full.selectedBuilding, "Bürogebäude")
        XCTAssertEqual(full.selectedTrade, "350 Leitern und Tritte")
        XCTAssertEqual(full.draft.context?.legacyContext.functionalLocation, "UN01-ST01-BG01-TECH-350")

        let aboveBuilding = try await ladderModel(anchoredAt: ["TPWEH": "UN01"])
        XCTAssertEqual(aboveBuilding.selectedBuilding, "Bürogebäude", "the only building is no choice")
        XCTAssertNotNil(aboveBuilding.draft.context)

        let otherBuilding = try await ladderModel(anchoredAt: ["TPWEH": "UN01", "TPGEB": "BG02"])
        XCTAssertEqual(otherBuilding.selectedBusinessEntity, "Musterunternehmen · Essen")
        XCTAssertNil(otherBuilding.selectedBuilding, "never falls back to another building")
        XCTAssertNil(otherBuilding.draft.context)

        let otherEntity = try await ladderModel(anchoredAt: ["TPWEH": "UN02", "TPGEB": "BG01"])
        XCTAssertNil(otherEntity.selectedBusinessEntity)
        XCTAssertNil(otherEntity.draft.context)
    }

    @MainActor
    func testSubdistributionFormIsFilledFromTheAnchoredPlace() async throws {
        let full = try await subdistributionModel(anchoredAt: ["TPWEH": "UN01", "TPGEB": "BG01"])
        XCTAssertEqual(full.selectedBusinessEntity, "Musterunternehmen · Essen")
        XCTAssertEqual(full.selectedBuilding, "Bürogebäude")
        XCTAssertEqual(full.selectedParentLocation, "Unterverteilung EG")
        XCTAssertTrue(full.isContextSelected)

        let otherBuilding = try await subdistributionModel(anchoredAt: ["TPWEH": "UN01", "TPGEB": "BG02"])
        XCTAssertEqual(otherBuilding.selectedBusinessEntity, "Musterunternehmen · Essen")
        XCTAssertNil(otherBuilding.selectedBuilding)
        XCTAssertFalse(otherBuilding.isContextSelected)
    }

    /// The place travels in the route, so a form whose task restarts still
    /// finds it; an existing draft never gets one.
    @MainActor
    func testCreationRouteCarriesTheAnchoredPlace() throws {
        let demo = FacilityDemoViewModel(
            isDemoMode: true,
            offlineWorkStore: OfflineWorkStore(repository: InMemoryOfflineWorkRepository(), workerID: "demo"),
            sapDataStore: SAPDataStore(
                repository: InMemorySAPDataCacheRepository(seed: TechnicalObjectDemoData.cachedData),
                refreshService: nil,
                localWorkerID: "demo"
            ),
            meterReferenceProvider: DemoMeterReferenceProvider(),
            photoAttachmentStore: InMemoryPhotoAttachmentStore(),
            workerDisplayName: "Alex Morgan",
            workerRole: .technician
        )
        let place = try anchor(["TPWEH": "UN01", "TPGEB": "BG01"])

        demo.openMobileLadder(preselecting: place)
        XCTAssertEqual(demo.technicalPlacesRoute, .createMobileLadder(place))
        demo.closeMobileLadder()

        demo.openSubdistribution(preselecting: place)
        XCTAssertEqual(demo.technicalPlacesRoute, .createSubdistribution(place))

        let draftID = UUID()
        demo.openMobileLadder(draftID, preselecting: place)
        XCTAssertEqual(demo.technicalPlacesRoute, .mobileLadderDraft(draftID))
    }

    /// "Equipment einbauen" offers a form only where the place's own
    /// building (or, above building level, its business entity) has a
    /// context, and names the reason otherwise.
    func testInstallAvailabilityFollowsThePlacesBuilding() throws {
        let contexts = [(country: "DE", businessEntity: "UN01", building: "BG01")]
        typealias Options = TechnicalPlaceInstallOptions
        XCTAssertEqual(
            Options.availability(at: try anchor(["TPWEH": "UN01", "TPGEB": "BG01"]), among: contexts), .available
        )
        XCTAssertEqual(Options.availability(at: try anchor(["TPWEH": "UN01"]), among: contexts), .available)
        XCTAssertEqual(
            Options.availability(at: try anchor(["TPWEH": "UN01", "TPGEB": "BG02"]), among: contexts, trade: "350"),
            .noContext(trade: "350"),
            "another building of the same entity is not this place"
        )
        XCTAssertEqual(
            Options.availability(at: try anchor(["TPWEH": "UN02"]), among: contexts, trade: "350"),
            .noContext(trade: "350")
        )
        XCTAssertEqual(Options.availability(at: try anchor(["TPWEH": "UN01"]), among: []), .noData)
        XCTAssertEqual(Options.availability(at: nil, among: contexts), .noBusinessEntity)
    }

    /// The demo place offers both forms.
    @MainActor
    func testDemoPlaceOffersBothInstallForms() async throws {
        let demo = FacilityDemoViewModel(
            isDemoMode: true,
            offlineWorkStore: OfflineWorkStore(repository: InMemoryOfflineWorkRepository(), workerID: "demo"),
            sapDataStore: SAPDataStore(
                repository: InMemorySAPDataCacheRepository(seed: TechnicalObjectDemoData.cachedData),
                refreshService: nil,
                localWorkerID: "demo"
            ),
            meterReferenceProvider: DemoMeterReferenceProvider(),
            photoAttachmentStore: InMemoryPhotoAttachmentStore(),
            workerDisplayName: "Alex Morgan",
            workerRole: .technician
        )
        let leaf = try XCTUnwrap(TechnicalObjectDemoData.objects.first {
            $0.reference.objectID == "UN01-ST01-BG01-EG00-300-BAU1"
        })
        let options = await demo.equipmentInstallOptions(at: leaf)
        XCTAssertEqual(options.mobileLadder, .available)
        XCTAssertEqual(options.subdistribution, .available)
    }

    /// Loading twice keeps a choice the technician made in between.
    @MainActor
    func testReloadDoesNotOverrideAChosenBusinessEntity() async throws {
        let model = try await ladderModel(anchoredAt: ["TPWEH": "UN01", "TPGEB": "BG02"])
        model.selectBusinessEntity("Musterunternehmen · Essen")
        model.selectBuilding("Bürogebäude")
        await model.load(preselecting: try anchor(["TPWEH": "UN01", "TPGEB": "BG02"]))
        XCTAssertEqual(model.selectedBuilding, "Bürogebäude")
    }

    private func anchor(_ codes: [String: String]) throws -> TechnicalPlaceCreationAnchor {
        var row: [String: Any] = ["STRNO": "UN01-ST01-X", "PLTXT": "Place", "TPLND": "DE", "TPORT": "ST01"]
        codes.forEach { row[$0.key] = $0.value }
        let node = try XCTUnwrap(SAPTechnicalObjectMapper.functionalLocation(from: row))
        return try XCTUnwrap(TechnicalPlaceCreationAnchor(node))
    }

    @MainActor
    private func ladderModel(anchoredAt codes: [String: String]) async throws -> MobileLadderCreationViewModel {
        let model = MobileLadderCreationViewModel(
            provider: DemoMobileLadderCreationProvider(),
            offlineWorkStore: OfflineWorkStore(repository: InMemoryOfflineWorkRepository(), workerID: "demo"),
            isDemo: true,
            item: nil
        )
        await model.load(preselecting: try anchor(codes))
        return model
    }

    @MainActor
    private func subdistributionModel(anchoredAt codes: [String: String]) async throws -> SubdistributionCreationViewModel {
        let model = SubdistributionCreationViewModel(
            provider: DemoSubdistributionCreationProvider(),
            offlineWorkStore: OfflineWorkStore(repository: InMemoryOfflineWorkRepository(), workerID: "demo"),
            isDemo: true,
            item: nil
        )
        await model.load(preselecting: try anchor(codes))
        return model
    }

    /// The demo tree has to contain at least one technical place whose detail
    /// opens — only a leaf does — and that place has to anchor the demo
    /// creation forms, or neither the actions card nor the preselection can
    /// be seen without a SAP landscape.
    func testDemoTreeHasAnOpenablePlaceThatAnchorsTheCreationForms() async throws {
        let leaf = try XCTUnwrap(TechnicalObjectDemoData.objects.first {
            $0.reference.objectID == "UN01-ST01-BG01-EG00-300-BAU1"
        })
        XCTAssertEqual(leaf.reference.kind, .functionalLocation)
        XCTAssertFalse(leaf.isSynthetic)
        XCTAssertEqual(leaf.directChildCount, 0, "the detail only opens for a leaf")

        let anchor = try XCTUnwrap(TechnicalPlaceCreationAnchor(leaf))
        let contexts = try await DemoMobileLadderCreationProvider()
            .loadMobileLadderCreationData(for: "demo").contexts
        XCTAssertTrue(contexts.contains {
            anchor.matches(
                countryCode: $0.legacyContext.country,
                businessEntity: $0.legacyContext.businessEntity,
                building: $0.legacyContext.building
            )
        })
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

    func testSQLiteLegacyCommitAndExactNotificationLinks() async throws {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString).appendingPathExtension("sqlite")
        defer { try? FileManager.default.removeItem(at: url) }
        let repository = try SQLiteSAPDataCacheRepository(databaseURL: url)
        try await repository.beginIncoming()
        try await repository.appendIncoming(.init(tables: [
            "T_0261": [[
                "MANDT": "100", "STRNO": "DE-ESS-FL-420", "TPLNR": "INTERNAL-1",
                "PLTXT": "Plant", "TPLND": "DE", "TPORT": "ESS", "CITY1": "Essen"
            ]],
            "T_0262": [[
                "MANDT": "100", "EQUNR": "EQ-1", "STRNO": "DE-ESS-FL-420",
                "TPLNR": "INTERNAL-1", "EQKTX": "Pump"
            ]],
            "T_0271": [[
                "MANDT": "100", "QMNUM": "N-1", "QMART": "I1", "QMTXT": "Exact",
                "STTXT": "OSNO", "STRNO": "DE-ESS-FL-420", "PLTXT": "Plant", "EQUNR": "EQ-1"
            ]]
        ], isLastPackage: true))
        _ = try await repository.commitIncoming(sapWorkerID: "1", refreshedAt: Date())
        let workerCount = try await repository.technicalObjectCount(for: "w1", kind: .equipment)
        XCTAssertEqual(workerCount, 1)
        let storedRoots = try await repository.loadTechnicalObjectRoots(for: "w1", limit: 10, offset: 0)
        XCTAssertEqual(storedRoots.objects.first?.cityName, "Essen")
        XCTAssertEqual(storedRoots.objects.first?.locationCode, "ESS")
        let equipmentReference = TechnicalObjectReference(kind: .equipment, objectID: "EQ-1")
        guard case let .equipment(detail)? = try await repository.loadTechnicalObjectDetail(for: "w1", reference: equipmentReference) else {
            return XCTFail("Missing equipment detail")
        }
        XCTAssertEqual(detail.linkedNotifications.map(\.id), ["N-1"])
        try await repository.beginIncoming()
        try await repository.appendIncoming(.init(tables: [
            "T_0261": [[
                "MANDT": "100", "STRNO": "DE-ESS-FL-420", "TPLNR": "INTERNAL-1",
                "PLTXT": "Plant", "TPLND": "DE", "TPORT": "ESS", "CITY1": "Essen"
            ]]
        ], isLastPackage: true))
        _ = try await repository.commitIncoming(sapWorkerID: "1", refreshedAt: Date())
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

    func testOldNormalizedCacheIsNotImportedOrModified() async throws {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString).appendingPathExtension("sqlite")
        defer { try? FileManager.default.removeItem(at: url) }
        try createVersionFourCache(at: url)
        XCTAssertThrowsError(try SQLiteSAPDataCacheRepository(databaseURL: url))
        var database: OpaquePointer?
        XCTAssertEqual(url.path.withCString {
            SQLiteC.open($0, &database, SQLiteC.openReadWrite | SQLiteC.openFullMutex, nil)
        }, SQLiteC.ok)
        defer { _ = SQLiteC.close(database) }
        var statement: OpaquePointer?
        XCTAssertEqual("SELECT raw_payload_json FROM sap_notifications".withCString {
            SQLiteC.prepare(database, $0, -1, &statement, nil)
        }, SQLiteC.ok)
        defer { _ = SQLiteC.finalize(statement) }
        XCTAssertEqual(SQLiteC.step(statement), SQLiteC.row)
        let storedText = try XCTUnwrap(SQLiteC.columnText(statement, 0))
        XCTAssertEqual(String(cString: storedText), "{\"EQUNR\":\"EQ-BACKFILL\"}")
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
