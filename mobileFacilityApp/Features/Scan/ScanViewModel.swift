import Foundation
import Observation

@MainActor
@Observable
final class ScanViewModel {
    enum Source: Equatable {
        case qrCode
        case rfid
    }

    enum State: Equatable {
        case idle
        case requestingPermission
        case configuring
        /// The camera is looking for a QR code, or the RFID reader is waiting
        /// for a tag.
        case scanning
        case resolving
        case results(Lookup)
        case failure(Failure)
    }

    enum ScannedCode: Equatable {
        case qrCode(LegacyQRCodePayload)
        case rfidTag(String, RFIDTagAssignment)
    }

    /// A scanned code and the maintenance notifications it resolved to.
    struct Lookup: Equatable {
        let code: ScannedCode
        let matches: [SAPNotificationSummary]
    }

    enum Failure: Equatable {
        case invalidCode
        case synchronizationRequired
        case noMatches
        case cameraPermissionDenied
        case cameraUnavailable
        case cacheUnavailable
        case rfidReaderUnavailable
        case rfidReaderNotConnected
        case bluetoothDenied
        case bluetoothOff
        case rfidTagUnknown
        case rfidNoMatches

        var titleKey: String {
            switch self {
            case .cameraPermissionDenied, .cameraUnavailable:
                "scan.error.camera.title"
            case .invalidCode:
                "scan.error.invalid.title"
            case .rfidReaderUnavailable, .rfidReaderNotConnected, .bluetoothDenied, .bluetoothOff:
                "scan.error.rfidReader.title"
            case .synchronizationRequired, .noMatches, .cacheUnavailable, .rfidTagUnknown, .rfidNoMatches:
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
            case .rfidReaderUnavailable: "scan.error.rfidUnavailable.message"
            case .rfidReaderNotConnected: "scan.error.rfidNotConnected.message"
            case .bluetoothDenied: "scan.error.bluetoothDenied.message"
            case .bluetoothOff: "scan.error.bluetoothOff.message"
            case .rfidTagUnknown: "scan.error.rfidTagUnknown.message"
            case .rfidNoMatches: "scan.error.rfidNoMatches.message"
            }
        }
    }

    private let sapDataStore: SAPDataStore
    private let rfidReader: RFIDReaderService
    /// Opens the only notification a new lookup found. Results restored after
    /// a cancelled scan are not opened again.
    private let openSingleMatch: @MainActor (SAPNotificationSummary) -> Void
    private var acceptedValue: String?
    private var resolutionTask: Task<Void, Never>?
    /// The results on screen when the current scan started. Cancelling the
    /// scan returns to them instead of discarding the technician's list.
    private var stateBeforeScan: (state: State, source: Source?) = (.idle, nil)

    private(set) var state: State = .idle
    /// The scanner `state` belongs to; `nil` while idle.
    private(set) var source: Source?

    init(
        sapDataStore: SAPDataStore,
        rfidReader: RFIDReaderService,
        openSingleMatch: @escaping @MainActor (SAPNotificationSummary) -> Void
    ) {
        self.sapDataStore = sapDataStore
        self.rfidReader = rfidReader
        self.openSingleMatch = openSingleMatch
    }

    var cameraShouldRun: Bool {
        guard source == .qrCode else { return false }
        switch state {
        case .requestingPermission, .configuring, .scanning:
            return true
        default:
            return false
        }
    }

    var isWaitingForRFIDTag: Bool {
        source == .rfid && state == .scanning
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
        guard beginScan(from: .qrCode) else { return }
        state = .requestingPermission
    }

    /// Cordova's `onRfidPress`: activates the reader and looks up the next tag.
    func startRFIDScan() {
        guard beginScan(from: .rfid) else { return }
        rfidReader.start()
        switch rfidReader.status {
        case .unavailable:
            state = .failure(.rfidReaderUnavailable)
        case .bluetoothDenied:
            state = .failure(.bluetoothDenied)
        case .bluetoothOff:
            state = .failure(.bluetoothOff)
        case .notConnected:
            state = .failure(.rfidReaderNotConnected)
        case .connected:
            state = .scanning
            let didStart = rfidReader.beginReading { [weak self] tag in
                self?.acceptRFIDTag(tag)
            }
            if !didStart { state = .failure(.rfidReaderNotConnected) }
        }
    }

    /// Looks a tag up without the reader. For hardware testing only.
    func lookUpRFIDTag(_ rawTag: String) {
        let tag = RFIDTagLookup.normalizedTag(rawTag)
        guard !tag.isEmpty else { return }
        if isBusy { cancel() }
        guard beginScan(from: .rfid) else { return }
        rfidReader.record("Manual tag entry: \(tag)")
        resolveRFIDTag(tag)
    }

    func cameraIsPreparing() {
        guard source == .qrCode, state == .requestingPermission else { return }
        state = .configuring
    }

    func cameraDidStart() {
        guard source == .qrCode, state == .requestingPermission || state == .configuring else { return }
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
        resolveQRCode(rawValue)
    }

    /// Stops a running scan or lookup. Results found before the scan started
    /// stay on screen.
    func cancel() {
        guard isBusy else { return }
        resetTransientState()
        (state, source) = stateBeforeScan
    }

    private func beginScan(from newSource: Source) -> Bool {
        guard !isBusy else { return false }
        resetTransientState()
        if case .results = state {
            stateBeforeScan = (state, source)
        } else {
            stateBeforeScan = (.idle, nil)
        }
        source = newSource
        return true
    }

    private func acceptRFIDTag(_ tag: String) {
        guard isWaitingForRFIDTag else { return }
        resolveRFIDTag(tag)
    }

    private func resolveQRCode(_ rawValue: String) {
        guard !rawValue.isEmpty, rawValue != acceptedValue else { return }
        acceptedValue = rawValue
        resolve {
            let payload = try LegacyQRCodeCodec.decode(rawValue)
            let matches = try await $0.resolveQRCode(payload)
            return matches.isEmpty ? .failure(.noMatches) : .results(Lookup(code: .qrCode(payload), matches: matches))
        }
    }

    private func resolveRFIDTag(_ tag: String) {
        let reader = rfidReader
        resolve {
            guard let resolution = try await $0.resolveRFIDTag(tag) else {
                reader.record("No T0212 assignment for tag \(tag)", isError: true)
                return .failure(.rfidTagUnknown)
            }
            let assignment = resolution.assignment
            reader.record(
                "Tag \(tag) → STRNO \(assignment.functionalLocationID), EQUNR '\(assignment.equipmentID)', "
                    + "STEUS '\(assignment.controlKey)'"
                    + (resolution.matchedLegacyTagPrefix ? " (13-character legacy tag)" : "")
                    + ": \(resolution.matches.count) notification(s)"
            )
            return resolution.matches.isEmpty
                ? .failure(.rfidNoMatches)
                : .results(Lookup(code: .rfidTag(tag, assignment), matches: resolution.matches))
        }
    }

    private func resolve(_ lookup: @escaping @MainActor (SAPDataStore) async throws -> State) {
        state = .resolving
        resolutionTask?.cancel()
        resolutionTask = Task { [weak self] in
            guard let self else { return }
            do {
                let newState = try await lookup(sapDataStore)
                guard !Task.isCancelled else { return }
                state = newState
                if case let .results(lookup) = newState, lookup.matches.count == 1 {
                    openSingleMatch(lookup.matches[0])
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
        rfidReader.endReading()
    }
}
