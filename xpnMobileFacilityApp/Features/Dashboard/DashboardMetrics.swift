import Foundation

/// The four counters on the dashboard. `nil` means "not known yet": the cards
/// show a placeholder for it, never a zero, because a technician reads a zero
/// as "no work".
struct DashboardMetrics: Codable, Equatable, Sendable {
    var notifications: Int?
    var defects: Int?
    var drafts: Int?
    var technicalPlaces: Int?

    static let unknown = DashboardMetrics()

    /// Each counter from `self` where it is known, otherwise from `fallback`.
    func filled(from fallback: DashboardMetrics) -> DashboardMetrics {
        DashboardMetrics(
            notifications: notifications ?? fallback.notifications,
            defects: defects ?? fallback.defects,
            drafts: drafts ?? fallback.drafts,
            technicalPlaces: technicalPlaces ?? fallback.technicalPlaces
        )
    }
}

/// The last counters a production worker saw, so the next launch can show
/// them on its first frame instead of waiting for the SAP cache.
///
/// Every counter is derived from the local SAP cache and the offline work
/// queue, and both only change through this app — a sync or a saved draft
/// updates the counters, which updates this snapshot. The saved value
/// therefore normally equals the one the launch is about to compute; it is
/// replaced as soon as that arrives. Demo mode keeps nothing here: its data is
/// in memory and never has to wait.
enum DashboardMetricsSnapshot {
    private static let keyPrefix = "dashboard-metrics"

    static func load(workerID: String) -> DashboardMetrics {
        guard
            let data = UserDefaults.standard.data(forKey: key(workerID: workerID)),
            let metrics = try? JSONDecoder().decode(DashboardMetrics.self, from: data)
        else {
            return .unknown
        }
        return metrics
    }

    static func save(_ metrics: DashboardMetrics, workerID: String) {
        guard let data = try? JSONEncoder().encode(metrics) else { return }
        UserDefaults.standard.set(data, forKey: key(workerID: workerID))
    }

    static func reset(workerID: String) {
        UserDefaults.standard.removeObject(forKey: key(workerID: workerID))
    }

    private static func key(workerID: String) -> String {
        let encodedWorkerID = Data(workerID.utf8).base64EncodedString()
        return "\(keyPrefix).production.\(encodedWorkerID)"
    }
}
