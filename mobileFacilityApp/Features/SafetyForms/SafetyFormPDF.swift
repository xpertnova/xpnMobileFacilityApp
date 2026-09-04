import Foundation
import UIKit

enum SafetyFormPDFError: Error {
    case missingContext
    case emptyDocument
}

struct LegacyElectricalSafetyPDFRenderer: Sendable {
    func render(_ record: ElectricalSafetyDraftPayload) throws -> BriefingPDFArtifact {
        guard let context = record.context else { throw SafetyFormPDFError.missingContext }
        let page = CGRect(x: 0, y: 0, width: 595, height: 842)
        let renderer = UIGraphicsPDFRenderer(bounds: page)
        let data = renderer.pdfData { pdf in
            pdf.beginPage()
            var y = StandardFormPDFHeaderRenderer.draw(
                StandardFormPDFHeaderData(
                    documentTitle: "Einweisungsformular nur für Dienstleistungen\nArbeiten an, in oder in der Nähe von elektrischen Anlagen",
                    instructorName: record.instructorName,
                    coordinator: record.coordinator,
                    partnerName: record.partner?.name ?? "",
                    partnerAddress: record.partner?.address ?? "",
                    instructedPerson: record.instructedPerson,
                    workLocation: [context.businessEntityTitle, context.buildingTitle, context.functionalLocationTitle]
                        .filter { !$0.isEmpty }
                        .joined(separator: "\n"),
                    workDescription: record.workDescription,
                    dateFrom: record.executionStart,
                    dateTo: record.executionEnd
                ),
                in: pdf.cgContext,
                pageWidth: page.width,
                margin: 30,
                startY: 30
            ) + 10
            draw("Arbeitsplatz: \(record.workplace)", at: &y, font: .systemFont(ofSize: 10), page: page)
            draw("Elektrotechnische Arbeiten: \(record.electricalWork)", at: &y, font: .systemFont(ofSize: 10), page: page)
            draw("Anlagenverantwortlicher: \(record.systemResponsible.name) (\(record.systemResponsible.company))", at: &y, font: .systemFont(ofSize: 10), page: page)
            draw("Arbeitsverantwortlicher: \(record.workResponsible.name) (\(record.workResponsible.company))", at: &y, font: .systemFont(ofSize: 10), page: page)

            draw("\nGeplante Arbeitsmethoden (entsprechend VDE 0705-100):", at: &y, font: .boldSystemFont(ofSize: 11), page: page)
            draw("[ \(record.workDeEnergized ? "X" : " ") ] Arbeiten im spannungsfreien Zustand", at: &y, font: .systemFont(ofSize: 10), page: page)
            draw("[ \(record.workLive ? "X" : " ") ] Arbeiten unter Spannung", at: &y, font: .systemFont(ofSize: 10), page: page)
            draw("[ \(record.workNearLiveParts ? "X" : " ") ] Arbeiten in der Nähe unter Spannung stehender Teile", at: &y, font: .systemFont(ofSize: 10), page: page)

            draw("\nEinweisung erfolgt an:", at: &y, font: .boldSystemFont(ofSize: 11), page: page)
            draw("[ \(record.instructedWorkResponsible ? "X" : " ") ] Arbeitsverantwortlicher", at: &y, font: .systemFont(ofSize: 10), page: page)
            draw("[ \(record.instructedAdditionalWorkers ? "X" : " ") ] zusätzliche Arbeitskräfte", at: &y, font: .systemFont(ofSize: 10), page: page)
            draw("Stichworte und zusätzliche Hinweise: \(record.instructionNotes)", at: &y, font: .systemFont(ofSize: 10), page: page)

            signatureStage(
                "Erteilung der DE und Bestätigung der Einweisung",
                date: record.handoverDate,
                slots: [.handoverSystemResponsible, .handoverWorkResponsible],
                record: record,
                pdf: pdf,
                y: &y,
                page: page
            )
            signatureStage(
                "Rückgabe der DE",
                date: record.returnDate,
                slots: [.returnSystemResponsible, .returnWorkResponsible],
                record: record,
                pdf: pdf,
                y: &y,
                page: page
            )
        }
        guard !data.isEmpty else { throw SafetyFormPDFError.emptyDocument }
        return BriefingPDFArtifact(data: data, fileName: "Einweisungsformular.pdf", createdAt: record.completedAt ?? .now)
    }

    private func signatureStage(
        _ title: String,
        date: Date,
        slots: [ElectricalSafetySignatureSlot],
        record: ElectricalSafetyDraftPayload,
        pdf: UIGraphicsPDFRendererContext,
        y: inout CGFloat,
        page: CGRect
    ) {
        ensureSpace(210, pdf: pdf, y: &y)
        draw("\n\(title)", at: &y, font: .boldSystemFont(ofSize: 11), page: page)
        draw("Datum/Uhrzeit: \(dateTime(date))", at: &y, font: .systemFont(ofSize: 10), page: page)
        for slot in slots {
            ensureSpace(105, pdf: pdf, y: &y)
            let label = slot == .handoverSystemResponsible || slot == .returnSystemResponsible
                ? "Anlagenverantwortlicher"
                : "Arbeitsverantwortlicher"
            draw(label, at: &y, font: .systemFont(ofSize: 10), page: page)
            if let signature = record.signatures[slot] {
                drawSignature(signature.pngData, at: &y, page: page)
            } else {
                y += 78
            }
        }
    }

    private func ensureSpace(_ height: CGFloat, pdf: UIGraphicsPDFRendererContext, y: inout CGFloat) {
        if y + height > 800 {
            pdf.beginPage()
            y = 30
        }
    }

    private func draw(_ value: String, at y: inout CGFloat, font: UIFont, page: CGRect, centered: Bool = false) {
        let rect = CGRect(x: 30, y: y, width: page.width - 60, height: 300)
        let style = NSMutableParagraphStyle()
        style.alignment = centered ? .center : .left
        style.lineBreakMode = .byWordWrapping
        let attributes: [NSAttributedString.Key: Any] = [.font: font, .paragraphStyle: style]
        (value as NSString).draw(in: rect, withAttributes: attributes)
        y += max(18, ceil((value as NSString).boundingRect(
            with: CGSize(width: rect.width, height: .greatestFiniteMagnitude),
            options: [.usesLineFragmentOrigin, .usesFontLeading],
            attributes: attributes,
            context: nil
        ).height) + 8)
    }

    private func drawSignature(_ data: Data, at y: inout CGFloat, page: CGRect) {
        guard let image = UIImage(data: data), image.size.width > 0, image.size.height > 0 else { y += 78; return }
        let rect = CGRect(x: 30, y: y, width: page.width - 60, height: 70)
        let scale = min(rect.width / image.size.width, rect.height / image.size.height)
        let size = CGSize(width: image.size.width * scale, height: image.size.height * scale)
        image.draw(in: CGRect(x: rect.midX - size.width / 2, y: rect.midY - size.height / 2, width: size.width, height: size.height))
        y += 78
    }

    private func dateTime(_ value: Date) -> String {
        value.formatted(.dateTime.locale(Locale(identifier: "de_DE")).day().month().year().hour().minute())
    }
}

struct LegacyFirePermitPDFRenderer: Sendable {
    private struct Row { let label: String; let value: String }
    private struct Section { let title: String; let rows: [Row] }

    func render(_ record: FirePermitRecord) throws -> BriefingPDFArtifact {
        guard let context = record.context else { throw SafetyFormPDFError.missingContext }
        let yesNo: (FirePermitMeasure) -> String = { record.measures[$0, default: false] ? "Ja" : "Nein" }
        let dash: (String) -> String = { $0.trimmed.isEmpty ? "-" : $0 }
        let date: (Date) -> String = { $0.formatted(.dateTime.locale(Locale(identifier: "de_DE")).day().month().year()) }
        let dateTime: (Date) -> String = { $0.formatted(.dateTime.locale(Locale(identifier: "de_DE")).day().month().year().hour().minute()) }
        let workTypeLabels: [FirePermitWorkType: String] = [
            .weldingCutting: "Schweißen, Schneiden und verwandte Verfahren",
            .grinding: "Trennschleifen",
            .soldering: "Löten",
            .thawing: "Auftauen",
            .hotGlue: "Heißklebearbeiten"
        ]
        let measureLabels = Self.measureLabels
        let workTypes = FirePermitWorkType.allCases.filter(record.workTypes.contains).compactMap { workTypeLabels[$0] }
            + (record.hasOtherWorkType ? ["Sonstiges: \(dash(record.otherWorkType))"] : [])

        func measureRows(_ measures: [FirePermitMeasure]) -> [Row] {
            measures.map { Row(label: measureLabels[$0] ?? $0.rawValue, value: yesNo($0)) }
        }

        let sections: [Section] = [
            Section(title: "1. Arbeitsort/-stelle", rows: [
                Row(label: "Art", value: workTypes.joined(separator: ", ").isEmpty ? "-" : workTypes.joined(separator: ", ")),
                Row(label: "Geschäftseinheit", value: context.businessEntityTitle),
                Row(label: "Gebäude", value: context.buildingTitle),
                Row(label: "Funktionsort", value: context.functionalLocationTitle),
                Row(label: "Räumliche Ausdehnung um die Arbeitsstelle", value: "Radius: \(dash(record.radiusMetres)) m\nHöhe: \(dash(record.heightMetres)) m\nTiefe: \(dash(record.depthMetres)) m")
            ]),
            Section(title: "2. Arbeitsauftrag (z. B. Träger abtrennen) Arbeitsverfahren", rows: [
                Row(label: "Arbeitsauftrag", value: dash(record.workDescription)),
                Row(label: "Auszuführen von – Name", value: dash(record.onSiteWorkerName))
            ]),
            Section(title: "3. Sicherheitsmaßnahmen bei Brandgefahr", rows:
                measureRows([.removeCombustibles, .removeCombustibleCoverings, .coverFixedCombustibles, .sealOpenings]) + [
                    Row(label: "Sonstiges", value: record.otherFireHazardEnabled ? dash(record.otherFireHazard) : "Nein"),
                    Row(label: "Maßnahme durchgeführt durch – Name", value: dash(record.fireHazardPerformer)),
                    Row(label: "Ausgeführt am", value: date(record.fireHazardCompletedOn))
                ] + measureRows([.water, .foam, .powder, .carbonDioxide, .connectedWaterHose, .waterFilledBucket, .notifyFireBrigade]) + [
                    Row(label: "Sonstiges", value: record.otherExtinguishingEnabled ? dash(record.otherExtinguishing) : "Nein"),
                    Row(label: "Maßnahme durchgeführt durch – Name", value: dash(record.extinguishingPerformer)),
                    Row(label: "Ausgeführt am", value: date(record.extinguishingCompletedOn)),
                    Row(label: measureLabels[.fireAlarmLoopsOutOfService]!, value: yesNo(.fireAlarmLoopsOutOfService)),
                    Row(label: "Maßnahme durchgeführt durch – Name", value: dash(record.fireAlarmPerformer)),
                    Row(label: measureLabels[.fireWatchDuringWork]!, value: yesNo(.fireWatchDuringWork)),
                    Row(label: "Name der Brandwache (Auftragnehmer)", value: dash(record.fireWatchName)),
                    Row(label: measureLabels[.fireWatchAfterWork]!, value: yesNo(.fireWatchAfterWork)),
                    Row(label: "Dauer der Brandwache", value: "\(dash(record.fireWatchDurationHours)) Stunde/n"),
                    Row(label: "Name der Brandwache (Auftragnehmer)", value: dash(record.afterWorkFireWatchName))
                ]
            ),
            Section(title: "4. Sicherheitsmaßnahmen bei Explosionsgefahr", rows:
                measureRows([.removeExplosives, .removePipelineExplosionHazard, .sealFixedContainers, .ventilationMeasures, .gasDetectors]) + [
                    Row(label: "Gaswarngeräte für", value: dash(record.gasDetectorDetails)),
                    Row(label: "Sonstiges", value: record.otherExplosionEnabled ? dash(record.otherExplosion) : "Nein"),
                    Row(label: "Maßnahme durchgeführt durch – Name", value: dash(record.explosionPerformer)),
                    Row(label: "Ausgeführt am", value: date(record.explosionCompletedOn)),
                    Row(label: "Überwachung der Sicherheitsmaßnahmen auf Wirksamkeit", value: dash(record.monitoringContractorName))
                ]
            ),
            Section(title: "5. Alarmierung", rows: [
                Row(label: "Druckknopfmelders", value: dash(record.manualCallPointLocation)),
                Row(label: "Mobil/Telefon", value: dash(record.mobileTelephone)),
                Row(label: "Feuerwehr / Notruf Nr.", value: "(0) 112")
            ]),
            Section(title: "6. Erlaubnis", rows: [
                Row(label: "Auftraggebender Unternehmer (Auftraggeber)", value: dash(record.permitIssuerName)),
                Row(label: "Ausgeführt am", value: date(record.permitIssuedOn)),
                Row(label: "Ausführender Unternehmer (Auftragnehmer)", value: dash(record.contractorName)),
                Row(label: "Ausgeführt am", value: date(record.contractorSignedOn)),
                Row(label: "Information an den Verantwortlichen Ausführenden nach Arbeitsauftrag erfolgt.", value: dash(record.onSiteWorkerName))
            ])
        ]

        let page = CGRect(x: 0, y: 0, width: 595.28, height: 841.89)
        let renderer = UIGraphicsPDFRenderer(bounds: page)
        let data = renderer.pdfData { pdf in
            var y: CGFloat = 28
            var pageNumber = 1

            func startPage(includeStandardHeader: Bool = false) {
                pdf.beginPage()
                if includeStandardHeader {
                    y = StandardFormPDFHeaderRenderer.draw(
                        StandardFormPDFHeaderData(
                            documentTitle: "Erlaubnisschein für feuergefährliche Arbeiten",
                            instructorName: record.instructorName,
                            coordinator: record.coordinator,
                            partnerName: record.partner?.name ?? "",
                            partnerAddress: record.partner?.address ?? "",
                            instructedPerson: record.instructedPerson,
                            workLocation: [context.businessEntityTitle, context.buildingTitle, context.functionalLocationTitle]
                                .filter { !$0.isEmpty }
                                .joined(separator: "\n"),
                            workDescription: record.workDescription,
                            dateFrom: record.executionStart,
                            dateTo: record.executionEnd
                        ),
                        in: pdf.cgContext,
                        pageWidth: page.width,
                        margin: 30,
                        startY: 28
                    ) + 10
                } else {
                    draw("Erlaubnisschein für feuergefährliche Arbeiten", in: CGRect(x: 30, y: 28, width: page.width - 60, height: 28), font: .boldSystemFont(ofSize: 18), color: .systemRed, alignment: .center)
                    y = 70
                }
            }
            func footer() {
                draw("Seite \(pageNumber)", in: CGRect(x: 30, y: page.height - 30, width: page.width - 60, height: 14), font: .italicSystemFont(ofSize: 8), color: .secondaryLabel, alignment: .right)
            }
            func ensure(_ height: CGFloat) {
                if y + height > page.height - 48 {
                    footer(); pageNumber += 1; startPage()
                }
            }
            func row(_ row: Row) {
                let width = page.width - 76
                let labelHeight = textHeight(row.label, width: width, font: .boldSystemFont(ofSize: 9.5))
                let valueHeight = textHeight(row.value, width: width, font: .systemFont(ofSize: 9.5))
                ensure(labelHeight + valueHeight + 16)
                draw(row.label, in: CGRect(x: 38, y: y + 4, width: width, height: labelHeight), font: .boldSystemFont(ofSize: 9.5), color: .label)
                draw(row.value, in: CGRect(x: 38, y: y + labelHeight + 7, width: width, height: valueHeight), font: .systemFont(ofSize: 9.5), color: .label)
                y += labelHeight + valueHeight + 16
            }
            func section(_ section: Section) {
                ensure(28)
                let rect = CGRect(x: 30, y: y, width: page.width - 60, height: 22)
                UIColor.systemGray5.setFill(); UIRectFill(rect)
                draw(section.title, in: rect.insetBy(dx: 8, dy: 4), font: .boldSystemFont(ofSize: 12), color: .label)
                y += 26
                section.rows.forEach(row)
            }
            func signature(_ slot: FirePermitSignatureSlot, _ signature: SafetyFormSignature) {
                ensure(132)
                let rect = CGRect(x: 30, y: y, width: page.width - 60, height: 122)
                UIColor.systemGray3.setStroke(); UIBezierPath(roundedRect: rect, cornerRadius: 4).stroke()
                draw(Self.signatureTitles[slot] ?? slot.rawValue, in: CGRect(x: 40, y: y + 8, width: rect.width - 20, height: 15), font: .boldSystemFont(ofSize: 9.5), color: .label)
                draw("\(signature.signerName) – \(dateTime(signature.capturedAt))", in: CGRect(x: 40, y: y + 25, width: rect.width - 20, height: 15), font: .systemFont(ofSize: 9), color: .secondaryLabel)
                drawSignature(signature.pngData, in: CGRect(x: 40, y: y + 42, width: rect.width - 20, height: 72))
                y += 130
            }

            startPage(includeStandardHeader: true)
            sections.forEach(section)
            section(Section(title: "Unterschriften", rows: []))
            for slot in FirePermitSignatureSlot.allCases {
                if let signatureValue = record.signatures[slot] { signature(slot, signatureValue) }
            }
            footer()
        }
        guard !data.isEmpty else { throw SafetyFormPDFError.emptyDocument }
        return BriefingPDFArtifact(data: data, fileName: "Feuererlaubnisschein.pdf", createdAt: .now)
    }

    private static let measureLabels: [FirePermitMeasure: String] = [
        .removeCombustibles: "Bewegliche brennbare Stoffe, Gegenstände und Staubablagerungen entfernen",
        .removeCombustibleCoverings: "Wand- und Deckenverkleidungen entfernen, soweit sie brennbare Stoffe abdecken oder selbst brennbar sind",
        .coverFixedCombustibles: "Ortsfeste brennbare Stoffe und Gegenstände abdecken und bei Bedarf anfeuchten",
        .sealOpenings: "Öffnungen zu benachbarten Bereichen abdichten",
        .water: "Wasser", .foam: "Schaum", .powder: "Pulver", .carbonDioxide: "CO²",
        .connectedWaterHose: "Angeschlossener Wasserschlauch", .waterFilledBucket: "Wassergefüllter Eimer",
        .notifyFireBrigade: "Feuerwehr benachrichtigen",
        .fireAlarmLoopsOutOfService: "Müssen einzelne Schleifen der Brandmeldeanlage außer Betrieb genommen werden?",
        .fireWatchDuringWork: "Während der feuergefährlichen Arbeiten",
        .fireWatchAfterWork: "Nach Abschluss der feuergefährlichen Arbeiten",
        .removeExplosives: "Explosionsfähige Stoffe und Gegenstände einschließlich Staubablagerungen entfernen",
        .removePipelineExplosionHazard: "Explosionsgefahr in Rohrleitungen beseitigen",
        .sealFixedContainers: "Ortsfeste Behälter, Apparate oder Rohrleitungen abdichten",
        .ventilationMeasures: "Lüftungstechnische Maßnahmen mit messtechnischer Überwachung durchführen",
        .gasDetectors: "Gaswarngeräte aufstellen"
    ]

    private static let signatureTitles: [FirePermitSignatureSlot: String] = [
        .fireHazardMeasures: "3a. Beseitigung der Brandgefahr",
        .extinguishingMedia: "3b. Bereitstellung von Löschmitteln/Feuerlöschern",
        .fireAlarmSystem: "3c. Brandmeldeanlage",
        .explosionHazardMeasures: "4a. Beseitigung der Explosionsgefahr",
        .permitIssuer: "Auftraggebender Unternehmer (Auftraggeber)",
        .contractor: "Ausführender Unternehmer (Auftragnehmer)",
        .onSiteWorker: "Verantwortlicher Ausführender"
    ]

    private func draw(_ value: String, in rect: CGRect, font: UIFont, color: UIColor, alignment: NSTextAlignment = .left) {
        let paragraph = NSMutableParagraphStyle(); paragraph.alignment = alignment; paragraph.lineBreakMode = .byWordWrapping
        (value as NSString).draw(in: rect, withAttributes: [.font: font, .foregroundColor: color, .paragraphStyle: paragraph])
    }

    private func textHeight(_ value: String, width: CGFloat, font: UIFont) -> CGFloat {
        let paragraph = NSMutableParagraphStyle(); paragraph.lineBreakMode = .byWordWrapping
        return ceil((value as NSString).boundingRect(with: CGSize(width: width, height: .greatestFiniteMagnitude), options: [.usesLineFragmentOrigin, .usesFontLeading], attributes: [.font: font, .paragraphStyle: paragraph], context: nil).height)
    }

    private func drawSignature(_ data: Data, in rect: CGRect) {
        guard let image = UIImage(data: data), image.size.width > 0, image.size.height > 0 else { return }
        let scale = min(rect.width / image.size.width, rect.height / image.size.height)
        let size = CGSize(width: image.size.width * scale, height: image.size.height * scale)
        image.draw(in: CGRect(x: rect.midX - size.width / 2, y: rect.midY - size.height / 2, width: size.width, height: size.height))
    }
}

private extension String {
    var trimmed: String { trimmingCharacters(in: .whitespacesAndNewlines) }
}
