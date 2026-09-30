import XCTest
@testable import mobileFacilityApp

final class RFIDTagLookupTests: XCTestCase {
    func testFullTagTakesTheLastRowAndLegacyPrefixTheFirst() {
        let assignments = [
            assignment("5E68688B29DB1", location: "FL-OLD-1"),
            assignment("5E68688B29DB1", location: "FL-OLD-2"),
            assignment("AAAA", location: "FL-A-1"),
            assignment("AAAA", location: "FL-A-2")
        ]

        let exact = RFIDTagLookup.assignment(for: "AAAA", in: assignments)
        XCTAssertEqual(exact?.assignment.functionalLocationID, "FL-A-2")
        XCTAssertEqual(exact?.matchedLegacyTagPrefix, false)

        let legacy = RFIDTagLookup.assignment(for: "5E68688B29DB11", in: assignments)
        XCTAssertEqual(legacy?.assignment.functionalLocationID, "FL-OLD-1")
        XCTAssertEqual(legacy?.matchedLegacyTagPrefix, true)

        XCTAssertNil(RFIDTagLookup.assignment(for: "5E68688B29DB", in: assignments))
        XCTAssertNil(RFIDTagLookup.assignment(for: "", in: assignments))
    }

    func testEquipmentFollowsCordovasLikePattern() {
        let notifications = [
            notification("1", location: "FL-1"),
            notification("2", location: "FL-1", equipment: "000000000010000040"),
            notification("3", location: "FL-1", equipment: "000000000010000041"),
            notification("4", location: "FL-2")
        ]

        func ids(equipment: String) -> [String] {
            RFIDTagLookup.notifications(
                notifications,
                matching: assignment("T", location: "FL-1", equipment: equipment)
            ).map(\.id)
        }

        XCTAssertEqual(ids(equipment: ""), ["1", "2", "3"])
        XCTAssertEqual(ids(equipment: "%"), ["1"])
        XCTAssertEqual(ids(equipment: "10000040"), ["2"])
    }

    func testControlKeyFiltersByFirstOperation() {
        let notifications = [
            notification("1", location: "FL-1", payload: #"{"T_PLPOD":[{"STEUS":"TFM3"}]}"#),
            notification("2", location: "FL-1", payload: #"{"T_PLPOD":[{"STEUS":"TFM5"}]}"#)
        ]
        let matches = RFIDTagLookup.notifications(
            notifications,
            matching: assignment("T", location: "FL-1", controlKey: "TFM5")
        )
        XCTAssertEqual(matches.map(\.id), ["2"])
    }

    func testReaderPaddingIsRemoved() {
        XCTAssertEqual(RFIDTagLookup.normalizedTag(" 5E68688B29DB11\0\0\n"), "5E68688B29DB11")
    }

    func testSQLiteResolvesSynchronizedTagAssignments() async throws {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
            .appendingPathExtension("sqlite")
        defer { try? FileManager.default.removeItem(at: url) }
        let repository = try SQLiteSAPDataCacheRepository(databaseURL: url)
        try await repository.beginIncoming()
        try await repository.appendIncoming(.init(tables: [
            "T_0212": [
                ["MANDT": "100", "RFIDTAG": "AAAA1111BBBB2", "STRNO": "DE-ESS-FL-420", "EQUNR": "EQ-1", "STEUS": ""],
                ["MANDT": "100", "RFIDTAG": "CCCC", "STRNO": "DE-ESS-FL-999", "EQUNR": "%", "STEUS": ""]
            ],
            "T_0271": [
                [
                    "MANDT": "100", "QMNUM": "N-1", "QMART": "I1", "QMTXT": "Pump",
                    "STTXT": "OSNO", "STRNO": "DE-ESS-FL-420", "PLTXT": "Plant", "EQUNR": "EQ-1"
                ],
                [
                    "MANDT": "100", "QMNUM": "N-2", "QMART": "I1", "QMTXT": "Other pump",
                    "STTXT": "OSNO", "STRNO": "DE-ESS-FL-420", "PLTXT": "Plant", "EQUNR": "EQ-2"
                ]
            ]
        ], isLastPackage: true))
        _ = try await repository.commitIncoming(sapWorkerID: "1", refreshedAt: Date())

        let resolution = try await repository.resolveRFIDTag("AAAA1111BBBB2", for: "w1")
        XCTAssertEqual(resolution?.matches.map(\.id), ["N-1"])
        XCTAssertEqual(resolution?.matchedLegacyTagPrefix, false)

        let legacy = try await repository.resolveRFIDTag("AAAA1111BBBB2F", for: "w1")
        XCTAssertEqual(legacy?.matches.map(\.id), ["N-1"])
        XCTAssertEqual(legacy?.matchedLegacyTagPrefix, true)

        let withoutNotifications = try await repository.resolveRFIDTag("CCCC", for: "w1")
        XCTAssertEqual(withoutNotifications?.assignment.functionalLocationID, "DE-ESS-FL-999")
        XCTAssertEqual(withoutNotifications?.matches, [])

        let unknown = try await repository.resolveRFIDTag("UNKNOWN", for: "w1")
        XCTAssertNil(unknown)
    }

    func testCaptureConfigurationRequiresEveryValue() {
        XCTAssertEqual(
            SocketMobileCaptureConfiguration.load(from: ["AppID": "ios:app", "AppKey": "key", "DeveloperID": "dev"]),
            .success(.init(appID: "ios:app", appKey: "key", developerID: "dev"))
        )
        XCTAssertEqual(
            SocketMobileCaptureConfiguration.load(from: ["AppID": "ios:app", "AppKey": " ", "DeveloperID": "dev"]),
            .failure(.missingValue("AppKey"))
        )
    }
}

@MainActor
final class RFIDScanViewModelTests: XCTestCase {
    private let tag = "AAAA1111BBBB22"

    func testReaderTagOpensTheOnlyMatch() async throws {
        let driver = FakeRFIDReaderDriver()
        let reader = RFIDReaderService(driver: driver)
        reader.start()
        driver.pair()
        var openedIDs: [String] = []
        let viewModel = try await makeViewModel(reader: reader, notificationIDs: ["4711"]) { openedIDs.append($0.id) }

        viewModel.startRFIDScan()
        XCTAssertTrue(viewModel.isWaitingForRFIDTag)
        XCTAssertTrue(driver.isReading)

        driver.onEvent?(.tagRead(tag + "\0"))
        XCTAssertFalse(driver.isReading)
        try await waitForLookup(viewModel)

        guard case let .results(lookup) = viewModel.state else {
            return XCTFail("Expected results, got \(viewModel.state)")
        }
        XCTAssertEqual(lookup.matches.map(\.id), ["4711"])
        XCTAssertEqual(openedIDs, ["4711"])
        XCTAssertEqual(viewModel.source, .rfid)
    }

    func testScanNeedsAConnectedReader() async throws {
        let unavailable = try await makeViewModel(
            reader: RFIDReaderService(unavailableReason: "tests"),
            notificationIDs: []
        ) { _ in }
        unavailable.startRFIDScan()
        XCTAssertEqual(unavailable.state, .failure(.rfidReaderUnavailable))

        let searching = RFIDReaderService(driver: FakeRFIDReaderDriver())
        searching.start()
        let disconnected = try await makeViewModel(reader: searching, notificationIDs: []) { _ in }
        disconnected.startRFIDScan()
        XCTAssertEqual(disconnected.state, .failure(.rfidReaderNotConnected))
    }

    func testUnknownTagAndCancelledScan() async throws {
        let driver = FakeRFIDReaderDriver()
        let reader = RFIDReaderService(driver: driver)
        reader.start()
        driver.pair()
        let viewModel = try await makeViewModel(reader: reader, notificationIDs: ["4711"]) { _ in }

        viewModel.startRFIDScan()
        viewModel.cancel()
        XCTAssertEqual(viewModel.state, .idle)
        XCTAssertFalse(driver.isReading)
        driver.onEvent?(.tagRead(tag))
        XCTAssertEqual(viewModel.state, .idle)

        viewModel.lookUpRFIDTag("UNKNOWN")
        try await waitForLookup(viewModel)
        XCTAssertEqual(viewModel.state, .failure(.rfidTagUnknown))
    }

    func testDisconnectStopsReading() {
        let driver = FakeRFIDReaderDriver()
        let reader = RFIDReaderService(driver: driver)
        reader.start()
        driver.pair()
        XCTAssertEqual(reader.status, .connected)
        XCTAssertEqual(reader.devices, [RFIDReaderDevice(id: "fake-1", name: "Fake reader", batteryPercent: 55)])

        XCTAssertTrue(reader.beginReading { _ in })
        driver.onEvent?(.deviceDisconnected(id: "fake-1"))
        XCTAssertEqual(reader.status, .notConnected)
        XCTAssertFalse(reader.isReading)
        XCTAssertFalse(reader.beginReading { _ in })
    }

    func testBluetoothIsRequestedOnStartAndGatesTheReader() async throws {
        let driver = FakeRFIDReaderDriver()
        let bluetooth = FakeBluetoothAccess()
        let reader = RFIDReaderService(driver: driver, bluetooth: bluetooth)
        XCTAssertFalse(bluetooth.didRequest)

        reader.start()
        XCTAssertTrue(bluetooth.didRequest)
        XCTAssertFalse(driver.didOpen)

        bluetooth.report(.denied)
        XCTAssertEqual(reader.status, .bluetoothDenied)
        XCTAssertFalse(driver.didOpen)
        let viewModel = try await makeViewModel(reader: reader, notificationIDs: []) { _ in }
        viewModel.startRFIDScan()
        XCTAssertEqual(viewModel.state, .failure(.bluetoothDenied))

        bluetooth.report(.allowed(isPoweredOn: false))
        XCTAssertEqual(reader.status, .bluetoothOff)
        XCTAssertTrue(driver.didOpen)
        viewModel.startRFIDScan()
        XCTAssertEqual(viewModel.state, .failure(.bluetoothOff))

        bluetooth.report(.allowed(isPoweredOn: true))
        driver.pair()
        XCTAssertTrue(reader.isConnected)
        XCTAssertTrue(reader.beginReading { _ in })

        bluetooth.report(.allowed(isPoweredOn: false))
        XCTAssertFalse(reader.isReading)
    }

    func testManagingReadersFromSettings() {
        let driver = FakeRFIDReaderDriver()
        let reader = RFIDReaderService(driver: driver)
        reader.startDiscovery()
        XCTAssertFalse(driver.didStartDiscovery, "Nothing happens before the reader is set up")

        reader.start()
        reader.startDiscovery()
        XCTAssertTrue(reader.isDiscovering)
        XCTAssertTrue(driver.didStartDiscovery)

        let found = RFIDDiscoveredReader(id: "ble-1", name: "S370")
        driver.onEvent?(.discovered(found))
        driver.onEvent?(.discovered(found))
        XCTAssertEqual(reader.discoveredReaders, [found], "Duplicates are not listed")
        driver.onEvent?(.discoveryEnded)
        XCTAssertFalse(reader.isDiscovering)

        reader.connect(found)
        XCTAssertEqual(reader.connectingReaderIDs, ["ble-1"])
        driver.onEvent?(.connectionEnded(id: "ble-1", error: nil))
        driver.pair(id: "ble-1", name: "S370")
        XCTAssertEqual(reader.connectingReaderIDs, [])
        XCTAssertEqual(reader.discoveredReaders, [])
        XCTAssertEqual(reader.devices.map(\.name), ["S370"])

        XCTAssertFalse(reader.canAddReader, "Only one reader is connected at a time")
        reader.startDiscovery()
        XCTAssertFalse(reader.isDiscovering)
        driver.onEvent?(.discovered(RFIDDiscoveredReader(id: "ble-2", name: "D600")))
        XCTAssertEqual(reader.discoveredReaders, [])
        reader.connect(RFIDDiscoveredReader(id: "ble-2", name: "D600"))
        XCTAssertEqual(driver.connected, [found])

        let device = reader.devices[0]
        reader.remove(device)
        XCTAssertEqual(reader.removingDeviceIDs, ["ble-1"])
        driver.onEvent?(.removalFailed(id: "ble-1", error: "test"))
        XCTAssertEqual(reader.removingDeviceIDs, [])
        XCTAssertTrue(reader.didFailRemoval)
        XCTAssertEqual(reader.devices.count, 1)

        reader.remove(device)
        XCTAssertFalse(reader.didFailRemoval)
        driver.onEvent?(.deviceDisconnected(id: "ble-1"))
        XCTAssertEqual(reader.devices, [])
        XCTAssertEqual(reader.status, .notConnected)
        XCTAssertTrue(reader.canAddReader)
    }

    private func waitForLookup(_ viewModel: ScanViewModel) async throws {
        var attempts = 0
        while viewModel.state == .resolving, attempts < 200 {
            attempts += 1
            try await Task.sleep(for: .milliseconds(5))
        }
    }

    private func makeViewModel(
        reader: RFIDReaderService,
        notificationIDs: [String],
        openSingleMatch: @escaping @MainActor (SAPNotificationSummary) -> Void
    ) async throws -> ScanViewModel {
        let store = SAPDataStore(
            repository: InMemorySAPDataCacheRepository(
                seed: SAPCachedData(
                    notifications: notificationIDs.map { notification($0, location: "FL-1") },
                    workerProfile: nil,
                    metadata: SAPCacheMetadata(sapWorkerID: "w1", lastSuccessfulRefreshAt: Date())
                ),
                workerID: "w1",
                rfidTagAssignments: [assignment(tag, location: "FL-1")]
            ),
            refreshService: nil,
            localWorkerID: "w1"
        )
        await store.loadCachedData()
        return ScanViewModel(sapDataStore: store, rfidReader: reader, isDemoMode: false, openSingleMatch: openSingleMatch)
    }
}

@MainActor
private final class FakeBluetoothAccess: BluetoothAccessChecking {
    private(set) var state: BluetoothAccessState = .unknown
    var onChange: ((BluetoothAccessState) -> Void)?
    private(set) var didRequest = false

    func request() {
        didRequest = true
    }

    func report(_ state: BluetoothAccessState) {
        self.state = state
        onChange?(state)
    }
}

@MainActor
private final class FakeRFIDReaderDriver: RFIDReaderDriver {
    var onEvent: ((RFIDReaderEvent) -> Void)?
    private(set) var isReading = false
    private(set) var didOpen = false
    private(set) var didStartDiscovery = false
    private(set) var connected: [RFIDDiscoveredReader] = []
    private(set) var removed: [RFIDReaderDevice] = []

    func open() {
        didOpen = true
        onEvent?(.ready)
    }

    func pair(id: String = "fake-1", name: String = "Fake reader") {
        onEvent?(.deviceConnected(id: id, name: name))
    }

    func setReading(_ isReading: Bool) {
        self.isReading = isReading
    }

    func requestBatteryLevels() {
        onEvent?(.batteryLevel(id: "fake-1", percent: 55))
    }

    func startDiscovery() {
        didStartDiscovery = true
    }

    func connect(_ reader: RFIDDiscoveredReader) {
        connected.append(reader)
    }

    func remove(_ device: RFIDReaderDevice) {
        removed.append(device)
    }
}

private func assignment(
    _ tag: String,
    location: String,
    equipment: String = "",
    controlKey: String = ""
) -> RFIDTagAssignment {
    RFIDTagAssignment(tag: tag, functionalLocationID: location, equipmentID: equipment, controlKey: controlKey)
}

private func notification(
    _ id: String,
    location: String,
    equipment: String = "",
    payload: String = "{}"
) -> SAPNotificationSummary {
    SAPNotificationSummary(
        id: id, client: "100", title: "Rundgang \(id)",
        functionalLocationID: location, functionalLocationName: "Building A",
        equipmentID: equipment,
        startDate: "2026-09-01", endDate: "2026-09-30",
        systemStatus: "MOFN", userStatus: "",
        rawPayloadJSON: payload
    )
}
