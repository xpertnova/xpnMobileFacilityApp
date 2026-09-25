import Foundation
import Observation

/// A defective position offered for an I2 notification after its form closes.
///
/// One row of the legacy `DefectPosItem` dialog. It is built by the form's
/// view model, because each form stores results, actions and comments in its
/// own shape.
struct I2DefectCandidate: Identifiable, Equatable, Sendable {
    /// Checklist position ID.
    let id: String
    let number: Int
    let title: String
    let resultCode: String
    let resultText: String
    let actionCode: String
    let actionText: String
    /// Comment plus the `HEADERTEXT` line, exactly what the I2 long text gets.
    let note: String
    let noteElementID: String

    init(
        id: String,
        number: Int,
        title: String,
        resultCode: String,
        resultText: String,
        actionCode: String = "",
        actionText: String = "",
        note: String,
        noteElementID: String
    ) {
        self.id = id
        self.number = number
        self.title = title
        self.resultCode = resultCode
        self.resultText = resultText
        self.actionCode = actionCode
        self.actionText = actionText
        self.note = note
        self.noteElementID = noteElementID
    }
}

/// The I2 (`Störungsmeldung`) rules shared by every inspection form.
///
/// Traced from the legacy Cordova client: candidate collection in
/// `WartungsPlan`/`Rundgang.setValue4Process` and
/// `HeaderFormBuilder.setValue4Process`, the row build in
/// `edata/insert.js insertI2Meldung`, and the per-position lookup in
/// `BaseFormController._hasI2Meldung4Position` / `_getI2Meldung4Position`.
enum I2NotificationRules {
    static let codeGroup = "ZPMI0001"
    static let priority = "3"
    static let userStatus = "MTFM"
    /// `defectPos.noteValue.trim().substring(0, 300)`.
    static let maximumLongTextLength = 300
    /// `getLongTextArray` splits the long text into `TDLINE`s of this size.
    static let longTextLineLength = 128
    static let headerTextMarker = "HEADERTEXT:"

    // MARK: - Candidates

    /// The comment the I2 carries. Positions below a `HEADER` row get the
    /// header appended so the lookup can tell identical position texts in
    /// different groups apart.
    static func note(comment: String, headerText: String?) -> String {
        guard let headerText, !headerText.isEmpty else { return comment }
        return comment + "\n- \(headerTextMarker) " + headerText
    }

    /// The `LTXA1` of the last `DNAME == "HEADER"` plan row before the
    /// position's operation, the way the legacy candidate loop reads it.
    static func headerText(operation: String, planRows: [[String: Any]]) -> String? {
        var header: String?
        for row in planRows {
            guard string(named: "VORNR", in: row) != operation else { break }
            if string(named: "DNAME", in: row) == "HEADER" {
                header = string(named: "LTXA1", in: row)
            }
        }
        guard let header, !header.isEmpty else { return nil }
        return header
    }

    /// Resolves the header from the plan rows, or falls back to the checklist
    /// group when the payload is not available (a form reopened from its
    /// offline snapshot carries no `T_PLPOD`).
    static func headerText(operation: String, planRows: [[String: Any]], groupTitle: String) -> String? {
        guard !planRows.isEmpty else { return groupTitle.isEmpty ? nil : groupTitle }
        return headerText(operation: operation, planRows: planRows)
    }

    /// Candidates of a segmented yes/no form (TFM1 Wartungsplan, TFM3
    /// Rundgang): every position answered "Ja" (`X`).
    static func segmentedCandidates(
        detail: SAPNotificationDetail,
        results: [String: NotificationReviewResult],
        comments: [String: String]
    ) -> [I2DefectCandidate] {
        let rows = planRows(rawPayloadJSON: detail.summary.rawPayloadJSON)
        return detail.inspectionItems.enumerated().compactMap { index, item in
            guard !item.isMeasuringPointEntry, results[item.id] == .yes else { return nil }
            let header = headerText(
                operation: operation(fromElementID: item.resultElementID),
                planRows: rows,
                groupTitle: item.groupTitle
            )
            return I2DefectCandidate(
                id: item.id,
                number: index + 1,
                title: item.title,
                resultCode: InspectionFormRules.segmentedDefectCode,
                resultText: String(localized: "notifications.detail.result.yes"),
                note: note(comment: comments[item.id, default: ""], headerText: header),
                noteElementID: item.commentElementID
            )
        }
    }

    /// The operation (`VORNR`) of an element ID such as `TFM1-0010-1`.
    static func operation(fromElementID elementID: String) -> String {
        let parts = elementID.split(separator: "-", omittingEmptySubsequences: false)
        return parts.count > 1 ? String(parts[1]) : ""
    }

    // MARK: - Requests

    /// Only positions the technician gave a real category become requests.
    static func requests(
        from candidates: [I2DefectCandidate],
        categories: [String: I2NotificationCategory],
        makeID: () -> String = makeTemporaryNotificationID
    ) -> [I2NotificationRequest] {
        candidates.compactMap { candidate in
            guard let category = categories[candidate.id], category.createsNotification else { return nil }
            return I2NotificationRequest(
                id: makeID(),
                positionID: candidate.id,
                shortText: candidate.title,
                category: category,
                note: candidate.note,
                noteElementID: candidate.noteElementID
            )
        }
    }

    /// `nBpmUtil.randomId(8, "NEU")`.
    static func makeTemporaryNotificationID() -> String {
        let alphabet = Array("0A1B2C3D4E5F6879")
        return "NEU-" + String((0..<8).compactMap { _ in alphabet.randomElement() })
    }

    // MARK: - Long text

    /// `getLongTextArray(noteValue.trim().substring(0, 300))`, or no lines
    /// when the note is blank.
    static func longTextLines(for note: String) -> [String] {
        let trimmed = note.trimmingCharacters(in: .whitespacesAndNewlines) as NSString
        guard trimmed.length > 0 else { return [] }
        let limited = trimmed.substring(to: min(trimmed.length, maximumLongTextLength))
        return splitToLength(limited, length: longTextLineLength)
    }

    /// Port of the legacy `splitStringToLength`: split before every blank that
    /// precedes a word character, then pack the pieces into lines that stay
    /// below `length` UTF-16 units.
    static func splitToLength(_ text: String, length: Int) -> [String] {
        let pieces = wordPieces(text)
        var lines: [String] = []
        var sentence = ""
        for piece in pieces {
            sentence += piece
            if (sentence as NSString).length >= length {
                let range = (sentence as NSString).range(of: piece, options: .backwards)
                sentence = (sentence as NSString).substring(to: range.location)
                lines.append(sentence)
                sentence = piece
            }
        }
        lines.append(sentence)
        return lines
    }

    /// `str.split(/(?=\s\b)/g)` with JavaScript's ASCII word boundary.
    private static func wordPieces(_ text: String) -> [String] {
        let units = Array(text.utf16)
        var pieces: [String] = []
        var start = 0
        for index in units.indices where index > start && index + 1 < units.count {
            guard isWhitespace(units[index]), isWordCharacter(units[index + 1]) else { continue }
            pieces.append(String(utf16CodeUnits: Array(units[start..<index]), count: index - start))
            start = index
        }
        pieces.append(String(utf16CodeUnits: Array(units[start...]), count: units.count - start))
        return pieces
    }

    private static func isWhitespace(_ unit: UInt16) -> Bool {
        guard let scalar = Unicode.Scalar(unit) else { return false }
        return scalar.properties.isWhitespace
    }

    private static func isWordCharacter(_ unit: UInt16) -> Bool {
        switch unit {
        case 0x30...0x39, 0x41...0x5A, 0x61...0x7A, 0x5F: true
        default: false
        }
    }

    // MARK: - Existing notifications

    /// The downloaded I2s that belong to one checklist position.
    ///
    /// A notification matches when its `QMTXT` contains the position text. The
    /// segmented forms additionally compare the `HEADERTEXT` line against the
    /// position's group, so a text repeated under several headers only shows
    /// the faults of its own group.
    static func notifications(
        _ notifications: [SAPI2NotificationSummary],
        forPositionTitle title: String,
        groupTitle: String,
        matchesGroupHeader: Bool
    ) -> [SAPI2NotificationSummary] {
        guard !title.isEmpty else { return [] }
        return notifications.filter { notification in
            guard notification.shortText.contains(title) else { return false }
            guard matchesGroupHeader, notification.longText.contains(headerTextMarker) else { return true }
            guard !groupTitle.isEmpty,
                  let range = notification.longText.range(of: groupTitle),
                  range.lowerBound > notification.longText.startIndex
            else { return false }
            return notification.longText[notification.longText.index(before: range.lowerBound)] == " "
        }
    }

    /// `onI2MeldungPositionPress` starts a new line before every `*` that
    /// does not open the text.
    static func displayLongText(_ longText: String) -> String {
        longText.replacingOccurrences(of: "(?!^)\\*", with: "\n*", options: .regularExpression)
    }

    // MARK: - Payload

    /// `T_PLPOD` of a cached notification payload, decoding `FELDWERT` when
    /// the payload predates the expanded cache format.
    static func planRows(rawPayloadJSON: String) -> [[String: Any]] {
        guard let data = rawPayloadJSON.data(using: .utf8),
              var payload = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any]
        else { return [] }
        if value(named: "T_PLPOD", in: payload) == nil,
           let feldwert = value(named: "FELDWERT", in: payload) as? String,
           let decoded = SAPLegacyDataExchangeCodec.cachedNotificationPayload(fromFeldwert: feldwert) {
            payload.merge(decoded) { _, decodedValue in decodedValue }
        }
        return value(named: "T_PLPOD", in: payload) as? [[String: Any]] ?? []
    }

    private static func value(named key: String, in dictionary: [String: Any]) -> Any? {
        dictionary.first { $0.key.caseInsensitiveCompare(key) == .orderedSame }?.value
    }

    private static func string(named key: String, in dictionary: [String: Any]) -> String {
        switch value(named: key, in: dictionary) {
        case let value as String: value
        case let value as NSNumber: value.stringValue
        default: ""
        }
    }
}

/// State of the "Mangelbehaftete Positionen" dialog, shared by every form.
@MainActor
@Observable
final class I2DefectSelection {
    private(set) var candidates: [I2DefectCandidate] = []
    private var categories: [String: I2NotificationCategory] = [:]
    var isPresented = false

    /// Opens the dialog with every category on "I2 nicht anlegen". Returns
    /// `false` when there is nothing to offer.
    @discardableResult
    func present(_ candidates: [I2DefectCandidate]) -> Bool {
        guard !candidates.isEmpty else { return false }
        self.candidates = candidates
        categories = [:]
        isPresented = true
        return true
    }

    func category(for candidateID: String) -> I2NotificationCategory {
        categories[candidateID] ?? .notCreated
    }

    func setCategory(_ category: I2NotificationCategory, for candidateID: String) {
        categories[candidateID] = category
    }

    /// Closes the dialog and returns the notifications to create.
    func accept() -> [I2NotificationRequest] {
        let requests = I2NotificationRules.requests(from: candidates, categories: categories)
        reset()
        return requests
    }

    func cancel() {
        reset()
    }

    private func reset() {
        isPresented = false
        candidates = []
        categories = [:]
    }
}
