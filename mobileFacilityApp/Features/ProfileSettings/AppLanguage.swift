import Foundation

enum AppLanguage: String, CaseIterable, Identifiable {
    case english = "en"
    case german = "de"

    static let storageKey = "mobileFacilityApp.settings.language"

    /// The language picked in the profile settings, or the German default.
    static var current: AppLanguage {
        resolved(from: UserDefaults.standard.string(forKey: storageKey))
    }

    var id: String { rawValue }

    var locale: Locale {
        Locale(identifier: rawValue)
    }

    /// The app's `<language>.lproj` bundle. `String(localized:)` against
    /// `Bundle.main` follows the device language, and its `locale:` argument
    /// only affects formatting, so code-built strings read from this bundle.
    var bundle: Bundle {
        Bundle.main.path(forResource: rawValue, ofType: "lproj").flatMap(Bundle.init(path:)) ?? .main
    }

    var titleKey: String {
        switch self {
        case .english: "language.english"
        case .german: "language.german"
        }
    }

    /// German is the product default, independent of the device language;
    /// English applies only once the user picks it in the profile settings.
    static func resolved(from storedValue: String?) -> AppLanguage {
        storedValue.flatMap(AppLanguage.init(rawValue:)) ?? .german
    }
}

extension Bundle {
    /// Pass as `bundle:` to every `String(localized:)`, so strings built in
    /// code use the in-app language like SwiftUI `Text` (which follows the
    /// `\.locale` environment set in `MobileFacilityApp`).
    static var appLanguage: Bundle {
        AppLanguage.current.bundle
    }
}
