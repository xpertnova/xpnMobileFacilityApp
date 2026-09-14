import Foundation
import UIKit

/// Compact, self-contained report used for the persisted `TFM7-pdf` document.
/// It intentionally depends only on the locally saved draft, so closing works
/// in airplane mode and the exact report survives retries unchanged.
enum SubdistributionPDFReport {
    static func make(draft: SubdistributionDraftPayload) -> Data {
        let page = CGRect(x: 0, y: 0, width: 595, height: 842) // A4 at 72 dpi
        let renderer = UIGraphicsPDFRenderer(bounds: page)
        return renderer.pdfData { context in
            context.beginPage()
            let margin: CGFloat = 42
            var y: CGFloat = margin
            let width = page.width - margin * 2
            func line(_ text: String, font: UIFont, color: UIColor = .black, spacing: CGFloat = 8) {
                let attributes: [NSAttributedString.Key: Any] = [.font: font, .foregroundColor: color]
                let size = (text as NSString).boundingRect(
                    with: CGSize(width: width, height: .greatestFiniteMagnitude),
                    options: [.usesLineFragmentOrigin, .usesFontLeading], attributes: attributes, context: nil
                ).integral
                if y + size.height > page.height - margin {
                    context.beginPage(); y = margin
                }
                (text as NSString).draw(in: CGRect(x: margin, y: y, width: width, height: size.height), withAttributes: attributes)
                y += size.height + spacing
            }
            func rule() {
                UIColor.systemGray3.setStroke()
                let path = UIBezierPath()
                path.move(to: CGPoint(x: margin, y: y))
                path.addLine(to: CGPoint(x: page.width - margin, y: y))
                path.lineWidth = 0.5
                path.stroke(); y += 14
            }

            line("TFM7 - Unterverteilung", font: .systemFont(ofSize: 22, weight: .bold), spacing: 4)
            let date = draft.performedOn.formatted(date: .long, time: .omitted)
            line("Performed on: \(date)", font: .systemFont(ofSize: 11), color: .darkGray, spacing: 16)
            if let contextValue = draft.context {
                line("Technical place: \(contextValue.legacyContext.functionalLocation)", font: .systemFont(ofSize: 12, weight: .semibold))
                let address = [contextValue.legacyContext.street, [contextValue.legacyContext.postalCode, contextValue.legacyContext.city].filter { !$0.isEmpty }.joined(separator: " ")].filter { !$0.isEmpty }.joined(separator: ", ")
                if !address.isEmpty { line("Address: \(address)", font: .systemFont(ofSize: 11), color: .darkGray) }
            }
            let status = draft.isOutOfOperation ? "Out of operation (aBet / INAK)" : (draft.hasDefect ? "Defect" : "In operation (iBet)")
            line("Status: \(status)", font: .systemFont(ofSize: 12, weight: .semibold), spacing: 16)
            if draft.isOutOfOperation, let comment = draft.outOfOperationComment, !comment.isEmpty {
                line("Comment: \(comment)", font: .systemFont(ofSize: 11), color: .darkGray, spacing: 16)
            }
            rule()
            line("Master data", font: .systemFont(ofSize: 15, weight: .bold))
            for characteristic in draft.context?.legacyContext.template.characteristics ?? [] {
                let value = draft.characteristicValues[characteristic.name, default: ""]
                line("\(characteristic.title.isEmpty ? characteristic.name : characteristic.title): \(value) \(characteristic.unit)", font: .systemFont(ofSize: 11))
            }
            rule()
            line("Inspection", font: .systemFont(ofSize: 15, weight: .bold))
            for item in draft.inspectionItems {
                let result = item.result ?? "-"
                let action = item.action ?? "-"
                line("\(item.number). \(item.title)\nResult: \(result)    Action: \(action)\(item.comment.isEmpty ? "" : "\nComment: \(item.comment)")", font: .systemFont(ofSize: 11), spacing: 12)
            }
        }
    }
}

private extension SubdistributionDraftPayload {
    var hasDefect: Bool {
        !isOutOfOperation && inspectionItems.contains(where: \.isDefective)
    }
}
