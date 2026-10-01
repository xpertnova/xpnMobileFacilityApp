import XCTest
@testable import mobileFacilityApp

final class LocalPhotoScopeDisplayTextTests: XCTestCase {
    private var storedLanguage: String?

    override func setUp() {
        super.setUp()
        storedLanguage = UserDefaults.standard.string(forKey: AppLanguage.storageKey)
    }

    override func tearDown() {
        UserDefaults.standard.set(storedLanguage, forKey: AppLanguage.storageKey)
        super.tearDown()
    }

    func testCatalogKeysFollowTheCurrentLanguage() throws {
        let scope = LocalPhotoScope(
            workflow: .technicalObject,
            ownerID: "EQ-1",
            displayTitleKey: "documents.workspace.title",
            displaySubtitle: "Pump"
        )
        let saved = try JSONDecoder().decode(LocalPhotoScope.self, from: JSONEncoder().encode(scope))

        select(.german)
        XCTAssertEqual(saved.localizedTitle, "Dokumente")
        select(.english)
        XCTAssertEqual(saved.localizedTitle, "Documents")
        XCTAssertEqual(saved.localizedSubtitle, "Pump")
    }

    /// Collections saved before the keys existed hold translated text only.
    func testLegacyRecordFollowsTheCurrentLanguage() throws {
        let legacyJSON = Data("""
        {"workflow":"defect","ownerID":"new-defect","displayTitle":"Fotos","displaySubtitle":"Neue Störungsmeldung"}
        """.utf8)
        let saved = try JSONDecoder().decode(LocalPhotoScope.self, from: legacyJSON)

        XCTAssertNil(saved.displayTitleKey)
        select(.english)
        XCTAssertEqual(saved.localizedTitle, "Photos")
        XCTAssertEqual(saved.localizedSubtitle, "New defect report")
    }

    func testFreeTextIsShownAsSaved() {
        let scope = LocalPhotoScope(
            workflow: .mobileLadder,
            ownerID: "draft",
            rowID: "1",
            displayTitleKey: "mobileLadder.photos.title",
            displaySubtitle: "Sprossen"
        )

        select(.english)
        XCTAssertEqual(scope.localizedSubtitle, "Sprossen")
    }

    private func select(_ language: AppLanguage) {
        UserDefaults.standard.set(language.rawValue, forKey: AppLanguage.storageKey)
    }
}
