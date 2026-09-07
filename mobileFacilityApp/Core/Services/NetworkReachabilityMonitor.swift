import Foundation
import Network
import Observation

enum NetworkReachabilityStatus: Equatable, Sendable {
    case checking
    case connected
    case disconnected
}

/// Observes the iPad's active network path. This deliberately reports network
/// reachability only; SAP availability remains known only after a confirmed SAP request.
@MainActor
@Observable
final class NetworkReachabilityMonitor {
    private let pathMonitor = NWPathMonitor()
    private let queue = DispatchQueue(
        label: "com.mobilefacility.network-reachability",
        qos: .utility
    )

    private(set) var status: NetworkReachabilityStatus = .checking

    init() {
        pathMonitor.pathUpdateHandler = { [weak self] path in
            let status = Self.status(for: path.status)

            Task { @MainActor [weak self] in
                self?.status = status
            }
        }
        pathMonitor.start(queue: queue)
    }

    nonisolated static func status(for pathStatus: NWPath.Status) -> NetworkReachabilityStatus {
        pathStatus == .satisfied ? .connected : .disconnected
    }

    deinit {
        pathMonitor.cancel()
    }
}
