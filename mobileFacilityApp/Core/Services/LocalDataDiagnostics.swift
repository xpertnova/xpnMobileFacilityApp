import Foundation

/// Debug-only trace of what a production login reads from the device: which
/// local stores opened and what the first cache and local-work loads returned.
/// It exists to find why a second login can show an empty workspace although
/// the data is still in SQLite. Do not add payloads or full worker IDs here.
enum LocalDataDiagnostics {
    private static let prefix = "[Local Data Debug]"

    static func log(_ message: @autoclosure () -> String) {
        #if DEBUG
        print("\(prefix) \(message())")
        #endif
    }

    static func redacted(_ workerID: String) -> String {
        let trimmed = workerID.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.count > 2 else { return "***" }
        return "\(trimmed.prefix(2))***(\(trimmed.count))"
    }
}
