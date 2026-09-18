import XCTest
@testable import mobileFacilityApp

final class NotificationListIndexTests: XCTestCase {
    private func location(
        id: String, building: String = "", trade: String = "", title: String
    ) -> FunctionalLocation {
        FunctionalLocation(
            id: id, countryCode: "DE", locationCode: "ESS", businessEntityCode: "100",
            buildingCode: building, tradeCode: trade, title: title,
            street: "", postalCode: "", city: "", country: ""
        )
    }

    func testFilterOptionsArePrecomputedPerHierarchyScope() {
        let options = NotificationStructuralFilterOptions(
            metadata: [
                .init(
                    countryCode: "DE", locationCode: "ESS", businessEntityCode: "100",
                    buildingCode: "A", tradeCode: "FM", formCode: "TFM2",
                    functionalLocationName: "Zeta building"
                ),
                .init(
                    countryCode: "DE", locationCode: "ESS", businessEntityCode: "100",
                    buildingCode: "A", tradeCode: "FM", formCode: "TFM1",
                    functionalLocationName: "Alpha building"
                ),
                .init(
                    countryCode: "DE", locationCode: "SAF", businessEntityCode: "200",
                    buildingCode: "B", tradeCode: "EL", formCode: "TFM7",
                    functionalLocationName: "Beta building"
                )
            ],
            directory: FunctionalLocationDirectory(locations: [
                location(id: "DE-ESS-100-A", building: "A", title: "GB A Office"),
                location(id: "DE-ESS-100-A-FM", building: "A", trade: "FM", title: "FM Facility management")
            ])
        )

        XCTAssertEqual(options.businessEntityOptions.map(\.id), ["DE-ESS-100", "DE-SAF-200"])
        XCTAssertEqual(
            options.buildingOptions(for: "DE-ESS-100").map(\.label),
            ["A — GB A Office"],
            "named by the building location, not by a notification in it"
        )
        XCTAssertEqual(
            options.buildingOptions(for: "DE-SAF-200").map(\.label),
            ["B"],
            "a building without its location keeps its code"
        )
        XCTAssertEqual(
            options.tradeOptions(for: "DE-ESS-100", buildingCode: "A").map(\.id),
            ["FM"]
        )
        XCTAssertEqual(
            options.tradeOptions(for: "DE-ESS-100", buildingCode: "A").map(\.label),
            ["FM Facility management"],
            "a text that starts with its code stands alone"
        )
        XCTAssertEqual(
            options.formOptions(
                for: "DE-ESS-100", buildingCode: "A", tradeCode: "FM"
            ).map(\.id),
            ["TFM1", "TFM2"]
        )
    }

    /// The legacy selection screen offers the form list as soon as the
    /// business entity is picked: `_afterGetGE4SelectionDDB` enables
    /// `select.formulare` and calls `_refreshFormulars`, which passes whatever
    /// `_getTpGeb()` / `_getTpGsg()` return — empty while nothing is selected.
    func testFormOptionsAreOfferedBeforeABuildingOrTradeIsChosen() {
        let options = NotificationStructuralFilterOptions(
            metadata: [
                .init(
                    countryCode: "DE", locationCode: "ESS", businessEntityCode: "100",
                    buildingCode: "A", tradeCode: "FM", formCode: "TFM2",
                    functionalLocationName: "Zeta building"
                ),
                .init(
                    countryCode: "DE", locationCode: "ESS", businessEntityCode: "100",
                    buildingCode: "A", tradeCode: "FM", formCode: "TFM1",
                    functionalLocationName: "Alpha building"
                ),
                .init(
                    countryCode: "DE", locationCode: "ESS", businessEntityCode: "100",
                    buildingCode: "B", tradeCode: "EL", formCode: "TFM7",
                    functionalLocationName: "Beta building"
                )
            ]
        )

        XCTAssertEqual(
            options.formOptions(for: "DE-ESS-100", buildingCode: "", tradeCode: "").map(\.id),
            ["TFM1", "TFM2", "TFM7"],
            "every form of the business entity, before a building is chosen"
        )
        XCTAssertEqual(
            options.formOptions(for: "DE-ESS-100", buildingCode: "A", tradeCode: "").map(\.id),
            ["TFM1", "TFM2"],
            "narrowed by the building, still without a trade"
        )
        XCTAssertEqual(
            options.formOptions(for: "DE-ESS-100", buildingCode: "", tradeCode: "EL").map(\.id),
            ["TFM7"]
        )
        XCTAssertEqual(
            options.formOptions(for: "DE-ESS-100", buildingCode: "A", tradeCode: "FM").map(\.id),
            ["TFM1", "TFM2"]
        )
        XCTAssertEqual(
            options.formOptions(for: "DE-SAF-200", buildingCode: "", tradeCode: "").map(\.id),
            [],
            "another business entity offers none of them"
        )
    }

    func testIndexedStructuralFilterPagesOnlyMatchingNotifications() async throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let index = try SQLiteNotificationListIndex(
            databaseURL: directory.appendingPathComponent("notification-list-index.sqlite")
        )
        let workerID = "worker-1"
        let version = "2026-09-16T10:00:00Z"
        try await index.replace(
            (0..<1_000).map { number in
                let entity = number.isMultiple(of: 2) ? "100" : "200"
                let isFilteredCombination = number % 4 == 1
                return notification(
                    id: String(format: "N-%04d", number),
                    title: number == 777 ? "Pump room inspection" : "Inspection \(number)",
                    entity: entity,
                    building: isFilteredCombination ? "A" : "B",
                    form: isFilteredCombination ? "TFM2" : "TFM1"
                )
            },
            for: workerID,
            sourceVersion: version
        )

        let isCurrent = try await index.isCurrent(for: workerID, sourceVersion: version)
        XCTAssertTrue(isCurrent)

        let filtered = try await index.loadNotifications(
            for: workerID,
            matching: "",
            structuralFilter: .init(
                businessEntityID: "DE-ESS-200",
                buildingCode: "A",
                tradeCode: "FM",
                formCode: "TFM2"
            ),
            limit: 40,
            offset: 0
        )
        XCTAssertEqual(filtered.notifications.count, 40)
        XCTAssertEqual(filtered.totalCount, 250)
        XCTAssertEqual(filtered.nextOffset, 40)
        XCTAssertTrue(filtered.notifications.allSatisfy {
            $0.structuralFilterMetadata?.businessEntityID == "DE-ESS-200" &&
            $0.structuralFilterMetadata?.buildingCode == "A" &&
            $0.structuralFilterMetadata?.formCode == "TFM2"
        })

        let search = try await index.loadNotifications(
            for: workerID,
            matching: "PUMP ROOM",
            structuralFilter: .empty,
            limit: 40,
            offset: 0
        )
        XCTAssertEqual(search.notifications.map(\.id), ["N-0777"])
        XCTAssertEqual(search.totalCount, 1)
    }

    func testIndexSummaryAndMetadataAreWorkerScoped() async throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let index = try SQLiteNotificationListIndex(
            databaseURL: directory.appendingPathComponent("notification-list-index.sqlite")
        )
        try await index.replace(
            [
                notification(id: "N-1", title: "Lift", entity: "100", building: "A", form: "TFM2"),
                notification(id: "N-2", title: "Pump", entity: "100", building: "B", form: "TFM1"),
                notification(id: "N-3", title: "Door", entity: "200", building: "A", form: "TFM1")
            ],
            for: "worker-1",
            sourceVersion: "v1"
        )
        try await index.replace(
            [notification(id: "N-4", title: "Other", entity: "300", building: "C", form: "TFM1")],
            for: "worker-2",
            sourceVersion: "v1"
        )

        let summary = try await index.summary(for: "worker-1")
        XCTAssertEqual(summary.actionableCount, 3)
        XCTAssertEqual(summary.businessEntityCount, 2)
        XCTAssertEqual(summary.elevatorInspectionCount, 1)
        let metadata = try await index.loadFilterMetadata(for: "worker-1")
        XCTAssertEqual(metadata.count, 3)
        let secondWorkerPage = try await index.loadNotifications(
            for: "worker-2", matching: "", structuralFilter: .empty, limit: 40, offset: 0
        )
        XCTAssertEqual(
            secondWorkerPage.notifications.map(\.id),
            ["N-4"]
        )
    }

    private func notification(
        id: String,
        title: String,
        entity: String,
        building: String,
        form: String
    ) -> SAPNotificationSummary {
        let metadata = NotificationStructuralFilterMetadata(
            countryCode: "DE",
            locationCode: "ESS",
            businessEntityCode: entity,
            buildingCode: building,
            tradeCode: "FM",
            formCode: form,
            functionalLocationName: "Building \(building)"
        )
        return SAPNotificationSummary(
            id: id,
            client: "100",
            title: title,
            functionalLocationID: "FL-\(id)",
            functionalLocationName: "Building \(building)",
            equipmentID: "EQ-\(id)",
            startDate: "20260916",
            endDate: "20260916",
            systemStatus: "OPEN",
            userStatus: "",
            rawPayloadJSON: "{}",
            structuralFilterMetadata: metadata
        )
    }
}
