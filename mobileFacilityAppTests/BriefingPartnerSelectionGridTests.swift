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

    func testAllFourFiltersCombineAndIgnoreSurroundingWhitespace() {
        let results = BriefingPartnerSelectionTable.filteredPartners(
            partners: partners,
            filters: [.function: " zt ", .name: "SERVICE", .searchTerm1: "west", .searchTerm2: "dort"],
            sort: .nameAscending
        )
        XCTAssertEqual(results.map(\.id), ["1"])
    }

    func testFiltersCanProduceAnEmptyResultAndBeCleared() {
        let empty = BriefingPartnerSelectionTable.filteredPartners(
            partners: partners, filters: [.name: "missing"], sort: .nameAscending
        )
        XCTAssertTrue(empty.isEmpty)
        let cleared = BriefingPartnerSelectionTable.filteredPartners(
            partners: partners, filters: [:], sort: .nameAscending
        )
        XCTAssertEqual(cleared.count, partners.count)
    }

    func testAddingScopesOnlyCurrentPresentationAndReopeningRestoresDirectory() {
        var currentSession = BriefingPartnerPickerSession()
        XCTAssertEqual(currentSession.visiblePartners(in: partners), partners)
        currentSession.recentlyAddedPartnerID = "2"
        XCTAssertEqual(currentSession.visiblePartners(in: partners).map(\.id), ["2"])

        let reopenedSession = BriefingPartnerPickerSession()
        XCTAssertEqual(reopenedSession.visiblePartners(in: partners), partners)
        XCTAssertEqual(partners.count, 2, "Presentation filtering must not mutate master data")
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

    func testExtractPropertyNumberFromBusinessEntity() {
        XCTAssertEqual(BriefingWorkflowViewModel.extractPropertyNumber(from: "DE-ESS-11250"), "11250")
        XCTAssertEqual(BriefingWorkflowViewModel.extractPropertyNumber(from: "DE-ESS-11248"), "11248")
        XCTAssertEqual(BriefingWorkflowViewModel.extractPropertyNumber(from: "11250"), "11250")
        XCTAssertEqual(BriefingWorkflowViewModel.extractPropertyNumber(from: "WE-11250"), "11250")
        XCTAssertEqual(BriefingWorkflowViewModel.extractPropertyNumber(from: "DE-DOR-00123"), "00123")
    }

    func testFilteringPartnersWithSearchTerm2Number() {
        let partnersWithNumbers = [
            BriefingPartnerSelection(
                id: "1", client: "100", function: "ZT", name: "Dummy A",
                searchTerm1: "TEST", searchTerm2: "11250"
            ),
            BriefingPartnerSelection(
                id: "2", client: "100", function: "ZT", name: "Dummy B",
                searchTerm1: "ESSEN", searchTerm2: "1"
            )
        ]

        let results = BriefingPartnerSelectionTable.filteredPartners(
            partners: partnersWithNumbers,
            filters: [.searchTerm2: "11250"],
            sort: .nameAscending
        )

        XCTAssertEqual(results.count, 1)
        XCTAssertEqual(results.first?.id, "1")
    }

    @MainActor
    func testSearchTerm2IsSetWhenWorkPropertyIsChosenOrUpdated() {
        let store = OfflineWorkStore(repository: InMemoryOfflineWorkRepository(), workerID: "test")
        let briefing = BriefingWorkflowViewModel(
            source: .init(
                isDemo: false,
                contexts: [
                    BriefingWorkflowViewModel.Context(
                        businessEntityID: "DE-ESS-10748",
                        businessEntityTitle: "DE-ESS-10748",
                        buildingCode: "A",
                        buildingTitle: "Building A"
                    ),
                    BriefingWorkflowViewModel.Context(
                        businessEntityID: "DE-ESS-11250",
                        businessEntityTitle: "DE-ESS-11250",
                        buildingCode: "B",
                        buildingTitle: "Building B"
                    )
                ],
                partners: [],
                templates: [],
                workerProfile: nil,
                workerName: "Test",
                offlineWorkStore: store
            )
        )

        // When form is first opened, no work property is chosen -> search form 2 is empty
        XCTAssertEqual(briefing.partnerSearchTerm2, "")

        // When work property is chosen -> sets search form 2
        briefing.selectBusinessEntity("DE-ESS-11250")
        XCTAssertEqual(briefing.partnerSearchTerm2, "11250")

        // When work property is updated -> updates search form 2
        briefing.selectBusinessEntity("DE-ESS-10748")
        XCTAssertEqual(briefing.partnerSearchTerm2, "10748")

        // When work property is cleared -> clears search form 2
        briefing.selectBusinessEntity("")
        XCTAssertEqual(briefing.partnerSearchTerm2, "")
    }

    @MainActor
    func testClearingFilterPersistsUntilWorkPropertyChanges() {
        let store = OfflineWorkStore(repository: InMemoryOfflineWorkRepository(), workerID: "test")
        let briefing = BriefingWorkflowViewModel(
            source: .init(
                isDemo: false,
                contexts: [],
                partners: [],
                templates: [],
                workerProfile: nil,
                workerName: "Test",
                offlineWorkStore: store
            )
        )

        // 1. User chooses work property
        briefing.selectBusinessEntity("DE-ESS-11250")
        XCTAssertEqual(briefing.partnerSearchTerm2, "11250")

        // 2. User clears the filter in partner picker
        briefing.partnerSearchTerm2 = ""
        XCTAssertEqual(briefing.partnerSearchTerm2, "")

        // 3. User does not change work property -> stays empty
        XCTAssertEqual(briefing.partnerSearchTerm2, "")

        // 4. User changes work property -> filter is set again
        briefing.selectBusinessEntity("DE-ESS-10748")
        XCTAssertEqual(briefing.partnerSearchTerm2, "10748")
    }
}

