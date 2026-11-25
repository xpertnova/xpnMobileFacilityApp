import Foundation

/// A `FROM_T0212` row: the technical object an RFID tag is attached to.
struct RFIDTagAssignment: Equatable, Sendable {
    let tag: String
    let functionalLocationID: String
    /// The raw `EQUNR`. Cordova's `getMeldungen4QROverview` builds
    /// `EQUNR LIKE '%<EQUNR>'`, so an empty value matches every notification
    /// of the location and `%` only those without equipment.
    let equipmentID: String
    let controlKey: String
}

/// The object a scanned tag belongs to and its open maintenance notifications.
struct RFIDTagResolution: Equatable, Sendable {
    let assignment: RFIDTagAssignment
    /// The tag was found only by its first 13 characters, the format of tags
    /// written before the DuraScan readers (`rfidTable.js`).
    let matchedLegacyTagPrefix: Bool
    let matches: [SAPNotificationSummary]
}

protocol RFIDTagNotificationResolving: Sendable {
    /// `nil` when no `FROM_T0212` row carries the tag.
    func resolveRFIDTag(_ tag: String, for localWorkerID: String) async throws -> RFIDTagResolution?
}

/// The RFID lookup of Cordova's `Navigate.controller.js` (`onRfidPress`) and
/// `edata/luw/rfidTable.js`, shared by the SQLite and in-memory caches.
enum RFIDTagLookup {
    static let legacyTagPrefixLength = 13

    /// The DuraScan reader pads its payload with NUL characters; Cordova
    /// removed them before the lookup.
    static func normalizedTag(_ rawValue: String) -> String {
        rawValue
            .replacingOccurrences(of: "\0", with: "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// Cordova takes the last row for the full tag and, failing that, the
    /// first row stored under the tag's first 13 characters.
    ///
    /// Cordova also rewrote that older row to the full tag and queued it for
    /// SAP (`TO_T0212`). That write is not part of this lookup.
    static func assignment(
        for tag: String,
        in assignments: [RFIDTagAssignment]
    ) -> (assignment: RFIDTagAssignment, matchedLegacyTagPrefix: Bool)? {
        guard !tag.isEmpty else { return nil }
        if let exact = assignments.last(where: { $0.tag == tag }) {
            return (exact, false)
        }
        let prefix = String(tag.prefix(legacyTagPrefixLength))
        guard prefix != tag, let legacy = assignments.first(where: { $0.tag == prefix }) else {
            return nil
        }
        return (legacy, true)
    }

    static func notifications(
        _ notifications: [SAPNotificationSummary],
        matching assignment: RFIDTagAssignment
    ) -> [SAPNotificationSummary] {
        let equipmentID = assignment.equipmentID
        let controlKey = assignment.controlKey
        let matches = notifications.filter { notification in
            guard notification.functionalLocationID == assignment.functionalLocationID else { return false }
            if equipmentID == "%" {
                guard notification.equipmentID.isEmpty else { return false }
            } else if !equipmentID.isEmpty {
                guard notification.equipmentID.hasSuffix(equipmentID) else { return false }
            }
            return controlKey.isEmpty || notification.legacyControlKey == controlKey
        }
        var unique: [String: SAPNotificationSummary] = [:]
        for match in matches where unique[match.id] == nil {
            unique[match.id] = match
        }
        return unique.values.sorted { ($0.startDate, $0.id) < ($1.startDate, $1.id) }
    }

    static func resolve(
        _ tag: String,
        assignments: [RFIDTagAssignment],
        notifications: [SAPNotificationSummary]
    ) -> RFIDTagResolution? {
        guard let found = assignment(for: tag, in: assignments) else { return nil }
        return RFIDTagResolution(
            assignment: found.assignment,
            matchedLegacyTagPrefix: found.matchedLegacyTagPrefix,
            matches: Self.notifications(notifications, matching: found.assignment)
        )
    }
}
