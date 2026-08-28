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
        case .forms: return "document"
        case .drafts: return "arrow.down.to.line.compact"
        }
    }
}

enum WorkStatus: String, CaseIterable, Identifiable {
    case open
    case draft
    case pending
    case attention
    case complete

    var id: String { rawValue }

    var titleKey: String {
        switch self {
        case .open: return "status.open"
        case .draft: return "status.draft"
        case .pending: return "status.pending"
        case .attention: return "status.attention"
        case .complete: return "status.complete"
        }
    }
}

struct MaintenanceNotification: Identifiable, Hashable {
    let id: String
    let title: String
    let location: String
    let dueDate: String
    let equipment: String
    var status: WorkStatus
    var completedChecks: Int
    let totalChecks: Int
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
