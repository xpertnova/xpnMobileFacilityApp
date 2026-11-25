import Foundation
import UIKit

/// Worker shown in an I1 report (`USER` row of the legacy app).
struct NotificationReportWorker: Equatable, Sendable {
    let firstName: String
    let lastName: String
    /// `PERSNR`, the legacy sync user (for example `S50828`).
    let personnelNumber: String
    /// `GESELLSCHAFT`.
    let company: String

    init(firstName: String, lastName: String, personnelNumber: String, company: String) {
        self.firstName = firstName
        self.lastName = lastName
        self.personnelNumber = personnelNumber
        self.company = company
    }

    init(profile: SAPUserProfile?, fallbackPersonnelNumber: String) {
        let personnelNumber = profile?.personalNumber ?? ""
        self.init(
            firstName: profile?.firstName ?? "",
            lastName: profile?.name ?? "",
            personnelNumber: personnelNumber.isEmpty ? fallbackPersonnelNumber : personnelNumber,
            company: profile?.company ?? ""
        )
    }

    /// `vorname + " " + name + "( " + userId + ")"` of the Formular reports.
    var inspectorText: String {
        "\(firstName) \(lastName)( \(personnelNumber))"
    }
}

/// Report of a closed TFM1 (Wartungsplan) or TFM3 (Rundgang) notification.
struct NotificationReviewReportPayload: Sendable {
    let formCode: String
    let notificationID: String
    let fields: NotificationReportFields
    let items: [SAPNotificationDetail.InspectionItem]
    let results: [String: NotificationReviewResult]
    let comments: [String: String]
    let performedOn: Date
    let worker: NotificationReportWorker

    var organization: NotificationReportOrganization {
        NotificationReportOrganization(
            company: worker.company,
            plant: fields["IWERK"],
            personnelNumber: worker.personnelNumber
        )
    }

    /// `WartungsPlan.buildPDF` for TFM1, `Rundgang.buildPDF` otherwise.
    var isMaintenancePlan: Bool { formCode.uppercased() == "TFM1" }
}

/// Port of `Rundgang.buildPDF` / `WartungsPlan.buildPDF` with the
/// `PdfBuilder` blocks they use.
enum NotificationReviewReportPDF {
    static func render(_ payload: NotificationReviewReportPayload) -> Data {
        let composer = NotificationReportComposer()
        if payload.isMaintenancePlan {
            drawMaintenancePlan(payload, on: composer)
        } else {
            drawRoundInspection(payload, on: composer)
        }
        return composer.render(organization: payload.organization)
    }

    /// Checklist rows in SAP order: a group band whenever the `HEADER`/`U1`
    /// title changes (`getGroupHeaderListItem`), then the numbered positions.
    private enum Row {
        case section(String)
        case position(number: Int, item: SAPNotificationDetail.InspectionItem)
    }

    private static func rows(_ items: [SAPNotificationDetail.InspectionItem]) -> [Row] {
        var rows: [Row] = []
        var currentGroup = ""
        for (index, item) in items.enumerated() {
            if !item.groupTitle.isEmpty, item.groupTitle != currentGroup {
                rows.append(.section(item.groupTitle))
            }
            currentGroup = item.groupTitle
            rows.append(.position(number: index + 1, item: item))
        }
        return rows
    }

    private static func isDefect(_ item: SAPNotificationDetail.InspectionItem, in payload: NotificationReviewReportPayload) -> Bool {
        // `getUIElementValue(befundKey) === ABAP_TRUE`: "Ja" was answered.
        payload.results[item.id] == .yes
    }

    private static func note(_ item: SAPNotificationDetail.InspectionItem, in payload: NotificationReviewReportPayload) -> String {
        payload.comments[item.id, default: ""].trimmingCharacters(in: .whitespacesAndNewlines)
    }

    // MARK: - Rundgang (addDocHeaderWN, addFormHeaderWN, addReportTableWN)

    private static func drawRoundInspection(_ payload: NotificationReviewReportPayload, on c: NotificationReportComposer) {
        let fields = payload.fields
        c.formularHeader(
            organization: payload.organization,
            formName: "Rundgang",
            date: NotificationReportFormat.reportDate(payload.performedOn),
            orgUnit: fields["GEWRK"]
        )

        var location = NotificationReportComposer.KeyValueRow(label: "Technischer Platz", value: fields["STRNO"])
        if !fields["EQUNR"].isEmpty {
            location = .init(
                label: "Technischer Platz / Equipment",
                value: "\(fields["STRNO"]) / \(NotificationReportFormat.withoutLeadingZeros(fields["EQUNR"]))"
            )
        }
        c.keyValueTable([
            .init(
                label: "Meldung / Bezeichnung",
                value: "\(NotificationReportFormat.withoutLeadingZeros(notificationNumber(payload))) / \(fields["PLTXT"])"
            ),
            location,
            .init(label: "Standort", value: "\(fields["CITY1_TO"]), \(fields["STREET_TO"])"),
            .init(label: "WE/GE", value: "\(fields["TPWEH"])/ \(fields["TPGEB"])"),
            .init(label: "Name(Prüfer)", value: payload.worker.inspectorText),
            .init(label: "Kalenderwoche", value: "\(NotificationReportFormat.calendarWeek(payload.performedOn))"),
            .init(label: "Datum/Unterschrift", value: NotificationReportFormat.reportDate(payload.performedOn))
        ])

        c.advance(20)
        let widths = [0.05, 0.30, 0.55, 0.10].map { c.contentWidth * $0 }
        let bold = UIFont.boldSystemFont(ofSize: 8)
        typealias Cell = NotificationReportComposer.Cell
        c.tableRow(
            [Cell(text: "Nr.", font: bold), Cell(text: "Zuordnung", font: bold),
             Cell(text: "Beschreibung", font: bold), Cell(text: "Befund", font: bold)],
            widths: widths,
            borders: .horizontal(top: true, bottom: true)
        )

        let textInsets = UIEdgeInsets(top: 5, left: 7, bottom: 5, right: 7)
        let numberInsets = UIEdgeInsets(top: 3, left: 5, bottom: 3, right: 5)
        var remarks: [NotificationReportComposer.Remark] = []
        for row in rows(payload.items) {
            switch row {
            case let .section(title):
                c.tableRow(
                    [Cell(), Cell(text: title, font: bold, span: 3)],
                    widths: widths,
                    borders: .horizontal(top: false, bottom: true)
                )
            case let .position(number, item):
                let icon = UIImage(named: isDefect(item, in: payload) ? "ReportFinding_Defect" : "ReportFinding_OK")
                c.tableRow(
                    [
                        Cell(text: "\(number).", insets: numberInsets),
                        Cell(text: item.title, insets: textInsets),
                        Cell(text: item.information, insets: textInsets),
                        Cell(alignment: .center, image: icon, imageWidth: 15, insets: numberInsets)
                    ],
                    widths: widths,
                    borders: .horizontal(top: false, bottom: true)
                )
                let note = note(item, in: payload)
                if !note.isEmpty {
                    remarks.append(.init(number: "\(number).", title: item.title, note: note))
                }
            }
        }
        c.remarksTable(remarks)
    }

    // MARK: - Tätigkeitsbericht (addDocHeader, addFormHeader, addFormHeaderZusatz, addReportTable)

    private static func drawMaintenancePlan(_ payload: NotificationReviewReportPayload, on c: NotificationReportComposer) {
        let fields = payload.fields
        drawActivityReportHeader(payload, on: c)

        // `addFormHeader`: bold label column of 150 pt (144 pt indented).
        var entries: [(label: String, value: String, isSubItem: Bool)] = [
            ("Beschreibung", fields["QMTXT"], false),
            ("Technischer Platz", "\(fields["STRNO"]) \(fields["PLTXT"])", false),
            ("Objektart", fields["PLTXT"], true)
        ]
        if !fields["EQUNR"].isEmpty {
            // The legacy app reads the technical place's floor and supply area
            // from its technical-place table (`GESCHOSS_TP`, `VERSOGBR_TP`).
            entries += [
                ("Geschoss", fields["GESCHOSS_TP"], true),
                ("Versorgungsbereich", fields["VERSOGBR_TP"], true),
                ("Equipment", "\(NotificationReportFormat.withoutLeadingZeros(fields["EQUNR"])) \(fields["EQKTX"])", false),
                ("Objektart", fields["PLTXT"], true),
                ("Geschoss", fields["GESCHOSS_TP"], true),
                ("Raum", fields["RAUM_BEZ"], true),
                ("Versorgungsbereich", fields["VERSOGBR"], true)
            ]
        } else {
            entries += [
                ("Geschoss", fields["GESCHOSS"], true),
                ("Versorgungsbereich", fields["VERSOGBR"], true)
            ]
        }
        let body = UIFont.systemFont(ofSize: 10)
        let bodyBold = UIFont.boldSystemFont(ofSize: 10)
        c.advance(5)
        for entry in entries {
            if !entry.isSubItem { c.advance(6) }
            let indent: CGFloat = entry.isSubItem ? 6 : 0
            let labelWidth: CGFloat = entry.isSubItem ? 144 : 150
            let valueWidth = c.contentWidth - 10 - indent - labelWidth
            let height = ceil(max(
                NotificationReportComposer.textHeight(entry.label, width: labelWidth, font: bodyBold),
                NotificationReportComposer.textHeight(entry.value, width: valueWidth, font: body)
            ))
            c.ensureSpace(height)
            let top = c.y
            let x = c.left + 5 + indent
            let label = entry.label, value = entry.value
            c.draw { _ in
                NotificationReportComposer.drawText(label, in: CGRect(x: x, y: top, width: labelWidth, height: height), font: bodyBold)
                NotificationReportComposer.drawText(value, in: CGRect(x: x + labelWidth, y: top, width: valueWidth, height: height), font: body)
            }
            c.advance(height)
        }
        c.advance(5)

        // `addFormHeaderZusatz`.
        c.advance(10)
        typealias Cell = NotificationReportComposer.Cell
        let zusatzWidths = [0.275, 0.17, 0.115, 0.215, 0.125, 0.10].map { c.contentWidth * $0 }
        let zusatz: [[String]] = [
            ["Erforderliches Startdatum", NotificationReportFormat.germanDate(sapValue: fields["STRMN"]), fields["STRUR"],
             "Gewünschtes Ende", NotificationReportFormat.germanDate(sapValue: fields["LTRMN"]), fields["LTRUR"]],
            ["Wartungsplan", NotificationReportFormat.withoutLeadingZeros(fields["WARPL"]), "",
             "Wartungsposition", NotificationReportFormat.withoutLeadingZeros(fields["WAPOS"]), ""],
            [],
            ["IH-Planergruppe", fields["INGRP"], fields["IWERK"], "", "", ""],
            ["Verantwortl. Arbeitsplatz", fields["GEWRK"], fields["IWERK"], "", "", ""]
        ]
        for columns in zusatz {
            guard columns.count == 6 else {
                c.advance(6)
                continue
            }
            var cells: [Cell] = [Cell(text: columns[0], font: bodyBold)]
            cells.append(Cell(text: columns[1], font: body, span: columns[2].isEmpty ? 2 : 1))
            if !columns[2].isEmpty { cells.append(Cell(text: columns[2], font: body)) }
            cells.append(Cell(text: columns[3], font: bodyBold))
            cells.append(Cell(text: columns[4], font: body, span: columns[5].isEmpty ? 2 : 1))
            if !columns[5].isEmpty { cells.append(Cell(text: columns[5], font: body)) }
            c.tableRow(cells, widths: zusatzWidths, borders: .none)
        }
        c.rule(spacing: 10)

        // `addReportTable`.
        c.advance(10)
        let widths = [0.50, 0.10, 0.10, 0.30].map { c.contentWidth * $0 }
        let font = UIFont.systemFont(ofSize: 11)
        let bold = UIFont.boldSystemFont(ofSize: 11)
        c.tableRow(
            [Cell(text: "Tätigkeiten", font: font),
             Cell(text: "Befund", font: font, alignment: .center, span: 2,
                  insets: UIEdgeInsets(top: 4, left: 6, bottom: 4, right: 6)),
             Cell()],
            widths: widths,
            borders: .none
        )
        c.tableRow(
            [Cell(font: font), Cell(text: "Ja", font: font), Cell(text: "Nein", font: font), Cell(text: "Bemerkung", font: font)],
            widths: widths,
            borders: .horizontal(top: false, bottom: true)
        )
        let textInsets = UIEdgeInsets(top: 5, left: 7, bottom: 5, right: 7)
        for row in rows(payload.items) {
            switch row {
            case let .section(title):
                c.tableRow([Cell(text: title, font: bold, span: 4)], widths: widths, borders: .none)
            case let .position(_, item):
                let defect = isDefect(item, in: payload)
                c.tableRow(
                    [
                        Cell(text: item.title, font: font, insets: textInsets),
                        Cell(image: checkbox(checked: defect), imageWidth: 20),
                        Cell(image: checkbox(checked: !defect), imageWidth: 20),
                        Cell(text: note(item, in: payload), font: font)
                    ],
                    widths: widths,
                    borders: .none
                )
            }
        }
        c.rule(spacing: 2)
    }

    /// `addDocHeader`: title, organisation, notification, date and name with
    /// the logo on the right, followed by a rule.
    private static func drawActivityReportHeader(_ payload: NotificationReviewReportPayload, on c: NotificationReportComposer) {
        let organization = payload.organization
        let logo = organization.logoImage
        let logoWidth: CGFloat = 75
        let logoColumn = logoWidth + 4 + 8
        let column = (c.contentWidth - logoColumn) / 2
        let titleFont = UIFont.boldSystemFont(ofSize: 28)
        let orgFont = UIFont.boldSystemFont(ofSize: 18)
        let font = UIFont.systemFont(ofSize: 12)
        let bold = UIFont.boldSystemFont(ofSize: 12)
        let x = c.left
        let top = c.y

        let formName = "Tätigkeitsbericht"
        let row1 = ceil(NotificationReportComposer.textHeight(formName, width: column * 2 - 8, font: titleFont)) + 4
        let row2 = ceil(NotificationReportComposer.textHeight(organization.name, width: column * 2 - 8, font: orgFont)) + 4 + 15
        let row3 = ceil(NotificationReportComposer.textHeight("Meldung:", width: column, font: font)) + 4
        let notification = notificationNumber(payload)
        let date = NotificationReportFormat.germanDate(payload.performedOn)
        let name = "\(payload.worker.lastName), \(payload.worker.firstName)"

        c.draw { _ in
            if let logo, logo.size.width > 0 {
                let height = logoWidth * logo.size.height / logo.size.width
                logo.draw(in: CGRect(x: x + column * 2 + 6, y: top + 4, width: logoWidth, height: height))
            }
            NotificationReportComposer.drawText(formName, in: CGRect(x: x + 4, y: top + 2, width: column * 2 - 8, height: row1), font: titleFont)
            NotificationReportComposer.drawText(organization.name, in: CGRect(x: x + 4, y: top + row1 + 2, width: column * 2 - 8, height: row2), font: orgFont)
            let row3Top = top + row1 + row2 + 2
            NotificationReportComposer.drawText("Meldung:", in: CGRect(x: x + 4, y: row3Top, width: 65, height: row3), font: bold)
            NotificationReportComposer.drawText(notification, in: CGRect(x: x + 69, y: row3Top, width: column * 2 - 73, height: row3), font: font)
            let row4Top = row3Top + row3
            NotificationReportComposer.drawText("Datum:", in: CGRect(x: x + 4, y: row4Top, width: 65, height: row3), font: bold)
            NotificationReportComposer.drawText(date, in: CGRect(x: x + 69, y: row4Top, width: column - 73, height: row3), font: font)
            NotificationReportComposer.drawText("Name:", in: CGRect(x: x + column + 4, y: row4Top, width: 60, height: row3), font: bold)
            NotificationReportComposer.drawText(name, in: CGRect(x: x + column + 64, y: row4Top, width: column + logoColumn - 68, height: row3), font: font)
        }
        c.advance(row1 + row2 + row3 * 2)
        c.rule(spacing: 18)
    }

    /// `T0281.QMNUM` as SAP delivers it, falling back to the work item's ID.
    private static func notificationNumber(_ payload: NotificationReviewReportPayload) -> String {
        let qmnum = payload.fields["QMNUM"]
        return qmnum.isEmpty ? payload.notificationID : qmnum
    }

    /// `pdfImages.befundMangel` (ticked) / `befundOk` (empty) box.
    private static func checkbox(checked: Bool) -> UIImage {
        let size = CGSize(width: 20, height: 20)
        let format = UIGraphicsImageRendererFormat()
        format.scale = 4
        format.opaque = false
        return UIGraphicsImageRenderer(size: size, format: format).image { context in
            let cg = context.cgContext
            let box = CGRect(x: 3.5, y: 3.5, width: 13, height: 13)
            cg.setStrokeColor(UIColor.black.cgColor)
            cg.setLineWidth(1)
            cg.stroke(box)
            guard checked else { return }
            cg.setLineWidth(1.2)
            cg.setLineCap(.round)
            cg.setLineJoin(.round)
            cg.move(to: CGPoint(x: box.minX + 2.8, y: box.midY + 0.2))
            cg.addLine(to: CGPoint(x: box.minX + 5.4, y: box.maxY - 3.2))
            cg.addLine(to: CGPoint(x: box.maxX - 2.6, y: box.minY + 3.2))
            cg.strokePath()
        }
    }
}
