import Foundation
import Observation

@MainActor
@Observable
final class ScanViewModel {
    enum State: Equatable {
        case idle
        case requestingPermission
        case configuring
        case scanning
        case resolving
        case results([SAPNotificationSummary])
        case failure(Failure)
    }

    enum Failure: Equatable {
        case invalidCode
        case synchronizationRequired
        case noMatches
        case cameraPermissionDenied
        case cameraUnavailable
        case cacheUnavailable

        var titleKey: String {
            switch self {
            case .cameraPermissionDenied, .cameraUnavailable:
                "scan.error.camera.title"
            case .invalidCode:
                "scan.error.invalid.title"
            case .synchronizationRequired, .noMatches, .cacheUnavailable:
                "scan.error.lookup.title"
            }
        }

        var messageKey: String {
            switch self {
            case .invalidCode: "scan.error.invalid.message"
            case .synchronizationRequired: "scan.error.synchronizationRequired.message"
            case .noMatches: "scan.error.noMatches.message"
            case .cameraPermissionDenied: "scan.error.cameraPermission.message"
            case .cameraUnavailable: "scan.error.cameraUnavailable.message"
            case .cacheUnavailable: "scan.error.cache.message"
            }
        }
    }

    private let sapDataStore: SAPDataStore
    private let isDemoMode: Bool
    private var acceptedValue: String?
    private var resolutionTask: Task<Void, Never>?

    private(set) var state: State = .idle

    init(sapDataStore: SAPDataStore, isDemoMode: Bool) {
        self.sapDataStore = sapDataStore
        self.isDemoMode = isDemoMode
    }

    var cameraShouldRun: Bool {
        switch state {
        case .requestingPermission, .configuring, .scanning:
            true
        default:
            false
        }
    }

    var isBusy: Bool {
        switch state {
        case .requestingPermission, .configuring, .scanning, .resolving:
            true
        default:
            false
        }
    }

    func startQRCodeScan() {
        guard !isBusy else { return }
        resetTransientState()
        if isDemoMode {
            accept(Self.demoPayload)
        } else {
            state = .requestingPermission
        }
    }

    func cameraIsPreparing() {
        guard state == .requestingPermission else { return }
        state = .configuring
    }

    func cameraDidStart() {
        guard state == .requestingPermission || state == .configuring else { return }
        state = .scanning
    }

    func cameraFailed(_ failure: QRCodeScannerFailure) {
        switch failure {
        case .permissionDenied:
            state = .failure(.cameraPermissionDenied)
        case .unavailable, .configurationFailed:
            state = .failure(.cameraUnavailable)
        }
    }

    func accept(_ rawValue: String) {
        guard !rawValue.isEmpty, rawValue != acceptedValue else { return }
        acceptedValue = rawValue
        state = .resolving
        resolutionTask?.cancel()
        resolutionTask = Task { [weak self] in
            guard let self else { return }
            do {
                let payload = try LegacyQRCodeCodec.decode(rawValue)
                let matches = try await sapDataStore.resolveQRCode(payload)
                guard !Task.isCancelled else { return }
                state = matches.isEmpty ? .failure(.noMatches) : .results(matches)
            } catch is CancellationError {
                return
            } catch LegacyQRCodeCodecError.invalidPayload {
                state = .failure(.invalidCode)
            } catch QRCodeResolutionError.synchronizationRequired {
                state = .failure(.synchronizationRequired)
            } catch {
                state = .failure(.cacheUnavailable)
            }
        }
    }

    func cancel() {
        resolutionTask?.cancel()
        resetTransientState()
        state = .idle
    }

    private func resetTransientState() {
        resolutionTask?.cancel()
        resolutionTask = nil
        acceptedValue = nil
    }

    func scanAgain() {
        startQRCodeScan()
    }

    private static let demoPayload = LegacyQRCodeCodec.encodeDemoMTFM(
        functionalLocationID: "UN01-ST01-BG01-TECH-420-Z",
        equipmentID: "EQ-100040"
    )
}
