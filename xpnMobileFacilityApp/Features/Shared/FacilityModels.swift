import Foundation

enum AppDestination: String, CaseIterable, Identifiable {
    case overview
    case scan
    case notifications
    case manualCapture
    case defects
    case technicalPlaces
    case forms
    case drafts
    case profileSettings

    var id: String { rawValue }

    var titleKey: String {
        switch self {
        case .overview: return "navigation.overview"
        case .scan: return "navigation.scan"
        case .notifications: return "navigation.notifications"
        case .manualCapture: return "navigation.manualCapture"
        case .defects: return "navigation.defects"
        case .technicalPlaces: return "navigation.technicalPlaces"
        case .forms: return "navigation.forms"
        case .drafts: return "navigation.drafts"
        case .profileSettings: return "profile.settings.title"
        }
    }

    var symbol: String {
        switch self {
        case .overview: return "house"
        case .scan: return "viewfinder"
        case .notifications: return "clipboard"
        case .manualCapture: return "pencil.line"
        case .defects: return "exclamationmark.triangle"
        case .technicalPlaces: return "square.3.layers.3d"
        case .forms: return "doc"
        case .drafts: return "arrow.down.to.line.compact"
        case .profileSettings: return "person.crop.circle"
        }
    }
}

enum WorkStatus: String, CaseIterable, Identifiable {
    case open
    case draft
    case pending
    case attention
    case complete
    case closedLocally

    var id: String { rawValue }

    var titleKey: String {
        switch self {
        case .open: return "status.open"
        case .draft: return "status.draft"
        case .pending: return "status.pending"
        case .attention: return "status.attention"
        case .complete: return "status.complete"
        case .closedLocally: return "status.closedLocally"
        }
    }
}

struct MaintenanceNotification: Identifiable, Hashable {
    let id: String
    let title: String
    let location: String
    let dueDate: String
    let equipment: String
    let sapStatus: String?
    var status: WorkStatus
    var completedChecks: Int
    let totalChecks: Int
    /// Local review state is not a SAP status. It stays on-device until a
    /// confirmed SAP upload path exists.
    var isTemporarilySaved = false
    var isClosedLocally = false
    var hasLocalDefect = false
    var structuralFilterMetadata: NotificationStructuralFilterMetadata?

    /// The inspection form behind this notification, resolved from the SAP
    /// control key (`STEUS` / `FORMNR`) carried in `structuralFilterMetadata`.
    var formType: NotificationFormType? {
        NotificationFormType(formCode: structuralFilterMetadata?.formCode ?? "")
    }

    /// Chip shown on the notification row. It names the inspection form the
    /// row opens, which is the one classification SAP delivers with the
    /// notification itself; an unknown control key keeps its raw code instead
    /// of being mapped to a guessed category.
    var categoryBadge: NotificationCategoryBadge? {
        let code = (structuralFilterMetadata?.formCode ?? "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .uppercased()
        guard !code.isEmpty else { return nil }
        return NotificationCategoryBadge(
            titleKey: formType?.titleKey,
            code: code,
            style: formType?.badgeStyle ?? .neutral
        )
    }
}

/// Row chip for a maintenance notification: the localized form name when the
/// app knows the control key, the bare SAP code otherwise.
struct NotificationCategoryBadge: Hashable {
    /// String Catalog key of the named form, `nil` for an unknown control key.
    let titleKey: String?
    /// The SAP control key itself (`TFM1` … `TFM9`, or a customer-specific one).
    let code: String
    let style: FacilityTemplateBadgeStyle
}

/// The inspection forms an MTFM notification can carry, keyed by the SAP
/// control key in `STEUS` / `FORMNR`.
///
/// Codes and workflows are the documented ones (`docs/NOTIFICATION_TYPES_AND_TP_CREATION.md`,
/// traced from the legacy controllers). Each title reuses the string of the
/// screen that code opens, so the chip and the screen behind it read the same.
/// `TFM9` and customer-specific keys have no screen here yet and keep their
/// raw code.
enum NotificationFormType: String, CaseIterable {
    case maintenancePlan = "TFM1"
    case elevator = "TFM2"
    case roundInspection = "TFM3"
    case fixedLadder = "TFM4"
    case mobileLadder = "TFM5"
    case holdOpenSystem = "TFM6"
    case subdistribution = "TFM7"
    case roofSystem = "TFM8"

    init?(formCode: String) {
        self.init(rawValue: formCode.trimmingCharacters(in: .whitespacesAndNewlines).uppercased())
    }

    var titleKey: String {
        switch self {
        case .maintenancePlan: "notifications.structuralFilter.form.tfm1"
        case .elevator: "elevator.inspection.title"
        case .roundInspection: "notifications.structuralFilter.form.tfm3"
        case .fixedLadder: "fixedLadder.inspection.title"
        case .mobileLadder: "mobileLadder.title"
        case .holdOpenSystem: "holdOpenSystem.inspection.title"
        case .subdistribution: "subdistribution.title"
        case .roofSystem: "roofSystem.inspection.title"
        }
    }

    var badgeStyle: FacilityTemplateBadgeStyle {
        switch self {
        case .maintenancePlan: .formMaintenancePlan
        case .elevator: .formElevator
        case .roundInspection: .formRoundInspection
        case .fixedLadder: .formFixedLadder
        case .mobileLadder: .formMobileLadder
        case .holdOpenSystem: .formHoldOpenSystem
        case .subdistribution: .formSubdistribution
        case .roofSystem: .formRoofSystem
        }
    }
}

struct Defect: Identifiable, Hashable {
    let id: String
    let title: String
    let location: String
    let reportedAt: String
    let severity: WorkStatus
    let description: String
}

struct DraftWork: Identifiable, Hashable {
    let id: String
    let title: String
    let detail: String
    let savedAt: String
    let status: WorkStatus
}

struct TechnicalPlace: Identifiable, Hashable {
    let id: String
    let code: String
    let title: String
    let detail: String
    let equipmentCount: Int
}

struct FacilityForm: Identifiable, Hashable {
    let id: String
    let titleKey: String
    let subtitleKey: String
    let coverageKeys: [String]
    let symbol: String
    let tint: String
}
