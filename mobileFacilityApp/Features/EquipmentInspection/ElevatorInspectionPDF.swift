import Foundation
import UIKit
import PDFKit

/// Report of a shared equipment inspection (TFM2, TFM4) — the legacy
/// `buildPDF` of `Aufzugskontrolle` and `MasterDataForm`, which differ only in
/// the title, the master-data heading and the material column.
struct ElevatorInspectionPDFPayload: Sendable, Equatable {
    /// `formName` of the legacy doc header (`klassenMerkmale.TXTBZ`).
    let formTitle: String
    /// Heading of the master-data block.
    let masterDataTitle: String
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
    /// `addAnwStatusToPdf`: note of an object reported out of operation.
    let outOfOperationComment: String?

    init(
        formTitle: String = EquipmentInspectionForm.elevator.reportTitleFallback,
        masterDataTitle: String = EquipmentInspectionForm.elevator.reportMasterDataTitle,
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
        assetValues: [String: String] = [:],
        outOfOperationComment: String? = nil
    ) {
        self.formTitle = formTitle
        self.masterDataTitle = masterDataTitle
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
        self.outOfOperationComment = outOfOperationComment
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


/// Report of the shared equipment inspections — the legacy `buildPDF` of
/// `Aufzugskontrolle` / `MasterDataForm`: `addDocHeaderWN`, `addFormHeaderWN`,
/// `addMasterDataToPdf`, `addAnwStatusToPdf`, `addReportTableAK` with its
/// legend, and the remarks page of `addBemerkungTableWN`.
enum ElevatorInspectionPDFRenderer {
    static func render(_ payload: ElevatorInspectionPDFPayload) throws -> ElevatorInspectionPDFArtifact {
        let organization = NotificationReportOrganization(
            company: payload.company,
            plant: payload.plant,
            personnelNumber: payload.workerID
        )
        let composer = NotificationReportComposer()
        composer.formularHeader(
            organization: organization,
            formName: payload.formTitle,
            date: NotificationReportFormat.reportDate(payload.performedAt),
            orgUnit: payload.orgUnit
        )
        composer.keyValueTable(formHeaderRows(payload))
        composer.keyValueTable(payload.assetCharacteristics.map { characteristic in
            .init(label: characteristic.title, value: assetValue(characteristic, values: payload.assetValues))
        })
        if let comment = payload.outOfOperationComment {
            composer.keyValueTable([.init(label: "Außer Betrieb", value: comment)])
        }
        let remarks = drawReportTable(payload, on: composer)
        drawLegend(payload, on: composer)
        composer.remarksTable(remarks)

        let data = composer.render(organization: organization)
        guard !data.isEmpty else { throw ElevatorInspectionPDFError.emptyDocument }
        return ElevatorInspectionPDFArtifact(
            data: data,
            fileName: "Bericht_\(NotificationReportFormat.withoutLeadingZeros(payload.notificationID)).pdf"
        )
    }

    private static func formHeaderRows(_ payload: ElevatorInspectionPDFPayload) -> [NotificationReportComposer.KeyValueRow] {
        var location = NotificationReportComposer.KeyValueRow(label: "Technischer Platz", value: payload.functionalLocation)
        if let equipmentID = payload.equipmentID, !equipmentID.isEmpty {
            location = .init(
                label: "Technischer Platz / Equipment",
                value: "\(payload.functionalLocation) / \(NotificationReportFormat.withoutLeadingZeros(equipmentID)) (\(payload.equipmentName ?? ""))"
            )
        }
        let date = NotificationReportFormat.reportDate(payload.performedAt)
        return [
            .init(
                label: "Meldung / Bezeichnung",
                value: "\(NotificationReportFormat.withoutLeadingZeros(payload.notificationID)) / \(payload.notificationTitle)"
            ),
            location,
            .init(label: "Standort", value: "\(payload.locationCity), \(payload.locationStreet)"),
            .init(label: "WE/GE", value: payload.weGe),
            .init(label: "Name(Prüfer)", value: "\(payload.workerName)( \(payload.workerID))"),
            .init(label: "Kalenderwoche", value: "\(NotificationReportFormat.calendarWeek(payload.performedAt))"),
            .init(label: "Datum/Unterschrift", value: date)
        ]
    }

    /// `addMasterDataToPdf`: option texts, `dd.MM.yyyy` dates, typed values
    /// followed by their unit.
    private static func assetValue(_ characteristic: ElevatorAssetCharacteristic, values: [String: String]) -> String {
        let value = EquipmentMasterDataRules.displayValue(for: characteristic, value: values[characteristic.id] ?? "")
        return characteristic.unit.isEmpty || value.isEmpty ? value : "\(value) \(characteristic.unit)"
    }

    /// `addReportTableAK`; returns the remarks for the page after it.
    private static func drawReportTable(
        _ payload: ElevatorInspectionPDFPayload,
        on c: NotificationReportComposer
    ) -> [NotificationReportComposer.Remark] {
        typealias Cell = NotificationReportComposer.Cell
        c.advance(20)
        var fractions: [CGFloat] = [0.05, 0, 0.08, 0.10]
        if payload.hasMaterialColumn { fractions.append(0.10) }
        var widths = fractions.map { c.contentWidth * $0 }
        widths[1] = c.contentWidth - widths.reduce(0, +)

        let bold = UIFont.boldSystemFont(ofSize: 8)
        let narrow = UIEdgeInsets(top: 2, left: 1, bottom: 2, right: 1)
        var header = [
            Cell(text: "Nr.", font: bold),
            Cell(text: "Überprüfte Anlagentechnik", font: bold),
            Cell(text: "Befund", font: bold, alignment: .center, insets: narrow),
            Cell(text: "Maßnahme", font: bold, alignment: .center, insets: narrow)
        ]
        if payload.hasMaterialColumn {
            header.append(Cell(text: "Material", font: bold, alignment: .center, insets: narrow))
        }
        c.tableRow(header, widths: widths, borders: .horizontal(top: true, bottom: true))

        let insets = UIEdgeInsets(top: 5, left: 4, bottom: 5, right: 4)
        var remarks: [NotificationReportComposer.Remark] = []
        var currentGroup = ""
        for (index, item) in payload.items.enumerated() {
            let number = "\(item.positionNumber > 0 ? item.positionNumber : index + 1)."
            let note = payload.notes[item.id, default: ""].trimmingCharacters(in: .whitespacesAndNewlines)
            if !note.isEmpty {
                remarks.append(.init(number: number, title: item.title, note: note))
            }
            if !item.groupTitle.isEmpty, item.groupTitle != currentGroup {
                c.tableRow(
                    [Cell(text: item.groupTitle, font: bold, span: widths.count)],
                    widths: widths,
                    borders: .horizontal(top: false, bottom: true)
                )
            }
            currentGroup = item.groupTitle
            // Photo positions carry only a note (`isFotoItem`).
            guard item.requiresResult else { continue }
            var cells = [
                Cell(text: number, insets: insets),
                Cell(text: item.title, insets: insets),
                Cell(text: payload.results[item.id, default: ""], alignment: .center, insets: insets),
                Cell(text: payload.actions[item.id, default: ""], alignment: .center, insets: insets)
            ]
            if payload.hasMaterialColumn {
                cells.append(Cell(text: payload.materials[item.id] == true ? "X" : "", alignment: .center, insets: insets))
            }
            c.tableRow(cells, widths: widths, borders: .horizontal(top: false, bottom: true))
        }
        return remarks
    }

    /// `addErlaeuterungTableAK`: the `key - text` lists of the result and
    /// action value helps, kept together.
    private static func drawLegend(_ payload: ElevatorInspectionPDFPayload, on c: NotificationReportComposer) {
        typealias Cell = NotificationReportComposer.Cell
        let results = payload.items.first { !$0.resultOptions.isEmpty }?.resultOptions ?? []
        let actions = payload.items.first { !$0.actionOptions.isEmpty }?.actionOptions ?? []
        let resultText = results.map { "\($0.code) - \($0.text)" }.joined(separator: "\n")
        let actionText = actions.map { "\($0.code) - \($0.text)" }.joined(separator: "\n")

        let widths = Array(repeating: c.contentWidth * 0.25, count: 3)
        let font = UIFont.systemFont(ofSize: 7)
        let bold = UIFont.boldSystemFont(ofSize: 7)
        let material = payload.hasMaterialColumn
        let heading = [
            Cell(text: "Befundkennziffer", font: bold),
            Cell(text: "Arbeitskennziffer", font: bold),
            Cell(text: material ? "Material bestellen" : "", font: bold)
        ]
        let lists = [
            Cell(text: resultText, font: font),
            Cell(text: actionText, font: font),
            Cell(text: material ? "(X) - für ein bestelltes Material" : "", font: font)
        ]
        c.advance(20)
        c.ensureSpace(c.rowHeight(heading, widths: widths) + c.rowHeight(lists, widths: widths))
        c.tableRow(heading, widths: widths, borders: .none)
        c.tableRow(lists, widths: widths, borders: .none)
    }
}
