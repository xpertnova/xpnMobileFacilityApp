import Foundation
import XCTest
@testable import mobileFacilityApp

/// Rundgang `MEASURE` rows and the measuring points behind them, traced from
/// `Rundgang.controller.js` and `MeasurePoints.controller.js`.
final class MeasuringPointTests: XCTestCase {
    // MARK: - Notification rows

    func testMeasureRowBecomesReadingEntryWithItsButtonTitle() throws {
        let detail = SAPNotificationDetail(summary: try makeSummary())

        XCTAssertEqual(detail.inspectionItems.map(\.isMeasuringPointEntry), [false, true])
        let measure = try XCTUnwrap(detail.inspectionItems.last)
        XCTAssertEqual(measure.measuringPointButtonTitle, "Messpunkt")
        XCTAssertEqual(measure.resultElementID, "TFM3-0160-1-")
        XCTAssertEqual(measure.commentElementID, "TFM3-0160-9B")
    }

    func testSnapshotKeepsTheReadingEntry() throws {
        let detail = SAPNotificationDetail(summary: try makeSummary())
        let snapshot = OfflineNotificationSnapshot(detail: detail)
        let decoded = try JSONDecoder().decode(
            OfflineNotificationSnapshot.self,
            from: JSONEncoder().encode(snapshot)
        )
        let reopened = SAPNotificationDetail(offlineSnapshot: decoded, notificationID: detail.summary.id)

        XCTAssertEqual(reopened.inspectionItems.last?.measuringPointButtonTitle, "Messpunkt")
    }

    func testFormRowOpensMeasuringPointsOnlyWhenPointsExist() throws {
        let measure = try XCTUnwrap(SAPNotificationDetail(summary: try makeSummary()).inspectionItems.last)

        let available = measure.inspectionFormItem(number: 2, measuringPoints: .available)
        XCTAssertFalse(available.requiresResult)
        XCTAssertTrue(available.resultOptions.isEmpty)
        XCTAssertEqual(available.measuringPoint, InspectionFormMeasuringPoint(buttonTitle: "Messpunkt", unavailableReasonKey: nil))

        let none = measure.inspectionFormItem(number: 2, measuringPoints: .none)
        XCTAssertEqual(none.measuringPoint?.unavailableReasonKey, "measuringPoints.row.none")

        // A form that does not pass availability keeps the old result row.
        XCTAssertNil(measure.inspectionFormItem(number: 2).measuringPoint)
    }

    @MainActor
    func testReviewClosesWithoutAnAnswerForTheMeasureRow() async throws {
        let detail = SAPNotificationDetail(summary: try makeSummary())
        let model = NotificationReviewViewModel(
            detail: detail,
            offlineWorkStore: OfflineWorkStore(repository: InMemoryOfflineWorkRepository(), workerID: "S50828"),
            photoStore: InMemoryPhotoAttachmentStore(),
            sapDataStore: makeDataStore(points: [makePoint()])
        )
        await model.load()
        XCTAssertTrue(model.hasMeasuringPoints)
        XCTAssertFalse(model.canClose)

        model.markEverythingOkay()

        XCTAssertTrue(model.canClose)
        XCTAssertNil(model.results[detail.inspectionItems[1].id])
    }

    @MainActor
    func testReadingsAreQueuedForSAPApartFromTheForm() async throws {
        let detail = SAPNotificationDetail(summary: try makeSummary())
        let workStore = OfflineWorkStore(repository: InMemoryOfflineWorkRepository(), workerID: "S50828")
        let model = NotificationReviewViewModel(
            detail: detail,
            offlineWorkStore: workStore,
            photoStore: InMemoryPhotoAttachmentStore(),
            sapDataStore: makeDataStore(points: [makePoint()])
        )
        await model.load()
        let reading = MeasuringPointReadingEntry(
            client: "100", pointID: "000000000134", unit: "KWH",
            value: Decimal(string: "1234.5")!, text: "Zähler getauscht",
            recordedAt: Date(timeIntervalSince1970: 1_790_000_000)
        )

        let saved = await model.saveMeterReadings([reading])

        XCTAssertTrue(saved)
        // The form itself stays unsaved; the reading is its own queued work.
        XCTAssertNil(workStore.notificationReview(notificationID: detail.summary.id))
        let item = try XCTUnwrap(workStore.meterReadingItems.first)
        XCTAssertEqual(item.status, .pendingSynchronization)
        XCTAssertEqual(item.payload.meterReading?.meter.technicalPlaceID, "D1-HAM-40012-02")
        XCTAssertEqual(item.payload.meterReading?.meter.client, "100")
        XCTAssertEqual(model.meterReadings, [reading])

        // Clearing the value removes the queued reading again.
        _ = await model.saveMeterReadings([])
        XCTAssertTrue(workStore.meterReadingItems.isEmpty)
    }

    // MARK: - TO_T0286

    func testUploadBuildsOneRowPerPlaceLikeUpdateMeasurementDocument() throws {
        let recordedAt = try XCTUnwrap(Calendar(identifier: .gregorian).date(
            from: DateComponents(year: 2026, month: 9, day: 24, hour: 14, minute: 5, second: 9)
        ))
        let items = [
            makeReadingItem(pointID: "000000000134", value: "1234.5", note: "Zähler getauscht", at: recordedAt),
            makeReadingItem(pointID: "000000000135", value: "88", note: "", at: recordedAt),
            makeReadingItem(pointID: "000000000136", location: "D1-HAM-40013-02", value: "1", note: "", at: recordedAt)
        ]

        let output = try SAPMeterReadingUploadBuilder.build(items: items, syncUserID: "s50828")

        XCTAssertEqual(Set(output.workItemIDs), Set(items.map(\.id)))
        XCTAssertEqual(output.rows.count, 2)
        let row = try XCTUnwrap(output.rows.first { $0["STRNO"] == "D1-HAM-40012-02" })
        XCTAssertEqual(row["MANDT"], "100")
        XCTAssertEqual(row["STRNO"], "D1-HAM-40012-02")
        XCTAssertEqual(row["EQUNR"], "")
        XCTAssertEqual(row["REQID"], "")
        let parameters = SAPLegacyDataExchangeCodec.decodedFeldwertObjects(try XCTUnwrap(row["MEASURMENT_BELEG"] ?? nil))
        XCTAssertEqual(parameters.count, 2)
        let first = try XCTUnwrap(parameters.first { $0["PARAMETER2"] as? String == "134" })
        XCTAssertEqual(first["PARAMETER1"] as? String, "100")
        XCTAssertEqual(first["PARAMETER2"] as? String, "134")
        XCTAssertEqual(first["PARAMETER3"] as? String, "20260924")
        XCTAssertEqual(first["PARAMETER4"] as? String, "140509")
        XCTAssertEqual(first["PARAMETER5"] as? String, "Zähler getauscht")
        XCTAssertEqual(first["PARAMETER6"] as? String, "S50828")
        XCTAssertEqual((first["PARAMETER7"] as? NSNumber)?.decimalValue, Decimal(string: "1234.5"))
        XCTAssertEqual(first["PARAMETER8"] as? String, "")
    }

    func testReadingWithoutSAPPointIsNotSent() throws {
        var item = makeReadingItem(pointID: "MP-E-1001", value: "1", note: "", at: .now)
        if case var .meterReading(payload) = item.payload {
            payload.meter.client = nil
            item = OfflineWorkItem(
                id: item.id, workerID: item.workerID, type: .meterReading, status: .pendingSynchronization,
                payload: .meterReading(payload), createdAt: item.createdAt, updatedAt: item.updatedAt, syncError: nil
            )
        }

        let output = try SAPMeterReadingUploadBuilder.build(items: [item], syncUserID: "S50828")

        XCTAssertTrue(output.rows.isEmpty)
        XCTAssertTrue(output.workItemIDs.isEmpty)
    }

    func testMeterKindFollowsTheSortField() {
        XCTAssertEqual(MeterKind(position: "STROM3", unit: "KWH"), .electricity)
        XCTAssertEqual(MeterKind(position: "WASSER", unit: "M3"), .water)
        XCTAssertEqual(MeterKind(position: "GAS", unit: "M3"), .gas)
        XCTAssertEqual(MeterKind(position: "WÄRME", unit: "MWH"), .heat)
        XCTAssertNil(MeterKind(position: "", unit: "M3"))
    }

    // MARK: - Measuring points

    func testPointsTakeTheirHistoryByNumericPoint() {
        let points = SAPMeasuringPoint.points(
            fromPointObjects: [
                [
                    "MANDT": "100", "POINT": "000000000134", "PSORT": "STROM1",
                    "PTTXT": "1333050   Betriebshof Bergedorf", "MRNGU": "KWH", "DECIM": 2
                ],
                ["MANDT": "100", "POINT": "000000000135", "PSORT": "WASSER", "PTTXT": "226344", "MRNGU": "M3", "DECIM": 2]
            ],
            historyObjects: [
                ["POINT": 134, "RECDV": 1500.25, "RECDU": "KWH", "IDATE": "20260901", "ITIME": "101500", "READR": "S50828"]
            ]
        )

        XCTAssertEqual(points.map(\.displayNumber), ["134", "135"])
        XCTAssertEqual(points[0].description, "1333050   Betriebshof Bergedorf")
        XCTAssertEqual(points[0].lastReading?.value, Decimal(string: "1500.25"))
        XCTAssertEqual(points[0].minimumValue, Decimal(string: "1500.25"))
        XCTAssertNil(points[1].lastReading)
        XCTAssertEqual(points[1].minimumValue, 0)
    }

    func testValidationFollowsTheLegacyEditDialog() {
        let point = makePoint(lastValue: Decimal(string: "100.5"))

        XCTAssertEqual(point.validationIssue(for: Decimal(string: "100.4")!), .belowLastReading)
        XCTAssertNil(point.validationIssue(for: Decimal(string: "100.5")!))
        XCTAssertNil(point.validationIssue(for: Decimal(string: "120.25")!))
        XCTAssertEqual(point.validationIssue(for: Decimal(string: "120.255")!), .tooManyDecimals)
        // Without a history, the legacy check compares with 0.
        XCTAssertEqual(makePoint().validationIssue(for: -1), .belowLastReading)
        XCTAssertNil(makePoint().validationIssue(for: 0))
    }

    func testDraftReadsGermanDecimalInput() {
        var draft = MeasuringPointDraft(reading: nil)
        XCTAssertEqual(draft.state(for: makePoint()), .empty)

        draft.valueText = "1234,56"
        XCTAssertEqual(draft.state(for: makePoint()), .valid(Decimal(string: "1234.56")!))

        draft.valueText = "12"
        XCTAssertEqual(draft.state(for: makePoint(lastValue: 13)), .invalid(.belowLastReading))
    }

    @MainActor
    func testRepositoryFindsNoPointsForAnUnknownPlace() async throws {
        let store = makeDataStore(points: [makePoint()])
        let detail = SAPNotificationDetail(summary: try makeSummary(functionalLocationID: "D1-HAM-40013-03"))

        let points = await store.loadMeasuringPoints(for: detail)

        XCTAssertEqual(points, [])
    }

    // MARK: - Fixtures

    private func makeReadingItem(
        pointID: String,
        location: String = "D1-HAM-40012-02",
        value: String,
        note: String,
        at date: Date
    ) -> OfflineWorkItem {
        let point = SAPMeasuringPoint(
            client: "100", pointID: pointID, position: "STROM1", description: "", unit: "KWH",
            decimals: 2, lastReading: nil
        )
        return OfflineWorkItem(
            id: UUID(), workerID: "S50828", type: .meterReading, status: .pendingSynchronization,
            payload: .meterReading(MeterReadingDraftPayload(
                meter: MeterReference(point: point, locationID: location),
                value: Decimal(string: value)!, note: note, recordedAt: date
            )),
            createdAt: date, updatedAt: date, syncError: nil
        )
    }

    private func makePoint(lastValue: Decimal? = nil) -> SAPMeasuringPoint {
        SAPMeasuringPoint(
            client: "100", pointID: "000000000134", position: "STROM1",
            description: "1333050   Betriebshof Bergedorf", unit: "KWH", decimals: 2,
            lastReading: lastValue.map {
                SAPMeasuringPointHistory(value: $0, unit: "KWH", date: "20260901", time: "101500", reader: "", text: "")
            }
        )
    }

    @MainActor
    private func makeDataStore(points: [SAPMeasuringPoint]) -> SAPDataStore {
        SAPDataStore(
            repository: InMemorySAPDataCacheRepository(
                seed: SAPCachedData(notifications: [], workerProfile: nil, metadata: nil),
                workerID: "S50828",
                measuringPointsByLocationID: ["D1-HAM-40012-02": points]
            ),
            refreshService: nil,
            localWorkerID: "S50828"
        )
    }

    /// Shaped like notification 005140017014: one position and the
    /// "Zählerstände" `MEASURE` row SAP delivers on plan 00041505.
    private func makeSummary(functionalLocationID: String = "D1-HAM-40012-02") throws -> SAPNotificationSummary {
        let payload: [String: Any] = [
            "MANDT": "100", "QMNUM": "005140017014", "QMART": "I1", "USTXT": "OPEN",
            "STRNO": functionalLocationID, "TPLNR": functionalLocationID, "PLNNR": "00041505",
            "T_PLPOD": [
                ["USR00": "HEADER", "DNAME": "HEADER", "STEUS": "TFM3", "VORNR": "0005", "LTXA1": "Allgemein"],
                [
                    "USR00": "POSITION", "DNAME": "POSITION", "STEUS": "TFM3", "VORNR": "0010",
                    "LTXA1": "Sind die Fenster intakt?",
                    "T_PROPS": [["POSNR": "1", "DFVAL": " ;X"]]
                ],
                [
                    "USR00": "MEASURE", "DNAME": "", "STEUS": "TFM3", "VORNR": "0160",
                    "LTXA1": "Zählerstände",
                    "T_PROPS": [[
                        "POSNR": 1, "DFVAL": "MESSPUNKT", "DFVAL_TXT": "Messpunkt",
                        "DTYPE": "ICON", "DLENG": "1"
                    ]]
                ]
            ]
        ]
        let data = try JSONSerialization.data(withJSONObject: payload, options: [.sortedKeys])
        return SAPNotificationSummary(
            id: "005140017014", client: "100", title: "Rundgang",
            functionalLocationID: functionalLocationID, functionalLocationName: "Betriebshof Bergedorf",
            startDate: "20260924", endDate: "20260924",
            systemStatus: "", userStatus: "OPEN",
            rawPayloadJSON: try XCTUnwrap(String(data: data, encoding: .utf8))
        )
    }
}
