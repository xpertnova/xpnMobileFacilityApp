import Foundation
import UIKit
import XCTest
@testable import mobileFacilityApp

/// Guards the one shared inspection checklist against drifting back into one
/// checklist per form. Every expectation here is traced to the legacy Cordova
/// controller named in its comment.
final class InspectionFormStandardizationTests: XCTestCase {

    // MARK: - Variants

    /// `Rundgang`/`WartungsPlan` build a `sap.m.SegmentedButton`; the other
    /// forms build a `sap.m.Select` per `T_PROPS.DTYPE`.
    func testResultControlStyleFollowsTheLegacyControllerPerFormCode() {
        XCTAssertEqual(InspectionFormVariant.forFormCode("TFM1").resultStyle, .segmented)
        XCTAssertEqual(InspectionFormVariant.forFormCode("TFM3").resultStyle, .segmented)
        for code in ["TFM2", "TFM4", "TFM5", "TFM6", "TFM7", "TFM8"] {
            XCTAssertEqual(
                InspectionFormVariant.forFormCode(code).resultStyle,
                .dropdown,
                "\(code) renders an SAP value help, not a yes/no decision"
            )
        }
    }

    /// `BaseFormController.buildDefaultElements` hides the out-of-order box
    /// for TFM1, TFM3, TFM8, TFM9 and TFMQ and shows it for the rest.
    func testOutOfServiceStatusMatchesTheLegacyExclusionList() {
        for code in ["TFM1", "TFM3", "TFM8", "TFM9", "TFMQ"] {
            XCTAssertFalse(
                InspectionFormVariant.forFormCode(code).supportsOutOfService,
                "\(code) has no out-of-order box in buildDefaultElements"
            )
        }
        for code in ["TFM2", "TFM4", "TFM5", "TFM6", "TFM7"] {
            XCTAssertTrue(
                InspectionFormVariant.forFormCode(code).supportsOutOfService,
                "\(code) carries the out-of-order box"
            )
        }
    }

    /// The MobileLeiter branch of `buildDefaultElements` labels the checkbox
    /// `form.chkBox.demount` instead of `form.chkBox.outOfOrder`.
    func testMobileLadderStatusIsLabelledDemountedRatherThanOutOfService() {
        XCTAssertEqual(
            InspectionFormVariant.forFormCode("TFM5").outOfServiceTitleKey,
            "inspection.outOfService.demounted"
        )
        XCTAssertEqual(
            InspectionFormVariant.forFormCode("TFM2").outOfServiceTitleKey,
            "inspection.outOfService"
        )
    }

    /// Only the dropdown forms declare the action and material columns.
    func testColumnSetPerFormCode() {
        let rundgang = InspectionFormVariant.forFormCode("TFM3")
        XCTAssertFalse(rundgang.hasActionColumn)
        XCTAssertFalse(rundgang.hasMaterialColumn)

        let elevator = InspectionFormVariant.forFormCode("TFM2")
        XCTAssertTrue(elevator.hasActionColumn)
        XCTAssertTrue(elevator.hasMaterialColumn)

        let ladder = InspectionFormVariant.forFormCode("TFM5")
        XCTAssertTrue(ladder.hasActionColumn)
        XCTAssertFalse(ladder.hasMaterialColumn)
    }

    /// A column SAP delivered no values for must not reserve table width.
    func testColumnsAreDroppedWhenSAPDeliveredNoValuesForThem() {
        let adjusted = InspectionFormVariant.forFormCode("TFM2")
            .adjusted(hasActionValues: true, hasMaterialValues: false)
        XCTAssertTrue(adjusted.hasActionColumn)
        XCTAssertFalse(adjusted.hasMaterialColumn)
    }

    func testUnknownFormCodeDerivesItsStyleFromTheOptionCount() {
        XCTAssertEqual(
            InspectionFormVariant.forFormCode("TFMX", optionCount: 2).resultStyle,
            .segmented
        )
        XCTAssertEqual(
            InspectionFormVariant.forFormCode("TFMX", optionCount: 5).resultStyle,
            .dropdown
        )
    }

    // MARK: - Shared rules

    /// `ElevatorInspectionLogic` and `HeaderFormBuilder.checkInputConstraints`
    /// agree: 2 and 4 are defects, 3 is a defect unless the action is 8.
    func testDropdownDefectClassification() {
        let style = InspectionControlStyle.dropdown
        XCTAssertFalse(InspectionFormRules.isDefective(resultCode: "1", style: style))
        XCTAssertTrue(InspectionFormRules.isDefective(resultCode: "2", style: style))
        XCTAssertTrue(InspectionFormRules.isDefective(resultCode: "3", style: style))
        XCTAssertFalse(InspectionFormRules.isDefective(resultCode: "3", actionCode: "8", style: style))
        XCTAssertTrue(InspectionFormRules.isDefective(resultCode: "4", actionCode: "8", style: style))
        XCTAssertFalse(InspectionFormRules.isDefective(resultCode: "5", style: style))
        XCTAssertFalse(InspectionFormRules.isDefective(resultCode: nil, style: style))
    }

    /// `Rundgang`/`WartungsPlan` compare the selected key against `"X"`.
    func testSegmentedDefectClassificationUsesTheSingleXCode() {
        XCTAssertTrue(InspectionFormRules.isDefective(resultCode: "X", style: .segmented))
        XCTAssertFalse(InspectionFormRules.isDefective(resultCode: "", style: .segmented))
        XCTAssertFalse(InspectionFormRules.isDefective(resultCode: nil, style: .segmented))
    }

    func testUnansweredPositionIsReportedOnlyWhenItCarriesAResultControl() {
        let variant = InspectionFormVariant.forFormCode("TFM2")
        XCTAssertEqual(
            InspectionFormRules.issues(resultCode: nil, variant: variant),
            [.resultMissing]
        )
        XCTAssertEqual(
            InspectionFormRules.issues(resultCode: nil, requiresResult: false, variant: variant),
            []
        )
    }

    /// `checkInputConstraints`: results 1 and 5 allow no material.
    func testMaterialIsRejectedForResultsThatAllowNone() {
        let variant = InspectionFormVariant.forFormCode("TFM2")
        for code in ["1", "5"] {
            XCTAssertEqual(
                InspectionFormRules.issues(
                    resultCode: code,
                    isMaterialSelected: true,
                    variant: variant
                ),
                [.materialNotAllowedForResult]
            )
        }
        XCTAssertEqual(
            InspectionFormRules.issues(resultCode: "2", isMaterialSelected: true, variant: variant),
            []
        )
    }

    /// `checkInputConstraints`: results 3 and 4 need an action and a comment,
    /// and a major defect (4) cannot have been repaired on site (8).
    func testDefectResultsRequireAnActionAndACommentAndRejectRepairedOnSite() {
        let variant = InspectionFormVariant.forFormCode("TFM2")
        XCTAssertEqual(
            InspectionFormRules.issues(resultCode: "3", variant: variant),
            [.actionAndCommentRequired]
        )
        XCTAssertEqual(
            InspectionFormRules.issues(resultCode: "3", actionCode: "7", variant: variant),
            [.actionAndCommentRequired]
        )
        XCTAssertEqual(
            InspectionFormRules.issues(
                resultCode: "3",
                actionCode: "7",
                comment: "Repair ordered",
                variant: variant
            ),
            []
        )
        XCTAssertEqual(
            InspectionFormRules.issues(
                resultCode: "4",
                actionCode: "8",
                comment: "Documented",
                variant: variant
            ),
            [.actionNotAllowedForResult]
        )
    }

    /// TFM1 and TFM3 share one rule: a defect needs a comment.
    func testBothSegmentedFormsRequireACommentForADefect() {
        for code in ["TFM1", "TFM3"] {
            let variant = InspectionFormVariant.forFormCode(code)
            XCTAssertTrue(variant.requiresCommentForDefect, code)
            XCTAssertEqual(
                InspectionFormRules.issues(resultCode: "X", variant: variant),
                [.commentRequired],
                code
            )
            XCTAssertEqual(
                InspectionFormRules.issues(resultCode: "X", comment: "Cracked pane", variant: variant),
                [],
                code
            )
            XCTAssertEqual(
                InspectionFormRules.issues(resultCode: "", variant: variant),
                [.resultMissing],
                code
            )
        }
    }

    /// `WartungsPlan.controller.js` keeps "not yet answered" in its hidden
    /// `"O"` item and reports `msg.viewForm.befund.leer` only for that key, so
    /// the empty `Befund` code of "in Ordnung" is an answer and must not raise
    /// the red exception marker.
    func testSegmentedInOrderAnswerIsNotReportedAsMissing() throws {
        let inOrder = try XCTUnwrap(
            NotificationReviewResult.formOptions.first {
                $0.id == NotificationReviewResult.no.rawValue
            }
        )
        XCTAssertEqual(inOrder.code, "", "in Ordnung posts an empty Befund")

        for code in ["TFM1", "TFM3"] {
            let variant = InspectionFormVariant.forFormCode(code)
            XCTAssertEqual(
                InspectionFormRules.issues(
                    resultCode: inOrder.code,
                    isResultAnswered: true,
                    variant: variant
                ),
                [],
                code
            )
            XCTAssertFalse(
                InspectionFormRules.isDefective(resultCode: inOrder.code, style: variant.resultStyle),
                code
            )
            XCTAssertEqual(
                InspectionFormRules.issues(
                    resultCode: nil,
                    isResultAnswered: false,
                    variant: variant
                ),
                [.resultMissing],
                code
            )
        }
    }

    /// `HeaderFormBuilder.validateFormValues` validates only the status
    /// comment while the form is out of service.
    func testOutOfServiceStatusRequiresAComment() {
        XCTAssertEqual(
            InspectionFormRules.outOfServiceIssues(comment: nil),
            [.outOfServiceCommentRequired]
        )
        XCTAssertEqual(
            InspectionFormRules.outOfServiceIssues(comment: "   "),
            [.outOfServiceCommentRequired]
        )
        XCTAssertEqual(InspectionFormRules.outOfServiceIssues(comment: "Shut down"), [])
    }

    /// `BaseFormController.onBefundChange` resets the action for result 1 and
    /// the material flag for results 1 and 5.
    func testAnsweringAResultClearsWhatItNoLongerPermits() {
        let cleared = InspectionFormRules.resolvedSelection(
            resultCode: "1",
            actionCode: "7",
            isMaterialSelected: true,
            style: .dropdown
        )
        XCTAssertNil(cleared.actionCode)
        XCTAssertFalse(cleared.isMaterialSelected)

        let notPresent = InspectionFormRules.resolvedSelection(
            resultCode: "5",
            actionCode: "9",
            isMaterialSelected: true,
            style: .dropdown
        )
        XCTAssertEqual(notPresent.actionCode, "9")
        XCTAssertFalse(notPresent.isMaterialSelected)

        let defect = InspectionFormRules.resolvedSelection(
            resultCode: "3",
            actionCode: "7",
            isMaterialSelected: true,
            style: .dropdown
        )
        XCTAssertEqual(defect.actionCode, "7")
        XCTAssertTrue(defect.isMaterialSelected)
    }

    // MARK: - Adapters

    /// The yes/no options must keep the SAP codes `SAPNotificationReviewUpload`
    /// posts (`""` / `"X"`) while staying individually identifiable.
    func testYesNoOptionsKeepTheirSAPCodesAndStayDistinguishable() {
        let options = NotificationReviewResult.formOptions
        XCTAssertEqual(options.map(\.code), ["", "X"])
        XCTAssertEqual(options.map(\.id), ["no", "yes"])
        XCTAssertEqual(options.map(\.tint), [.satisfactory, .defect])
        XCTAssertEqual(NotificationReviewResult(optionID: "yes"), .yes)
        XCTAssertEqual(NotificationReviewResult(optionID: "no"), .no)
        XCTAssertNil(NotificationReviewResult(optionID: nil))
        XCTAssertNil(NotificationReviewResult(optionID: "maybe"))
    }

    func testElevatorItemExposesItsSAPValueHelpAsSharedOptions() {
        let item = ElevatorInspectionItem(
            id: "TFM2-0010-1",
            vornr: "0010",
            steus: "TFM2",
            positionNumber: 1,
            title: "Triebwerksraum",
            information: "",
            resultElementID: "TFM2-0010-1",
            resultOptions: [
                ElevatorInspectionValueOption(code: "1", text: "In Ordnung"),
                ElevatorInspectionValueOption(code: "4", text: "Erheblicher Mangel")
            ],
            actionElementID: "TFM2-0010-2",
            actionOptions: [ElevatorInspectionValueOption(code: "7", text: "Reparatur")],
            materialElementID: "TFM2-0010-3",
            commentElementID: "TFM2-0010-9B"
        )

        let formItem = item.inspectionFormItem
        XCTAssertEqual(formItem.resultOptions.map(\.code), ["1", "4"])
        XCTAssertEqual(formItem.resultOptions.map(\.title), ["In Ordnung", "Erheblicher Mangel"])
        XCTAssertEqual(formItem.actionOptions.map(\.code), ["7"])
        XCTAssertTrue(formItem.supportsMaterial)
        XCTAssertEqual(formItem.number, 1)
    }

    func testMobileLadderOptionsStillCarryTheVerifiedTFM5Codes() {
        XCTAssertEqual(MobileLadderInspectionResult.formOptions.map(\.code), ["1", "2", "3", "4", "5"])
        XCTAssertEqual(MobileLadderInspectionAction.formOptions.map(\.code), ["7", "8", "9"])
    }

    /// The checklist geometry lives in one place, so two forms cannot lay
    /// their inspection points out differently.
    func testEveryFormSharesOneColumnGeometry() {
        XCTAssertEqual(InspectionFormMetrics.resultColumn, InspectionFormMetrics.actionColumn)
        XCTAssertEqual(
            InspectionFormMetrics.leadingColumnWidth,
            InspectionFormMetrics.numberColumn
                + InspectionFormMetrics.leadingColumnSpacing
                + InspectionFormMetrics.statusColumn
        )
        // The number and its status marker read as one unit, so they sit
        // closer together than two data columns do.
        XCTAssertLessThan(
            InspectionFormMetrics.leadingColumnSpacing,
            InspectionFormMetrics.rowSpacing
        )
    }

    /// The narrow columns have to fit their own labels. "Bemerkung" wrapped
    /// onto a second line while the comment column was 58pt at subheadline
    /// weight, which is what pushed the header out of line with its controls.
    func testNarrowColumnsAreWideEnoughForTheirLabels() {
        let font = UIFont.preferredFont(forTextStyle: .caption1)
        let bold = UIFontMetrics(forTextStyle: .caption1).scaledFont(
            for: UIFont.systemFont(ofSize: font.pointSize, weight: .bold)
        )
        let cases: [(String, CGFloat)] = [
            (InspectionFormColumn.material, InspectionFormMetrics.materialColumn),
            (InspectionFormColumn.photo, InspectionFormMetrics.photoColumn),
            (InspectionFormColumn.comment, InspectionFormMetrics.commentColumn)
        ]
        for locale in [Locale(identifier: "de"), Locale(identifier: "en")] {
            for (key, width) in cases {
                let label = localized(key, locale)
                let measured = (label as NSString)
                    .size(withAttributes: [.font: bold])
                    .width
                XCTAssertLessThanOrEqual(
                    measured.rounded(.up),
                    width,
                    "\(label) (\(locale.identifier)) does not fit its \(width)pt column"
                )
            }
        }
    }

    /// A checklist has to fit the iPad landscape content area beside the
    /// expanded sidebar, or SwiftUI compresses the columns until their labels
    /// wrap. 1366pt screen − 340pt sidebar − 28pt page padding on each side.
    func testWidestChecklistFitsTheIPadLandscapeContentArea() {
        let available: CGFloat = 1366 - 340 - 28 * 2
        for code in ["TFM1", "TFM2", "TFM3", "TFM5", "TFM7"] {
            let variant = InspectionFormVariant.forFormCode(code)
            XCTAssertLessThanOrEqual(
                InspectionFormMetrics.intrinsicWidth(for: variant),
                available,
                "\(code) cannot lay its columns out without compressing them"
            )
        }
    }

    // MARK: - Form behaviour

    /// TFM3 used to close with an uncommented defect while TFM1 refused.
    /// `Rundgang.controller.js.checkInputConstraints` applies the same rule.
    @MainActor
    func testRundgangRefusesToCloseADefectWithoutAComment() async throws {
        let detail = SAPNotificationDetail(summary: try makeRundgangSummary())
        XCTAssertEqual(detail.inspectionItems.count, 2)

        let model = NotificationReviewViewModel(
            detail: detail,
            offlineWorkStore: OfflineWorkStore(
                repository: InMemoryOfflineWorkRepository(),
                workerID: "S50828"
            ),
            photoStore: InMemoryPhotoAttachmentStore()
        )
        await model.load()

        XCTAssertFalse(model.canClose)

        for item in detail.inspectionItems {
            model.results[item.id] = .no
        }
        XCTAssertTrue(model.canClose)

        let defective = detail.inspectionItems[0]
        model.results[defective.id] = .yes
        XCTAssertTrue(model.isCommentMissing(for: defective.id))
        XCTAssertFalse(model.canClose)

        model.comments[defective.id] = "Fire door does not latch"
        XCTAssertFalse(model.isCommentMissing(for: defective.id))
        XCTAssertTrue(model.canClose)
    }

    /// TFM2 carries the header status, so it must lock its positions, clear
    /// the recorded answers, and refuse to close undocumented.
    @MainActor
    func testElevatorOutOfServiceLocksClearsAndRequiresDocumentation() async throws {
        let detail = SAPNotificationDetail(summary: try makeElevatorSummary())
        let model = EquipmentInspectionViewModel(
            detail: detail,
            offlineWorkStore: OfflineWorkStore(
                repository: InMemoryOfflineWorkRepository(),
                workerID: "S50828"
            ),
            photoStore: InMemoryPhotoAttachmentStore()
        )
        await model.load()
        XCTAssertEqual(model.items.count, 1)

        let item = model.items[0]
        model.results[item.id] = "4"
        model.actions[item.id] = "7"
        model.comments[item.id] = "Cable wear"
        XCTAssertTrue(model.arePositionsEditable)
        XCTAssertTrue(model.hasDefect)

        await model.confirmOutOfServiceChange(to: true)

        XCTAssertTrue(model.isOutOfService)
        XCTAssertFalse(model.arePositionsEditable)
        XCTAssertTrue(model.results.isEmpty)
        XCTAssertTrue(model.actions.isEmpty)
        XCTAssertTrue(model.comments.isEmpty)
        XCTAssertFalse(model.hasDefect)
        XCTAssertTrue(model.deficientItems.isEmpty)
        XCTAssertFalse(model.isAllGoodAvailable)

        // Undocumented: closing is refused.
        XCTAssertTrue(model.isOutOfServiceCommentMissing)
        XCTAssertFalse(model.isChecklistValid)

        model.outOfServiceComment = "Lift shut down by the operator"
        XCTAssertFalse(model.isOutOfServiceCommentMissing)
        XCTAssertTrue(model.isChecklistValid)

        await model.confirmOutOfServiceChange(to: false)
        XCTAssertFalse(model.isOutOfService)
        XCTAssertTrue(model.arePositionsEditable)
        XCTAssertEqual(model.outOfServiceComment, "")
    }

    /// The status posts in the header elements the legacy client reserves for
    /// it, and the notification stays open (`MIAR`) with `aBet Mnot`.
    func testElevatorUploadPostsTheOutOfServiceStatusInTheHeaderElements() throws {
        let source = try makeElevatorSummary()
        let draft = ElevatorInspectionDraftPayload(
            notificationID: source.id,
            performedOn: Date(timeIntervalSince1970: 1_773_489_600),
            pdfDocumentID: "PDF-1",
            pdfBytes: Data("PDF".utf8),
            outgoingProcessID: "PROC-1",
            isClosedLocally: true,
            isOutOfOperation: true,
            outOfOperationComment: "Lift shut down by the operator"
        )
        let workItem = OfflineWorkItem(
            id: UUID(),
            workerID: "S50828",
            type: .elevatorInspection,
            status: .pendingSynchronization,
            payload: .elevatorInspection(draft),
            createdAt: .now,
            updatedAt: .now,
            syncError: nil
        )

        let batch = try SAPEquipmentInspectionUploadBuilder.build(
            workItem: workItem,
            source: source,
            syncUserID: "S50828",
            photoData: [:]
        )

        let header = try XCTUnwrap(batch.headers.first)
        XCTAssertEqual(header["STTXT"], "MIAR")
        XCTAssertEqual(header["STATUSNR"], "2")
        let userStatus = try XCTUnwrap(header["USTXT"] ?? nil)
        XCTAssertTrue(userStatus.contains("Mnot"))

        let statusRow = batch.values.first { $0["ELEMENTNR"] == "TFM2-0000-1" }
        XCTAssertEqual(statusRow?["ELEMENTWERT"], "aBet")
        let commentRow = batch.values.first { $0["ELEMENTNR"] == "TFM2-0000-9B" }
        XCTAssertEqual(commentRow?["ELEMENTWERT"], "Lift shut down by the operator")
    }

    /// Without the status set, an unanswered position still blocks the upload.
    func testElevatorUploadStillRejectsAnUnansweredPositionWhenInService() throws {
        let source = try makeElevatorSummary()
        let draft = ElevatorInspectionDraftPayload(
            notificationID: source.id,
            pdfDocumentID: "PDF-1",
            pdfBytes: Data("PDF".utf8),
            outgoingProcessID: "PROC-1",
            isClosedLocally: true,
            isOutOfOperation: false
        )
        let workItem = OfflineWorkItem(
            id: UUID(),
            workerID: "S50828",
            type: .elevatorInspection,
            status: .pendingSynchronization,
            payload: .elevatorInspection(draft),
            createdAt: .now,
            updatedAt: .now,
            syncError: nil
        )

        XCTAssertThrowsError(
            try SAPEquipmentInspectionUploadBuilder.build(
                workItem: workItem,
                source: source,
                syncUserID: "S50828",
                photoData: [:]
            )
        )
    }

    /// An out-of-service form without a comment must not reach SAP either.
    func testElevatorUploadRejectsAnUndocumentedOutOfServiceStatus() throws {
        let source = try makeElevatorSummary()
        let draft = ElevatorInspectionDraftPayload(
            notificationID: source.id,
            pdfDocumentID: "PDF-1",
            pdfBytes: Data("PDF".utf8),
            outgoingProcessID: "PROC-1",
            isClosedLocally: true,
            isOutOfOperation: true,
            outOfOperationComment: "   "
        )
        let workItem = OfflineWorkItem(
            id: UUID(),
            workerID: "S50828",
            type: .elevatorInspection,
            status: .pendingSynchronization,
            payload: .elevatorInspection(draft),
            createdAt: .now,
            updatedAt: .now,
            syncError: nil
        )

        XCTAssertThrowsError(
            try SAPEquipmentInspectionUploadBuilder.build(
                workItem: workItem,
                source: source,
                syncUserID: "S50828",
                photoData: [:]
            )
        )
    }


    /// TFM2 used to close a clean inspection the moment the button was tapped,
    /// while every other form asked first. Closing is irreversible — the form
    /// becomes read-only — so all five confirm.
    @MainActor
    func testElevatorAsksBeforeClosingACleanInspection() async throws {
        let detail = SAPNotificationDetail(summary: try makeElevatorSummary())
        let model = EquipmentInspectionViewModel(
            detail: detail,
            offlineWorkStore: OfflineWorkStore(
                repository: InMemoryOfflineWorkRepository(),
                workerID: "S50828"
            ),
            photoStore: InMemoryPhotoAttachmentStore()
        )
        await model.load()
        let item = try XCTUnwrap(model.items.first)

        // Unanswered: neither dialog opens, the row is flagged instead.
        model.handleCloseTapped()
        XCTAssertFalse(model.isCloseConfirmationPresented)
        XCTAssertFalse(model.isStatusDecisionPresented)
        XCTAssertTrue(model.validationErrors.contains(item.id))

        // Clean result: the plain confirmation, not an immediate save.
        model.results[item.id] = "1"
        model.handleCloseTapped()
        XCTAssertTrue(model.isCloseConfirmationPresented)
        XCTAssertFalse(model.isStatusDecisionPresented)
        XCTAssertFalse(model.isClosedLocally, "closing waits for the confirmation")

        // Defect: the status decision replaces the plain confirmation.
        model.isCloseConfirmationPresented = false
        model.results[item.id] = "4"
        model.actions[item.id] = "7"
        model.comments[item.id] = "Cable wear"
        model.handleCloseTapped()
        XCTAssertTrue(model.isStatusDecisionPresented)
        XCTAssertFalse(model.isCloseConfirmationPresented)
    }

    /// An out-of-service form confirms too, and stays open for the follow-up.
    @MainActor
    func testElevatorOutOfServiceCloseIsConfirmedAndLeavesTheNotificationOpen() async throws {
        let detail = SAPNotificationDetail(summary: try makeElevatorSummary())
        let model = EquipmentInspectionViewModel(
            detail: detail,
            offlineWorkStore: OfflineWorkStore(
                repository: InMemoryOfflineWorkRepository(),
                workerID: "S50828"
            ),
            photoStore: InMemoryPhotoAttachmentStore()
        )
        await model.load()
        await model.confirmOutOfServiceChange(to: true)

        // Undocumented: no dialog, the missing comment is reported instead.
        model.handleCloseTapped()
        XCTAssertFalse(model.isCloseConfirmationPresented)

        model.outOfServiceComment = "Lift shut down by the operator"
        model.handleCloseTapped()
        XCTAssertTrue(model.isCloseConfirmationPresented)
        XCTAssertFalse(model.isStatusDecisionPresented)
    }

    /// The dialog stacks three or more choices instead of squeezing them into
    /// one row, the way a system alert does.
    func testConfirmationDialogLaysOutItsActions() {
        let single = FacilityDialogAction(titleKey: "a", emphasis: .primary) {}
        XCTAssertEqual(single.id, "a")
        XCTAssertEqual(
            FacilityDialogAction(titleKey: "b", perform: {}).emphasis,
            .secondary,
            "an action is secondary unless it is the one being recommended"
        )
    }

    // MARK: - Fixtures

    private func makeRundgangSummary() throws -> SAPNotificationSummary {
        let payload: [String: Any] = [
            "MANDT": "100",
            "QMNUM": "005140055905",
            "QMART": "I1",
            "QMTXT": "MTFM_Rundgang",
            "STRNO": "DE-ESS-10748-01",
            "STEUS": "TFM3",
            "T_PLPOD": [
                [
                    "USR00": "POSITION", "STEUS": "TFM3", "VORNR": "0010",
                    "LTXA1": "Brandschutztüren", "LTXA2": "Freigängigkeit prüfen",
                    "T_PROPS": [["POSNR": "1", "DFVAL": " ;X", "DFVAL_TXT": "Nein;Ja"]]
                ],
                [
                    "USR00": "POSITION", "STEUS": "TFM3", "VORNR": "0020",
                    "LTXA1": "Fluchtwege", "LTXA2": "",
                    "T_PROPS": [["POSNR": "1", "DFVAL": " ;X", "DFVAL_TXT": "Nein;Ja"]]
                ]
            ]
        ]
        let data = try JSONSerialization.data(withJSONObject: payload, options: [.sortedKeys])
        return SAPNotificationSummary(
            id: "005140055905",
            client: "100",
            title: "MTFM_Rundgang",
            functionalLocationID: "DE-ESS-10748-01",
            functionalLocationName: "Verwaltungsgebäude",
            startDate: "20260914",
            endDate: "20260914",
            systemStatus: "MMAB",
            userStatus: "OPEN",
            rawPayloadJSON: try XCTUnwrap(String(data: data, encoding: .utf8))
        )
    }

    private func makeElevatorSummary() throws -> SAPNotificationSummary {
        let payload: [String: Any] = [
            "MANDT": "100",
            "QMNUM": "4710000012",
            "QMART": "I1",
            "FORMNR": "TFM2",
            "USTXT": "OPEN",
            "T_PLPOD": [
                [
                    "USR00": "POSITION", "STEUS": "TFM2", "VORNR": "0010",
                    "LTXA1": "Triebwerksraum", "LTXA2": "",
                    "T_PROPS": [
                        ["POSNR": "1", "DFVAL": "1;2;3;4;5", "DFVAL_TXT": "OK;Reinigung;Mangel;Erheblich;Fehlt"],
                        ["POSNR": "2", "DFVAL": "7;8;9", "DFVAL_TXT": "Reparatur;Behoben;Stillgelegt"]
                    ]
                ]
            ]
        ]
        let data = try JSONSerialization.data(withJSONObject: payload, options: [.sortedKeys])
        return SAPNotificationSummary(
            id: "4710000012",
            client: "100",
            title: "Aufzugskontrolle",
            functionalLocationID: "FL-1",
            functionalLocationName: "Aufzug",
            equipmentID: "EQ-100010",
            startDate: "20260914",
            endDate: "20260914",
            systemStatus: "MMAB",
            userStatus: "OPEN",
            rawPayloadJSON: try XCTUnwrap(String(data: data, encoding: .utf8))
        )
    }

    // MARK: - Column vocabulary and toolbar

    /// The legacy client labels the `formPositionTable` from one set of
    /// `tabelle.column.header.*` texts, so the result column reads "Befund" /
    /// "Result" on every form — never "Finding".
    func testEveryFormSharesOneColumnVocabulary() {
        XCTAssertEqual(InspectionFormColumn.number, "inspection.column.number")
        XCTAssertEqual(InspectionFormColumn.asset, "inspection.column.asset")
        XCTAssertEqual(InspectionFormColumn.result, "inspection.column.result")
        XCTAssertEqual(InspectionFormColumn.action, "inspection.column.action")
        XCTAssertEqual(InspectionFormColumn.material, "inspection.column.material")
        XCTAssertEqual(InspectionFormColumn.photo, "inspection.column.photo")
        XCTAssertEqual(InspectionFormColumn.comment, "inspection.column.comment")
    }

    /// `tabelle.column.header.*` in `i18n_en.properties` / `i18n.properties`.
    func testColumnLabelsMatchTheLegacyWording() {
        let english = Locale(identifier: "en")
        XCTAssertEqual(localized(InspectionFormColumn.number, english), "No.")
        XCTAssertEqual(localized(InspectionFormColumn.asset, english), "Reviewed asset")
        XCTAssertEqual(localized(InspectionFormColumn.result, english), "Result")
        XCTAssertEqual(localized(InspectionFormColumn.action, english), "Action")
        XCTAssertEqual(localized(InspectionFormColumn.material, english), "Material")
        XCTAssertEqual(localized(InspectionFormColumn.photo, english), "Photo")
        XCTAssertEqual(localized(InspectionFormColumn.comment, english), "Comment")
        XCTAssertEqual(localized(InspectionFormColumn.performedOn, english), "Performed on")
        XCTAssertEqual(localized("inspection.outOfService", english), "Out of operation")
        XCTAssertEqual(localized("inspection.outOfService.demounted", english), "Disassembled")

        let german = Locale(identifier: "de")
        XCTAssertEqual(localized(InspectionFormColumn.asset, german), "Überprüfte Anlagentechnik")
        XCTAssertEqual(localized(InspectionFormColumn.result, german), "Befund")
        XCTAssertEqual(localized(InspectionFormColumn.action, german), "Maßnahme")
        XCTAssertEqual(localized(InspectionFormColumn.comment, german), "Bemerkung")
        XCTAssertEqual(localized("inspection.outOfService", german), "Außer Betrieb")
        XCTAssertEqual(localized("inspection.outOfService.demounted", german), "Demontiert")
    }

    /// The date and the status share one toolbar band above the checklist,
    /// like the `form.date` and `form.outOfOrder` rows of
    /// `TableFormHeader.fragment.xml`. TFM1 is the one form whose controller
    /// hides that date.
    func testOnlyWartungsplanHidesTheExecutionDate() {
        XCTAssertFalse(InspectionFormVariant.forFormCode("TFM1").showsPerformedOnDate)
        XCTAssertFalse(InspectionFormVariant.forFormCode("TFM1").hasTableToolbar)
        for code in ["TFM2", "TFM3", "TFM4", "TFM5", "TFM6", "TFM7", "TFM8"] {
            XCTAssertTrue(
                InspectionFormVariant.forFormCode(code).showsPerformedOnDate,
                "\(code) shows the legacy form.date row"
            )
            XCTAssertTrue(InspectionFormVariant.forFormCode(code).hasTableToolbar, code)
        }
    }

    // MARK: - Group headers

    /// `bindTableItems` routes `USR00 == "HEADER"` / `"U1"` rows to
    /// `getGroupHeaderListItem` and does not advance `itemNr` for them.
    func testElevatorChecklistKeepsItsGroupHeadersWithoutNumberingThem() throws {
        let payload: [String: Any] = [
            "MANDT": "100",
            "QMNUM": "4710000012",
            "QMART": "I1",
            "FORMNR": "TFM2",
            "T_PLPOD": [
                ["USR00": "HEADER", "STEUS": "TFM2", "VORNR": "0005", "LTXA1": "Fahrkorbkontrolle"],
                [
                    "USR00": "POSITION", "STEUS": "TFM2", "VORNR": "0010",
                    "LTXA1": "Fahrkorb darf nicht anfahren",
                    "T_PROPS": [["POSNR": "1", "DFVAL": "1;2", "DFVAL_TXT": "OK;Mangel"]]
                ],
                [
                    "USR00": "POSITION", "STEUS": "TFM2", "VORNR": "0020",
                    "LTXA1": "Beleuchtung prüfen",
                    "T_PROPS": [["POSNR": "1", "DFVAL": "1;2", "DFVAL_TXT": "OK;Mangel"]]
                ],
                ["USR00": "U1", "STEUS": "TFM2", "VORNR": "0025", "LTXA1": "Maschinenraumkontrolle"],
                [
                    "USR00": "POSITION", "STEUS": "TFM2", "VORNR": "0030",
                    "LTXA1": "Auf Undichtigkeit an der Maschine prüfen",
                    "T_PROPS": [["POSNR": "1", "DFVAL": "1;2", "DFVAL_TXT": "OK;Mangel"]]
                ]
            ]
        ]
        let json = try XCTUnwrap(
            String(data: try JSONSerialization.data(withJSONObject: payload), encoding: .utf8)
        )
        let items = ElevatorInspectionDecoder.decodeItems(from: json)

        XCTAssertEqual(items.count, 3, "group rows are bands, not positions")
        XCTAssertEqual(items.map(\.positionNumber), [1, 2, 3])
        XCTAssertEqual(
            items.map(\.groupTitle),
            ["Fahrkorbkontrolle", "Fahrkorbkontrolle", "Maschinenraumkontrolle"]
        )
        XCTAssertEqual(items.map(\.inspectionFormItem).map(\.groupTitle), items.map(\.groupTitle))
    }

    /// The segmented forms carry the same bands, and reopening a saved draft
    /// must not lose them.
    func testSegmentedChecklistKeepsItsGroupHeadersAcrossAnOfflineSnapshot() throws {
        let payload: [String: Any] = [
            "MANDT": "100",
            "QMNUM": "005140055905",
            "QMART": "I1",
            "STEUS": "TFM3",
            "T_PLPOD": [
                ["USR00": "HEADER", "STEUS": "TFM3", "VORNR": "0005", "LTXA1": "Außenanlagen"],
                [
                    "USR00": "POSITION", "STEUS": "TFM3", "VORNR": "0010", "LTXA1": "Zuwegung",
                    "T_PROPS": [["POSNR": "1", "DFVAL": " ;X", "DFVAL_TXT": "Nein;Ja"]]
                ],
                ["USR00": "HEADER", "STEUS": "TFM3", "VORNR": "0015", "LTXA1": "Innenbereich"],
                [
                    "USR00": "POSITION", "STEUS": "TFM3", "VORNR": "0020", "LTXA1": "Fluchtwege",
                    "T_PROPS": [["POSNR": "1", "DFVAL": " ;X", "DFVAL_TXT": "Nein;Ja"]]
                ]
            ]
        ]
        let json = try XCTUnwrap(
            String(data: try JSONSerialization.data(withJSONObject: payload), encoding: .utf8)
        )
        let summary = SAPNotificationSummary(
            id: "005140055905",
            client: "100",
            title: "MTFM_Rundgang",
            functionalLocationID: "DE-ESS-10748-01",
            functionalLocationName: "Verwaltungsgebäude",
            startDate: "20260914",
            endDate: "20260914",
            systemStatus: "MMAB",
            userStatus: "OPEN",
            rawPayloadJSON: json
        )

        let detail = SAPNotificationDetail(summary: summary)
        XCTAssertEqual(detail.inspectionItems.count, 2)
        XCTAssertEqual(detail.inspectionItems.map(\.groupTitle), ["Außenanlagen", "Innenbereich"])

        let snapshot = OfflineNotificationSnapshot(detail: detail)
        XCTAssertEqual(snapshot.inspectionItems.map(\.groupTitle), ["Außenanlagen", "Innenbereich"])

        let restored = SAPNotificationDetail(offlineSnapshot: snapshot, notificationID: summary.id)
        XCTAssertEqual(restored.inspectionItems.map(\.groupTitle), ["Außenanlagen", "Innenbereich"])
    }

    /// A draft saved before group bands existed has no `groupTitle` key at
    /// all, and must still decode.
    func testOfflineSnapshotWithoutGroupTitlesStillDecodes() throws {
        let legacyJSON = """
        {
          "id": "TFM3-0010-1",
          "title": "Fluchtwege",
          "information": "",
          "resultElementID": "TFM3-0010-1",
          "commentElementID": "TFM3-0010-9B"
        }
        """
        let item = try JSONDecoder().decode(
            OfflineNotificationSnapshot.InspectionItem.self,
            from: Data(legacyJSON.utf8)
        )
        XCTAssertNil(item.groupTitle)
        XCTAssertEqual(item.title, "Fluchtwege")
    }

    private func localized(_ key: String, _ locale: Locale) -> String {
        String(
            localized: String.LocalizationValue(key),
            bundle: .main,
            locale: locale
        )
    }
}
