import Network
import SAPFoundation
import XCTest
@testable import mobileFacilityApp

@MainActor
final class NetworkReachabilityMonitorTests: XCTestCase {
    func testWiFiReachabilityIsConnected() {
        XCTAssertEqual(
            NetworkReachabilityMonitor.mappedStatus(for: .wifi),
            .connected
        )
    }

    func testWWANReachabilityIsConnected() {
        XCTAssertEqual(
            NetworkReachabilityMonitor.mappedStatus(for: .wwan),
            .connected
        )
    }

    func testOfflineReachabilityIsDisconnected() {
        XCTAssertEqual(
            NetworkReachabilityMonitor.mappedStatus(for: .offline),
            .disconnected
        )
    }

    func testSatisfiedPathIsConnected() {
        XCTAssertEqual(
            NetworkReachabilityMonitor.mappedStatus(for: .satisfied),
            .connected
        )
    }

    func testUnavailablePathIsDisconnected() {
        XCTAssertEqual(
            NetworkReachabilityMonitor.mappedStatus(for: .unsatisfied),
            .disconnected
        )
    }

    func testPathThatRequiresConnectionIsDisconnected() {
        XCTAssertEqual(
            NetworkReachabilityMonitor.mappedStatus(for: .requiresConnection),
            .disconnected
        )
    }

    func testStatusCanTransitionFromDisconnectedBackToConnectedUsingSAPReachability() {
        let monitor = NetworkReachabilityMonitor(startMonitoring: false)

        monitor.updateStatus(for: .offline)
        XCTAssertEqual(monitor.status, .disconnected)

        monitor.updateStatus(for: .wifi)
        XCTAssertEqual(monitor.status, .connected)
    }

    func testConnectionCallbacksTransitionStatus() {
        let monitor = NetworkReachabilityMonitor(startMonitoring: false)

        monitor.handleConnectionLost()
        XCTAssertEqual(monitor.status, .disconnected)

        monitor.handleConnectionEstablished()
        XCTAssertEqual(monitor.status, .connected)

        monitor.handleConnectionChanged(previous: .wifi, current: .offline)
        XCTAssertEqual(monitor.status, .disconnected)

        monitor.handleConnectionChanged(previous: .offline, current: .wwan)
        XCTAssertEqual(monitor.status, .connected)
    }
}
