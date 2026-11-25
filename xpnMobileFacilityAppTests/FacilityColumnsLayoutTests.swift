import XCTest
@testable import mobileFacilityApp

final class FacilityColumnsLayoutTests: XCTestCase {
    private let dashboardMetrics = FacilityColumnsLayout(columnCounts: [4, 2, 1], minimumColumnWidth: 230, spacing: 14)

    func testKeepsFourColumnsBesideTheExpandedSidebarOnThirteenInchIPad() {
        // 1376 pt window − 340 pt sidebar − 1 pt divider − 2 × 28 pt padding.
        XCTAssertEqual(dashboardMetrics.columnCount(forWidth: 979), 4)
    }

    func testKeepsFourColumnsBesideTheRailOnIPadMini() {
        // 1133 pt window − 72 pt rail − 1 pt divider − 2 × 20 pt padding.
        XCTAssertEqual(dashboardMetrics.columnCount(forWidth: 1_020), 4)
    }

    func testStepsToTwoColumnsRatherThanThreeOnTheNarrowestWindow() {
        // 700 pt window − 72 pt rail − 1 pt divider − 2 × 20 pt padding.
        XCTAssertEqual(dashboardMetrics.columnCount(forWidth: 587), 2)
        XCTAssertEqual(dashboardMetrics.columnCount(forWidth: 900), 2)
    }

    func testFallsBackToTheSmallestCountWhenNothingFits() {
        XCTAssertEqual(dashboardMetrics.columnCount(forWidth: 200), 1)
    }

    func testUsesTheLargestCountWithoutAWidth() {
        XCTAssertEqual(dashboardMetrics.columnCount(forWidth: nil), 4)
    }
}
