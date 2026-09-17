import SwiftUI
import UIKit

struct ScanView: View {
    let demo: FacilityDemoViewModel

    @Environment(\.scenePhase) private var scenePhase
    @State private var mode: ScanMode = .qrCode
    @State private var rfidState: RFIDScanState = .ready
    @State private var viewModel: ScanViewModel

    init(demo: FacilityDemoViewModel) {
        self.demo = demo
        _viewModel = State(initialValue: ScanViewModel(
            sapDataStore: demo.sapDataStore,
            isDemoMode: demo.isDemoMode
        ))
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                PageHeader("scan.title", subtitle: "scan.subtitle", trailing: AnyView(modePicker))

                FacilitySideColumnLayout(sideWidth: 430, minimumMainWidth: 490, spacing: 18) {
                    scannerViewport
                    deviceColumn
                }
            }
            .facilityPageContent()
        }
        .background(FacilityTheme.canvas)
        .onChange(of: mode) { _, _ in
            viewModel.cancel()
            rfidState = .ready
        }
        .onChange(of: viewModel.state) { _, state in
            guard case let .results(matches) = state, matches.count == 1,
                  let notification = matches.first else { return }
            demo.openScannedNotification(notification)
        }
        .onDisappear { viewModel.cancel() }
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
            if mode == .qrCode { qrOutcome }

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

    private var actionButton: some View {
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

        case let .results(matches) where matches.count > 1:
            VStack(alignment: .leading, spacing: 12) {
                Text("scan.results.title").font(.headline)
                Text("scan.results.subtitle").font(.subheadline).foregroundStyle(.secondary)
                ForEach(matches) { notification in
                    Button {
                        demo.openScannedNotification(notification)
                    } label: {
                        VStack(alignment: .leading, spacing: 4) {
                            Text(notification.title.isEmpty ? notification.id : notification.title)
                                .font(.subheadline.weight(.semibold))
                                .foregroundStyle(FacilityTheme.ink)
                            Text([notification.id, notification.displayLocation]
                                .filter { !$0.isEmpty }
                                .joined(separator: " · "))
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    if notification.id != matches.last?.id { Divider() }
                }
            }
            .facilityCard()

        default:
            EmptyView()
        }
    }

    private func performPrimaryAction() {
        if mode == .qrCode {
            viewModel.startQRCodeScan()
        } else {
            simulateRFIDScan()
        }
    }

    private func simulateRFIDScan() {
        guard rfidState != .scanning else { return }
        rfidState = .scanning
        Task {
            try? await Task.sleep(for: .milliseconds(1_300))
            guard !Task.isCancelled else { return }
            rfidState = .complete
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

    private var isActivelyScanning: Bool {
        mode == .rfid ? rfidState == .scanning : viewModel.state == .scanning
    }

    private var isResolving: Bool {
        mode == .qrCode && viewModel.state == .resolving
    }

    private var primaryActionIsBusy: Bool {
        mode == .qrCode ? viewModel.isBusy : rfidState == .scanning
    }

    private var primaryActionKey: String {
        if mode == .rfid {
            return rfidState == .scanning ? "scan.action.simulating" : "scan.action.simulate"
        }
        if demo.isDemoMode {
            return viewModel.isBusy ? "scan.action.simulating" : "scan.action.simulate"
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
        if mode == .rfid { return rfidState.messageKey }
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

private enum RFIDScanState: Equatable {
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
