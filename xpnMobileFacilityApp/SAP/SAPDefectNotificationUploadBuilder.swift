import CryptoKit
import Foundation

enum SAPDefectNotificationUploadError: LocalizedError {
    case missingCategory
    case missingParentNotification
    case parentNotificationUnavailable(String)

    var errorDescription: String? {
        switch self {
        case .missingCategory:
            "Kategorie fehlt. Bitte die Störungsmeldung öffnen und eine Kategorie wählen."
        case .missingParentNotification:
            "I1-Meldung fehlt. Bitte die Störungsmeldung öffnen und eine I1-Meldung wählen."
        case let .parentNotificationUnavailable(id):
            "I1-Meldung \(id) ist nicht mehr offen. Bitte die Störungsmeldung öffnen und eine andere I1-Meldung wählen."
        }
    }
}

/// Builds the `TO_T0284` I2 notification and its `TO_T0285` photos for a
/// defect reported from the defect form.
///
/// SAP creates an I2 only under an I1 (`/EZO/PM_TFM_F01_NOTIF_CREATE`,
/// `CREATE_TFM4I2`: "message ref. no. is missing"), so the defect is built
/// exactly like an I2 of a closed form (`insertI2Meldung`, see
/// `SAPI2NotificationUploadBuilder`) with the I1 the technician chose as
/// parent, except that:
/// - `PRIOK` follows the chosen priority (`DefectPriority.sapPriority`);
/// - its photos are its own, not copies of the parent's, and go up as `I2`
///   documents of class `D_TFM_AllgemeineDokumente` / `TFM009`.
enum SAPDefectNotificationUploadBuilder {
    struct Identifiers: Equatable {
        /// `VORGANGSNR` of the photos; also clears them on a retried upload.
        let processID: String
        /// Temporary `QMNUM`, `NEU-` plus eight characters.
        let notificationID: String
    }

    static func identifiers(for workItemID: UUID) -> Identifiers {
        let hex = workItemID.uuidString.replacingOccurrences(of: "-", with: "").uppercased()
        return Identifiers(processID: hex, notificationID: "NEU-\(hex.prefix(8))")
    }

    static func build(
        workItem: OfflineWorkItem,
        defect: DefectDraftPayload,
        parentNotification: [String: Any],
        template: [String: Any]?,
        photoData: [String: Data],
        syncUserID: String,
        now: Date = .now
    ) throws -> SAPNotificationOutgoingBatch {
        guard let category = defect.category, category.createsNotification else {
            throw SAPDefectNotificationUploadError.missingCategory
        }
        guard defect.parentNotificationID?.isEmpty == false else {
            throw SAPDefectNotificationUploadError.missingParentNotification
        }

        let ids = identifiers(for: workItem.id)
        let output = try SAPI2NotificationUploadBuilder.build(
            requests: [I2NotificationRequest(
                id: ids.notificationID,
                positionID: "",
                // `QMTXT` holds 40 characters.
                shortText: String(defect.shortText.prefix(DefectDraftPayload.maximumShortTextLength)),
                category: category,
                note: defect.longText,
                noteElementID: ""
            )],
            parentNotification: parentNotification,
            template: template,
            parentDocuments: [],
            syncUserID: syncUserID,
            now: now,
            priority: defect.priority.sapPriority
        )

        let client = (output.notifications.first?["MANDT"] ?? nil) ?? ""
        let userID = syncUserID.uppercased()
        let documentColumns = (LegacySQLiteSchema.byName["TO_T0285"]?.columns ?? []).map(\.name)
        let documents = try defect.attachmentIDs.enumerated().map { index, attachmentID in
            guard let data = photoData[attachmentID], !data.isEmpty else {
                throw SAPNotificationReviewUploadError.missingPhoto(attachmentID)
            }
            // The photos keep no capture time; they are ordered after saving.
            let createdAt = workItem.updatedAt.addingTimeInterval(Double(index) / 1000)
            let date = format(createdAt, "yyyyMMdd")
            let time = format(createdAt, "HHmmss")
            var metadata = Dictionary(uniqueKeysWithValues: documentColumns.map { ($0, "") })
            metadata.merge([
                "MANDT": client, "VORGANGSNR": ids.processID,
                "DOCID": documentID(ids.processID, attachmentID: attachmentID),
                "QMNUM": ids.notificationID,
                "CREATEDBY": userID, "CREATEDDATE": date, "CREATEDTIME": time,
                "MODIFIEDDATE": date, "MODIFIEDTIME": time, "MODIFIEDBY": userID,
                "DOC_TYPE": "JPG", "DOC_MIMETYPE": "image/jpeg",
                "NAME": "Foto_\(format(createdAt, "dd_MM_yyyy_HH_mm_ss_SSS"))",
                "DOKAR": "FMD", "DOKOB": "SMQMEL", "OBJKY": ids.notificationID,
                "DMS_CONTENTTYPE": SAPI2NotificationUploadBuilder.documentClass,
                "DMS_DOCID": SAPI2NotificationUploadBuilder.documentValueList
            ]) { _, value in value }
            return SAPNotificationOutgoingDocument(metadata: metadata, data: data)
        }

        var batch = SAPNotificationOutgoingBatch(
            workItemIDs: [workItem.id], attachmentIDs: defect.attachmentIDs,
            processIDs: [ids.processID], equipmentIDs: [],
            headers: [], values: [], documents: [], equipment: []
        )
        batch.i2Notifications = output.notifications
        batch.i2Documents = documents
        return batch
    }

    /// Stable per photo, so a retried upload sends the same document.
    private static func documentID(_ processID: String, attachmentID: String) -> String {
        SHA256.hash(data: Data("\(processID)|\(attachmentID)".utf8))
            .map { String(format: "%02X", $0) }
            .joined()
            .prefix(32)
            .description
    }

    private static func format(_ date: Date, _ pattern: String) -> String {
        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = pattern
        return formatter.string(from: date)
    }
}
