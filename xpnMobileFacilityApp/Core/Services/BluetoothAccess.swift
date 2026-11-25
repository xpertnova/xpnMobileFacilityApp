import CoreBluetooth
import Foundation

enum BluetoothAccessState: Equatable, Sendable {
    /// Not reported yet: the prompt is unanswered, or access is granted but
    /// no manager has reported the power state.
    case unknown
    case denied
    case unsupported
    case allowed(isPoweredOn: Bool)
}

/// Bluetooth permission and power for readers that connect over Bluetooth.
@MainActor
protocol BluetoothAccessChecking: AnyObject {
    var state: BluetoothAccessState { get }
    /// Called on the main actor whenever `state` changes.
    var onChange: ((BluetoothAccessState) -> Void)? { get set }
    /// Shows the system permission prompt when it has not been answered and
    /// starts reporting changes.
    func request()
}

/// iOS shows its Bluetooth prompt (with `NSBluetoothAlwaysUsageDescription`)
/// the first time the app creates a `CBCentralManager`. That happens only in
/// `request()`, so the prompt appears when the technician starts using RFID.
@MainActor
final class CoreBluetoothAccess: NSObject, BluetoothAccessChecking {
    private(set) var state: BluetoothAccessState
    var onChange: ((BluetoothAccessState) -> Void)?
    private var manager: CBCentralManager?

    override init() {
        state = Self.stateFromAuthorization()
        super.init()
    }

    func request() {
        guard manager == nil else { return }
        // No system alert for "Bluetooth is off"; the scan screen explains it.
        manager = CBCentralManager(
            delegate: self,
            queue: .main,
            options: [CBCentralManagerOptionShowPowerAlertKey: false]
        )
    }

    private func update(_ newState: BluetoothAccessState) {
        guard newState != state else { return }
        state = newState
        onChange?(newState)
    }

    private static func stateFromAuthorization() -> BluetoothAccessState {
        switch CBManager.authorization {
        case .denied, .restricted: .denied
        case .notDetermined, .allowedAlways: .unknown
        @unknown default: .unknown
        }
    }
}

extension CoreBluetoothAccess: CBCentralManagerDelegate {
    nonisolated func centralManagerDidUpdateState(_ central: CBCentralManager) {
        let managerState = central.state
        MainActor.assumeIsolated {
            switch managerState {
            case .poweredOn: update(.allowed(isPoweredOn: true))
            case .poweredOff: update(.allowed(isPoweredOn: false))
            case .unauthorized: update(.denied)
            case .unsupported: update(.unsupported)
            case .unknown, .resetting: break
            @unknown default: break
            }
        }
    }
}
