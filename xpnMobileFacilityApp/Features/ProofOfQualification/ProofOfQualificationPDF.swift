import Foundation
import UIKit

struct ProofOfQualificationPDFPayload: Sendable {
  let planNumber: String
  let legacyDocumentID: String
  let instructorName: String
  let organizationUnit: String
  let contactPerson: String
  let coordinator: String
  let partner: SAPBriefingPartner
  let workLocation: String
  let taskDescription: String
  let executionStart: Date
  let executionEnd: Date
  let sections: [SAPBriefingTemplateSection]
  let answerKeysByItemID: [String: String]
  let commentsByItemID: [String: String]
  let coordinatorSignature: Data
  let instructedPersonSignature: Data
  let completedAt: Date
}

enum ProofOfQualificationPDFError: Error {
  case emptyDocument
}

/// Fixed German document copy mirrors the established TFMQ_001 document.
/// All variable checklist, worker, partner, and form values are preserved from
/// SAP or the completed form and are never passed through app localization.
struct ProofOfQualificationPDFRenderer: Sendable {
  private enum Layout {
    static let pageSize = CGSize(width: 595.28, height: 841.89)
    static let page = CGRect(origin: .zero, size: pageSize)
    static let leftMargin: CGFloat = 25
    static let topMargin: CGFloat = 25
    static let rightMargin: CGFloat = 25
    static let bottomMargin: CGFloat = 52
    static let headerFont = UIFont.boldSystemFont(ofSize: 18)
    static let tableHeaderFont = UIFont.boldSystemFont(ofSize: 10.5)
    static let bodyFont = UIFont.systemFont(ofSize: 9)
    static let bodyBoldFont = UIFont.boldSystemFont(ofSize: 9)
    static let footerFont = UIFont.italicSystemFont(ofSize: 9)
    static let tableHeaderHeight: CGFloat = 24
    static let answerLineHeight: CGFloat = 16
    static let borderColor = UIColor.black.withAlphaComponent(0.75)
    static let sectionFill = UIColor(white: 0.93, alpha: 1)
  }

  private var contentWidth: CGFloat {
    Layout.pageSize.width - Layout.leftMargin - Layout.rightMargin
  }

  private var contentBottom: CGFloat {
    Layout.pageSize.height - Layout.bottomMargin
  }

  private var checklistColumnWidths: [CGFloat] {
    [contentWidth * 0.08, contentWidth * 0.48, contentWidth * 0.20, contentWidth * 0.24]
  }

  func render(_ payload: ProofOfQualificationPDFPayload) throws -> BriefingPDFArtifact {
    let totalPageCount = 1 + checklistPageCount(for: payload)
    let renderer = UIGraphicsPDFRenderer(bounds: Layout.page)
    let data = renderer.pdfData { context in
      context.beginPage()
      drawFirstPage(
        context: context.cgContext,
        payload: payload,
        pageNumber: 1,
        pageCount: totalPageCount
      )

      drawChecklistPages(
        context: context,
        payload: payload,
        firstPageNumber: 2,
        pageCount: totalPageCount
      )
    }

    guard !data.isEmpty else { throw ProofOfQualificationPDFError.emptyDocument }
    return BriefingPDFArtifact(
      data: data,
      fileName: "Qualifikationsnachweis.pdf",
      createdAt: payload.completedAt
    )
  }

  // MARK: - Page 1

  private func drawFirstPage(
    context: CGContext,
    payload: ProofOfQualificationPDFPayload,
    pageNumber: Int,
    pageCount: Int
  ) {
    var y = Layout.topMargin

    // Title Block
    let title = "Kontrolle Qualifikationsnachweis Partnerfirma"
    let titleHeight: CGFloat = 36
    let titleRect = CGRect(x: Layout.leftMargin, y: y, width: contentWidth, height: titleHeight)
    drawCell(titleRect, fill: .white, context: context)
    drawText(title, in: titleRect.insetBy(dx: 8, dy: 7), font: Layout.headerFont, alignment: .center)
    y = titleRect.maxY

    // Row 1: Einweiser/Abnehmer(E.ON Mitarbeiter) | Name | Orgunit
    let r1Col1Width = contentWidth * 0.25
    let r1Col2Width = contentWidth * 0.50
    let r1Col3Width = contentWidth * 0.25
    let r1Label = "Einweiser/Abnehmer(E.ON\nMitarbeiter)"
    let orgText = payload.organizationUnit.isEmpty ? "e.on" : payload.organizationUnit
    let r1Org = "\(orgText)\n(E.ON-Organisationseinheit)"
    let r1Height = max(
      36,
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

    let partner = [payload.partner.name, payload.partner.address]
      .filter { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
      .joined(separator: "\n")
    let dateRange = "\(fixedDateOnly(payload.executionStart)) - \(fixedDateOnly(payload.executionEnd))"

    let gridRows: [(String, String)] = [
      ("Benannter Koordinator ggf. SiGeKo gemäß BauStellV:\n(Wird bei gegenseitiger Gefährdung durch den Einweiser/Abnehmer\nbenannt)", payload.coordinator),
      ("Partnerfirma/Auftragnehmer:\n(Name und Anschrift)", partner),
      ("Eingewiesener:\n(Verantwortlicher der Partnerfirma für die durchzuführenden Arbeiten)", payload.contactPerson),
      ("Leistungs-/Arbeitsort:", payload.workLocation),
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

    // Signature Block (spaced ~8pt below row 7)
    drawSignatureTable(at: y + 8, context: context, payload: payload)

    // Footer
    drawFooter(context: context, pageNumber: pageNumber, pageCount: pageCount)
  }

  private func drawSignatureTable(
    at originY: CGFloat,
    context: CGContext,
    payload: ProofOfQualificationPDFPayload
  ) {
    let columnWidth = contentWidth / 2
    let timestamp = fixedDateTimeWithSeconds(payload.completedAt)

    let leftDate = CGRect(x: Layout.leftMargin, y: originY, width: columnWidth, height: 26)
    let rightDate = CGRect(x: leftDate.maxX, y: originY, width: columnWidth, height: 26)
    drawCell(leftDate, context: context)
    drawCell(rightDate, context: context)
    drawText("Datum, Uhrzeit:", in: leftDate.insetBy(dx: 5, dy: 5), font: Layout.bodyFont, alignment: .left)
    drawText(timestamp, in: leftDate.insetBy(dx: 5, dy: 5), font: Layout.bodyFont, alignment: .right)
    drawText("Datum, Uhrzeit:", in: rightDate.insetBy(dx: 5, dy: 5), font: Layout.bodyFont, alignment: .left)
    drawText(timestamp, in: rightDate.insetBy(dx: 5, dy: 5), font: Layout.bodyFont, alignment: .right)

    let boxHeight: CGFloat = 110
    let leftBox = CGRect(x: Layout.leftMargin, y: leftDate.maxY, width: columnWidth, height: boxHeight)
    let rightBox = CGRect(x: leftBox.maxX, y: rightDate.maxY, width: columnWidth, height: boxHeight)
    drawCell(leftBox, context: context)
    drawCell(rightBox, context: context)

    drawText("Einweiser/Abnehmer", in: CGRect(x: leftBox.minX, y: leftBox.minY + 4, width: columnWidth, height: 16), font: Layout.bodyFont, alignment: .center)
    drawText("Eingewiesener", in: CGRect(x: rightBox.minX, y: rightBox.minY + 4, width: columnWidth, height: 16), font: Layout.bodyFont, alignment: .center)

    drawSignature(payload.coordinatorSignature, in: CGRect(x: leftBox.minX + 15, y: leftBox.minY + 22, width: columnWidth - 30, height: 64))
    drawSignature(payload.instructedPersonSignature, in: CGRect(x: rightBox.minX + 15, y: rightBox.minY + 22, width: columnWidth - 30, height: 64))

    drawText("Unterschrift", in: CGRect(x: leftBox.minX, y: leftBox.maxY - 18, width: columnWidth, height: 14), font: Layout.bodyFont, alignment: .center)
    drawText("Unterschrift", in: CGRect(x: rightBox.minX, y: rightBox.maxY - 18, width: columnWidth, height: 14), font: Layout.bodyFont, alignment: .center)

    drawText(
      "[ X ]Kopie an Eingewiesenen übergeben.",
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

  // MARK: - Page 2+ (Checklist)

  private func drawChecklistPages(
    context: UIGraphicsPDFRendererContext,
    payload: ProofOfQualificationPDFPayload,
    firstPageNumber: Int,
    pageCount: Int
  ) {
    var pageNumber = firstPageNumber
    context.beginPage()
    var graphicsContext = context.cgContext
    var y = drawChecklistHeader(at: Layout.topMargin, context: graphicsContext)

    for (sectionIndex, section) in payload.sections.enumerated() {
      let headerH = sectionHeaderHeight(section)
      let firstItemH = section.items.first.map { checklistItemHeight($0, comment: payload.commentsByItemID[$0.id] ?? "") } ?? 0
      if y + headerH + firstItemH > contentBottom {
        drawFooter(context: graphicsContext, pageNumber: pageNumber, pageCount: pageCount)
        pageNumber += 1
        context.beginPage()
        graphicsContext = context.cgContext
        y = drawChecklistHeader(at: Layout.topMargin, context: graphicsContext)
      }

      y = drawSection(section, at: y, context: graphicsContext)

      for (itemIndex, item) in section.items.enumerated() {
        let positionNumber = section.items
          .prefix(itemIndex + 1)
          .filter { $0.rowType != .subposition }
          .count
        let number = item.rowType == .subposition
          ? ""
          : "\(sectionIndex + 1).\(String(format: "%02d", positionNumber))"
        let comment = payload.commentsByItemID[item.id] ?? ""
        let height = checklistItemHeight(item, comment: comment)
        if y + height > contentBottom {
          drawFooter(context: graphicsContext, pageNumber: pageNumber, pageCount: pageCount)
          pageNumber += 1
          context.beginPage()
          graphicsContext = context.cgContext
          y = drawChecklistHeader(at: Layout.topMargin, context: graphicsContext)
        }
        drawChecklistItem(
          item,
          number: number,
          selectedKey: payload.answerKeysByItemID[item.id],
          comment: comment,
          at: y,
          height: height,
          context: graphicsContext
        )
        y += height
      }
    }
    drawFooter(context: graphicsContext, pageNumber: pageNumber, pageCount: pageCount)
  }

  private func checklistPageCount(for payload: ProofOfQualificationPDFPayload) -> Int {
    var pages = 1
    var y = Layout.topMargin + Layout.tableHeaderHeight
    for section in payload.sections {
      let headerH = sectionHeaderHeight(section)
      let firstItemH = section.items.first.map { checklistItemHeight($0, comment: payload.commentsByItemID[$0.id] ?? "") } ?? 0
      if y + headerH + firstItemH > contentBottom {
        pages += 1
        y = Layout.topMargin + Layout.tableHeaderHeight
      }
      y += headerH
      for item in section.items {
        let height = checklistItemHeight(item, comment: payload.commentsByItemID[item.id] ?? "")
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
    context: CGContext
  ) -> CGFloat {
    let titles = ["Nr", "Aufgaben", "Durchgeführt", "Bermerkung"]
    var x = Layout.leftMargin
    for (index, width) in checklistColumnWidths.enumerated() {
      let rect = CGRect(x: x, y: y, width: width, height: Layout.tableHeaderHeight)
      drawCell(rect, fill: .white, context: context)
      drawText(
        titles[index],
        in: rect.insetBy(dx: 4, dy: 4),
        font: Layout.tableHeaderFont,
        alignment: index == 2 ? .center : .left
      )
      x = rect.maxX
    }
    return y + Layout.tableHeaderHeight
  }

  private func sectionHeaderHeight(_ section: SAPBriefingTemplateSection) -> CGFloat {
    let separator = section.items.isEmpty ? "\n" : " "
    let fullText = [section.title, section.subtitle]
      .compactMap { $0 }
      .filter { !$0.isEmpty }
      .joined(separator: separator)
    let textH = textHeight(fullText, width: contentWidth - 12, font: Layout.bodyFont)
    return max(24, ceil(textH) + 10)
  }

  private func drawSection(
    _ section: SAPBriefingTemplateSection,
    at y: CGFloat,
    context: CGContext
  ) -> CGFloat {
    let height = sectionHeaderHeight(section)
    let rect = CGRect(x: Layout.leftMargin, y: y, width: contentWidth, height: height)
    drawCell(rect, fill: Layout.sectionFill, context: context)

    let separator = section.items.isEmpty ? "\n" : " "
    let paragraph = NSMutableParagraphStyle()
    paragraph.lineBreakMode = .byWordWrapping
    let attrString = NSMutableAttributedString()
    attrString.append(NSAttributedString(
      string: section.title,
      attributes: [.font: Layout.bodyBoldFont, .foregroundColor: UIColor.black, .paragraphStyle: paragraph]
    ))
    if let subtitle = section.subtitle, !subtitle.isEmpty {
      attrString.append(NSAttributedString(
        string: separator + subtitle,
        attributes: [.font: Layout.bodyFont, .foregroundColor: UIColor.black, .paragraphStyle: paragraph]
      ))
    }
    attrString.draw(with: rect.insetBy(dx: 6, dy: 5), options: [.usesLineFragmentOrigin, .usesFontLeading], context: nil)
    return rect.maxY
  }

  private func checklistItemHeight(_ item: SAPBriefingTemplateItem, comment: String) -> CGFloat {
    let titleH = textHeight(item.title, width: checklistColumnWidths[1] - 8, font: Layout.bodyFont)
    let commentH = textHeight(comment, width: checklistColumnWidths[3] - 8, font: Layout.bodyFont)
    let answerH = answerOptionsStacked(item.answerOptions)
      ? CGFloat(item.answerOptions.count) * Layout.answerLineHeight + 8
      : 0
    return max(28, ceil(max(titleH, commentH)) + 10, answerH)
  }

  /// Horizontal option layout used when every option fits in the answer column.
  private func answerOptionsRowWidth(_ options: [SAPBriefingAnswerOption]) -> CGFloat {
    var width: CGFloat = 12
    for opt in options {
      let titleWidth: CGFloat = ceil(textWidth(opt.title, font: Layout.bodyFont))
      width += 11 + 5 + titleWidth + 4 + 12
    }
    return width
  }

  private func answerOptionsStacked(_ options: [SAPBriefingAnswerOption]) -> Bool {
    options.count > 1 && answerOptionsRowWidth(options) > checklistColumnWidths[2]
  }

  private func drawChecklistItem(
    _ item: SAPBriefingTemplateItem,
    number: String,
    selectedKey: String?,
    comment: String,
    at y: CGFloat,
    height: CGFloat,
    context: CGContext
  ) {
    var x = Layout.leftMargin
    let rects = checklistColumnWidths.map { width -> CGRect in
      defer { x += width }
      return CGRect(x: x, y: y, width: width, height: height)
    }
    rects.forEach { drawCell($0, context: context) }

    if item.rowType != .subposition {
      drawText(number, in: rects[0].insetBy(dx: 4, dy: 5), font: Layout.bodyFont)
    }
    drawText(item.title, in: rects[1].insetBy(dx: 4, dy: 5), font: Layout.bodyFont)
    drawAnswer(item: item, selectedKey: selectedKey, in: rects[2], context: context)
    drawText(comment, in: rects[3].insetBy(dx: 4, dy: 5), font: Layout.bodyFont)
  }

  private func drawAnswer(
    item: SAPBriefingTemplateItem,
    selectedKey: String?,
    in rect: CGRect,
    context: CGContext
  ) {
    let boxSize: CGFloat = 11.0
    let boxY = rect.minY + 6.0

    if item.answerOptions.isEmpty {
      let isSelected = selectedKey == "J" || selectedKey?.lowercased() == "ja"
      let box = CGRect(x: rect.minX + 15.0, y: boxY, width: boxSize, height: boxSize)
      drawCheckboxBox(isSelected: isSelected, in: box, context: context)
      let labelRect = CGRect(x: box.maxX + 6.0, y: rect.minY + 5.0, width: 35, height: boxSize + 4)
      drawText("Ja", in: labelRect, font: Layout.bodyFont)
      return
    }

    if item.answerOptions.count == 1, let opt = item.answerOptions.first {
      let isSelected = selectedKey == opt.key || (selectedKey == "J" && opt.key == "J")
      let box = CGRect(x: rect.minX + 15.0, y: boxY, width: boxSize, height: boxSize)
      drawCheckboxBox(isSelected: isSelected, in: box, context: context)
      let labelRect = CGRect(x: box.maxX + 6.0, y: rect.minY + 5.0, width: 35, height: boxSize + 4)
      drawText(opt.title, in: labelRect, font: Layout.bodyFont)
      return
    }

    if answerOptionsStacked(item.answerOptions) {
      for (index, opt) in item.answerOptions.enumerated() {
        let lineY = rect.minY + CGFloat(index) * Layout.answerLineHeight
        let box = CGRect(x: rect.minX + 6.0, y: lineY + 6.0, width: boxSize, height: boxSize)
        drawCheckboxBox(isSelected: selectedKey == opt.key, in: box, context: context)
        let labelRect = CGRect(x: box.maxX + 5.0, y: lineY + 5.0, width: rect.maxX - box.maxX - 9.0, height: boxSize + 4)
        drawText(opt.title, in: labelRect, font: Layout.bodyFont)
      }
      return
    }

    var optX = rect.minX + 12.0
    for opt in item.answerOptions {
      let isSelected = selectedKey == opt.key
      let box = CGRect(x: optX, y: boxY, width: boxSize, height: boxSize)
      drawCheckboxBox(isSelected: isSelected, in: box, context: context)
      let labelWidth = ceil(textWidth(opt.title, font: Layout.bodyFont)) + 4
      let labelRect = CGRect(x: box.maxX + 5.0, y: rect.minY + 5.0, width: labelWidth, height: boxSize + 4)
      drawText(opt.title, in: labelRect, font: Layout.bodyFont)
      optX = labelRect.maxX + 12.0
    }
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
      context.move(to: CGPoint(x: box.minX + 2.5, y: box.minY + 5.5))
      context.addLine(to: CGPoint(x: box.minX + 4.8, y: box.minY + 8.5))
      context.addLine(to: CGPoint(x: box.maxX - 2.2, y: box.minY + 2.5))
      context.strokePath()
    }
    context.restoreGState()
  }

  // MARK: - Footer & Utility

  private func drawFooter(
    context: CGContext,
    pageNumber: Int,
    pageCount: Int
  ) {
    let y = Layout.pageSize.height - 44
    context.setStrokeColor(Layout.borderColor.cgColor)
    context.setLineWidth(0.6)
    context.move(to: CGPoint(x: Layout.leftMargin, y: y))
    context.addLine(to: CGPoint(x: Layout.pageSize.width - Layout.rightMargin, y: y))
    context.strokePath()

    let leftText = "Geschäftsführer/Managing Directors: André Schrödel,\nDr. Marc Stienemann, Peter Olschewski, Zsolt Szabo"
    let centerText = "E.ON Service GmbH Sitz/Head Office: Essen\nRegistergericht/Registry Court: Essen\nHandelsregisternummer/Commercial Register No.: HRB 16297"
    let rightText = "Seite \(pageNumber) von \(pageCount)"

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

  private func fixedDateOnly(_ date: Date) -> String {
    let formatter = DateFormatter()
    formatter.locale = Locale(identifier: "en_US_POSIX")
    formatter.calendar = Calendar(identifier: .gregorian)
    formatter.dateFormat = "dd.MM.yyyy"
    return formatter.string(from: date)
  }

  private func fixedDateTimeWithSeconds(_ date: Date) -> String {
    let formatter = DateFormatter()
    formatter.locale = Locale(identifier: "en_US_POSIX")
    formatter.calendar = Calendar(identifier: .gregorian)
    formatter.dateFormat = "dd.MM.yyyy HH:mm:ss"
    return formatter.string(from: date)
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

  private func drawText(
    _ value: String,
    in rect: CGRect,
    font: UIFont,
    color: UIColor = .black,
    alignment: NSTextAlignment = .left
  ) {
    let paragraph = NSMutableParagraphStyle()
    paragraph.alignment = alignment
    paragraph.lineBreakMode = .byWordWrapping
    (value as NSString).draw(
      with: rect,
      options: [.usesLineFragmentOrigin, .usesFontLeading],
      attributes: [
        .font: font,
        .foregroundColor: color,
        .paragraphStyle: paragraph,
      ],
      context: nil
    )
  }

  private func textHeight(_ value: String, width: CGFloat, font: UIFont) -> CGFloat {
    guard !value.isEmpty else { return font.lineHeight }
    let paragraph = NSMutableParagraphStyle()
    paragraph.lineBreakMode = .byWordWrapping
    return ceil(
      (value as NSString).boundingRect(
        with: CGSize(width: width, height: .greatestFiniteMagnitude),
        options: [.usesLineFragmentOrigin, .usesFontLeading],
        attributes: [.font: font, .paragraphStyle: paragraph],
        context: nil
      ).height
    )
  }

  private func textWidth(_ value: String, font: UIFont) -> CGFloat {
    (value as NSString).size(withAttributes: [.font: font]).width
  }
}
