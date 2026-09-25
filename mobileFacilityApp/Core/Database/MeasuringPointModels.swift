import Foundation

/// A measuring point of a technical place, with the last reading SAP holds for
/// it.
///
/// Traced from `MeasurePoints.controller.js _setMeasurementDocument`: the
/// points come from `FROM_T0274.MEASURMENT_POINT` of the notification's
/// `STRNO`, and each point takes the first `MEASURMENT_BELEG` entry whose
/// `POINT` matches numerically (`history.POINT == oPoint.POINT * 1`).
struct SAPMeasuringPoint: Identifiable, Equatable, Sendable {
    /// `MANDT`; posted as `PARAMETER1`.
    let client: String
    /// `POINT` as SAP sends it, zero-padded (`000000000134`).
    let pointID: String
    /// `PSORT`, e.g. `STROM1`, `WASSER`.
    let position: String
    /// `PTTXT`: the meter number and where it hangs.
    let description: String
    /// `MRNGU`, e.g. `KWH`, `M3`.
    let unit: String
    /// `DECIM`: the most fraction digits a reading may have.
    let decimals: Int
    let lastReading: SAPMeasuringPointHistory?

    var id: String { pointID }

    /// `POINT` without its leading zeros, as the legacy table shows it and as
    /// `util.assistmethods.removeZero` posts it in `PARAMETER2`.
    var displayNumber: String {
        let trimmed = pointID.drop { $0 == "0" }
        return trimmed.isEmpty ? pointID : String(trimmed)
    }

    /// `onChangeReadingValue` accepts a value only when it is not below the
    /// last recorded one. Without a history the legacy check compares with an
    /// empty string, which JavaScript reads as `0`.
    var minimumValue: Decimal {
        lastReading?.value ?? 0
    }

    /// Why `value` cannot be saved for this point, or `nil` when it can.
    func validationIssue(for value: Decimal) -> MeasuringPointValidationIssue? {
        if value < minimumValue { return .belowLastReading }
        if value.fractionDigitCount > max(decimals, 0) { return .tooManyDecimals }
        return nil
    }
}

enum MeasuringPointValidationIssue: Equatable, Sendable {
    case belowLastReading
    case tooManyDecimals
}

/// One `MEASURMENT_BELEG` entry. Only the fields the legacy history dialog
/// reads (`aHistoryKeys`) are kept.
struct SAPMeasuringPointHistory: Equatable, Sendable {
    /// `RECDV`: the recorded counter value.
    let value: Decimal?
    /// `RECDU`.
    let unit: String
    /// `IDATE` / `ITIME`.
    let date: String
    let time: String
    /// `READR`.
    let reader: String
    /// `MDTXT`.
    let text: String
}

/// Narrow read of the measuring points the SAP package delivered for a
/// technical place (`select.getMeasuringPoints`).
protocol MeasuringPointProviding: Sendable {
    func loadMeasuringPoints(functionalLocationID: String) async throws -> [SAPMeasuringPoint]
    /// Every place's points, keyed by `STRNO`, for readings taken outside a
    /// Rundgang.
    func loadAllMeasuringPoints() async throws -> [String: [SAPMeasuringPoint]]
}

/// A reading the technician entered on the measuring-point screen.
///
/// It holds what `onBeforeOpenEdit` and `onPressEditSave` put into the
/// legacy `oData` row: the point, the value, the optional text and the moment
/// it was taken. The `TO_T0286` row is built from these at synchronization.
struct MeasuringPointReadingEntry: Codable, Equatable, Identifiable, Sendable {
    let client: String
    let pointID: String
    let unit: String
    let value: Decimal
    /// `PARAMETER5`, at most `maximumTextLength` characters.
    let text: String
    let recordedAt: Date

    var id: String { pointID }

    /// `maxLength="40"` of the legacy text area.
    static let maximumTextLength = 40
}

extension SAPMeasuringPoint {
    /// Builds the points of one `FROM_T0274` row from its decoded
    /// `MEASURMENT_POINT` and `MEASURMENT_BELEG` arrays.
    static func points(
        fromPointObjects pointObjects: [[String: Any]],
        historyObjects: [[String: Any]]
    ) -> [SAPMeasuringPoint] {
        pointObjects.compactMap { object in
            let pointID = string("POINT", in: object)
            guard !pointID.isEmpty else { return nil }
            let number = numericPoint(pointID)
            let history = historyObjects.first { entry in
                let entryPoint = string("POINT", in: entry)
                return numericPoint(entryPoint) == number && !entryPoint.isEmpty
            }
            return SAPMeasuringPoint(
                client: string("MANDT", in: object),
                pointID: pointID,
                position: string("PSORT", in: object),
                description: string("PTTXT", in: object),
                unit: string("MRNGU", in: object),
                decimals: Int(string("DECIM", in: object)) ?? 0,
                lastReading: history.map { entry in
                    SAPMeasuringPointHistory(
                        value: decimal("RECDV", in: entry),
                        unit: string("RECDU", in: entry),
                        date: string("IDATE", in: entry),
                        time: string("ITIME", in: entry),
                        reader: string("READR", in: entry),
                        text: string("MDTXT", in: entry)
                    )
                }
            )
        }
    }

    private static func numericPoint(_ value: String) -> String {
        let trimmed = value.trimmingCharacters(in: .whitespaces).drop { $0 == "0" }
        return String(trimmed)
    }

    private static func string(_ key: String, in object: [String: Any]) -> String {
        switch object[key] {
        case let string as String: string.trimmingCharacters(in: .whitespaces)
        case let number as NSNumber: number.stringValue
        default: ""
        }
    }

    private static func decimal(_ key: String, in object: [String: Any]) -> Decimal? {
        switch object[key] {
        case let number as NSNumber:
            return Decimal(string: number.stringValue, locale: Locale(identifier: "en_US_POSIX"))
        case let string as String:
            let trimmed = string.trimmingCharacters(in: .whitespaces)
            guard !trimmed.isEmpty else { return nil }
            return Decimal(string: trimmed, locale: Locale(identifier: "en_US_POSIX"))
        default:
            return nil
        }
    }
}

extension Decimal {
    /// Digits after the decimal separator, ignoring trailing zeros.
    var fractionDigitCount: Int {
        var value = self
        var rounded = Decimal()
        var digits = 0
        while digits < 38 {
            NSDecimalRound(&rounded, &value, digits, .plain)
            if rounded == value { return digits }
            digits += 1
        }
        return digits
    }
}

extension MeterReference {
    /// A SAP measuring point as the meter a reading work item refers to.
    init(point: SAPMeasuringPoint, locationID: String) {
        self.init(
            id: point.pointID,
            kind: MeterKind(position: point.position, unit: point.unit) ?? .electricity,
            technicalPlaceID: locationID,
            technicalPlaceName: point.description,
            unit: point.unit,
            previousValue: point.minimumValue,
            previousReadingAt: point.lastReading.flatMap { $0.recordedAt },
            client: point.client,
            decimals: point.decimals
        )
    }
}

extension SAPMeasuringPointHistory {
    /// `IDATE` / `ITIME` as a date, when SAP sent them in a known form.
    var recordedAt: Date? {
        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.locale = Locale(identifier: "en_US_POSIX")
        let rawTime = time.replacingOccurrences(of: ":", with: "")
        for (format, value) in [
            ("yyyyMMddHHmmss", date + rawTime),
            ("yyyy-MM-ddHHmmss", date + rawTime),
            ("yyyyMMdd", date),
            ("yyyy-MM-dd", date)
        ] {
            formatter.dateFormat = format
            if let parsed = formatter.date(from: value) { return parsed }
        }
        return nil
    }
}
