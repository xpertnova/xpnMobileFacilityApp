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
}
