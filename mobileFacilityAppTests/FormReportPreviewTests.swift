import CoreGraphics
import SwiftUI
import XCTest
@testable import mobileFacilityApp

/// The paperclip that opens the report of a closed notification from the
/// local-work and defect lists.
final class FormReportPreviewTests: XCTestCase {

    // MARK: Artifact

    func testNoArtifactWithoutAStoredReport() {
        XCTAssertNil(FormReportPDFArtifact(notificationID: "000123456", data: nil))
        XCTAssertNil(FormReportPDFArtifact(notificationID: "000123456", data: Data()))
    }

    func testArtifactFileNameDropsTheLeadingZerosOfTheNotification() {
        let artifact = FormReportPDFArtifact(notificationID: "000123456", data: Data([0x25, 0x50]))

        XCTAssertEqual(artifact?.fileName, "Bericht_123456.pdf")
        XCTAssertEqual(artifact?.id, "000123456")
    }

    // MARK: Stored report

    private func review(closed: Bool, pdfData: Data?) -> NotificationReviewDraftPayload {
        NotificationReviewDraftPayload(
            notificationID: "000123456",
            performedOn: Date(timeIntervalSince1970: 1_700_000_000),
            results: ["10": .yes],
            comments: ["10": "Befund"],
            photoAttachments: [],
            isClosedLocally: closed,
            pdfData: pdfData
        )
    }

    func testClosedReviewKeepsItsReportThroughTheOfflineQueue() throws {
        let stored = Data("%PDF-1.4".utf8)
        let encoded = try JSONEncoder().encode(review(closed: true, pdfData: stored))
        let decoded = try JSONDecoder().decode(NotificationReviewDraftPayload.self, from: encoded)

        XCTAssertEqual(decoded.pdfData, stored)
        XCTAssertNotNil(FormReportPDFArtifact(notificationID: decoded.notificationID, data: decoded.pdfData))
    }

    /// Reviews closed before the report was kept stay readable; they simply
    /// offer no paperclip.
    func testReviewStoredBeforeTheReportWasKeptStillDecodes() throws {
        let legacy = """
        {
          "notificationID": "000123456",
          "performedOn": 723456.0,
          "results": {},
          "comments": {},
          "photoAttachments": [],
          "isClosedLocally": true
        }
        """
        let decoded = try JSONDecoder().decode(
            NotificationReviewDraftPayload.self,
            from: Data(legacy.utf8)
        )

        XCTAssertTrue(decoded.isClosedLocally)
        XCTAssertNil(decoded.pdfData)
        XCTAssertNil(FormReportPDFArtifact(notificationID: decoded.notificationID, data: decoded.pdfData))
    }

    func testAnOpenDraftIsEncodedWithoutAReport() throws {
        let encoded = try JSONEncoder().encode(review(closed: false, pdfData: nil))
        let decoded = try JSONDecoder().decode(NotificationReviewDraftPayload.self, from: encoded)

        XCTAssertNil(decoded.pdfData)
    }

    // MARK: Layout on the narrowest window

    /// 700 pt window − 72 pt rail − 1 pt divider − 2 × 20 pt padding, as in
    /// `FacilityColumnsLayoutTests`.
    private let narrowestPageWidth: CGFloat = 587

    /// Width `DefectCardColumns` is given on a closed notification card that
    /// carries the paperclip.
    private func defectCardColumnsWidth(withPaperclip: Bool) -> CGFloat {
        narrowestPageWidth
            - 2 * 18 // facilityCard padding
            - (withPaperclip ? FormReportPaperclipButton.rowFootprint : 0)
            - DefectCardMetrics.photoTileWidth
            - DefectCardMetrics.photoTileSpacing
    }

    func testPaperclipCostsTheDefectCardItsBadgeHeadroom() {
        XCTAssertEqual(defectCardColumnsWidth(withPaperclip: false), 483)
        XCTAssertEqual(defectCardColumnsWidth(withPaperclip: true), 437)
    }

    /// German `Befund` (61.7 pt) + 8 pt + `Lokal abgeschlossen` (140.8 pt),
    /// measured with the badge font (`.system(size: 11.5, weight: .bold)`)
    /// plus its 2 × 10 pt horizontal padding.
    private let germanClosedDefectBadgesWidth: CGFloat = 210.5

    /// The badges of a closed notification move under the text on the
    /// narrowest window once the paperclip takes its column. That is the
    /// designed fallback of `FacilitySideColumnLayout`, not a clipped card.
    func testGermanClosedDefectCardStacksItsBadgesOnTheNarrowestWindow() {
        let layout = DefectCardMetrics.layout

        XCTAssertTrue(
            layout.isSideBySide(
                forWidth: defectCardColumnsWidth(withPaperclip: false),
                sideIdealWidth: germanClosedDefectBadgesWidth
            )
        )
        XCTAssertFalse(
            layout.isSideBySide(
                forWidth: defectCardColumnsWidth(withPaperclip: true),
                sideIdealWidth: germanClosedDefectBadgesWidth
            )
        )
    }

    /// English badges (`Attention` 74.4 pt + 8 pt + `Closed locally`
    /// 101.1 pt) still fit beside the text with the paperclip.
    func testEnglishClosedDefectCardKeepsItsBadgesBesideTheText() {
        XCTAssertTrue(
            DefectCardMetrics.layout.isSideBySide(
                forWidth: defectCardColumnsWidth(withPaperclip: true),
                sideIdealWidth: 183.5
            )
        )
    }

    /// On a 13" window the paperclip changes nothing for either language.
    func testWideWindowKeepsTheBadgesBesideTheTextInBothLanguages() {
        // 1376 pt window − 340 pt sidebar − 1 pt divider − 2 × 28 pt padding.
        let wideColumns: CGFloat = 979 - 2 * 18 - FormReportPaperclipButton.rowFootprint
            - DefectCardMetrics.photoTileWidth
            - DefectCardMetrics.photoTileSpacing

        XCTAssertTrue(
            DefectCardMetrics.layout.isSideBySide(
                forWidth: wideColumns,
                sideIdealWidth: germanClosedDefectBadgesWidth
            )
        )
    }

    /// The local-work row has no side-column fallback: the paperclip only
    /// narrows the title and subtitle, which are line-limited.
    func testLocalWorkRowKeepsRoomForTitleAndStatusOnTheNarrowestWindow() {
        let rowContent = narrowestPageWidth - 2 * 18 - FormReportPaperclipButton.rowFootprint
        let icon: CGFloat = 44 + 16
        let statusBadge: CGFloat = 140.8 // "Lokal abgeschlossen"
        let minimumSpacer: CGFloat = 12

        XCTAssertEqual(rowContent, 505)
        XCTAssertGreaterThan(rowContent - icon - statusBadge - minimumSpacer, 280)
    }
}

/// Title of the equipment-inspection report header.
final class EquipmentInspectionReportTitleTests: XCTestCase {
    /// TFM2 names itself instead of printing the SAP class description
    /// ("e.on Aufzug Merkmale"), and matches what the upload rebuilds.
    func testElevatorReportIsTitledAufzugskontrolle() {
        XCTAssertTrue(EquipmentInspectionForm.elevator.reportTitleIgnoresClassDescription)
        XCTAssertEqual(EquipmentInspectionForm.elevator.reportTitleFallback, "Aufzugskontrolle")
    }

    /// TFM6 is pinned the same way, to the short form the user asked for
    /// rather than the class description SAP delivers.
    func testHoldOpenSystemReportIsTitledFSA() {
        XCTAssertTrue(EquipmentInspectionForm.holdOpenSystem.reportTitleIgnoresClassDescription)
        XCTAssertEqual(EquipmentInspectionForm.holdOpenSystem.reportTitleFallback, "FSA")
    }

    /// The other equipment forms still print the class description when SAP
    /// delivers one, as `buildPDF` does.
    func testTheOtherEquipmentFormsKeepTheClassDescription() {
        for form in [
            EquipmentInspectionForm.fixedLadder,
            .subdistribution,
            .roofSystem
        ] {
            XCTAssertFalse(
                form.reportTitleIgnoresClassDescription,
                "\(form.formCode) unexpectedly stopped using its class description"
            )
        }
    }
}
