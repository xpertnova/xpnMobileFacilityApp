import SwiftUI

struct DashboardView: View {
    let demo: FacilityDemoViewModel

    private let metricColumns = Array(
        repeating: GridItem(.flexible(minimum: 0), spacing: 14),
        count: 4
    )
    private let actionColumns = [
        GridItem(.flexible(minimum: 190), spacing: 14),
        GridItem(.flexible(minimum: 190), spacing: 14),
        GridItem(.flexible(minimum: 190), spacing: 14)
    ]

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                dashboardHeader

                LazyVGrid(columns: metricColumns, spacing: 14) {
                    MetricCard(count: demo.allNotificationCount, titleKey: "dashboard.metrics.notifications", symbol: "checklist", tint: FacilityTheme.blue) {
                        demo.open(.notifications)
                    }
                    MetricCard(count: visibleDefectCount, titleKey: "dashboard.metrics.defects", symbol: "exclamationmark.triangle", tint: FacilityTheme.red) {
                        demo.open(.defects)
                    }
                    MetricCard(count: demo.offlineWorkStore.savedNotificationCount, titleKey: "dashboard.metrics.drafts", symbol: "tray.and.arrow.down", tint: FacilityTheme.orange) {
                        demo.open(.drafts)
                    }
                    MetricCard(count: visibleTechnicalPlaceCount, titleKey: "dashboard.metrics.places", symbol: "square.split.2x2", tint: FacilityTheme.accent) {
                        demo.open(.technicalPlaces)
                    }
                }
                .frame(maxWidth: .infinity)

                quickAccess
                latestActivity
            }
            .padding(28)
            .frame(maxWidth: 1280, alignment: .leading)
        }
    }

    private var dashboardHeader: some View {
        HStack(alignment: .bottom, spacing: 20) {
            VStack(alignment: .leading, spacing: 5) {
                Text(String(format: String(localized: "dashboard.greeting"), demo.effectiveWorkerDisplayName))
                    .font(.system(size: 29, weight: .bold, design: .rounded))
                    .foregroundStyle(FacilityTheme.ink)
                Text(dashboardContext)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            Spacer(minLength: 12)
            if !demo.isDemoMode, demo.sapDataStore.isRefreshAvailable {
                SAPConnectionBadge()
            }
        }
    }

    private var visibleDefectCount: Int {
        demo.offlineWorkStore.closedDefectNotificationCount
    }

    private var dashboardContext: String {
        let currentDate = Date.now.formatted(
            .dateTime.weekday(.wide).day().month(.wide).year()
        )
        let organizationUnit = demo.sapDataStore.workerProfile?.organizationUnit
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return [currentDate, organizationUnit]
            .filter { !$0.isEmpty }
            .joined(separator: " · ")
    }

    private var visibleTechnicalPlaceCount: Int {
        demo.isDemoMode ? demo.technicalPlaces.count : 0
    }

    private var quickAccess: some View {
        VStack(alignment: .leading, spacing: 11) {
            Text("dashboard.quickActions")
                .font(.caption.weight(.heavy))
                .foregroundStyle(.secondary)
                .textCase(.uppercase)

            LazyVGrid(columns: actionColumns, spacing: 14) {
                DashboardActionCard(titleKey: "dashboard.tile.scan", subtitleKey: "dashboard.tile.scan.subtitle", symbol: "qrcode.viewfinder", tint: FacilityTheme.accent) {
                    demo.open(.scan)
                }
                DashboardActionCard(titleKey: "dashboard.action.capture", subtitleKey: "dashboard.action.capture.subtitle", symbol: "square.and.pencil", tint: FacilityTheme.accent) {
                    demo.openManualCapture()
                }
                DashboardActionCard(titleKey: "dashboard.action.drafts", subtitleKey: "dashboard.action.drafts.subtitle", symbol: "tray.and.arrow.down", tint: FacilityTheme.orange) {
                    demo.open(.drafts)
                }
                DashboardActionCard(titleKey: "dashboard.tile.defects", subtitleKey: "dashboard.tile.defects.subtitle", symbol: "exclamationmark.triangle", tint: FacilityTheme.red) {
                    demo.open(.defects)
                }
                DashboardActionCard(titleKey: "dashboard.tile.places", subtitleKey: "dashboard.tile.places.subtitle", symbol: "square.split.2x2", tint: FacilityTheme.accent) {
                    demo.open(.technicalPlaces)
                }
                DashboardActionCard(titleKey: "dashboard.tile.forms", subtitleKey: "dashboard.tile.forms.subtitle", symbol: "doc.text", tint: FacilityTheme.blue) {
                    demo.open(.forms)
                }
            }
        }
    }

    private var latestActivity: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("dashboard.latestActivity")
                .font(.caption.weight(.heavy))
                .foregroundStyle(.secondary)
                .textCase(.uppercase)
                .padding(.bottom, 10)

            if demo.visibleNotifications.isEmpty {
                ContentUnavailableView {
                    Label("sap.cache.empty.title", systemImage: "tray")
                } description: {
                    Text("sap.cache.empty.message")
                }
                .frame(maxWidth: .infinity, minHeight: 170)
            } else {
                ForEach(Array(demo.visibleNotifications.prefix(3).enumerated()), id: \.element.id) { index, notification in
                    Button {
                        demo.selectedNotificationID = notification.id
                        demo.open(.notifications)
                    } label: {
                        NotificationActivityRow(notification: notification)
                    }
                    .buttonStyle(.plain)

                    if index < min(demo.visibleNotifications.count, 3) - 1 {
                        Divider().padding(.leading, 64)
                    }
                }
            }
        }
        .facilityCard()
    }
}

private struct SAPConnectionBadge: View {
    var body: some View {
        Text("sap.connection.connected")
            .font(.subheadline.weight(.bold))
            .foregroundStyle(FacilityTheme.accent)
            .padding(.horizontal, 12)
            .padding(.vertical, 7)
            .background(FacilityTheme.accentSoft, in: Capsule())
            .accessibilityAddTraits(.isStaticText)
    }
}

private struct DashboardActionCard: View {
    let titleKey: String
    let subtitleKey: String
    let symbol: String
    let tint: Color
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 13) {
                Image(systemName: symbol)
                    .font(.title3.weight(.semibold))
                    .foregroundStyle(tint)
                    .frame(width: 44, height: 44)
                    .background(tint.opacity(0.12), in: RoundedRectangle(cornerRadius: 13, style: .continuous))
                Text(LocalizedStringKey(titleKey))
                    .font(.headline)
                    .foregroundStyle(FacilityTheme.ink)
                Text(LocalizedStringKey(subtitleKey))
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.leading)
                    .lineLimit(3)
                Spacer(minLength: 0)
            }
            .frame(maxWidth: .infinity, minHeight: 164, alignment: .leading)
            .facilityCard()
        }
        .buttonStyle(.plain)
    }
}

private struct NotificationActivityRow: View {
    let notification: MaintenanceNotification

    private var tint: Color {
        switch notification.status {
        case .attention: FacilityTheme.red
        case .draft: FacilityTheme.orange
        case .pending, .complete, .closedLocally: FacilityTheme.accent
        case .open: FacilityTheme.blue
        }
    }

    private var symbol: String {
        switch notification.status {
        case .attention: "exclamationmark.triangle.fill"
        case .draft: "tray.and.arrow.down.fill"
        case .pending: "arrow.triangle.2.circlepath"
        case .complete: "checkmark.square.fill"
        case .closedLocally: "checkmark.circle.fill"
        case .open: "checklist"
        }
    }

    private var detail: String {
        [notification.dueDate, notification.id, notification.location]
            .filter { !$0.isEmpty }
            .joined(separator: "  ·  ")
    }

    var body: some View {
        HStack(alignment: .center, spacing: 13) {
            Image(systemName: symbol)
                .foregroundStyle(tint)
                .font(.title3.weight(.semibold))
                .frame(width: 44, height: 44)
                .background(tint.opacity(0.12), in: RoundedRectangle(cornerRadius: 13, style: .continuous))
            VStack(alignment: .leading, spacing: 3) {
                Text(notification.title)
                    .font(.headline)
                    .foregroundStyle(FacilityTheme.ink)
                    .lineLimit(1)
                Text(detail)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            Spacer()
            if let sapStatus = notification.sapStatus, !sapStatus.isEmpty {
                Text(sapStatus)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(FacilityTheme.blue)
                    .lineLimit(1)
            } else {
                StatusPill(status: notification.status)
            }
        }
        .contentShape(Rectangle())
        .padding(.vertical, 8)
    }
}
