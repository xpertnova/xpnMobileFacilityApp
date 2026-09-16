import Foundation

enum SAPTFM2InspectionUploadError: LocalizedError {
    case invalidInspection(String)
    case missingSourceNotification(String)
    case missingPhoto(String)
    case missingPDF(String)

    var errorDescription: String? {
        switch self {
        case let .invalidInspection(id):
            return "Ungültige Aufzugskontrolle für Meldung \(id)."
        case let .missingSourceNotification(id):
            return "Quellmeldung \(id) nicht gefunden."
        case let .missingPhoto(id):
            return "Foto \(id) nicht gefunden."
        case let .missingPDF(id):
            return "PDF-Bericht für Meldung \(id) fehlt."
        }
    }
}

enum SAPTFM2InspectionUploadBuilder {
    static func build(
        workItem: OfflineWorkItem,
        source: SAPNotificationSummary,
        syncUserID: String,
        photoData: [String: Data],
        pdfData: Data? = nil,
        now: Date = .now
    ) throws -> SAPNotificationOutgoingBatch {
        guard case let .elevatorInspection(inspection) = workItem.payload,
              inspection.isClosedLocally,
              let processID = inspection.outgoingProcessID,
              !processID.isEmpty,
              let sourceData = source.rawPayloadJSON.data(using: .utf8),
              var notificationData = try JSONSerialization.jsonObject(with: sourceData) as? [String: Any]
        else {
            throw SAPTFM2InspectionUploadError.invalidInspection(source.id)
        }

        let effectivePDF = pdfData ?? inspection.pdfBytes ?? Data()
        guard !effectivePDF.isEmpty else {
            throw SAPTFM2InspectionUploadError.missingPDF(inspection.notificationID)
        }

        if value(named: "T_PLPOD", in: notificationData) == nil,
           let feldwert = stringValue(value(named: "FELDWERT", in: notificationData)),
           let decoded = SAPLegacyDataExchangeCodec.cachedNotificationPayload(fromFeldwert: feldwert) {
            notificationData.merge(decoded) { _, decodedValue in decodedValue }
        }

        guard (stringValue(value(named: "QMART", in: notificationData)) ?? "").uppercased() == "I1" else {
            throw SAPTFM2InspectionUploadError.invalidInspection(source.id)
        }

        let items = ElevatorInspectionDecoder.decodeItems(from: source.rawPayloadJSON)
        guard !items.isEmpty else {
            throw SAPTFM2InspectionUploadError.invalidInspection(source.id)
        }

        // Validate that all items have a Befund result
        for item in items {
            guard let result = inspection.elementValues[item.resultElementID], !result.isEmpty else {
                throw SAPTFM2InspectionUploadError.invalidInspection(source.id)
            }
        }

        let hasDefect = ElevatorInspectionLogic.hasAnyDefect(
            items: items,
            elementValues: inspection.elementValues
        )

        let finalStatus = inspection.closingSystemStatus.isEmpty ? (hasDefect ? "MIAR" : "MMAB") : inspection.closingSystemStatus

        let formNumber = "TFM2"
        let createdDate = basicDate(now)
        let createdTime = basicTime(now)
        let performedDate = basicDate(inspection.performedOn)
        let userID = syncUserID.uppercased()

        notificationData["STTXT"] = finalStatus
        let currentUSTXT = stringValue(value(named: "USTXT", in: notificationData)) ?? ""
        let updatedUSTXT = updatedUserStatus(currentUSTXT, hasDefect: hasDefect)
        notificationData["USTXT"] = updatedUSTXT
        notificationData["AENAM"] = userID
        notificationData["AEDAT"] = performedDate
        notificationData["FORMNR"] = formNumber
        notificationData["STATUSNR"] = hasDefect ? "2" : "1"
        notificationData["FELDWERT"] = ""

        let allowedHeaderColumns = Set(
            LegacySQLiteSchema.byName["TO_T0281"]?.columns.map(\.name) ?? []
        )
        var header: LegacySAPRow = notificationData.reduce(into: [:]) { result, entry in
            let key = entry.key.uppercased()
            if allowedHeaderColumns.contains(key), let value = stringValue(entry.value) {
                result[key] = value
            }
        }

        header["REQID"] = ""
        header["VORGANGSNR"] = processID
        header["QMNUM"] = inspection.notificationID
        header["CREATEDBY"] = userID
        header["CREATEDDATE"] = createdDate
        header["CREATEDTIME"] = createdTime
        header["MODIFIEDBY"] = userID
        header["MODIFIEDDATE"] = createdDate
        header["MODIFIEDTIME"] = createdTime
        header["FORMNR"] = formNumber
        header["STATUSNR"] = hasDefect ? "2" : "1"
        header["STTXT"] = finalStatus
        header["USTXT"] = updatedUSTXT
        header["AEDAT"] = performedDate
        header["AENAM"] = userID
        header["FELDWERT"] = try SAPLegacyDataExchangeCodec.packedFeldwert(notificationData)

        // T_0283 values
        var values: [LegacySAPRow] = []
        for item in items {
            // Property 1 (Befund)
            let befundVal = inspection.elementValues[item.resultElementID] ?? ""
            values.append(valueRow(
                client: source.client, processID: processID, notificationID: inspection.notificationID,
                elementID: item.resultElementID, value: befundVal,
                userID: userID, date: createdDate, time: createdTime
            ))

            // Property 2 (Action, if position exists)
            if item.hasAction, let actionID = item.actionElementID {
                let actionVal = inspection.elementValues[actionID] ?? ""
                values.append(valueRow(
                    client: source.client, processID: processID, notificationID: inspection.notificationID,
                    elementID: actionID, value: actionVal,
                    userID: userID, date: createdDate, time: createdTime
                ))
            }

            // Property 3 (Material, if position exists)
            if item.hasMaterial, let materialID = item.materialElementID {
                let isChecked = inspection.materialFlags[materialID] ?? inspection.materialFlags[item.id] ?? false
                let materialVal = isChecked ? "X" : ""
                values.append(valueRow(
                    client: source.client, processID: processID, notificationID: inspection.notificationID,
                    elementID: materialID, value: materialVal,
                    userID: userID, date: createdDate, time: createdTime
                ))
            }

            // Property 9B (Comment/Note)
            let noteVal = inspection.comments[item.commentElementID] ?? inspection.comments[item.id] ?? ""
            values.append(valueRow(
                client: source.client, processID: processID, notificationID: inspection.notificationID,
                elementID: item.commentElementID, value: noteVal,
                userID: userID, date: createdDate, time: createdTime
            ))
        }

        // Trailing elements
        for elementID in ["\(formNumber)-0000-1", "\(formNumber)-0000-9B"] {
            values.append(valueRow(
                client: source.client, processID: processID, notificationID: inspection.notificationID,
                elementID: elementID, value: "", userID: userID,
                date: createdDate, time: createdTime
            ))
        }

        // T_0282 documents: 1 PDF + up to 20 photos
        var documents: [SAPNotificationOutgoingDocument] = []

        // 1. PDF Document
        let cleanID = inspection.notificationID.replacingOccurrences(
            of: "^0+", with: "", options: .regularExpression
        )
        let pdfDocID = inspection.pdfDocumentID.isEmpty ? "NEU\(processID)PDF" : inspection.pdfDocumentID
        var pdfMetadata = Dictionary(uniqueKeysWithValues:
            (LegacySQLiteSchema.byName["TO_T0282"]?.columns ?? []).map { ($0.name, "") }
        )
        pdfMetadata.merge([
            "MANDT": source.client, "REQID": "", "VORGANGSNR": processID,
            "DOCID": pdfDocID, "ELEMENTNR": "TFM2-pdf",
            "DOKNR": "", "QMNUM": inspection.notificationID,
            "CREATEDBY": userID, "CREATEDDATE": createdDate, "CREATEDTIME": createdTime,
            "MODIFIEDDATE": createdDate, "MODIFIEDTIME": createdTime, "MODIFIEDBY": userID,
            "DOC_TYPE": "PDF", "DOC_MIMETYPE": "application/pdf",
            "NAME": "Bericht_\(cleanID).pdf", "DESCRIPTION": "",
            "FELDWERT": "", "DOKAR": "FMD", "DOKOB": "SMQMEL",
            "OBJKY": inspection.notificationID, "DMS_CONTENTTYPE": "D_TFM_Wartung",
            "DMS_DOCID": "TFM006"
        ]) { _, value in value }
        documents.append(SAPNotificationOutgoingDocument(metadata: pdfMetadata, data: effectivePDF))

        // 2. Photo Attachments
        for attachment in inspection.photoAttachments {
            guard let data = photoData[attachment.localAttachmentID], !data.isEmpty else {
                throw SAPTFM2InspectionUploadError.missingPhoto(attachment.localAttachmentID)
            }
            let captureDate = basicDate(attachment.capturedAt)
            let captureTime = basicTime(attachment.capturedAt)
            var photoMetadata = Dictionary(uniqueKeysWithValues:
                (LegacySQLiteSchema.byName["TO_T0282"]?.columns ?? []).map { ($0.name, "") }
            )
            photoMetadata.merge([
                "MANDT": source.client, "REQID": "", "VORGANGSNR": processID,
                "DOCID": attachment.sapDocumentID, "ELEMENTNR": attachment.sapElementID,
                "DOKNR": "", "QMNUM": inspection.notificationID,
                "CREATEDBY": userID, "CREATEDDATE": captureDate, "CREATEDTIME": captureTime,
                "MODIFIEDDATE": captureDate, "MODIFIEDTIME": captureTime, "MODIFIEDBY": userID,
                "DOC_TYPE": "JPG", "DOC_MIMETYPE": "image/jpeg",
                "NAME": photoName(attachment.capturedAt), "DESCRIPTION": "",
                "FELDWERT": "", "DOKAR": "FMD", "DOKOB": "SMQMEL",
                "OBJKY": inspection.notificationID, "DMS_CONTENTTYPE": "D_TFM_Wartung",
                "DMS_DOCID": "TFM006"
            ]) { _, value in value }
            documents.append(SAPNotificationOutgoingDocument(metadata: photoMetadata, data: data))
        }

        return SAPNotificationOutgoingBatch(
            workItemIDs: [workItem.id],
            attachmentIDs: inspection.photoAttachments.map(\.localAttachmentID),
            processIDs: [processID],
            equipmentIDs: [],
            headers: [header],
            values: values,
            documents: documents,
            equipment: []
        )
    }

    private static func valueRow(
        client: String, processID: String, notificationID: String, elementID: String,
        value: String, userID: String, date: String, time: String
    ) -> LegacySAPRow {
        [
            "MANDT": client, "REQID": "", "VORGANGSNR": processID,
            "ELEMENTNR": elementID, "QMNUM": notificationID,
            "CREATEDBY": userID, "CREATEDDATE": date, "CREATEDTIME": time,
            "MODIFIEDDATE": date, "MODIFIEDTIME": time, "MODIFIEDBY": userID,
            "FELDBEZEICHNUNG": "", "FELDWERT": value
        ]
    }

    private static func updatedUserStatus(_ current: String, hasDefect: Bool) -> String {
        var statuses = current.split(whereSeparator: \.isWhitespace).map(String.init)
        statuses.removeAll { $0 == "Mnot" }
        if hasDefect { statuses.append("Mnot") }
        return statuses.joined(separator: " ")
    }

    private static func value(named name: String, in dictionary: [String: Any]) -> Any? {
        dictionary.first { $0.key.caseInsensitiveCompare(name) == .orderedSame }?.value
    }

    private static func stringValue(_ value: Any?) -> String? {
        if let string = value as? String { return string }
        if let number = value as? NSNumber { return number.stringValue }
        return nil
    }

    private static func basicDate(_ date: Date) -> String { format(date, "yyyyMMdd") }
    private static func basicTime(_ date: Date) -> String { format(date, "HHmmss") }
    private static func photoName(_ date: Date) -> String { "Foto_\(format(date, "dd_MM_yyyy_HH_mm_ss_SSS"))" }

    private static func format(_ date: Date, _ format: String) -> String {
        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = format
        return formatter.string(from: date)
    }
}
