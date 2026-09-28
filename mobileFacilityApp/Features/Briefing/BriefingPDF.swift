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
        let subtitle: String?
        let number: Int
        let items: [Item]

        init(
            id: String,
            title: String,
            subtitle: String? = nil,
            number: Int,
            items: [Item]
        ) {
            self.id = id
            self.title = title
            self.subtitle = subtitle
            self.number = number
            self.items = items
        }
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

    /// Raw PDF bytes encoded for the legacy SAP document field. This is
    /// intentionally not a data URL: T_0282.FELDWERT expects only Base64.
    var base64EncodedString: String {
        data.base64EncodedString()
    }

    var uploadPayload: FormPDFUploadPayload {
        FormPDFUploadPayload(
            fileName: fileName,
            mimeType: "application/pdf",
            base64Content: base64EncodedString
        )
    }
}

/// Transport-neutral representation shared by every form renderer. The SAP
/// adapter can map `base64Content` to T_0282.FELDWERT once its write operation
/// and acknowledgement semantics are composed at the production boundary.
struct FormPDFUploadPayload: Codable, Sendable, Equatable {
    let fileName: String
    let mimeType: String
    let base64Content: String
}

enum BriefingPDFRenderingError: LocalizedError {
    case emptyDocument

    var errorDescription: String? {
        String(localized: "briefing.pdf.createFailed", bundle: .appLanguage)
    }
}

/// Core Graphics port of the legacy briefing document matching the official
/// 5-page template, while dynamically laying out arbitrary checklist rows,
/// sections, subpositions, warning symbols, and multi-page continuation breaks.
struct LegacyBriefingPDFRenderer: Sendable {
    private enum Layout {
        static let pageSize = CGSize(width: 595.28, height: 841.89)
        static let leftMargin: CGFloat = 25
        static let topMargin: CGFloat = 25
        static let rightMargin: CGFloat = 25
        static let bottomMargin: CGFloat = 52
        static let headerFont = UIFont.boldSystemFont(ofSize: 18)
        static let tableHeaderFont = UIFont.boldSystemFont(ofSize: 10.5)
        static let bodyFont = UIFont.systemFont(ofSize: 9)
        static let bodyBoldFont = UIFont.boldSystemFont(ofSize: 9)
        static let subInfoFont = UIFont.systemFont(ofSize: 7.5)
        static let footerFont = UIFont.italicSystemFont(ofSize: 9)
        static let tableHeaderHeight: CGFloat = 24
        static let sectionHeight: CGFloat = 20
        static let borderColor = UIColor.black.withAlphaComponent(0.75)
        static let sectionFill = UIColor(white: 0.93, alpha: 1)
    }

    func render(_ payload: BriefingPDFPayload) throws -> BriefingPDFArtifact {
        let copy = BriefingPDFCopy()
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
        var y = drawBriefingHeader(
            context: context,
            payload: payload,
            copy: copy,
            startY: Layout.topMargin
        ) + 12

        for declaration in copy.declarations {
            let height = max(
                30,
                textHeight(declaration, width: contentWidth, font: Layout.bodyBoldFont) + 6
            )
            drawText(
                declaration,
                in: CGRect(x: Layout.leftMargin, y: y, width: contentWidth, height: height),
                font: Layout.bodyBoldFont
            )
            y += height + 4
        }

        drawSignatureTable(
            at: y + 8,
            context: context,
            payload: payload,
            copy: copy
        )
        drawFooter(context: context, pageNumber: pageNumber, pageCount: pageCount, copy: copy)
    }

    private func drawBriefingHeader(
        context: CGContext,
        payload: BriefingPDFPayload,
        copy: BriefingPDFCopy,
        startY: CGFloat
    ) -> CGFloat {
        var y = startY

        // Title block
        let titleHeight = max(44, textHeight(copy.title, width: contentWidth - 16, font: Layout.headerFont) + 14)
        let titleRect = CGRect(x: Layout.leftMargin, y: y, width: contentWidth, height: titleHeight)
        drawCell(titleRect, fill: .white, context: context)
        drawText(copy.title, in: titleRect.insetBy(dx: 8, dy: 7), font: Layout.headerFont, alignment: .center)
        y = titleRect.maxY

        // Row 1: Einweiser/Abnehmer(E.ON Mitarbeiter) | Name | Orgunit
        let r1Col1Width = contentWidth * 0.25
        let r1Col2Width = contentWidth * 0.50
        let r1Col3Width = contentWidth * 0.25
        let r1Label = "Einweiser/Abnehmer(E.ON\nMitarbeiter)"
        let orgText = payload.organizationUnit.isEmpty ? "e.on" : payload.organizationUnit
        let r1Org = "\(orgText)\n(E.ON-Organisationseinheit)"
        let r1Height = max(
            38,
            textHeight(r1Label, width: r1Col1Width - 10, font: Layout.bodyFont) + 10,
            textHeight(payload.instructorName, width: r1Col2Width - 10, font: Layout.bodyFont) + 10,
            textHeight(r1Org, width: r1Col3Width - 10, font: Layout.bodyFont) + 10
        )
        let r1Rect1 = CGRect(x: Layout.leftMargin, y: y, width: r1Col1Width, height: r1Height)
        let r1Rect2 = CGRect(x: r1Rect1.maxX, y: y, width: r1Col2Width, height: r1Height)
        let r1Rect3 = CGRect(x: r1Rect2.maxX, y: y, width: r1Col3Width, height: r1Height)
        drawCell(r1Rect1, context: context)
        drawCell(r1Rect2, context: context)
        drawCell(r1Rect3, context: context)
        drawText(r1Label, in: r1Rect1.insetBy(dx: 5, dy: 5), font: Layout.bodyFont)
        drawText(payload.instructorName, in: r1Rect2.insetBy(dx: 5, dy: 5), font: Layout.bodyFont)
        drawText(r1Org, in: r1Rect3.insetBy(dx: 5, dy: 5), font: Layout.bodyFont)
        y += r1Height

        // Rows 2 through 7 (50% / 50% split)
        let labelColWidth = contentWidth * 0.50
        let valueColWidth = contentWidth * 0.50

        let partner = [payload.partnerName, payload.partnerAddress]
            .filter { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
            .joined(separator: "\n")
        let location = [payload.businessEntity, payload.workLocation]
            .filter { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
            .joined(separator: "\n")
        let dateRange = "\(fixedDateOnly(payload.startDate)) - \(fixedDateOnly(payload.endDate))"

        let gridRows: [(String, String)] = [
            ("Benannter Koordinator ggf. SiGeKo gemäß BauStellV:\n(Wird bei gegenseitiger Gefährdung durch den Einweiser/Abnehmer benannt)", payload.coordinator),
            ("Partnerfirma/Auftragnehmer:\n(Name und Anschrift)", partner),
            ("Eingewiesener:\n(Verantwortlicher der Partnerfirma für die durchzuführenden Arbeiten)", payload.instructedPerson),
            ("Leistungs-/Arbeitsort:", location),
            ("Durchzuführende Arbeiten:", payload.taskDescription),
            ("Ausführung von ... bis... :\n(Datum)", dateRange)
        ]

        for (lbl, val) in gridRows {
            let rowHeight = max(
                34,
                textHeight(lbl, width: labelColWidth - 10, font: Layout.bodyFont) + 10,
                textHeight(val, width: valueColWidth - 10, font: Layout.bodyFont) + 10
            )
            let lblRect = CGRect(x: Layout.leftMargin, y: y, width: labelColWidth, height: rowHeight)
            let valRect = CGRect(x: lblRect.maxX, y: y, width: valueColWidth, height: rowHeight)
            drawCell(lblRect, context: context)
            drawCell(valRect, context: context)
            drawText(lbl, in: lblRect.insetBy(dx: 5, dy: 5), font: Layout.bodyFont)
            drawText(val, in: valRect.insetBy(dx: 5, dy: 5), font: Layout.bodyFont)
            y += rowHeight
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
        let timestamp = fixedDateTimeWithSeconds(payload.completedAt)

        let leftDate = CGRect(x: Layout.leftMargin, y: originY, width: columnWidth, height: 26)
        let rightDate = CGRect(x: leftDate.maxX, y: originY, width: columnWidth, height: 26)
        drawCell(leftDate, context: context)
        drawCell(rightDate, context: context)
        drawText("\(copy.dateTime): \(timestamp)", in: leftDate.insetBy(dx: 5, dy: 5), font: Layout.bodyFont)
        drawText("\(copy.dateTime): \(timestamp)", in: rightDate.insetBy(dx: 5, dy: 5), font: Layout.bodyFont)

        let boxHeight: CGFloat = 110
        let leftBox = CGRect(x: Layout.leftMargin, y: leftDate.maxY, width: columnWidth, height: boxHeight)
        let rightBox = CGRect(x: leftBox.maxX, y: rightDate.maxY, width: columnWidth, height: boxHeight)
        drawCell(leftBox, context: context)
        drawCell(rightBox, context: context)

        drawText(copy.signatureInstructor, in: CGRect(x: leftBox.minX, y: leftBox.minY + 4, width: columnWidth, height: 16), font: Layout.bodyFont, alignment: .center)
        drawText(copy.signatureInstructedPerson, in: CGRect(x: rightBox.minX, y: rightBox.minY + 4, width: columnWidth, height: 16), font: Layout.bodyFont, alignment: .center)

        drawSignature(payload.instructorSignature, in: CGRect(x: leftBox.minX + 15, y: leftBox.minY + 22, width: columnWidth - 30, height: 64))
        drawSignature(payload.instructedPersonSignature, in: CGRect(x: rightBox.minX + 15, y: rightBox.minY + 22, width: columnWidth - 30, height: 64))

        drawText(copy.signature, in: CGRect(x: leftBox.minX, y: leftBox.maxY - 18, width: columnWidth, height: 14), font: Layout.bodyFont, alignment: .center)
        drawText(copy.signature, in: CGRect(x: rightBox.minX, y: rightBox.maxY - 18, width: columnWidth, height: 14), font: Layout.bodyFont, alignment: .center)

        drawText(
            "[ X ]\(copy.copyDelivered)",
            in: CGRect(x: Layout.leftMargin, y: leftBox.maxY + 5, width: contentWidth, height: 18),
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
        var y = drawSectionOverview(
            payload.sections,
            at: Layout.topMargin,
            context: graphicsContext,
            copy: copy
        ) + 8
        y = drawChecklistHeader(at: y, context: graphicsContext, copy: copy)

        for section in payload.sections {
            let headerH = sectionHeaderHeight(section)
            let firstItemH = section.items.first.map(checklistItemHeight) ?? 0
            if y + headerH + firstItemH > contentBottom {
                drawFooter(context: graphicsContext, pageNumber: pageNumber, pageCount: pageCount, copy: copy)
                pageNumber += 1
                context.beginPage()
                graphicsContext = context.cgContext
                y = drawChecklistHeader(at: Layout.topMargin, context: graphicsContext, copy: copy)
            }

            y = drawSection(section, at: y, context: graphicsContext)

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

    private func sectionHeaderHeight(_ section: BriefingPDFPayload.Section) -> CGFloat {
        if section.items.isEmpty {
            let combined = [section.title, section.subtitle]
                .compactMap { $0 }
                .filter { !$0.isEmpty }
                .joined(separator: "\n")
            return max(28, ceil(textHeight(combined, width: contentWidth - 12, font: Layout.bodyFont)) + 10)
        }
        var total = Layout.sectionHeight
        if let subtitle = section.subtitle, !subtitle.isEmpty {
            total += max(22, ceil(textHeight(subtitle, width: contentWidth - 12, font: Layout.bodyFont)) + 8)
        }
        return total
    }

    private func drawSection(
        _ section: BriefingPDFPayload.Section,
        at y: CGFloat,
        context: CGContext
    ) -> CGFloat {
        if section.items.isEmpty {
            let combined = [section.title, section.subtitle]
                .compactMap { $0 }
                .filter { !$0.isEmpty }
                .joined(separator: "\n")
            let bannerHeight = max(28, ceil(textHeight(combined, width: contentWidth - 12, font: Layout.bodyFont)) + 10)
            let rect = CGRect(x: Layout.leftMargin, y: y, width: contentWidth, height: bannerHeight)
            drawCell(rect, fill: Layout.sectionFill, context: context)
            let paragraph = NSMutableParagraphStyle()
            paragraph.lineBreakMode = .byWordWrapping
            let attrString = NSMutableAttributedString()
            attrString.append(NSAttributedString(
                string: section.title + "\n",
                attributes: [.font: Layout.bodyBoldFont, .foregroundColor: UIColor.black, .paragraphStyle: paragraph]
            ))
            if let subtitle = section.subtitle, !subtitle.isEmpty {
                attrString.append(NSAttributedString(
                    string: subtitle,
                    attributes: [.font: Layout.bodyFont, .foregroundColor: UIColor.black, .paragraphStyle: paragraph]
                ))
            }
            attrString.draw(with: rect.insetBy(dx: 6, dy: 5), options: [.usesLineFragmentOrigin, .usesFontLeading], context: nil)
            return rect.maxY
        }

        let sectionRect = CGRect(x: Layout.leftMargin, y: y, width: contentWidth, height: Layout.sectionHeight)
        drawCell(sectionRect, fill: Layout.sectionFill, context: context)
        drawText(section.title, in: sectionRect.insetBy(dx: 5, dy: 3), font: Layout.bodyBoldFont)
        var nextY = sectionRect.maxY

        if let subtitle = section.subtitle, !subtitle.isEmpty {
            let subHeight = max(22, ceil(textHeight(subtitle, width: contentWidth - 12, font: Layout.bodyFont)) + 8)
            let subRect = CGRect(x: Layout.leftMargin, y: nextY, width: contentWidth, height: subHeight)
            drawCell(subRect, fill: .white, context: context)
            drawText(subtitle, in: subRect.insetBy(dx: 6, dy: 4), font: Layout.bodyFont)
            nextY = subRect.maxY
        }

        return nextY
    }

    private func checklistPageCount(for payload: BriefingPDFPayload) -> Int {
        var pages = 1
        var y = Layout.topMargin + sectionOverviewHeight(for: payload.sections) + 8
            + Layout.tableHeaderHeight
        for section in payload.sections {
            let headerH = sectionHeaderHeight(section)
            let firstItemH = section.items.first.map(checklistItemHeight) ?? 0
            if y + headerH + firstItemH > contentBottom {
                pages += 1
                y = Layout.topMargin + Layout.tableHeaderHeight
            }
            y += headerH
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

    private func drawSectionOverview(
        _ sections: [BriefingPDFPayload.Section],
        at y: CGFloat,
        context: CGContext,
        copy: BriefingPDFCopy
    ) -> CGFloat {
        let numberWidth: CGFloat = 36
        let headerHeight: CGFloat = 20
        let rowHeight: CGFloat = 20
        let numberHeader = CGRect(x: Layout.leftMargin, y: y, width: numberWidth, height: headerHeight)
        let taskHeader = CGRect(
            x: numberHeader.maxX,
            y: y,
            width: contentWidth - numberWidth,
            height: headerHeight
        )
        drawCell(numberHeader, fill: .white, context: context)
        drawCell(taskHeader, fill: .white, context: context)
        drawText(copy.number, in: numberHeader.insetBy(dx: 5, dy: 3), font: Layout.bodyFont)
        drawText(copy.tasks, in: taskHeader.insetBy(dx: 5, dy: 3), font: Layout.bodyFont)

        var rowY = y + headerHeight
        for section in sections {
            guard section.number > 0, !section.items.isEmpty else { continue }
            let numberRect = CGRect(x: Layout.leftMargin, y: rowY, width: numberWidth, height: rowHeight)
            let titleRect = CGRect(
                x: numberRect.maxX,
                y: rowY,
                width: contentWidth - numberWidth,
                height: rowHeight
            )
            drawCell(numberRect, fill: Layout.sectionFill, context: context)
            drawCell(titleRect, fill: Layout.sectionFill, context: context)
            drawText("\(section.number)", in: numberRect.insetBy(dx: 5, dy: 3), font: Layout.bodyBoldFont)
            drawText(section.title, in: titleRect.insetBy(dx: 5, dy: 3), font: Layout.bodyBoldFont)
            rowY += rowHeight
        }
        return rowY
    }

    private func sectionOverviewHeight(for sections: [BriefingPDFPayload.Section]) -> CGFloat {
        let validSections = sections.filter { $0.number > 0 && !$0.items.isEmpty }
        return 20 + CGFloat(validSections.count) * 20
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
                in: rect.insetBy(dx: 4, dy: 4),
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
        if item.rowType != .subposition {
            drawChecklistNumber(item.number, in: rects[0].insetBy(dx: 3, dy: 4))
        }
        drawText(item.title, in: rects[1].insetBy(dx: 4, dy: 4), font: Layout.bodyFont)
        drawAnswer(
            item.answer,
            warningSymbolID: item.warningSymbolID,
            in: rects[2].insetBy(dx: 4, dy: 4),
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

        let boxSize: CGFloat = 10.5
        let boxY = rect.minY + 1.0
        let textY = rect.minY + 0.5

        // Checkbox 1: Ja
        let jaBox = CGRect(x: rect.minX + 3.0, y: boxY, width: boxSize, height: boxSize)
        drawCheckboxBox(isSelected: isYes, in: jaBox, context: context)

        let jaLabelRect = CGRect(x: jaBox.maxX + 4.0, y: textY, width: 22, height: boxSize + 4)
        drawText(copy.yes, in: jaLabelRect, font: Layout.bodyFont)

        // Checkbox 2: Nein
        let neinBox = CGRect(x: jaBox.minX + 42.0, y: boxY, width: boxSize, height: boxSize)
        drawCheckboxBox(isSelected: isNo, in: neinBox, context: context)

        let neinLabelRect = CGRect(x: neinBox.maxX + 4.0, y: textY, width: 28, height: boxSize + 4)
        drawText(copy.no, in: neinLabelRect, font: Layout.bodyFont)

        guard let symbol = warningImage(for: warningSymbolID) else { return }
        let iconWidth: CGFloat = 20
        symbol.draw(in: CGRect(
            x: rect.maxX - iconWidth + 2,
            y: rect.minY + 1.0,
            width: 16,
            height: 16
        ))
    }

    private func drawCheckboxBox(
        isSelected: Bool,
        in box: CGRect,
        context: CGContext
    ) {
        context.saveGState()
        context.setStrokeColor(UIColor.black.cgColor)
        context.setLineWidth(0.8)
        context.stroke(box)
        if isSelected {
            context.setStrokeColor(UIColor.black.cgColor)
            context.setLineWidth(1.3)
            context.setLineCap(.round)
            context.setLineJoin(.round)
            context.beginPath()
            context.move(to: CGPoint(x: box.minX + 2.2, y: box.minY + 5.5))
            context.addLine(to: CGPoint(x: box.minX + 4.5, y: box.minY + 8.5))
            context.addLine(to: CGPoint(x: box.maxX - 2.0, y: box.minY + 2.5))
            context.strokePath()
        }
        context.restoreGState()
    }

    private func warningImage(for identifier: String?) -> UIImage? {
        let assetName: String?
        switch identifier?.trimmingCharacters(in: .whitespacesAndNewlines).uppercased() {
        case "I001": assetName = "BriefingSafety_I001"
        case "M014": assetName = "BriefingSafety_M014"
        case "P002": assetName = "BriefingSafety_P002"
        case "W001": assetName = "BriefingSafety_W001"
        case "W002": assetName = "BriefingSafety_W002"
        case "W003", "IG": assetName = "BriefingSafety_W003"
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

    private func checklistItemHeight(_ item: BriefingPDFPayload.Item) -> CGFloat {
        let height = max(
            textHeight(item.title, width: checklistColumnWidths[1] - 8, font: Layout.bodyFont),
            textHeight(item.comment, width: checklistColumnWidths[3] - 8, font: Layout.bodyFont)
        )
        return max(28, ceil(height) + 8)
    }

    private var checklistColumnWidths: [CGFloat] {
        [contentWidth * 0.08, contentWidth * 0.48, contentWidth * 0.20, contentWidth * 0.24]
    }

    private func drawChecklistNumber(_ number: String, in rect: CGRect) {
        let baseFont = UIFont.monospacedDigitSystemFont(ofSize: 8.5, weight: .regular)
        let naturalWidth = (number as NSString).size(withAttributes: [.font: baseFont]).width
        let fittedSize = naturalWidth > rect.width
            ? max(7, baseFont.pointSize * rect.width / naturalWidth)
            : baseFont.pointSize
        let font = UIFont.monospacedDigitSystemFont(ofSize: fittedSize, weight: .regular)

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
        let y = Layout.pageSize.height - 44
        context.setStrokeColor(Layout.borderColor.cgColor)
        context.setLineWidth(0.6)
        context.move(to: CGPoint(x: Layout.leftMargin, y: y))
        context.addLine(to: CGPoint(x: Layout.pageSize.width - Layout.rightMargin, y: y))
        context.strokePath()

        let leftText = "Geschäftsführer/Managing Directors: André Schrödel,\nDr. Marc Stienemann, Peter Olschewski, Zsolt Szabo"
        let centerText = "E.ON Service GmbH Sitz/Head Office: Essen\nRegistergericht/Registry Court: Essen\nHandelsregisternummer/Commercial Register No.: HRB 16297"
        let rightText = String(format: copy.pageNumberFormat, Int64(pageNumber), Int64(pageCount))

        drawText(
            leftText,
            in: CGRect(x: Layout.leftMargin, y: y + 3, width: contentWidth * 0.39, height: 32),
            font: UIFont.systemFont(ofSize: 6.4)
        )
        drawText(
            centerText,
            in: CGRect(x: Layout.leftMargin + contentWidth * 0.40, y: y + 3, width: contentWidth * 0.39, height: 32),
            font: UIFont.systemFont(ofSize: 6.4)
        )
        drawText(
            rightText,
            in: CGRect(x: Layout.pageSize.width - Layout.rightMargin - 100, y: y + 5, width: 95, height: 16),
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

    private func fixedDateTimeWithSeconds(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "de_DE")
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.dateFormat = "dd.MM.yyyy HH:mm:ss"
        return formatter.string(from: date)
    }

    private func fixedDateOnly(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "de_DE")
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.dateFormat = "dd.MM.yyyy"
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

private struct BriefingPDFCopy {
    let title = "Einweisung von Partnerfirmen\n(Standort- und Projektmanagement: CHG, ESE, Westnetz)"
    let declarations = [
        "Mit dieser Einweisung werden z. B. die standort- und betriebsspezifischen Gegebenheiten/Regelungen und Hinweise zu konkreten Arbeitsbedingungen, die zum Zeitpunkt der Auftragsdurchführung bestehen, „Betriebsfremden“ vermittelt.",
        "Der Eingewiesene hat die Pflicht, die zum Einsatz kommenden Mitarbeiter/innen der Partnerfirma, oder ggf. eingesetzter Subunternehmer, über die Inhalte der Einweisung vor Beginn der Arbeiten zu unterweisen.",
        "Gemäß der allgemeinen Einkaufs- und Zahlungsbedingungen hat sich die Partnerfirma verpflichtet, während der durchzuführenden Arbeiten die maßgeblichen Vorschriften und Regeln zum Arbeits- und Gesundheitsschutz einzuhalten."
    ]
    let dateTime = "Datum, Uhrzeit"
    let signatureInstructor = "Einweiser/Abnehmer"
    let signatureInstructedPerson = "Eingewiesener"
    let signature = "Unterschrift"
    let copyDelivered = "Kopie an Eingewiesenen übergeben."
    let number = "Nr"
    let tasks = "Aufgaben"
    let completed = "Durchgeführt"
    let comment = "Bermerkung"
    let yes = "Ja"
    let no = "Nein"
    let pageNumberFormat = "Seite %lld von %lld"
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
