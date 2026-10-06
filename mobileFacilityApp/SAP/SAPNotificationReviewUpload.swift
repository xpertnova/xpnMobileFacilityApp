import Foundation

struct SAPNotificationOutgoingDocument: Sendable {
    let metadata: [String: String]
    /// JPEG inspection evidence and the TFM7 PDF report use the exact same
    /// metadata -> binary upload -> final post transport sequence.
    let data: Data
    /// A row that only points at a document SAP already holds under its
    /// `DOKNR` (legacy `_insertDocument`). `synchronizeDocTo._prepareAndSend302`
    /// sends such a row like any other, with an empty `FELDWERT`, so the
    /// empty-content guard does not apply to it.
    var referencesExistingDocument: Bool = false
}

struct SAPNotificationOutgoingBatch: Sendable {
    let workItemIDs: [UUID]
    let attachmentIDs: [String]
    let processIDs: [String]
    let equipmentIDs: [String]
    let headers: [LegacySAPRow]
    let values: [LegacySAPRow]
    let documents: [SAPNotificationOutgoingDocument]
    let equipment: [LegacySAPRow]
    /// `TO_T0265` technical-place master records.
    var functionalLocations: [LegacySAPRow] = []
    /// `TO_T0211` master-data proposals (`Vorschlag`).
    var proposals: [LegacySAPRow] = []
    /// `TO_T0284` I2 notifications created from the closed forms.
    var i2Notifications: [LegacySAPRow] = []
    /// `TO_T0285` documents of those I2 notifications. They reuse the parent
    /// photos but are uploaded separately as `I2` documents.
    var i2Documents: [SAPNotificationOutgoingDocument] = []
    /// `TO_T0300` I3 notifications of closed instruction forms.
    var i3Notifications: [LegacySAPRow] = []
    /// `TO_T0302` PDF reports of those I3 notifications, uploaded as `I3`.
    var i3Documents: [SAPNotificationOutgoingDocument] = []
    /// `TO_T0302` rows that only point at a standard SAP DMS document by its
    /// `DOKNR` (legacy `_insertDocument`). They carry no bytes but travel the
    /// same way as every other `TO_T0302` row: staged with the metadata and
    /// sent through `M0002031` with an empty `FELDWERT`.
    var i3DocumentReferences: [SAPNotificationOutgoingDocument] = []
    /// `TO_T0286` meter readings, one row per technical place.
    var meterReadings: [LegacySAPRow] = []

    static let empty = SAPNotificationOutgoingBatch(
        workItemIDs: [], attachmentIDs: [], processIDs: [], equipmentIDs: [],
        headers: [], values: [], documents: [], equipment: []
    )

    var manifest: SAPOutgoingBatchManifest {
        SAPOutgoingBatchManifest(workItemIDs: workItemIDs, attachmentIDs: attachmentIDs)
    }
}

/// Turns closed local work into `TO_*` rows before a TO request and settles
/// that work once SAP answered for it.
protocol SAPOutgoingWorkCoordinating: Sendable {
    /// Whether `prepare()` would find closed work to send. Changes nothing.
    func hasPendingWork() async throws -> Bool
    func prepare() async throws -> SAPNotificationOutgoingBatch
    /// SAP confirmed the TO request: the work is removed from the device.
    func complete(_ batch: SAPOutgoingBatchManifest) async throws
    /// The TO request did not reach ABAP processing: the work is sent again.
    func fail(_ batch: SAPOutgoingBatchManifest, error: Error) async
}

enum SAPMeterReadingUploadError: LocalizedError {
    case missingTechnicalPlace

    var errorDescription: String? {
        "Zählerstand ohne SAP-Messpunkt kann nicht übertragen werden."
    }
}

enum SAPNotificationReviewUploadError: LocalizedError {
    case invalidReview(String)
    case missingSourceNotification(String)
    case missingDocumentMapping(String)
    case missingPhoto(String)

    var errorDescription: String? {
        switch self {
        case let .invalidReview(id):
            "Ungültige Prüfung für Meldung \(id)."
        case let .missingSourceNotification(id):
            "Quellmeldung \(id) nicht gefunden."
        case let .missingDocumentMapping(formNumber):
            "Keine Dokumentklasse für Formular \(formNumber)."
        case let .missingPhoto(id):
            "Foto \(id) nicht gefunden."
        }
    }
}

enum SAPNotificationReviewUploadBuilder {
    static func build(
        workItem: OfflineWorkItem,
        source: SAPNotificationSummary,
        syncUserID: String,
        photoData: [String: Data],
        reportPDF: Data? = nil,
        measuringDocument: String = "",
        now: Date = .now
    ) throws -> SAPNotificationOutgoingBatch {
        guard case let .notificationReview(review) = workItem.payload,
              review.isClosedLocally,
              let processID = review.outgoingProcessID,
              !processID.isEmpty,
              !review.results.isEmpty,
              let sourceData = source.rawPayloadJSON.data(using: .utf8),
              var notificationData = try JSONSerialization.jsonObject(with: sourceData) as? [String: Any]
        else {
            throw SAPNotificationReviewUploadError.invalidReview(source.id)
        }

        if value(named: "T_PLPOD", in: notificationData) == nil,
           let feldwert = stringValue(value(named: "FELDWERT", in: notificationData)),
           let decoded = SAPLegacyDataExchangeCodec.cachedNotificationPayload(fromFeldwert: feldwert) {
            notificationData.merge(decoded) { _, decodedValue in decodedValue }
        }
        guard (stringValue(value(named: "QMART", in: notificationData)) ?? "").uppercased() == "I1" else {
            throw SAPNotificationReviewUploadError.invalidReview(source.id)
        }

        let detail = SAPNotificationDetail(summary: source)
        // A `MEASURE` row has no Befund to answer (`validateFormValues`).
        guard !detail.inspectionItems.isEmpty,
              detail.inspectionItems.allSatisfy({
                  !$0.resultElementID.isEmpty && !$0.commentElementID.isEmpty
                      && ($0.isMeasuringPointEntry || review.results[$0.id] != nil)
              })
        else {
            throw SAPNotificationReviewUploadError.invalidReview(source.id)
        }

        let formNumber = detail.inspectionItems[0].resultElementID
            .split(separator: "-", maxSplits: 1).first.map(String.init) ?? ""
        guard !formNumber.isEmpty else {
            throw SAPNotificationReviewUploadError.invalidReview(source.id)
        }

        let createdDate = basicDate(now)
        let createdTime = basicTime(now)
        let performedDate = basicDate(review.performedOn)
        let userID = syncUserID.uppercased()
        let hasDefect = detail.inspectionItems.contains {
            !$0.isMeasuringPointEntry && review.results[$0.id] == .yes
        }
        notificationData["STTXT"] = "MMAB"
        notificationData["USTXT"] = updatedUserStatus(
            stringValue(value(named: "USTXT", in: notificationData)) ?? "",
            hasDefect: hasDefect
        )
        notificationData["AENAM"] = userID
        notificationData["AEDAT"] = performedDate
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
        header["QMNUM"] = review.notificationID
        header["CREATEDBY"] = userID
        header["CREATEDDATE"] = createdDate
        header["CREATEDTIME"] = createdTime
        header["MODIFIEDBY"] = userID
        header["MODIFIEDDATE"] = createdDate
        header["MODIFIEDTIME"] = createdTime
        header["FORMNR"] = formNumber
        header["STATUSNR"] = hasDefect ? "2" : "1"
        header["STTXT"] = "MMAB"
        header["USTXT"] = stringValue(value(named: "USTXT", in: notificationData)) ?? ""
        header["AEDAT"] = performedDate
        header["AENAM"] = userID
        header["FELDWERT"] = try SAPLegacyDataExchangeCodec.packedFeldwert(notificationData)

        var values: [LegacySAPRow] = []
        for item in detail.inspectionItems {
            // `Rundgang._onViewDisplay` stores the saved `MEASURMENT_BELEG`
            // as the reading button's element value.
            let resultValue = item.isMeasuringPointEntry
                ? measuringDocument
                : (review.results[item.id] == .yes ? "X" : "")
            values.append(valueRow(
                client: source.client, processID: processID, notificationID: review.notificationID,
                elementID: item.resultElementID,
                value: resultValue,
                userID: userID, date: createdDate, time: createdTime
            ))
            values.append(valueRow(
                client: source.client, processID: processID, notificationID: review.notificationID,
                elementID: item.commentElementID,
                value: review.comments[item.id, default: ""],
                userID: userID, date: createdDate, time: createdTime
            ))
        }
        for elementID in ["\(formNumber)-0000-1", "\(formNumber)-0000-9B"] {
            values.append(valueRow(
                client: source.client, processID: processID, notificationID: review.notificationID,
                elementID: elementID, value: "", userID: userID,
                date: createdDate, time: createdTime
            ))
        }

        let mapping: (documentClass: String, valueList: String)?
        if review.photoAttachments.isEmpty {
            mapping = try? documentMapping(notificationData: notificationData, formNumber: formNumber)
        } else {
            mapping = try documentMapping(notificationData: notificationData, formNumber: formNumber)
        }
        var documents = try review.photoAttachments.map { attachment -> SAPNotificationOutgoingDocument in
            guard detail.inspectionItems.contains(where: {
                $0.id == attachment.checklistItemID && $0.commentElementID == attachment.sapElementID
            }), let data = photoData[attachment.localAttachmentID], !data.isEmpty else {
                throw SAPNotificationReviewUploadError.missingPhoto(attachment.localAttachmentID)
            }
            guard let mapping else {
                throw SAPNotificationReviewUploadError.missingDocumentMapping(formNumber)
            }
            let date = basicDate(attachment.capturedAt)
            let time = basicTime(attachment.capturedAt)
            var metadata = Dictionary(uniqueKeysWithValues:
                (LegacySQLiteSchema.byName["TO_T0282"]?.columns ?? []).map { ($0.name, "") }
            )
            metadata.merge([
                "MANDT": source.client, "REQID": "", "VORGANGSNR": processID,
                "DOCID": attachment.sapDocumentID, "ELEMENTNR": attachment.sapElementID,
                "DOKNR": "", "QMNUM": review.notificationID,
                "CREATEDBY": userID, "CREATEDDATE": date, "CREATEDTIME": time,
                "MODIFIEDDATE": date, "MODIFIEDTIME": time, "MODIFIEDBY": userID,
                "DOC_TYPE": "JPG", "DOC_MIMETYPE": "image/jpeg",
                "NAME": photoName(attachment.capturedAt), "DESCRIPTION": "",
                "FELDWERT": "", "DOKAR": "FMD", "DOKOB": "SMQMEL",
                "OBJKY": review.notificationID, "DMS_CONTENTTYPE": mapping.documentClass,
                "DMS_DOCID": mapping.valueList
            ]) { _, value in value }
            return SAPNotificationOutgoingDocument(metadata: metadata, data: data)
        }

        // `BaseFormController.closeProcess`: the report of the closed form is
        // one more `T0282` document of the notification.
        if let reportPDF, !reportPDF.isEmpty, let mapping {
            var metadata = Dictionary(uniqueKeysWithValues:
                (LegacySQLiteSchema.byName["TO_T0282"]?.columns ?? []).map { ($0.name, "") }
            )
            metadata.merge([
                "MANDT": source.client, "REQID": "", "VORGANGSNR": processID,
                "DOCID": "NEU\(processID)PDF", "ELEMENTNR": "\(formNumber)-pdf",
                "DOKNR": "", "QMNUM": review.notificationID,
                "CREATEDBY": userID, "CREATEDDATE": createdDate, "CREATEDTIME": createdTime,
                "MODIFIEDDATE": createdDate, "MODIFIEDTIME": createdTime, "MODIFIEDBY": userID,
                "DOC_TYPE": "PDF", "DOC_MIMETYPE": "application/pdf",
                "NAME": "Bericht_\(format(now, "dd_MM_yyyy_HH_mm_ss_SSS"))", "DESCRIPTION": "Bericht",
                "FELDWERT": "", "DOKAR": "FMD", "DOKOB": "SMQMEL",
                "OBJKY": review.notificationID, "DMS_CONTENTTYPE": mapping.documentClass,
                "DMS_DOCID": mapping.valueList
            ]) { _, value in value }
            documents.append(SAPNotificationOutgoingDocument(metadata: metadata, data: reportPDF))
        }

        return SAPNotificationOutgoingBatch(
            workItemIDs: [workItem.id],
            attachmentIDs: review.photoAttachments.map(\.localAttachmentID),
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

    private static func documentMapping(
        notificationData: [String: Any], formNumber: String
    ) throws -> (documentClass: String, valueList: String) {
        let category = stringValue(value(named: "ZZQCODE_CI", in: notificationData)) ?? ""
        switch category {
        case "I001": return ("D_TFM_Wartung", "TFM006")
        case "I002": return ("D_TFM_Wartung", "TFM005")
        case "I003", "I004": return ("D_TFM_Sachverstaendige", "TFM008")
        case "I006": return ("D_TFM_Wartung", "TFM007")
        default:
            switch formNumber.uppercased() {
            case "TFM1": return ("D_TFM_Wartung", "TFM005")
            case "TFM2": return ("D_TFM_Wartung", "TFM006")
            case "TFM3": return ("D_TFM_Wartung", "TFM007")
            default: throw SAPNotificationReviewUploadError.missingDocumentMapping(formNumber)
            }
        }
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

struct SAPNotificationReviewOutgoingCoordinator: SAPOutgoingWorkCoordinating {
    let workerID: String
    let syncUserID: String
    let offlineRepository: any OfflineWorkRepository
    let cacheRepository: any SAPDataCacheRepository
    let outgoingStore: any SAPNotificationOutgoingStore
    let photoStore: any PhotoAttachmentStore

    func hasPendingWork() async throws -> Bool {
        try await offlineRepository.loadWork(for: workerID).contains(where: \.isReadyForSynchronization)
    }

    func prepare() async throws -> SAPNotificationOutgoingBatch {
        let allWork = try await offlineRepository.loadWork(for: workerID)
        let pending = allWork.filter(\.isReadyForSynchronization)
        // The rows of every waiting work item are built again below. Rows left
        // from an earlier attempt of work that was deleted since, or that can
        // no longer be built, must not go with the request.
        try await outgoingStore.discardNotificationOutgoingRows()
        guard !pending.isEmpty else { return .empty }
        let pendingIDs = Set(pending.map(\.id))

        // Work that cannot be built, such as an instruction form closed before
        // its report was kept, a defect saved before it had a category or a
        // review whose source notification or photo is gone, is marked failed
        // on its own instead of holding back every other item.
        var rejected: [(item: OfflineWorkItem, error: Error)] = []
        do {
            var batches: [SAPNotificationOutgoingBatch] = []
            for item in pending {
                do {
                    if let batch = try await batch(for: item, allWork: allWork, pendingIDs: pendingIDs) {
                        batches.append(batch)
                    }
                } catch {
                    rejected.append((item, error))
                }
            }
            let meterItems = pending.filter { $0.payload.meterReading != nil }
            if !meterItems.isEmpty {
                let meterOutput = try SAPMeterReadingUploadBuilder.build(items: meterItems, syncUserID: syncUserID)
                var meterBatch = SAPNotificationOutgoingBatch(
                    workItemIDs: meterOutput.workItemIDs, attachmentIDs: [], processIDs: [], equipmentIDs: [],
                    headers: [], values: [], documents: [], equipment: []
                )
                meterBatch.meterReadings = meterOutput.rows
                batches.append(meterBatch)
                for item in meterItems where !meterOutput.workItemIDs.contains(item.id) {
                    rejected.append((item, SAPMeterReadingUploadError.missingTechnicalPlace))
                }
            }
            let merged = SAPNotificationOutgoingBatch(
                workItemIDs: batches.flatMap(\.workItemIDs),
                attachmentIDs: batches.flatMap(\.attachmentIDs),
                processIDs: batches.flatMap(\.processIDs),
                equipmentIDs: batches.flatMap(\.equipmentIDs),
                headers: batches.flatMap(\.headers),
                values: batches.flatMap(\.values),
                documents: batches.flatMap(\.documents),
                equipment: batches.flatMap(\.equipment),
                functionalLocations: batches.flatMap(\.functionalLocations),
                proposals: batches.flatMap(\.proposals),
                i2Notifications: batches.flatMap(\.i2Notifications),
                i2Documents: batches.flatMap(\.i2Documents),
                i3Notifications: batches.flatMap(\.i3Notifications),
                i3Documents: batches.flatMap(\.i3Documents),
                // Leaving this out defaults it to empty, which still stages
                // the rows but drops them from the document upload.
                i3DocumentReferences: batches.flatMap(\.i3DocumentReferences),
                meterReadings: batches.flatMap(\.meterReadings)
            )
            let i3DocumentRows = merged.i3Documents.map(\.legacyRow)
                + merged.i3DocumentReferences.map(\.legacyRow)
            try await outgoingStore.replaceNotificationOutgoingRows(
                processIDs: merged.processIDs, equipmentIDs: merged.equipmentIDs,
                headers: merged.headers,
                values: merged.values,
                documents: merged.documents.map(\.legacyRow),
                equipment: merged.equipment,
                functionalLocations: merged.functionalLocations,
                proposals: merged.proposals,
                i2Notifications: merged.i2Notifications,
                i2Documents: merged.i2Documents.map(\.legacyRow),
                i3Notifications: merged.i3Notifications,
                i3Documents: i3DocumentRows,
                meterReadings: merged.meterReadings
            )
            for item in pending {
                if let rejection = rejected.first(where: { $0.item.id == item.id }) {
                    if item.type == .defect {
                        SAPSynchronizationDiagnostics.logI2(
                            "defect \(item.id) not sent: \(rejection.error.localizedDescription)"
                        )
                    }
                    try await offlineRepository.save(copy(
                        item, status: .failed, error: rejection.error.localizedDescription
                    ))
                } else {
                    try await offlineRepository.save(copy(item, status: .synchronizing, error: nil))
                }
            }
            return merged
        } catch {
            for item in pending {
                try? await offlineRepository.save(copy(item, status: .failed, error: error.localizedDescription))
            }
            throw error
        }
    }

    /// The rows of one waiting work item, or nil for work that goes with the
    /// request in another way (meter readings) or not at all.
    private func batch(
        for item: OfflineWorkItem,
        allWork: [OfflineWorkItem],
        pendingIDs: Set<UUID>
    ) async throws -> SAPNotificationOutgoingBatch? {
        switch item.payload {
        case .briefing, .proofOfQualification, .electricalSafety, .firePermit:
            return try await instructionFormBatch(for: item)
        case let .defect(defect):
            return try await defectBatch(for: item, defect: defect)
        case let .notificationReview(review):
            let page = try await cacheRepository.loadNotifications(
                for: workerID, matching: review.notificationID,
                structuralFilter: .empty, limit: 20, offset: 0
            )
            guard let source = page.notifications.first(where: { $0.id == review.notificationID }) else {
                throw SAPNotificationReviewUploadError.missingSourceNotification(review.notificationID)
            }
            var photos: [String: Data] = [:]
            for attachment in review.photoAttachments {
                photos[attachment.localAttachmentID] = try await loadPhoto(attachment.localAttachmentID)
            }
            let userProfile = try? await cacheRepository.loadUserProfile(for: workerID)
            let detail = SAPNotificationDetail(summary: source)
            let report = NotificationReviewReportPDF.render(NotificationReviewReportPayload(
                formCode: detail.formCode,
                notificationID: review.notificationID,
                fields: NotificationReportFields(rawPayloadJSON: source.rawPayloadJSON),
                // `addReportTableWN` prints only rows with a Befund.
                items: detail.inspectionItems.filter { !$0.isMeasuringPointEntry },
                results: review.results,
                comments: review.comments,
                performedOn: review.performedOn,
                worker: NotificationReportWorker(profile: userProfile, fallbackPersonnelNumber: syncUserID)
            ))
            let measuringDocument = try measuringDocument(
                for: source, in: allWork.filter { pendingIDs.contains($0.id) }
            )
            var batch = try SAPNotificationReviewUploadBuilder.build(
                workItem: item, source: source, syncUserID: syncUserID, photoData: photos,
                reportPDF: report, measuringDocument: measuringDocument
            )
            try await addI2Notifications(review.i2Requests, source: source, to: &batch)
            return batch
        case let .elevatorInspection(inspection):
            let page = try await cacheRepository.loadNotifications(
                for: workerID, matching: inspection.notificationID,
                structuralFilter: .empty, limit: 20, offset: 0
            )
            guard let source = page.notifications.first(where: { $0.id == inspection.notificationID }) else {
                throw SAPEquipmentInspectionUploadError.missingSourceNotification(inspection.notificationID)
            }
            var photos: [String: Data] = [:]
            for attachment in inspection.photoAttachments {
                photos[attachment.localAttachmentID] = try await loadPhoto(attachment.localAttachmentID)
            }
            var pdfData = inspection.pdfBytes ?? Data()
            if pdfData.isEmpty {
                let userProfile = try? await cacheRepository.loadUserProfile(for: workerID)
                let form = inspection.form
                let items = ElevatorInspectionDecoder.decodeItems(from: source.rawPayloadJSON)
                let hasMat = form.supportsMaterial && items.contains { $0.hasMaterial }
                var res: [String: String] = [:]
                var acts: [String: String] = [:]
                var mats: [String: Bool] = [:]
                var notes: [String: String] = [:]
                for itm in items {
                    res[itm.id] = inspection.elementValues[itm.resultElementID] ?? ""
                    if let actID = itm.actionElementID { acts[itm.id] = inspection.elementValues[actID] ?? "" }
                    if let matID = itm.materialElementID { mats[itm.id] = inspection.materialFlags[matID] ?? false }
                    notes[itm.id] = inspection.comments[itm.commentElementID] ?? inspection.comments[itm.id] ?? ""
                }
                let fields = NotificationReportFields(rawPayloadJSON: source.rawPayloadJSON)
                let payload = ElevatorInspectionPDFPayload(
                    formTitle: form.reportTitleFallback,
                    masterDataTitle: form.reportMasterDataTitle,
                    notificationID: inspection.notificationID,
                    notificationTitle: fields["PLTXT"].isEmpty ? source.title : fields["PLTXT"],
                    functionalLocation: source.functionalLocationID,
                    equipmentID: source.equipmentID.isEmpty ? nil : source.equipmentID,
                    equipmentName: fields["EQKTX"],
                    locationCity: fields["CITY1_TO"],
                    locationStreet: fields["STREET_TO"],
                    weGe: "\(fields["TPWEH"])/ \(fields["TPGEB"])",
                    workerName: [userProfile?.firstName, userProfile?.name].compactMap { $0 }.filter { !$0.isEmpty }.joined(separator: " "),
                    workerID: userProfile?.personalNumber ?? workerID,
                    company: userProfile?.company ?? "",
                    orgUnit: fields["GEWRK"],
                    plant: fields["IWERK"],
                    performedAt: inspection.performedOn,
                    items: items,
                    results: res,
                    actions: acts,
                    materials: mats,
                    notes: notes,
                    hasMaterialColumn: hasMat,
                    outOfOperationComment: inspection.isOutOfOperation == true
                        ? inspection.outOfOperationComment ?? "" : nil
                )
                pdfData = (try? ElevatorInspectionPDFRenderer.render(payload).data) ?? Data()
            }
            var batch = try SAPEquipmentInspectionUploadBuilder.build(
                workItem: item, source: source, syncUserID: syncUserID,
                photoData: photos, pdfData: pdfData
            )
            // An out-of-service inspection has no positions left to
            // report a fault for.
            if !(inspection.isOutOfOperation ?? false) {
                try await addI2Notifications(inspection.i2Requests ?? [], source: source, to: &batch)
            }
            return batch
        case let .mobileLadder(draft):
            var photos: [String: Data] = [:]
            for attachment in draft.photoAttachments {
                photos[attachment.localAttachmentID] = try await loadPhoto(attachment.localAttachmentID)
            }
            let batch = try SAPMobileLadderUploadBuilder.build(
                workItem: item, draft: draft, syncUserID: syncUserID, photoData: photos
            )
            let photoWorkIDs = allWork.compactMap { candidate -> UUID? in
                guard let collection = candidate.payload.photoCollection,
                      collection.scope.workflow == .mobileLadder,
                      collection.scope.ownerID == draft.localDraftID else { return nil }
                return candidate.id
            }
            return batch.addingCleanupWorkItemIDs(photoWorkIDs)
        case let .subdistribution(draft):
            var photos: [String: Data] = [:]
            for attachment in draft.photoAttachments {
                photos[attachment.localAttachmentID] = try await loadPhoto(attachment.localAttachmentID)
            }
            let batch = try SAPSubdistributionUploadBuilder.build(
                workItem: item, draft: draft, syncUserID: syncUserID, photoData: photos
            )
            let photoWorkIDs = allWork.compactMap { candidate -> UUID? in
                guard let collection = candidate.payload.photoCollection,
                      collection.scope.workflow == .subdistribution,
                      collection.scope.ownerID == draft.localDraftID else { return nil }
                return candidate.id
            }
            return batch.addingCleanupWorkItemIDs(photoWorkIDs)
        default:
            return nil
        }
    }

    func complete(_ batch: SAPOutgoingBatchManifest) async throws {
        try await offlineRepository.delete(ids: batch.workItemIDs)
        for id in batch.attachmentIDs { try? await photoStore.delete(id: id) }
    }

    func fail(_ batch: SAPOutgoingBatchManifest, error: Error) async {
        guard !batch.workItemIDs.isEmpty else { return }
        let work = (try? await offlineRepository.loadWork(for: workerID)) ?? []
        // A cancelled synchronization is not a failure of the work itself.
        let isCancelled = error is CancellationError
        for item in work where batch.workItemIDs.contains(item.id) {
            try? await offlineRepository.save(isCancelled
                ? copy(item, status: .pendingSynchronization, error: nil)
                : copy(item, status: .failed, error: error.localizedDescription))
        }
    }

    private func copy(_ item: OfflineWorkItem, status: OfflineWorkStatus, error: String?) -> OfflineWorkItem {
        OfflineWorkItem(
            id: item.id, workerID: item.workerID, type: item.type, status: status,
            payload: item.payload, createdAt: item.createdAt, updatedAt: .now, syncError: error
        )
    }

    /// Adds the I2 notifications chosen for a closed form. Their documents
    /// are copies of the form's own photo documents, so they are built from
    /// the batch the form produced.
    private func addI2Notifications(
        _ requests: [I2NotificationRequest],
        source: SAPNotificationSummary,
        to batch: inout SAPNotificationOutgoingBatch
    ) async throws {
        guard !requests.isEmpty else { return }
        guard let parent = SAPI2NotificationUploadBuilder.parentNotification(from: source) else {
            throw SAPNotificationReviewUploadError.missingSourceNotification(source.id)
        }
        let output = try SAPI2NotificationUploadBuilder.build(
            requests: requests,
            parentNotification: parent,
            template: try await newNotificationTemplate(),
            parentDocuments: batch.documents,
            syncUserID: syncUserID
        )
        batch.i2Notifications += output.notifications
        batch.i2Documents += output.documents
    }

    /// `insertI3Meldung` for a closed briefing, qualification check,
    /// electrical-safety form or fire permit.
    private func instructionFormBatch(for item: OfflineWorkItem) async throws -> SAPNotificationOutgoingBatch {
        guard let provider = cacheRepository as? any I3NotificationContextProviding else {
            throw I3NotificationUploadError.contextUnavailable
        }
        let input: I3NotificationInput
        switch item.payload {
        case let .briefing(draft):
            let directory = try await cacheRepository.loadFunctionalLocationDirectory(for: workerID)
            guard let building = directory.buildings.first(where: {
                $0.businessEntityID == draft.businessEntityID && $0.buildingCode == draft.buildingCode
            }) else {
                throw I3NotificationUploadError.missingFunctionalLocation(
                    "\(draft.businessEntityID) \(draft.buildingCode)"
                )
            }
            input = I3NotificationInput(
                form: .briefing, workItemID: item.id, functionalLocationID: building.id,
                instructedPerson: draft.instructedPerson, coordinator: draft.coordinator,
                task: draft.taskDescription, start: draft.startDate, end: draft.endDate,
                partner: Self.instructionPartner(id: draft.selectedPartnerID, temporary: draft.temporaryPartner),
                partnerEmail: draft.partnerEmail,
                selectedOptionalSectionIDs: draft.selectedOptionalSectionIDs,
                pdfData: draft.pdfData ?? Data(), completedAt: draft.completedAt ?? item.updatedAt,
                additionalDocumentSymbolIDs: draft.additionalDocumentSymbolIDs ?? []
            )
        case let .proofOfQualification(draft):
            guard let context = draft.context else {
                throw I3NotificationUploadError.missingFunctionalLocation(draft.workLocation)
            }
            input = I3NotificationInput(
                form: .qualification, workItemID: item.id, functionalLocationID: context.functionalLocationID,
                instructedPerson: draft.contactPerson, coordinator: draft.coordinator,
                task: draft.taskDescription, start: draft.executionStart, end: draft.executionEnd,
                partner: Self.instructionPartner(draft.partner), partnerEmail: draft.partnerEmail,
                selectedOptionalSectionIDs: [],
                pdfData: draft.pdfData ?? Data(), completedAt: draft.completedAt ?? item.updatedAt,
                additionalDocumentSymbolIDs: draft.additionalDocumentSymbolIDs ?? []
            )
        case let .electricalSafety(draft):
            guard let context = draft.context else {
                throw I3NotificationUploadError.missingFunctionalLocation(draft.workplace)
            }
            // Forms closed before the report was kept render it again from
            // the saved draft, which holds every value and signature.
            var pdfData = draft.pdfData ?? Data()
            if pdfData.isEmpty {
                pdfData = (try? LegacyElectricalSafetyPDFRenderer().render(draft).data) ?? Data()
            }
            input = I3NotificationInput(
                form: .electricalSafety, workItemID: item.id, functionalLocationID: context.functionalLocationID,
                instructedPerson: draft.instructedPerson, coordinator: draft.coordinator,
                task: draft.workDescription, start: draft.executionStart, end: draft.executionEnd,
                partner: Self.instructionPartner(draft.partner), partnerEmail: draft.partnerEmail,
                selectedOptionalSectionIDs: [],
                pdfData: pdfData, completedAt: draft.completedAt ?? item.updatedAt
            )
        case let .firePermit(draft):
            guard let context = draft.context else {
                throw I3NotificationUploadError.missingFunctionalLocation(draft.workDescription)
            }
            input = I3NotificationInput(
                form: .firePermit, workItemID: item.id, functionalLocationID: context.functionalLocationID,
                instructedPerson: draft.instructedPerson, coordinator: draft.coordinator,
                task: draft.workDescription, start: draft.executionStart, end: draft.executionEnd,
                partner: Self.instructionPartner(draft.partner), partnerEmail: draft.partnerEmail,
                selectedOptionalSectionIDs: [],
                pdfData: draft.pdfData, completedAt: draft.completedAt
            )
        default:
            throw I3NotificationUploadError.contextUnavailable
        }
        var existingPartner = ""
        if case let .existing(addressNumber) = input.partner { existingPartner = addressNumber }
        let context = try await provider.loadI3NotificationContext(
            functionalLocationID: input.functionalLocationID,
            planNumber: input.form.planNumber,
            partnerAddressNumber: existingPartner
        )
        return try SAPI3NotificationUploadBuilder.build(input: input, context: context, syncUserID: syncUserID)
    }

    /// The briefing keeps a partner entered on the device beside its choice.
    private static func instructionPartner(
        id: String,
        temporary: BriefingTemporaryPartner?
    ) -> I3NotificationPartner {
        if let temporary, temporary.id == id {
            return .new(.init(
                addressNumber: temporary.id, title: temporary.title, company: temporary.company,
                contactName: temporary.contactName, email: temporary.email, telephone: temporary.telephone,
                street: temporary.street, houseNumber: temporary.houseNumber,
                postalCode: temporary.postalCode, city: temporary.city, country: temporary.country
            ))
        }
        return id.isEmpty ? .none : .existing(addressNumber: id)
    }

    /// `getData4PartnerCreate` treats an address number with `NEU` as new.
    private static func instructionPartner(_ partner: SAPBriefingPartner?) -> I3NotificationPartner {
        guard let partner, !partner.id.isEmpty else { return .none }
        guard partner.id.contains("NEU") else { return .existing(addressNumber: partner.id) }
        return .new(.init(
            addressNumber: partner.id, company: partner.name, contactName: partner.contactName,
            email: partner.email, street: partner.street, houseNumber: partner.houseNumber,
            postalCode: partner.postalCode, city: partner.city, country: partner.country
        ))
    }

    /// A defect from the defect form: an I2 under the I1 the technician chose.
    private func defectBatch(for item: OfflineWorkItem, defect: DefectDraftPayload) async throws -> SAPNotificationOutgoingBatch {
        guard defect.category?.createsNotification == true else {
            throw SAPDefectNotificationUploadError.missingCategory
        }
        guard let parentID = defect.parentNotificationID, !parentID.isEmpty else {
            throw SAPDefectNotificationUploadError.missingParentNotification
        }
        let page = try await cacheRepository.loadNotifications(
            for: workerID, matching: parentID, structuralFilter: .empty, limit: 20, offset: 0
        )
        guard let source = page.notifications.first(where: { $0.id == parentID }),
              let parent = SAPI2NotificationUploadBuilder.parentNotification(from: source)
        else {
            throw SAPDefectNotificationUploadError.parentNotificationUnavailable(parentID)
        }
        var photos: [String: Data] = [:]
        for id in defect.attachmentIDs {
            photos[id] = try await loadPhoto(id)
        }
        return try SAPDefectNotificationUploadBuilder.build(
            workItem: item, defect: defect, parentNotification: parent,
            template: try await newNotificationTemplate(), photoData: photos, syncUserID: syncUserID
        )
    }

    private func newNotificationTemplate() async throws -> [String: Any]? {
        guard let provider = cacheRepository as? any I2NotificationTemplateProviding,
              let json = try await provider.loadNewNotificationTemplateJSON(),
              let data = json.data(using: .utf8)
        else { return nil }
        return (try? JSONSerialization.jsonObject(with: data)) as? [String: Any]
    }

    /// The packed readings of the notification's place that go with this
    /// synchronization, or empty when there are none.
    private func measuringDocument(for source: SAPNotificationSummary, in work: [OfflineWorkItem]) throws -> String {
        let payload = source.rawPayloadJSON.data(using: .utf8)
            .flatMap { try? JSONSerialization.jsonObject(with: $0) as? [String: Any] } ?? [:]
        let locationID = (payload["STRNO"] as? String).flatMap { $0.isEmpty ? nil : $0 } ?? source.functionalLocationID
        let readings = work.filter { $0.payload.meterReading?.meter.technicalPlaceID == locationID }
        guard !readings.isEmpty else { return "" }
        let output = try SAPMeterReadingUploadBuilder.build(items: readings, syncUserID: syncUserID)
        return (output.rows.first?["MEASURMENT_BELEG"] ?? nil) ?? ""
    }

    private func loadPhoto(_ id: String) async throws -> Data {
        do { return try await photoStore.loadJPEG(id: id) }
        catch { throw SAPNotificationReviewUploadError.missingPhoto(id) }
    }
}

private extension SAPNotificationOutgoingBatch {
    func addingCleanupWorkItemIDs(_ ids: [UUID]) -> Self {
        var copy = Self(
            workItemIDs: workItemIDs + ids, attachmentIDs: attachmentIDs,
            processIDs: processIDs, equipmentIDs: equipmentIDs, headers: headers,
            values: values, documents: documents, equipment: equipment,
            functionalLocations: functionalLocations, proposals: proposals,
            i2Notifications: i2Notifications, i2Documents: i2Documents,
            i3Notifications: i3Notifications, i3Documents: i3Documents
        )
        copy.i3DocumentReferences = i3DocumentReferences
        copy.meterReadings = meterReadings
        return copy
    }
}

extension SAPNotificationOutgoingDocument {
    /// The metadata as the `TO_T0282` / `TO_T0285` row it is stored as.
    var legacyRow: LegacySAPRow {
        metadata.reduce(into: LegacySAPRow()) { row, entry in
            row[entry.key] = entry.value
        }
    }
}

/// The template a new TFM5/TFM7 object was drafted with still is the one
/// `getItemNewMeldung` would select for its functional location.
enum SAPLegacyCreationTemplateRule {
    static func matches(_ template: some LegacyCreationTemplate, plant: String, plannerGroup: String) -> Bool {
        plannerGroup.isEmpty || (template.plant == plant && template.plannerGroup == plannerGroup)
    }
}

enum SAPMobileLadderUploadBuilder {
    static func build(
        workItem: OfflineWorkItem,
        draft: MobileLadderDraftPayload,
        syncUserID: String,
        photoData: [String: Data],
        now: Date = .now
    ) throws -> SAPNotificationOutgoingBatch {
        guard let identifiers = draft.legacyIdentifiers,
              let context = draft.context?.legacyContext,
              !draft.inspectionItems.isEmpty,
              (draft.isDisassembled || draft.inspectionItems.allSatisfy({ $0.result != nil })),
              draft.photoAttachments.count <= 20,
              // Drafts saved while any template could be picked must not
              // reach SAP with another plant's template.
              SAPLegacyCreationTemplateRule.matches(
                context.template, plant: context.plant, plannerGroup: context.plannerGroup
              ),
              let sourceData = context.sourceNotificationJSON.data(using: .utf8),
              var notificationData = try JSONSerialization.jsonObject(with: sourceData) as? [String: Any]
        else { throw SAPNotificationReviewUploadError.invalidReview(draft.localDraftID) }

        let createdDate = date(now), createdTime = time(now), performedDate = date(draft.performedOn)
        let user = syncUserID.uppercased()
        let template = context.template
        // `HeaderFormBuilder.setValue4Process`: Demontiert, result 2 or 4, or
        // result 3 with an action other than "repaired" is deficient. The
        // notification's user status (profile ZPMNI1) then gains `Mnot`;
        // iBet/dem belong to the equipment's `ANW_STATUS` only.
        let isDeficient = draft.isDisassembled || draft.inspectionItems.contains { item in
            switch item.result {
            case .cleaningRequired, .majorDefect: true
            case .minorDefect: item.action != nil && item.action != .repaired
            default: false
            }
        }
        let userStatus = isDeficient ? "Mnot" : ""
        notificationData.merge(jsonObject(template.planDataJSON ?? "")) { _, plan in plan }
        notificationData.merge([
            "MANDT": context.client, "QMNUM": identifiers.notificationNumber, "QMART": "I1",
            "QMTXT": draft.designation, "STTXT": "MMAB", "USTXT": userStatus,
            "EQUNR": identifiers.equipmentNumber, "EQKTX": draft.designation,
            "STRNO": context.functionalLocation, "TPLND": context.country, "TPORT": context.location,
            "TPWEH": context.businessEntity, "TPGEB": context.building, "TPGSG": context.trade,
            "IWERK": template.plant.isEmpty ? context.plant : template.plant,
            "INGRP": template.plannerGroup.isEmpty ? context.plannerGroup : template.plannerGroup,
            "GEWRK": template.workCenter.isEmpty ? context.workCenter : template.workCenter,
            "PLNTY": template.planType, "PLNNR": template.planNumber, "PLNAL": template.planVersion,
            "FORMNR": template.formCode, "AEDAT": performedDate, "AENAM": user,
            "T_PLPOD": planRows(draft, formCode: template.formCode)
        ]) { _, new in new }
        notificationData["FELDWERT"] = ""

        let allowed = Set(LegacySQLiteSchema.byName["TO_T0281"]?.columns.map(\.name) ?? [])
        var header: LegacySAPRow = notificationData.reduce(into: [:]) { result, entry in
            let key = entry.key.uppercased()
            if allowed.contains(key), let value = string(entry.value) { result[key] = value }
        }
        header.merge([
            "REQID": "", "VORGANGSNR": identifiers.processNumber,
            "QMNUM": identifiers.notificationNumber, "CREATEDBY": user,
            "CREATEDDATE": createdDate, "CREATEDTIME": createdTime,
            "MODIFIEDBY": user, "MODIFIEDDATE": createdDate, "MODIFIEDTIME": createdTime,
            "FORMNR": template.formCode, "STATUSNR": isDeficient ? "2" : "1", "STTXT": "MMAB",
            "FELDWERT": try SAPLegacyDataExchangeCodec.packedFeldwert(notificationData)
        ]) { _, new in new }

        var values: [LegacySAPRow] = []
        for item in draft.inspectionItems {
            values.append(valueRow(context.client, identifiers, item.resultElementID, item.result?.rawValue ?? "", user, createdDate, createdTime))
            if let action = item.action {
                values.append(valueRow(context.client, identifiers, item.actionElementID, action.rawValue, user, createdDate, createdTime))
            }
            values.append(valueRow(context.client, identifiers, item.commentElementID, item.comment, user, createdDate, createdTime))
        }
        values.append(valueRow(
            context.client, identifiers, "\(template.formCode)-0000-1",
            draft.isDisassembled ? "dem" : "iBet", user, createdDate, createdTime
        ))
        values.append(valueRow(
            context.client, identifiers, "\(template.formCode)-0000-9B",
            draft.disassembledComment ?? "", user, createdDate, createdTime
        ))

        var documents = try draft.photoAttachments.map { attachment -> SAPNotificationOutgoingDocument in
            let belongsToInspection = draft.inspectionItems.contains(where: {
                $0.id == attachment.inspectionItemID && $0.commentElementID == attachment.sapElementID
            })
            let belongsToDisassembledStatus = attachment.inspectionItemID == MobileLadderDraftPayload.disassembledStatusRowID
                && attachment.sapElementID == "\(template.formCode)-0000-9B"
            guard (belongsToInspection || belongsToDisassembledStatus),
                  let jpeg = photoData[attachment.localAttachmentID], !jpeg.isEmpty else {
                throw SAPNotificationReviewUploadError.missingPhoto(attachment.localAttachmentID)
            }
            let captureDate = date(attachment.capturedAt), captureTime = time(attachment.capturedAt)
            var metadata = Dictionary(uniqueKeysWithValues:
                (LegacySQLiteSchema.byName["TO_T0282"]?.columns ?? []).map { ($0.name, "") }
            )
            metadata.merge([
                "MANDT": context.client, "REQID": "", "VORGANGSNR": identifiers.processNumber,
                "DOCID": attachment.sapDocumentID, "ELEMENTNR": attachment.sapElementID,
                "QMNUM": identifiers.notificationNumber, "CREATEDBY": user,
                "CREATEDDATE": captureDate, "CREATEDTIME": captureTime,
                "MODIFIEDBY": user, "MODIFIEDDATE": captureDate, "MODIFIEDTIME": captureTime,
                "DOC_TYPE": "JPG", "DOC_MIMETYPE": "image/jpeg",
                "NAME": photoName(attachment.capturedAt), "DOKAR": "FMD", "DOKOB": "SMQMEL",
                "OBJKY": identifiers.notificationNumber,
                "DMS_CONTENTTYPE": "D_TFM_Dokumentation", "DMS_DOCID": "TFM001"
            ]) { _, new in new }
            return SAPNotificationOutgoingDocument(metadata: metadata, data: jpeg)
        }
        // `closeProcess`: every closed form carries its report as
        // `<FORMNR>-pdf`. Ladders closed before the report existed have none.
        if let reportPDF = draft.reportPDF, !reportPDF.isEmpty,
           let pdfDocumentID = draft.pdfDocumentID, !pdfDocumentID.isEmpty {
            var metadata = Dictionary(uniqueKeysWithValues:
                (LegacySQLiteSchema.byName["TO_T0282"]?.columns ?? []).map { ($0.name, "") }
            )
            metadata.merge([
                "MANDT": context.client, "REQID": "", "VORGANGSNR": identifiers.processNumber,
                "DOCID": pdfDocumentID, "ELEMENTNR": "\(template.formCode)-pdf",
                "QMNUM": identifiers.notificationNumber, "CREATEDBY": user,
                "CREATEDDATE": createdDate, "CREATEDTIME": createdTime,
                "MODIFIEDBY": user, "MODIFIEDDATE": createdDate, "MODIFIEDTIME": createdTime,
                "DOC_TYPE": "PDF", "DOC_MIMETYPE": "application/pdf",
                "NAME": NotificationReportFormat.legacyReportName(draft.reportCreatedAt ?? now), "DESCRIPTION": "Bericht",
                "DOKAR": "FMD", "DOKOB": "SMQMEL", "OBJKY": identifiers.notificationNumber,
                "DMS_CONTENTTYPE": "D_TFM_Dokumentation", "DMS_DOCID": "TFM001"
            ]) { _, new in new }
            documents.append(SAPNotificationOutgoingDocument(metadata: metadata, data: reportPDF))
        }

        // A new ladder's `masterDataQuery` carries the new `EQUNR` and no
        // `STRNO`, so its proposals are filed under the new equipment.
        let proposals = SAPMasterDataProposalRows.rows(
            proposals: draft.outgoingProposals,
            processID: identifiers.processNumber,
            notificationID: identifiers.notificationNumber,
            equipmentID: identifiers.equipmentNumber,
            functionalLocationID: "",
            userID: user,
            date: createdDate,
            time: createdTime
        )

        return SAPNotificationOutgoingBatch(
            workItemIDs: [workItem.id], attachmentIDs: draft.photoAttachments.map(\.localAttachmentID),
            processIDs: [identifiers.processNumber], equipmentIDs: [identifiers.equipmentNumber],
            headers: [header], values: values, documents: documents,
            equipment: [try equipmentRow(draft, context, identifiers, user: user, createdAt: workItem.createdAt)],
            proposals: proposals
        )
    }

    private static func planRows(_ draft: MobileLadderDraftPayload, formCode: String) -> [[String: Any]] {
        draft.inspectionItems.map { item in
            let operation = item.resultElementID.split(separator: "-").dropFirst().first.map(String.init) ?? ""
            return [
                "USR00": "POSITION", "STEUS": formCode, "VORNR": operation,
                "LTXA1": item.title, "LTXA2": item.information,
                "T_PROPS": [["POSNR": "1", "DFVAL": "1;2;3;4;5;"], ["POSNR": "2", "DFVAL": "7;8;9;"]]
            ]
        }
    }

    private static func equipmentRow(
        _ draft: MobileLadderDraftPayload,
        _ context: MobileLadderLegacyContext,
        _ identifiers: MobileLadderLegacyIdentifiers,
        user: String,
        createdAt: Date
    ) throws -> LegacySAPRow {
        var equipment = jsonObject(context.template.equipmentDataJSON)
        // `afterGetNewMasterData` stamps the new equipment with
        // `getBerichtDatum()` (`yyyy-MM-dd`) and the user. Without these
        // dates SAP's maintenance plan creation fails on an initial key date.
        let creationDate = format(createdAt, "yyyy-MM-dd")
        equipment.merge([
            "MANDT_TO": context.client, "EQUNR_TO": identifiers.equipmentNumber,
            "ERDAT_TO": creationDate, "ERNAM_TO": user, "AEDAT_TO": creationDate, "AENAM_TO": user,
            "EQUNR": identifiers.equipmentNumber, "EQTYP_TO": "I",
            "EQART_TO": context.template.equipmentType, "EQKTX": draft.designation,
            "SHTXT_TO": draft.designation, "TPLNR_TO": context.functionalLocation,
            "SWERK_TO": context.template.plant.isEmpty ? context.plant : context.template.plant,
            // `setAnwStatus`: a dismantled ladder is also `INAK`.
            "ANW_STATUS": draft.isDisassembled ? "dem" : "iBet", "SYS_STATUS": draft.isDisassembled ? "INAK" : "",
            "T_CLASS_EQ": classData(draft, context)
        ]) { _, new in new }
        return [
            "MANDT": context.client, "REQID": "", "STRNO": context.functionalLocation,
            "EQUNR": identifiers.equipmentNumber,
            "FELDWERT": try SAPLegacyDataExchangeCodec.packedFeldwert(equipment)
        ]
    }

    private static func classData(_ draft: MobileLadderDraftPayload, _ context: MobileLadderLegacyContext) -> [String: Any] {
        var data = jsonObject(context.template.classDataJSON)
        let values = [
            "TFMMOBLEITER_WERKSTOFF": draft.material,
            "TFMMOBLEITER_BAUART": draft.constructionType,
            "TFMMOBLEITER_ARTIKELNR": draft.factoryNumber,
            "TFMMOBLEITER_HERSTELLER": draft.manufacturer,
            "TFMMOBLEITER_ANZAHLSPROSSEN": draft.rungCount,
            "TFMMOBLEITER_GESELLSCHAFT": draft.clientCompany,
            "TFMMOBLEITER_RAUM": draft.room,
            "TFMMOBLEITER_INVENTNR": draft.inventoryNumber,
            "TFMMOBLEITER_BEZ": draft.designation
        ]
        data["KLART"] = context.template.classType
        data["KLASSE"] = context.template.className
        data["KLAGR"] = context.template.classGroup
        data["T_CLOBJDAT"] = context.template.characteristics.map {
            ["ATNAM": $0.name, "ATWRT": sapValue(values[$0.name] ?? "", of: $0), "MSEHI": $0.unit]
        }
        return data
    }

    /// The dropdowns show a value's text (`ATWTB`), while `_buildHeaderForm`
    /// keys each ComboBox item by `ATWRT` and stores that key. Some keys
    /// differ from their text, e.g. `PLATTFORMLEITER` for "Plattformleiter".
    private static func sapValue(_ value: String, of characteristic: MobileLadderLegacyCharacteristic) -> String {
        characteristic.values.first { $0.title == value }?.value ?? value
    }

    private static func valueRow(
        _ client: String, _ identifiers: MobileLadderLegacyIdentifiers,
        _ element: String, _ value: String, _ user: String, _ date: String, _ time: String
    ) -> LegacySAPRow {
        [
            "MANDT": client, "REQID": "", "VORGANGSNR": identifiers.processNumber,
            "ELEMENTNR": element, "QMNUM": identifiers.notificationNumber,
            "CREATEDBY": user, "CREATEDDATE": date, "CREATEDTIME": time,
            "MODIFIEDBY": user, "MODIFIEDDATE": date, "MODIFIEDTIME": time,
            "FELDBEZEICHNUNG": "", "FELDWERT": value
        ]
    }

    private static func jsonObject(_ value: String) -> [String: Any] {
        guard let data = value.data(using: .utf8),
              let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return [:] }
        return object
    }

    private static func string(_ value: Any) -> String? {
        if let value = value as? String { return value }
        if let value = value as? NSNumber { return value.stringValue }
        return nil
    }

    private static func date(_ value: Date) -> String { format(value, "yyyyMMdd") }
    private static func time(_ value: Date) -> String { format(value, "HHmmss") }
    private static func photoName(_ value: Date) -> String { "Foto_\(format(value, "dd_MM_yyyy_HH_mm_ss_SSS"))" }
    private static func format(_ value: Date, _ pattern: String) -> String {
        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = pattern
        return formatter.string(from: value)
    }
}

/// Builds the native TFM7 outgoing rows.  Its data model is intentionally not
/// shared with TFM5: all characteristic identifiers and inspection element
/// IDs come from the SAP template snapshot carried by the draft.
enum SAPSubdistributionUploadBuilder {
    static func build(
        workItem: OfflineWorkItem,
        draft: SubdistributionDraftPayload,
        syncUserID: String,
        photoData: [String: Data],
        now: Date = .now
    ) throws -> SAPNotificationOutgoingBatch {
        guard let identifiers = draft.legacyIdentifiers,
              let context = draft.context?.legacyContext,
              let reportPDF = draft.reportPDF, !reportPDF.isEmpty,
              let pdfDocumentID = draft.pdfDocumentID, !pdfDocumentID.isEmpty,
              draft.photoAttachments.count <= 20,
              (draft.isOutOfOperation || inspectionRequirementsAreComplete(draft)),
              SAPLegacyCreationTemplateRule.matches(
                context.template, plant: context.plant, plannerGroup: context.plannerGroup
              ),
              let sourceData = context.sourceNotificationJSON.data(using: .utf8),
              var notificationData = try JSONSerialization.jsonObject(with: sourceData) as? [String: Any]
        else { throw SAPNotificationReviewUploadError.invalidReview(draft.localDraftID) }

        let createdDate = date(now), createdTime = time(now), performedDate = date(draft.performedOn)
        let user = syncUserID.uppercased()
        let template = context.template
        let hasDefect = !draft.isOutOfOperation && draft.inspectionItems.contains(where: \.isDefective)
        let closureStatus: String
        if draft.isOutOfOperation { closureStatus = "MIAR" }
        else if hasDefect { closureStatus = draft.defectCloseAction?.sapStatus ?? "MIAR" }
        else { closureStatus = "MMAB" }
        let applicationStatus = draft.isOutOfOperation ? "aBet" : "iBet"
        // Only `Mnot` goes to the notification (profile ZPMNI1); aBet/iBet
        // are the equipment's `ANW_STATUS` and the `TFM7-0000-1` value.
        let userStatus = (draft.isOutOfOperation || hasDefect) ? "Mnot" : ""
        guard let designation = equipmentDesignation(draft: draft) else {
            throw SAPNotificationReviewUploadError.invalidReview(draft.localDraftID)
        }

        notificationData.merge(jsonObject(template.planDataJSON ?? "")) { _, plan in plan }
        notificationData.merge([
            "MANDT": context.client, "QMNUM": identifiers.notificationNumber, "QMART": "I1",
            "QMTXT": designation, "STTXT": closureStatus, "USTXT": userStatus,
            "EQUNR": identifiers.equipmentNumber, "EQKTX": designation,
            "STRNO": context.functionalLocation, "TPLND": context.country, "TPORT": context.location,
            "TPWEH": context.businessEntity, "TPGEB": context.building, "TPGSG": context.segment,
            "IWERK": template.plant.isEmpty ? context.plant : template.plant,
            "INGRP": template.plannerGroup.isEmpty ? context.plannerGroup : template.plannerGroup,
            "GEWRK": template.workCenter.isEmpty ? context.workCenter : template.workCenter,
            "PLNTY": template.planType, "PLNNR": template.planNumber, "PLNAL": template.planVersion,
            "FORMNR": "TFM7", "AEDAT": performedDate, "AENAM": user,
            "T_PLPOD": planRows(draft)
        ]) { _, value in value }
        notificationData["FELDWERT"] = ""

        let allowed = Set(LegacySQLiteSchema.byName["TO_T0281"]?.columns.map(\.name) ?? [])
        var header: LegacySAPRow = notificationData.reduce(into: [:]) { result, entry in
            let key = entry.key.uppercased()
            if allowed.contains(key), let value = string(entry.value) { result[key] = value }
        }
        header.merge([
            "REQID": "", "VORGANGSNR": identifiers.processNumber, "QMNUM": identifiers.notificationNumber,
            "CREATEDBY": user, "CREATEDDATE": createdDate, "CREATEDTIME": createdTime,
            "MODIFIEDBY": user, "MODIFIEDDATE": createdDate, "MODIFIEDTIME": createdTime,
            "FORMNR": "TFM7", "STATUSNR": draft.isOutOfOperation || hasDefect ? "2" : "1",
            "STTXT": closureStatus, "USTXT": userStatus, "AEDAT": performedDate, "AENAM": user,
            "FELDWERT": try SAPLegacyDataExchangeCodec.packedFeldwert(notificationData)
        ]) { _, value in value }

        var values: [LegacySAPRow] = []
        for characteristic in template.characteristics {
            values.append(valueRow(
                context.client, identifiers, characteristic.name,
                draft.characteristicValues[characteristic.name, default: ""], user, createdDate, createdTime
            ))
        }
        for item in draft.inspectionItems {
            if !item.resultElementID.isEmpty {
                values.append(valueRow(context.client, identifiers, item.resultElementID, item.result ?? "", user, createdDate, createdTime))
            }
            if !item.actionElementID.isEmpty {
                values.append(valueRow(context.client, identifiers, item.actionElementID, item.action ?? "", user, createdDate, createdTime))
            }
            values.append(valueRow(context.client, identifiers, item.commentElementID, item.comment, user, createdDate, createdTime))
        }
        values.append(valueRow(context.client, identifiers, "TFM7-0000-1", applicationStatus, user, createdDate, createdTime))
        values.append(valueRow(
            context.client,
            identifiers,
            SubdistributionDraftPayload.outOfOperationCommentElementID,
            draft.outOfOperationComment ?? "",
            user,
            createdDate,
            createdTime
        ))

        var documents = try draft.photoAttachments.map { attachment -> SAPNotificationOutgoingDocument in
            let belongsToInspection = draft.inspectionItems.contains(where: {
                $0.id == attachment.inspectionItemID && $0.commentElementID == attachment.sapElementID
            })
            let belongsToOutOfOperationStatus = attachment.inspectionItemID == SubdistributionDraftPayload.statusRowID
                && attachment.sapElementID == SubdistributionDraftPayload.outOfOperationCommentElementID
            guard (belongsToInspection || belongsToOutOfOperationStatus),
                  let jpeg = photoData[attachment.localAttachmentID], !jpeg.isEmpty else {
                throw SAPNotificationReviewUploadError.missingPhoto(attachment.localAttachmentID)
            }
            return SAPNotificationOutgoingDocument(
                metadata: documentMetadata(
                    client: context.client, processID: identifiers.processNumber,
                    notificationID: identifiers.notificationNumber, documentID: attachment.sapDocumentID,
                    elementID: attachment.sapElementID, user: user, timestamp: attachment.capturedAt,
                    type: "JPG", mimeType: "image/jpeg", name: photoName(attachment.capturedAt)
                ), data: jpeg
            )
        }
        // `closeProcess`: named and described "Bericht" like every report.
        var reportMetadata = documentMetadata(
            client: context.client, processID: identifiers.processNumber,
            notificationID: identifiers.notificationNumber, documentID: pdfDocumentID,
            elementID: "TFM7-pdf", user: user, timestamp: now,
            type: "PDF", mimeType: "application/pdf",
            name: NotificationReportFormat.legacyReportName(draft.reportCreatedAt ?? now)
        )
        reportMetadata["DESCRIPTION"] = "Bericht"
        documents.append(SAPNotificationOutgoingDocument(metadata: reportMetadata, data: reportPDF))

        return SAPNotificationOutgoingBatch(
            workItemIDs: [workItem.id], attachmentIDs: draft.photoAttachments.map(\.localAttachmentID),
            processIDs: [identifiers.processNumber], equipmentIDs: [identifiers.equipmentNumber],
            headers: [header], values: values, documents: documents,
            equipment: [try equipmentRow(
                draft: draft, context: context, identifiers: identifiers, designation: designation,
                user: user, createdAt: workItem.createdAt
            )]
        )
    }

    /// Keep SAP upload validation equal to the creation screen: a draft that
    /// bypasses the UI still cannot close TFM7 without the required photo and
    /// comment for a documentation position.
    private static func inspectionRequirementsAreComplete(_ draft: SubdistributionDraftPayload) -> Bool {
        draft.inspectionItems.allSatisfy { item in
            let hasResult = !item.requiresResult || item.result != nil
            let hasDocumentation = !item.requiresDocumentation
                || (!item.comment.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                    && draft.photoAttachments.contains(where: { $0.inspectionItemID == item.id }))
            return hasResult && hasDocumentation
        }
    }

    private static func planRows(_ draft: SubdistributionDraftPayload) -> [[String: Any]] {
        draft.inspectionItems.map { item in
            [
                "USR00": "POSITION", "STEUS": "TFM7", "VORNR": item.id,
                "LTXA1": item.title, "LTXA2": item.information,
                "T_PROPS": [
                    ["POSNR": "1", "DFVAL": item.resultValues.map(\.value).joined(separator: ";") + ";"],
                    ["POSNR": "2", "DFVAL": item.actionValues.map(\.value).joined(separator: ";") + ";"]
                ]
            ]
        }
    }

    private static func equipmentDesignation(draft: SubdistributionDraftPayload) -> String? {
        for name in ["TFMUNTERVERT_BEZUNTERVERT", "TFMSCHUTZSCH_UNTERVERTEILUNG"] {
            let value = draft.characteristicValues[name, default: ""].trimmingCharacters(in: .whitespacesAndNewlines)
            if !value.isEmpty { return value }
        }
        return nil
    }

    private static func equipmentRow(
        draft: SubdistributionDraftPayload, context: SubdistributionLegacyContext,
        identifiers: SubdistributionLegacyIdentifiers, designation: String,
        user: String, createdAt: Date
    ) throws -> LegacySAPRow {
        var equipment = jsonObject(context.template.equipmentDataJSON)
        // `afterGetNewMasterData`, as for TFM5.
        let creationDate = format(createdAt, "yyyy-MM-dd")
        equipment.merge([
            "MANDT_TO": context.client, "EQUNR_TO": identifiers.equipmentNumber,
            "ERDAT_TO": creationDate, "ERNAM_TO": user, "AEDAT_TO": creationDate, "AENAM_TO": user,
            "EQUNR": identifiers.equipmentNumber, "EQTYP_TO": "I", "EQART_TO": "TFMNSPV",
            "EQKTX": designation, "SHTXT_TO": designation, "TPLNR_TO": context.functionalLocation,
            "SWERK_TO": context.template.plant.isEmpty ? context.plant : context.template.plant,
            "ANW_STATUS": draft.isOutOfOperation ? "aBet" : "iBet",
            "SYS_STATUS": draft.isOutOfOperation ? "INAK" : "",
            "T_CLASS_EQ": classData(draft: draft, context: context)
        ]) { _, value in value }
        return [
            "MANDT": context.client, "REQID": "", "STRNO": context.functionalLocation,
            "EQUNR": identifiers.equipmentNumber,
            "FELDWERT": try SAPLegacyDataExchangeCodec.packedFeldwert(equipment)
        ]
    }

    private static func classData(draft: SubdistributionDraftPayload, context: SubdistributionLegacyContext) -> [String: Any] {
        var data = jsonObject(context.template.classDataJSON)
        data["KLART"] = context.template.classType
        data["KLASSE"] = context.template.className
        data["KLAGR"] = context.template.classGroup
        data["T_CLOBJDAT"] = context.template.characteristics.map { characteristic in
            ["ATNAM": characteristic.name, "ATWRT": draft.characteristicValues[characteristic.name, default: ""], "MSEHI": characteristic.unit]
        }
        return data
    }

    private static func documentMetadata(
        client: String, processID: String, notificationID: String, documentID: String, elementID: String,
        user: String, timestamp: Date, type: String, mimeType: String, name: String
    ) -> [String: String] {
        let day = date(timestamp), clock = time(timestamp)
        var metadata = Dictionary(uniqueKeysWithValues:
            (LegacySQLiteSchema.byName["TO_T0282"]?.columns ?? []).map { ($0.name, "") }
        )
        metadata.merge([
            "MANDT": client, "REQID": "", "VORGANGSNR": processID, "DOCID": documentID,
            "ELEMENTNR": elementID, "QMNUM": notificationID, "CREATEDBY": user,
            "CREATEDDATE": day, "CREATEDTIME": clock, "MODIFIEDBY": user,
            "MODIFIEDDATE": day, "MODIFIEDTIME": clock, "DOC_TYPE": type,
            "DOC_MIMETYPE": mimeType, "NAME": name, "DOKAR": "FMD", "DOKOB": "SMQMEL",
            "OBJKY": notificationID, "DMS_CONTENTTYPE": "D_TFM_Dokumentation", "DMS_DOCID": "TFM001"
        ]) { _, value in value }
        return metadata
    }

    private static func valueRow(
        _ client: String, _ identifiers: SubdistributionLegacyIdentifiers, _ element: String,
        _ value: String, _ user: String, _ date: String, _ time: String
    ) -> LegacySAPRow {
        [
            "MANDT": client, "REQID": "", "VORGANGSNR": identifiers.processNumber,
            "ELEMENTNR": element, "QMNUM": identifiers.notificationNumber,
            "CREATEDBY": user, "CREATEDDATE": date, "CREATEDTIME": time,
            "MODIFIEDBY": user, "MODIFIEDDATE": date, "MODIFIEDTIME": time,
            "FELDBEZEICHNUNG": "", "FELDWERT": value
        ]
    }

    private static func jsonObject(_ value: String) -> [String: Any] {
        guard let data = value.data(using: .utf8),
              let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return [:] }
        return object
    }

    private static func string(_ value: Any) -> String? {
        if let value = value as? String { return value }
        if let value = value as? NSNumber { return value.stringValue }
        return nil
    }

    private static func date(_ value: Date) -> String { format(value, "yyyyMMdd") }
    private static func time(_ value: Date) -> String { format(value, "HHmmss") }
    private static func photoName(_ value: Date) -> String { "Foto_\(format(value, "dd_MM_yyyy_HH_mm_ss_SSS"))" }
    private static func format(_ value: Date, _ pattern: String) -> String {
        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = pattern
        return formatter.string(from: value)
    }
}
