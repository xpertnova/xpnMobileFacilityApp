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
        let network = NetworkStub(isReachable: false)
        let monitor = NetworkReachabilityMonitor(startMonitoring: false, isNetworkReachable: { network.isReachable })

        monitor.handleConnectionLost()
        XCTAssertEqual(monitor.status, .disconnected)

        monitor.handleConnectionEstablished()
        XCTAssertEqual(monitor.status, .connected)

        monitor.handleConnectionChanged(previous: .wifi, current: .offline)
        XCTAssertEqual(monitor.status, .disconnected)

        network.isReachable = true
        monitor.handleConnectionChanged(previous: .offline, current: .wifi)
        XCTAssertEqual(monitor.status, .connected)
    }

    /// SAPFoundation counts `.wwan` only with a cellular carrier
    /// (`CTTelephonyNetworkInfo`), which an iPad without SIM, or a simulator,
    /// never has. The monitor then relies on the reachability check.
    func testCellularChangeCountsAsConnectedWhileTheNetworkIsReachable() {
        let network = NetworkStub(isReachable: false)
        let monitor = NetworkReachabilityMonitor(startMonitoring: false, isNetworkReachable: { network.isReachable })
        monitor.handleConnectionLost()

        network.isReachable = true
        monitor.handleConnectionChanged(previous: .offline, current: .wwan)

        XCTAssertEqual(monitor.status, .connected)
        XCTAssertEqual(monitor.currentReachabilityType, .wwan)
    }

    /// SAP reports a lost connection while Wi-Fi renegotiates; the status
    /// only drops once the network is really unreachable.
    func testLostCallbackIsIgnoredWhileTheNetworkIsStillReachable() {
        let network = NetworkStub(isReachable: true)
        let monitor = NetworkReachabilityMonitor(startMonitoring: false, isNetworkReachable: { network.isReachable })
        monitor.handleConnectionEstablished()

        monitor.handleConnectionLost()

        XCTAssertEqual(monitor.status, .connected)
    }
}

private final class NetworkStub: @unchecked Sendable {
    var isReachable: Bool

    init(isReachable: Bool) {
        self.isReachable = isReachable
    }
}
