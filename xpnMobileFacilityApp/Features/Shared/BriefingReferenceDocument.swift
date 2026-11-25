import Foundation

/// A standard SAP DMS document an instruction-form position can point at,
/// identified by the position's `USR02` symbol (`documentKey` of the legacy
/// `reportTable`).
///
/// Traced from `_pdfData4Open` in `InstructFormCreate.controller.js`. The
/// bundled PDF under `Resources/documents/` is only what the technician reads
/// on the iPad; SAP already holds the document under `documentNumber`, so a
/// form that has to send one posts a reference row and never the bytes.
struct BriefingReferenceDocument: Identifiable {
    let symbolID: String
    let fileName: String
    let title: String
    /// `DOKNR` of the legacy `_insertDocument`.
    let documentNumber: String
    /// `DESCRIPTION` of the `TO_T0302` reference row. It is the legacy
    /// spelling, which differs from `title` for symbol 2, and goes to SAP
    /// exactly as `_pdfData4Open` writes it.
    let sapDescription: String

    var id: String { symbolID }

    init?(symbolID: String?) {
        guard let symbolID else { return nil }
        switch symbolID {
        case "1":
            self.init(symbolID, "EinweisungsDienstleistungen", "Einweisungsformular nur für Dienstleistungen")
        case "2":
            self.init(
                symbolID, "SichOrdnEnerUmwelt",
                "Sicherheits-, Ordnungs-, Energie- und Umweltvorschriften",
                sapDescription: "Sicherheits-,Ordnung-,Energie- und Umweltvorschriften"
            )
        case "3":
            self.init(symbolID, "SicherheitsCheckliste", "Sicherheits-Checkliste")
        case "4":
            self.init(symbolID, "Matrix", "Matrix")
        case "5":
            self.init(symbolID, "GasFeuerLoeschanlage", "Gas-Feuerlöschanlage")
        case "6":
            self.init(symbolID, "Sicherheitsbereich", "Sicherheitsbereich")
        case "7":
            self.init(symbolID, "Qualifikationsnachweis", "Qualifikationsnachweis")
        default:
            return nil
        }
    }

    private init(
        _ symbolID: String,
        _ fileName: String,
        _ title: String,
        sapDescription: String? = nil
    ) {
        self.symbolID = symbolID
        self.fileName = fileName
        self.title = title
        self.documentNumber = "DOKNR\(symbolID)"
        self.sapDescription = sapDescription ?? title
    }
}

/// Collects the standard documents an instruction form has to send with its
/// report.
enum InstructionFormReferenceDocuments {
    /// Legacy `InstructFormCreate._additionalDocs`: while closing, every
    /// position answered "Ja" whose `reportTable` entry carries a
    /// `documentKey` contributes one reference. The legacy loop does not
    /// deduplicate, so two positions pointing at the same document send two
    /// rows, and this keeps that behaviour.
    ///
    /// `selectedOptionalSectionIDs` drops the optional sections the
    /// technician did not take, which the legacy app never writes as
    /// positions in the first place.
    static func symbolIDs(
        sections: [SAPBriefingTemplateSection],
        answerKeysByItemID: [String: String],
        selectedOptionalSectionIDs: Set<String>? = nil
    ) -> [String] {
        sections.flatMap { section -> [String] in
            if let selectedOptionalSectionIDs,
               section.isOptional,
               !selectedOptionalSectionIDs.contains(section.id) {
                return []
            }
            return section.items.compactMap { item in
                guard
                    let symbolID = item.documentSymbolID,
                    BriefingReferenceDocument(symbolID: symbolID) != nil,
                    let answer = answerKeysByItemID[item.id],
                    isAffirmative(answer, in: item)
                else { return nil }
                return symbolID
            }
        }
    }

    /// The answer control only ever stores one of the two normalized keys, so
    /// "Ja" is the affirmative side of that pair — whatever raw key SAP sent.
    private static func isAffirmative(_ answer: String, in item: SAPBriefingTemplateItem) -> Bool {
        item.answerOptions
            .normalizedForLegacyYesNoControl
            .first(where: \.isAffirmativeBriefingAnswer)?
            .key == answer
    }
}
