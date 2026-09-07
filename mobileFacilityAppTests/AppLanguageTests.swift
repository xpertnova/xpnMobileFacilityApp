import XCTest
@testable import mobileFacilityApp

final class AppLanguageTests: XCTestCase {
    func testSupportedLanguagesMapToExpectedLocales() {
        XCTAssertEqual(AppLanguage.english.rawValue, "en")
        XCTAssertEqual(AppLanguage.english.locale.language.languageCode?.identifier, "en")
        XCTAssertEqual(AppLanguage.german.rawValue, "de")
        XCTAssertEqual(AppLanguage.german.locale.language.languageCode?.identifier, "de")
    }

    func testStoredLanguageTakesPrecedenceOverSystemLanguage() {
        XCTAssertEqual(
            AppLanguage.resolved(from: "en", preferredLanguages: ["de-DE"]),
            .english
        )
        XCTAssertEqual(
            AppLanguage.resolved(from: "de", preferredLanguages: ["en-US"]),
            .german
        )
    }

    func testGermanSystemLanguageIsTheDefault() {
        XCTAssertEqual(
            AppLanguage.resolved(from: nil, preferredLanguages: ["de-DE"]),
            .german
        )
    }

    func testUnsupportedOrInvalidLanguageFallsBackToEnglish() {
        XCTAssertEqual(
            AppLanguage.resolved(from: nil, preferredLanguages: ["uk-UA"]),
            .english
        )
        XCTAssertEqual(
            AppLanguage.resolved(from: "invalid", preferredLanguages: ["en-GB"]),
            .english
        )
    }
}
