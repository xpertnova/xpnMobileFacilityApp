import XCTest
@testable import mobileFacilityApp

/// Local sign-in on the shared iPad. Each test gets its own defaults suite, so
/// the real accounts in `UserDefaults.standard` are never touched.
final class LocalCredentialStoreTests: XCTestCase {
    private let storageKey = "mobileFacility.localCredentials"
    private var suiteName: String!
    private var defaults: UserDefaults!

    override func setUp() {
        super.setUp()
        suiteName = "LocalCredentialStoreTests.\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: suiteName)
    }

    override func tearDown() {
        defaults.removePersistentDomain(forName: suiteName)
        defaults = nil
        suiteName = nil
        super.tearDown()
    }

    func testCreatedAccountSignsInWithTheSamePassword() throws {
        let created = try LocalCredentialStore.createAccount(username: "S50828", password: "secret", defaults: defaults)
        let signedIn = try LocalCredentialStore.authenticate(username: "S50828", password: "secret", defaults: defaults)

        XCTAssertEqual(signedIn, created)
    }

    func testWrongPasswordIsRejected() throws {
        _ = try LocalCredentialStore.createAccount(username: "S50828", password: "secret", defaults: defaults)

        XCTAssertThrowsError(
            try LocalCredentialStore.authenticate(username: "S50828", password: "Secret", defaults: defaults)
        ) { error in
            XCTAssertEqual(error as? LocalCredentialStoreError, .invalidCredentials)
        }
    }

    func testUnknownUserIsRejected() {
        XCTAssertThrowsError(
            try LocalCredentialStore.authenticate(username: "nobody", password: "secret", defaults: defaults)
        ) { error in
            XCTAssertEqual(error as? LocalCredentialStoreError, .invalidCredentials)
        }
    }

    func testBlankUsernameCannotCreateAnAccount() {
        XCTAssertThrowsError(
            try LocalCredentialStore.createAccount(username: "   ", password: "secret", defaults: defaults)
        ) { error in
            XCTAssertEqual(error as? LocalCredentialStoreError, .invalidCredentials)
        }
    }

    func testUsernameIsMatchedWithoutCaseAndSurroundingSpaces() throws {
        _ = try LocalCredentialStore.createAccount(username: "  Jürgen ", password: "secret", defaults: defaults)

        XCTAssertThrowsError(
            try LocalCredentialStore.createAccount(username: "JURGEN", password: "other", defaults: defaults)
        ) { error in
            XCTAssertEqual(error as? LocalCredentialStoreError, .usernameAlreadyExists)
        }
        XCTAssertNoThrow(try LocalCredentialStore.authenticate(username: "jurgen", password: "secret", defaults: defaults))
    }

    func testDisplayNameKeepsWhatWasTypedWhileTheWorkerIDIsNormalized() throws {
        let user = try LocalCredentialStore.createAccount(username: "  Jürgen ", password: "secret", defaults: defaults)

        XCTAssertEqual(user.displayName, "Jürgen")
        XCTAssertEqual(user.workerID, "jurgen")
    }

    func testPasswordIsNotStoredInPlainText() throws {
        _ = try LocalCredentialStore.createAccount(username: "S50828", password: "plain-secret", defaults: defaults)

        let stored = try XCTUnwrap(defaults.data(forKey: storageKey))
        XCTAssertNil(String(decoding: stored, as: UTF8.self).range(of: "plain-secret"))
    }

    func testSamePasswordIsHashedWithADifferentSaltPerAccount() throws {
        _ = try LocalCredentialStore.createAccount(username: "first", password: "secret", defaults: defaults)
        _ = try LocalCredentialStore.createAccount(username: "second", password: "secret", defaults: defaults)

        let data = try XCTUnwrap(defaults.data(forKey: storageKey))
        let accounts = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: [String: String]])
        XCTAssertNotEqual(accounts["first"]?["passwordHash"], accounts["second"]?["passwordHash"])
    }

    func testCorruptStorageIsReportedInsteadOfTreatedAsNoAccounts() {
        defaults.set(Data("not json".utf8), forKey: storageKey)

        XCTAssertThrowsError(
            try LocalCredentialStore.createAccount(username: "S50828", password: "secret", defaults: defaults)
        ) { error in
            XCTAssertEqual(error as? LocalCredentialStoreError, .storageUnavailable)
        }
    }
}
