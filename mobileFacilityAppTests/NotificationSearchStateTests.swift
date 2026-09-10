import XCTest
@testable import mobileFacilityApp

final class NotificationSearchStateTests: XCTestCase {
    func testDraftTextDoesNotChangeTheAppliedQueryUntilSubmitted() {
        var state = NotificationSearchState()

        state.draftQuery = "  Pump  "

        XCTAssertEqual(state.appliedQuery, "")
        XCTAssertTrue(state.submit())
        XCTAssertEqual(state.appliedQuery, "Pump")
    }

    func testSubmittingTheSameNormalizedQueryDoesNotStartAnotherSearch() {
        var state = NotificationSearchState()
        state.draftQuery = "Pump"
        XCTAssertTrue(state.submit())

        state.draftQuery = "  Pump  "

        XCTAssertFalse(state.submit())
        XCTAssertEqual(state.appliedQuery, "Pump")
    }

    func testSubmittingAnEmptyDraftClearsTheAppliedQuery() {
        var state = NotificationSearchState(draftQuery: "Pump")
        XCTAssertTrue(state.submit())

        state.draftQuery = "   "

        XCTAssertTrue(state.submit())
        XCTAssertEqual(state.appliedQuery, "")
    }
}
