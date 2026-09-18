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
        case results(Lookup)
        case failure(Failure)
    }

    /// A scanned code and the maintenance notifications it resolved to.
    struct Lookup: Equatable {
        let payload: LegacyQRCodePayload
        let matches: [SAPNotificationSummary]
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
    /// Opens the only notification a new lookup found. Results restored after
    /// a cancelled scan are not opened again.
    private let openSingleMatch: @MainActor (SAPNotificationSummary) -> Void
    private var acceptedValue: String?
    private var resolutionTask: Task<Void, Never>?
    /// The results on screen when the current scan started. Cancelling the
    /// scan returns to them instead of discarding the technician's list.
    private var stateBeforeScan: State = .idle

    private(set) var state: State = .idle

    init(
        sapDataStore: SAPDataStore,
        isDemoMode: Bool,
        openSingleMatch: @escaping @MainActor (SAPNotificationSummary) -> Void
    ) {
        self.sapDataStore = sapDataStore
        self.isDemoMode = isDemoMode
        self.openSingleMatch = openSingleMatch
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
        if case .results = state {
            stateBeforeScan = state
        } else {
            stateBeforeScan = .idle
        }
        if isDemoMode {
            resolve(Self.demoPayload)
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
        // A permission answer can arrive after the technician cancelled.
        guard cameraShouldRun else { return }
        switch failure {
        case .permissionDenied:
            state = .failure(.cameraPermissionDenied)
        case .unavailable, .configurationFailed:
            state = .failure(.cameraUnavailable)
        }
    }

    func accept(_ rawValue: String) {
        guard cameraShouldRun else { return }
        resolve(rawValue)
    }

    /// Stops a running scan or lookup. Results found before the scan started
    /// stay on screen.
    func cancel() {
        guard isBusy else { return }
        resetTransientState()
        state = stateBeforeScan
    }

    private func resolve(_ rawValue: String) {
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
                if matches.isEmpty {
                    state = .failure(.noMatches)
                } else {
                    state = .results(Lookup(payload: payload, matches: matches))
                    if matches.count == 1 { openSingleMatch(matches[0]) }
                }
            } catch is CancellationError {
                return
            } catch {
                guard !Task.isCancelled else { return }
                state = .failure(Self.failure(for: error))
            }
        }
    }

    private static func failure(for error: Error) -> Failure {
        if error as? LegacyQRCodeCodecError == .invalidPayload { return .invalidCode }
        if error as? QRCodeResolutionError == .synchronizationRequired { return .synchronizationRequired }
        return .cacheUnavailable
    }

    private func resetTransientState() {
        resolutionTask?.cancel()
        resolutionTask = nil
        acceptedValue = nil
    }

    private static let demoPayload = LegacyQRCodeCodec.encodeDemoMTFM(
        functionalLocationID: "UN01-ST01-BG01-TECH-420-Z",
        equipmentID: "EQ-100040"
    )
}
