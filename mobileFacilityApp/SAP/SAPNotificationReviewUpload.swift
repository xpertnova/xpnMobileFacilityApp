import Foundation

struct SAPNotificationOutgoingDocument: Sendable {
    let metadata: [String: String]
    let jpegData: Data
}

struct SAPNotificationOutgoingBatch: Sendable {
    let workItemIDs: [UUID]
    let attachmentIDs: [String]
    let processIDs: [String]
    let headers: [LegacySAPRow]
    let values: [LegacySAPRow]
    let documents: [SAPNotificationOutgoingDocument]

    static let empty = SAPNotificationOutgoingBatch(
        workItemIDs: [], attachmentIDs: [], processIDs: [], headers: [], values: [], documents: []
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
            headers: [header],
            values: values,
            documents: documents
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
            guard item.type == .notificationReview,
                  let review = item.payload.notificationReview,
                  review.isClosedLocally else { return false }
            return [.pendingSynchronization, .failed, .synchronizing].contains(item.status)
        }
        guard !pending.isEmpty else { return .empty }

        do {
            var batches: [SAPNotificationOutgoingBatch] = []
            for item in pending {
                guard let review = item.payload.notificationReview else { continue }
                let page = try await cacheRepository.loadNotifications(
                    for: workerID, matching: review.notificationID,
                    structuralFilter: .empty, limit: 20, offset: 0
                )
                guard let source = page.notifications.first(where: { $0.id == review.notificationID }) else {
                    throw SAPNotificationReviewUploadError.missingSourceNotification(review.notificationID)
                }
                var photos: [String: Data] = [:]
                for attachment in review.photoAttachments {
                    do {
                        photos[attachment.localAttachmentID] = try await photoStore.loadJPEG(id: attachment.localAttachmentID)
                    } catch {
                        throw SAPNotificationReviewUploadError.missingPhoto(attachment.localAttachmentID)
                    }
                }
                batches.append(try SAPNotificationReviewUploadBuilder.build(
                    workItem: item, source: source, syncUserID: syncUserID, photoData: photos
                ))
            }
            let merged = SAPNotificationOutgoingBatch(
                workItemIDs: batches.flatMap(\.workItemIDs),
                attachmentIDs: batches.flatMap(\.attachmentIDs),
                processIDs: batches.flatMap(\.processIDs),
                headers: batches.flatMap(\.headers),
                values: batches.flatMap(\.values),
                documents: batches.flatMap(\.documents)
            )
            try await outgoingStore.replaceNotificationOutgoingRows(
                processIDs: merged.processIDs, headers: merged.headers,
                values: merged.values,
                documents: merged.documents.map { document in
                    document.metadata.reduce(into: LegacySAPRow()) { row, entry in
                        row[entry.key] = entry.value
                    }
                }
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
}
