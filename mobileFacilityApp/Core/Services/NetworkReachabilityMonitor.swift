import Foundation
import Network
import Observation
import SAPFoundation
import SystemConfiguration

enum NetworkReachabilityStatus: Equatable, Sendable {
    case checking
    case connected
    case disconnected
}

/// Observes network connectivity using SAPFoundation's connectivity infrastructure
/// (ConnectivityReceiver, ConnectivityObserver, and ConnectivityUtils) combined with
/// SAP host reachability, system reachability flags, and active probing for robust offline-to-online recovery.
@MainActor
@Observable
final class NetworkReachabilityMonitor {
    @ObservationIgnored
    private nonisolated(unsafe) var observerBridge: SAPConnectivityObserverBridge?
    @ObservationIgnored
    private var pathMonitor: NWPathMonitor?
    @ObservationIgnored
    private var refreshTask: Task<Void, Never>?
    @ObservationIgnored
    private var recoveryTask: Task<Void, Never>?

    private(set) var status: NetworkReachabilityStatus = .checking
    private(set) var currentReachabilityType: ReachabilityType?

    /// SAP, host and system reachability combined; replaceable so the SAP
    /// callbacks can be checked without depending on the device's network.
    @ObservationIgnored
    private let isNetworkReachable: @Sendable () -> Bool

    /// SAP host parsed from ConfigurationProvider.plist
    nonisolated static let sapHost: String? = {
        guard let url = Bundle.main.url(forResource: "ConfigurationProvider", withExtension: "plist"),
              let dict = NSDictionary(contentsOf: url) as? [String: Any],
              let host = dict["host"] as? String,
              !host.isEmpty, !host.contains("YOUR_") else {
            return nil
        }
        return host
    }()

    init(
        startMonitoring: Bool = true,
        isNetworkReachable: @escaping @Sendable () -> Bool = { NetworkReachabilityMonitor.evaluateReachability() }
    ) {
        self.isNetworkReachable = isNetworkReachable
        if startMonitoring {
            start()
        }
    }

    deinit {
        if let observerBridge {
            ConnectivityReceiver.unregisterObserver(observerBridge)
        }
        pathMonitor?.cancel()
        refreshTask?.cancel()
        recoveryTask?.cancel()
    }

    func start() {
        guard observerBridge == nil else {
            refresh()
            return
        }

        print("[SAP Connection] 🚀 Starting network reachability monitoring (SAP ConnectivityReceiver + NWPathMonitor)")

        let bridge = SAPConnectivityObserverBridge(owner: self)
        self.observerBridge = bridge
        ConnectivityReceiver.registerObserver(bridge)

        // Monitor network path via NWPathMonitor for complementary events
        let monitor = NWPathMonitor()
        self.pathMonitor = monitor
        let queue = DispatchQueue(label: "com.mobilefacility.reachability-monitor", qos: .utility)
        monitor.pathUpdateHandler = { [weak self] path in
            Task { @MainActor [weak self] in
                guard let self else { return }
                print("[SAP Connection] 🌐 [NWPathMonitor] Path updated: status=\(path.status), interfaces=\(path.availableInterfaces.map(\.name))")
                if path.status == .satisfied {
                    self.updateStatusDirectly(.connected, reason: "NWPathMonitor satisfied")
                } else {
                    // Wi-Fi may be renegotiating or awaiting socket activity. Run an active probe:
                    let isReachable = await Self.probeNetwork()
                    if isReachable {
                        self.updateStatusDirectly(.connected, reason: "Active probe after NWPath update")
                    } else {
                        self.updateStatusDirectly(.disconnected, reason: "NWPathMonitor unsatisfied")
                    }
                }
            }
        }
        monitor.start(queue: queue)

        synchronizeReachability()
    }

    func stop() {
        print("[SAP Connection] 🛑 Stopping network reachability monitoring")
        refreshTask?.cancel()
        refreshTask = nil

        recoveryTask?.cancel()
        recoveryTask = nil

        pathMonitor?.cancel()
        pathMonitor = nil

        if let bridge = observerBridge {
            ConnectivityReceiver.unregisterObserver(bridge)
            self.observerBridge = nil
        }
    }

    /// Queries SAP ConnectivityUtils and system reachability to synchronize the state.
    func refresh() {
        print("[SAP Connection] 🔄 Refresh requested")
        synchronizeReachability()

        refreshTask?.cancel()
        refreshTask = Task { @MainActor [weak self] in
            for (step, delay) in [1.0, 2.5, 4.0].enumerated() {
                try? await Task.sleep(for: .seconds(delay))
                guard !Task.isCancelled, let self else { return }
                print("[SAP Connection] ⏱️ Running retry check #\(step + 1) after \(delay)s delay")
                let isOnline = await Self.probeNetwork()
                if isOnline {
                    self.updateStatusDirectly(.connected, reason: "Retry check #\(step + 1) probe succeeded")
                    break
                }
            }
        }
    }

    /// Synchronizes status directly from SAP ConnectivityUtils, host reachability, and system flags
    func synchronizeReachability() {
        let isConnected = isNetworkReachable()
        let isSAPConnected = ConnectivityUtils.isConnected()
        let isSystemReachable = Self.checkSystemReachability()

        print("[SAP Connection] 🔍 Reachability check -> overall=\(isConnected ? "CONNECTED" : "DISCONNECTED") (SAP.isConnected=\(isSAPConnected), systemReachable=\(isSystemReachable))")

        updateStatusDirectly(
            isConnected ? .connected : .disconnected,
            reason: "synchronizeReachability (SAP=\(isSAPConnected), System=\(isSystemReachable))"
        )
    }

    private func updateStatusDirectly(_ newStatus: NetworkReachabilityStatus, reason: String) {
        let oldStatus = status
        if status != newStatus {
            status = newStatus
            let symbol = (newStatus == .connected) ? "🟢 CONNECTED" : "🔴 DISCONNECTED"
            print("[SAP Connection] \(symbol) Status changed: \(oldStatus) -> \(newStatus) [Reason: \(reason)]")
            if newStatus == .disconnected {
                startDisconnectedRecoveryTask()
            } else {
                recoveryTask?.cancel()
                recoveryTask = nil
            }
        } else {
            print("[SAP Connection] ℹ️ Status confirmed: \(status) [Reason: \(reason)]")
            if newStatus == .disconnected, recoveryTask == nil {
                startDisconnectedRecoveryTask()
            }
        }
    }

    /// Background recovery loop while disconnected: probes network with a 3-second interval until reconnection is confirmed.
    private func startDisconnectedRecoveryTask() {
        guard recoveryTask == nil else { return }
        print("[SAP Connection] ⏳ Starting disconnected recovery probe loop (interval: 3s)")

        recoveryTask = Task { @MainActor [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(3))
                guard !Task.isCancelled, let self else { return }
                guard self.status == .disconnected else { return }

                print("[SAP Connection] 🔍 Probing for network reconnection (interval: 3s)...")
                let isOnline = await Self.probeNetwork()
                if isOnline {
                    print("[SAP Connection] 🟢 Recovery probe succeeded -> marking CONNECTED")
                    self.updateStatusDirectly(.connected, reason: "Recovery probe succeeded")
                    return
                }
            }
        }
    }

    /// Internal handler called by the SAP ConnectivityObserver bridge when a connection is established.
    func handleConnectionEstablished() {
        print("[SAP Connection] 🟢 [SAP Observer] connectionEstablished() received")
        updateStatusDirectly(.connected, reason: "SAP ConnectivityObserver.connectionEstablished")
    }

    /// Internal handler called by the SAP ConnectivityObserver bridge when reachability changes.
    func handleConnectionChanged(
        previous: ReachabilityType,
        current: ReachabilityType
    ) {
        currentReachabilityType = current
        let isConnected = ConnectivityUtils.isConnected(current) || isNetworkReachable()
        print("[SAP Connection] 🔀 [SAP Observer] connectionChanged: \(previous) -> \(current), isConnected=\(isConnected)")
        updateStatusDirectly(
            isConnected ? .connected : .disconnected,
            reason: "SAP ConnectivityObserver.connectionChanged(\(previous) -> \(current))"
        )
    }

    /// Internal handler called by the SAP ConnectivityObserver bridge when connection is lost.
    func handleConnectionLost() {
        print("[SAP Connection] 🔴 [SAP Observer] connectionLost() received")
        if !isNetworkReachable() {
            updateStatusDirectly(.disconnected, reason: "SAP ConnectivityObserver.connectionLost")
        } else {
            print("[SAP Connection] ⚠️ SAP reported connection lost, but reachability check indicates network is reachable")
        }
    }

    /// Updates status for a specific SAP ReachabilityType (useful for tests)
    func updateStatus(for reachabilityType: ReachabilityType) {
        currentReachabilityType = reachabilityType
        status = Self.mappedStatus(for: reachabilityType)
    }

    /// Retained for test compatibility with NWPath.Status
    func updateStatus(for pathStatus: NWPath.Status) {
        status = Self.mappedStatus(for: pathStatus)
    }

    nonisolated static func mappedStatus(
        for reachabilityType: ReachabilityType
    ) -> NetworkReachabilityStatus {
        ConnectivityUtils.isConnected(reachabilityType) ? .connected : .disconnected
    }

    nonisolated static func mappedStatus(
        for pathStatus: NWPath.Status
    ) -> NetworkReachabilityStatus {
        switch pathStatus {
        case .satisfied:
            .connected
        case .unsatisfied, .requiresConnection:
            .disconnected
        @unknown default:
            .checking
        }
    }

    /// Evaluates reachability using SAP ConnectivityUtils, specific SAP host flags, and system flags.
    nonisolated static func evaluateReachability() -> Bool {
        if ConnectivityUtils.isConnected() {
            return true
        }
        if let host = sapHost, checkHostReachability(host: host) {
            return true
        }
        return checkSystemReachability()
    }

    /// Queries reachability specifically for a designated host (e.g. SAP backend host).
    nonisolated static func checkHostReachability(host: String) -> Bool {
        guard let reachability = SCNetworkReachabilityCreateWithName(nil, host) else {
            return false
        }
        var flags: SCNetworkReachabilityFlags = []
        guard SCNetworkReachabilityGetFlags(reachability, &flags) else {
            return false
        }
        let isReachable = flags.contains(.reachable)
        let connectionRequired = flags.contains(.connectionRequired)
        let canConnectAutomatically = flags.contains(.connectionOnDemand) || flags.contains(.connectionOnTraffic)
        let canConnectWithoutUserInteraction = canConnectAutomatically && !flags.contains(.interventionRequired)

        return isReachable && (!connectionRequired || canConnectWithoutUserInteraction)
    }

    /// Reads system-level reachability flags to properly evaluate on-demand / on-traffic Wi-Fi connections.
    nonisolated static func checkSystemReachability() -> Bool {
        var zeroAddress = sockaddr_in()
        zeroAddress.sin_len = UInt8(MemoryLayout<sockaddr_in>.size)
        zeroAddress.sin_family = sa_family_t(AF_INET)

        guard let reachability = withUnsafePointer(to: &zeroAddress, {
            $0.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                SCNetworkReachabilityCreateWithAddress(nil, $0)
            }
        }) else {
            return false
        }

        var flags: SCNetworkReachabilityFlags = []
        guard SCNetworkReachabilityGetFlags(reachability, &flags) else {
            return false
        }

        let isReachable = flags.contains(.reachable)
        let connectionRequired = flags.contains(.connectionRequired)
        let canConnectAutomatically = flags.contains(.connectionOnDemand) || flags.contains(.connectionOnTraffic)
        let canConnectWithoutUserInteraction = canConnectAutomatically && !flags.contains(.interventionRequired)

        return isReachable && (!connectionRequired || canConnectWithoutUserInteraction)
    }

    /// Probes the network with reachability checks and an active lightweight HTTP request.
    /// The outbound HTTP request forces iOS kernel to bind interface en0 and activate routes.
    nonisolated static func probeNetwork() async -> Bool {
        if evaluateReachability() {
            return true
        }

        let targetURL: URL = {
            if let host = sapHost, let url = URL(string: "https://\(host)") {
                return url
            }
            return URL(string: "https://captive.apple.com/hotspot-detect.html")!
        }()

        var request = URLRequest(url: targetURL)
        request.httpMethod = "HEAD"
        request.timeoutInterval = 2.0
        request.cachePolicy = .reloadIgnoringLocalAndRemoteCacheData

        let config = URLSessionConfiguration.ephemeral
        config.timeoutIntervalForRequest = 2.0
        config.timeoutIntervalForResource = 2.0
        config.waitsForConnectivity = false
        let session = URLSession(configuration: config)

        do {
            let (_, response) = try await session.data(for: request)
            if let http = response as? HTTPURLResponse {
                return http.statusCode > 0
            }
            return true
        } catch {
            // Outbound traffic kick-starts the iOS network interface.
            // Check reachability flags immediately after the attempt:
            if ConnectivityUtils.isConnected() || checkSystemReachability() {
                return true
            }
            if let host = sapHost, checkHostReachability(host: host) {
                return true
            }
            return false
        }
    }
}

/// Helper bridge conforming to SAPFoundation.ConnectivityObserver.
/// This decouples nonisolated SAPFoundation callbacks from @MainActor SwiftUI observation,
/// preventing retain cycles and threading deadlocks.
private final class SAPConnectivityObserverBridge: ConnectivityObserver, @unchecked Sendable {
    private weak var owner: NetworkReachabilityMonitor?

    init(owner: NetworkReachabilityMonitor) {
        self.owner = owner
    }

    func connectionEstablished() {
        if Thread.isMainThread {
            MainActor.assumeIsolated {
                owner?.handleConnectionEstablished()
            }
        } else {
            Task { @MainActor [weak owner] in
                owner?.handleConnectionEstablished()
            }
        }
    }

    func connectionChanged(
        _ previousReachabilityType: ReachabilityType,
        reachabilityType: ReachabilityType
    ) {
        if Thread.isMainThread {
            MainActor.assumeIsolated {
                owner?.handleConnectionChanged(
                    previous: previousReachabilityType,
                    current: reachabilityType
                )
            }
        } else {
            Task { @MainActor [weak owner] in
                owner?.handleConnectionChanged(
                    previous: previousReachabilityType,
                    current: reachabilityType
                )
            }
        }
    }

    func connectionLost() {
        if Thread.isMainThread {
            MainActor.assumeIsolated {
                owner?.handleConnectionLost()
            }
        } else {
            Task { @MainActor [weak owner] in
                owner?.handleConnectionLost()
            }
        }
    }
}
