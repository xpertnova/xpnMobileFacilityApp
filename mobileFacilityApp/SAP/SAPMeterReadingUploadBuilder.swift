import Foundation

/// Builds the outgoing `TO_T0286` rows of the meter readings taken on the
/// device.
///
/// Traced from `MeasurePoints.controller.js`:
/// - `onBeforeOpenEdit` fills one `util.datatypes.type4DataParameter` per
///   point: `PARAMETER1` = `MANDT`, `PARAMETER2` = `POINT` without leading
///   zeros, `PARAMETER3` / `PARAMETER4` = date and time of the reading,
///   `PARAMETER5` = text, `PARAMETER6` = user, `PARAMETER8` = unit;
/// - `onPressEditSave` sets `PARAMETER7` to the value as a number;
/// - `_updateMeasurementDocument` keeps the points with a value, clears
///   `PARAMETER8`, and packs them with `getFeldwert` into
///   `MEASURMENT_BELEG` of one row per `MANDT` + `STRNO`;
/// - `inserItemTO_T0286` deletes the place's pending row before inserting,
///   so a place holds one row with every reading of it.
enum SAPMeterReadingUploadBuilder {
    struct Output: Sendable {
        let rows: [LegacySAPRow]
        let workItemIDs: [UUID]
    }

    static func build(
        items: [OfflineWorkItem],
        syncUserID: String
    ) throws -> Output {
        var groups: [String: (client: String, location: String, parameters: [[String: Any]])] = [:]
        var order: [String] = []
        var workItemIDs: [UUID] = []
        let userID = syncUserID.uppercased()

        for item in items.sorted(by: { $0.createdAt < $1.createdAt }) {
            // A reading needs a SAP point: its place and client. Readings of
            // the former preview fixtures have neither and stay on the device
            // instead of being settled unsent.
            guard let reading = item.payload.meterReading,
                  !reading.meter.technicalPlaceID.isEmpty,
                  let client = reading.meter.client, !client.isEmpty else { continue }
            let meter = reading.meter
            let key = "\(client)|\(meter.technicalPlaceID)"
            if groups[key] == nil {
                groups[key] = (client, meter.technicalPlaceID, [])
                order.append(key)
            }
            let recordedAt = reading.recordedAt ?? item.updatedAt
            let parameters: [String: Any] = [
                "PARAMETER1": client,
                "PARAMETER2": pointNumber(meter.id),
                "PARAMETER3": format(recordedAt, "yyyyMMdd"),
                "PARAMETER4": format(recordedAt, "HHmmss"),
                "PARAMETER5": String(reading.note.prefix(MeasuringPointReadingEntry.maximumTextLength)),
                "PARAMETER6": userID,
                "PARAMETER7": NSDecimalNumber(decimal: reading.value),
                "PARAMETER8": "",
                "PARAMETER9": "",
                "PARAMETER10": ""
            ]
            // A later reading of the same point replaces the earlier one, as
            // the legacy screen holds one value per point.
            groups[key]?.parameters.removeAll { ($0["PARAMETER2"] as? String) == parameters["PARAMETER2"] as? String }
            groups[key]?.parameters.append(parameters)
            workItemIDs.append(item.id)
        }

        let rows = try order.compactMap { key -> LegacySAPRow? in
            guard let group = groups[key] else { return nil }
            return [
                "MANDT": group.client,
                "REQID": "",
                "STRNO": group.location,
                "EQUNR": "",
                "MEASURMENT_BELEG": try SAPLegacyDataExchangeCodec.packedFeldwert(group.parameters)
            ]
        }
        return Output(rows: rows, workItemIDs: workItemIDs)
    }

    /// `util.assistmethods.removeZero`.
    static func pointNumber(_ pointID: String) -> String {
        let trimmed = pointID.drop { $0 == "0" }
        return trimmed.isEmpty ? pointID : String(trimmed)
    }

    private static func format(_ date: Date, _ format: String) -> String {
        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = format
        return formatter.string(from: date)
    }
}
