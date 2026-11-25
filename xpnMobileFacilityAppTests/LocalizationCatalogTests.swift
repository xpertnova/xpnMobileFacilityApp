import Foundation
import XCTest
@testable import mobileFacilityApp

/// Every user-facing string needs German (the product default) and English.
/// A key without a translation shows up as the raw key, and a literal missing
/// from the catalog shows up in English even in the German app.
final class LocalizationCatalogTests: XCTestCase {
    private static let appSources = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent()
        .deletingLastPathComponent()
        .appendingPathComponent("mobileFacilityApp")
    private static let resources = appSources.appendingPathComponent("Resources")

    /// `feature.section.name`, optionally followed by format arguments.
    private static let identifierKey = try! NSRegularExpression(
        pattern: #"^[A-Za-z][A-Za-z0-9_]*(\.[A-Za-z0-9_]+)+( .*)?$"#
    )

    private var storedLanguage: String?

    override func setUp() {
        super.setUp()
        storedLanguage = UserDefaults.standard.string(forKey: AppLanguage.storageKey)
    }

    override func tearDown() {
        UserDefaults.standard.set(storedLanguage, forKey: AppLanguage.storageKey)
        super.tearDown()
    }

    // MARK: - Catalog

    func testEveryIdentifierKeyHasGermanAndEnglish() throws {
        let catalogs = try FileManager.default
            .contentsOfDirectory(at: Self.resources, includingPropertiesForKeys: nil)
            .filter { $0.pathExtension == "xcstrings" }
        XCTAssertFalse(catalogs.isEmpty)

        for catalogURL in catalogs {
            for (key, entry) in try Self.entries(in: catalogURL) where Self.isIdentifierKey(key) {
                guard entry["shouldTranslate"] as? Bool != false else { continue }
                for language in ["de", "en"] {
                    let value = Self.translation(of: entry, in: language)
                    XCTAssertNotNil(value, "\(catalogURL.lastPathComponent): \(key) has no \(language) text")
                    XCTAssertNotEqual(value, key, "\(catalogURL.lastPathComponent): \(key) shows its key in \(language)")
                }
            }
        }
    }

    /// `String(localized:)` with a literal, and SwiftUI views given an
    /// identifier key, must find a German text in `Localizable.xcstrings`.
    func testLocalizedLiteralsInTheCodeAreTranslated() throws {
        let catalog = try Self.entries(in: Self.resources.appendingPathComponent("Localizable.xcstrings"))
        let localizedString = try NSRegularExpression(pattern: #"String\(\s*localized:\s*"((?:[^"\\]|\\.)*)""#)
        let viewKey = try NSRegularExpression(
            pattern: #"\b(?:Text|Button|Label|Toggle|Section|LocalizedStringKey|navigationTitle)\(\s*"((?:[^"\\]|\\.)*)""#
        )

        var missing: [String] = []
        for fileURL in try Self.swiftSources() {
            let source = try String(contentsOf: fileURL, encoding: .utf8)
            let file = fileURL.lastPathComponent
            for key in Self.captures(of: localizedString, in: source) where !key.contains(#"\("#) {
                if !Self.hasGermanText(catalog[key]) { missing.append("\(file): \(key)") }
            }
            for key in Self.captures(of: viewKey, in: source)
            where !key.contains(#"\("#) && Self.isIdentifierKey(key) {
                if !Self.hasGermanText(catalog[key]) { missing.append("\(file): \(key)") }
            }
        }

        XCTAssertEqual(missing, [], "literals without a German text in Localizable.xcstrings")
    }

    // MARK: - SAP refresh errors

    /// The password dialog shows these to the technician, so each must follow
    /// the in-app language rather than fall back to its key or to English.
    func testEverySAPRefreshErrorFollowsTheAppLanguage() {
        let errors: [SAPReadError] = [
            .configurationUnavailable, .authenticatedConnectionUnavailable, .passwordRequired,
            .invalidCredentials, .initialPasswordChangeRequired, .tokenInvalidOrExpired,
            .preparationTimedOut, .malformedPayload, .networkUnavailable, .requestTimedOut,
            .httpStatus(500), .serviceUnavailable
        ]

        UserDefaults.standard.set(AppLanguage.german.rawValue, forKey: AppLanguage.storageKey)
        let german = errors.map { sapRefreshErrorMessage($0) } + [sapRefreshErrorMessage(nil)]
        UserDefaults.standard.set(AppLanguage.english.rawValue, forKey: AppLanguage.storageKey)
        let english = errors.map { sapRefreshErrorMessage($0) } + [sapRefreshErrorMessage(nil)]

        for (index, (germanText, englishText)) in zip(german, english).enumerated() {
            let error = index < errors.count ? "\(errors[index])" : "nil"
            XCTAssertNotEqual(germanText, englishText, "\(error) is not translated")
            XCTAssertFalse(germanText.hasPrefix("sap.refresh."), "\(error) shows its key")
            XCTAssertFalse(englishText.hasPrefix("sap.refresh."), "\(error) shows its key")
        }
    }

    func testSAPBackendMessageIsShownAsSAPSentIt() {
        XCTAssertEqual(sapRefreshErrorMessage(.backendMessage("Benutzer gesperrt")), "Benutzer gesperrt")
    }

    // MARK: - Helpers

    private static func entries(in catalogURL: URL) throws -> [String: [String: Any]] {
        let data = try Data(contentsOf: catalogURL)
        let catalog = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        return try XCTUnwrap(catalog["strings"] as? [String: [String: Any]])
    }

    /// The `stringUnit` value, or a marker for plural/device variations.
    private static func translation(of entry: [String: Any], in language: String) -> String? {
        guard let localization = (entry["localizations"] as? [String: Any])?[language] as? [String: Any] else {
            return nil
        }
        if let unit = localization["stringUnit"] as? [String: Any],
           let value = unit["value"] as? String, !value.isEmpty {
            return value
        }
        return localization["variations"] != nil ? "<variations>" : nil
    }

    private static func hasGermanText(_ entry: [String: Any]?) -> Bool {
        guard let entry else { return false }
        return entry["shouldTranslate"] as? Bool == false || translation(of: entry, in: "de") != nil
    }

    private static func isIdentifierKey(_ key: String) -> Bool {
        identifierKey.firstMatch(in: key, range: NSRange(key.startIndex..., in: key)) != nil
    }

    private static func captures(of expression: NSRegularExpression, in source: String) -> [String] {
        expression.matches(in: source, range: NSRange(source.startIndex..., in: source)).compactMap {
            Range($0.range(at: 1), in: source).map { String(source[$0]) }
        }
    }

    private static func swiftSources() throws -> [URL] {
        let enumerator = try XCTUnwrap(FileManager.default.enumerator(at: appSources, includingPropertiesForKeys: nil))
        return enumerator.compactMap { $0 as? URL }.filter { $0.pathExtension == "swift" }
    }
}
