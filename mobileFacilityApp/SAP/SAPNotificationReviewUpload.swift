import Foundation

struct SAPNotificationOutgoingDocument: Sendable {
    let metadata: [String: String]
    let jpegData: Data
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

    static let empty = SAPNotificationOutgoingBatch(
        workItemIDs: [], attachmentIDs: [], processIDs: [], equipmentIDs: [],
        headers: [], values: [], documents: [], equipment: []
    )
}

enum SAPNotificationReviewUploadError: Error {
    case invalidReview(String)
    case missingSourceNotification(String)
    case missingDocumentMapping(String)
    case missingPhoto(String)
}

enum SAPNotificationReviewUploadBuilder {
    static func build(
        workItem: OfflineWorkItem,
        source: SAPNotificationSummary,
        syncUserID: String,
        photoData: [String: Data],
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
        guard !detail.inspectionItems.isEmpty,
              detail.inspectionItems.allSatisfy({
                  !$0.resultElementID.isEmpty && !$0.commentElementID.isEmpty && review.results[$0.id] != nil
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
        let hasDefect = review.results.values.contains(.yes)
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
            values.append(valueRow(
                client: source.client, processID: processID, notificationID: review.notificationID,
                elementID: item.resultElementID,
                value: review.results[item.id] == .yes ? "X" : "",
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
            mapping = nil
        } else {
            mapping = try documentMapping(notificationData: notificationData, formNumber: formNumber)
        }
        let documents = try review.photoAttachments.map { attachment -> SAPNotificationOutgoingDocument in
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
            return SAPNotificationOutgoingDocument(metadata: metadata, jpegData: data)
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

struct SAPNotificationReviewOutgoingCoordinator: Sendable {
    let workerID: String
    let syncUserID: String
    let offlineRepository: any OfflineWorkRepository
    let cacheRepository: any SAPDataCacheRepository
    let outgoingStore: any SAPNotificationOutgoingStore
    let photoStore: any PhotoAttachmentStore

    func prepare() async throws -> SAPNotificationOutgoingBatch {
        let allWork = try await offlineRepository.loadWork(for: workerID)
        let pending = allWork.filter { item in
            guard [.pendingSynchronization, .failed, .synchronizing].contains(item.status) else {
                return false
            }
            if let review = item.payload.notificationReview { return review.isClosedLocally }
            if let inspection = item.payload.elevatorInspection { return inspection.isClosedLocally }
            return item.payload.mobileLadder != nil
        }
        guard !pending.isEmpty else { return .empty }

        do {
            var batches: [SAPNotificationOutgoingBatch] = []
            for item in pending {
                switch item.payload {
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
                    batches.append(try SAPNotificationReviewUploadBuilder.build(
                        workItem: item, source: source, syncUserID: syncUserID, photoData: photos
                    ))
                case let .elevatorInspection(inspection):
                    let page = try await cacheRepository.loadNotifications(
                        for: workerID, matching: inspection.notificationID,
                        structuralFilter: .empty, limit: 20, offset: 0
                    )
                    guard let source = page.notifications.first(where: { $0.id == inspection.notificationID }) else {
                        throw SAPTFM2InspectionUploadError.missingSourceNotification(inspection.notificationID)
                    }
                    var photos: [String: Data] = [:]
                    for attachment in inspection.photoAttachments {
                        photos[attachment.localAttachmentID] = try await loadPhoto(attachment.localAttachmentID)
                    }
                    var pdfData = inspection.pdfBytes ?? Data()
                    if pdfData.isEmpty {
                        let userProfile = try? await cacheRepository.loadUserProfile(for: workerID)
                        let items = ElevatorInspectionDecoder.decodeItems(from: source.rawPayloadJSON)
                        let hasMat = items.contains { $0.hasMaterial }
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
                        let payload = ElevatorInspectionPDFPayload(
                            notificationID: inspection.notificationID,
                            notificationTitle: source.title,
                            functionalLocation: source.functionalLocationID,
                            equipmentID: source.equipmentID.isEmpty ? nil : source.equipmentID,
                            equipmentName: nil,
                            locationCity: "",
                            locationStreet: "",
                            weGe: "",
                            workerName: [userProfile?.firstName, userProfile?.name].compactMap { $0 }.filter { !$0.isEmpty }.joined(separator: " "),
                            workerID: userProfile?.personalNumber ?? workerID,
                            company: userProfile?.company ?? "",
                            orgUnit: "",
                            plant: "",
                            performedAt: inspection.performedOn,
                            items: items,
                            results: res,
                            actions: acts,
                            materials: mats,
                            notes: notes,
                            hasMaterialColumn: hasMat
                        )
                        pdfData = (try? ElevatorInspectionPDFRenderer.render(payload).data) ?? Data()
                    }
                    batches.append(try SAPTFM2InspectionUploadBuilder.build(
                        workItem: item, source: source, syncUserID: syncUserID,
                        photoData: photos, pdfData: pdfData
                    ))
                case let .mobileLadder(draft):
                    var photos: [String: Data] = [:]
                    for attachment in draft.photoAttachments {
                        photos[attachment.localAttachmentID] = try await loadPhoto(attachment.localAttachmentID)
                    }
                    var batch = try SAPMobileLadderUploadBuilder.build(
                        workItem: item, draft: draft, syncUserID: syncUserID, photoData: photos
                    )
                    let photoWorkIDs = allWork.compactMap { candidate -> UUID? in
                        guard let collection = candidate.payload.photoCollection,
                              collection.scope.workflow == .mobileLadder,
                              collection.scope.ownerID == draft.localDraftID else { return nil }
                        return candidate.id
                    }
                    batch = batch.addingCleanupWorkItemIDs(photoWorkIDs)
                    batches.append(batch)
                default:
                    continue
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
                equipment: batches.flatMap(\.equipment)
            )
            try await outgoingStore.replaceNotificationOutgoingRows(
                processIDs: merged.processIDs, equipmentIDs: merged.equipmentIDs,
                headers: merged.headers,
                values: merged.values,
                documents: merged.documents.map { document in
                    document.metadata.reduce(into: LegacySAPRow()) { row, entry in
                        row[entry.key] = entry.value
                    }
                },
                equipment: merged.equipment
            )
            for item in pending {
                try await offlineRepository.save(copy(item, status: .synchronizing, error: nil))
            }
            return merged
        } catch {
            for item in pending {
                try? await offlineRepository.save(copy(item, status: .failed, error: error.localizedDescription))
            }
            throw error
        }
    }

    func complete(_ batch: SAPNotificationOutgoingBatch) async throws {
        try await offlineRepository.delete(ids: batch.workItemIDs)
        for id in batch.attachmentIDs { try? await photoStore.delete(id: id) }
    }

    func fail(_ batch: SAPNotificationOutgoingBatch, error: Error) async {
        guard !batch.workItemIDs.isEmpty else { return }
        let work = (try? await offlineRepository.loadWork(for: workerID)) ?? []
        for item in work where batch.workItemIDs.contains(item.id) {
            try? await offlineRepository.save(copy(item, status: .failed, error: error.localizedDescription))
        }
    }

    private func copy(_ item: OfflineWorkItem, status: OfflineWorkStatus, error: String?) -> OfflineWorkItem {
        OfflineWorkItem(
            id: item.id, workerID: item.workerID, type: item.type, status: status,
            payload: item.payload, createdAt: item.createdAt, updatedAt: .now, syncError: error
        )
    }

    private func loadPhoto(_ id: String) async throws -> Data {
        do { return try await photoStore.loadJPEG(id: id) }
        catch { throw SAPNotificationReviewUploadError.missingPhoto(id) }
    }
}

private extension SAPNotificationOutgoingBatch {
    func addingCleanupWorkItemIDs(_ ids: [UUID]) -> Self {
        Self(
            workItemIDs: workItemIDs + ids, attachmentIDs: attachmentIDs,
            processIDs: processIDs, equipmentIDs: equipmentIDs, headers: headers,
            values: values, documents: documents, equipment: equipment
        )
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
              let sourceData = context.sourceNotificationJSON.data(using: .utf8),
              var notificationData = try JSONSerialization.jsonObject(with: sourceData) as? [String: Any]
        else { throw SAPNotificationReviewUploadError.invalidReview(draft.localDraftID) }

        let createdDate = date(now), createdTime = time(now), performedDate = date(draft.performedOn)
        let user = syncUserID.uppercased()
        let template = context.template
        notificationData.merge([
            "MANDT": context.client, "QMNUM": identifiers.notificationNumber, "QMART": "I1",
            "QMTXT": draft.designation, "STTXT": "MMAB", "USTXT": draft.isDisassembled ? "dem" : "iBet",
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
            "FORMNR": template.formCode, "STATUSNR": "1", "STTXT": "MMAB",
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

        let documents = try draft.photoAttachments.map { attachment -> SAPNotificationOutgoingDocument in
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
            return SAPNotificationOutgoingDocument(metadata: metadata, jpegData: jpeg)
        }

        return SAPNotificationOutgoingBatch(
            workItemIDs: [workItem.id], attachmentIDs: draft.photoAttachments.map(\.localAttachmentID),
            processIDs: [identifiers.processNumber], equipmentIDs: [identifiers.equipmentNumber],
            headers: [header], values: values, documents: documents,
            equipment: [try equipmentRow(draft, context, identifiers)]
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
        _ identifiers: MobileLadderLegacyIdentifiers
    ) throws -> LegacySAPRow {
        var equipment = jsonObject(context.template.equipmentDataJSON)
        equipment.merge([
            "EQUNR": identifiers.equipmentNumber, "EQTYP_TO": "I",
            "EQART_TO": context.template.equipmentType, "EQKTX": draft.designation,
            "SHTXT_TO": draft.designation, "TPLNR_TO": context.functionalLocation,
            "SWERK_TO": context.template.plant.isEmpty ? context.plant : context.template.plant,
            "ANW_STATUS": draft.isDisassembled ? "dem" : "iBet", "SYS_STATUS": "",
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
            ["ATNAM": $0.name, "ATWRT": values[$0.name] ?? "", "MSEHI": $0.unit]
        }
        return data
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
