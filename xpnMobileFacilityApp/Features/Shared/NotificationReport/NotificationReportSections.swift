import Foundation
import UIKit

/// Building blocks of the legacy `PdfBuilder` I1 reports. Each function mirrors
/// one pdfmake block, with its column widths, font sizes and borders.
extension NotificationReportComposer {
    struct KeyValueRow: Equatable, Sendable {
        let label: String
        let value: String
    }

    // MARK: - Formular header (`addDocHeaderWN`)

    /// The framed "Formular" header of Rundgang and the equipment inspections.
    func formularHeader(
        organization: NotificationReportOrganization,
        formName: String,
        date: String,
        orgUnit: String
    ) {
        let widths = [contentWidth * 0.18, contentWidth * 0.62, contentWidth * 0.20]
        let small = UIFont.systemFont(ofSize: 6)
        let body = UIFont.systemFont(ofSize: 8)
        let title = UIFont.boldSystemFont(ofSize: 14)

        func greyLabel(_ text: String) -> Cell {
            Cell(text: text, font: small, alignment: .center, fill: Self.greyFill)
        }

        // Row heights: the logo spans rows 1-2, organisation and title rows 3-5.
        let row1 = max(
            rowHeight([Cell(text: "Formular", font: title)], widths: [widths[1]]),
            rowHeight([Cell(text: date, font: body, insets: UIEdgeInsets(top: 4, left: 4, bottom: 4, right: 4))], widths: [widths[2]])
        )
        let greyRow = rowHeight([greyLabel("Datum")], widths: [widths[2]])
        let logo = organization.logoImage
        let logoWidth: CGFloat = min(85, widths[0] - 8)
        let logoHeight = logo.map { logoWidth * $0.size.height / max(1, $0.size.width) } ?? 0
        let row2 = max(greyRow, logoHeight + 14 - row1)
        let valueRow = rowHeight([Cell(text: orgUnit, font: body, insets: UIEdgeInsets(top: 4, left: 4, bottom: 4, right: 4))], widths: [widths[2]])
        let spannedInsets = UIEdgeInsets(top: 12, left: 4, bottom: 12, right: 4)
        let spanned = rowHeight(
            [Cell(text: organization.name, font: title, insets: spannedInsets),
             Cell(text: formName, font: title, insets: spannedInsets)],
            widths: [widths[0], widths[1]]
        )
        let row5 = max(valueRow, spanned - valueRow - greyRow)
        let rows = [row1, row2, valueRow, greyRow, row5, greyRow]
        let total = rows.reduce(0, +)
        ensureSpace(total)
        let origin = y

        let x0 = left, x1 = left + widths[0], x2 = x1 + widths[1]
        let r = rows.reduce(into: [origin]) { $0.append($0.last! + $1) } // row boundaries

        // Grey label bands.
        drawRow([greyLabel("Dokumentenart")], widths: [widths[1]], borders: .none, at: r[1], height: row2, offsetX: x1)
        drawRow([greyLabel("Datum")], widths: [widths[2]], borders: .none, at: r[1], height: row2, offsetX: x2)
        drawRow([greyLabel("Verantwortliche Organisation")], widths: [widths[2]], borders: .none, at: r[3], height: greyRow, offsetX: x2)
        drawRow(
            [greyLabel("Geltungsbereich"), greyLabel("Titel"), greyLabel("Ersteller")],
            widths: widths, borders: .none, at: r[5], height: greyRow
        )

        let orgName = organization.name
        let bottomOfSpan = r[5]
        draw { cg in
            if let logo {
                let rect = CGRect(
                    x: x0 + (widths[0] - logoWidth) / 2,
                    y: origin + (r[2] - origin - logoHeight) / 2,
                    width: logoWidth,
                    height: logoHeight
                )
                logo.draw(in: rect)
            }
            Self.drawText("Formular", in: CGRect(x: x1, y: origin + 2, width: widths[1], height: row1), font: title, alignment: .center)
            Self.drawText(date, in: CGRect(x: x2 + 4, y: origin + 4, width: widths[2] - 8, height: row1), font: body, alignment: .center)
            Self.drawText(orgUnit, in: CGRect(x: x2 + 4, y: r[2] + 4, width: widths[2] - 8, height: valueRow), font: body, alignment: .center)
            for (text, x, width) in [(orgName, x0, widths[0]), (formName, x1, widths[1])] {
                let height = Self.textHeight(text, width: width - 8, font: title)
                Self.drawText(
                    text,
                    in: CGRect(x: x + 4, y: r[2] + (bottomOfSpan - r[2] - height) / 2, width: width - 8, height: height + 2),
                    font: title,
                    alignment: .center
                )
            }

            // Frame: outer box, column rules and the row rules each column has.
            cg.saveGState()
            cg.setStrokeColor(Self.borderColor.cgColor)
            cg.setLineWidth(0.8)
            cg.stroke(CGRect(x: x0, y: origin, width: widths.reduce(0, +), height: total))
            for x in [x1, x2] {
                cg.move(to: CGPoint(x: x, y: origin))
                cg.addLine(to: CGPoint(x: x, y: origin + total))
            }
            for (boundary, from, to) in [
                (r[1], x1, x2 + widths[2]), (r[2], x0, x2 + widths[2]),
                (r[3], x2, x2 + widths[2]), (r[4], x2, x2 + widths[2]), (r[5], x0, x2 + widths[2])
            ] {
                cg.move(to: CGPoint(x: from, y: boundary))
                cg.addLine(to: CGPoint(x: to, y: boundary))
            }
            cg.strokePath()
            cg.restoreGState()
        }
        advance(total)
    }

    // MARK: - Framed key/value table (`addFormHeaderWN`)

    /// 25 % / 75 % framed table, font size 8, `margin: [0, 10]`.
    func keyValueTable(_ rows: [KeyValueRow]) {
        guard !rows.isEmpty else { return }
        advance(10)
        let widths = [contentWidth * 0.25, contentWidth * 0.75]
        let insets = UIEdgeInsets(top: 4, left: 4, bottom: 4, right: 4)
        for row in rows {
            tableRow(
                [Cell(text: row.label, insets: insets), Cell(text: row.value, insets: insets)],
                widths: widths,
                borders: .grid
            )
        }
        advance(10)
    }

    // MARK: - Remarks on a new page (`addBemerkungTableWN`)

    struct Remark: Equatable, Sendable {
        let number: String
        let title: String
        let note: String
    }

    /// `pageBreak: "before"`, 5 % / 40 % / * framed table, font size 8.
    func remarksTable(_ remarks: [Remark]) {
        guard !remarks.isEmpty else { return }
        newPage()
        advance(20)
        let widths = [contentWidth * 0.05, contentWidth * 0.40, contentWidth * 0.55]
        let bold = UIFont.boldSystemFont(ofSize: 8)
        tableRow(
            [Cell(text: "Nr.", font: bold), Cell(text: "Zuordnung", font: bold), Cell(text: "Bemerkung", font: bold)],
            widths: widths,
            borders: .grid
        )
        let insets = UIEdgeInsets(top: 6, left: 4, bottom: 2, right: 4)
        for remark in remarks {
            tableRow(
                [
                    Cell(text: remark.number, insets: insets),
                    Cell(text: remark.title, insets: insets),
                    Cell(text: remark.note, insets: insets)
                ],
                widths: widths,
                borders: .grid
            )
        }
    }

    // MARK: - Helpers

    func drawRow(_ cells: [Cell], widths: [CGFloat], borders: Borders, at top: CGFloat, height: CGFloat, offsetX: CGFloat) {
        let shift = offsetX - left
        var shiftedCells = cells
        if shift != 0, !shiftedCells.isEmpty {
            // Leading spacer cell moves the row to `offsetX`.
            shiftedCells.insert(Cell(insets: .zero), at: 0)
            drawRow(shiftedCells, widths: [shift] + widths, borders: borders, at: top, height: height)
        } else {
            drawRow(cells, widths: widths, borders: borders, at: top, height: height)
        }
    }
}
