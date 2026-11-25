import Foundation

enum NotificationStructuralFilterPreferences {
    private static let keyPrefix = "notification-structural-filter"

    static func load(workerID: String, isDemoMode: Bool) -> NotificationStructuralFilter {
        guard
            let data = UserDefaults.standard.data(forKey: key(workerID: workerID, isDemoMode: isDemoMode)),
            let filter = try? JSONDecoder().decode(NotificationStructuralFilter.self, from: data)
        else {
            return .empty
        }
        return filter
    }

    static func save(_ filter: NotificationStructuralFilter, workerID: String, isDemoMode: Bool) {
        let preferenceKey = key(workerID: workerID, isDemoMode: isDemoMode)
        guard filter.hasBusinessEntity else {
            UserDefaults.standard.removeObject(forKey: preferenceKey)
            return
        }
        guard let data = try? JSONEncoder().encode(filter) else { return }
        UserDefaults.standard.set(data, forKey: preferenceKey)
    }

    static func reset(workerID: String, isDemoMode: Bool) {
        UserDefaults.standard.removeObject(forKey: key(workerID: workerID, isDemoMode: isDemoMode))
    }

    private static func key(workerID: String, isDemoMode: Bool) -> String {
        let scope = isDemoMode ? "demo" : "production"
        let encodedWorkerID = Data(workerID.utf8).base64EncodedString()
        return "\(keyPrefix).\(scope).\(encodedWorkerID)"
    }
}
