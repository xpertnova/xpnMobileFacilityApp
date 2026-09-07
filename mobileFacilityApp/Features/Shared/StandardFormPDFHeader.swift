import Foundation
import UIKit

struct StandardFormPDFHeaderData: Sendable, Equatable {
    let documentTitle: String
    let instructorName: String
    let organizationUnit: String
    let coordinator: String
    let partnerName: String
    let partnerAddress: String
    let instructedPerson: String
    let workLocation: String
    let workDescription: String
    let dateFrom: Date
    let dateTo: Date
}

/// Fixed-German PDF header shared by all four form renderers.
enum StandardFormPDFHeaderRenderer {
    private static let labelFont = UIFont.boldSystemFont(ofSize: 9)
    private static let valueFont = UIFont.systemFont(ofSize: 9)
    private static let titleFont = UIFont.boldSystemFont(ofSize: 17)
    private static let border = UIColor.black.withAlphaComponent(0.72)
    private static let labelFill = UIColor(white: 0.96, alpha: 1)

    @discardableResult
    static func draw(
        _ header: StandardFormPDFHeaderData,
        in context: CGContext,
        pageWidth: CGFloat,
        margin: CGFloat,
        startY: CGFloat
    ) -> CGFloat {
        let contentWidth = pageWidth - margin * 2
        var y = startY
        let titleHeight = max(
            58,
            textHeight(header.documentTitle, width: contentWidth - 16, font: titleFont) + 16
        )
        let titleRect = CGRect(x: margin, y: y, width: contentWidth, height: titleHeight)
        fillAndStroke(titleRect, fill: .white, context: context)
        drawText(
            header.documentTitle,
            in: titleRect.insetBy(dx: 8, dy: 8),
            font: titleFont,
            alignment: .center
        )
        y = titleRect.maxY

        let partner = [header.partnerName, header.partnerAddress]
            .filter { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
            .joined(separator: "\n")
        let instructorHeight = max(
            46,
            textHeight("Einweiser/Abnehmer\n(E.ON Mitarbeiter)", width: contentWidth * 0.25 - 12, font: labelFont) + 12,
            textHeight(header.instructorName, width: contentWidth * 0.5 - 12, font: valueFont) + 12,
            textHeight(header.organizationUnit, width: contentWidth * 0.25 - 12, font: valueFont) + 12
        )
        let instructorRects = [
            CGRect(x: margin, y: y, width: contentWidth * 0.25, height: instructorHeight),
            CGRect(x: margin + contentWidth * 0.25, y: y, width: contentWidth * 0.5, height: instructorHeight),
            CGRect(x: margin + contentWidth * 0.75, y: y, width: contentWidth * 0.25, height: instructorHeight)
        ]
        instructorRects.enumerated().forEach { index, rect in
            fillAndStroke(rect, fill: index == 0 ? labelFill : .white, context: context)
        }
        drawText("Einweiser/Abnehmer\n(E.ON Mitarbeiter)", in: instructorRects[0].insetBy(dx: 6, dy: 6), font: labelFont)
        drawText(header.instructorName, in: instructorRects[1].insetBy(dx: 6, dy: 6), font: valueFont)
        drawText(header.organizationUnit, in: instructorRects[2].insetBy(dx: 6, dy: 6), font: valueFont)
        y += instructorHeight

        let rows = [
            ("Benannter Koordinator ggf. SiGeKo gemäß BauStellV", header.coordinator),
            ("Partnerfirma/Auftragnehmer\n(Name und Anschrift)", partner),
            ("Eingewiesener\n(Verantwortlicher der Partnerfirma für die durchzuführenden Arbeiten)", header.instructedPerson),
            ("Leistungs-/Arbeitsort", header.workLocation),
            ("Durchzuführende Arbeiten", header.workDescription),
            ("Ausführung von ... bis ...\n(Datum und Uhrzeit)", formattedRange(from: header.dateFrom, to: header.dateTo))
        ]

        let labelWidth = contentWidth * 0.5
        for (label, value) in rows {
            let valueWidth = contentWidth - labelWidth
            let height = max(
                34,
                textHeight(label, width: labelWidth - 12, font: labelFont) + 12,
                textHeight(value, width: valueWidth - 12, font: valueFont) + 12
            )
            let labelRect = CGRect(x: margin, y: y, width: labelWidth, height: height)
            let valueRect = CGRect(x: labelRect.maxX, y: y, width: valueWidth, height: height)
            fillAndStroke(labelRect, fill: labelFill, context: context)
            fillAndStroke(valueRect, fill: .white, context: context)
            drawText(label, in: labelRect.insetBy(dx: 6, dy: 6), font: labelFont)
            drawText(value, in: valueRect.insetBy(dx: 6, dy: 6), font: valueFont)
            y += height
        }
        return y
    }

    static func formattedRange(from: Date, to: Date) -> String {
        "\(formattedDateTime(from)) - \(formattedDateTime(to))"
    }

    private static func formattedDateTime(_ value: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "de_DE")
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.dateFormat = "dd.MM.yyyy HH:mm"
        return formatter.string(from: value)
    }

    private static func fillAndStroke(_ rect: CGRect, fill: UIColor, context: CGContext) {
        context.setFillColor(fill.cgColor)
        context.fill(rect)
        context.setStrokeColor(border.cgColor)
        context.setLineWidth(0.6)
        context.stroke(rect)
    }

    private static func drawText(
        _ value: String,
        in rect: CGRect,
        font: UIFont,
        alignment: NSTextAlignment = .left
    ) {
        let paragraph = NSMutableParagraphStyle()
        paragraph.alignment = alignment
        paragraph.lineBreakMode = .byWordWrapping
        (value as NSString).draw(
            in: rect,
            withAttributes: [.font: font, .paragraphStyle: paragraph, .foregroundColor: UIColor.black]
        )
    }

    private static func textHeight(_ value: String, width: CGFloat, font: UIFont) -> CGFloat {
        let paragraph = NSMutableParagraphStyle()
        paragraph.lineBreakMode = .byWordWrapping
        return ceil((value as NSString).boundingRect(
            with: CGSize(width: max(width, 1), height: .greatestFiniteMagnitude),
            options: [.usesLineFragmentOrigin, .usesFontLeading],
            attributes: [.font: font, .paragraphStyle: paragraph],
            context: nil
        ).height)
    }
}
