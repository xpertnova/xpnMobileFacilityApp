import Foundation

public enum DashboardGreeting: String, CaseIterable, Equatable, Sendable {
    case morning
    case afternoon
    case evening

    public static func greeting(for date: Date = .now, calendar: Calendar = .current) -> DashboardGreeting {
        let hour = calendar.component(.hour, from: date)
        switch hour {
        case 5..<12:
            return .morning
        case 12..<18:
            return .afternoon
        default:
            return .evening
        }
    }

    public var localizationKey: String {
        switch self {
        case .morning:
            return "dashboard.greeting.morning"
        case .afternoon:
            return "dashboard.greeting.afternoon"
        case .evening:
            return "dashboard.greeting.evening"
        }
    }

    public func localizedTemplate(bundle: Bundle? = nil) -> String {
        String(localized: String.LocalizationValue(localizationKey), bundle: bundle ?? .appLanguage)
    }

    public func formatted(workerName: String, bundle: Bundle? = nil) -> String {
        let template = localizedTemplate(bundle: bundle)
        return String(format: template, workerName)
    }
}
