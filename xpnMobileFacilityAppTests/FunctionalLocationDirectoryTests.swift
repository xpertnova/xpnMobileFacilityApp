import XCTest
@testable import mobileFacilityApp

final class FunctionalLocationDirectoryTests: XCTestCase {
    func testSQLiteDirectoryKeepsActiveBusinessEntityBuildingAndTradeLocations() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let repository = try SQLiteSAPDataCacheRepository(
            databaseURL: directory.appendingPathComponent("cache.sqlite"),
            workerID: "S50828"
        )
        try await repository.insertLegacyRows([
            row("DE-SAF-11152", text: "Rauschermühle"),
            row("DE-SAF-11152-01", building: "01", text: "GB01_Rauschermühle_G8 Hauptlager"),
            row("DE-SAF-11152-01-350", building: "01", trade: "350", text: "350 Leitern und Tritte"),
            // A sub-location below a trade never names a level.
            row("DE-SAF-11152-01-330-003", building: "01", trade: "330", sub: "003", text: "Sektionaltor"),
            row("DE-SAF-11152-02", building: "02", text: "GB02 closed", status: "aBet")
        ], into: "FROM_T0272")

        let locations = try await repository.loadFunctionalLocationDirectory(for: "S50828")

        XCTAssertEqual(locations.businessEntities.map(\.id), ["DE-SAF-11152"])
        XCTAssertEqual(locations.buildings.map(\.id), ["DE-SAF-11152-01"])
        XCTAssertEqual(
            locations.building(countryCode: "DE", businessEntityCode: "11152", buildingCode: "01")?.title,
            "GB01_Rauschermühle_G8 Hauptlager"
        )
        XCTAssertEqual(
            locations.trade(countryCode: "DE", businessEntityCode: "11152", buildingCode: "01", tradeCode: "350")?.title,
            "350 Leitern und Tritte"
        )
        XCTAssertNil(locations.trade(countryCode: "DE", businessEntityCode: "11152", buildingCode: "01", tradeCode: "330"))
        XCTAssertNil(locations.building(countryCode: "DE", businessEntityCode: "11152", buildingCode: "02"))
    }

    func testSafetyFormsOfferEachBuildingAsTheWorkLocation() {
        let directory = FunctionalLocationDirectory(locations: [
            location("DE-SAF-11152", text: "Rauschermühle"),
            location("DE-SAF-11152-01", building: "01", text: "GB01_Rauschermühle_G8 Hauptlager"),
            location("DE-SAF-11152-01-350", building: "01", trade: "350", text: "350 Leitern und Tritte"),
            // A building whose business entity is not offered cannot be reached.
            location("DE-SAF-99999-01", businessEntity: "99999", building: "01", text: "Orphan")
        ])

        let contexts = SafetyFormContext.buildings(in: directory)

        XCTAssertEqual(contexts, [SafetyFormContext(
            businessEntityID: "DE-SAF-11152",
            businessEntityTitle: "DE-SAF-11152",
            buildingCode: "01",
            buildingTitle: "GB01_Rauschermühle_G8 Hauptlager",
            functionalLocationID: "DE-SAF-11152-01",
            functionalLocationTitle: "Rauschermühle,\n56648, Saffig (DE)"
        )])
    }

    private func row(
        _ strno: String, building: String = "", trade: String = "", sub: String = "",
        text: String, status: String = "iBet"
    ) -> LegacySAPRow {
        [
            "MANDT": "100", "STRNO": strno, "TPLND": "DE", "TPORT": "SAF", "TPWEH": "11152",
            "TPGEB": building, "TPGSG": trade, "TPUSG": sub, "PLTXT": text, "USTXT": status
        ]
    }

    private func location(
        _ id: String, businessEntity: String = "11152", building: String = "", trade: String = "", text: String
    ) -> FunctionalLocation {
        FunctionalLocation(
            id: id, countryCode: "DE", locationCode: "SAF", businessEntityCode: businessEntity,
            buildingCode: building, tradeCode: trade, title: text,
            street: "Rauschermühle", postalCode: "56648", city: "Saffig", country: "DE"
        )
    }
}
