import Foundation

extension LocalPhotoScope {
    /// The title in the current app language.
    var localizedTitle: String {
        Self.displayText(key: displayTitleKey, storedText: displayTitle)
    }

    /// The subtitle in the current app language.
    var localizedSubtitle: String {
        Self.displayText(key: displaySubtitleKey, storedText: displaySubtitle)
    }

    private static func displayText(key: String?, storedText: String) -> String {
        guard let key = key ?? legacyKeysByText[storedText] else { return storedText }
        return String(localized: String.LocalizationValue(key), bundle: .appLanguage)
    }

    /// Records saved before the catalog keys existed hold the translated text
    /// of one of these keys, in whichever language was picked at the time.
    /// Mapping that text back to its key lets those records follow the
    /// current language as well.
    private static let legacyKeysByText: [String: String] = {
        let keys = [
            "photos.workspace.title",
            "documents.workspace.title",
            "mobileLadder.photos.title",
            "subdistribution.photos.title",
            "manual.defect.form.title",
            "manual.meter.form.title",
            "mobileLadder.field.disassembled",
            "subdistribution.outOfOperation"
        ]
        var keysByText: [String: String] = [:]
        for language in AppLanguage.allCases {
            for key in keys {
                keysByText[String(localized: String.LocalizationValue(key), bundle: language.bundle)] = key
            }
        }
        return keysByText
    }()
}
