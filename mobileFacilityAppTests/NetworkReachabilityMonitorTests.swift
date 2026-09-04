import Network
import XCTest
@testable import mobileFacilityApp

final class NetworkReachabilityMonitorTests: XCTestCase {
    func testSatisfiedPathIsConnected() {
        XCTAssertEqual(
            NetworkReachabilityMonitor.status(for: .satisfied),
            .connected
        )
    }

    func testUnavailableAndRequiredConnectionPathsAreDisconnected() {
        XCTAssertEqual(
            NetworkReachabilityMonitor.status(for: .unsatisfied),
            .disconnected
        )
        XCTAssertEqual(
            NetworkReachabilityMonitor.status(for: .requiresConnection),
            .disconnected
        )
    }
}
