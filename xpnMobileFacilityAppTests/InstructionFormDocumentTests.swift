import XCTest
@testable import mobileFacilityApp

/// Standard documents an instruction form sends with its report when the
/// technician answered "Ja" on a position that points at one
/// (`_additionalDocs` / `_insertDocument` of `InstructFormCreate`).
final class InstructionFormDocumentTests: XCTestCase {

    // MARK: Catalogue

    func testEverySymbolMapsToItsLegacyDocumentNumber() {
        for symbol in ["1", "2", "3", "4", "5", "6", "7"] {
            XCTAssertEqual(
                BriefingReferenceDocument(symbolID: symbol)?.documentNumber,
                "DOKNR\(symbol)"
            )
        }
        XCTAssertNil(BriefingReferenceDocument(symbolID: "8"))
        XCTAssertNil(BriefingReferenceDocument(symbolID: nil))
    }

    /// `_pdfData4Open` spells the second document differently from the title
    /// the app shows, and SAP receives the legacy spelling.
    func testSecondDocumentKeepsTheLegacyDescriptionForSAP() {
        let document = BriefingReferenceDocument(symbolID: "2")

        XCTAssertEqual(document?.title, "Sicherheits-, Ordnungs-, Energie- und Umweltvorschriften")
        XCTAssertEqual(document?.sapDescription, "Sicherheits-,Ordnung-,Energie- und Umweltvorschriften")
        XCTAssertEqual(BriefingReferenceDocument(symbolID: "3")?.sapDescription, "Sicherheits-Checkliste")
    }

    // MARK: Collecting the answered positions

    private let yesNo = [
        SAPBriefingAnswerOption(key: "NO", title: "Nein"),
        SAPBriefingAnswerOption(key: "YES", title: "Ja")
    ]

    private func item(_ id: String, document: String?) -> SAPBriefingTemplateItem {
        SAPBriefingTemplateItem(
            id: id, orderIdentifier: id, rowType: .position, title: id,
            answerOptions: yesNo, documentSymbolID: document, warningSymbolID: nil
        )
    }

    private func section(
        _ id: String,
        optional: Bool = false,
        _ items: [SAPBriefingTemplateItem]
    ) -> SAPBriefingTemplateSection {
        SAPBriefingTemplateSection(id: id, title: id, isOptional: optional, items: items)
    }

    func testOnlyPositionsAnsweredYesContributeTheirDocument() {
        let sections = [
            section("0010", [
                item("a", document: "2"),
                item("b", document: "3"),
                item("c", document: nil)
            ])
        ]

        let symbols = InstructionFormReferenceDocuments.symbolIDs(
            sections: sections,
            answerKeysByItemID: ["a": "YES", "b": "NO", "c": "YES"]
        )

        XCTAssertEqual(symbols, ["2"])
    }

    func testUnansweredAndUnknownSymbolsAreIgnored() {
        let sections = [section("0010", [item("a", document: "9"), item("b", document: "3")])]

        XCTAssertEqual(
            InstructionFormReferenceDocuments.symbolIDs(
                sections: sections,
                answerKeysByItemID: ["a": "YES"]
            ),
            []
        )
    }

    /// An optional section the technician did not take never becomes a
    /// position, so its documents are not sent either.
    func testOptionalSectionsNotTakenContributeNothing() {
        let sections = [
            section("0010", [item("a", document: "2")]),
            section("0090", optional: true, [item("b", document: "5")])
        ]
        let answers = ["a": "YES", "b": "YES"]

        XCTAssertEqual(
            InstructionFormReferenceDocuments.symbolIDs(
                sections: sections, answerKeysByItemID: answers,
                selectedOptionalSectionIDs: []
            ),
            ["2"]
        )
        XCTAssertEqual(
            InstructionFormReferenceDocuments.symbolIDs(
                sections: sections, answerKeysByItemID: answers,
                selectedOptionalSectionIDs: ["0090"]
            ),
            ["2", "5"]
        )
    }

    /// The legacy loop pushes one entry per answered position and never
    /// deduplicates, so two positions sharing a document send two rows.
    func testTwoPositionsSharingADocumentSendItTwice() {
        let sections = [section("0010", [item("a", document: "2"), item("b", document: "2")])]

        XCTAssertEqual(
            InstructionFormReferenceDocuments.symbolIDs(
                sections: sections,
                answerKeysByItemID: ["a": "YES", "b": "YES"]
            ),
            ["2", "2"]
        )
    }

    /// SAP may deliver its own keys; the control stores the affirmative one
    /// of the pair, whatever it is called.
    func testAffirmativeKeyIsTakenFromTheItemsOwnOptions() {
        let options = [
            SAPBriefingAnswerOption(key: "N", title: "Nein"),
            SAPBriefingAnswerOption(key: "J", title: "Ja")
        ]
        let sections = [section("0010", [
            SAPBriefingTemplateItem(
                id: "a", orderIdentifier: "a", rowType: .position, title: "a",
                answerOptions: options, documentSymbolID: "4", warningSymbolID: nil
            )
        ])]

        XCTAssertEqual(
            InstructionFormReferenceDocuments.symbolIDs(sections: sections, answerKeysByItemID: ["a": "J"]),
            ["4"]
        )
        XCTAssertEqual(
            InstructionFormReferenceDocuments.symbolIDs(sections: sections, answerKeysByItemID: ["a": "N"]),
            []
        )
    }

    // MARK: Upload rows

    /// `electricalSafety` is the one form that needs no plan positions, which
    /// keeps the fixture small; the reference rows are built the same way for
    /// every I3 form.
    private func batch(symbolIDs: [String]) throws -> SAPNotificationOutgoingBatch {
        let input = I3NotificationInput(
            form: .electricalSafety,
            workItemID: UUID(uuidString: "3F2504E0-4F89-11D3-9A0C-0305E82C3301")!,
            functionalLocationID: "DE-SAF-11152-10", instructedPerson: "Muster",
            coordinator: "Koordinator", task: "Arbeit",
            start: Date(timeIntervalSince1970: 1_700_000_000),
            end: Date(timeIntervalSince1970: 1_700_086_400),
            partner: .none, partnerEmail: "", selectedOptionalSectionIDs: [],
            pdfData: Data("%PDF-1.4".utf8),
            completedAt: Date(timeIntervalSince1970: 1_700_000_000),
            additionalDocumentSymbolIDs: symbolIDs
        )
        let context = I3NotificationLegacyContext(
            templateJSON: nil,
            functionalLocationJSON: #"{"STRNO":"DE-SAF-11152-10","IWERK":"1000","MANDT2":"100"}"#,
            planPositionsJSON: nil, partnerJSON: nil,
            userJSON: #"{"PERSNR":"S50828"}"#
        )
        return try SAPI3NotificationUploadBuilder.build(
            input: input, context: context, syncUserID: "S50828"
        )
    }

    func testNoReferenceRowsWhenNoPositionAskedForADocument() throws {
        let batch = try batch(symbolIDs: [])

        XCTAssertTrue(batch.i3DocumentReferences.isEmpty)
        XCTAssertEqual(batch.i3Documents.count, 1, "the form's own report is still there")
    }

    func testReferenceRowCarriesTheDocumentNumberAndNoContent() throws {
        let batch = try batch(symbolIDs: ["3"])

        XCTAssertEqual(batch.i3DocumentReferences.count, 1)
        let reference = try XCTUnwrap(batch.i3DocumentReferences.first)
        XCTAssertTrue(reference.referencesExistingDocument)
        XCTAssertTrue(reference.data.isEmpty, "SAP resolves the file from its own DMS")
        let row = reference.metadata
        XCTAssertEqual(row["DOKNR"], "DOKNR3")
        XCTAssertEqual(row["DESCRIPTION"], "Sicherheits-Checkliste")
        XCTAssertEqual(row["DOKOB"], "SMQMEL")
        XCTAssertEqual(row["DOKAR"], "FMD")
        XCTAssertEqual(row["DOC_TYPE"], "PDF")
        XCTAssertEqual(row["DOC_MIMETYPE"], "application/pdf")
        XCTAssertEqual(row["OBJKY"], row["QMNUM"])
        XCTAssertEqual(row["MANDT2"], "100", "the document belongs to the notification's client")
        XCTAssertEqual(row["NAME"]?.hasPrefix("DOKNR3_"), true)
    }

    /// The form's own report keeps its bytes; the references are a separate
    /// list so only they are exempt from the empty-content guard.
    func testTheFormsOwnReportKeepsItsBytes() throws {
        let batch = try batch(symbolIDs: ["2", "5"])

        XCTAssertEqual(batch.i3Documents.first?.metadata["MANDT2"], "100")
        XCTAssertEqual(batch.i3Documents.count, 1)
        XCTAssertEqual(batch.i3Documents.first?.data, Data("%PDF-1.4".utf8))
        XCTAssertEqual(batch.i3Documents.first?.referencesExistingDocument, false)
        XCTAssertEqual(batch.i3DocumentReferences.count, 2)
        XCTAssertTrue(batch.i3DocumentReferences.allSatisfy(\.referencesExistingDocument))
    }

    func testEachReferenceGetsItsOwnStableDocumentID() throws {
        let first = try batch(symbolIDs: ["2", "2"])
        let again = try batch(symbolIDs: ["2", "2"])

        let ids = first.i3DocumentReferences.compactMap { $0.metadata["DOCID"] }
        XCTAssertEqual(Set(ids).count, 2, "a retry must replace its own rows, not merge them")
        XCTAssertEqual(ids, again.i3DocumentReferences.compactMap { $0.metadata["DOCID"] })
        XCTAssertFalse(ids.contains(where: { $0.isEmpty }))
    }

    // MARK: Stored drafts

    /// Briefings saved before instruction documents were sent must still
    /// decode; the key is simply absent.
    func testBriefingDraftWithoutTheNewKeyStillDecodes() throws {
        var payload = BriefingDraftPayload(
            templateID: "TFMINSTRUC|I3|A|TFMB_001", businessEntityID: "11152",
            businessEntityTitle: "WE", buildingCode: "10", buildingTitle: "GE",
            coordinator: "K", instructedPerson: "P", selectedPartnerID: "1000001",
            temporaryPartner: nil, partnerEmail: "", taskDescription: "T",
            startDate: Date(timeIntervalSince1970: 1_700_000_000),
            endDate: Date(timeIntervalSince1970: 1_700_086_400),
            selectedOptionalSectionIDs: [], answerKeysByItemID: [:],
            commentsByItemID: [:], instructorSignature: nil,
            instructedPersonSignature: nil, completedAt: nil
        )
        payload.additionalDocumentSymbolIDs = ["2"]

        let encoded = try JSONEncoder().encode(payload)
        var json = try XCTUnwrap(
            JSONSerialization.jsonObject(with: encoded) as? [String: Any]
        )
        XCTAssertNotNil(json["additionalDocumentSymbolIDs"])

        json.removeValue(forKey: "additionalDocumentSymbolIDs")
        let legacy = try JSONSerialization.data(withJSONObject: json)
        let decoded = try JSONDecoder().decode(BriefingDraftPayload.self, from: legacy)

        XCTAssertNil(decoded.additionalDocumentSymbolIDs)
    }
}
