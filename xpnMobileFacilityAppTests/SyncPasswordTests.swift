import Foundation
import XCTest
@testable import mobileFacilityApp

/// The legacy synchronization password: the rules of `ChangePasswordDialog`,
/// the order in which `M0153003` flags are read, and keeping the token a
/// password change returns.
final class SyncPasswordTests: XCTestCase {
    // MARK: - Rules

    func testPasswordMeetingEveryRuleIsValid() {
        XCTAssertEqual(
            SyncPasswordRules.satisfiedRules(by: "Fassade7!", userName: "s50828"),
            Set(SyncPasswordRules.Rule.allCases)
        )
        XCTAssertEqual(
            SyncPasswordRules.validate(newPassword: "Fassade7!", repetition: "Fassade7!", userName: "s50828"),
            .valid
        )
    }

    func testEachMissingRuleIsReported() {
        let rules = { (password: String) in SyncPasswordRules.satisfiedRules(by: password, userName: "s50828") }
        XCTAssertFalse(rules("fassade7!").contains(.uppercaseLetter))
        XCTAssertFalse(rules("FASSADE7!").contains(.lowercaseLetter))
        XCTAssertFalse(rules("Fassadee!").contains(.digit))
        XCTAssertFalse(rules("Fass7!a").contains(.minimumLength))
        XCTAssertFalse(rules("Fassade77").contains(.specialCharacter))
    }

    func testUserNameIsRejectedInAnyCase() {
        XCTAssertFalse(
            SyncPasswordRules.satisfiedRules(by: "aS50828b!", userName: "s50828").contains(.excludesUserName)
        )
        XCTAssertTrue(
            SyncPasswordRules.satisfiedRules(by: "Fassade7!", userName: "").contains(.excludesUserName)
        )
    }

    func testHyphenCountsAsSpecialCharacterAsTheHintSays() {
        XCTAssertTrue(SyncPasswordRules.satisfiedRules(by: "Fassade7-", userName: "").contains(.specialCharacter))
        XCTAssertFalse(SyncPasswordRules.satisfiedRules(by: "Fassade7_", userName: "").contains(.specialCharacter))
    }

    func testOnlyASCIILettersCountAsTheLegacyCheckDoes() {
        let rules = SyncPasswordRules.satisfiedRules(by: "ÄÖÜ7!äöüß", userName: "")
        XCTAssertFalse(rules.contains(.uppercaseLetter))
        XCTAssertFalse(rules.contains(.lowercaseLetter))
    }

    func testSubmitChecksRunInTheLegacyOrder() {
        XCTAssertEqual(
            SyncPasswordRules.validate(newPassword: "Fass ade7!", repetition: "Other", userName: ""),
            .containsWhitespace
        )
        XCTAssertEqual(
            SyncPasswordRules.validate(newPassword: "weak", repetition: "Other", userName: ""),
            .rulesNotMet
        )
        XCTAssertEqual(
            SyncPasswordRules.validate(newPassword: "Fassade7!", repetition: "Fassade7?", userName: ""),
            .repetitionDiffers
        )
    }

    // MARK: - M0153003 flags

    func testInitialFlagIsReadEvenWithoutCheckPassword() throws {
        let authorization = try SAPLegacyDataExchangeCodec.authorization(
            from: Self.response(#"{"CHECKPW":"","PWINITIAL":"X"}"#)
        )
        XCTAssertTrue(authorization.requiresInitialPasswordChange)
        XCTAssertEqual(authorization.checkPasswordFlag, "")
        XCTAssertEqual(authorization.initialPasswordFlag, "X")
    }

    func testAcceptedInitialPasswordAsksForANewOne() throws {
        let authorization = try SAPLegacyDataExchangeCodec.authorization(
            from: Self.response(#"{"CHECKPW":"X","PWINITIAL":"X"}"#)
        )
        XCTAssertTrue(authorization.isAccepted)
        XCTAssertTrue(authorization.requiresInitialPasswordChange)
    }

    // MARK: - Store

    @MainActor
    func testChangedPasswordKeepsTheReturnedToken() async throws {
        let tokens = InMemorySAPSyncTokenStore()
        let service = FakePasswordService(result: .success("NEW-TOKEN"))
        let store = Self.store(service: service, tokens: tokens)

        let keptToken = try await store.changeInitialPassword(oldPassword: "Init1234", newPassword: "Fassade7!")

        XCTAssertTrue(keptToken)
        XCTAssertEqual(tokens.token(for: "account"), "NEW-TOKEN")
        XCTAssertTrue(store.hasValidSavedToken)
        let calls = await service.changes
        XCTAssertEqual(calls.first?.old, "Init1234")
        XCTAssertEqual(calls.first?.new, "Fassade7!")
    }

    @MainActor
    func testRejectedChangeKeepsNoToken() async {
        let tokens = InMemorySAPSyncTokenStore()
        let store = Self.store(service: FakePasswordService(result: .failure(.changeRejected)), tokens: tokens)

        do {
            try await store.changeInitialPassword(oldPassword: "Wrong", newPassword: "Fassade7!")
            XCTFail("A rejected change must throw")
        } catch {
            XCTAssertEqual(error as? SAPSyncPasswordError, .changeRejected)
        }
        XCTAssertNil(tokens.token(for: "account"))
    }

    @MainActor
    func testWithoutPasswordServiceNothingReachesSAP() async {
        let store = SAPDataStore(
            repository: InMemorySAPDataCacheRepository(),
            refreshService: nil,
            localWorkerID: "demo"
        )

        XCTAssertFalse(store.isPasswordServiceAvailable)
        do {
            try await store.changeInitialPassword(oldPassword: "Init1234", newPassword: "Fassade7!")
            XCTFail("The demo has no password service")
        } catch {
            XCTAssertNotNil(error as? SAPReadError)
        }
    }

    // MARK: - Helpers

    @MainActor
    private static func store(service: FakePasswordService, tokens: InMemorySAPSyncTokenStore) -> SAPDataStore {
        SAPDataStore(
            repository: InMemorySAPDataCacheRepository(),
            refreshService: nil,
            passwordService: service,
            tokenStore: tokens,
            localWorkerID: "s50828",
            synchronizationUserID: "s50828",
            tokenStoreAccountID: "account"
        )
    }

    private static func response(_ value: String) throws -> String {
        let envelope: [[String: String]] = [["KEY": "STRUCTURE", "PAR": "/EZO/MTFMS_PARAMETER", "VALUE": value]]
        return String(decoding: try JSONSerialization.data(withJSONObject: envelope), as: UTF8.self)
    }
}

private actor FakePasswordService: SAPSyncPasswordService {
    let result: Result<String?, SAPSyncPasswordError>
    private(set) var changes: [(old: String, new: String)] = []

    init(result: Result<String?, SAPSyncPasswordError>) {
        self.result = result
    }

    func changeInitialPassword(oldPassword: String, newPassword: String) async throws -> String? {
        changes.append((oldPassword, newPassword))
        return try result.get()
    }

}
