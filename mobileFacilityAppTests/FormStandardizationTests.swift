import XCTest
import CoreGraphics
import PDFKit
@testable import mobileFacilityApp

final class FormStandardizationTests: XCTestCase {
    func testSharedHeaderUsesTheStandardizedFieldOrder() {
        XCTAssertEqual(
            standardFormHeaderFieldOrder,
            [
                .instructorFirstName,
                .instructorLastName,
                .context,
                .coordinator,
                .partnerCompany,
                .instructedPerson,
                .partnerAddress,
                .workDescription,
                .executionStart,
                .executionEnd
            ]
        )
    }

    @MainActor
    func testCoordinatorIsRequiredByBriefingAndSafetyForms() {
        let safetySource = SafetyFormSource(
            contexts: [],
            partners: [],
            instructorFirstName: "Test",
            instructorLastName: "User",
            organizationUnit: ""
        )
        XCTAssertTrue(FirePermitViewModel(source: safetySource).validationIssues.contains(.coordinator))
        XCTAssertTrue(
            ElectricalSafetyViewModel(source: safetySource, existingDraft: nil)
                .validationIssues.contains(.coordinator)
        )

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
        XCTAssertTrue(briefing.validationIssues.contains(.coordinator))
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

    func testFirePermitPDFMatchesFivePageLegacyDocumentStructure() throws {
        let source = SafetyFormSource(
            contexts: [],
            partners: [],
            instructorFirstName: "Ada",
            instructorLastName: "Lovelace",
            organizationUnit: "E.ON"
        )
        var record = FirePermitRecord(source: source, now: Date(timeIntervalSince1970: 0))
        record.context = safetyFormContextFixture
        record.workDescription = "Welding work"

        let artifact = try LegacyFirePermitPDFRenderer().render(record)

        XCTAssertEqual(artifact.fileName, "Feuererlaubnisschein.pdf")
        XCTAssertEqual(pdfPageCount(in: artifact.data), 5)
    }

    func testElectricalSafetyPDFMatchesTwoPageLegacyDocumentStructure() throws {
        let source = SafetyFormSource(
            contexts: [],
            partners: [],
            instructorFirstName: "Ada",
            instructorLastName: "Lovelace",
            organizationUnit: "E.ON"
        )
        var record = ElectricalSafetyDraftPayload(source: source, now: Date(timeIntervalSince1970: 0))
        record.context = safetyFormContextFixture
        record.workplace = "Switch room"
        record.electricalWork = "Inspection"

        let artifact = try LegacyElectricalSafetyPDFRenderer().render(record)

        XCTAssertEqual(artifact.fileName, "Einweisungsformular.pdf")
        XCTAssertEqual(pdfPageCount(in: artifact.data), 2)
    }

    func testSafetyPDFAlwaysIncludesTheLegalCompanyFooter() throws {
        let source = SafetyFormSource(
            contexts: [],
            partners: [],
            instructorFirstName: "Ada",
            instructorLastName: "Lovelace",
            organizationUnit: "External contractor"
        )
        var record = FirePermitRecord(source: source, now: Date(timeIntervalSince1970: 0))
        record.context = safetyFormContextFixture

        let artifact = try LegacyFirePermitPDFRenderer().render(record)
        let text = try XCTUnwrap(PDFDocument(data: artifact.data)?.string)

        XCTAssertTrue(text.contains("Geschäftsführer/Managing Directors"))
        XCTAssertTrue(text.contains("E.ON Service GmbH Sitz/Head Office: Essen"))
        XCTAssertTrue(text.contains("Seite 1 von 5"))
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

    @MainActor
    func testBriefingPDFMatchesFivePageTemplateStructure() throws {
        let briefing = BriefingWorkflowViewModel(
            source: .demo(
                OfflineWorkStore(repository: InMemoryOfflineWorkRepository(), workerID: "test"),
                workerName: "Sudhir Kancherla"
            )
        )
        briefing.selectedBusinessEntityID = "DE-ANR-17705-01"
        briefing.selectedBuildingCode = "GB01"
        briefing.selectedTemplateID = "TFMINSTRUC|I3|A|TFMB_001"
        briefing.coordinator = "Sdfsdfsdfsdf"
        briefing.instructedPerson = "sdfsdfsdfsdf"
        briefing.selectedPartnerID = "1000001"
        briefing.taskDescription = "sdfsdfsdfsdfsdfsdf"

        let dummySignature = Data([0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A])
        briefing.instructorSignature = dummySignature
        briefing.instructedPersonSignature = dummySignature

        let payload = try XCTUnwrap(briefing.makePDFPayload())
        let artifact = try LegacyBriefingPDFRenderer().render(payload)

        XCTAssertEqual(artifact.fileName, "Einweisung.pdf")
        let doc = try XCTUnwrap(PDFDocument(data: artifact.data))
        XCTAssertEqual(doc.pageCount, 5)

        // Page 1: Header, Disclaimer, Signatures, 3-column legal footer
        let p1 = try XCTUnwrap(doc.page(at: 0)?.string)
        XCTAssertTrue(p1.contains("Einweisung von Partnerfirmen"))
        XCTAssertTrue(p1.contains("Einweiser/Abnehmer(E.ON"))
        XCTAssertTrue(p1.contains("Sudhir Kancherla"))
        XCTAssertTrue(p1.contains("e.on"))
        XCTAssertTrue(p1.contains("Benannter Koordinator ggf. SiGeKo gemäß BauStellV:"))
        XCTAssertTrue(p1.contains("Sdfsdfsdfsdf"))
        XCTAssertTrue(p1.contains("Partnerfirma/Auftragnehmer:"))
        XCTAssertTrue(p1.contains("Test Adresse für IT Zwecke"))
        XCTAssertTrue(p1.contains("Eingewiesener:"))
        XCTAssertTrue(p1.contains("sdfsdfsdfsdf"))
        XCTAssertTrue(p1.contains("Leistungs-/Arbeitsort:"))
        XCTAssertTrue(p1.contains("Durchzuführende Arbeiten:"))
        XCTAssertTrue(p1.contains("Ausführung von ... bis... :"))
        XCTAssertTrue(p1.contains("Mit dieser Einweisung werden z. B. die standort- und betriebsspezifischen Gegebenheiten"))
        XCTAssertTrue(p1.contains("Datum, Uhrzeit:"))
        XCTAssertTrue(p1.contains("Einweiser/Abnehmer"))
        XCTAssertTrue(p1.contains("Eingewiesener"))
        XCTAssertTrue(p1.contains("[ X ]Kopie an Eingewiesenen übergeben."))
        XCTAssertTrue(p1.contains("Geschäftsführer/Managing Directors"))
        XCTAssertTrue(p1.contains("E.ON Service GmbH Sitz/Head Office: Essen"))
        XCTAssertTrue(p1.contains("HRB 16297"))
        XCTAssertTrue(p1.contains("Seite 1 von 5"))

        // Page 2: Overview table + Section 1 + Section 2
        let p2 = try XCTUnwrap(doc.page(at: 1)?.string)
        XCTAssertTrue(p2.contains("Nr Aufgaben"))
        XCTAssertTrue(p2.contains("Fachliche und persönliche Eignung"))
        XCTAssertTrue(p2.contains("Notfallmanagement"))
        XCTAssertTrue(p2.contains("Flucht und Rettungswege/Sammelplatz"))
        XCTAssertTrue(p2.contains("Sicherheitskennzeichnung"))
        XCTAssertTrue(p2.contains("Arbeitsplatz/-einrichtung"))
        XCTAssertTrue(p2.contains("Arbeitsaufgabe/-ablauf"))
        XCTAssertTrue(p2.contains("Unfälle"))
        XCTAssertFalse(p2.contains("Sicherheitscheckliste für Erdarbeiten\n"))
        XCTAssertTrue(p2.contains("Nr Aufgaben Durchgeführt Bermerkung"))
        XCTAssertTrue(p2.contains("1.01"))
        XCTAssertTrue(p2.contains("1.02"))
        XCTAssertTrue(p2.contains("Seite 2 von 5"))

        // Page 3: PSA subpositions
        let p3 = try XCTUnwrap(doc.page(at: 2)?.string)
        XCTAssertTrue(p3.contains("Seite 3 von 5"))
        XCTAssertTrue(p3.contains("Schutzbrille"))
        XCTAssertTrue(p3.contains("Schutzhelm"))
        XCTAssertTrue(p3.contains("Sicherheitsschuh"))
        XCTAssertTrue(p3.contains("Gehörschutz"))

        // Page 4: Arbeitsplatz
        let p4 = try XCTUnwrap(doc.page(at: 3)?.string)
        XCTAssertTrue(p4.contains("Seite 4 von 5"))
        XCTAssertTrue(p4.contains("5.01"))

        // Page 5: Erdarbeiten banner + Unfälle
        let p5 = try XCTUnwrap(doc.page(at: 4)?.string)
        XCTAssertTrue(p5.contains("Seite 5 von 5"))
        XCTAssertTrue(p5.contains("Sicherheitscheckliste für Erdarbeiten"))
        XCTAssertTrue(p5.contains("Die Sicherheitscheckliste Erdarbeiten in der Nähe erdverlegter Kabel und Rohrleitungen wurde ausgefüllt."))
        XCTAssertTrue(p5.contains("8.01"))
        XCTAssertTrue(p5.contains("8.02"))
        XCTAssertTrue(p5.contains("8.03"))
    }

    func testBriefingPDFDynamicChecklistRows() throws {
        let dummySignature = Data([0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A])
        let section = BriefingPDFPayload.Section(
            id: "sec-dynamic",
            title: "Dynamischer Abschnitt",
            subtitle: "Wichtiger Hinweis zum dynamischen Abschnitt",
            number: 1,
            items: [
                BriefingPDFPayload.Item(
                    id: "it-1",
                    number: "1.01",
                    rowType: .position,
                    title: "Erste dynamische Aufgabe",
                    answer: .yes(key: "YES", title: "Ja"),
                    comment: "Alles in Ordnung",
                    warningSymbolID: "W001"
                ),
                BriefingPDFPayload.Item(
                    id: "it-2",
                    number: "",
                    rowType: .subposition,
                    title: "Spezifische PSA Unterposition",
                    answer: .no(key: "NO", title: "Nein"),
                    comment: "",
                    warningSymbolID: nil
                )
            ]
        )

        let payload = BriefingPDFPayload(
            planNumber: "TFMB_DYN",
            instructorName: "Max Mustermann",
            organizationUnit: "E.ON Test",
            coordinator: "Anna Koordinator",
            partnerName: "Partner AG",
            partnerAddress: "Musterweg 1, 12345 Stadt",
            instructedPerson: "Jan Arbeiter",
            businessEntity: "DE-TEST-001",
            workLocation: "Gebäude A · Technikraum",
            taskDescription: "Wartung der Klimaanlage",
            startDate: Date(timeIntervalSince1970: 1_700_000_000),
            endDate: Date(timeIntervalSince1970: 1_700_000_000),
            completedAt: Date(timeIntervalSince1970: 1_700_000_000),
            instructorSignature: dummySignature,
            instructedPersonSignature: dummySignature,
            sections: [section]
        )

        let artifact = try LegacyBriefingPDFRenderer().render(payload)
        let doc = try XCTUnwrap(PDFDocument(data: artifact.data))
        XCTAssertEqual(doc.pageCount, 2)

        let p2 = try XCTUnwrap(doc.page(at: 1)?.string)
        XCTAssertTrue(p2.contains("Dynamischer Abschnitt"))
        XCTAssertTrue(p2.contains("Wichtiger Hinweis zum dynamischen Abschnitt"))
        XCTAssertTrue(p2.contains("Erste dynamische Aufgabe"))
        XCTAssertTrue(p2.contains("Spezifische PSA Unterposition"))
        XCTAssertTrue(p2.contains("Alles in Ordnung"))
        XCTAssertTrue(p2.contains("Seite 2 von 2"))
    }

    func testSAPBriefingTemplateSectionSubtitlePreservation() {
        let section = SAPBriefingTemplateSection(
            id: "0010",
            title: "Fachliche Eignung",
            subtitle: "Wichtige Erläuterung",
            isOptional: false,
            items: []
        )
        XCTAssertEqual(section.subtitle, "Wichtige Erläuterung")
    }

    private var safetyFormContextFixture: SafetyFormContext {
        SafetyFormContext(
            businessEntityID: "BE-1",
            businessEntityTitle: "Essen",
            buildingCode: "GB01",
            buildingTitle: "Main building",
            functionalLocationID: "DE-ESS-001",
            functionalLocationTitle: "Switch room"
        )
    }

    private func pdfPageCount(in data: Data) -> Int? {
        guard let provider = CGDataProvider(data: data as CFData),
              let document = CGPDFDocument(provider) else {
            return nil
        }
        return document.numberOfPages
    }
}
