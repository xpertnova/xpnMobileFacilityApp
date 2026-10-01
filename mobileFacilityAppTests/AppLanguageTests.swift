import Observation
import XCTest
@testable import mobileFacilityApp

final class AppLanguageTests: XCTestCase {
    func testSupportedLanguagesMapToExpectedLocales() {
        XCTAssertEqual(AppLanguage.english.rawValue, "en")
        XCTAssertEqual(AppLanguage.english.locale.language.languageCode?.identifier, "en")
        XCTAssertEqual(AppLanguage.german.rawValue, "de")
        XCTAssertEqual(AppLanguage.german.locale.language.languageCode?.identifier, "de")
    }

    func testStoredLanguageIsUsed() {
        XCTAssertEqual(AppLanguage.resolved(from: "en"), .english)
        XCTAssertEqual(AppLanguage.resolved(from: "de"), .german)
    }

    func testGermanIsTheDefault() {
        XCTAssertEqual(AppLanguage.resolved(from: nil), .german)
    }

    func testInvalidStoredLanguageFallsBackToGerman() {
        XCTAssertEqual(AppLanguage.resolved(from: "invalid"), .german)
    }

    /// Views that only show strings built with `bundle: .appLanguage` are
    /// redrawn through this, not through `\.locale`.
    func testLanguageChangeNotifiesReadersOfCurrentLanguage() {
        var didNotify = false
        withObservationTracking {
            _ = AppLanguage.current
        } onChange: {
            didNotify = true
        }

        AppLanguageObservation.shared.languageDidChange()

        XCTAssertTrue(didNotify)
    }
}
