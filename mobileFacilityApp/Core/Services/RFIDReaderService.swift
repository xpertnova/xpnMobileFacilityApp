import Foundation
import Observation
import OSLog

/// A connected reader. Socket Mobile readers stay paired and reconnect on
/// their own until they are removed.
struct RFIDReaderDevice: Identifiable, Equatable, Sendable {
    /// CaptureSDK's device GUID.
    let id: String
    let name: String
    var batteryPercent: Int?
}

/// A Bluetooth LE reader found by a search, not yet connected.
struct RFIDDiscoveredReader: Identifiable, Equatable, Sendable {
    /// CaptureSDK's identifier UUID.
    let id: String
    let name: String
}

/// What a reader SDK reports. Follows CaptureSDK's `CaptureHelper` delegates
/// (Socket Mobile's SingleEntrySwift sample) and Cordova's
/// `DurascanController.swift`.
enum RFIDReaderEvent: Equatable, Sendable {
    /// The SDK is open.
    case ready
    case deviceConnected(id: String, name: String)
    case deviceDisconnected(id: String)
    case batteryLevel(id: String, percent: Int)
    case discovered(RFIDDiscoveredReader)
    case discoveryEnded
    /// A connection attempt to a discovered reader ended; `error` is `nil`
    /// on success, and the reader then also arrives as `.deviceConnected`.
    case connectionEnded(id: String, error: String?)
    /// Removing a connected reader failed; it stays connected.
    case removalFailed(id: String, error: String)
    /// A decoded tag. Drivers deliver tags only while reading is on.
    case tagRead(String)
    case error(String)
}

/// The hardware adapter behind `RFIDReaderService`. Everything that touches a
/// reader SDK lives in an implementation of this protocol, so the lookup, the
/// scan screen and the reader settings work and are testable without hardware.
@MainActor
protocol RFIDReaderDriver: AnyObject {
    /// Called on the main actor.
    var onEvent: ((RFIDReaderEvent) -> Void)? { get set }
    /// Opens the SDK. Paired readers then connect on their own.
    func open()
    /// Cordova's `activateReader` / `deactivateReader`: tags are only
    /// delivered between the two.
    func setReading(_ isReading: Bool)
    func requestBatteryLevels()
    /// Searches for Bluetooth LE readers; results arrive as `.discovered`.
    func startDiscovery()
    /// Shows the system picker for Bluetooth Classic readers (e.g. DuraScan
    /// D600). A chosen reader arrives as `.deviceConnected`.
    func addClassicReader()
    func connect(_ reader: RFIDDiscoveredReader)
    /// Unpairs the reader so it no longer reconnects.
    func remove(_ device: RFIDReaderDevice)
}

enum RFIDReaderStatus: Equatable, Sendable {
    /// This build has no reader SDK or no credentials for it, or the iPad
    /// has no Bluetooth.
    case unavailable
    /// The technician declined Bluetooth access (or it is restricted).
    case bluetoothDenied
    case bluetoothOff
    /// Ready, but no reader is connected.
    case notConnected
    case connected
}

struct RFIDDiagnosticEntry: Identifiable, Equatable, Sendable {
    let id: Int
    let date: Date
    let message: String
    let isError: Bool
}

/// The app's RFID readers: connected and discovered devices, the tag callback
/// of a running scan and a diagnostic log for hardware testing.
@MainActor
@Observable
final class RFIDReaderService {
    static let diagnosticsLimit = 200

    /// `start()` was called: Bluetooth was requested and the SDK opens as
    /// soon as it is allowed.
    private(set) var isStarted = false
    private(set) var devices: [RFIDReaderDevice] = []
    private(set) var discoveredReaders: [RFIDDiscoveredReader] = []
    private(set) var isDiscovering = false
    private(set) var connectingReaderIDs: Set<String> = []
    private(set) var removingDeviceIDs: Set<String> = []
    private(set) var isReading = false
    /// Newest first.
    private(set) var diagnostics: [RFIDDiagnosticEntry] = []
    private var bluetoothState: BluetoothAccessState

    @ObservationIgnored private let driver: (any RFIDReaderDriver)?
    /// `nil` for readers that do not use Bluetooth (demo, tests).
    @ObservationIgnored private let bluetooth: (any BluetoothAccessChecking)?
    private var hasOpenedDriver = false
    @ObservationIgnored private var tagHandler: ((String) -> Void)?
    @ObservationIgnored private var nextDiagnosticID = 0
    @ObservationIgnored private let unavailableReason: String?

    private static let logger = Logger(
        subsystem: Bundle.main.bundleIdentifier ?? "mobileFacilityApp",
        category: "RFID"
    )

    init(driver: any RFIDReaderDriver, bluetooth: (any BluetoothAccessChecking)? = nil) {
        self.driver = driver
        self.bluetooth = bluetooth
        unavailableReason = nil
        bluetoothState = bluetooth?.state ?? .allowed(isPoweredOn: true)
        driver.onEvent = { [weak self] event in self?.handle(event) }
        bluetooth?.onChange = { [weak self] state in self?.bluetoothChanged(to: state) }
    }

    /// A service without hardware; `reason` is logged when it is started.
    init(unavailableReason: String) {
        driver = nil
        bluetooth = nil
        self.unavailableReason = unavailableReason
        bluetoothState = .allowed(isPoweredOn: true)
    }

    var status: RFIDReaderStatus {
        guard driver != nil else { return .unavailable }
        switch bluetoothState {
        case .unsupported: return .unavailable
        case .denied: return .bluetoothDenied
        case .allowed(isPoweredOn: false): return .bluetoothOff
        case .unknown, .allowed(isPoweredOn: true): return devices.isEmpty ? .notConnected : .connected
        }
    }

    var isConnected: Bool {
        status == .connected
    }

    /// Readers can be searched for, connected and removed.
    var canManageReaders: Bool {
        isStarted && hasOpenedDriver && status != .bluetoothOff && status != .bluetoothDenied
    }

    /// Asks for Bluetooth access, which shows the system prompt the first
    /// time, and then opens the reader SDK once. Call it when the technician
    /// turns to RFID, not before. Later calls only refresh battery levels.
    func start() {
        guard !isStarted else {
            if isConnected { driver?.requestBatteryLevels() }
            return
        }
        isStarted = true
        guard driver != nil else {
            record("Reader unavailable: \(unavailableReason ?? "no driver")", isError: true)
            return
        }
        if let bluetooth {
            record("Requesting Bluetooth access")
            bluetooth.request()
        } else {
            openDriverIfAllowed()
        }
    }

    // MARK: - Managing readers

    func startDiscovery() {
        guard canManageReaders, !isDiscovering, let driver else { return }
        discoveredReaders = []
        isDiscovering = true
        record("Searching for Bluetooth LE readers")
        driver.startDiscovery()
    }

    func addClassicReader() {
        guard canManageReaders, let driver else { return }
        record("Opening the Bluetooth Classic reader picker")
        driver.addClassicReader()
    }

    func connect(_ reader: RFIDDiscoveredReader) {
        guard canManageReaders, !connectingReaderIDs.contains(reader.id), let driver else { return }
        connectingReaderIDs.insert(reader.id)
        record("Connecting to \(reader.name)")
        driver.connect(reader)
    }

    func remove(_ device: RFIDReaderDevice) {
        guard canManageReaders, !removingDeviceIDs.contains(device.id), let driver else { return }
        removingDeviceIDs.insert(device.id)
        record("Removing \(device.name)")
        driver.remove(device)
    }

    // MARK: - Reading

    /// Delivers the next tag to `onTag`, once. Returns `false` when no reader
    /// is connected.
    @discardableResult
    func beginReading(onTag: @escaping (String) -> Void) -> Bool {
        guard isConnected, let driver else {
            record("Read requested without a connected reader", isError: true)
            return false
        }
        tagHandler = onTag
        isReading = true
        record("Reading started")
        driver.setReading(true)
        return true
    }

    func endReading() {
        guard isReading else { return }
        tagHandler = nil
        isReading = false
        record("Reading stopped")
        driver?.setReading(false)
    }

    // MARK: - Diagnostics

    func record(_ message: String, isError: Bool = false) {
        if isError {
            Self.logger.error("\(message, privacy: .public)")
        } else {
            Self.logger.info("\(message, privacy: .public)")
        }
        diagnostics.insert(
            RFIDDiagnosticEntry(id: nextDiagnosticID, date: Date(), message: message, isError: isError),
            at: 0
        )
        nextDiagnosticID += 1
        if diagnostics.count > Self.diagnosticsLimit {
            diagnostics.removeLast(diagnostics.count - Self.diagnosticsLimit)
        }
    }

    // MARK: - Events

    private func bluetoothChanged(to state: BluetoothAccessState) {
        guard state != bluetoothState else { return }
        bluetoothState = state
        switch state {
        case .unknown:
            return
        case .unsupported:
            record("Bluetooth is not supported on this device", isError: true)
        case .denied:
            record("Bluetooth access denied", isError: true)
        case .allowed(isPoweredOn: false):
            record("Bluetooth is off", isError: true)
        case .allowed(isPoweredOn: true):
            record("Bluetooth on and allowed")
        }
        if !isConnected {
            endReading()
            isDiscovering = false
            connectingReaderIDs = []
        }
        openDriverIfAllowed()
    }

    private func openDriverIfAllowed() {
        guard isStarted, !hasOpenedDriver, let driver, case .allowed = bluetoothState else { return }
        hasOpenedDriver = true
        record("Opening reader SDK")
        driver.open()
    }

    func handle(_ event: RFIDReaderEvent) {
        switch event {
        case .ready:
            record("Reader SDK ready")
        case let .deviceConnected(id, name):
            record("Reader connected: \(name)")
            if let index = devices.firstIndex(where: { $0.id == id }) {
                devices[index] = RFIDReaderDevice(id: id, name: name, batteryPercent: devices[index].batteryPercent)
            } else {
                devices.append(RFIDReaderDevice(id: id, name: name))
            }
            driver?.requestBatteryLevels()
        case let .deviceDisconnected(id):
            removingDeviceIDs.remove(id)
            guard let index = devices.firstIndex(where: { $0.id == id }) else { return }
            record("Reader disconnected: \(devices[index].name)", isError: true)
            devices.remove(at: index)
            if devices.isEmpty { endReading() }
        case let .batteryLevel(id, percent):
            guard let index = devices.firstIndex(where: { $0.id == id }) else { return }
            devices[index].batteryPercent = percent
            record("Battery \(devices[index].name): \(percent) %")
        case let .discovered(reader):
            guard !discoveredReaders.contains(where: { $0.id == reader.id }),
                  !devices.contains(where: { $0.name == reader.name }) else { return }
            record("Found \(reader.name)")
            discoveredReaders.append(reader)
        case .discoveryEnded:
            record("Search ended: \(discoveredReaders.count) reader(s) found")
            isDiscovering = false
        case let .connectionEnded(id, error):
            connectingReaderIDs.remove(id)
            if let error {
                record("Connection failed: \(error)", isError: true)
            } else {
                discoveredReaders.removeAll { $0.id == id }
            }
        case let .removalFailed(id, error):
            removingDeviceIDs.remove(id)
            record("Removing failed: \(error)", isError: true)
        case let .tagRead(rawTag):
            let tag = RFIDTagLookup.normalizedTag(rawTag)
            guard let handler = tagHandler, !tag.isEmpty else {
                record("Tag ignored (not reading): \(tag)")
                return
            }
            record("Tag read: \(tag)")
            endReading()
            handler(tag)
        case let .error(message):
            record("Reader error: \(message)", isError: true)
        }
    }
}

extension RFIDReaderService {
    static func demo() -> RFIDReaderService {
        RFIDReaderService(driver: DemoRFIDReaderDriver())
    }

    /// Socket Mobile's CaptureSDK when `SocketMobileCapture.plist` ships with
    /// the build; otherwise an unavailable reader.
    static func production() -> RFIDReaderService {
        switch SocketMobileCaptureConfiguration.load() {
        case let .success(configuration):
            return RFIDReaderService(
                driver: SocketMobileRFIDReaderDriver(configuration: configuration),
                bluetooth: CoreBluetoothAccess()
            )
        case let .failure(reason):
            return RFIDReaderService(unavailableReason: reason.description)
        }
    }
}

/// Demo mode's readers: one paired reader, one more to find by searching and
/// one from the Classic picker. Returns the demo tag after a short delay.
/// Never used in production.
@MainActor
final class DemoRFIDReaderDriver: RFIDReaderDriver {
    static let demoTag = "5E68688B29DB11"

    var onEvent: ((RFIDReaderEvent) -> Void)?
    private var tasks: [Task<Void, Never>] = []
    private var readTask: Task<Void, Never>?
    private var batteryByID: [String: Int] = ["demo-d600": 80]

    func open() {
        onEvent?(.ready)
        onEvent?(.deviceConnected(id: "demo-d600", name: "DuraScan D600 (Demo)"))
    }

    func setReading(_ isReading: Bool) {
        readTask?.cancel()
        guard isReading else { return }
        readTask = Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(1_300))
            guard !Task.isCancelled else { return }
            self?.onEvent?(.tagRead(Self.demoTag + "\0\0"))
        }
    }

    func requestBatteryLevels() {
        for (id, percent) in batteryByID {
            onEvent?(.batteryLevel(id: id, percent: percent))
        }
    }

    func startDiscovery() {
        after(milliseconds: 900) { $0.onEvent?(.discovered(RFIDDiscoveredReader(id: "demo-s370", name: "Socket Mobile S370 (Demo)"))) }
        after(milliseconds: 2_500) { $0.onEvent?(.discoveryEnded) }
    }

    func addClassicReader() {
        after(milliseconds: 700) { driver in
            driver.batteryByID["demo-d600-2"] = 45
            driver.onEvent?(.deviceConnected(id: "demo-d600-2", name: "DuraScan D600 #2 (Demo)"))
        }
    }

    func connect(_ reader: RFIDDiscoveredReader) {
        after(milliseconds: 800) { driver in
            driver.batteryByID[reader.id] = 100
            driver.onEvent?(.connectionEnded(id: reader.id, error: nil))
            driver.onEvent?(.deviceConnected(id: reader.id, name: reader.name))
        }
    }

    func remove(_ device: RFIDReaderDevice) {
        after(milliseconds: 400) { driver in
            driver.batteryByID[device.id] = nil
            driver.onEvent?(.deviceDisconnected(id: device.id))
        }
    }

    private func after(milliseconds: Int, _ action: @escaping @MainActor (DemoRFIDReaderDriver) -> Void) {
        tasks.removeAll { $0.isCancelled }
        tasks.append(Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(milliseconds))
            guard !Task.isCancelled, let self else { return }
            action(self)
        })
    }
}
