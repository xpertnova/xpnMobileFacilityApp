import Foundation

enum AppLanguage: String, CaseIterable, Identifiable {
    case english = "en"
    case german = "de"

    static let storageKey = "mobileFacilityApp.settings.language"

    var id: String { rawValue }

    var locale: Locale {
        Locale(identifier: rawValue)
    }

    var titleKey: String {
        switch self {
        case .english: "language.english"
        case .german: "language.german"
        }
    }

    static func resolved(
        from storedValue: String?,
        preferredLanguages: [String] = Locale.preferredLanguages
    ) -> AppLanguage {
        if let storedValue, let language = AppLanguage(rawValue: storedValue) {
            return language
        }

        guard let preferredLanguage = preferredLanguages.first else {
            return .english
        }

        let languageCode = Locale(identifier: preferredLanguage).language.languageCode?.identifier
        return languageCode == AppLanguage.german.rawValue ? .german : .english
    }
}
