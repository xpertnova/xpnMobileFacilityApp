import Foundation
import PDFKit
import SwiftUI
import UIKit

/// Frozen, local-only input for the legacy briefing PDF. It deliberately has
/// no SAP transport types or synchronization behavior.
struct BriefingPDFPayload: Sendable, Equatable {
    struct Section: Sendable, Equatable, Identifiable {
        let id: String
        let title: String
        let number: Int
        let items: [Item]
    }

    struct Item: Sendable, Equatable, Identifiable {
        enum Answer: Sendable, Equatable {
            case yes(key: String, title: String)
            case no(key: String, title: String)
            case notApplicable
        }

        let id: String
        let number: String
        let rowType: SAPBriefingTemplateRowType
        let title: String
        let answer: Answer
        let comment: String
        let warningSymbolID: String?
    }

    let planNumber: String
    let instructorName: String
    let organizationUnit: String
    let coordinator: String
    let partnerName: String
    let partnerAddress: String
    let instructedPerson: String
    let businessEntity: String
    let workLocation: String
    let taskDescription: String
    let startDate: Date
    let endDate: Date
    let completedAt: Date
    let localeIdentifier: String
    let instructorSignature: Data
    let instructedPersonSignature: Data
    let sections: [Section]
}

struct BriefingPDFArtifact: Identifiable, Sendable, Equatable {
    let id: UUID
    let data: Data
    let fileName: String
    let createdAt: Date

    init(
        id: UUID = UUID(),
        data: Data,
        fileName: String,
        createdAt: Date
    ) {
        self.id = id
        self.data = data
        self.fileName = fileName
        self.createdAt = createdAt
    }
}

enum BriefingPDFRenderingError: LocalizedError {
    case emptyDocument

    var errorDescription: String? {
        String(localized: "briefing.pdf.createFailed")
    }
}

/// Core Graphics port of the legacy Cordova pdfmake briefing document, using
/// the same content order, A4 sizing, table proportions, and pagination.
struct LegacyBriefingPDFRenderer: Sendable {
    private enum Layout {
        static let pageSize = CGSize(width: 595.28, height: 841.89)
        static let leftMargin: CGFloat = 25
        static let topMargin: CGFloat = 25
        static let rightMargin: CGFloat = 25
        static let bottomMargin: CGFloat = 50
        static let headerFont = UIFont.boldSystemFont(ofSize: 22)
        static let tableHeaderFont = UIFont.boldSystemFont(ofSize: 12)
        static let bodyFont = UIFont.systemFont(ofSize: 10)
        static let bodyBoldFont = UIFont.boldSystemFont(ofSize: 10)
        static let subInfoFont = UIFont.systemFont(ofSize: 8)
        static let footerFont = UIFont.italicSystemFont(ofSize: 10)
        static let tableHeaderHeight: CGFloat = 30
        static let sectionHeight: CGFloat = 24
        static let borderColor = UIColor.black.withAlphaComponent(0.75)
        static let sectionFill = UIColor(white: 0.93, alpha: 1)
    }

    func render(_ payload: BriefingPDFPayload) throws -> BriefingPDFArtifact {
        let copy = BriefingPDFCopy(localeIdentifier: payload.localeIdentifier)
        let totalPageCount = 1 + checklistPageCount(for: payload)
        let renderer = UIGraphicsPDFRenderer(
            bounds: CGRect(origin: .zero, size: Layout.pageSize)
        )
        let data = renderer.pdfData { context in
            context.beginPage()
            drawFirstPage(
                context: context.cgContext,
                payload: payload,
                copy: copy,
                pageNumber: 1,
                pageCount: totalPageCount
            )
            drawChecklistPages(
                context: context,
                payload: payload,
                copy: copy,
                firstPageNumber: 2,
                pageCount: totalPageCount
            )
        }

        guard !data.isEmpty else { throw BriefingPDFRenderingError.emptyDocument }
        return BriefingPDFArtifact(
            data: data,
            fileName: fileName(for: payload),
            createdAt: payload.completedAt
        )
    }

    private func drawFirstPage(
        context: CGContext,
        payload: BriefingPDFPayload,
        copy: BriefingPDFCopy,
        pageNumber: Int,
        pageCount: Int
    ) {
        var y = Layout.topMargin
        let titleHeight = max(
            55,
            textHeight(copy.title, width: contentWidth, font: Layout.headerFont) + 8
        )
        let titleRect = CGRect(
            x: Layout.leftMargin,
            y: y,
            width: contentWidth,
            height: titleHeight
        )
        drawText(copy.title, in: titleRect, font: Layout.headerFont, alignment: .center)
        y = titleRect.maxY + 5

        let headerRows = [
            BriefingPDFHeaderRow(
                label: "\(copy.instructor)\n\(copy.employeeHint)",
                value: payload.instructorName,
                secondaryLabel: copy.organizationHint,
                secondaryValue: payload.organizationUnit
            ),
            BriefingPDFHeaderRow(label: copy.coordinator, value: payload.coordinator),
            BriefingPDFHeaderRow(
                label: "\(copy.partnerCompany)\n\(copy.nameAndAddressHint)",
                value: [payload.partnerName, payload.partnerAddress]
                    .filter { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
                    .joined(separator: "\n")
            ),
            BriefingPDFHeaderRow(label: copy.instructedPerson, value: payload.instructedPerson),
            BriefingPDFHeaderRow(
                label: copy.workLocation,
                value: [payload.businessEntity, payload.workLocation]
                    .filter { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
                    .joined(separator: "\n")
            ),
            BriefingPDFHeaderRow(label: copy.task, value: payload.taskDescription),
            BriefingPDFHeaderRow(
                label: "\(copy.executionPeriod)\n\(copy.dateHint)",
                value: "\(formattedDate(payload.startDate, localeIdentifier: payload.localeIdentifier)) - \(formattedDate(payload.endDate, localeIdentifier: payload.localeIdentifier))"
            )
        ]
        y = drawHeaderTable(headerRows, at: y, context: context) + 9

        for declaration in copy.declarations {
            let height = max(
                34,
                textHeight(declaration, width: contentWidth, font: Layout.bodyBoldFont) + 8
            )
            drawText(
                declaration,
                in: CGRect(x: Layout.leftMargin, y: y, width: contentWidth, height: height),
                font: Layout.bodyBoldFont
            )
            y += height + 2
        }

        drawSignatureTable(
            at: y + 6,
            context: context,
            payload: payload,
            copy: copy
        )
        drawFooter(context: context, pageNumber: pageNumber, pageCount: pageCount, copy: copy)
    }

    private func drawHeaderTable(
        _ rows: [BriefingPDFHeaderRow],
        at originY: CGFloat,
        context: CGContext
    ) -> CGFloat {
        var y = originY
        let labelWidth = contentWidth * 0.48
        let valueWidth = contentWidth - labelWidth

        for row in rows {
            let primaryHeight = max(
                textHeight(row.label, width: labelWidth - 10, font: Layout.bodyFont),
                textHeight(row.value, width: valueWidth - 10, font: Layout.bodyFont)
            ) + 12
            let secondaryHeight: CGFloat = row.secondaryLabel == nil ? 0 : 30
            let height = max(CGFloat(31), primaryHeight + secondaryHeight)
            let labelRect = CGRect(x: Layout.leftMargin, y: y, width: labelWidth, height: height)
            let valueRect = CGRect(x: labelRect.maxX, y: y, width: valueWidth, height: height)
            drawCell(labelRect, context: context)
            drawCell(valueRect, context: context)
            drawText(row.label, in: labelRect.insetBy(dx: 5, dy: 5), font: Layout.bodyFont)
            drawText(row.value, in: valueRect.insetBy(dx: 5, dy: 5), font: Layout.bodyFont)

            if let secondaryLabel = row.secondaryLabel,
               let secondaryValue = row.secondaryValue {
                drawText(
                    secondaryLabel,
                    in: CGRect(
                        x: labelRect.minX + 5,
                        y: labelRect.maxY - 16,
                        width: labelRect.width - 10,
                        height: 12
                    ),
                    font: Layout.subInfoFont
                )
                drawText(
                    secondaryValue,
                    in: CGRect(
                        x: valueRect.minX + 5,
                        y: valueRect.maxY - 16,
                        width: valueRect.width - 10,
                        height: 12
                    ),
                    font: Layout.subInfoFont
                )
            }
            y += height
        }
        return y
    }

    private func drawSignatureTable(
        at originY: CGFloat,
        context: CGContext,
        payload: BriefingPDFPayload,
        copy: BriefingPDFCopy
    ) {
        let columnWidth = contentWidth / 2
        let timestamp = formattedDateTime(
            payload.completedAt,
            localeIdentifier: payload.localeIdentifier
        )
        let leftDate = CGRect(x: Layout.leftMargin, y: originY, width: columnWidth, height: 30)
        let rightDate = CGRect(x: leftDate.maxX, y: originY, width: columnWidth, height: 30)
        drawCell(leftDate, context: context)
        drawCell(rightDate, context: context)
        drawText("\(copy.dateTime): \(timestamp)", in: leftDate.insetBy(dx: 5, dy: 5), font: Layout.bodyFont)
        drawText("\(copy.dateTime): \(timestamp)", in: rightDate.insetBy(dx: 5, dy: 5), font: Layout.bodyFont)

        let leftLabel = CGRect(x: leftDate.minX, y: leftDate.maxY, width: columnWidth, height: 24)
        let rightLabel = CGRect(x: rightDate.minX, y: rightDate.maxY, width: columnWidth, height: 24)
        drawCell(leftLabel, context: context)
        drawCell(rightLabel, context: context)
        drawText(copy.signatureInstructor, in: leftLabel.insetBy(dx: 4, dy: 3), font: Layout.bodyFont, alignment: .center)
        drawText(copy.signatureInstructedPerson, in: rightLabel.insetBy(dx: 4, dy: 3), font: Layout.bodyFont, alignment: .center)

        let leftImage = CGRect(x: leftDate.minX, y: leftLabel.maxY, width: columnWidth, height: 84)
        let rightImage = CGRect(x: rightDate.minX, y: rightLabel.maxY, width: columnWidth, height: 84)
        drawCell(leftImage, context: context)
        drawCell(rightImage, context: context)
        drawSignature(payload.instructorSignature, in: leftImage.insetBy(dx: 10, dy: 5))
        drawSignature(payload.instructedPersonSignature, in: rightImage.insetBy(dx: 10, dy: 5))

        let leftCaption = CGRect(x: leftDate.minX, y: leftImage.maxY, width: columnWidth, height: 22)
        let rightCaption = CGRect(x: rightDate.minX, y: rightImage.maxY, width: columnWidth, height: 22)
        drawCell(leftCaption, context: context)
        drawCell(rightCaption, context: context)
        drawText(copy.signature, in: leftCaption.insetBy(dx: 4, dy: 3), font: Layout.bodyFont, alignment: .center)
        drawText(copy.signature, in: rightCaption.insetBy(dx: 4, dy: 3), font: Layout.bodyFont, alignment: .center)
        drawText(
            "[ X ] \(copy.copyDelivered)",
            in: CGRect(x: Layout.leftMargin, y: leftCaption.maxY + 5, width: contentWidth, height: 18),
            font: Layout.bodyFont
        )
    }

    private func drawSignature(_ data: Data, in rect: CGRect) {
        guard let image = UIImage(data: data), image.size.width > 0, image.size.height > 0 else { return }
        let scale = min(rect.width / image.size.width, rect.height / image.size.height)
        let size = CGSize(width: image.size.width * scale, height: image.size.height * scale)
        image.draw(in: CGRect(
            x: rect.midX - size.width / 2,
            y: rect.midY - size.height / 2,
            width: size.width,
            height: size.height
        ))
    }

    private func drawChecklistPages(
        context: UIGraphicsPDFRendererContext,
        payload: BriefingPDFPayload,
        copy: BriefingPDFCopy,
        firstPageNumber: Int,
        pageCount: Int
    ) {
        var pageNumber = firstPageNumber
        context.beginPage()
        var graphicsContext = context.cgContext
        var y = drawChecklistHeader(at: Layout.topMargin, context: graphicsContext, copy: copy)

        for section in payload.sections {
            let firstItemHeight = section.items.first.map(checklistItemHeight) ?? 0
            if y + Layout.sectionHeight + firstItemHeight > contentBottom {
                drawFooter(context: graphicsContext, pageNumber: pageNumber, pageCount: pageCount, copy: copy)
                pageNumber += 1
                context.beginPage()
                graphicsContext = context.cgContext
                y = drawChecklistHeader(at: Layout.topMargin, context: graphicsContext, copy: copy)
            }

            let sectionRect = CGRect(
                x: Layout.leftMargin,
                y: y,
                width: contentWidth,
                height: Layout.sectionHeight
            )
            drawCell(sectionRect, fill: Layout.sectionFill, context: graphicsContext)
            drawText(
                "\(section.number). \(section.title)",
                in: sectionRect.insetBy(dx: 5, dy: 4),
                font: Layout.bodyBoldFont
            )
            y = sectionRect.maxY

            for item in section.items {
                let height = checklistItemHeight(item)
                if y + height > contentBottom {
                    drawFooter(context: graphicsContext, pageNumber: pageNumber, pageCount: pageCount, copy: copy)
                    pageNumber += 1
                    context.beginPage()
                    graphicsContext = context.cgContext
                    y = drawChecklistHeader(at: Layout.topMargin, context: graphicsContext, copy: copy)
                }
                drawChecklistItem(item, at: y, height: height, context: graphicsContext, copy: copy)
                y += height
            }
        }
        drawFooter(context: graphicsContext, pageNumber: pageNumber, pageCount: pageCount, copy: copy)
    }

    private func checklistPageCount(for payload: BriefingPDFPayload) -> Int {
        var pages = 1
        var y = Layout.topMargin + Layout.tableHeaderHeight
        for section in payload.sections {
            let firstItemHeight = section.items.first.map(checklistItemHeight) ?? 0
            if y + Layout.sectionHeight + firstItemHeight > contentBottom {
                pages += 1
                y = Layout.topMargin + Layout.tableHeaderHeight
            }
            y += Layout.sectionHeight
            for item in section.items {
                let height = checklistItemHeight(item)
                if y + height > contentBottom {
                    pages += 1
                    y = Layout.topMargin + Layout.tableHeaderHeight
                }
                y += height
            }
        }
        return pages
    }

    private func drawChecklistHeader(
        at y: CGFloat,
        context: CGContext,
        copy: BriefingPDFCopy
    ) -> CGFloat {
        let labels = [copy.number, copy.tasks, copy.completed, copy.comment]
        var x = Layout.leftMargin
        for (index, width) in checklistColumnWidths.enumerated() {
            let rect = CGRect(x: x, y: y, width: width, height: Layout.tableHeaderHeight)
            drawCell(rect, fill: Layout.sectionFill, context: context)
            drawText(
                labels[index],
                in: rect.insetBy(dx: 4, dy: 5),
                font: Layout.tableHeaderFont,
                alignment: index == 2 ? .center : .left
            )
            x = rect.maxX
        }
        return y + Layout.tableHeaderHeight
    }

    private func drawChecklistItem(
        _ item: BriefingPDFPayload.Item,
        at y: CGFloat,
        height: CGFloat,
        context: CGContext,
        copy: BriefingPDFCopy
    ) {
        var x = Layout.leftMargin
        let rects = checklistColumnWidths.map { width -> CGRect in
            defer { x += width }
            return CGRect(x: x, y: y, width: width, height: height)
        }
        rects.forEach { drawCell($0, context: context) }
        drawChecklistNumber(item.number, in: rects[0].insetBy(dx: 3, dy: 4))
        drawText(item.title, in: rects[1].insetBy(dx: 4, dy: 4), font: Layout.bodyFont)
        drawAnswer(
            item.answer,
            warningSymbolID: item.warningSymbolID,
            in: rects[2].insetBy(dx: 3, dy: 3),
            context: context,
            copy: copy
        )
        drawText(item.comment, in: rects[3].insetBy(dx: 4, dy: 4), font: Layout.bodyFont)
    }

    private func drawAnswer(
        _ answer: BriefingPDFPayload.Item.Answer,
        warningSymbolID: String?,
        in rect: CGRect,
        context: CGContext,
        copy: BriefingPDFCopy
    ) {
        let isYes: Bool
        let isNo: Bool
        switch answer {
        case .yes:
            isYes = true
            isNo = false
        case .no:
            isYes = false
            isNo = true
        case .notApplicable:
            isYes = false
            isNo = false
        }

        let iconWidth: CGFloat = 28
        let answerWidth = max(44, (rect.width - iconWidth) / 2)
        drawCheckbox(
            label: copy.yes,
            isSelected: isYes,
            in: CGRect(x: rect.minX, y: rect.minY, width: answerWidth, height: rect.height),
            context: context
        )
        drawCheckbox(
            label: copy.no,
            isSelected: isNo,
            in: CGRect(x: rect.minX + answerWidth, y: rect.minY, width: answerWidth, height: rect.height),
            context: context
        )

        guard let symbol = warningImage(for: warningSymbolID) else { return }
        symbol.draw(in: CGRect(
            x: rect.maxX - iconWidth + 3,
            y: rect.midY - 9,
            width: 18,
            height: 18
        ))
    }

    private func warningImage(for identifier: String?) -> UIImage? {
        let assetName: String?
        switch identifier?.trimmingCharacters(in: .whitespacesAndNewlines).uppercased() {
        case "I001": assetName = "BriefingSafety_I001"
        case "M014": assetName = "BriefingSafety_M014"
        case "P002": assetName = "BriefingSafety_P002"
        case "W001": assetName = "BriefingSafety_W001"
        case "W002": assetName = "BriefingSafety_W002"
        case "ig": assetName = "BriefingSafety_W003"
        case "X001": assetName = "BriefingSafety_X001"
        default: assetName = nil
        }
        if let assetName, let image = UIImage(named: assetName) {
            return image
        }
        guard identifier?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false else {
            return nil
        }
        return UIImage(systemName: "exclamationmark.triangle.fill")
    }

    private func drawCheckbox(
        label: String,
        isSelected: Bool,
        in rect: CGRect,
        context: CGContext
    ) {
        let box = CGRect(x: rect.minX + 2, y: rect.midY - 6, width: 12, height: 12)
        context.setStrokeColor(Layout.borderColor.cgColor)
        context.setLineWidth(0.8)
        context.stroke(box)
        if isSelected {
            context.setStrokeColor(UIColor.black.cgColor)
            context.setLineWidth(1.5)
            context.move(to: CGPoint(x: box.minX + 2, y: box.midY))
            context.addLine(to: CGPoint(x: box.midX - 0.5, y: box.maxY - 2))
            context.addLine(to: CGPoint(x: box.maxX - 2, y: box.minY + 2))
            context.strokePath()
        }
        drawText(
            label,
            in: CGRect(
                x: box.maxX + 3,
                y: rect.minY,
                width: max(0, rect.maxX - box.maxX - 3),
                height: rect.height
            ),
            font: Layout.bodyFont
        )
    }

    private func checklistItemHeight(_ item: BriefingPDFPayload.Item) -> CGFloat {
        let height = max(
            textHeight(item.title, width: checklistColumnWidths[1] - 8, font: Layout.bodyFont),
            textHeight(item.comment, width: checklistColumnWidths[3] - 8, font: Layout.bodyFont)
        )
        return max(32, ceil(height) + 8)
    }

    private var checklistColumnWidths: [CGFloat] {
        // Section/item identifiers can be multi-digit (for example, 12.08).
        // Keep their column wide enough to preserve a single-line identifier.
        [contentWidth * 0.08, contentWidth * 0.47, contentWidth * 0.30, contentWidth * 0.15]
    }

    private func drawChecklistNumber(_ number: String, in rect: CGRect) {
        let baseFont = UIFont.monospacedDigitSystemFont(ofSize: 9, weight: .regular)
        let naturalWidth = (number as NSString).size(withAttributes: [.font: baseFont]).width
        let fittedSize = naturalWidth > rect.width
            ? max(7, baseFont.pointSize * rect.width / naturalWidth)
            : baseFont.pointSize
        let font = UIFont.monospacedDigitSystemFont(ofSize: fittedSize, weight: .regular)

        // `draw(in:withAttributes:)` is intentionally single-line. A checklist
        // identifier must never break between its section and item components.
        (number as NSString).draw(
            in: rect,
            withAttributes: [
                .font: font,
                .foregroundColor: UIColor.black
            ]
        )
    }

    private var contentWidth: CGFloat {
        Layout.pageSize.width - Layout.leftMargin - Layout.rightMargin
    }

    private var contentBottom: CGFloat {
        Layout.pageSize.height - Layout.bottomMargin
    }

    private func drawCell(
        _ rect: CGRect,
        fill: UIColor? = nil,
        context: CGContext
    ) {
        if let fill {
            context.setFillColor(fill.cgColor)
            context.fill(rect)
        }
        context.setStrokeColor(Layout.borderColor.cgColor)
        context.setLineWidth(0.6)
        context.stroke(rect)
    }

    private func drawFooter(
        context: CGContext,
        pageNumber: Int,
        pageCount: Int,
        copy: BriefingPDFCopy
    ) {
        let text = String(
            format: copy.pageNumberFormat,
            locale: copy.locale,
            Int64(pageNumber),
            Int64(pageCount)
        )
        drawText(
            text,
            in: CGRect(
                x: Layout.leftMargin,
                y: Layout.pageSize.height - Layout.bottomMargin + 14,
                width: contentWidth,
                height: 18
            ),
            font: Layout.footerFont,
            alignment: .right
        )
    }

    private func drawText(
        _ text: String,
        in rect: CGRect,
        font: UIFont,
        alignment: NSTextAlignment = .left
    ) {
        let paragraph = NSMutableParagraphStyle()
        paragraph.alignment = alignment
        paragraph.lineBreakMode = .byWordWrapping
        (text as NSString).draw(
            with: rect,
            options: [.usesLineFragmentOrigin, .usesFontLeading],
            attributes: [
                .font: font,
                .foregroundColor: UIColor.black,
                .paragraphStyle: paragraph
            ],
            context: nil
        )
    }

    private func textHeight(_ text: String, width: CGFloat, font: UIFont) -> CGFloat {
        guard !text.isEmpty else { return font.lineHeight }
        let paragraph = NSMutableParagraphStyle()
        paragraph.lineBreakMode = .byWordWrapping
        return ceil((text as NSString).boundingRect(
            with: CGSize(width: max(width, 1), height: .greatestFiniteMagnitude),
            options: [.usesLineFragmentOrigin, .usesFontLeading],
            attributes: [.font: font, .paragraphStyle: paragraph],
            context: nil
        ).height)
    }

    private func formattedDate(_ date: Date, localeIdentifier: String) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: localeIdentifier)
        formatter.dateStyle = .short
        formatter.timeStyle = .none
        return formatter.string(from: date)
    }

    private func formattedDateTime(_ date: Date, localeIdentifier: String) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: localeIdentifier)
        formatter.dateStyle = .short
        formatter.timeStyle = .short
        return formatter.string(from: date)
    }

    private func fileName(for payload: BriefingPDFPayload) -> String {
        let baseName = payload.instructedPerson
            .folding(options: [.diacriticInsensitive, .caseInsensitive], locale: .current)
            .unicodeScalars
            .map { CharacterSet.alphanumerics.contains($0) ? String($0) : "-" }
            .joined()
            .replacingOccurrences(of: "--", with: "-")
            .trimmingCharacters(in: CharacterSet(charactersIn: "-"))
        let safeName = baseName.isEmpty ? "briefing" : baseName
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd-HHmm"
        return "Briefing-\(safeName)-\(formatter.string(from: payload.completedAt)).pdf"
    }
}

private struct BriefingPDFHeaderRow {
    let label: String
    let value: String
    var secondaryLabel: String?
    var secondaryValue: String?
}

private struct BriefingPDFCopy {
    let locale: Locale
    let title: String
    let instructor: String
    let employeeHint: String
    let organizationHint: String
    let coordinator: String
    let partnerCompany: String
    let nameAndAddressHint: String
    let instructedPerson: String
    let workLocation: String
    let task: String
    let executionPeriod: String
    let dateHint: String
    let declarations: [String]
    let dateTime: String
    let signatureInstructor: String
    let signatureInstructedPerson: String
    let signature: String
    let copyDelivered: String
    let number: String
    let tasks: String
    let completed: String
    let comment: String
    let yes: String
    let no: String
    let pageNumberFormat: String

    init(localeIdentifier: String) {
        locale = Locale(identifier: localeIdentifier)
        title = Self.localized("title", locale: locale)
        instructor = Self.localized("instructor", locale: locale)
        employeeHint = Self.localized("employeeHint", locale: locale)
        organizationHint = Self.localized("organizationHint", locale: locale)
        coordinator = Self.localized("coordinator", locale: locale)
        partnerCompany = Self.localized("partnerCompany", locale: locale)
        nameAndAddressHint = Self.localized("nameAndAddressHint", locale: locale)
        instructedPerson = Self.localized("instructedPerson", locale: locale)
        workLocation = Self.localized("workLocation", locale: locale)
        task = Self.localized("task", locale: locale)
        executionPeriod = Self.localized("executionPeriod", locale: locale)
        dateHint = Self.localized("dateHint", locale: locale)
        declarations = [
            Self.localized("declaration.one", locale: locale),
            Self.localized("declaration.two", locale: locale),
            Self.localized("declaration.three", locale: locale)
        ]
        dateTime = Self.localized("dateTime", locale: locale)
        signatureInstructor = Self.localized("signature.instructor", locale: locale)
        signatureInstructedPerson = Self.localized("signature.instructedPerson", locale: locale)
        signature = Self.localized("signature.caption", locale: locale)
        copyDelivered = Self.localized("copyDelivered", locale: locale)
        number = Self.localized("number", locale: locale)
        tasks = Self.localized("tasks", locale: locale)
        completed = Self.localized("completed", locale: locale)
        comment = Self.localized("comment", locale: locale)
        yes = Self.localized("yes", locale: locale)
        no = Self.localized("no", locale: locale)
        pageNumberFormat = Self.localized("pageNumber", locale: locale)
    }

    private static func localized(_ key: String, locale: Locale) -> String {
        let languageCode = locale.language.languageCode?.identifier ?? "en"
        let languageBundle = Bundle.main.path(forResource: languageCode, ofType: "lproj")
            .flatMap(Bundle.init(path:))
        return (languageBundle ?? .main).localizedString(
            forKey: key,
            value: key,
            table: "BriefingPDF"
        )
    }
}

struct BriefingPDFRenderingOverlay: View {
    var body: some View {
        ZStack {
            Color.black.opacity(0.25)
                .ignoresSafeArea()
            VStack(spacing: 14) {
                ProgressView()
                    .controlSize(.large)
                Text("briefing.pdf.preparing")
                    .multilineTextAlignment(.center)
            }
            .padding(28)
            .background(Color(uiColor: .systemBackground))
            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
            .shadow(color: .black.opacity(0.25), radius: 12, y: 4)
        }
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.updatesFrequently)
    }
}

struct BriefingPDFPreview: View {
    let artifact: BriefingPDFArtifact
    let onFinish: () -> Void

    @State private var shareItem: BriefingPDFShareItem?
    @State private var isShowingShareError = false

    var body: some View {
        NavigationStack {
            BriefingPDFDocumentView(data: artifact.data)
                .navigationTitle("briefing.pdf.title")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .confirmationAction) {
                        Button("briefing.pdf.finish") {
                            cleanUpShareFile()
                            onFinish()
                        }
                    }
                    ToolbarItem(placement: .primaryAction) {
                        Button {
                            prepareShare()
                        } label: {
                            Label("briefing.pdf.share", systemImage: "square.and.arrow.up")
                        }
                    }
                }
        }
        .interactiveDismissDisabled()
        .sheet(item: $shareItem, onDismiss: cleanUpShareFile) { item in
            BriefingActivitySheet(url: item.url, onComplete: cleanUpShareFile)
        }
        .alert("briefing.pdf.shareFailed.title", isPresented: $isShowingShareError) {
            Button("OK", role: .cancel) {}
        } message: {
            Text("briefing.pdf.shareFailed.message")
        }
        .onDisappear(perform: cleanUpShareFile)
    }

    private func prepareShare() {
        cleanUpShareFile()
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
            .appendingPathComponent(artifact.fileName)
        do {
            try FileManager.default.createDirectory(
                at: url.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
            try artifact.data.write(to: url, options: .atomic)
            shareItem = BriefingPDFShareItem(url: url)
        } catch {
            try? FileManager.default.removeItem(at: url.deletingLastPathComponent())
            isShowingShareError = true
        }
    }

    private func cleanUpShareFile() {
        guard let shareItem else { return }
        try? FileManager.default.removeItem(at: shareItem.url.deletingLastPathComponent())
        self.shareItem = nil
    }
}

struct BriefingReferenceDocumentPreview: View {
    let document: BriefingReferenceDocument

    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            Group {
                if let localURL {
                    BriefingPDFDocumentView(localURL: localURL)
                } else {
                    ContentUnavailableView(
                        "briefing.document.unavailable",
                        systemImage: "doc.questionmark"
                    )
                }
            }
            .navigationTitle(document.title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("app.button.close", action: dismiss.callAsFunction)
                }
                if let localURL {
                    ToolbarItem(placement: .primaryAction) {
                        ShareLink(item: localURL) {
                            Label("briefing.pdf.share", systemImage: "square.and.arrow.up")
                        }
                    }
                }
            }
        }
    }

    private var localURL: URL? {
        Bundle.main.url(forResource: document.fileName, withExtension: "pdf")
    }
}

struct BriefingPDFDocumentView: UIViewRepresentable {
    let document: PDFDocument?

    init(data: Data) {
        document = PDFDocument(data: data)
    }

    init(localURL: URL?) {
        document = localURL.flatMap(PDFDocument.init(url:))
    }

    func makeUIView(context: Context) -> PDFView {
        let view = PDFView()
        view.autoScales = true
        view.displayDirection = .vertical
        view.displayMode = .singlePageContinuous
        view.document = document
        return view
    }

    func updateUIView(_ view: PDFView, context: Context) {
        view.document = document
    }
}

private struct BriefingPDFShareItem: Identifiable {
    let id = UUID()
    let url: URL
}

private struct BriefingActivitySheet: UIViewControllerRepresentable {
    let url: URL
    let onComplete: () -> Void

    func makeUIViewController(context: Context) -> UIActivityViewController {
        let controller = UIActivityViewController(activityItems: [url], applicationActivities: nil)
        controller.completionWithItemsHandler = { _, _, _, _ in
            DispatchQueue.main.async(execute: onComplete)
        }
        return controller
    }

    func updateUIViewController(_ controller: UIActivityViewController, context: Context) {}
}
