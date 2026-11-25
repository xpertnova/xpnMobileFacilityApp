import Foundation
import Observation
import os

enum AppLanguage: String, CaseIterable, Identifiable {
    case english = "en"
    case german = "de"

    static let storageKey = "mobileFacilityApp.settings.language"

    /// The language picked in the profile settings, or the German default.
    ///
    /// Read inside a SwiftUI `body`, this also subscribes the view to
    /// language changes, so strings built with `bundle: .appLanguage` are
    /// redrawn like `Text` keys are when `\.locale` changes.
    static var current: AppLanguage {
        AppLanguageObservation.shared.trackChanges()
        return resolved(from: UserDefaults.standard.string(forKey: storageKey))
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
    /// `\.locale` environment set in `xpnMobileFacilityApp`).
    static var appLanguage: Bundle {
        AppLanguage.current.bundle
    }
}

/// Lets SwiftUI track `AppLanguage.current`, which reads `UserDefaults` and so
/// is invisible to view updates on its own. A view that only shows strings
/// built in code would otherwise keep the old language until something else
/// redraws it.
final class AppLanguageObservation: Observable, Sendable {
    static let shared = AppLanguageObservation()

    private let registrar = ObservationRegistrar()
    private let revision = OSAllocatedUnfairLock(initialState: 0)

    private init() {}

    /// Registers the calling view (or other observation scope) for changes.
    func trackChanges() {
        registrar.access(self, keyPath: \.currentRevision)
    }

    /// Called once the stored language has changed, to redraw every view
    /// that read `AppLanguage.current` while building its body.
    func languageDidChange() {
        registrar.withMutation(of: self, keyPath: \.currentRevision) {
            revision.withLock { $0 += 1 }
        }
    }

    private var currentRevision: Int {
        revision.withLock { $0 }
    }
}
