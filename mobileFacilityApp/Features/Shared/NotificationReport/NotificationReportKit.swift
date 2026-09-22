import Foundation
import UIKit

/// Company shown in the header logo and footer of an I1 report — the legacy
/// `PdfBuilder._getImage` and `document.footer` of the Cordova app.
///
/// Every I1 `buildPDF` passes `USER.GESELLSCHAFT` as `org`, replaced by a
/// fixed name for the plants (`T0281.IWERK`) 1501, 1505 and 1556.
struct NotificationReportOrganization: Equatable, Sendable {
    enum Logo: String, Sendable {
        case eon = "ReportLogo_EON"
        case westnetz = "ReportLogo_Westnetz"
        case hanseWerk = "ReportLogo_HanseWerk"
        case hanseGas = "ReportLogo_HanseGas"
        case schleswigHolsteinNetz = "ReportLogo_SHNetz"
        case rww = "ReportLogo_RWW"
    }

    enum Footer: Sendable {
        case eon
        case westnetz
        case none
    }

    let name: String
    let logo: Logo
    let footer: Footer

    init(company: String, plant: String, personnelNumber: String) {
        let name: String
        switch plant.trimmingCharacters(in: .whitespacesAndNewlines) {
        case "1501": name = "HanseGas GmbH"
        case "1505": name = "HanseWerk AG"
        case "1556": name = "Schleswig-Holstein Netz"
        default: name = company.trimmingCharacters(in: .whitespacesAndNewlines)
        }
        self.name = name
        logo = Self.logo(organization: name, personnelNumber: personnelNumber)
        footer = Self.footer(organization: name)
    }

    /// `_getImage(org, userId)`: the first matching rule wins, e.on otherwise.
    private static func logo(organization: String, personnelNumber: String) -> Logo {
        let org = organization.lowercased()
        let user = personnelNumber.uppercased()
        if org.contains("innogy")
            || organization.range(of: "e(.)?on", options: [.regularExpression, .caseInsensitive]) != nil {
            return .eon
        }
        if user.contains("FIN") { return .eon }
        if org.contains("westnetz") { return .westnetz }
        if user.contains("FWN") { return .westnetz }
        if org.contains("hansewerk") { return .hanseWerk }
        if org.contains("hansegas") { return .hanseGas }
        if org.contains("netz") { return .schleswigHolsteinNetz }
        if org.contains("rww") { return .rww }
        return .eon
    }

    /// `document.footer`: company details for e.on/innogy and Westnetz only.
    private static func footer(organization: String) -> Footer {
        let org = organization.lowercased()
        if org.contains("innogy") || org.contains("e.on") { return .eon }
        if org.contains("westnetz") { return .westnetz }
        return .none
    }

    var logoImage: UIImage? { UIImage(named: logo.rawValue) }

    /// Left and middle footer columns.
    var footerColumns: (left: String, middle: String) {
        switch footer {
        case .eon:
            return (
                "Geschäftsführer/Managing Directors: André Schrödel,\nDr. Marc Stienemann, Peter Olschewski, Zsolt Szabo",
                "E.ON Service GmbH Sitz/Head Office: Essen\nRegistergericht/Registry Court: Essen\nHandelsregisternummer/Commercial Register No.: HRB 16297"
            )
        case .westnetz:
            return (
                "Geschäftsführung:\nJochen Dwertmann,\nDr. Jürgen Grönner,\nDr. Alexander Montebaur",
                "Sitz der Gesellschaft: Dortmund\nEingetragen beim Amtsgericht Dortmund\nUSt-IdNr.: DE325265170\nHandelsregister-Nr. HRB 30872"
            )
        case .none:
            return ("", "")
        }
    }
}

/// Value formatting shared by the I1 reports (`util.assistmethods`).
enum NotificationReportFormat {
    /// `getBerichtDatum`: `yyyy-MM-dd`.
    static func reportDate(_ date: Date) -> String { format(date, "yyyy-MM-dd") }

    /// `getDatumWithHyphenString`: `dd.MM.yyyy`.
    static func germanDate(_ date: Date) -> String { format(date, "dd.MM.yyyy") }

    /// SAP date text (`yyyyMMdd` or `yyyy-MM-dd`) as `dd.MM.yyyy`; empty for
    /// empty or zero dates.
    static func germanDate(sapValue: String) -> String {
        let digits = sapValue.filter(\.isNumber)
        guard digits.count == 8, digits != "00000000" else { return "" }
        let chars = Array(digits)
        return "\(String(chars[6...7])).\(String(chars[4...5])).\(String(chars[0...3]))"
    }

    /// `resolveWeekNumber`: ISO 8601 calendar week.
    static func calendarWeek(_ date: Date) -> Int {
        var calendar = Calendar(identifier: .iso8601)
        calendar.timeZone = .current
        return calendar.component(.weekOfYear, from: date)
    }

    static func withoutLeadingZeros(_ value: String) -> String {
        value.replacingOccurrences(of: "^0+", with: "", options: .regularExpression)
    }

    private static func format(_ date: Date, _ pattern: String) -> String {
        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.locale = Locale(identifier: "de_DE")
        formatter.dateFormat = pattern
        return formatter.string(from: date)
    }
}

/// Uppercased string view of the SAP `T_0271` notification row (including the
/// decoded `FELDWERT`) that the legacy `buildPDF` functions read from.
struct NotificationReportFields: Sendable, Equatable {
    private let values: [String: String]

    init(values: [String: String]) {
        self.values = Dictionary(values.map { ($0.key.uppercased(), $0.value) }) { first, _ in first }
    }

    /// The cached notification JSON, merged with its decoded `FELDWERT` like
    /// the upload builders do.
    init(rawPayloadJSON: String) {
        guard let data = rawPayloadJSON.data(using: .utf8),
              var payload = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
        else {
            self.init(values: [:])
            return
        }
        if let feldwert = payload.first(where: { $0.key.caseInsensitiveCompare("FELDWERT") == .orderedSame })?.value as? String,
           let decoded = SAPLegacyDataExchangeCodec.cachedNotificationPayload(fromFeldwert: feldwert) {
            payload.merge(decoded) { _, decodedValue in decodedValue }
        }
        self.init(payload: payload)
    }

    init(payload: [String: Any]) {
        var strings: [String: String] = [:]
        for (key, value) in payload {
            if let string = value as? String {
                strings[key.uppercased()] = string.trimmingCharacters(in: .whitespacesAndNewlines)
            } else if let number = value as? NSNumber {
                strings[key.uppercased()] = number.stringValue
            }
        }
        self.init(values: strings)
    }

    subscript(_ key: String) -> String { values[key.uppercased()] ?? "" }
}

/// Page composer for the I1 reports: A4 with the `pageMargins` of the legacy
/// `PdfBuilder` ([25, 25, 25, 50]) and its three-column footer with
/// "Seite X von Y". Content is recorded per page first, so the footer knows
/// the page count.
final class NotificationReportComposer {
    static let pageSize = CGSize(width: 595.28, height: 841.89)
    static let margin: CGFloat = 25
    static let bottomMargin: CGFloat = 50
    static let borderColor = UIColor.black
    static let greyFill = UIColor(white: 0xDD / 255.0, alpha: 1)

    let left = NotificationReportComposer.margin
    let contentWidth = NotificationReportComposer.pageSize.width - NotificationReportComposer.margin * 2
    var bottom: CGFloat { Self.pageSize.height - Self.bottomMargin }
    private(set) var y = NotificationReportComposer.margin
    private var pages: [[(CGContext) -> Void]] = [[]]

    func draw(_ command: @escaping (CGContext) -> Void) {
        pages[pages.count - 1].append(command)
    }

    func advance(_ height: CGFloat) { y += height }

    func newPage() {
        pages.append([])
        y = Self.margin
    }

    /// Moves to a new page when `height` does not fit below the current
    /// position (pdfmake `dontBreakRows` / `unbreakable`).
    func ensureSpace(_ height: CGFloat) {
        if y + height > bottom, y > Self.margin { newPage() }
    }

    func render(organization: NotificationReportOrganization) -> Data {
        let renderer = UIGraphicsPDFRenderer(bounds: CGRect(origin: .zero, size: Self.pageSize))
        let pageCount = pages.count
        return renderer.pdfData { context in
            for (index, commands) in pages.enumerated() {
                context.beginPage()
                let cg = context.cgContext
                commands.forEach { $0(cg) }
                drawFooter(page: index + 1, of: pageCount, organization: organization, in: cg)
            }
        }
    }

    private func drawFooter(page: Int, of count: Int, organization: NotificationReportOrganization, in cg: CGContext) {
        let top = bottom
        Self.strokeLine(from: CGPoint(x: left, y: top), to: CGPoint(x: left + contentWidth, y: top), width: 0.8, in: cg)
        let columns = organization.footerColumns
        let font = UIFont.systemFont(ofSize: 7)
        // 40 % / 40 % / 20 % like pdfmake; the middle column may run into the
        // page-number column, whose text is right-aligned and short.
        Self.drawText(columns.left, in: CGRect(x: left + 4, y: top + 3, width: contentWidth * 0.4 - 8, height: 44), font: font)
        Self.drawText(columns.middle, in: CGRect(x: left + contentWidth * 0.4 + 4, y: top + 3, width: contentWidth * 0.46, height: 44), font: font)
        Self.drawText(
            "Seite \(page) von \(count)",
            in: CGRect(x: left + contentWidth * 0.8, y: top + 3, width: contentWidth * 0.2 - 15, height: 14),
            font: .italicSystemFont(ofSize: 10),
            alignment: .right
        )
    }

    // MARK: - Tables

    enum Borders {
        /// Every cell framed (pdfmake default layout).
        case grid
        /// Horizontal rules only.
        case horizontal(top: Bool, bottom: Bool)
        case none
    }

    struct Cell {
        var text: String = ""
        var font: UIFont = .systemFont(ofSize: 8)
        var alignment: NSTextAlignment = .left
        var image: UIImage? = nil
        var imageWidth: CGFloat = 0
        var fill: UIColor? = nil
        /// Number of columns the cell covers.
        var span: Int = 1
        /// pdfmake cell padding plus the cell's own `margin`.
        var insets = UIEdgeInsets(top: 2, left: 4, bottom: 2, right: 4)
    }

    /// Height of one table row: the tallest cell, like pdfmake.
    func rowHeight(_ cells: [Cell], widths: [CGFloat]) -> CGFloat {
        zip(cells, cellWidths(cells, widths: widths)).map { cell, width in
            let contentWidth = max(1, width - cell.insets.left - cell.insets.right)
            var height = Self.textHeight(cell.text, width: contentWidth, font: cell.font)
            if let image = cell.image, image.size.width > 0 {
                height = max(height, cell.imageWidth * image.size.height / image.size.width)
            }
            return ceil(height) + cell.insets.top + cell.insets.bottom
        }.max() ?? 0
    }

    /// Draws one table row at the current position, starting a new page first
    /// when the row does not fit; the row never splits.
    func tableRow(_ cells: [Cell], widths: [CGFloat], borders: Borders, minHeight: CGFloat = 0) {
        let height = max(minHeight, rowHeight(cells, widths: widths))
        ensureSpace(height)
        drawRow(cells, widths: widths, borders: borders, at: y, height: height)
        y += height
    }

    func drawRow(_ cells: [Cell], widths: [CGFloat], borders: Borders, at top: CGFloat, height: CGFloat) {
        var x = left
        let spans = cellWidths(cells, widths: widths)
        let tableWidth = widths.reduce(0, +)
        for (cell, width) in zip(cells, spans) {
            let rect = CGRect(x: x, y: top, width: width, height: height)
            draw { cg in Self.drawCell(cell, in: rect, borders: borders, in: cg) }
            x += width
        }
        if case let .horizontal(topRule, bottomRule) = borders {
            let rowLeft = left
            draw { cg in
                if topRule {
                    Self.strokeLine(from: CGPoint(x: rowLeft, y: top), to: CGPoint(x: rowLeft + tableWidth, y: top), width: 0.8, in: cg)
                }
                if bottomRule {
                    Self.strokeLine(from: CGPoint(x: rowLeft, y: top + height), to: CGPoint(x: rowLeft + tableWidth, y: top + height), width: 0.8, in: cg)
                }
            }
        }
    }

    /// A full-width rule (`drawLineToDoc`).
    func rule(spacing: CGFloat) {
        y += spacing
        let lineY = y
        let x = left
        let width = contentWidth
        draw { cg in
            Self.strokeLine(from: CGPoint(x: x, y: lineY), to: CGPoint(x: x + width, y: lineY), width: 0.6, in: cg)
        }
    }

    private func cellWidths(_ cells: [Cell], widths: [CGFloat]) -> [CGFloat] {
        var index = 0
        return cells.map { cell in
            let end = min(widths.count, index + max(1, cell.span))
            defer { index = end }
            return widths[index..<end].reduce(0, +)
        }
    }

    private static func drawCell(_ cell: Cell, in rect: CGRect, borders: Borders, in cg: CGContext) {
        if let fill = cell.fill {
            cg.setFillColor(fill.cgColor)
            cg.fill(rect)
        }
        let content = rect.inset(by: cell.insets)
        if let image = cell.image, image.size.width > 0 {
            let height = cell.imageWidth * image.size.height / image.size.width
            let x: CGFloat
            switch cell.alignment {
            case .center: x = content.midX - cell.imageWidth / 2
            case .right: x = content.maxX - cell.imageWidth
            default: x = content.minX
            }
            image.draw(in: CGRect(x: x, y: content.minY, width: cell.imageWidth, height: height))
        }
        if !cell.text.isEmpty {
            drawText(cell.text, in: content, font: cell.font, alignment: cell.alignment)
        }
        if case .grid = borders {
            cg.setStrokeColor(borderColor.cgColor)
            cg.setLineWidth(0.8)
            cg.stroke(rect)
        }
    }

    // MARK: - Drawing primitives

    static func drawText(
        _ text: String,
        in rect: CGRect,
        font: UIFont,
        color: UIColor = .black,
        alignment: NSTextAlignment = .left
    ) {
        let style = NSMutableParagraphStyle()
        style.alignment = alignment
        style.lineBreakMode = .byWordWrapping
        (text as NSString).draw(
            with: rect,
            options: [.usesLineFragmentOrigin, .usesFontLeading],
            attributes: [.font: font, .foregroundColor: color, .paragraphStyle: style],
            context: nil
        )
    }

    static func textHeight(_ text: String, width: CGFloat, font: UIFont) -> CGFloat {
        let measured = text.isEmpty ? " " : text
        return (measured as NSString).boundingRect(
            with: CGSize(width: width, height: .greatestFiniteMagnitude),
            options: [.usesLineFragmentOrigin, .usesFontLeading],
            attributes: [.font: font],
            context: nil
        ).height
    }

    static func textWidth(_ text: String, font: UIFont) -> CGFloat {
        ceil((text as NSString).size(withAttributes: [.font: font]).width)
    }

    static func strokeLine(from start: CGPoint, to end: CGPoint, width: CGFloat, in cg: CGContext) {
        cg.saveGState()
        cg.setStrokeColor(borderColor.cgColor)
        cg.setLineWidth(width)
        cg.move(to: start)
        cg.addLine(to: end)
        cg.strokePath()
        cg.restoreGState()
    }
}
