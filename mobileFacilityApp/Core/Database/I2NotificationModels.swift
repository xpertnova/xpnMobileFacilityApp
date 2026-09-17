import Foundation

/// The category a technician assigns to a defective position before an I2
/// fault notification (`Störungsmeldung`) is created for it.
///
/// Traced from `BaseFormController.baseFormInit`, which hardcodes the list for
/// the `DefectPosItem` dialog. The code posts as `QMCOD` in code group
/// `ZPMI0001`; `n.a` ("I2 nicht anlegen") is the default and creates nothing.
/// There is no `004` in the legacy list.
enum I2NotificationCategory: String, CaseIterable, Codable, Identifiable, Sendable {
    case notCreated = "n.a"
    case caretaker = "001"
    case cleaning = "002"
    case technical = "003"
    case winterService = "005"
    case greenAreas = "006"

    var id: String { rawValue }
    var code: String { rawValue }

    var createsNotification: Bool { self != .notCreated }

    var titleKey: String {
        switch self {
        case .notCreated: "i2.category.notCreated"
        case .caretaker: "i2.category.caretaker"
        case .cleaning: "i2.category.cleaning"
        case .technical: "i2.category.technical"
        case .winterService: "i2.category.winterService"
        case .greenAreas: "i2.category.greenAreas"
        }
    }
}

/// One I2 notification the technician asked for while closing an I1 form.
///
/// It stays inside the parent form's offline draft, so the I1 and its I2s
/// share one status and reach SAP in the same upload. The rows themselves are
/// built at synchronization time by `SAPI2NotificationUploadBuilder`.
struct I2NotificationRequest: Codable, Equatable, Identifiable, Sendable {
    /// Temporary `QMNUM` (`NEU-` plus eight characters, as
    /// `nBpmUtil.randomId(8, "NEU")`). Kept stable so a retried upload
    /// replaces its own `TO_T0284` row instead of adding a second one.
    let id: String
    /// Checklist position the notification was created for.
    let positionID: String
    /// Position text. Posts as `QMTXT`, which is also what the existing-I2
    /// lookup matches against.
    let shortText: String
    let category: I2NotificationCategory
    /// The position comment, including the `HEADERTEXT` line for grouped
    /// positions, before the 300-character long-text cut.
    let note: String
    /// `ELEMENTNR` of the position note. Photos stored under it are copied to
    /// `TO_T0285` for the I2.
    let noteElementID: String
}

/// An I2 notification SAP delivered in `FROM_T0271`, shown read-only next to
/// the position it was created for.
///
/// The fields are the columns of the legacy `I2MeldungList` popover.
struct SAPI2NotificationSummary: Identifiable, Equatable, Sendable {
    /// `QMNUM`
    let id: String
    /// `QMTXT`
    let shortText: String
    /// `QMNAM`
    let reporter: String
    /// `STRMN`
    let startDate: String
    /// `STRUR`
    let startTime: String
    /// `REFNUM`, the I1 the fault was reported from.
    let referenceID: String
    /// `STTXT`
    let systemStatus: String
    /// The `TDLINE`s of the decoded `FELDWERT`, joined like
    /// `select.formatLongText(..., true)`.
    let longText: String

    init(
        id: String,
        shortText: String,
        reporter: String = "",
        startDate: String = "",
        startTime: String = "",
        referenceID: String = "",
        systemStatus: String = "",
        longText: String = ""
    ) {
        self.id = id
        self.shortText = shortText
        self.reporter = reporter
        self.startDate = startDate
        self.startTime = startTime
        self.referenceID = referenceID
        self.systemStatus = systemStatus
        self.longText = longText
    }
}

/// The technical object whose I2 notifications a form shows.
///
/// `select.getItemMeldung` reads `FROM_T0271 WHERE QMART = 'I2'` for the same
/// client and equipment, or for the same functional location when the I1 has
/// no equipment.
struct I2NotificationObjectReference: Equatable, Sendable {
    let client: String
    let equipmentID: String
    let functionalLocationID: String

    var isEmpty: Bool { equipmentID.isEmpty && functionalLocationID.isEmpty }
}

/// Narrow read of the downloaded I2 notifications.
protocol I2NotificationReading: Sendable {
    func loadI2Notifications(for object: I2NotificationObjectReference) async throws -> [SAPI2NotificationSummary]
}

/// Narrow read of the new-notification template `insertI2Meldung` starts
/// from: the `FROM_T0268` row with `LKEY = 'MELDUNG'` and `LPAR = 'MELDUNG'`.
protocol I2NotificationTemplateProviding: Sendable {
    /// The decoded template as JSON, or `nil` when the cache has none.
    func loadNewNotificationTemplateJSON() async throws -> String?
}

/// Faults already reported for the demo Wartungsplan, so the per-position
/// lookup can be tried without SAP. Demo only.
enum I2NotificationDemoData {
    static let notificationsByObjectID: [String: [SAPI2NotificationSummary]] = [
        "DE-SAF-11152-10": [
            SAPI2NotificationSummary(
                id: "DEMO-I2-0001",
                shortText: "Sind die Ansprechpartner noch korrekt?",
                reporter: "DEMO",
                startDate: "2026-06-02",
                startTime: "08:18:25",
                referenceID: "005140055904",
                systemStatus: "MMAB",
                longText: "*Alarmkontakt der Nachtschicht war nicht erreichbar.*Kontakt wurde im Alarmplan ersetzt."
            ),
            SAPI2NotificationSummary(
                id: "DEMO-I2-0002",
                shortText: "Sind die Ansprechpartner noch korrekt?",
                reporter: "DEMO",
                startDate: "2026-09-01",
                startTime: "17:52:41",
                referenceID: "005140055904",
                systemStatus: "MOFN",
                longText: "*Hausmeister hat gewechselt.*Neuer Ansprechpartner fehlt im Alarmplan."
            )
        ]
    ]
}
