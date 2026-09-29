import CaptureSDK
import Foundation

/// Credentials for Socket Mobile's CaptureSDK. They are issued per bundle ID
/// on the Socket Mobile developer portal; the Cordova app's keys belong to
/// `de.xpertnova.mtfm.*` and do not work here.
///
/// Read from `SocketMobileCapture.plist` in the app bundle
/// (keys `AppID`, `AppKey`, `DeveloperID`). The file is gitignored.
struct SocketMobileCaptureConfiguration: Equatable, Sendable {
    static let resourceName = "SocketMobileCapture"

    enum LoadError: Error, Equatable, CustomStringConvertible {
        case missingFile
        case missingValue(String)

        var description: String {
            switch self {
            case .missingFile: "\(SocketMobileCaptureConfiguration.resourceName).plist is not in the app bundle"
            case let .missingValue(key): "\(SocketMobileCaptureConfiguration.resourceName).plist has no \(key)"
            }
        }
    }

    let appID: String
    let appKey: String
    let developerID: String

    static func load(from bundle: Bundle = .main) -> Result<Self, LoadError> {
        guard
            let url = bundle.url(forResource: resourceName, withExtension: "plist"),
            let values = NSDictionary(contentsOf: url) as? [String: Any]
        else { return .failure(.missingFile) }
        return load(from: values)
    }

    static func load(from values: [String: Any]) -> Result<Self, LoadError> {
        func value(_ key: String) -> String? {
            let value = (values[key] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines)
            return value?.isEmpty == false ? value : nil
        }
        guard let appID = value("AppID") else { return .failure(.missingValue("AppID")) }
        guard let appKey = value("AppKey") else { return .failure(.missingValue("AppKey")) }
        guard let developerID = value("DeveloperID") else { return .failure(.missingValue("DeveloperID")) }
        return .success(Self(appID: appID, appKey: appKey, developerID: developerID))
    }
}

/// Socket Mobile readers through CaptureSDK 2.x (Swift package), following
/// Socket Mobile's SingleEntrySwift sample and Cordova's
/// `cordova-plugin-xpertnova-rfid/DurascanController.swift`.
///
/// Not verified on hardware yet; see docs/RFID.md.
@MainActor
final class SocketMobileRFIDReaderDriver: RFIDReaderDriver {
    var onEvent: ((RFIDReaderEvent) -> Void)?

    private let configuration: SocketMobileCaptureConfiguration
    private let captureHelper = CaptureHelper.sharedInstance
    private var delegate: CaptureDelegate?
    private var devicesByID: [String: CaptureHelperDevice] = [:]
    private var discoveredByID: [String: SKTCaptureDiscoveredDeviceInfo] = [:]
    private var isReading = false

    init(configuration: SocketMobileCaptureConfiguration) {
        self.configuration = configuration
    }

    func open() {
        guard delegate == nil else { return }
        let delegate = CaptureDelegate(driver: self)
        self.delegate = delegate

        let appInfo = SKTAppInfo()
        appInfo.appID = configuration.appID
        appInfo.appKey = configuration.appKey
        appInfo.developerID = configuration.developerID

        // Delegates run on the main queue. CaptureSDK is opened once and never
        // closed; closing makes the readers reinitialize on the next open.
        captureHelper.dispatchQueue = DispatchQueue.main
        captureHelper.pushDelegate(delegate)
        captureHelper.openWithAppInfo(appInfo) { [weak self] result in
            Self.onMain {
                guard let self else { return }
                if result == .E_NOERROR {
                    self.onEvent?(.ready)
                    // The reader confirms a read itself (beep/LED), as in Cordova.
                    self.captureHelper.setConfirmationMode(.modeDevice) { _ in }
                } else {
                    self.onEvent?(.error("CaptureSDK open failed: \(result.rawValue)"))
                }
            }
        }
    }

    func setReading(_ isReading: Bool) {
        self.isReading = isReading
    }

    func requestBatteryLevels() {
        for (id, device) in devicesByID {
            device.getBatteryLevelWithCompletionHandler { [weak self] result, level in
                Self.onMain {
                    guard result == .E_NOERROR, let level else { return }
                    let percent = SKTHelper.getCurrentLevel(fromBatteryLevel: Int(level))
                    self?.onEvent?(.batteryLevel(id: id, percent: percent))
                }
            }
        }
    }

    func startDiscovery() {
        discoveredByID = [:]
        captureHelper.addBluetoothDevice(.bluetoothLowEnergy) { [weak self] result in
            Self.onMain {
                guard result != .E_NOERROR else { return }
                self?.onEvent?(.error("Bluetooth LE search failed: \(result.rawValue)"))
                self?.onEvent?(.discoveryEnded)
            }
        }
    }

    func addClassicReader() {
        // Shows the iOS accessory picker. Readers must be in Application Mode.
        captureHelper.addBluetoothDevice(.bluetoothClassic) { [weak self] result in
            Self.onMain {
                guard result != .E_NOERROR else { return }
                self?.onEvent?(.error("Bluetooth Classic picker failed: \(result.rawValue)"))
            }
        }
    }

    func connect(_ reader: RFIDDiscoveredReader) {
        guard let info = discoveredByID[reader.id] else {
            onEvent?(.connectionEnded(id: reader.id, error: "Reader is no longer discovered"))
            return
        }
        captureHelper.connectToDiscoveredDevice(info) { [weak self] result in
            Self.onMain {
                self?.onEvent?(.connectionEnded(
                    id: reader.id,
                    error: result == .E_NOERROR ? nil : "connectToDiscoveredDevice: \(result.rawValue)"
                ))
            }
        }
    }

    func remove(_ device: RFIDReaderDevice) {
        captureHelper.removeBluetoothDevice(device.id) { [weak self] result in
            Self.onMain {
                guard let self else { return }
                if result == .E_NOERROR {
                    self.devicesByID[device.id] = nil
                    self.onEvent?(.deviceDisconnected(id: device.id))
                } else {
                    self.onEvent?(.removalFailed(id: device.id, error: "removeBluetoothDevice: \(result.rawValue)"))
                }
            }
        }
    }

    // MARK: - CaptureHelper callbacks

    fileprivate func deviceArrived(_ device: CaptureHelperDevice) {
        // SocketCam (the camera scanner) and the BLE device manager are not readers.
        switch device.deviceInfo.deviceType {
        case .socketCamC820, .socketCamC860, .deviceManagerBle:
            return
        default:
            break
        }
        guard let id = device.deviceInfo.guid else { return }
        devicesByID[id] = device
        onEvent?(.deviceConnected(id: id, name: device.deviceInfo.name ?? "Socket Mobile"))
    }

    fileprivate func deviceRemoved(_ device: CaptureHelperDevice) {
        guard let id = device.deviceInfo.guid, devicesByID.removeValue(forKey: id) != nil else { return }
        onEvent?(.deviceDisconnected(id: id))
    }

    fileprivate func discovered(_ info: SKTCaptureDiscoveredDeviceInfo) {
        guard let id = info.identifierUuid else { return }
        discoveredByID[id] = info
        onEvent?(.discovered(RFIDDiscoveredReader(id: id, name: info.name ?? "Socket Mobile")))
    }

    fileprivate func discoveryEnded(_ result: SKTResult) {
        if result != .E_NOERROR {
            onEvent?(.error("Bluetooth LE search ended: \(result.rawValue)"))
        }
        onEvent?(.discoveryEnded)
    }

    fileprivate func decoded(_ data: SKTCaptureDecodedData?, result: SKTResult) {
        guard result == .E_NOERROR else {
            onEvent?(.error("Decoded data result: \(result.rawValue)"))
            return
        }
        guard isReading, let tag = data?.stringFromDecodedData(), !tag.isEmpty else { return }
        onEvent?(.tagRead(tag))
    }

    fileprivate func batteryChanged(_ level: Int, device: CaptureHelperDevice) {
        guard let id = device.deviceInfo.guid else { return }
        onEvent?(.batteryLevel(id: id, percent: SKTHelper.getCurrentLevel(fromBatteryLevel: level)))
    }

    fileprivate func failed(_ result: SKTResult) {
        onEvent?(.error("CaptureSDK error: \(result.rawValue)"))
    }

    /// Completion handlers are not documented to run on `dispatchQueue`.
    nonisolated fileprivate static func onMain(_ action: @escaping @MainActor () -> Void) {
        if Thread.isMainThread {
            MainActor.assumeIsolated(action)
        } else {
            DispatchQueue.main.async { MainActor.assumeIsolated(action) }
        }
    }
}

/// CaptureHelper's delegate protocols are not actor-isolated; with
/// `dispatchQueue = .main` the callbacks arrive on the main thread.
private final class CaptureDelegate:
    CaptureHelperDevicePresenceDelegate,
    CaptureHelperDiscoveryDelegate,
    CaptureHelperDeviceDecodedDataDelegate,
    CaptureHelperDevicePowerDelegate,
    CaptureHelperErrorDelegate
{
    private weak var driver: SocketMobileRFIDReaderDriver?

    init(driver: SocketMobileRFIDReaderDriver) {
        self.driver = driver
    }

    func didNotifyArrivalForDevice(_ device: CaptureHelperDevice, withResult result: SKTResult) {
        SocketMobileRFIDReaderDriver.onMain { [weak driver] in driver?.deviceArrived(device) }
    }

    func didNotifyRemovalForDevice(_ device: CaptureHelperDevice, withResult result: SKTResult) {
        SocketMobileRFIDReaderDriver.onMain { [weak driver] in driver?.deviceRemoved(device) }
    }

    func didDiscoverDevice(_ device: SKTCaptureDiscoveredDeviceInfo) {
        SocketMobileRFIDReaderDriver.onMain { [weak driver] in driver?.discovered(device) }
    }

    func didEndDiscoveryWithResult(_ result: SKTResult) {
        SocketMobileRFIDReaderDriver.onMain { [weak driver] in driver?.discoveryEnded(result) }
    }

    func didReceiveDecodedData(
        _ decodedData: SKTCaptureDecodedData?,
        fromDevice device: CaptureHelperDevice,
        withResult result: SKTResult
    ) {
        SocketMobileRFIDReaderDriver.onMain { [weak driver] in driver?.decoded(decodedData, result: result) }
    }

    func didChangePowerState(_ powerState: SKTCapturePowerState, forDevice device: CaptureHelperDevice) {}

    func didChangeBatteryLevel(_ batteryLevel: Int, forDevice device: CaptureHelperDevice) {
        SocketMobileRFIDReaderDriver.onMain { [weak driver] in driver?.batteryChanged(batteryLevel, device: device) }
    }

    func didReceiveError(_ error: SKTResult) {
        SocketMobileRFIDReaderDriver.onMain { [weak driver] in driver?.failed(error) }
    }
}
