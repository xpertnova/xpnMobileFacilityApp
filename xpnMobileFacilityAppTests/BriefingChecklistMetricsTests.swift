import CoreGraphics
import XCTest
@testable import mobileFacilityApp

final class BriefingChecklistMetricsTests: XCTestCase {
    func testRegularWindowKeepsTheOriginalColumns() {
        let metrics = BriefingChecklistMetrics(layout: FacilityLayoutMetrics(windowSize: CGSize(width: 1_376, height: 1_032)))

        XCTAssertEqual(metrics.numberColumn, 70)
        XCTAssertEqual(metrics.answerColumn, 220)
        XCTAssertEqual(metrics.documentColumn, 54)
        XCTAssertEqual(metrics.informationColumn, 64)
        XCTAssertEqual(metrics.commentColumn, 96)
    }

    func testCompactWindowLeavesTheItemTextReadableInTheNarrowestWindow() {
        let metrics = BriefingChecklistMetrics(layout: FacilityLayoutMetrics(windowSize: CGSize(width: 700, height: 744)))
        let fixedColumns = metrics.numberColumn + metrics.answerColumn + metrics.documentColumn
            + metrics.informationColumn + metrics.commentColumn
        // 700 pt window − 72 pt rail − 1 pt divider − 2 × 20 pt page padding
        // − 2 × 12 pt row padding.
        let rowWidth: CGFloat = 700 - 72 - 1 - 40 - 24

        XCTAssertGreaterThanOrEqual(rowWidth - fixedColumns, 200)
    }
}
