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
                PageHeader("dashboard.title", subtitle: "dashboard.context")

                LazyVGrid(columns: metricColumns, spacing: 14) {
                    MetricCard(count: demo.openNotifications, titleKey: "dashboard.metrics.notifications", symbol: "checklist", tint: FacilityTheme.blue) {
                        demo.open(.notifications)
                    }
                    MetricCard(count: demo.defects.count, titleKey: "dashboard.metrics.defects", symbol: "exclamationmark.triangle", tint: FacilityTheme.red) {
                        demo.open(.defects)
                    }
                    MetricCard(count: demo.offlineWorkStore.draftCount, titleKey: "dashboard.metrics.drafts", symbol: "tray.and.arrow.down", tint: FacilityTheme.orange) {
                        demo.open(.drafts)
                    }
                    MetricCard(count: 51, titleKey: "dashboard.metrics.places", symbol: "square.split.2x2", tint: FacilityTheme.accent) {
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

            ReferenceActivityRow(symbol: "checkmark.circle.fill", tint: FacilityTheme.accent, titleKey: "activity.route", detailKey: "activity.route.detail", timeKey: "activity.route.time", status: .complete)
            Divider().padding(.leading, 58)
            ReferenceActivityRow(symbol: "tray.and.arrow.down.fill", tint: FacilityTheme.orange, titleKey: "activity.draft", detailKey: "activity.draft.detail", timeKey: "activity.draft.time", status: .draft)
            Divider().padding(.leading, 58)
            ReferenceActivityRow(symbol: "exclamationmark.triangle.fill", tint: FacilityTheme.red, titleKey: "activity.defect", detailKey: "activity.defect.detail", timeKey: "activity.defect.time", status: .attention)
        }
        .facilityCard()
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

private struct ReferenceActivityRow: View {
    let symbol: String
    let tint: Color
    let titleKey: String
    let detailKey: String
    let timeKey: String
    let status: WorkStatus

    var body: some View {
        HStack(alignment: .center, spacing: 13) {
            Image(systemName: symbol)
                .foregroundStyle(tint)
                .font(.title3)
                .frame(width: 30)
            VStack(alignment: .leading, spacing: 3) {
                Text(LocalizedStringKey(titleKey))
                    .font(.subheadline.weight(.semibold))
                Text(LocalizedStringKey(detailKey))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Text(LocalizedStringKey(timeKey))
                .font(.caption2)
                .foregroundStyle(.tertiary)
            StatusPill(status: status)
        }
        .padding(.vertical, 13)
    }
}
