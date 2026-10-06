import Foundation

/// The `TFM5-pdf` / `TFM7-pdf` report of a closed new object, built from the
/// locally saved draft only, so closing works offline and a retried upload
/// sends the same report.
extension MobileLadderDraftPayload {
    func reportPDF(worker: NotificationReportWorker) -> Data? {
        guard let context = context?.legacyContext else { return nil }
        let template = context.template
        let fieldValues: [String: String] = [
            "TFMMOBLEITER_WERKSTOFF": material,
            "TFMMOBLEITER_BAUART": constructionType,
            "TFMMOBLEITER_ARTIKELNR": factoryNumber,
            "TFMMOBLEITER_HERSTELLER": manufacturer,
            "TFMMOBLEITER_ANZAHLSPROSSEN": rungCount,
            "TFMMOBLEITER_GESELLSCHAFT": clientCompany,
            "TFMMOBLEITER_RAUM": room,
            "TFMMOBLEITER_INVENTNR": inventoryNumber,
            "TFMMOBLEITER_BEZ": designation
        ]
        var masterData = template.characteristics.sorted { $0.position < $1.position }.map { characteristic in
            NotificationReportComposer.KeyValueRow(
                label: characteristic.title.isEmpty ? characteristic.name : characteristic.title,
                value: NewTechnicalObjectReportPayload.masterDataValue(
                    fieldValues[characteristic.name] ?? "",
                    unit: characteristic.unit,
                    options: characteristic.values.map { ($0.value, $0.title) }
                )
            )
        }
        if masterData.isEmpty {
            // A template without its class snapshot: the form's own fields.
            masterData = [
                ("mobileLadder.field.material", material),
                ("mobileLadder.field.type", constructionType),
                ("mobileLadder.field.factoryNumber", factoryNumber),
                ("mobileLadder.field.manufacturer", manufacturer),
                ("mobileLadder.field.rungCount", rungCount),
                ("mobileLadder.field.clientCompany", clientCompany),
                ("mobileLadder.field.room", room),
                ("mobileLadder.field.inventoryNumber", inventoryNumber),
                ("mobileLadder.field.designation", designation)
            ].map { .init(label: NotificationReportFormat.german($0.0), value: $0.1) }
        }

        let payload = NewTechnicalObjectReportPayload(
            formTitle: NewTechnicalObjectReportPayload.classTitle(
                classDataJSON: template.classDataJSON, fallback: "Mobile Leitern"
            ),
            designation: designation,
            functionalLocation: context.functionalLocation,
            city: context.city,
            street: context.street,
            businessEntity: context.businessEntity,
            building: context.building,
            orgUnit: template.workCenter.ifEmpty(context.workCenter),
            worker: worker,
            performedOn: performedOn,
            masterData: masterData,
            operatingStatus: isDisassembled
                ? .init(label: "Demontiert", value: disassembledComment ?? "")
                : nil,
            items: inspectionItems.map { item in
                .init(
                    number: item.number, title: item.title,
                    result: item.result?.code ?? "", action: item.action?.code ?? "",
                    note: item.comment, hasResult: true
                )
            },
            resultLegend: MobileLadderInspectionResult.allCases.map {
                .init(code: $0.code, text: NotificationReportFormat.german($0.titleKey))
            },
            actionLegend: MobileLadderInspectionAction.allCases.map {
                .init(code: $0.code, text: NotificationReportFormat.german($0.titleKey))
            }
        )
        return NewTechnicalObjectReportPDF.render(payload)
    }
}

extension SubdistributionDraftPayload {
    func reportPDF(worker: NotificationReportWorker) -> Data? {
        guard let context = context?.legacyContext else { return nil }
        let template = context.template
        let designation = ["TFMUNTERVERT_BEZUNTERVERT", "TFMSCHUTZSCH_UNTERVERTEILUNG"].lazy
            .map { self.characteristicValues[$0, default: ""].trimmingCharacters(in: .whitespacesAndNewlines) }
            .first { !$0.isEmpty } ?? ""
        let masterData = template.characteristics.sorted { $0.position < $1.position }.map { characteristic in
            NotificationReportComposer.KeyValueRow(
                label: characteristic.title.isEmpty ? characteristic.name : characteristic.title,
                value: NewTechnicalObjectReportPayload.masterDataValue(
                    characteristicValues[characteristic.name, default: ""],
                    unit: characteristic.unit,
                    options: characteristic.values.map { ($0.value, $0.title) }
                )
            )
        }
        let legendSource = inspectionItems.first { !$0.resultValues.isEmpty }
        let actionSource = inspectionItems.first { !$0.actionValues.isEmpty }

        let payload = NewTechnicalObjectReportPayload(
            formTitle: NewTechnicalObjectReportPayload.classTitle(
                classDataJSON: template.classDataJSON, fallback: "Unterverteilung"
            ),
            designation: designation,
            functionalLocation: context.functionalLocation,
            city: context.city,
            street: context.street,
            businessEntity: context.businessEntity,
            building: context.building,
            orgUnit: template.workCenter.ifEmpty(context.workCenter),
            worker: worker,
            performedOn: performedOn,
            masterData: masterData,
            operatingStatus: isOutOfOperation
                ? .init(label: "Außer Betrieb", value: outOfOperationComment ?? "")
                : nil,
            items: inspectionItems.map { item in
                .init(
                    number: item.number, title: item.title,
                    result: item.result ?? "", action: item.action ?? "",
                    note: item.comment, hasResult: item.requiresResult
                )
            },
            resultLegend: (legendSource?.resultValues ?? []).map { .init(code: $0.value, text: $0.title) },
            actionLegend: (actionSource?.actionValues ?? []).map { .init(code: $0.value, text: $0.title) }
        )
        return NewTechnicalObjectReportPDF.render(payload)
    }
}

extension NotificationReportFormat {
    /// `closeProcess`: `DESCRIPTION + "_" + getNewDateTimeName()`, taken
    /// when the form is closed and the report is built.
    static func legacyReportName(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "dd_MM_yyyy_HH_mm_ss_SSS"
        return "Bericht_\(formatter.string(from: date))"
    }

    /// The German text of a catalog key: the reports are German like the
    /// legacy `PdfBuilder`, whatever the app language.
    static func german(_ key: String) -> String {
        guard let path = Bundle.main.path(forResource: "de", ofType: "lproj"),
              let bundle = Bundle(path: path)
        else { return Bundle.main.localizedString(forKey: key, value: nil, table: nil) }
        return bundle.localizedString(forKey: key, value: nil, table: nil)
    }
}
