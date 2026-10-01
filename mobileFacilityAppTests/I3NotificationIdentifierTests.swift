import Foundation
import XCTest
@testable import mobileFacilityApp

/// An I3 upload that SAP did not confirm is sent again with the next
/// synchronization. Its identifiers derive from the work item, so the retry
/// replaces its own rows instead of creating a second notification in SAP.
final class I3NotificationIdentifierTests: XCTestCase {
    private let workItemID = UUID(uuidString: "3F2504E0-4F89-11D3-9A0C-0305E82C3301")!
    private let otherWorkItemID = UUID(uuidString: "9B1DEB4D-3B7D-4BAD-9BDD-2B0D7B3DCB6D")!

    // MARK: - Identifiers

    func testIdentifiersFollowTheLegacyFormats() {
        let ids = SAPI3NotificationUploadBuilder.identifiers(for: workItemID)

        // `getUIID()`: 32 upper-case hexadecimal digits.
        XCTAssertEqual(ids.processID, "3F2504E04F8911D39A0C0305E82C3301")
        // `randomId(8, "NEU")`.
        XCTAssertEqual(ids.notificationID, "NEU-3F2504E0")
        XCTAssertEqual(ids.documentID.count, 32)
        XCTAssertTrue(ids.documentID.allSatisfy { $0.isHexDigit && !$0.isLowercase })
    }

    func testTheSameWorkItemAlwaysGetsTheSameIdentifiers() {
        let first = SAPI3NotificationUploadBuilder.identifiers(for: workItemID)
        let again = SAPI3NotificationUploadBuilder.identifiers(for: workItemID)

        XCTAssertEqual(first.processID, again.processID)
        XCTAssertEqual(first.notificationID, again.notificationID)
        XCTAssertEqual(first.documentID, again.documentID)
    }

    func testDifferentWorkItemsNeverShareIdentifiers() {
        let first = SAPI3NotificationUploadBuilder.identifiers(for: workItemID)
        let other = SAPI3NotificationUploadBuilder.identifiers(for: otherWorkItemID)

        XCTAssertNotEqual(first.processID, other.processID)
        XCTAssertNotEqual(first.notificationID, other.notificationID)
        XCTAssertNotEqual(first.documentID, other.documentID)
    }

    // MARK: - Rows of a retried upload

    func testRetriedUploadCarriesTheSameIdentifiersInEveryRow() throws {
        let first = try batch(workItemID: workItemID)
        let retry = try batch(workItemID: workItemID)
        let ids = SAPI3NotificationUploadBuilder.identifiers(for: workItemID)

        for batch in [first, retry] {
            XCTAssertEqual(batch.workItemIDs, [workItemID])
            XCTAssertEqual(batch.processIDs, [ids.processID])
            XCTAssertEqual(batch.i3Notifications.count, 1)
            // `TO_T0300` (`type4T0300`) has no process column; `QMNUM` keys it.
            XCTAssertEqual(batch.i3Notifications.first?["QMNUM"] ?? nil, ids.notificationID)
            let document = try XCTUnwrap(batch.i3Documents.first?.metadata)
            XCTAssertEqual(document["VORGANGSNR"], ids.processID)
            XCTAssertEqual(document["QMNUM"], ids.notificationID)
            XCTAssertEqual(document["OBJKY"], ids.notificationID)
            XCTAssertEqual(document["DOCID"], ids.documentID)
        }
    }

    func testAnotherFormGetsItsOwnNotification() throws {
        let first = try XCTUnwrap(batch(workItemID: workItemID).i3Documents.first?.metadata)
        let other = try XCTUnwrap(batch(workItemID: otherWorkItemID).i3Documents.first?.metadata)

        XCTAssertNotEqual(first["VORGANGSNR"], other["VORGANGSNR"])
        XCTAssertNotEqual(first["QMNUM"], other["QMNUM"])
        XCTAssertNotEqual(first["DOCID"], other["DOCID"])
    }

    // MARK: - Nothing is queued without its data

    func testFormWithoutItsReportIsNotSent() {
        XCTAssertThrowsError(try batch(workItemID: workItemID, pdfData: Data())) { error in
            guard case I3NotificationUploadError.missingPDF = error else {
                return XCTFail("Expected missingPDF, got \(error)")
            }
        }
    }

    func testFormWhoseBuildingIsNotCachedIsNotSent() {
        XCTAssertThrowsError(try batch(workItemID: workItemID, functionalLocationJSON: "")) { error in
            guard case let I3NotificationUploadError.missingFunctionalLocation(id) = error else {
                return XCTFail("Expected missingFunctionalLocation, got \(error)")
            }
            XCTAssertEqual(id, "DE-SAF-11152-10")
        }
    }

    func testFormWhosePlanIsNotCachedIsNotSent() {
        let plans: [(I3NotificationForm, String)] = [(.briefing, "TFMB_001"), (.qualification, "TFMQ_001")]
        for (form, planNumber) in plans {
            XCTAssertThrowsError(try batch(workItemID: workItemID, form: form)) { error in
                guard case let I3NotificationUploadError.missingPlan(number) = error else {
                    return XCTFail("Expected missingPlan for \(form), got \(error)")
                }
                XCTAssertEqual(number, planNumber)
            }
        }
    }

    // MARK: - Fixture

    /// `electricalSafety` is the one form that needs no plan positions, which
    /// keeps the fixture small.
    private func batch(
        workItemID: UUID,
        form: I3NotificationForm = .electricalSafety,
        pdfData: Data = Data("%PDF-1.4".utf8),
        functionalLocationJSON: String = #"{"STRNO":"DE-SAF-11152-10","IWERK":"1000","MANDT2":"100"}"#
    ) throws -> SAPNotificationOutgoingBatch {
        let input = I3NotificationInput(
            form: form,
            workItemID: workItemID,
            functionalLocationID: "DE-SAF-11152-10", instructedPerson: "Muster",
            coordinator: "Koordinator", task: "Arbeit",
            start: Date(timeIntervalSince1970: 1_700_000_000),
            end: Date(timeIntervalSince1970: 1_700_086_400),
            partner: .none, partnerEmail: "", selectedOptionalSectionIDs: [],
            pdfData: pdfData,
            completedAt: Date(timeIntervalSince1970: 1_700_000_000)
        )
        let context = I3NotificationLegacyContext(
            templateJSON: nil,
            functionalLocationJSON: functionalLocationJSON,
            planPositionsJSON: nil, partnerJSON: nil,
            userJSON: #"{"PERSNR":"S50828"}"#
        )
        return try SAPI3NotificationUploadBuilder.build(input: input, context: context, syncUserID: "S50828")
    }
}
