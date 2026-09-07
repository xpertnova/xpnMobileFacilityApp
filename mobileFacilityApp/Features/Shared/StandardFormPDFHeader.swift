import Foundation
import UIKit

struct StandardFormPDFHeaderData: Sendable, Equatable {
    let documentTitle: String
    let instructorName: String
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
        drawText(
            header.documentTitle,
            in: CGRect(x: margin, y: y, width: contentWidth, height: 42),
            font: titleFont,
            alignment: .center
        )
        y += 48

        let partner = [header.partnerName, header.partnerAddress]
            .filter { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
            .joined(separator: "\n")
        let rows = [
            ("Unterweisender", header.instructorName),
            ("Koordinator", header.coordinator),
            ("Partnerfirma / Auftragnehmer\n(Name und Anschrift)", partner),
            ("Eingewiesene Person", header.instructedPerson),
            ("Leistungs- / Arbeitsort", header.workLocation),
            ("Durchzuführende Arbeiten", header.workDescription),
            ("Ausführung von / bis\n(Datum und Uhrzeit)", formattedRange(from: header.dateFrom, to: header.dateTo))
        ]

        let labelWidth = contentWidth * 0.4
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
        "\(formattedDateTime(from)) – \(formattedDateTime(to))"
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
