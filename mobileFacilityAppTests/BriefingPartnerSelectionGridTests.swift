import XCTest
@testable import mobileFacilityApp

final class BriefingPartnerSelectionGridTests: XCTestCase {
    private let partners = [
        BriefingPartnerSelection(
            id: "1",
            client: "100",
            function: "ZT",
            name: "Westnetz Service GmbH",
            searchTerm1: "Westnetz",
            searchTerm2: "Dortmund"
        ),
        BriefingPartnerSelection(
            id: "2",
            client: "200",
            function: "Z1",
            name: "Innoggy Partner",
            searchTerm1: "Innoggy",
            searchTerm2: "Essen"
        )
    ]

    func testGridColumnsExposeEveryLegacyPartnerField() throws {
        let partner = try XCTUnwrap(partners.first)

        XCTAssertEqual(BriefingPartnerSelectionTable.Column.client.value(from: partner), "100")
        XCTAssertEqual(BriefingPartnerSelectionTable.Column.function.value(from: partner), "ZT")
        XCTAssertEqual(BriefingPartnerSelectionTable.Column.name.value(from: partner), "Westnetz Service GmbH")
        XCTAssertEqual(BriefingPartnerSelectionTable.Column.searchTerm1.value(from: partner), "Westnetz")
        XCTAssertEqual(BriefingPartnerSelectionTable.Column.searchTerm2.value(from: partner), "Dortmund")
    }

    func testGridCombinesCaseInsensitiveColumnFilters() {
        let results = BriefingPartnerSelectionTable.filteredPartners(
            partners: partners,
            filters: [.function: "zt", .searchTerm2: "DORT"],
            sort: .nameAscending
        )

        XCTAssertEqual(results.map(\.id), ["1"])
    }

    func testGridSortsAscendingAndDescendingBySelectedColumn() {
        let ascending = BriefingPartnerSelectionTable.filteredPartners(
            partners: partners,
            filters: [:],
            sort: .clientAscending
        )
        let descending = BriefingPartnerSelectionTable.filteredPartners(
            partners: partners,
            filters: [:],
            sort: .clientDescending
        )

        XCTAssertEqual(ascending.map(\.id), ["1", "2"])
        XCTAssertEqual(descending.map(\.id), ["2", "1"])
    }
}
