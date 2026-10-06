import Foundation
import UIKit

/// Report of a newly created technical object: TFM5 (mobile ladder) and TFM7
/// (subdistribution). It has the layout of the other I1 reports, the
/// equipment inspection report in particular: framed "Formular" header,
/// form data, master data, operating status, the `Befund`/`Maßnahme` table
/// with its legend and the remarks page.
///
/// SAP numbers do not exist yet when the object is closed (`NEU-…`), so the
/// form data shows the designation and functional location instead.
struct NewTechnicalObjectReportPayload: Sendable, Equatable {
    struct Item: Sendable, Equatable {
        let number: Int
        let title: String
        let result: String
        let action: String
        let note: String
        /// Photo positions carry only a note (`isFotoItem`).
        let hasResult: Bool
    }

    struct LegendEntry: Sendable, Equatable {
        let code: String
        let text: String
    }

    /// `klassenMerkmale.TXTBZ`, for example "Mobile Leitern".
    let formTitle: String
    let designation: String
    let functionalLocation: String
    let city: String
    let street: String
    let businessEntity: String
    let building: String
    let orgUnit: String
    let worker: NotificationReportWorker
    let performedOn: Date
    let masterData: [NotificationReportComposer.KeyValueRow]
    /// `addAnwStatusToPdf`: "Demontiert" / "Außer Betrieb" with its note.
    let operatingStatus: NotificationReportComposer.KeyValueRow?
    let items: [Item]
    let resultLegend: [LegendEntry]
    let actionLegend: [LegendEntry]
}

enum NewTechnicalObjectReportPDF {
    static func render(_ payload: NewTechnicalObjectReportPayload) -> Data {
        // Logo and footer follow the worker's company (`USER.GESELLSCHAFT`)
        // only: unlike the other I1 reports, the plant does not replace it.
        let organization = NotificationReportOrganization(
            company: payload.worker.company,
            plant: "",
            personnelNumber: payload.worker.personnelNumber
        ).withCompanyFooter()
        let composer = NotificationReportComposer()
        let date = NotificationReportFormat.reportDate(payload.performedOn)
        composer.formularHeader(
            organization: organization,
            formName: payload.formTitle,
            date: date,
            orgUnit: payload.orgUnit
        )
        composer.keyValueTable([
            .init(label: "Bezeichnung", value: payload.designation),
            .init(label: "Technischer Platz", value: payload.functionalLocation),
            .init(label: "Standort", value: "\(payload.city), \(payload.street)"),
            .init(label: "WE/GE", value: "\(payload.businessEntity)/ \(payload.building)"),
            .init(label: "Name(Prüfer)", value: payload.worker.inspectorText),
            .init(label: "Kalenderwoche", value: "\(NotificationReportFormat.calendarWeek(payload.performedOn))"),
            .init(label: "Datum/Unterschrift", value: date)
        ])
        composer.keyValueTable(payload.masterData)
        if let status = payload.operatingStatus {
            composer.keyValueTable([status])
        }
        let remarks = drawReportTable(payload, on: composer)
        drawLegend(payload, on: composer)
        composer.remarksTable(remarks)
        return composer.render(organization: organization)
    }

    /// `addReportTableAK` without the material column; returns the remarks
    /// for the page after it.
    private static func drawReportTable(
        _ payload: NewTechnicalObjectReportPayload,
        on c: NotificationReportComposer
    ) -> [NotificationReportComposer.Remark] {
        typealias Cell = NotificationReportComposer.Cell
        c.advance(20)
        var widths = [0.05, 0, 0.08, 0.10].map { c.contentWidth * $0 }
        widths[1] = c.contentWidth - widths.reduce(0, +)

        let bold = UIFont.boldSystemFont(ofSize: 8)
        let narrow = UIEdgeInsets(top: 2, left: 1, bottom: 2, right: 1)
        c.tableRow(
            [
                Cell(text: "Nr.", font: bold),
                Cell(text: "Überprüfte Anlagentechnik", font: bold),
                Cell(text: "Befund", font: bold, alignment: .center, insets: narrow),
                Cell(text: "Maßnahme", font: bold, alignment: .center, insets: narrow)
            ],
            widths: widths,
            borders: .horizontal(top: true, bottom: true)
        )

        let insets = UIEdgeInsets(top: 5, left: 4, bottom: 5, right: 4)
        var remarks: [NotificationReportComposer.Remark] = []
        for item in payload.items {
            let number = "\(item.number)."
            let note = item.note.trimmingCharacters(in: .whitespacesAndNewlines)
            if !note.isEmpty {
                remarks.append(.init(number: number, title: item.title, note: note))
            }
            guard item.hasResult else { continue }
            c.tableRow(
                [
                    Cell(text: number, insets: insets),
                    Cell(text: item.title, insets: insets),
                    Cell(text: item.result, alignment: .center, insets: insets),
                    Cell(text: item.action, alignment: .center, insets: insets)
                ],
                widths: widths,
                borders: .horizontal(top: false, bottom: true)
            )
        }
        return remarks
    }

    /// `addErlaeuterungTableAK`: the `key - text` lists of the result and
    /// action codes, kept together.
    private static func drawLegend(_ payload: NewTechnicalObjectReportPayload, on c: NotificationReportComposer) {
        typealias Cell = NotificationReportComposer.Cell
        func list(_ entries: [NewTechnicalObjectReportPayload.LegendEntry]) -> String {
            entries.map { "\($0.code) - \($0.text)" }.joined(separator: "\n")
        }
        let widths = Array(repeating: c.contentWidth * 0.25, count: 2)
        let font = UIFont.systemFont(ofSize: 7)
        let bold = UIFont.boldSystemFont(ofSize: 7)
        let heading = [Cell(text: "Befundkennziffer", font: bold), Cell(text: "Arbeitskennziffer", font: bold)]
        let lists = [Cell(text: list(payload.resultLegend), font: font), Cell(text: list(payload.actionLegend), font: font)]
        c.advance(20)
        c.ensureSpace(c.rowHeight(heading, widths: widths) + c.rowHeight(lists, widths: widths))
        c.tableRow(heading, widths: widths, borders: .none)
        c.tableRow(lists, widths: widths, borders: .none)
    }
}

extension NewTechnicalObjectReportPayload {
    /// The class text (`TXTBZ`) of the template's class snapshot.
    static func classTitle(classDataJSON: String, fallback: String) -> String {
        guard let data = classDataJSON.data(using: .utf8),
              let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let title = object.first(where: { $0.key.uppercased() == "TXTBZ" })?.value as? String,
              !title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        else { return fallback }
        return title.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// `addMasterDataToPdf`: the value-help text of a coded value, otherwise
    /// the value followed by its unit.
    static func masterDataValue(_ value: String, unit: String, options: [(code: String, text: String)]) -> String {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        if let option = options.first(where: { $0.code == trimmed }) { return option.text }
        return unit.isEmpty || trimmed.isEmpty ? trimmed : "\(trimmed) \(unit)"
    }
}
