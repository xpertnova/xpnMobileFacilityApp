import SwiftUI

struct ScanView: View {
    @State private var mode: ScanMode = .qrCode
    @State private var scanState: ScanState = .ready

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                PageHeader(
                    "scan.title",
                    subtitle: "scan.subtitle",
                    trailing: AnyView(modePicker)
                )

                ViewThatFits(in: .horizontal) {
                    HStack(alignment: .top, spacing: 18) {
                        scannerViewport
                        deviceColumn
                    }

                    VStack(alignment: .leading, spacing: 18) {
                        scannerViewport
                        deviceColumn
                    }
                }
            }
            .padding(28)
            .frame(maxWidth: 1280, alignment: .leading)
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
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .fill(FacilityTheme.navy)

            VStack(spacing: 0) {
                Spacer()

                ZStack {
                    ScanFrame()
                        .stroke(FacilityTheme.accent, lineWidth: 4)
                        .frame(width: 240, height: 240)

                    Capsule()
                        .fill(
                            LinearGradient(
                                colors: [.clear, FacilityTheme.accent, .clear],
                                startPoint: .leading,
                                endPoint: .trailing
                            )
                        )
                        .frame(width: 170, height: 3)
                        .shadow(color: FacilityTheme.accent.opacity(0.8), radius: 12)
                        .offset(y: scanState == .scanning ? 76 : 0)
                        .animation(.easeInOut(duration: 0.75).repeatCount(scanState == .scanning ? 2 : 0, autoreverses: true), value: scanState)
                }

                Spacer()

                Text(LocalizedStringKey(viewportMessageKey))
                    .font(.subheadline)
                    .foregroundStyle(.white.opacity(0.78))
                    .padding(.bottom, 24)
            }
        }
        .frame(minWidth: 490, maxWidth: .infinity, minHeight: 400)
    }

    private var deviceColumn: some View {
        VStack(spacing: 14) {
            Button(action: simulateScan) {
                HStack(spacing: 9) {
                    if scanState == .scanning {
                        ProgressView().tint(.white)
                    } else {
                        Image(systemName: "qrcode.viewfinder")
                    }
                    Text(LocalizedStringKey(scanState.buttonKey))
                }
                .font(.headline)
                .frame(maxWidth: .infinity, minHeight: 48)
                .foregroundStyle(.white)
                .background(FacilityTheme.accent, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
            }
            .buttonStyle(.plain)
            .disabled(scanState == .scanning)

            VStack(alignment: .leading, spacing: 15) {
                Text("scan.devices.title")
                    .font(.headline)

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
        .frame(width: 430)
    }

    private func simulateScan() {
        guard scanState != .scanning else { return }

        withAnimation(.easeInOut(duration: 0.2)) {
            scanState = .scanning
        }
        Task {
            try? await Task.sleep(nanoseconds: 1_300_000_000)
            guard !Task.isCancelled else { return }
            withAnimation(.easeInOut(duration: 0.2)) {
                scanState = .complete
            }
        }
    }

    private var viewportMessageKey: String {
        if scanState == .ready, mode == .rfid {
            return "scan.viewport.rfidReady"
        }
        return scanState.messageKey
    }
}

private enum ScanMode: CaseIterable, Identifiable {
    case qrCode
    case rfid

    var id: Self { self }

    var titleKey: String {
        switch self {
        case .qrCode: "scan.mode.qr"
        case .rfid: "scan.mode.rfid"
        }
    }
}

private enum ScanState: Equatable {
    case ready
    case scanning
    case complete

    var messageKey: String {
        switch self {
        case .ready: "scan.viewport.ready"
        case .scanning: "scan.viewport.scanning"
        case .complete: "scan.viewport.complete"
        }
    }

    var buttonKey: String {
        switch self {
        case .ready, .complete: "scan.action.simulate"
        case .scanning: "scan.action.simulating"
        }
    }
}

private struct ScanFrame: Shape {
    func path(in rect: CGRect) -> Path {
        let side: CGFloat = 38
        var path = Path()

        path.move(to: CGPoint(x: 0, y: side))
        path.addLine(to: .zero)
        path.addLine(to: CGPoint(x: side, y: 0))

        path.move(to: CGPoint(x: rect.maxX - side, y: 0))
        path.addLine(to: CGPoint(x: rect.maxX, y: 0))
        path.addLine(to: CGPoint(x: rect.maxX, y: side))

        path.move(to: CGPoint(x: 0, y: rect.maxY - side))
        path.addLine(to: CGPoint(x: 0, y: rect.maxY))
        path.addLine(to: CGPoint(x: side, y: rect.maxY))

        path.move(to: CGPoint(x: rect.maxX - side, y: rect.maxY))
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY))
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY - side))
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
                Text(LocalizedStringKey(titleKey))
                    .font(.subheadline.weight(.semibold))
                Text(LocalizedStringKey(subtitleKey))
                    .font(.caption)
                    .foregroundStyle(.secondary)
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
