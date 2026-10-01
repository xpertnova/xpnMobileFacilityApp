import SwiftUI
import UIKit

struct ScanView: View {
    let demo: FacilityDemoViewModel

    @Environment(\.scenePhase) private var scenePhase
    @State private var mode: ScanMode = .qrCode
    /// RFID, and every scan in demo mode, only plays the scan animation.
    @State private var simulationState: SimulatedScanState = .ready
    @State private var viewModel: ScanViewModel

    init(demo: FacilityDemoViewModel) {
        self.demo = demo
        _viewModel = State(initialValue: ScanViewModel(
            sapDataStore: demo.sapDataStore,
            openSingleMatch: { [demo] in demo.openScannedNotification($0) }
        ))
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                PageHeader("scan.title", subtitle: "scan.subtitle", trailing: AnyView(modePicker))

                FacilitySideColumnLayout(sideWidth: 430, minimumMainWidth: 490, spacing: 18) {
                    mainColumn
                    deviceColumn
                }
            }
            .facilityPageContent()
        }
        .background(FacilityTheme.canvas)
        .onChange(of: mode) { _, _ in
            // Switching to RFID only stops a running scan; found
            // notifications are still listed when the technician comes back.
            viewModel.cancel()
            simulationState = .ready
        }
        .onDisappear { viewModel.cancel() }
    }

    @ViewBuilder
    private var mainColumn: some View {
        if !isSimulated, case let .results(lookup) = viewModel.state {
            ScanResultsPanel(
                lookup: lookup,
                rows: demo.scanResultRows(for: lookup.matches),
                open: demo.openScannedNotification
            )
        } else {
            scannerViewport
        }
    }

    private var modePicker: some View {
        Picker("scan.mode", selection: $mode) {
            ForEach(ScanMode.allCases) { mode in
                Text(LocalizedStringKey(mode.titleKey)).tag(mode)
            }
        }
        .pickerStyle(.segmented)
        .frame(width: 190)
    }

    private var scannerViewport: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 22, style: .continuous).fill(FacilityTheme.navy)

            if mode == .qrCode, shouldShowCamera {
                QRCodeCameraView(
                    isActive: viewModel.cameraShouldRun && scenePhase == .active,
                    onPreparing: viewModel.cameraIsPreparing,
                    onReady: viewModel.cameraDidStart,
                    onCode: viewModel.accept,
                    onFailure: viewModel.cameraFailed
                )
                .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
            }

            VStack(spacing: 0) {
                Spacer()
                ZStack {
                    ScanFrame()
                        .stroke(FacilityTheme.accent, lineWidth: 4)
                        .frame(width: 240, height: 240)

                    Capsule()
                        .fill(LinearGradient(
                            colors: [.clear, FacilityTheme.accent, .clear],
                            startPoint: .leading,
                            endPoint: .trailing
                        ))
                        .frame(width: 170, height: 3)
                        .shadow(color: FacilityTheme.accent.opacity(0.8), radius: 12)
                        .offset(y: isActivelyScanning ? 76 : -76)
                        .opacity(isActivelyScanning ? 1 : 0)
                        .animation(
                            isActivelyScanning
                                ? .easeInOut(duration: 0.8).repeatForever(autoreverses: true)
                                : .default,
                            value: isActivelyScanning
                        )
                }
                Spacer()
                HStack(spacing: 8) {
                    if isResolving { ProgressView().tint(.white) }
                    Text(LocalizedStringKey(viewportMessageKey))
                }
                .font(.subheadline)
                .foregroundStyle(.white.opacity(0.88))
                .padding(.bottom, 24)
            }
        }
        .frame(maxWidth: .infinity, minHeight: 400)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(Text(LocalizedStringKey(viewportMessageKey)))
    }

    private var deviceColumn: some View {
        VStack(spacing: 14) {
            actionButton
            if !isSimulated { qrOutcome }

            VStack(alignment: .leading, spacing: 15) {
                Text("scan.devices.title").font(.headline)
                ScanDeviceRow(
                    symbol: "printer.fill",
                    titleKey: "scan.devices.printer.title",
                    subtitleKey: "scan.devices.printer.subtitle"
                )
                ScanDeviceRow(
                    symbol: "antenna.radiowaves.left.and.right",
                    titleKey: "scan.devices.rfid.title",
                    subtitleKey: "scan.devices.rfid.subtitle"
                )
            }
            .facilityCard()
        }
    }

    @ViewBuilder
    private var actionButton: some View {
        if canCancelScan {
            Button(action: viewModel.cancel) {
                Label("scan.action.cancel", systemImage: "xmark")
                    .font(.headline)
                    .frame(maxWidth: .infinity, minHeight: 48)
                    .foregroundStyle(FacilityTheme.ink)
                    .background(FacilityTheme.surface, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                    .overlay {
                        RoundedRectangle(cornerRadius: 14, style: .continuous)
                            .stroke(.gray.opacity(0.28))
                    }
            }
            .buttonStyle(.plain)
        } else {
            primaryButton
        }
    }

    private var primaryButton: some View {
        Button(action: performPrimaryAction) {
            HStack(spacing: 9) {
                if primaryActionIsBusy {
                    ProgressView().tint(.white)
                } else {
                    Image(systemName: mode == .qrCode ? "qrcode.viewfinder" : "antenna.radiowaves.left.and.right")
                }
                Text(LocalizedStringKey(primaryActionKey))
            }
            .font(.headline)
            .frame(maxWidth: .infinity, minHeight: 48)
            .foregroundStyle(.white)
            .background(FacilityTheme.accent, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        }
        .buttonStyle(.plain)
        .disabled(primaryActionIsBusy)
    }

    @ViewBuilder
    private var qrOutcome: some View {
        switch viewModel.state {
        case let .failure(failure):
            VStack(alignment: .leading, spacing: 12) {
                Label(LocalizedStringKey(failure.titleKey), systemImage: "exclamationmark.triangle.fill")
                    .font(.headline)
                    .foregroundStyle(FacilityTheme.red)
                Text(LocalizedStringKey(failure.messageKey))
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                if failure == .cameraPermissionDenied {
                    Button("scan.action.openSettings", action: openSettings)
                        .buttonStyle(.bordered)
                }
            }
            .facilityCard()

        default:
            EmptyView()
        }
    }

    /// Demo mode has no camera and no SAP cache to look a code up in, so its
    /// QR scan is simulated like RFID instead of failing on an empty lookup.
    private var isSimulated: Bool {
        mode == .rfid || demo.isDemoMode
    }

    private func performPrimaryAction() {
        if isSimulated {
            simulateScan()
        } else {
            viewModel.startQRCodeScan()
        }
    }

    private func simulateScan() {
        guard simulationState != .scanning else { return }
        simulationState = .scanning
        Task {
            try? await Task.sleep(for: .milliseconds(1_300))
            guard !Task.isCancelled else { return }
            simulationState = .complete
        }
    }

    private func openSettings() {
        guard let url = URL(string: UIApplication.openSettingsURLString) else { return }
        UIApplication.shared.open(url)
    }

    private var shouldShowCamera: Bool {
        guard !demo.isDemoMode else { return false }
        switch viewModel.state {
        case .requestingPermission, .configuring, .scanning, .resolving:
            return true
        default:
            return false
        }
    }

    /// While the camera is open the primary action stops it. The lookup after
    /// a code was read is brief and only shows progress.
    private var canCancelScan: Bool {
        !isSimulated && viewModel.cameraShouldRun
    }

    private var isActivelyScanning: Bool {
        isSimulated ? simulationState == .scanning : viewModel.state == .scanning
    }

    private var isResolving: Bool {
        !isSimulated && viewModel.state == .resolving
    }

    private var primaryActionIsBusy: Bool {
        isSimulated ? simulationState == .scanning : viewModel.isBusy
    }

    private var primaryActionKey: String {
        if isSimulated {
            return simulationState == .scanning ? "scan.action.simulating" : "scan.action.simulate"
        }
        switch viewModel.state {
        case .requestingPermission, .configuring, .scanning, .resolving:
            return "scan.action.scanning"
        case .results:
            return "scan.action.again"
        case .failure:
            return "scan.action.retry"
        case .idle:
            return "scan.action.start"
        }
    }

    private var viewportMessageKey: String {
        if isSimulated {
            return simulationState == .ready && mode == .qrCode ? "scan.viewport.ready" : simulationState.messageKey
        }
        switch viewModel.state {
        case .idle: return "scan.viewport.ready"
        case .requestingPermission: return "scan.viewport.permission"
        case .configuring: return "scan.viewport.configuring"
        case .scanning: return "scan.viewport.scanning"
        case .resolving: return "scan.viewport.resolving"
        case .results: return "scan.viewport.complete"
        case .failure: return "scan.viewport.failed"
        }
    }
}

private enum ScanMode: CaseIterable, Identifiable {
    case qrCode
    case rfid
    var id: Self { self }
    var titleKey: String { self == .qrCode ? "scan.mode.qr" : "scan.mode.rfid" }
}

private enum SimulatedScanState: Equatable {
    case ready
    case scanning
    case complete
    var messageKey: String {
        switch self {
        case .ready: "scan.viewport.rfidReady"
        case .scanning: "scan.viewport.scanning"
        case .complete: "scan.viewport.complete"
        }
    }
}

private struct ScanFrame: Shape {
    func path(in rect: CGRect) -> Path {
        let side: CGFloat = 38
        var path = Path()
        path.move(to: CGPoint(x: 0, y: side)); path.addLine(to: .zero); path.addLine(to: CGPoint(x: side, y: 0))
        path.move(to: CGPoint(x: rect.maxX - side, y: 0)); path.addLine(to: CGPoint(x: rect.maxX, y: 0)); path.addLine(to: CGPoint(x: rect.maxX, y: side))
        path.move(to: CGPoint(x: 0, y: rect.maxY - side)); path.addLine(to: CGPoint(x: 0, y: rect.maxY)); path.addLine(to: CGPoint(x: side, y: rect.maxY))
        path.move(to: CGPoint(x: rect.maxX - side, y: rect.maxY)); path.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY)); path.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY - side))
        return path
    }
}

private struct ScanDeviceRow: View {
    let symbol: String
    let titleKey: String
    let subtitleKey: String

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: symbol)
                .font(.title3)
                .foregroundStyle(FacilityTheme.ink)
                .frame(width: 42, height: 42)
                .background(FacilityTheme.blue.opacity(0.1), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            VStack(alignment: .leading, spacing: 3) {
                Text(LocalizedStringKey(titleKey)).font(.subheadline.weight(.semibold))
                Text(LocalizedStringKey(subtitleKey)).font(.caption).foregroundStyle(.secondary)
            }
            Spacer(minLength: 4)
            Text("scan.devices.ready")
                .font(.caption.weight(.semibold))
                .foregroundStyle(FacilityTheme.accent)
                .padding(.horizontal, 9)
                .padding(.vertical, 5)
                .background(FacilityTheme.accentSoft, in: Capsule())
        }
    }
}

/// The notifications a scanned code resolved to, drawn like the rows of the
/// maintenance notification list.
private struct ScanResultsPanel: View {
    let lookup: ScanViewModel.Lookup
    let rows: [MaintenanceNotification]
    let open: (SAPNotificationSummary) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            header

            ForEach(Array(zip(lookup.matches, rows)), id: \.0.id) { summary, notification in
                ScanResultRow(summary: summary, notification: notification) {
                    open(summary)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var header: some View {
        HStack(alignment: .center, spacing: 14) {
            Image(systemName: "qrcode.viewfinder")
                .font(.title3.weight(.semibold))
                .foregroundStyle(FacilityTheme.accent)
                .frame(width: 44, height: 44)
                .background(FacilityTheme.accentSoft, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 3) {
                HStack(alignment: .center, spacing: 8) {
                    Text("scan.results.title")
                        .font(.title3.weight(.bold))
                        .foregroundStyle(FacilityTheme.ink)
                    Text(lookup.matches.count, format: .number)
                        .font(.caption.weight(.bold))
                        .foregroundStyle(FacilityTheme.accent)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 3)
                        .background(FacilityTheme.accentSoft, in: Capsule())
                }
                Text("scan.results.scannedCode \(lookup.payload.scannedCodeDescription)")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
        }
        .accessibilityElement(children: .combine)
    }
}

private struct ScanResultRow: View {
    let summary: SAPNotificationSummary
    let notification: MaintenanceNotification
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(alignment: .top, spacing: 16) {
                NotificationStatusIcon(status: notification.status)

                VStack(alignment: .leading, spacing: 10) {
                    Text(titleLine)
                        .font(.headline)
                        .foregroundStyle(FacilityTheme.ink)
                        .multilineTextAlignment(.leading)

                    VStack(alignment: .leading, spacing: 6) {
                        Text(technicalObjectLine)
                        if !notification.location.isEmpty, notification.location != summary.functionalLocationID {
                            Text(notification.location)
                        }
                    }
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.leading)

                    HStack(alignment: .center, spacing: 6) {
                        Text(notification.dueDate)
                            .font(.subheadline)
                            .foregroundStyle(.secondary)

                        Spacer(minLength: 8)

                        if !formCode.isEmpty {
                            FacilityTemplateBadge(text: formCode, style: .neutral)
                        }

                        NotificationStatusBadges(notification: notification)

                        Image(systemName: "chevron.right")
                            .font(.caption.weight(.bold))
                            .foregroundStyle(.tertiary)
                            .padding(.leading, 8)
                    }
                }
            }
            .padding(20)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(.white, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
            .shadow(color: Color.black.opacity(0.04), radius: 8, x: 0, y: 2)
            .contentShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        }
        .buttonStyle(.plain)
    }

    private var titleLine: String {
        "\(notification.title) · \(String(localized: "notifications.detail.number", bundle: .appLanguage)) \(notification.id)"
    }

    private var technicalObjectLine: String {
        guard !summary.equipmentID.isEmpty else { return summary.functionalLocationID }
        return [
            summary.functionalLocationID,
            "\(String(localized: "notifications.detail.equipment", bundle: .appLanguage)) \(summary.equipmentID.withoutSAPLeadingZeros)"
        ]
        .filter { !$0.isEmpty }
        .joined(separator: " · ")
    }

    /// Form code (`STEUS`), the same grey badge the notification header shows.
    private var formCode: String {
        let indexedCode = notification.structuralFilterMetadata?.formCode ?? ""
        return (indexedCode.isEmpty ? summary.legacyControlKey : indexedCode).uppercased()
    }
}

private extension LegacyQRCodePayload {
    var scannedCodeDescription: String {
        switch self {
        case let .mtfm(_, functionalLocationID, equipmentID):
            guard let equipmentID else { return functionalLocationID }
            return "\(functionalLocationID) · \(String(localized: "notifications.detail.equipment", bundle: .appLanguage)) \(equipmentID.withoutSAPLeadingZeros)"
        case let .mihm(objectNumber, technicalReference):
            return "\(objectNumber) · \(technicalReference)"
        }
    }
}

private extension String {
    /// SAP pads numeric equipment numbers with zeros; the legacy notification
    /// list showed them without the padding.
    var withoutSAPLeadingZeros: String {
        guard !isEmpty, allSatisfy({ $0.isASCII && $0.isNumber }) else { return self }
        let trimmed = drop(while: { $0 == "0" })
        return trimmed.isEmpty ? "0" : String(trimmed)
    }
}
