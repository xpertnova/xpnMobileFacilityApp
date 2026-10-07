import SwiftUI
import UIKit

/// Settings card for the Socket Mobile RFID reader: the connected reader with
/// battery and removal, and a Bluetooth LE search with the readers it finds.
/// Only one reader is connected at a time.
struct RFIDReaderSettingsSection: View {
    let reader: RFIDReaderService

    @State private var deviceToRemove: RFIDReaderDevice?

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            header

            switch reader.status {
            case .unavailable:
                notice("profile.settings.rfid.unavailable", symbol: "nosign")
            case .bluetoothDenied:
                notice("profile.settings.rfid.bluetoothDenied", symbol: "exclamationmark.triangle.fill") {
                    Button("scan.action.openSettings", action: openSystemSettings)
                        .buttonStyle(.bordered)
                }
            case .bluetoothOff:
                notice("profile.settings.rfid.bluetoothOff", symbol: "exclamationmark.triangle.fill")
                connectedReaders
            case .notConnected, .connected:
                if reader.isStarted {
                    connectedReaders
                    addReaders
                } else {
                    setUp
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .facilityCard()
        .facilityConfirmationDialog(
            isPresented: Binding(
                get: { deviceToRemove != nil },
                set: { if !$0 { deviceToRemove = nil } }
            ),
            titleKey: "profile.settings.rfid.remove.title",
            messageKey: "profile.settings.rfid.remove.message",
            confirmTitleKey: "profile.settings.rfid.remove.confirm",
            isDestructive: true
        ) { [deviceToRemove] in
            // Captured while the dialog is shown: confirming dismisses it
            // first, which clears `deviceToRemove` before this runs.
            if let deviceToRemove { reader.remove(deviceToRemove) }
        }
    }

    private var header: some View {
        HStack(alignment: .top, spacing: 14) {
            Image(systemName: "antenna.radiowaves.left.and.right")
                .font(.title2.weight(.semibold))
                .foregroundStyle(FacilityTheme.accent)
                .frame(width: 46, height: 46)
                .background(FacilityTheme.accentSoft, in: RoundedRectangle(cornerRadius: 13, style: .continuous))
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 4) {
                Text("profile.settings.rfid.title")
                    .font(.headline)
                    .foregroundStyle(FacilityTheme.ink)
                Text("profile.settings.rfid.description")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    /// Bluetooth is requested only here, when the technician chooses to set
    /// up readers, so the system prompt appears in context.
    private var setUp: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("profile.settings.rfid.setUp.message")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            Button(action: reader.start) {
                Label("profile.settings.rfid.setUp.action", systemImage: "dot.radiowaves.left.and.right")
                    .font(.subheadline.weight(.semibold))
                    .frame(minHeight: 44)
                    .padding(.horizontal, 16)
                    .foregroundStyle(.white)
                    .background(FacilityTheme.accent, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            }
            .buttonStyle(.plain)
        }
    }

    // MARK: - Connected readers

    private var connectedReaders: some View {
        VStack(alignment: .leading, spacing: 10) {
            sectionTitle("profile.settings.rfid.connected.title")
            if reader.devices.isEmpty {
                placeholder("profile.settings.rfid.connected.empty")
            } else {
                ForEach(reader.devices) { device in
                    ReaderRow(
                        name: device.name,
                        detail: batteryText(for: device),
                        badge: reader.isReading ? .reading : .ready
                    ) {
                        if reader.removingDeviceIDs.contains(device.id) {
                            ProgressView()
                        } else {
                            Button(role: .destructive) {
                                deviceToRemove = device
                            } label: {
                                Text("profile.settings.rfid.remove.action")
                            }
                            .buttonStyle(.bordered)
                            .disabled(!reader.canManageReaders)
                        }
                    }
                }
            }
            if reader.didFailRemoval {
                notice("profile.settings.rfid.remove.failed", symbol: "exclamationmark.triangle.fill")
            }
        }
    }

    private func batteryText(for device: RFIDReaderDevice) -> Text? {
        device.batteryPercent.map { Text("profile.settings.rfid.battery \($0)") }
    }

    // MARK: - Adding readers

    private var addReaders: some View {
        VStack(alignment: .leading, spacing: 10) {
            sectionTitle("profile.settings.rfid.add.title")

            Button(action: reader.startDiscovery) {
                HStack(spacing: 8) {
                    if reader.isDiscovering {
                        ProgressView()
                    } else {
                        Image(systemName: "magnifyingglass")
                    }
                    Text(reader.isDiscovering ? "profile.settings.rfid.search.running" : "profile.settings.rfid.search.action")
                }
                .frame(minHeight: 36)
            }
            .buttonStyle(.bordered)
            .disabled(reader.isDiscovering || !reader.canAddReader)

            Text(reader.devices.isEmpty ? "profile.settings.rfid.add.hint" : "profile.settings.rfid.add.limit")
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            if reader.isDiscovering || !reader.discoveredReaders.isEmpty {
                sectionTitle("profile.settings.rfid.found.title")
                    .padding(.top, 6)
                if reader.discoveredReaders.isEmpty {
                    placeholder("profile.settings.rfid.search.running")
                }
                ForEach(reader.discoveredReaders) { discovered in
                    ReaderRow(name: discovered.name, detail: nil, badge: nil) {
                        if reader.connectingReaderIDs.contains(discovered.id) {
                            ProgressView()
                        } else {
                            Button("profile.settings.rfid.connect.action") { reader.connect(discovered) }
                                .buttonStyle(.borderedProminent)
                                .tint(FacilityTheme.accent)
                                .disabled(!reader.canAddReader || !reader.connectingReaderIDs.isEmpty)
                        }
                    }
                }
            }
        }
    }

    // MARK: - Building blocks

    private func sectionTitle(_ key: LocalizedStringKey) -> some View {
        Text(key)
            .font(.subheadline.weight(.semibold))
            .foregroundStyle(FacilityTheme.ink)
    }

    private func placeholder(_ key: LocalizedStringKey) -> some View {
        Text(key)
            .font(.subheadline)
            .foregroundStyle(.secondary)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(14)
            .background(FacilityTheme.canvas, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
    }

    private func notice(_ key: LocalizedStringKey, symbol: String) -> some View {
        notice(key, symbol: symbol) { EmptyView() }
    }

    private func notice<Action: View>(
        _ key: LocalizedStringKey,
        symbol: String,
        @ViewBuilder action: () -> Action
    ) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Label {
                Text(key)
                    .fixedSize(horizontal: false, vertical: true)
            } icon: {
                Image(systemName: symbol).foregroundStyle(FacilityTheme.orange)
            }
            .font(.subheadline)
            .foregroundStyle(FacilityTheme.ink)
            action()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(14)
        .background(FacilityTheme.orange.opacity(0.08), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
    }

    private func openSystemSettings() {
        guard let url = URL(string: UIApplication.openSettingsURLString) else { return }
        UIApplication.shared.open(url)
    }
}

private enum ReaderBadge {
    case ready
    case reading

    var titleKey: LocalizedStringKey {
        switch self {
        case .ready: "scan.devices.ready"
        case .reading: "scan.devices.reading"
        }
    }
}

private struct ReaderRow<Trailing: View>: View {
    let name: String
    let detail: Text?
    let badge: ReaderBadge?
    @ViewBuilder let trailing: () -> Trailing

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: "sensor.tag.radiowaves.forward")
                .font(.title3)
                .foregroundStyle(FacilityTheme.ink)
                .frame(width: 42, height: 42)
                .background(FacilityTheme.blue.opacity(0.1), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 3) {
                Text(verbatim: name)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(FacilityTheme.ink)
                if let detail {
                    detail.font(.caption).foregroundStyle(.secondary)
                }
            }

            Spacer(minLength: 8)

            if let badge {
                Text(badge.titleKey)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(FacilityTheme.accent)
                    .padding(.horizontal, 9)
                    .padding(.vertical, 5)
                    .background(FacilityTheme.accentSoft, in: Capsule())
                    .fixedSize()
            }

            trailing()
        }
        .padding(12)
        .background(FacilityTheme.canvas.opacity(0.6), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
    }
}
