import XCTest
@testable import mobileFacilityApp

/// The notification row chip names the inspection form SAP delivered with the
/// notification (`STEUS` / `FORMNR`). Nothing here may derive a category from
/// a label, an ID segment or a cost group — those are not SAP data.
final class NotificationBadgeTests: XCTestCase {
    func testDemoNotificationsBadgeTheirInspectionForm() throws {
        let expected: [String: (titleKey: String, style: FacilityTemplateBadgeStyle)] = [
            "4710000012": ("elevator.inspection.title", .formElevator),
            "4710000024": ("fixedLadder.inspection.title", .formFixedLadder),
            "4710000036": ("holdOpenSystem.inspection.title", .formHoldOpenSystem),
            "4710000048": ("roofSystem.inspection.title", .formRoofSystem),
            "M-31042": ("notifications.structuralFilter.form.tfm3", .formRoundInspection),
            "4710000031": ("subdistribution.title", .formSubdistribution),
            "005140055904": ("notifications.structuralFilter.form.tfm1", .formMaintenancePlan),
            "M-30965": ("notifications.structuralFilter.form.tfm1", .formMaintenancePlan)
        ]

        for (id, expectation) in expected {
            let notification = try XCTUnwrap(
                MockFacilityData.notifications.first { $0.id == id },
                "demo notification \(id) is missing"
            )
            let badge = try XCTUnwrap(notification.categoryBadge, "no badge for \(id)")
            XCTAssertEqual(badge.titleKey, expectation.titleKey, "title key for \(id)")
            XCTAssertEqual(badge.style, expectation.style, "style for \(id)")
            XCTAssertEqual(badge.code, notification.structuralFilterMetadata?.formCode, "code for \(id)")
        }
    }

    /// TFM9 has no screen in the app yet, so the chip stays verbatim instead of
    /// claiming a form the technician cannot open.
    func testUnknownControlKeyKeepsItsRawCode() throws {
        let badge = try XCTUnwrap(makeNotification(formCode: "TFM9").categoryBadge)

        XCTAssertNil(badge.titleKey)
        XCTAssertEqual(badge.code, "TFM9")
        XCTAssertEqual(badge.style, .neutral)
    }

    func testMissingFormCodeShowsNoBadge() {
        XCTAssertNil(makeNotification(formCode: "").categoryBadge)
        XCTAssertNil(makeNotification(formCode: "   ").categoryBadge)
        XCTAssertNil(
            MaintenanceNotification(
                id: "N-1003",
                title: "Ohne Strukturdaten",
                location: "Bereich X",
                dueDate: "Heute",
                equipment: "EQ-CUSTOM",
                sapStatus: nil,
                status: .open,
                completedChecks: 0,
                totalChecks: 0
            ).categoryBadge
        )
    }

    func testFormCodeCaseAndPaddingAreNormalized() throws {
        let notification = makeNotification(formCode: " tfm5 ")

        XCTAssertEqual(notification.formType, .mobileLadder)
        let badge = try XCTUnwrap(notification.categoryBadge)
        XCTAssertEqual(badge.code, "TFM5")
        XCTAssertEqual(badge.titleKey, "mobileLadder.title")
        XCTAssertEqual(badge.style, .formMobileLadder)
    }

    /// A functional location that happens to contain a three-digit segment must
    /// not produce a badge: the row only reports what SAP classified.
    func testLabelsAloneDoNotProduceABadge() {
        let notification = MaintenanceNotification(
            id: "N-1004",
            title: "Lüftungsfilter prüfen",
            location: "UN01-ST01-BG01-TECH-430-RLT1",
            dueDate: "Heute",
            equipment: "UN01-ST01-BG01-TECH-430-RLT1",
            sapStatus: nil,
            status: .open,
            completedChecks: 0,
            totalChecks: 0
        )

        XCTAssertNil(notification.categoryBadge)
    }

    func testEveryFormTitleIsTranslatedInBothLanguages() {
        for formType in NotificationFormType.allCases {
            for language in ["de", "en"] {
                let value = String(
                    localized: String.LocalizationValue(formType.titleKey),
                    bundle: .main,
                    locale: Locale(identifier: language)
                )
                XCTAssertFalse(value.isEmpty, "\(formType.rawValue) has no \(language) text")
                XCTAssertNotEqual(
                    value,
                    formType.titleKey,
                    "\(formType.titleKey) is missing from the \(language) catalog"
                )
            }
        }
    }

    private func makeNotification(formCode: String) -> MaintenanceNotification {
        MaintenanceNotification(
            id: "N-1001",
            title: "Prüfung",
            location: "Technikzentrale",
            dueDate: "Heute",
            equipment: "EQ-CUSTOM",
            sapStatus: nil,
            status: .open,
            completedChecks: 0,
            totalChecks: 3,
            structuralFilterMetadata: .init(
                countryCode: "DE",
                locationCode: "ESS",
                businessEntityCode: "11248",
                buildingCode: "A",
                tradeCode: "FM",
                formCode: formCode,
                functionalLocationName: "Technikzentrale"
            )
        )
    }
}
