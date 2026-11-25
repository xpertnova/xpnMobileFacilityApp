import Foundation
import UIKit

enum SafetyFormPDFError: Error {
    case missingContext
    case emptyDocument
}

private enum SafetyPDFCanvas {
    static let page = CGRect(x: 0, y: 0, width: 595.28, height: 841.89)
    static let margin: CGFloat = 25
    static let contentWidth = page.width - margin * 2
    static let blue = UIColor(red: 0.38, green: 0.44, blue: 0.58, alpha: 1)
    static let lightBlue = UIColor(red: 0.39, green: 0.67, blue: 0.86, alpha: 1)
    static let matrixBlue = UIColor(red: 0.27, green: 0.45, blue: 0.76, alpha: 1)
    static let matrixLightBlue = UIColor(red: 0.85, green: 0.89, blue: 0.95, alpha: 1)
    static let matrixSideBlue = UIColor(red: 0.52, green: 0.61, blue: 0.72, alpha: 1)

    static func text(
        _ value: String,
        in rect: CGRect,
        font: UIFont,
        color: UIColor = .black,
        alignment: NSTextAlignment = .left,
        lineBreak: NSLineBreakMode = .byWordWrapping
    ) {
        let paragraph = NSMutableParagraphStyle()
        paragraph.alignment = alignment
        paragraph.lineBreakMode = lineBreak
        (value as NSString).draw(
            with: rect,
            options: [.usesLineFragmentOrigin, .usesFontLeading],
            attributes: [.font: font, .foregroundColor: color, .paragraphStyle: paragraph],
            context: nil
        )
    }

    static func cell(_ rect: CGRect, fill: UIColor = .white, context: CGContext) {
        context.setFillColor(fill.cgColor)
        context.fill(rect)
        context.setStrokeColor(UIColor.black.cgColor)
        context.setLineWidth(0.55)
        context.stroke(rect)
    }

    static func line(from: CGPoint, to: CGPoint, color: UIColor = .black, context: CGContext) {
        context.setStrokeColor(color.cgColor)
        context.setLineWidth(0.55)
        context.move(to: from)
        context.addLine(to: to)
        context.strokePath()
    }

    static func checkbox(_ selected: Bool, at origin: CGPoint, size: CGFloat = 7, context: CGContext) {
        let box = CGRect(origin: origin, size: CGSize(width: size, height: size))
        context.setFillColor(UIColor.white.cgColor)
        context.fill(box)
        context.setStrokeColor(UIColor.black.cgColor)
        context.setLineWidth(0.55)
        context.stroke(box)
        guard selected else { return }
        context.setLineWidth(1)
        context.move(to: CGPoint(x: box.minX + 1.2, y: box.midY))
        context.addLine(to: CGPoint(x: box.midX - 0.2, y: box.maxY - 1.2))
        context.addLine(to: CGPoint(x: box.maxX - 1.1, y: box.minY + 1.1))
        context.strokePath()
    }

    static func radio(_ selected: Bool, at center: CGPoint, context: CGContext) {
        let circle = CGRect(x: center.x - 5, y: center.y - 5, width: 10, height: 10)
        context.setFillColor(UIColor.white.cgColor)
        context.fillEllipse(in: circle)
        context.setStrokeColor(UIColor.black.cgColor)
        context.setLineWidth(0.8)
        context.strokeEllipse(in: circle)
        if selected {
            context.setFillColor(UIColor.black.cgColor)
            context.fillEllipse(in: circle.insetBy(dx: 2.3, dy: 2.3))
        }
    }

    static func signature(_ data: Data?, in rect: CGRect) {
        guard let data, let image = UIImage(data: data), image.size.width > 0, image.size.height > 0 else { return }
        let scale = min(rect.width / image.size.width, rect.height / image.size.height)
        let size = CGSize(width: image.size.width * scale, height: image.size.height * scale)
        image.draw(in: CGRect(x: rect.midX - size.width / 2, y: rect.midY - size.height / 2, width: size.width, height: size.height))
    }

    static func underlinedValue(_ value: String, in rect: CGRect, font: UIFont, context: CGContext) {
        text(value, in: rect.insetBy(dx: 4, dy: 0), font: font, lineBreak: .byTruncatingTail)
        line(from: CGPoint(x: rect.minX, y: rect.maxY), to: CGPoint(x: rect.maxX, y: rect.maxY), context: context)
    }

    static func footer(pageNumber: Int, pageCount: Int, context: CGContext) {
        let y = page.height - 51
        line(from: CGPoint(x: margin, y: y), to: CGPoint(x: page.width - margin, y: y), context: context)
        text(
            "Geschäftsführer/Managing Directors: André Schrödel,\nDr. Marc Stienemann, Peter Olschewski, Zsolt Szabo",
            in: CGRect(x: margin + 5, y: y + 4, width: contentWidth * 0.39, height: 34),
            font: .systemFont(ofSize: 6.4)
        )
        text(
            "E.ON Service GmbH Sitz/Head Office: Essen\nRegistergericht/Registry Court: Essen\nHandelsregisternummer/Commercial Register No.: HRB 16297",
            in: CGRect(x: margin + contentWidth * 0.40, y: y + 4, width: contentWidth * 0.40, height: 34),
            font: .systemFont(ofSize: 6.4)
        )
        text(
            "Seite \(pageNumber) von \(pageCount)",
            in: CGRect(x: page.width - margin - 96, y: y + 5, width: 91, height: 15),
            font: .italicSystemFont(ofSize: 9),
            alignment: .right
        )
    }

    static func date(_ value: Date) -> String { formatter("dd.MM.yyyy").string(from: value) }
    static func dateTime(_ value: Date) -> String { formatter("dd.MM.yyyy HH:mm").string(from: value) }

    private static func formatter(_ format: String) -> DateFormatter {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "de_DE")
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.dateFormat = format
        return formatter
    }
}

struct LegacyElectricalSafetyPDFRenderer: Sendable {
    func render(_ record: ElectricalSafetyDraftPayload) throws -> BriefingPDFArtifact {
        guard let context = record.context else { throw SafetyFormPDFError.missingContext }
        let renderer = UIGraphicsPDFRenderer(bounds: SafetyPDFCanvas.page)
        let data = renderer.pdfData { pdf in
            pdf.beginPage()
            drawFirstPage(record, context: context, pdf: pdf.cgContext)

            pdf.beginPage()
            drawBody(record, context: pdf.cgContext)
            SafetyPDFCanvas.footer(pageNumber: 2, pageCount: 2, context: pdf.cgContext)
        }
        guard !data.isEmpty else { throw SafetyFormPDFError.emptyDocument }
        return BriefingPDFArtifact(data: data, fileName: "Einweisungsformular.pdf", createdAt: record.completedAt ?? .now)
    }

    private func location(_ context: SafetyFormContext) -> String {
        let be = context.businessEntityTitle.isEmpty ? context.businessEntityID : context.businessEntityTitle
        let bld = context.buildingTitle.isEmpty ? context.buildingCode : context.buildingTitle
        let fl = context.functionalLocationTitle.isEmpty ? context.functionalLocationID : context.functionalLocationTitle
        return [be, bld, fl]
            .filter { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
            .joined(separator: "\n")
    }

    private func drawFirstPage(
        _ record: ElectricalSafetyDraftPayload,
        context: SafetyFormContext,
        pdf: CGContext
    ) {
        let margin = SafetyPDFCanvas.margin
        let contentWidth = SafetyPDFCanvas.contentWidth
        var y = margin

        // Title Box
        let title = "Einweisungsformular nur für Dienstleistungen\nArbeiten an, in oder in der Nähe von elektrischen\nAnlagen"
        let titleFont = UIFont.boldSystemFont(ofSize: 18)
        let titleHeight = max(
            52,
            textHeight(title, width: contentWidth - 16, font: titleFont) + 16
        )
        let titleRect = CGRect(x: margin, y: y, width: contentWidth, height: titleHeight)
        SafetyPDFCanvas.cell(titleRect, fill: .white, context: pdf)
        SafetyPDFCanvas.text(
            title,
            in: titleRect.insetBy(dx: 8, dy: 7),
            font: titleFont,
            alignment: .center
        )
        y = titleRect.maxY

        // Row 1: Abnehmer(E.ON Mitarbeiter) | Name | Orgunit
        let r1Col1Width = contentWidth * 0.25
        let r1Col2Width = contentWidth * 0.50
        let r1Col3Width = contentWidth * 0.25
        let r1Label = "Abnehmer(E.ON Mitarbeiter)"
        let orgText = record.organizationUnit.isEmpty ? "e.on" : record.organizationUnit
        let r1Org = "\(orgText)\n(E.ON-Organisationseinheit)"
        let bodyFont = UIFont.systemFont(ofSize: 9.5)
        let r1Height = max(
            36,
            textHeight(r1Label, width: r1Col1Width - 10, font: bodyFont) + 10,
            textHeight(record.instructorName, width: r1Col2Width - 10, font: bodyFont) + 10,
            textHeight(r1Org, width: r1Col3Width - 10, font: bodyFont) + 10
        )
        let r1Rect1 = CGRect(x: margin, y: y, width: r1Col1Width, height: r1Height)
        let r1Rect2 = CGRect(x: r1Rect1.maxX, y: y, width: r1Col2Width, height: r1Height)
        let r1Rect3 = CGRect(x: r1Rect2.maxX, y: y, width: r1Col3Width, height: r1Height)
        SafetyPDFCanvas.cell(r1Rect1, context: pdf)
        SafetyPDFCanvas.cell(r1Rect2, context: pdf)
        SafetyPDFCanvas.cell(r1Rect3, context: pdf)
        SafetyPDFCanvas.text(r1Label, in: r1Rect1.insetBy(dx: 5, dy: 5), font: bodyFont)
        SafetyPDFCanvas.text(record.instructorName, in: r1Rect2.insetBy(dx: 5, dy: 5), font: bodyFont)
        SafetyPDFCanvas.text(r1Org, in: r1Rect3.insetBy(dx: 5, dy: 5), font: bodyFont)
        y += r1Height

        // Rows 2 through 7 (50% / 50% split)
        let labelColWidth = contentWidth * 0.50
        let valueColWidth = contentWidth * 0.50

        let partner = [record.partner?.name, record.partner?.address]
            .compactMap { $0 }
            .filter { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
            .joined(separator: "\n")
        let loc = location(context)
        let dateRange = "\(SafetyPDFCanvas.date(record.executionStart)) - \(SafetyPDFCanvas.date(record.executionEnd))"

        let gridRows: [(String, String)] = [
            ("Benannter Koordinator ggf. SiGeKo gemäß BauStellV:\n(Wird bei gegenseitiger Gefährdung durch den Einweiser/Abnehmer\nbenannt)", record.coordinator),
            ("Partnerfirma/Auftragnehmer:\n(Name und Anschrift)", partner),
            ("Eingewiesener:\n(Verantwortlicher der Partnerfirma für die durchzuführenden Arbeiten)", record.instructedPerson),
            ("Leistungs-/Arbeitsort:", loc),
            ("Durchzuführende Arbeiten:", record.workDescription),
            ("Ausführung von ... bis... :\n(Datum)", dateRange)
        ]

        for (lbl, val) in gridRows {
            let rowHeight = max(
                34,
                textHeight(lbl, width: labelColWidth - 10, font: bodyFont) + 10,
                textHeight(val, width: valueColWidth - 10, font: bodyFont) + 10
            )
            let lblRect = CGRect(x: margin, y: y, width: labelColWidth, height: rowHeight)
            let valRect = CGRect(x: lblRect.maxX, y: y, width: valueColWidth, height: rowHeight)
            SafetyPDFCanvas.cell(lblRect, context: pdf)
            SafetyPDFCanvas.cell(valRect, context: pdf)
            SafetyPDFCanvas.text(lbl, in: lblRect.insetBy(dx: 5, dy: 5), font: bodyFont)
            SafetyPDFCanvas.text(val, in: valRect.insetBy(dx: 5, dy: 5), font: bodyFont)
            y += rowHeight
        }

        SafetyPDFCanvas.footer(pageNumber: 1, pageCount: 2, context: pdf)
    }

    private func drawBody(_ record: ElectricalSafetyDraftPayload, context: CGContext) {
        let x = SafetyPDFCanvas.margin
        let width = SafetyPDFCanvas.contentWidth
        let body = UIFont.systemFont(ofSize: 10)
        let small = UIFont.systemFont(ofSize: 8)

        SafetyPDFCanvas.text("Einweisungsformular", in: CGRect(x: x, y: 25, width: 175, height: 24), font: .boldSystemFont(ofSize: 18), color: SafetyPDFCanvas.blue)
        SafetyPDFCanvas.text("nur für Dienstleistungen", in: CGRect(x: x + 175, y: 25, width: 220, height: 24), font: .boldSystemFont(ofSize: 18), color: SafetyPDFCanvas.lightBlue)
        SafetyPDFCanvas.text("Arbeiten an, in oder in der Nähe von elektrischen Anlagen", in: CGRect(x: x, y: 53, width: width, height: 20), font: .systemFont(ofSize: 14))

        section("Arbeitsstelle", y: 93)
        fieldRow("Arbeitsstelle", value: record.workplace, y: 112)
        fieldRow("Durchzuführende Arbeiten", value: record.electricalWork, y: 146)
        responsible("Anlagenverantwortlicher", person: record.systemResponsible, y: 181)
        responsible("Arbeitsverantwortlicher", person: record.workResponsible, y: 222)

        SafetyPDFCanvas.text("Geplante Arbeitsmethoden", in: CGRect(x: x, y: 260, width: 190, height: 19), font: .systemFont(ofSize: 14), color: SafetyPDFCanvas.blue)
        SafetyPDFCanvas.text("(entsprechend VDE 0705-100)", in: CGRect(x: x + 190, y: 263, width: 200, height: 16), font: body)
        radioRow("Arbeiten im spannungsfreien Zustand", record.workDeEnergized, y: 287)
        radioRow("Arbeiten unter Spannung", record.workLive, y: 311)
        radioRow("Arbeiten in der Nähe unter Spannung stehender Teile", record.workNearLiveParts, y: 335)

        section("Einweisung", y: 373)
        SafetyPDFCanvas.text(
            "Eine Einweisung über die bei der Durchführung der Arbeiten zu beachtenden Verhaltensmaßnamen und Maßnahmen zur Gefahrenabwehr, in Bezug auf die elektrische Gefährdung durch die Anlage und die Anlagenumgebung ist durch den Anlagenveranstwortlichen erfolgt an:",
            in: CGRect(x: x, y: 396, width: width, height: 42),
            font: body
        )
        radioRow("Arbeitsverantwortlicher", record.instructedWorkResponsible, y: 442)
        radioRow("zusätzliche Arbeitskräfte", record.instructedAdditionalWorkers, y: 466)
        SafetyPDFCanvas.text(
            "Stichworte zum Inhalt der Einweisung und zusätzliche Hinweise (zum Beispiel Einbauorte von Arbeitserden, Abstände, Kennzeichen, zusätzliche Sicherheitsmaßnahmen, Telefonnummer der zuständigen Organisationseinheit)",
            in: CGRect(x: x, y: 488, width: width, height: 34),
            font: body
        )
        if !record.instructionNotes.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            SafetyPDFCanvas.text(record.instructionNotes, in: CGRect(x: x + 5, y: 524, width: width - 10, height: 47), font: body)
        }

        signatureStage("Erteilung der DE und Bestätigung der Einweisung", date: record.handoverDate, first: record.signatures[.handoverSystemResponsible]?.pngData, second: record.signatures[.handoverWorkResponsible]?.pngData, y: 548)
        signatureStage("Rückgabe der DE", date: record.returnDate, first: record.signatures[.returnSystemResponsible]?.pngData, second: record.signatures[.returnWorkResponsible]?.pngData, y: 643)

        func section(_ title: String, y: CGFloat) {
            SafetyPDFCanvas.text(title, in: CGRect(x: x, y: y, width: width, height: 19), font: .systemFont(ofSize: 14), color: SafetyPDFCanvas.blue)
        }
        func fieldRow(_ label: String, value: String, y: CGFloat) {
            SafetyPDFCanvas.text(label, in: CGRect(x: x + 5, y: y, width: 140, height: 18), font: body)
            if !value.isEmpty {
                SafetyPDFCanvas.text(value, in: CGRect(x: x + 154, y: y, width: width - 154, height: 18), font: body)
            }
        }
        func responsible(_ label: String, person: ElectricalSafetyDraftPayload.ResponsiblePerson, y: CGFloat) {
            SafetyPDFCanvas.text(label, in: CGRect(x: x + 5, y: y, width: 140, height: 18), font: body)
            let rects = [
                CGRect(x: x + 129, y: y - 1, width: 109, height: 17),
                CGRect(x: x + 252, y: y - 1, width: 169, height: 17),
                CGRect(x: x + 435, y: y - 1, width: 109, height: 17)
            ]
            let values = [person.name, person.company, person.telephone]
            let labels = ["Name", "Firma", "Mobil/Telefon"]
            for index in rects.indices {
                SafetyPDFCanvas.underlinedValue(values[index], in: rects[index], font: body, context: context)
                SafetyPDFCanvas.text(labels[index], in: CGRect(x: rects[index].minX + 5, y: rects[index].maxY + 2, width: rects[index].width, height: 12), font: small)
            }
        }
        func radioRow(_ label: String, _ selected: Bool, y: CGFloat) {
            SafetyPDFCanvas.radio(selected, at: CGPoint(x: x + 10, y: y + 6), context: context)
            SafetyPDFCanvas.text(label, in: CGRect(x: x + 28, y: y - 1, width: width - 28, height: 18), font: body)
        }
        func signatureStage(_ title: String, date: Date, first: Data?, second: Data?, y: CGFloat) {
            SafetyPDFCanvas.text(title, in: CGRect(x: x, y: y, width: width, height: 20), font: .systemFont(ofSize: 14), color: SafetyPDFCanvas.blue)
            let gap: CGFloat = 14
            let column = (width - gap * 2) / 3
            let rects = (0..<3).map { CGRect(x: x + CGFloat($0) * (column + gap), y: y + 28, width: column, height: 40) }
            SafetyPDFCanvas.text(SafetyPDFCanvas.dateTime(date), in: rects[0].insetBy(dx: 5, dy: 5), font: body)
            SafetyPDFCanvas.signature(first, in: rects[1].insetBy(dx: 5, dy: 0))
            SafetyPDFCanvas.signature(second, in: rects[2].insetBy(dx: 5, dy: 0))
            let labels = ["Datum, Uhrzeit", "Anlagenverantwortlicher", "Arbeitsverantwortlicher"]
            for index in rects.indices {
                SafetyPDFCanvas.line(from: CGPoint(x: rects[index].minX, y: rects[index].maxY), to: CGPoint(x: rects[index].maxX, y: rects[index].maxY), context: context)
                SafetyPDFCanvas.text(labels[index], in: CGRect(x: rects[index].minX + 5, y: rects[index].maxY + 2, width: rects[index].width, height: 12), font: small)
            }
        }
    }

    private func textHeight(_ value: String, width: CGFloat, font: UIFont) -> CGFloat {
        guard !value.isEmpty else { return font.lineHeight }
        let paragraph = NSMutableParagraphStyle()
        paragraph.lineBreakMode = .byWordWrapping
        return ceil(
            (value as NSString).boundingRect(
                with: CGSize(width: max(width, 1), height: .greatestFiniteMagnitude),
                options: [.usesLineFragmentOrigin, .usesFontLeading],
                attributes: [.font: font, .paragraphStyle: paragraph],
                context: nil
            ).height
        )
    }
}

struct LegacyFirePermitPDFRenderer: Sendable {
    private let tiny = UIFont.systemFont(ofSize: 6.4)
    private let tinyBold = UIFont.boldSystemFont(ofSize: 6.5)

    func render(_ record: FirePermitRecord) throws -> BriefingPDFArtifact {
        guard let context = record.context else { throw SafetyFormPDFError.missingContext }
        let renderer = UIGraphicsPDFRenderer(bounds: SafetyPDFCanvas.page)
        let data = renderer.pdfData { pdf in
            pdf.beginPage()
            _ = StandardFormPDFHeaderRenderer.draw(
                StandardFormPDFHeaderData(
                    documentTitle: "Erlaubnisschein für feuergefährliche Arbeiten",
                    instructorName: record.instructorName,
                    organizationUnit: record.organizationUnit,
                    coordinator: record.coordinator,
                    partnerName: record.partner?.name ?? "",
                    partnerAddress: record.partner?.address ?? "",
                    instructedPerson: record.instructedPerson,
                    workLocation: location(context),
                    workDescription: record.workDescription,
                    dateFrom: record.executionStart,
                    dateTo: record.executionEnd
                ),
                in: pdf.cgContext,
                pageWidth: SafetyPDFCanvas.page.width,
                margin: SafetyPDFCanvas.margin,
                startY: SafetyPDFCanvas.margin
            )
            footer(1, pdf.cgContext)

            pdf.beginPage()
            drawPermitPage(record, location: context, context: pdf.cgContext)
            footer(2, pdf.cgContext)

            pdf.beginPage()
            drawPermissionPage(record, context: pdf.cgContext)
            footer(3, pdf.cgContext)

            pdf.beginPage()
            drawResponsibilitiesPage(context: pdf.cgContext)
            footer(4, pdf.cgContext)

            pdf.beginPage()
            drawMatrixPage(context: pdf.cgContext)
            footer(5, pdf.cgContext)
        }
        guard !data.isEmpty else { throw SafetyFormPDFError.emptyDocument }
        return BriefingPDFArtifact(data: data, fileName: "Feuererlaubnisschein.pdf", createdAt: .now)
    }

    private func footer(_ page: Int, _ context: CGContext) {
        SafetyPDFCanvas.footer(pageNumber: page, pageCount: 5, context: context)
    }

    private func location(_ context: SafetyFormContext) -> String {
        [context.functionalLocationID, context.businessEntityTitle, context.buildingTitle, context.functionalLocationTitle]
            .filter { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
            .joined(separator: "\n")
    }

    private func drawPermitPage(_ record: FirePermitRecord, location: SafetyFormContext, context: CGContext) {
        let x = SafetyPDFCanvas.margin
        let width = SafetyPDFCanvas.contentWidth

        SafetyPDFCanvas.cell(CGRect(x: x, y: 25, width: width, height: 50), context: context)
        SafetyPDFCanvas.text("Erlaubnisschein für feuergefährliche Arbeiten", in: CGRect(x: x + 5, y: 29, width: width - 10, height: 20), font: .boldSystemFont(ofSize: 14), color: .systemRed, alignment: .center)
        SafetyPDFCanvas.text("Es ist vorab zu prüfen, ob anstelle dieser Arbeiten sogenannte kalte Verfahren\n(Sägen, Schrauben, Kaltkleben, etc.) eingesetzt werden können!", in: CGRect(x: x + 5, y: 51, width: width - 10, height: 22), font: .boldSystemFont(ofSize: 7.2), color: .systemRed, alignment: .center)

        let workRect = CGRect(x: x, y: 75, width: width, height: 43)
        SafetyPDFCanvas.cell(workRect, context: context)
        SafetyPDFCanvas.text("Art:", in: CGRect(x: x + 24, y: 80, width: 25, height: 12), font: tiny)
        let workItems: [(String, Bool)] = [
            ("Schweißen, Schneiden und verwandte Verfahren (Schweißerlaubnis)", record.workTypes.contains(.weldingCutting)),
            ("Trennschleifen", record.workTypes.contains(.grinding)),
            ("Löten", record.workTypes.contains(.soldering)),
            ("Auftauen", record.workTypes.contains(.thawing)),
            ("Heißklebearbeiten", record.workTypes.contains(.hotGlue)),
            ("Sonstiges: \(record.hasOtherWorkType ? dash(record.otherWorkType) : "")", record.hasOtherWorkType)
        ]
        checkboxLabel(workItems[0], x: x + 66, y: 80, width: 390, context: context)
        let workWidths: [CGFloat] = [70, 49, 57, 88, 155]
        var workX = x + 66
        for index in 1..<workItems.count {
            checkboxLabel(workItems[index], x: workX, y: 97, width: workWidths[index - 1], context: context)
            workX += workWidths[index - 1]
        }

        var y: CGFloat = 118
        sectionHeader("1", "Arbeitsort/-stelle", value: [location.businessEntityTitle, location.buildingTitle, location.functionalLocationTitle].filter { !$0.isEmpty }.joined(separator: ", "), y: y, context: context)
        y += 17
        standardRow("", "Brand-/explosions-gefährdeter\nBereich", "Räumliche Ausdehnung um die Arbeitsstelle:\nUmkreis (Radius) von \(dash(record.radiusMetres)) m, Höhe von \(dash(record.heightMetres)) m, Tiefe von \(dash(record.depthMetres)) m", y: y, height: 34, context: context)
        y += 34
        workOrderRow(record, y: y, context: context)
        y += 42
        simpleHeader("3", "Sicherheitsmaßnahmen bei Brandgefahr", y: y, context: context)
        y += 17

        signedChecklistRow(
            number: "3a",
            title: "Beseitigung der Brandgefahr -\nSicherheitsvorkehrungen vor\nBeginn der Arbeiten",
            items: [
                (Self.measureLabels[.removeCombustibles]!, record.measures[.removeCombustibles, default: false]),
                (Self.measureLabels[.removeCombustibleCoverings]!, record.measures[.removeCombustibleCoverings, default: false]),
                (Self.measureLabels[.coverFixedCombustibles]!, record.measures[.coverFixedCombustibles, default: false]),
                (Self.measureLabels[.sealOpenings]!, record.measures[.sealOpenings, default: false]),
                ("Sonstiges: \(record.otherFireHazardEnabled ? dash(record.otherFireHazard) : "")", record.otherFireHazardEnabled)
            ],
            signer: record.fireHazardPerformer,
            date: record.fireHazardCompletedOn,
            signature: record.signatures[.fireHazardMeasures]?.pngData,
            y: y,
            height: 120,
            context: context
        )
        y += 120
        signedChecklistRow(
            number: "3b",
            title: "Bereitstellung von Löschmitteln/\nFeuerlöschern",
            items: [
                (Self.measureLabels[.water]!, record.measures[.water, default: false]),
                (Self.measureLabels[.foam]!, record.measures[.foam, default: false]),
                (Self.measureLabels[.powder]!, record.measures[.powder, default: false]),
                (Self.measureLabels[.carbonDioxide]!, record.measures[.carbonDioxide, default: false]),
                (Self.measureLabels[.connectedWaterHose]!, record.measures[.connectedWaterHose, default: false]),
                (Self.measureLabels[.waterFilledBucket]!, record.measures[.waterFilledBucket, default: false]),
                (Self.measureLabels[.notifyFireBrigade]!, record.measures[.notifyFireBrigade, default: false]),
                ("Sonstiges: \(record.otherExtinguishingEnabled ? dash(record.otherExtinguishing) : "")", record.otherExtinguishingEnabled)
            ],
            signer: record.extinguishingPerformer,
            date: record.extinguishingCompletedOn,
            signature: record.signatures[.extinguishingMedia]?.pngData,
            y: y,
            height: 94,
            columns: 2,
            context: context
        )
        y += 94
        fireAlarmRow(record, y: y, context: context)
        y += 72
        compactRow("3d", "Brandposten", Self.measureLabels[.fireWatchDuringWork]!, selected: record.measures[.fireWatchDuringWork, default: false], trailing: "Name der Brandpostens: \(record.fireWatchName)", y: y, height: 25, context: context)
        y += 25
        compactRow("3e", "Brandwache", Self.measureLabels[.fireWatchAfterWork]!, selected: record.measures[.fireWatchAfterWork, default: false], trailing: "Dauer: \(dash(record.fireWatchDurationHours)) Stunde/n    Name: \(record.afterWorkFireWatchName)", y: y, height: 30, context: context)
        y += 30
        simpleHeader("4", "Sicherheitsmaßnahmen bei Explosionsgefahr", y: y, context: context)
        y += 17
        signedChecklistRow(
            number: "4a",
            title: "Beseitigung der\nExplosionsgefahr",
            items: [
                (Self.measureLabels[.removeExplosives]!, record.measures[.removeExplosives, default: false]),
                (Self.measureLabels[.removePipelineExplosionHazard]!, record.measures[.removePipelineExplosionHazard, default: false]),
                (Self.measureLabels[.sealFixedContainers]!, record.measures[.sealFixedContainers, default: false]),
                (Self.measureLabels[.ventilationMeasures]!, record.measures[.ventilationMeasures, default: false]),
                ("\(Self.measureLabels[.gasDetectors]!) für \(record.gasDetectorDetails)", record.measures[.gasDetectors, default: false]),
                ("Sonstiges: \(record.otherExplosionEnabled ? dash(record.otherExplosion) : "")", record.otherExplosionEnabled)
            ],
            signer: record.explosionPerformer,
            date: record.explosionCompletedOn,
            signature: record.signatures[.explosionHazardMeasures]?.pngData,
            y: y,
            height: 118,
            context: context
        )
        y += 118
        compactRow("4b", "Überwachung", "Überwachen der Sicherheitsmaßnahmen auf Wirksamkeit", selected: true, trailing: "Name: \(record.monitoringContractorName)", y: y, height: 25, context: context)
    }

    private func checkboxLabel(_ item: (String, Bool), x: CGFloat, y: CGFloat, width: CGFloat, context: CGContext) {
        SafetyPDFCanvas.checkbox(item.1, at: CGPoint(x: x, y: y + 1), context: context)
        SafetyPDFCanvas.text(item.0, in: CGRect(x: x + 9, y: y, width: width - 9, height: 24), font: tiny)
    }

    private func sectionHeader(_ number: String, _ title: String, value: String, y: CGFloat, context: CGContext) {
        let x = SafetyPDFCanvas.margin
        let rect = CGRect(x: x, y: y, width: SafetyPDFCanvas.contentWidth, height: 17)
        SafetyPDFCanvas.cell(rect, context: context)
        verticals(at: [x + 22, x + 140], from: y, to: y + 17, context: context)
        SafetyPDFCanvas.text(number, in: CGRect(x: x + 5, y: y + 3, width: 14, height: 11), font: tinyBold)
        SafetyPDFCanvas.text(title, in: CGRect(x: x + 27, y: y + 3, width: 108, height: 12), font: tinyBold)
        SafetyPDFCanvas.text(value, in: CGRect(x: x + 145, y: y + 3, width: rect.width - 150, height: 12), font: tiny)
    }

    private func standardRow(_ number: String, _ title: String, _ value: String, y: CGFloat, height: CGFloat, context: CGContext) {
        let x = SafetyPDFCanvas.margin
        let rect = CGRect(x: x, y: y, width: SafetyPDFCanvas.contentWidth, height: height)
        SafetyPDFCanvas.cell(rect, context: context)
        verticals(at: [x + 22, x + 140], from: y, to: y + height, context: context)
        SafetyPDFCanvas.text(number, in: CGRect(x: x + 5, y: y + 4, width: 14, height: 11), font: tiny)
        SafetyPDFCanvas.text(title, in: CGRect(x: x + 27, y: y + 4, width: 108, height: height - 8), font: tiny)
        SafetyPDFCanvas.text(value, in: CGRect(x: x + 145, y: y + 4, width: rect.width - 150, height: height - 8), font: tiny)
    }

    private func workOrderRow(_ record: FirePermitRecord, y: CGFloat, context: CGContext) {
        let x = SafetyPDFCanvas.margin
        let width = SafetyPDFCanvas.contentWidth
        SafetyPDFCanvas.cell(CGRect(x: x, y: y, width: width, height: 42), context: context)
        verticals(at: [x + 22, x + 140, x + width - 130], from: y, to: y + 42, context: context)
        SafetyPDFCanvas.text("2", in: CGRect(x: x + 5, y: y + 5, width: 14, height: 12), font: tinyBold)
        SafetyPDFCanvas.text("Arbeitsauftrag (z. B. Träger\nabtrennen) Arbeitsverfahren", in: CGRect(x: x + 27, y: y + 4, width: 108, height: 34), font: tinyBold)
        SafetyPDFCanvas.text(record.workDescription, in: CGRect(x: x + 145, y: y + 5, width: width - 280, height: 32), font: tiny)
        SafetyPDFCanvas.text("Name:", in: CGRect(x: x + width - 125, y: y + 4, width: 115, height: 10), font: tiny)
        SafetyPDFCanvas.underlinedValue(record.onSiteWorkerName, in: CGRect(x: x + width - 125, y: y + 15, width: 115, height: 17), font: tiny, context: context)
    }

    private func simpleHeader(_ number: String, _ title: String, y: CGFloat, context: CGContext) {
        let x = SafetyPDFCanvas.margin
        let rect = CGRect(x: x, y: y, width: SafetyPDFCanvas.contentWidth, height: 17)
        SafetyPDFCanvas.cell(rect, context: context)
        SafetyPDFCanvas.line(from: CGPoint(x: x + 22, y: y), to: CGPoint(x: x + 22, y: y + 17), context: context)
        SafetyPDFCanvas.text(number, in: CGRect(x: x + 5, y: y + 3, width: 14, height: 11), font: tinyBold)
        SafetyPDFCanvas.text(title, in: CGRect(x: x + 27, y: y + 3, width: rect.width - 32, height: 11), font: tinyBold)
    }

    private func signedChecklistRow(
        number: String,
        title: String,
        items: [(String, Bool)],
        signer: String,
        date: Date,
        signature: Data?,
        y: CGFloat,
        height: CGFloat,
        columns: Int = 1,
        context: CGContext
    ) {
        let x = SafetyPDFCanvas.margin
        let width = SafetyPDFCanvas.contentWidth
        let titleX = x + 22
        let contentX = x + 140
        let signerX = x + width - 130
        SafetyPDFCanvas.cell(CGRect(x: x, y: y, width: width, height: height), context: context)
        verticals(at: [titleX, contentX, signerX], from: y, to: y + height, context: context)
        SafetyPDFCanvas.text(number, in: CGRect(x: x + 4, y: y + 4, width: 17, height: 12), font: tiny)
        SafetyPDFCanvas.text(title, in: CGRect(x: titleX + 5, y: y + 4, width: 109, height: height - 8), font: tiny)

        let itemWidth = (signerX - contentX - 12) / CGFloat(columns)
        let rows = Int(ceil(Double(items.count) / Double(columns)))
        let rowHeight = max(12, (height - 10) / CGFloat(rows))
        for (index, item) in items.enumerated() {
            let column = index % columns
            let row = index / columns
            let itemX = contentX + 6 + CGFloat(column) * itemWidth
            let itemY = y + 5 + CGFloat(row) * rowHeight
            SafetyPDFCanvas.checkbox(item.1, at: CGPoint(x: itemX, y: itemY + 1), context: context)
            SafetyPDFCanvas.text(item.0, in: CGRect(x: itemX + 9, y: itemY, width: itemWidth - 10, height: rowHeight), font: tiny)
        }
        drawSigner(name: signer, date: date, signature: signature, rect: CGRect(x: signerX, y: y, width: 130, height: height), context: context)
    }

    private func drawSigner(name: String, date: Date, signature: Data?, rect: CGRect, context: CGContext) {
        SafetyPDFCanvas.text("Name:", in: CGRect(x: rect.minX + 6, y: rect.minY + 4, width: rect.width - 12, height: 10), font: tiny)
        SafetyPDFCanvas.underlinedValue(name, in: CGRect(x: rect.minX + 6, y: rect.minY + 14, width: rect.width - 12, height: 14), font: tiny, context: context)
        SafetyPDFCanvas.text("Ausgeführt: \(SafetyPDFCanvas.date(date))", in: CGRect(x: rect.minX + 6, y: rect.minY + 34, width: rect.width - 12, height: 11), font: tiny)
        SafetyPDFCanvas.signature(signature, in: CGRect(x: rect.minX + 8, y: rect.minY + 47, width: rect.width - 16, height: max(8, rect.height - 65)))
        SafetyPDFCanvas.line(from: CGPoint(x: rect.minX + 6, y: rect.maxY - 14), to: CGPoint(x: rect.maxX - 6, y: rect.maxY - 14), context: context)
        SafetyPDFCanvas.text("(Unterschrift)", in: CGRect(x: rect.minX + 10, y: rect.maxY - 12, width: rect.width - 20, height: 10), font: .systemFont(ofSize: 5.5))
    }

    private func fireAlarmRow(_ record: FirePermitRecord, y: CGFloat, context: CGContext) {
        let x = SafetyPDFCanvas.margin
        let width = SafetyPDFCanvas.contentWidth
        let contentX = x + 140
        let signerX = x + width - 130
        SafetyPDFCanvas.cell(CGRect(x: x, y: y, width: width, height: 72), context: context)
        verticals(at: [x + 22, contentX, signerX], from: y, to: y + 72, context: context)
        SafetyPDFCanvas.text("3c", in: CGRect(x: x + 4, y: y + 4, width: 17, height: 11), font: tiny)
        SafetyPDFCanvas.text("Brandmeldeanlage", in: CGRect(x: x + 27, y: y + 4, width: 108, height: 12), font: tiny)
        SafetyPDFCanvas.text("Müssen von der Brandmeldeanlage einzelne Schleifen außer Betrieb genommen werden?", in: CGRect(x: contentX + 5, y: y + 4, width: signerX - contentX - 10, height: 22), font: tiny)
        checkboxLabel(("Ja", record.measures[.fireAlarmLoopsOutOfService, default: false]), x: contentX + 80, y: y + 29, width: 44, context: context)
        checkboxLabel(("Nein", !record.measures[.fireAlarmLoopsOutOfService, default: false]), x: contentX + 135, y: y + 29, width: 48, context: context)
        SafetyPDFCanvas.text("Verantwortlicher der Brandmeldeanlage: \(record.fireAlarmPerformer)", in: CGRect(x: contentX + 5, y: y + 48, width: signerX - contentX - 10, height: 14), font: tiny)
        SafetyPDFCanvas.text("Information an den Verantwortlichen\nerfolgt.", in: CGRect(x: signerX + 6, y: y + 5, width: 118, height: 22), font: tiny)
        SafetyPDFCanvas.signature(record.signatures[.fireAlarmSystem]?.pngData, in: CGRect(x: signerX + 8, y: y + 28, width: 114, height: 29))
        SafetyPDFCanvas.line(from: CGPoint(x: signerX + 6, y: y + 58), to: CGPoint(x: signerX + 124, y: y + 58), context: context)
        SafetyPDFCanvas.text("(Unterschrift Verantwortlicher)", in: CGRect(x: signerX + 7, y: y + 60, width: 120, height: 9), font: .systemFont(ofSize: 5.3))
    }

    private func compactRow(_ number: String, _ title: String, _ label: String, selected: Bool, trailing: String, y: CGFloat, height: CGFloat, context: CGContext) {
        let x = SafetyPDFCanvas.margin
        let width = SafetyPDFCanvas.contentWidth
        SafetyPDFCanvas.cell(CGRect(x: x, y: y, width: width, height: height), context: context)
        verticals(at: [x + 22, x + 140], from: y, to: y + height, context: context)
        SafetyPDFCanvas.text(number, in: CGRect(x: x + 4, y: y + 4, width: 17, height: 11), font: tiny)
        SafetyPDFCanvas.text(title, in: CGRect(x: x + 27, y: y + 4, width: 108, height: 12), font: tiny)
        SafetyPDFCanvas.checkbox(selected, at: CGPoint(x: x + 146, y: y + 5), context: context)
        SafetyPDFCanvas.text(label, in: CGRect(x: x + 156, y: y + 4, width: 200, height: height - 6), font: tiny)
        SafetyPDFCanvas.text(trailing, in: CGRect(x: x + 360, y: y + 4, width: width - 366, height: height - 6), font: tiny)
    }

    private func verticals(at values: [CGFloat], from: CGFloat, to: CGFloat, context: CGContext) {
        for x in values {
            SafetyPDFCanvas.line(from: CGPoint(x: x, y: from), to: CGPoint(x: x, y: to), context: context)
        }
    }

    private func drawPermissionPage(_ record: FirePermitRecord, context: CGContext) {
        let x = SafetyPDFCanvas.margin
        let width = SafetyPDFCanvas.contentWidth
        let font = UIFont.systemFont(ofSize: 7.2)
        var y: CGFloat = 25

        SafetyPDFCanvas.cell(CGRect(x: x, y: y, width: width, height: 64), context: context)
        verticals(at: [x + 22, x + 140, x + width - 130], from: y, to: y + 64, context: context)
        SafetyPDFCanvas.text("5", in: CGRect(x: x + 5, y: y + 5, width: 14, height: 12), font: tinyBold)
        SafetyPDFCanvas.text("Alarmierung", in: CGRect(x: x + 27, y: y + 5, width: 108, height: 12), font: font)
        SafetyPDFCanvas.text("Standort des nächstgelegenen:\n\nDruckknopfmelders: \(record.manualCallPointLocation)\nMobil/Telefon: \(record.mobileTelephone)", in: CGRect(x: x + 145, y: y + 5, width: width - 280, height: 56), font: font)
        SafetyPDFCanvas.text("Feuerwehr / Notruf Nr.:", in: CGRect(x: x + width - 125, y: y + 5, width: 115, height: 13), font: font)
        SafetyPDFCanvas.text("(0) 112", in: CGRect(x: x + width - 125, y: y + 25, width: 115, height: 25), font: .systemFont(ofSize: 15), color: .systemRed, alignment: .center)
        y += 64

        SafetyPDFCanvas.cell(CGRect(x: x, y: y, width: width, height: 18), context: context)
        verticals(at: [x + 22, x + 140], from: y, to: y + 18, context: context)
        SafetyPDFCanvas.text("6", in: CGRect(x: x + 5, y: y + 4, width: 14, height: 12), font: tinyBold)
        SafetyPDFCanvas.text("Erlaubnis", in: CGRect(x: x + 27, y: y + 4, width: 108, height: 12), font: tinyBold)
        SafetyPDFCanvas.text("die notwendigen Unterschriften müssen vor Beginn der Tätigkeit eingeholt werden", in: CGRect(x: x + 145, y: y + 4, width: width - 150, height: 12), font: font)
        y += 18

        permissionRow(
            title: "Auftraggebender Unternehmer\n(Auftraggeber)",
            explanation: "Die Maßnahmen nach 3 und 4 tragen den durch die örtlichen Verhältnisse entstehenden Gefahren Rechnung.",
            name: record.permitIssuerName,
            date: record.permitIssuedOn,
            signature: record.signatures[.permitIssuer]?.pngData,
            y: y,
            height: 118,
            context: context
        )
        y += 118
        permissionRow(
            title: "Ausführender Unternehmer\n(Auftragnehmer)",
            explanation: "Die Arbeiten nach 2 dürfen erst begonnen werden, wenn die Sicherheitsmaßnahmen nach 3a-3e und/oder 4a-4b durchgeführt sind.",
            name: record.contractorName,
            date: record.contractorSignedOn,
            signature: record.signatures[.contractor]?.pngData,
            confirmationName: record.onSiteWorkerName,
            confirmationSignature: record.signatures[.onSiteWorker]?.pngData,
            y: y,
            height: 118,
            context: context
        )
    }

    private func permissionRow(
        title: String,
        explanation: String,
        name: String,
        date: Date,
        signature: Data?,
        confirmationName: String? = nil,
        confirmationSignature: Data? = nil,
        y: CGFloat,
        height: CGFloat,
        context: CGContext
    ) {
        let x = SafetyPDFCanvas.margin
        let width = SafetyPDFCanvas.contentWidth
        let titleWidth: CGFloat = 140
        let confirmationWidth: CGFloat = confirmationName == nil ? 0 : 130
        let mainWidth = width - titleWidth - confirmationWidth
        let rect = CGRect(x: x, y: y, width: width, height: height)
        SafetyPDFCanvas.cell(rect, context: context)
        verticals(at: [x + titleWidth], from: y, to: y + height, context: context)
        if confirmationWidth > 0 {
            verticals(at: [x + width - confirmationWidth], from: y, to: y + height, context: context)
        }
        SafetyPDFCanvas.text(title, in: CGRect(x: x + 5, y: y + 5, width: titleWidth - 10, height: 28), font: tiny)
        SafetyPDFCanvas.text(explanation, in: CGRect(x: x + titleWidth + 5, y: y + 5, width: mainWidth - 10, height: 31), font: tiny)
        SafetyPDFCanvas.text(name, in: CGRect(x: x + titleWidth + 8, y: y + 34, width: mainWidth - 16, height: 13), font: tiny, alignment: .center)
        SafetyPDFCanvas.signature(signature, in: CGRect(x: x + titleWidth + 10, y: y + 45, width: mainWidth - 20, height: 47))
        SafetyPDFCanvas.text(SafetyPDFCanvas.date(date), in: CGRect(x: x + 10, y: y + height - 28, width: titleWidth - 20, height: 12), font: tiny)
        SafetyPDFCanvas.line(from: CGPoint(x: x + 8, y: y + height - 15), to: CGPoint(x: x + titleWidth - 8, y: y + height - 15), context: context)
        SafetyPDFCanvas.text("Datum", in: CGRect(x: x + 10, y: y + height - 13, width: titleWidth - 20, height: 10), font: .systemFont(ofSize: 5.5))
        SafetyPDFCanvas.line(from: CGPoint(x: x + titleWidth + 5, y: y + height - 15), to: CGPoint(x: x + titleWidth + mainWidth - 5, y: y + height - 15), context: context)
        SafetyPDFCanvas.text("Unterschrift des Unternehmers oder dessen Beauftragten", in: CGRect(x: x + titleWidth + 9, y: y + height - 13, width: mainWidth - 18, height: 10), font: .systemFont(ofSize: 5.5))
        if let confirmationName {
            let confirmationX = x + width - confirmationWidth
            SafetyPDFCanvas.text("Kenntnisnahme des Ausführenden\nnach 2", in: CGRect(x: confirmationX + 5, y: y + 5, width: confirmationWidth - 10, height: 24), font: tiny)
            SafetyPDFCanvas.text(confirmationName, in: CGRect(x: confirmationX + 7, y: y + 29, width: confirmationWidth - 14, height: 13), font: tiny, alignment: .center)
            SafetyPDFCanvas.signature(confirmationSignature, in: CGRect(x: confirmationX + 8, y: y + 43, width: confirmationWidth - 16, height: 49))
            SafetyPDFCanvas.line(from: CGPoint(x: confirmationX + 6, y: y + height - 15), to: CGPoint(x: confirmationX + confirmationWidth - 6, y: y + height - 15), context: context)
            SafetyPDFCanvas.text("(Unterschrift)", in: CGRect(x: confirmationX + 9, y: y + height - 13, width: confirmationWidth - 18, height: 10), font: .systemFont(ofSize: 5.5))
        }
    }

    private func drawResponsibilitiesPage(context: CGContext) {
        let x = SafetyPDFCanvas.margin
        let width = SafetyPDFCanvas.contentWidth
        let heading = UIFont.boldSystemFont(ofSize: 12)
        let body = UIFont.systemFont(ofSize: 10)
        SafetyPDFCanvas.text("Aufgaben und Verantwortung", in: CGRect(x: x, y: 25, width: width, height: 20), font: heading)
        SafetyPDFCanvas.text("Auftraggeber (FM-Mitarbeiter/Projektleiter)", in: CGRect(x: x, y: 53, width: width, height: 20), font: heading)
        SafetyPDFCanvas.text("Auftraggeber ist eine vom Unternehmen beauftragte Person zur Durchführung derartiger Tätigkeiten. Dieser ist verantwortlich für die Auslösung des Auftrages. Er hat dem Auftragnehmer Auskunft über mögliche Brand- und Explosionsgefährdungen zu geben.", in: CGRect(x: x + 24, y: 81, width: width - 24, height: 52), font: body)
        SafetyPDFCanvas.text("Auftragnehmer", in: CGRect(x: x, y: 136, width: width, height: 20), font: heading)
        SafetyPDFCanvas.text("Der Auftragnehmer (im Sinne des Gesetzes) oder dessen Beauftragter ist voll für die Einhaltung der Arbeits- und Brandschutzbestimmungen beim Schweißen, Schneiden u.ä. thermischen Verfahren verantwortlich. Er beauftragt den Ausführenden und ist für die Unterschrift auf dem Feuererlaubnisschein zuständig.", in: CGRect(x: x + 24, y: 164, width: width - 24, height: 62), font: body)
        SafetyPDFCanvas.text("Ausführender", in: CGRect(x: x, y: 231, width: width, height: 20), font: heading)
        SafetyPDFCanvas.text("Der Ausführende muss entsprechend der auszuführenden Arbeiten eine Qualifikation besitzen. Er ist verantwortlich für die", in: CGRect(x: x + 24, y: 259, width: width - 24, height: 38), font: body)
        SafetyPDFCanvas.text("•  Einhaltung der Sicherheits- und Schutzmaßnahmen\n•  Arbeits- und brandschutzgerechtes Verhalten beim Schweißen, Schneiden u.ä. thermischen Verfahren", in: CGRect(x: x + 48, y: 300, width: width - 48, height: 48), font: body)
        SafetyPDFCanvas.text("und hat mit seiner Unterschrift auf dem Feuererlaubnisschein dies zu bestätigen.", in: CGRect(x: x + 24, y: 352, width: width - 24, height: 28), font: body)
    }

    private func drawMatrixPage(context: CGContext) {
        let x = SafetyPDFCanvas.margin
        let width = SafetyPDFCanvas.contentWidth
        let font = UIFont.systemFont(ofSize: 7.2)
        let bold = UIFont.boldSystemFont(ofSize: 7.2)
        SafetyPDFCanvas.text("Matrix", in: CGRect(x: x, y: 25, width: width, height: 18), font: .systemFont(ofSize: 12), color: SafetyPDFCanvas.matrixSideBlue)
        SafetyPDFCanvas.text("Die in der Matrix aufgeführten Stundenwerte sind als Anhaltspunkt zu nutzen, in Einzelfällen kann auch eine Brandwache >5 Std. notwendig sein.", in: CGRect(x: x, y: 42, width: width, height: 14), font: .systemFont(ofSize: 6.4))

        let sideWidth: CGFloat = 50
        let labelWidth: CGFloat = 101
        let valueWidth = (width - sideWidth - labelWidth) / 6
        let factorX = x + sideWidth + labelWidth
        let header = CGRect(x: factorX, y: 58, width: valueWidth * 6, height: 18)
        SafetyPDFCanvas.cell(header, fill: SafetyPDFCanvas.matrixBlue, context: context)
        SafetyPDFCanvas.text("Bauliche Faktoren", in: header.insetBy(dx: 4, dy: 4), font: bold, color: .white, alignment: .center)
        let titles = [
            "Nichtbrennbare Bauweise bzw. Konstruktion und/oder Baustoff\nTyp A1",
            "Brennbare Bauweise bzw. Konstruktion und/oder Baustoff\nTyp B2 Ohne verdeckte Hohlräume",
            "Brennbare Bauweise bzw. Konstruktion und/oder Baustoff\nTyp B2 Mit ungeschützten verdeckten Hohlräume"
        ]
        for index in 0..<3 {
            let rect = CGRect(x: factorX + CGFloat(index) * valueWidth * 2, y: 76, width: valueWidth * 2, height: 53)
            SafetyPDFCanvas.cell(rect, fill: SafetyPDFCanvas.matrixLightBlue, context: context)
            SafetyPDFCanvas.text(titles[index], in: rect.insetBy(dx: 4, dy: 6), font: font, alignment: .center)
        }
        for index in 0..<6 {
            let rect = CGRect(x: factorX + CGFloat(index) * valueWidth, y: 129, width: valueWidth, height: 47)
            SafetyPDFCanvas.cell(rect, context: context)
            SafetyPDFCanvas.text(index.isMultiple(of: 2) ? "Brandposten während der Ausführung der Heißarbeit" : "Brandwache nach der Ausführung", in: rect.insetBy(dx: 3, dy: 4), font: font, alignment: .center)
        }

        let labels = [
            "Nicht Brennbar, alle Brandlasten befinden sich in geschlossenen Anlagen bzw. sind Brandschutztechnisch geschützt",
            "Büros, Lager (Handlager) oder Fertigung mit begrenzter Brandlast",
            "Büros, Lager (Handlager) oder Fertigung mit erheblicher Brandlast",
            "Logistiklager",
            "Logistiklager langsame Brandlast auf Celloulose- bzw. Kohlenstoff-Basis"
        ]
        let values = [
            ["0,5 h", "0 h", "1 h", "3 h", "1 h", "5 h"],
            ["1 h", "1 h", "1 h", "3 h", "1 h", "5 h"],
            ["1 h", "2 h", "1 h", "3 h", "1 h", "5 h"],
            ["1 h", "2 h", "1 h", "3 h", "1 h", "5 h"],
            ["1 h", "3 h", "1 h", "3 h", "1 h", "5 h"]
        ]
        let heights: [CGFloat] = [61, 47, 54, 28, 54]
        let totalHeight = heights.reduce(0, +)
        let sideRect = CGRect(x: x, y: 176, width: sideWidth, height: totalHeight)
        SafetyPDFCanvas.cell(sideRect, fill: SafetyPDFCanvas.matrixSideBlue, context: context)
        context.saveGState()
        context.translateBy(x: sideRect.midX, y: sideRect.midY)
        context.rotate(by: -.pi / 2)
        SafetyPDFCanvas.text("Nutzungs-/Belegungsfaktoren", in: CGRect(x: -sideRect.height / 2, y: -8, width: sideRect.height, height: 16), font: font, alignment: .center)
        context.restoreGState()

        var y: CGFloat = 176
        for row in labels.indices {
            let fill = row.isMultiple(of: 2) ? SafetyPDFCanvas.matrixLightBlue : UIColor.white
            let labelRect = CGRect(x: x + sideWidth, y: y, width: labelWidth, height: heights[row])
            SafetyPDFCanvas.cell(labelRect, fill: fill, context: context)
            SafetyPDFCanvas.text(labels[row], in: labelRect.insetBy(dx: 4, dy: 3), font: font)
            for column in 0..<6 {
                let rect = CGRect(x: factorX + CGFloat(column) * valueWidth, y: y, width: valueWidth, height: heights[row])
                SafetyPDFCanvas.cell(rect, fill: fill, context: context)
                SafetyPDFCanvas.text(values[row][column], in: rect.insetBy(dx: 2, dy: max(3, (heights[row] - 12) / 2)), font: bold, alignment: .center)
            }
            y += heights[row]
        }
    }

    private func dash(_ value: String) -> String {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? "-" : trimmed
    }

    private static let measureLabels: [FirePermitMeasure: String] = [
        .removeCombustibles: "Entfernen sämtlicher beweglicher brennbarer Stoffe und Gegenstände und Staubablagerungen",
        .removeCombustibleCoverings: "Entfernen von Wand- und Deckenverkleidungen, soweit sie brennbare Stoffe abdecken oder selbst brennbar sind",
        .coverFixedCombustibles: "Abdecken ortsfester brennbarer Stoffe und Gegenstände mit geeigneten Mitteln und ggf. Anfeuchten",
        .sealOpenings: "Abdichten von Öffnungen zu benachbarten Bereichen mittels Lehm, Gips, Mörtel oder feuchter Erde",
        .water: "Wasser",
        .foam: "Schaum",
        .powder: "Pulver",
        .carbonDioxide: "CO²",
        .connectedWaterHose: "Angeschlossener Wasserschlauch",
        .waterFilledBucket: "Wassergefüllter Eimer",
        .notifyFireBrigade: "Benachrichtigen der Feuerwehr",
        .fireAlarmLoopsOutOfService: "Schleifen der Brandmeldeanlage außer Betrieb nehmen",
        .fireWatchDuringWork: "Während der feuergefährlichen Arbeiten",
        .fireWatchAfterWork: "Nach Abschluss der feuergefährlichen Arbeiten",
        .removeExplosives: "Entfernen sämtlicher explosionsfähiger Stoffe und Gegenstände - auch Staubablagerungen und Behälter mit gefährlichem Inhalt oder dessen Resten",
        .removePipelineExplosionHazard: "Explosionsgefahr in Rohrleitungen beseitigen",
        .sealFixedContainers: "Abdichten von ortsfesten Behältern, Apparaten oder Rohrleitungen, die brennbare Flüssigkeiten, Gase oder Stäube enthalten",
        .ventilationMeasures: "Durchführen lüftungstechnischer Maßnahmen nach EX-RL in Verbindung mit messtechnischer Überwachung",
        .gasDetectors: "Aufstellen von Gaswarngeräten"
    ]
}
