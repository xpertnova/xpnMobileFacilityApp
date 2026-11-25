import Foundation
import XCTest
@testable import mobileFacilityApp

final class SAPSyncStageTests: XCTestCase {
    func testReceivingIncomingPackagesStageEquality() {
        let stage1 = SAPReadRefreshStage.receivingIncomingPackages(packageNumber: 1)
        let stage2 = SAPReadRefreshStage.receivingIncomingPackages(packageNumber: 2)
        let stage1Repeat = SAPReadRefreshStage.receivingIncomingPackages(packageNumber: 1)

        XCTAssertEqual(stage1, stage1Repeat)
        XCTAssertNotEqual(stage1, stage2)
    }

    func testDefaultPackageNumber() {
        let defaultStage = SAPReadRefreshStage.receivingIncomingPackages()
        XCTAssertEqual(defaultStage, .receivingIncomingPackages(packageNumber: 1))
    }
}
