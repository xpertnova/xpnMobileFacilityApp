import XCTest
@testable import mobileFacilityApp

final class FormStandardizationTests: XCTestCase {
    func testSharedHeaderUsesTheStandardizedFieldOrder() {
        XCTAssertEqual(
            standardFormHeaderFieldOrder,
            [
                .instructorFirstName,
                .instructorLastName,
                .partnerCompany,
                .instructedPerson,
                .partnerAddress,
                .context,
                .workDescription,
                .executionStart,
                .executionEnd
            ]
        )
    }

    func testGermanPDFDateRangeUsesDateAndTwentyFourHourTime() throws {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = .current
        let from = try XCTUnwrap(calendar.date(from: DateComponents(year: 2026, month: 1, day: 2, hour: 13, minute: 45)))
        let to = try XCTUnwrap(calendar.date(from: DateComponents(year: 2026, month: 1, day: 3, hour: 8, minute: 5)))

        XCTAssertEqual(
            StandardFormPDFHeaderRenderer.formattedRange(from: from, to: to),
            "02.01.2026 13:45 - 03.01.2026 08:05"
        )
    }

    func testPDFArtifactProvidesRawBase64ForSAPDocumentUpload() throws {
        let pdfData = Data([0x25, 0x50, 0x44, 0x46])
        let artifact = BriefingPDFArtifact(
            data: pdfData,
            fileName: "form.pdf",
            createdAt: Date(timeIntervalSince1970: 0)
        )

        XCTAssertEqual(artifact.base64EncodedString, pdfData.base64EncodedString())
        XCTAssertFalse(artifact.base64EncodedString.hasPrefix("data:"))
        XCTAssertEqual(Data(base64Encoded: artifact.base64EncodedString), pdfData)
        XCTAssertEqual(
            artifact.uploadPayload,
            FormPDFUploadPayload(
                fileName: "form.pdf",
                mimeType: "application/pdf",
                base64Content: "JVBERg=="
            )
        )
    }

    func testLockedSignatureRequirementUsesTheLocalizedSignerFieldLabel() {
        let requirement = SignatureInputRequirement(
            signerName: " \n",
            requiredNameField: "System responsible person"
        )

        XCTAssertFalse(requirement.isSigningEnabled)
        XCTAssertEqual(requirement.requiredNameField, "System responsible person")
        XCTAssertEqual(
            requirement.lockedMessage,
            String(
                format: String(localized: "signature.prerequisite.prompt"),
                locale: .current,
                "System responsible person"
            )
        )
    }

    func testNamedSignatureRequirementEnablesSigning() {
        let requirement = SignatureInputRequirement(
            signerName: "Ava Technician",
            requiredNameField: "System responsible person"
        )

        XCTAssertTrue(requirement.isSigningEnabled)
        XCTAssertNil(requirement.lockedMessage)
    }

    func testSafetySignatureSlotsUseTheirCorrespondingNameFields() {
        XCTAssertEqual(
            ElectricalSafetySignatureSlot.handoverSystemResponsible.signerNameFieldKey,
            "electricalSafety.systemResponsible"
        )
        XCTAssertEqual(
            ElectricalSafetySignatureSlot.returnWorkResponsible.signerNameFieldKey,
            "electricalSafety.workResponsible"
        )
        XCTAssertEqual(
            FirePermitSignatureSlot.fireHazardMeasures.signerNameFieldKey,
            "firePermit.measurePerformedBy"
        )
        XCTAssertEqual(
            FirePermitSignatureSlot.permitIssuer.signerNameFieldKey,
            "firePermit.permitIssuer"
        )
        XCTAssertEqual(
            FirePermitSignatureSlot.onSiteWorker.signerNameFieldKey,
            "firePermit.onSiteWorkerConfirmation"
        )
    }

    @MainActor
    func testAllFourFormsRejectMissingWorkLocation() {
        let safetySource = SafetyFormSource(
            contexts: [],
            partners: [],
            instructorFirstName: "Test",
            instructorLastName: "User",
            organizationUnit: "Stored only"
        )
        let fire = FirePermitViewModel(source: safetySource)
        let electrical = ElectricalSafetyViewModel(source: safetySource, existingDraft: nil)
        let qualification = ProofOfQualificationViewModel(
            source: ProofOfQualificationSource(
                isDemo: false,
                contexts: [],
                partners: [],
                template: nil,
                instructorFirstName: "Test",
                instructorLastName: "User",
                organizationUnit: "Stored only"
            )
        )
        let store = OfflineWorkStore(repository: InMemoryOfflineWorkRepository(), workerID: "test")
        let briefing = BriefingWorkflowViewModel(
            source: .init(
                isDemo: false,
                contexts: [],
                partners: [],
                templates: [],
                workerProfile: nil,
                workerName: "Test User",
                offlineWorkStore: store
            )
        )

        XCTAssertTrue(fire.validationIssues.contains(.context))
        XCTAssertTrue(electrical.validationIssues.contains(.context))
        XCTAssertTrue(qualification.validationIssues.contains(.context))
        XCTAssertFalse(briefing.canComplete)
        XCTAssertTrue(briefing.validationIssues.contains(.building))
    }

    @MainActor
    func testAllFourFormsExposeSeparateInstructorNamesWhileKeepingPDFNamesCombined() {
        let safetySource = SafetyFormSource(
            contexts: [],
            partners: [],
            instructorFirstName: "Ada",
            instructorLastName: "Lovelace",
            organizationUnit: "Facility management"
        )
        let fire = FirePermitViewModel(source: safetySource)
        let electrical = ElectricalSafetyViewModel(source: safetySource, existingDraft: nil)
        let qualification = ProofOfQualificationViewModel(
            source: ProofOfQualificationSource(
                isDemo: false,
                contexts: [],
                partners: [],
                template: nil,
                instructorFirstName: "Ada",
                instructorLastName: "Lovelace",
                organizationUnit: "Facility management"
            )
        )
        let briefing = BriefingWorkflowViewModel(
            source: .init(
                isDemo: false,
                contexts: [],
                partners: [],
                templates: [],
                workerProfile: SAPWorkerProfile(
                    personnelNumber: "42",
                    firstName: "Ada",
                    lastName: "Lovelace",
                    organizationUnit: "Facility management",
                    role: "",
                    email: "",
                    isActive: "X",
                    roleCode: ""
                ),
                workerName: "Ignored fallback",
                offlineWorkStore: OfflineWorkStore(
                    repository: InMemoryOfflineWorkRepository(),
                    workerID: "test"
                )
            )
        )

        XCTAssertEqual(safetySource.instructorFirstName, "Ada")
        XCTAssertEqual(safetySource.instructorLastName, "Lovelace")
        XCTAssertEqual(fire.record.instructorName, "Ada Lovelace")
        XCTAssertEqual(electrical.draft.instructorName, "Ada Lovelace")
        XCTAssertEqual(qualification.instructorFirstName, "Ada")
        XCTAssertEqual(qualification.instructorLastName, "Lovelace")
        XCTAssertEqual(qualification.instructorName, "Ada Lovelace")
        XCTAssertEqual(briefing.instructorFirstName, "Ada")
        XCTAssertEqual(briefing.instructorLastName, "Lovelace")
        XCTAssertEqual(briefing.instructorName, "Ada Lovelace")
    }

    @MainActor
    func testMovingDateFromForwardMovesDateToInEveryForm() {
        let source = SafetyFormSource(
            contexts: [],
            partners: [],
            instructorFirstName: "Test",
            instructorLastName: "User",
            organizationUnit: ""
        )
        let later = Date(timeIntervalSince1970: 2_000)

        let fire = FirePermitViewModel(source: source)
        fire.record.executionEnd = Date(timeIntervalSince1970: 1_000)
        fire.setExecutionStart(later)
        XCTAssertEqual(fire.record.executionEnd, later)

        let electrical = ElectricalSafetyViewModel(source: source, existingDraft: nil)
        electrical.draft.executionEnd = Date(timeIntervalSince1970: 1_000)
        electrical.setExecutionStart(later)
        XCTAssertEqual(electrical.draft.executionEnd, later)

        let qualification = ProofOfQualificationViewModel(
            source: ProofOfQualificationSource(
                isDemo: false,
                contexts: [],
                partners: [],
                template: nil,
                instructorFirstName: "Test",
                instructorLastName: "User",
                organizationUnit: ""
            )
        )
        qualification.executionEnd = Date(timeIntervalSince1970: 1_000)
        qualification.setExecutionStart(later)
        XCTAssertEqual(qualification.executionEnd, later)

        let briefing = BriefingWorkflowViewModel(
            source: .init(
                isDemo: false,
                contexts: [],
                partners: [],
                templates: [],
                workerProfile: nil,
                workerName: "Test User",
                offlineWorkStore: OfflineWorkStore(
                    repository: InMemoryOfflineWorkRepository(),
                    workerID: "test"
                )
            )
        )
        briefing.endDate = Date(timeIntervalSince1970: 1_000)
        briefing.setStartDate(later)
        XCTAssertEqual(briefing.endDate, later)
    }
}
