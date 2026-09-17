import Foundation
import XCTest
@testable import mobileFacilityApp

final class SAPOnboardingPersistenceTests: XCTestCase {
    func testMatchingLandscapeRestoresOnboardingID() {
        withDefaults { defaults in
            let onboardingID = UUID()
            SAPOnboardingPersistence.store(
                onboardingID: onboardingID,
                for: "landscape-a",
                defaults: defaults
            )

            XCTAssertEqual(
                SAPOnboardingPersistence.onboardingID(
                    for: "landscape-a",
                    defaults: defaults
                ),
                onboardingID
            )
        }
    }

    func testChangedLandscapeDoesNotRestorePreviousOnboardingID() {
        withDefaults { defaults in
            SAPOnboardingPersistence.store(
                onboardingID: UUID(),
                for: "landscape-a",
                defaults: defaults
            )

            XCTAssertNil(
                SAPOnboardingPersistence.onboardingID(
                    for: "landscape-b",
                    defaults: defaults
                )
            )
            XCTAssertNil(
                SAPOnboardingPersistence.onboardingID(
                    for: "landscape-a",
                    defaults: defaults
                )
            )
        }
    }

    func testLegacyOnboardingIDWithoutFingerprintStartsFreshOnboarding() {
        withDefaults { defaults in
            defaults.set(UUID().uuidString, forKey: "userOnboardingID")

            XCTAssertNil(
                SAPOnboardingPersistence.onboardingID(
                    for: "landscape-a",
                    defaults: defaults
                )
            )
            XCTAssertNil(defaults.string(forKey: "userOnboardingID"))
        }
    }

    private func withDefaults(_ body: (UserDefaults) -> Void) {
        let suiteName = "SAPOnboardingPersistenceTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defer { defaults.removePersistentDomain(forName: suiteName) }
        body(defaults)
    }
}
