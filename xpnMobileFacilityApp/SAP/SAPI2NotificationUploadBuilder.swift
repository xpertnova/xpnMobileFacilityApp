import Foundation

/// Builds the outgoing `TO_T0284` I2 notifications and their `TO_T0285`
/// documents for a closed I1 form.
///
/// Traced from `edata/insert.js insertI2Meldung`:
/// - the notification starts from the `FROM_T0268` `MELDUNG` template, whose
///   keys are filled from the parent `FROM_T0271` row (`objectAssign` only
///   copies keys the target already has);
/// - it is then overridden to an I2 referencing the parent (`REFNUM`) with
///   priority 3, code group `ZPMI0001`, the chosen category as `QMCOD`, the
///   position text as `QMTXT` and the note as `T_LTXT_QM`;
/// - the whole object is packed into `FELDWERT`, and the table columns take the
///   values of the same names;
/// - every document of the parent stored under the position note is copied
///   with the I2 `QMNUM` and document class `D_TFM_AllgemeineDokumente` /
///   `TFM009`. Everything else, including `DOCID` and `OBJKY`, stays as it was.
enum SAPI2NotificationUploadBuilder {
    static let documentClass = "D_TFM_AllgemeineDokumente"
    static let documentValueList = "TFM009"

    struct Output: Sendable {
        let notifications: [LegacySAPRow]
        let documents: [SAPNotificationOutgoingDocument]
    }

    static func build(
        requests: [I2NotificationRequest],
        parentNotification: [String: Any],
        template: [String: Any]?,
        parentDocuments: [SAPNotificationOutgoingDocument],
        syncUserID: String,
        now: Date = .now,
        priority: String = I2NotificationRules.priority
    ) throws -> Output {
        guard !requests.isEmpty else { return Output(notifications: [], documents: []) }

        let parentID = string(named: "QMNUM", in: parentNotification)
        let functionalLocation = string(named: "STRNO", in: parentNotification)
        guard !parentID.isEmpty else { throw SAPNotificationReviewUploadError.invalidReview(parentID) }

        let columns = (LegacySQLiteSchema.byName["TO_T0284"]?.columns ?? []).map(\.name)
        let columnSet = Set(columns)
        // `mtfmMeldung`: the parent row's own columns. A column the cached row
        // does not carry was `NULL` there, which `objectAssign` skips, so it is
        // left out rather than blanked. `FELDWERT` and `REQID` are replaced
        // below and at staging.
        var parentRow: [String: String] = [:]
        for column in columns where column != "FELDWERT" {
            switch value(named: column, in: parentNotification) {
            case let string as String: parentRow[column] = string
            case let number as NSNumber: parentRow[column] = number.stringValue
            default: break
            }
        }
        parentRow["REQID"] = ""

        // `resultQmel`: the template filled from the parent. Without a cached
        // template the parent row itself is the only shape we know.
        var base: [String: Any]
        if let template {
            base = template
            // The decoded parent value keeps its JSON type (`TPWEH` is a
            // number there), as `objectAssign` copies it.
            for key in template.keys where columnSet.contains(key) {
                guard let value = parentRow[key] else { continue }
                switch self.value(named: key, in: parentNotification) {
                case let number as NSNumber: base[key] = number
                default: base[key] = value
                }
            }
        } else {
            base = parentRow
        }

        let userID = syncUserID.uppercased()
        base["REFNUM"] = parentID
        base["QMART"] = "I2"
        base["PRIOK"] = priority
        base["QMGRP"] = I2NotificationRules.codeGroup
        base["TPLNR"] = functionalLocation
        base["STRNO"] = functionalLocation
        base["STRMN"] = ""
        base["LTRMN"] = ""
        base["STTXT"] = ""
        base["USTXT"] = I2NotificationRules.userStatus
        base["AEDAT"] = basicDate(now)
        base["AENAM"] = userID
        base["QMNAM"] = userID

        var notifications: [LegacySAPRow] = []
        var documents: [SAPNotificationOutgoingDocument] = []
        for request in requests where request.category.createsNotification {
            var object = base
            object["QMNUM"] = request.id
            object["QMTXT"] = request.shortText
            object["QMCOD"] = request.category.code
            let lines = I2NotificationRules.longTextLines(for: request.note)
            if !lines.isEmpty {
                object["T_LTXT_QM"] = lines.map { ["TDFORMAT": "", "TDLINE": $0] }
            }

            var row: LegacySAPRow = parentRow.mapValues { Optional($0) }
            for (key, value) in object where columnSet.contains(key) && key != "FELDWERT" {
                if let string = value as? String { row[key] = string }
            }
            row["FELDWERT"] = try SAPLegacyDataExchangeCodec.packedFeldwert(object)
            notifications.append(row)

            for document in parentDocuments where document.metadata["ELEMENTNR"] == request.noteElementID {
                var metadata = document.metadata
                metadata["QMNUM"] = request.id
                metadata["DMS_CONTENTTYPE"] = documentClass
                metadata["DMS_DOCID"] = documentValueList
                documents.append(SAPNotificationOutgoingDocument(metadata: metadata, data: document.data))
            }
        }
        return Output(notifications: notifications, documents: documents)
    }

    /// The parent I1 as `insertI2Meldung` sees it: the cached row with its
    /// decoded `FELDWERT` values taking precedence.
    static func parentNotification(from source: SAPNotificationSummary) -> [String: Any]? {
        guard let data = source.rawPayloadJSON.data(using: .utf8),
              var payload = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any]
        else { return nil }
        if value(named: "T_PLPOD", in: payload) == nil,
           let feldwert = value(named: "FELDWERT", in: payload) as? String,
           let decoded = SAPLegacyDataExchangeCodec.cachedNotificationPayload(fromFeldwert: feldwert) {
            payload.merge(decoded) { _, decodedValue in decodedValue }
        }
        if string(named: "QMNUM", in: payload).isEmpty {
            payload["QMNUM"] = source.id
        }
        return payload
    }

    private static func value(named name: String, in dictionary: [String: Any]) -> Any? {
        dictionary[name] ?? dictionary.first { $0.key.caseInsensitiveCompare(name) == .orderedSame }?.value
    }

    private static func string(named name: String, in dictionary: [String: Any]) -> String {
        switch value(named: name, in: dictionary) {
        case let string as String: string
        case let number as NSNumber: number.stringValue
        default: ""
        }
    }

    private static func basicDate(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyyMMdd"
        return formatter.string(from: date)
    }
}
