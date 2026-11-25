import CoreGraphics
import XCTest
@testable import mobileFacilityApp

final class FacilityLayoutMetricsTests: XCTestCase {
    func testIPadMiniLandscapeIsCompact() {
        XCTAssertEqual(FacilityLayoutMetrics(windowSize: CGSize(width: 1_133, height: 744)).tier, .compact)
    }

    func testElevenInchIPadsLandscapeAreRegular() {
        XCTAssertEqual(FacilityLayoutMetrics(windowSize: CGSize(width: 1_180, height: 820)).tier, .regular)
        XCTAssertEqual(FacilityLayoutMetrics(windowSize: CGSize(width: 1_210, height: 834)).tier, .regular)
    }

    func testThirteenInchIPadLandscapeIsRegular() {
        XCTAssertEqual(FacilityLayoutMetrics(windowSize: CGSize(width: 1_376, height: 1_032)).tier, .regular)
    }

    func testNarrowSplitViewPaneOnLargeIPadIsCompact() {
        XCTAssertEqual(FacilityLayoutMetrics(windowSize: CGSize(width: 900, height: 1_032)).tier, .compact)
    }

    func testUnmeasuredWindowKeepsRegularLayout() {
        XCTAssertEqual(FacilityLayoutMetrics.regular.tier, .regular)
        XCTAssertEqual(FacilityLayoutMetrics(windowSize: CGSize(width: 0, height: 744)).tier, .regular)
    }

    func testRegularTierKeepsTheLargeIPadSizes() {
        let layout = FacilityLayoutMetrics(windowSize: CGSize(width: 1_376, height: 1_032))

        XCTAssertEqual(layout.expandedSidebarWidth, 340)
        XCTAssertEqual(layout.sidebarRowMinHeight, 48)
        XCTAssertEqual(layout.dialogPadding(32), 32)
        XCTAssertEqual(layout.commentEditorHeight, 190)
    }

    func testFullSidebarOverlaysTheScreenOnlyInNarrowWindows() {
        XCTAssertTrue(FacilityLayoutMetrics(windowSize: CGSize(width: 700, height: 744)).overlaysExpandedSidebar)
        XCTAssertFalse(FacilityLayoutMetrics(windowSize: CGSize(width: 1_133, height: 744)).overlaysExpandedSidebar)
        XCTAssertFalse(FacilityLayoutMetrics(windowSize: CGSize(width: 1_376, height: 1_032)).overlaysExpandedSidebar)
        XCTAssertFalse(FacilityLayoutMetrics.regular.overlaysExpandedSidebar)
    }

    func testCompactTierTightensPagePadding() {
        XCTAssertEqual(FacilityLayoutMetrics(windowSize: CGSize(width: 1_376, height: 1_032)).pagePadding, 28)
        XCTAssertEqual(FacilityLayoutMetrics(windowSize: CGSize(width: 1_133, height: 744)).pagePadding, 20)
    }

    func testCompactTierTightensDialogPaddingButNeverWidensIt() {
        let layout = FacilityLayoutMetrics(windowSize: CGSize(width: 1_133, height: 744))

        XCTAssertEqual(layout.dialogPadding(32), 22)
        XCTAssertEqual(layout.dialogPadding(16), 16)
    }
}
