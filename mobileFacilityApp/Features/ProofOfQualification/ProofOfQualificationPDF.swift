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
  let partnerEmail: String
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
    static let page = CGRect(x: 0, y: 0, width: 595.28, height: 841.89)
    static let margin: CGFloat = 28
    static let contentWidth = page.width - margin * 2
    static let bottom: CGFloat = 796
    static let border = UIColor.black.withAlphaComponent(0.72)
    static let sectionFill = UIColor(white: 0.93, alpha: 1)
    static let headerFill = UIColor(white: 0.96, alpha: 1)
  }

  func render(_ payload: ProofOfQualificationPDFPayload) throws -> BriefingPDFArtifact {
    let renderer = UIGraphicsPDFRenderer(bounds: Layout.page)
    var pageNumber = 0
    let data = renderer.pdfData { context in
      pageNumber += 1
      context.beginPage()
      drawCover(payload, context: context.cgContext, pageNumber: pageNumber)

      pageNumber += 1
      context.beginPage()
      var y = drawChecklistHeader(
        context: context.cgContext, pageNumber: pageNumber, payload: payload)

      for (sectionIndex, section) in payload.sections.enumerated() {
        let sectionTitle = "\(sectionIndex + 1). \(section.title)"
        let sectionHeight = max(
          30,
          textHeight(
            sectionTitle, width: Layout.contentWidth - 16, font: .boldSystemFont(ofSize: 10)) + 14)
        if y + sectionHeight > Layout.bottom {
          pageNumber += 1
          context.beginPage()
          y = drawChecklistHeader(
            context: context.cgContext, pageNumber: pageNumber, payload: payload)
        }
        drawSection(sectionTitle, y: y, height: sectionHeight, context: context.cgContext)
        y += sectionHeight

        for (itemIndex, item) in section.items.enumerated() {
          let positionNumber = section.items
            .prefix(itemIndex + 1)
            .filter { $0.rowType != .subposition }
            .count
          let number =
            item.rowType == .subposition
            ? ""
            : "\(sectionIndex + 1).\(String(format: "%02d", positionNumber))"
          let answer = answerTitle(for: item, selectedKey: payload.answerKeysByItemID[item.id])
          let comment = payload.commentsByItemID[item.id] ?? ""
          let rowHeight = max(
            42,
            textHeight(item.title, width: 277, font: .systemFont(ofSize: 9)) + 14,
            textHeight(comment, width: 95, font: .systemFont(ofSize: 9)) + 14
          )
          if y + rowHeight > Layout.bottom {
            pageNumber += 1
            context.beginPage()
            y = drawChecklistHeader(
              context: context.cgContext, pageNumber: pageNumber, payload: payload)
          }
          drawChecklistRow(
            number: number,
            task: item.title,
            answer: answer,
            comment: comment,
            y: y,
            height: rowHeight,
            context: context.cgContext
          )
          y += rowHeight
        }
      }
    }

    guard !data.isEmpty else { throw ProofOfQualificationPDFError.emptyDocument }
    return BriefingPDFArtifact(
      data: data,
      fileName: "Qualifikationsnachweis.pdf",
      createdAt: payload.completedAt
    )
  }

  private func drawCover(
    _ payload: ProofOfQualificationPDFPayload,
    context: CGContext,
    pageNumber: Int
  ) {
    var y: CGFloat = Layout.margin
    drawText(
      "Kontrolle Qualifikationsnachweis Partnerfirma",
      in: CGRect(x: Layout.margin, y: y, width: Layout.contentWidth, height: 42),
      font: .boldSystemFont(ofSize: 17),
      alignment: .center
    )
    y += 48

    drawInfoRow(
      label: "Einweiser/Abnehmer\n(E.ON Mitarbeiter)",
      value: payload.instructorName,
      secondaryLabel: "E.ON-Organisationseinheit",
      secondaryValue: payload.organizationUnit,
      y: y,
      height: 58,
      context: context
    )
    y += 58
    drawWideRow(
      label: "Benannter Koordinator ggf. SiGeKo gemäß BauStellV",
      value: payload.coordinator,
      y: y,
      height: 48,
      context: context
    )
    y += 48
    drawWideRow(
      label: "Partnerfirma/Auftragnehmer\n(Name und Anschrift)",
      value: [payload.partner.name, payload.partner.address, payload.partnerEmail]
        .filter { !$0.isEmpty }
        .joined(separator: "\n"),
      y: y,
      height: 76,
      context: context
    )
    y += 76
    drawWideRow(
      label: "Eingewiesener\n(Verantwortlicher der Partnerfirma)",
      value: payload.contactPerson,
      y: y,
      height: 58,
      context: context
    )
    y += 58
    drawWideRow(
      label: "Leistungs-/Arbeitsort",
      value: payload.workLocation,
      y: y,
      height: 58,
      context: context
    )
    y += 58
    drawWideRow(
      label: "Durchzuführende Arbeiten",
      value: payload.taskDescription,
      y: y,
      height: 72,
      context: context
    )
    y += 72
    drawWideRow(
      label: "Ausführung von ... bis ...\n(Datum)",
      value: "\(fixedDate(payload.executionStart)) - \(fixedDate(payload.executionEnd))",
      y: y,
      height: 50,
      context: context
    )
    y += 66

    let signatureWidth = (Layout.contentWidth - 8) / 2
    drawSignatureBox(
      title: "Koordinator*in",
      signature: payload.coordinatorSignature,
      rect: CGRect(x: Layout.margin, y: y, width: signatureWidth, height: 128),
      context: context
    )
    drawSignatureBox(
      title: "Eingewiesene*r",
      signature: payload.instructedPersonSignature,
      rect: CGRect(x: Layout.margin + signatureWidth + 8, y: y, width: signatureWidth, height: 128),
      context: context
    )
    y += 140
    drawText(
      "[ X ] Kopie an Eingewiesenen übergeben.",
      in: CGRect(x: Layout.margin, y: y, width: Layout.contentWidth, height: 20),
      font: .systemFont(ofSize: 9)
    )
    drawFooter(
      context: context,
      pageNumber: pageNumber,
      planNumber: payload.planNumber,
      documentID: payload.legacyDocumentID
    )
  }

  @discardableResult
  private func drawChecklistHeader(
    context: CGContext,
    pageNumber: Int,
    payload: ProofOfQualificationPDFPayload
  ) -> CGFloat {
    drawText(
      "Kontrolle Qualifikationsnachweis Partnerfirma",
      in: CGRect(x: Layout.margin, y: Layout.margin, width: Layout.contentWidth, height: 26),
      font: .boldSystemFont(ofSize: 13),
      alignment: .center
    )
    let y: CGFloat = 62
    let widths: [CGFloat] = [42, 290, 105, Layout.contentWidth - 437]
    let titles = ["Nr.", "Aufgaben", "Durchgeführt", "Bemerkung"]
    var x = Layout.margin
    for (index, title) in titles.enumerated() {
      let rect = CGRect(x: x, y: y, width: widths[index], height: 34)
      fillAndStroke(rect, fill: Layout.headerFill, context: context)
      drawText(
        title, in: rect.insetBy(dx: 5, dy: 5), font: .boldSystemFont(ofSize: 9),
        alignment: index == 2 ? .center : .left)
      x += widths[index]
    }
    drawFooter(
      context: context,
      pageNumber: pageNumber,
      planNumber: payload.planNumber,
      documentID: payload.legacyDocumentID
    )
    return y + 34
  }

  private func drawSection(_ title: String, y: CGFloat, height: CGFloat, context: CGContext) {
    let rect = CGRect(x: Layout.margin, y: y, width: Layout.contentWidth, height: height)
    fillAndStroke(rect, fill: Layout.sectionFill, context: context)
    drawText(title, in: rect.insetBy(dx: 8, dy: 6), font: .boldSystemFont(ofSize: 10))
  }

  private func drawChecklistRow(
    number: String,
    task: String,
    answer: String,
    comment: String,
    y: CGFloat,
    height: CGFloat,
    context: CGContext
  ) {
    let widths: [CGFloat] = [42, 290, 105, Layout.contentWidth - 437]
    let values = [number, task, answer, comment]
    var x = Layout.margin
    for (index, value) in values.enumerated() {
      let rect = CGRect(x: x, y: y, width: widths[index], height: height)
      fillAndStroke(rect, fill: .white, context: context)
      drawText(
        value,
        in: rect.insetBy(dx: 5, dy: 6),
        font: .systemFont(ofSize: 9),
        alignment: index == 0 || index == 2 ? .center : .left
      )
      x += widths[index]
    }
  }

  private func drawInfoRow(
    label: String,
    value: String,
    secondaryLabel: String,
    secondaryValue: String,
    y: CGFloat,
    height: CGFloat,
    context: CGContext
  ) {
    let widths: [CGFloat] = [130, 165, 120, Layout.contentWidth - 415]
    let values = [label, value, secondaryLabel, secondaryValue]
    var x = Layout.margin
    for (index, text) in values.enumerated() {
      let rect = CGRect(x: x, y: y, width: widths[index], height: height)
      fillAndStroke(
        rect, fill: index.isMultiple(of: 2) ? Layout.headerFill : .white, context: context)
      drawText(
        text, in: rect.insetBy(dx: 6, dy: 6),
        font: index.isMultiple(of: 2) ? .boldSystemFont(ofSize: 8) : .systemFont(ofSize: 9))
      x += widths[index]
    }
  }

  private func drawWideRow(
    label: String,
    value: String,
    y: CGFloat,
    height: CGFloat,
    context: CGContext
  ) {
    let labelRect = CGRect(x: Layout.margin, y: y, width: 220, height: height)
    let valueRect = CGRect(
      x: labelRect.maxX, y: y, width: Layout.contentWidth - labelRect.width, height: height)
    fillAndStroke(labelRect, fill: Layout.headerFill, context: context)
    fillAndStroke(valueRect, fill: .white, context: context)
    drawText(label, in: labelRect.insetBy(dx: 7, dy: 6), font: .boldSystemFont(ofSize: 9))
    drawText(value, in: valueRect.insetBy(dx: 7, dy: 6), font: .systemFont(ofSize: 9))
  }

  private func drawSignatureBox(
    title: String,
    signature: Data,
    rect: CGRect,
    context: CGContext
  ) {
    fillAndStroke(rect, fill: .white, context: context)
    let titleRect = CGRect(x: rect.minX, y: rect.minY, width: rect.width, height: 26)
    fillAndStroke(titleRect, fill: Layout.headerFill, context: context)
    drawText(
      title, in: titleRect.insetBy(dx: 5, dy: 5), font: .boldSystemFont(ofSize: 9),
      alignment: .center)
    let imageRect = CGRect(
      x: rect.minX + 12, y: titleRect.maxY + 4, width: rect.width - 24, height: 72)
    if let image = UIImage(data: signature), image.size.width > 0, image.size.height > 0 {
      let scale = min(imageRect.width / image.size.width, imageRect.height / image.size.height)
      let size = CGSize(width: image.size.width * scale, height: image.size.height * scale)
      image.draw(
        in: CGRect(
          x: imageRect.midX - size.width / 2, y: imageRect.midY - size.height / 2,
          width: size.width, height: size.height))
    }
    drawText(
      "Unterschrift", in: CGRect(x: rect.minX, y: rect.maxY - 22, width: rect.width, height: 18),
      font: .systemFont(ofSize: 8), alignment: .center)
  }

  private func drawFooter(
    context: CGContext,
    pageNumber: Int,
    planNumber: String,
    documentID: String
  ) {
    context.setStrokeColor(UIColor.black.withAlphaComponent(0.25).cgColor)
    context.setLineWidth(0.5)
    context.move(to: CGPoint(x: Layout.margin, y: 812))
    context.addLine(to: CGPoint(x: Layout.page.width - Layout.margin, y: 812))
    context.strokePath()
    drawText(
      "\(documentID) · \(planNumber)",
      in: CGRect(x: Layout.margin, y: 817, width: Layout.contentWidth / 2, height: 14),
      font: .systemFont(ofSize: 7),
      color: .darkGray
    )
    drawText(
      "Seite \(pageNumber)",
      in: CGRect(x: Layout.page.midX, y: 817, width: Layout.contentWidth / 2, height: 14),
      font: .systemFont(ofSize: 7),
      color: .darkGray,
      alignment: .right
    )
  }

  private func answerTitle(for item: SAPBriefingTemplateItem, selectedKey: String?) -> String {
    guard let selectedKey else { return "-" }
    return item.answerOptions.first(where: { $0.key == selectedKey })?.title ?? selectedKey
  }

  private func fixedDate(_ date: Date) -> String {
    let formatter = DateFormatter()
    formatter.locale = Locale(identifier: "en_US_POSIX")
    formatter.calendar = Calendar(identifier: .gregorian)
    formatter.dateFormat = "dd.MM.yyyy"
    return formatter.string(from: date)
  }

  private func fillAndStroke(_ rect: CGRect, fill: UIColor, context: CGContext) {
    context.setFillColor(fill.cgColor)
    context.fill(rect)
    context.setStrokeColor(Layout.border.cgColor)
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
      in: rect,
      withAttributes: [
        .font: font,
        .foregroundColor: color,
        .paragraphStyle: paragraph,
      ]
    )
  }

  private func textHeight(_ value: String, width: CGFloat, font: UIFont) -> CGFloat {
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
}
