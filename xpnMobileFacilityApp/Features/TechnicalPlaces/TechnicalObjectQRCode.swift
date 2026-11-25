import Foundation
import UIKit

/// The scannable identification of a technical object, and the label that
/// carries it.
///
/// The payload is the legacy MTFM QR contract (`LegacyQRCodeCodec`), so a code
/// generated here resolves through the app's own scanner and matches the codes
/// the legacy app printed. The label mirrors the fields the legacy printer was
/// given in `QrPrintList.controller.js` (`weNr` = functional location,
/// `tgaNr` = equipment).
enum TechnicalObjectQRCode {
    /// The control key stays empty: it names a form type in the legacy data,
    /// and a technical object does not carry one. `decode` maps an empty
    /// `STEUS` to "no control key", which makes the scan resolve every
    /// notification at the object instead of one form's.
    static func payload(for object: TechnicalObjectNode) -> String? {
        switch object.reference.kind {
        case .functionalLocation:
            guard !object.reference.objectID.isEmpty else { return nil }
            // `EQUNR: "%"` is the legacy marker for a location-only code; the
            // scan then matches notifications without equipment.
            return LegacyQRCodeCodec.encodeMTFM(functionalLocationID: object.reference.objectID)
        case .equipment:
            // Equipment is only resolvable together with its location, which
            // is what the notification rows are keyed on.
            guard !object.functionalLocationID.isEmpty, !object.reference.objectID.isEmpty else { return nil }
            return LegacyQRCodeCodec.encodeMTFM(
                functionalLocationID: object.functionalLocationID,
                equipmentID: object.reference.objectID
            )
        }
    }

    /// A single label page sized for a 62 × 40 mm roll, the format the legacy
    /// label printer used. Kept at 72 dpi so it prints unscaled and previews
    /// at its real size.
    static func labelPDF(for object: TechnicalObjectNode, payload: String) -> Data? {
        guard let code = QRCodeImageRenderer.image(for: payload) else { return nil }
        let page = CGRect(x: 0, y: 0, width: 176, height: 113)
        let margin: CGFloat = 8
        let codeSide = page.height - margin * 2

        return UIGraphicsPDFRenderer(bounds: page).pdfData { context in
            context.beginPage()
            code.draw(in: CGRect(x: margin, y: margin, width: codeSide, height: codeSide))

            let textX = margin + codeSide + 8
            let textWidth = page.width - textX - margin
            var y = margin
            func line(_ text: String, size: CGFloat, weight: UIFont.Weight, color: UIColor = .black) {
                guard !text.isEmpty, y < page.height - margin else { return }
                let font = UIFont.monospacedSystemFont(ofSize: size, weight: weight)
                let attributes: [NSAttributedString.Key: Any] = [.font: font, .foregroundColor: color]
                let height = (text as NSString).boundingRect(
                    with: CGSize(width: textWidth, height: page.height - y - margin),
                    options: [.usesLineFragmentOrigin, .usesFontLeading],
                    attributes: attributes,
                    context: nil
                ).integral.height
                (text as NSString).draw(
                    in: CGRect(x: textX, y: y, width: textWidth, height: height),
                    withAttributes: attributes
                )
                y += height + 2
            }

            line(object.displayName, size: 7, weight: .bold)
            line(object.functionalLocationID.isEmpty
                 ? object.reference.objectID
                 : object.functionalLocationID, size: 6, weight: .regular, color: .darkGray)
            if object.reference.kind == .equipment {
                line(object.reference.objectID, size: 6, weight: .regular, color: .darkGray)
            }
            if let din = object.dinGroup {
                line("KG \(din)", size: 6, weight: .regular, color: .darkGray)
            }
        }
    }

    /// File name for the shared label, built from the identifier so a
    /// technician can tell two saved labels apart.
    static func labelFileName(for object: TechnicalObjectNode) -> String {
        let identifier = object.reference.objectID
            .components(separatedBy: CharacterSet.alphanumerics.inverted)
            .filter { !$0.isEmpty }
            .joined(separator: "-")
        return "QR-\(identifier.isEmpty ? "Label" : identifier).pdf"
    }
}

/// One segment of a technical object's identifier, paired with the object in
/// the hierarchy that the segment's prefix belongs to.
///
/// The segments come from splitting the real identifier, and the names come
/// from the breadcrumb rows. Only an RE-FX place, whose scheme the customer
/// confirmed, also gets the level each segment stands for.
struct TechnicalObjectIdentifierSegment: Identifiable, Equatable {
    let position: Int
    let value: String
    /// The RE-FX level this segment names, for a place of that scheme.
    let level: TechnicalPlaceStructureLevel?
    /// The ancestor whose identifier equals this segment's cumulative prefix,
    /// when the hierarchy holds one.
    let objectName: String?

    var id: Int { position }

    static func segments(
        of identifier: String,
        breadcrumbs: [TechnicalObjectNode],
        isStructured: Bool = false
    ) -> [TechnicalObjectIdentifierSegment] {
        let separators = CharacterSet(charactersIn: "-/_.")
        let components = identifier
            .components(separatedBy: separators)
            .filter { !$0.isEmpty }
        // Nothing to show for an identifier that is a single block: the card
        // would just repeat the identifier above it.
        guard components.count > 1 else { return [] }

        // A placeholder level without a name of its own would only repeat
        // its identifier.
        let namesByIdentifier = Dictionary(
            breadcrumbs.filter { !$0.name.isEmpty }.map { ($0.reference.objectID, $0.displayName) },
            uniquingKeysWith: { first, _ in first }
        )
        // The separator is taken from the identifier so the rebuilt prefixes
        // compare equal to the ancestors' own identifiers.
        let separator = identifier.first { $0.unicodeScalars.allSatisfy(separators.contains) }
            .map(String.init) ?? "-"

        var prefix = ""
        return components.enumerated().map { index, component in
            prefix = prefix.isEmpty ? component : prefix + separator + component
            return TechnicalObjectIdentifierSegment(
                position: index + 1,
                value: component,
                level: isStructured ? TechnicalPlaceStructureLevel(rawValue: index + 1) : nil,
                objectName: namesByIdentifier[prefix].flatMap { $0 == component ? nil : $0 }
            )
        }
    }
}
