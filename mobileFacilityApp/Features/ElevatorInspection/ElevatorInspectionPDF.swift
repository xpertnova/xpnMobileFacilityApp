import Foundation
import UIKit
import PDFKit

struct ElevatorInspectionPDFPayload: Sendable, Equatable {
    let notificationID: String
    let notificationTitle: String
    let functionalLocation: String
    let equipmentID: String?
    let equipmentName: String?
    let locationCity: String
    let locationStreet: String
    let weGe: String
    let workerName: String
    let workerID: String
    let company: String
    let orgUnit: String
    let plant: String
    let performedAt: Date
    let items: [ElevatorInspectionItem]
    let results: [String: String]
    let actions: [String: String]
    let materials: [String: Bool]
    let notes: [String: String]
    let hasMaterialColumn: Bool
    let assetCharacteristics: [ElevatorAssetCharacteristic]
    let assetValues: [String: String]

    init(
        notificationID: String,
        notificationTitle: String,
        functionalLocation: String,
        equipmentID: String?,
        equipmentName: String?,
        locationCity: String,
        locationStreet: String,
        weGe: String,
        workerName: String,
        workerID: String,
        company: String,
        orgUnit: String,
        plant: String,
        performedAt: Date,
        items: [ElevatorInspectionItem],
        results: [String: String],
        actions: [String: String],
        materials: [String: Bool],
        notes: [String: String],
        hasMaterialColumn: Bool,
        assetCharacteristics: [ElevatorAssetCharacteristic] = [],
        assetValues: [String: String] = [:]
    ) {
        self.notificationID = notificationID
        self.notificationTitle = notificationTitle
        self.functionalLocation = functionalLocation
        self.equipmentID = equipmentID
        self.equipmentName = equipmentName
        self.locationCity = locationCity
        self.locationStreet = locationStreet
        self.weGe = weGe
        self.workerName = workerName
        self.workerID = workerID
        self.company = company
        self.orgUnit = orgUnit
        self.plant = plant
        self.performedAt = performedAt
        self.items = items
        self.results = results
        self.actions = actions
        self.materials = materials
        self.notes = notes
        self.hasMaterialColumn = hasMaterialColumn
        self.assetCharacteristics = assetCharacteristics
        self.assetValues = assetValues
    }
}

struct ElevatorInspectionPDFArtifact: Sendable, Equatable {
    let data: Data
    let fileName: String
}

enum ElevatorInspectionPDFError: LocalizedError {
    case emptyDocument

    var errorDescription: String? {
        switch self {
        case .emptyDocument:
            return "Das PDF-Dokument konnte nicht erstellt werden."
        }
    }
}

enum ElevatorInspectionPDFRenderer {
    private static let pageBounds = CGRect(x: 0, y: 0, width: 595.28, height: 841.89) // A4
    private static let margin: CGFloat = 28
    private static let contentWidth = pageBounds.width - margin * 2

    private static let fontTitle = UIFont.boldSystemFont(ofSize: 11)
    private static let fontHeader = UIFont.boldSystemFont(ofSize: 9)
    private static let fontSub = UIFont.systemFont(ofSize: 7)
    private static let fontBody = UIFont.systemFont(ofSize: 8)
    private static let fontBoldBody = UIFont.boldSystemFont(ofSize: 8)
    private static let fontSmall = UIFont.systemFont(ofSize: 7)

    static func render(_ payload: ElevatorInspectionPDFPayload) throws -> ElevatorInspectionPDFArtifact {
        let renderer = UIGraphicsPDFRenderer(bounds: pageBounds)
        let data = renderer.pdfData { context in
            var currentY: CGFloat = margin

            context.beginPage()
            guard let cg = UIGraphicsGetCurrentContext() else { return }

            // 1. Doc Header
            currentY = drawDocHeader(payload, in: cg, startY: currentY)
            currentY += 12

            // 2. Form Header
            currentY = drawFormHeader(payload, in: cg, startY: currentY)
            currentY += 14

            // 3. Elevator master data (the legacy addMasterDataToPdf output)
            if !payload.assetCharacteristics.isEmpty {
                currentY = drawElevatorAssetData(payload, in: cg, startY: currentY)
                currentY += 14
            }

            // 4. Report Table
            currentY = drawReportTable(payload, in: cg, context: context, startY: currentY)

            // 5. Erläuterungstabelle (Legend)
            if currentY + 70 > pageBounds.height - margin {
                context.beginPage()
                currentY = margin
            }
            currentY = drawErlaeuterungTable(payload, in: cg, startY: currentY)

            // 6. Bemerkungstabelle (if notes exist)
            let notesExist = payload.items.contains { item in
                let note = payload.notes[item.id]?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
                return !note.isEmpty
            }
            if notesExist {
                context.beginPage()
                currentY = margin
                _ = drawBemerkungTable(payload, in: cg, context: context, startY: currentY)
            }
        }

        guard !data.isEmpty else { throw ElevatorInspectionPDFError.emptyDocument }
        let cleanID = payload.notificationID.replacingOccurrences(
            of: "^0+", with: "", options: .regularExpression
        )
        return ElevatorInspectionPDFArtifact(
            data: data,
            fileName: "Bericht_\(cleanID).pdf"
        )
    }

    // MARK: - 1. Doc Header (addDocHeaderWN)
    private static func drawDocHeader(_ payload: ElevatorInspectionPDFPayload, in cg: CGContext, startY: CGFloat) -> CGFloat {
        let orgName: String
        switch payload.plant {
        case "1501": orgName = "HanseGas GmbH"
        case "1505": orgName = "HanseWerk AG"
        case "1556": orgName = "Schleswig-Holstein Netz"
        default:
            orgName = payload.company.isEmpty ? "XPN Facility Management" : payload.company
        }

        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "dd.MM.yyyy"
        let dateText = dateFormatter.string(from: payload.performedAt)

        let headerHeight: CGFloat = 50
        let col1Width = contentWidth * 0.22
        let col3Width = contentWidth * 0.25
        let col2Width = contentWidth - col1Width - col3Width

        let rect1 = CGRect(x: margin, y: startY, width: col1Width, height: headerHeight)
        let rect2 = CGRect(x: rect1.maxX, y: startY, width: col2Width, height: headerHeight)
        let rect3 = CGRect(x: rect2.maxX, y: startY, width: col3Width, height: headerHeight)

        for rect in [rect1, rect2, rect3] {
            strokeRect(rect, in: cg)
        }

        // Col 1: Organization
        drawText(orgName, in: rect1.insetBy(dx: 4, dy: 16), font: fontTitle, alignment: .center)

        // Col 2: Formular / Dokumentenart / Aufzugskontrolle
        let row2a = CGRect(x: rect2.minX, y: rect2.minY, width: rect2.width, height: 25)
        let row2b = CGRect(x: rect2.minX, y: row2a.maxY, width: rect2.width, height: 25)
        strokeLine(from: CGPoint(x: rect2.minX, y: row2a.maxY), to: CGPoint(x: rect2.maxX, y: row2a.maxY), in: cg)
        drawText("Formular", in: row2a.insetBy(dx: 4, dy: 2), font: fontHeader, alignment: .center)
        drawText("Dokumentenart", in: row2a.insetBy(dx: 4, dy: 14), font: fontSub, color: .gray, alignment: .center)
        drawText("Aufzugskontrolle", in: row2b.insetBy(dx: 4, dy: 6), font: fontTitle, alignment: .center)

        // Col 3: Datum / OrgUnit
        let row3a = CGRect(x: rect3.minX, y: rect3.minY, width: rect3.width, height: 25)
        let row3b = CGRect(x: rect3.minX, y: row3a.maxY, width: rect3.width, height: 25)
        strokeLine(from: CGPoint(x: rect3.minX, y: row3a.maxY), to: CGPoint(x: rect3.maxX, y: row3a.maxY), in: cg)
        drawText(dateText, in: row3a.insetBy(dx: 4, dy: 2), font: fontBody, alignment: .center)
        drawText("Datum", in: row3a.insetBy(dx: 4, dy: 14), font: fontSub, color: .gray, alignment: .center)
        let orgUnitText = payload.orgUnit.isEmpty ? "-" : payload.orgUnit
        drawText(orgUnitText, in: row3b.insetBy(dx: 4, dy: 2), font: fontBody, alignment: .center)
        drawText("Verantwortliche Organisation", in: row3b.insetBy(dx: 4, dy: 14), font: fontSub, color: .gray, alignment: .center)

        return startY + headerHeight
    }

    // MARK: - 2. Form Header (addFormHeaderWN)
    private static func drawFormHeader(_ payload: ElevatorInspectionPDFPayload, in cg: CGContext, startY: CGFloat) -> CGFloat {
        let cleanQMNUM = payload.notificationID.replacingOccurrences(
            of: "^0+", with: "", options: .regularExpression
        )

        let equipText: String
        if let eqID = payload.equipmentID, !eqID.isEmpty {
            let cleanEQ = eqID.replacingOccurrences(of: "^0+", with: "", options: .regularExpression)
            let eqName = payload.equipmentName ?? ""
            equipText = " / \(cleanEQ) (\(eqName))"
        } else {
            equipText = ""
        }

        let streetCity: String
        if payload.locationCity.isEmpty && payload.locationStreet.isEmpty {
            streetCity = "-"
        } else if payload.locationCity.isEmpty {
            streetCity = payload.locationStreet
        } else if payload.locationStreet.isEmpty {
            streetCity = payload.locationCity
        } else {
            streetCity = "\(payload.locationCity), \(payload.locationStreet)"
        }

        let calendar = Calendar(identifier: .gregorian)
        let kwNumber = calendar.component(.weekOfYear, from: payload.performedAt)
        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "dd.MM.yyyy"
        let dateString = dateFormatter.string(from: payload.performedAt)

        let rows: [(label: String, value: String)] = [
            ("Meldung / Bezeichnung", "\(cleanQMNUM) / \(payload.notificationTitle)"),
            ("Technischer Platz / Equipment", "\(payload.functionalLocation)\(equipText)"),
            ("Standort", streetCity),
            ("WE / GE", payload.weGe.isEmpty ? "-" : payload.weGe),
            ("Name", "\(payload.workerName) (\(payload.workerID))"),
            ("Kalenderwoche", "KW \(kwNumber)"),
            ("Datum / Unterschrift", dateString)
        ]

        var currentY = startY
        let labelWidth = contentWidth * 0.35
        let valueWidth = contentWidth - labelWidth
        let rowHeight: CGFloat = 16

        for row in rows {
            let labelRect = CGRect(x: margin, y: currentY, width: labelWidth, height: rowHeight)
            let valueRect = CGRect(x: labelRect.maxX, y: currentY, width: valueWidth, height: rowHeight)

            strokeRect(labelRect, in: cg)
            strokeRect(valueRect, in: cg)

            drawText(row.label, in: labelRect.insetBy(dx: 4, dy: 3), font: fontBoldBody)
            drawText(row.value, in: valueRect.insetBy(dx: 4, dy: 3), font: fontBody)

            currentY += rowHeight
        }

        return currentY
    }

    // MARK: - 3. Elevator master data (addMasterDataToPdf)
    private static func drawElevatorAssetData(
        _ payload: ElevatorInspectionPDFPayload,
        in cg: CGContext,
        startY: CGFloat
    ) -> CGFloat {
        var currentY = startY
        let titleHeight: CGFloat = 18
        let titleRect = CGRect(x: margin, y: currentY, width: contentWidth, height: titleHeight)
        strokeRect(titleRect, in: cg)
        drawText("Aufzug Merkmale", in: titleRect.insetBy(dx: 4, dy: 3), font: fontBoldBody)
        currentY += titleHeight

        let labelWidth = contentWidth * 0.45
        let valueWidth = contentWidth - labelWidth
        let rowHeight: CGFloat = 16
        for characteristic in payload.assetCharacteristics {
            let labelRect = CGRect(x: margin, y: currentY, width: labelWidth, height: rowHeight)
            let valueRect = CGRect(x: labelRect.maxX, y: currentY, width: valueWidth, height: rowHeight)
            strokeRect(labelRect, in: cg)
            strokeRect(valueRect, in: cg)
            drawText(characteristic.title, in: labelRect.insetBy(dx: 4, dy: 3), font: fontBody)
            let value = elevatorAssetDisplayValue(characteristic, values: payload.assetValues)
            let valueWithUnit = characteristic.unit.isEmpty || value == "-" ? value : "\(value) \(characteristic.unit)"
            drawText(valueWithUnit, in: valueRect.insetBy(dx: 4, dy: 3), font: fontBody)
            currentY += rowHeight
        }
        return currentY
    }

    private static func elevatorAssetDisplayValue(
        _ characteristic: ElevatorAssetCharacteristic,
        values: [String: String]
    ) -> String {
        let raw = values[characteristic.id]?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        guard !raw.isEmpty else { return "-" }
        let parts = characteristic.allowsMultipleValues
            ? raw.split(separator: ";").map { String($0).trimmingCharacters(in: .whitespacesAndNewlines) }
            : [raw]
        return parts.map { value in
            characteristic.options.first {
                $0.code.caseInsensitiveCompare(value) == .orderedSame
                    || $0.text.caseInsensitiveCompare(value) == .orderedSame
            }?.text ?? value
        }
        .joined(separator: ", ")
    }

    // MARK: - 4. Report Table (addReportTableAK)
    private static func drawReportTable(
        _ payload: ElevatorInspectionPDFPayload,
        in cg: CGContext,
        context: UIGraphicsPDFRendererContext,
        startY: CGFloat
    ) -> CGFloat {
        var currentY = startY
        let colNrWidth: CGFloat = 24
        let colBefundWidth: CGFloat = 45
        let colActionWidth: CGFloat = 45
        let colMaterialWidth: CGFloat = payload.hasMaterialColumn ? 45 : 0
        let colTextWidth = contentWidth - colNrWidth - colBefundWidth - colActionWidth - colMaterialWidth

        // Header drawer
        let drawHeader: (CGFloat) -> CGFloat = { y in
            let headerHeight: CGFloat = 18
            let rNr = CGRect(x: margin, y: y, width: colNrWidth, height: headerHeight)
            let rText = CGRect(x: rNr.maxX, y: y, width: colTextWidth, height: headerHeight)
            let rBefund = CGRect(x: rText.maxX, y: y, width: colBefundWidth, height: headerHeight)
            let rAction = CGRect(x: rBefund.maxX, y: y, width: colActionWidth, height: headerHeight)

            strokeRect(rNr, in: cg)
            strokeRect(rText, in: cg)
            strokeRect(rBefund, in: cg)
            strokeRect(rAction, in: cg)

            drawText("Nr.", in: rNr.insetBy(dx: 2, dy: 4), font: fontBoldBody, alignment: .center)
            drawText("Überprüfte Anlagentechnik", in: rText.insetBy(dx: 4, dy: 4), font: fontBoldBody)
            drawText("Befund", in: rBefund.insetBy(dx: 2, dy: 4), font: fontBoldBody, alignment: .center)
            drawText("Maßnahme", in: rAction.insetBy(dx: 2, dy: 4), font: fontBoldBody, alignment: .center)

            if payload.hasMaterialColumn {
                let rMat = CGRect(x: rAction.maxX, y: y, width: colMaterialWidth, height: headerHeight)
                strokeRect(rMat, in: cg)
                drawText("Material", in: rMat.insetBy(dx: 2, dy: 4), font: fontBoldBody, alignment: .center)
            }

            return y + headerHeight
        }

        currentY = drawHeader(currentY)

        let rowHeight: CGFloat = 16
        for (index, item) in payload.items.enumerated() {
            if currentY + rowHeight > pageBounds.height - margin - 40 {
                context.beginPage()
                currentY = margin
                currentY = drawHeader(currentY)
            }

            let rNr = CGRect(x: margin, y: currentY, width: colNrWidth, height: rowHeight)
            let rText = CGRect(x: rNr.maxX, y: currentY, width: colTextWidth, height: rowHeight)
            let rBefund = CGRect(x: rText.maxX, y: currentY, width: colBefundWidth, height: rowHeight)
            let rAction = CGRect(x: rBefund.maxX, y: currentY, width: colActionWidth, height: rowHeight)

            strokeRect(rNr, in: cg)
            strokeRect(rText, in: cg)
            strokeRect(rBefund, in: cg)
            strokeRect(rAction, in: cg)

            let befundVal = payload.results[item.id] ?? ""
            let actionVal = payload.actions[item.id] ?? ""
            let materialChecked = payload.materials[item.id] == true

            drawText("\(index + 1).", in: rNr.insetBy(dx: 2, dy: 3), font: fontBody, alignment: .center)
            drawText(item.title, in: rText.insetBy(dx: 4, dy: 3), font: fontBody)
            drawText(befundVal, in: rBefund.insetBy(dx: 2, dy: 3), font: fontBody, alignment: .center)
            drawText(actionVal, in: rAction.insetBy(dx: 2, dy: 3), font: fontBody, alignment: .center)

            if payload.hasMaterialColumn {
                let rMat = CGRect(x: rAction.maxX, y: currentY, width: colMaterialWidth, height: rowHeight)
                strokeRect(rMat, in: cg)
                drawText(materialChecked ? "(X)" : "", in: rMat.insetBy(dx: 2, dy: 3), font: fontBody, alignment: .center)
            }

            currentY += rowHeight
        }

        return currentY + 12
    }

    // MARK: - 4. Erläuterungstabelle (addErlaeuterungTableAK)
    private static func drawErlaeuterungTable(_ payload: ElevatorInspectionPDFPayload, in cg: CGContext, startY: CGFloat) -> CGFloat {
        var currentY = startY
        let colWidth = contentWidth / 3

        let headerHeight: CGFloat = 16
        let rHead1 = CGRect(x: margin, y: currentY, width: colWidth, height: headerHeight)
        let rHead2 = CGRect(x: rHead1.maxX, y: currentY, width: colWidth, height: headerHeight)
        let rHead3 = CGRect(x: rHead2.maxX, y: currentY, width: colWidth, height: headerHeight)

        strokeRect(rHead1, in: cg)
        strokeRect(rHead2, in: cg)
        strokeRect(rHead3, in: cg)

        drawText("Befundkennziffer", in: rHead1.insetBy(dx: 4, dy: 3), font: fontBoldBody)
        drawText("Arbeitskennziffer", in: rHead2.insetBy(dx: 4, dy: 3), font: fontBoldBody)
        drawText("Material bestellen", in: rHead3.insetBy(dx: 4, dy: 3), font: fontBoldBody)

        currentY += headerHeight

        // Collect distinct options from inspection items
        var befundLines: [String] = []
        if let firstItem = payload.items.first {
            for opt in firstItem.resultOptions {
                befundLines.append("\(opt.code) = \(opt.text)")
            }
        }
        if befundLines.isEmpty {
            befundLines = [
                "1 = In Ordnung",
                "2 = Mangel beseitigt",
                "3 = Mangel behoben",
                "4 = Mangel vorhanden",
                "5 = entfällt"
            ]
        }

        var actionLines: [String] = []
        if let itemWithActions = payload.items.first(where: { !$0.actionOptions.isEmpty }) {
            for opt in itemWithActions.actionOptions {
                actionLines.append("\(opt.code) = \(opt.text)")
            }
        }
        if actionLines.isEmpty {
            actionLines = [
                "7 = Kleinreparatur durchgeführt",
                "8 = Weiterer Einsatz erforderlich",
                "9 = Keine Maßnahme"
            ]
        }

        let materialText = "(X) - für ein bestelltes Material"

        let col1Text = befundLines.joined(separator: "\n")
        let col2Text = actionLines.joined(separator: "\n")

        let maxLines = max(befundLines.count, actionLines.count, 2)
        let bodyHeight: CGFloat = max(45, CGFloat(maxLines) * 11 + 8)

        let rBody1 = CGRect(x: margin, y: currentY, width: colWidth, height: bodyHeight)
        let rBody2 = CGRect(x: rBody1.maxX, y: currentY, width: colWidth, height: bodyHeight)
        let rBody3 = CGRect(x: rBody2.maxX, y: currentY, width: colWidth, height: bodyHeight)

        strokeRect(rBody1, in: cg)
        strokeRect(rBody2, in: cg)
        strokeRect(rBody3, in: cg)

        drawText(col1Text, in: rBody1.insetBy(dx: 4, dy: 4), font: fontSmall)
        drawText(col2Text, in: rBody2.insetBy(dx: 4, dy: 4), font: fontSmall)
        drawText(materialText, in: rBody3.insetBy(dx: 4, dy: 4), font: fontSmall)

        return currentY + bodyHeight + 12
    }

    // MARK: - 5. Bemerkungstabelle (addBemerkungTableWN)
    private static func drawBemerkungTable(
        _ payload: ElevatorInspectionPDFPayload,
        in cg: CGContext,
        context: UIGraphicsPDFRendererContext,
        startY: CGFloat
    ) -> CGFloat {
        var currentY = startY
        let titleHeight: CGFloat = 20
        let titleRect = CGRect(x: margin, y: currentY, width: contentWidth, height: titleHeight)
        drawText("Bemerkungen", in: titleRect, font: fontTitle)
        currentY += titleHeight

        let colNrWidth: CGFloat = 28
        let colTitleWidth: CGFloat = contentWidth * 0.35
        let colNoteWidth = contentWidth - colNrWidth - colTitleWidth

        let drawHeader: (CGFloat) -> CGFloat = { y in
            let h: CGFloat = 16
            let r1 = CGRect(x: margin, y: y, width: colNrWidth, height: h)
            let r2 = CGRect(x: r1.maxX, y: y, width: colTitleWidth, height: h)
            let r3 = CGRect(x: r2.maxX, y: y, width: colNoteWidth, height: h)
            strokeRect(r1, in: cg)
            strokeRect(r2, in: cg)
            strokeRect(r3, in: cg)
            drawText("Nr.", in: r1.insetBy(dx: 2, dy: 3), font: fontBoldBody, alignment: .center)
            drawText("Zuordnung", in: r2.insetBy(dx: 4, dy: 3), font: fontBoldBody)
            drawText("Bemerkung", in: r3.insetBy(dx: 4, dy: 3), font: fontBoldBody)
            return y + h
        }

        currentY = drawHeader(currentY)

        for (index, item) in payload.items.enumerated() {
            let note = payload.notes[item.id]?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            guard !note.isEmpty else { continue }

            let rowHeight: CGFloat = max(20, CGFloat(note.count / 40 + 1) * 12 + 6)
            if currentY + rowHeight > pageBounds.height - margin - 20 {
                context.beginPage()
                currentY = margin
                currentY = drawHeader(currentY)
            }

            let r1 = CGRect(x: margin, y: currentY, width: colNrWidth, height: rowHeight)
            let r2 = CGRect(x: r1.maxX, y: currentY, width: colTitleWidth, height: rowHeight)
            let r3 = CGRect(x: r2.maxX, y: currentY, width: colNoteWidth, height: rowHeight)

            strokeRect(r1, in: cg)
            strokeRect(r2, in: cg)
            strokeRect(r3, in: cg)

            drawText("\(index + 1).", in: r1.insetBy(dx: 2, dy: 4), font: fontBody, alignment: .center)
            drawText(item.title, in: r2.insetBy(dx: 4, dy: 4), font: fontBody)
            drawText(note, in: r3.insetBy(dx: 4, dy: 4), font: fontBody)

            currentY += rowHeight
        }

        return currentY
    }

    // MARK: - Drawing Helpers
    private static func drawText(
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
            attributes: [
                .font: font,
                .foregroundColor: color,
                .paragraphStyle: style
            ],
            context: nil
        )
    }

    private static func strokeRect(_ rect: CGRect, in context: CGContext) {
        context.setStrokeColor(UIColor.black.cgColor)
        context.setLineWidth(0.5)
        context.stroke(rect)
    }

    private static func strokeLine(from: CGPoint, to: CGPoint, in context: CGContext) {
        context.setStrokeColor(UIColor.black.cgColor)
        context.setLineWidth(0.5)
        context.move(to: from)
        context.addLine(to: to)
        context.strokePath()
    }
}
