import SwiftUI

struct NotificationsView: View {
    let demo: FacilityDemoViewModel
    @State private var query = ""

    private var visibleNotifications: [MaintenanceNotification] {
        guard !query.isEmpty else { return demo.notifications }
        return demo.notifications.filter {
            $0.title.localizedCaseInsensitiveContains(query) ||
            $0.location.localizedCaseInsensitiveContains(query) ||
            $0.id.localizedCaseInsensitiveContains(query)
        }
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                PageHeader("notifications.title", subtitle: "notifications.subtitle")
                HStack(spacing: 12) {
                    Label("notifications.all", systemImage: "line.3.horizontal.decrease.circle")
                        .font(.subheadline.weight(.semibold))
                        .padding(.horizontal, 12)
                        .padding(.vertical, 8)
                        .background(FacilityTheme.accentSoft, in: Capsule())
                    Spacer()
                    TextField("notifications.search", text: $query)
                        .textFieldStyle(.plain)
                        .padding(.horizontal, 12)
                        .frame(maxWidth: 330, minHeight: 40)
                        .background(.white, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                }

                VStack(spacing: 0) {
                    ForEach(visibleNotifications) { notification in
                        NotificationRow(notification: notification, isSelected: demo.selectedNotificationID == notification.id) {
                            demo.selectedNotificationID = notification.id
                        }
                        if notification.id != visibleNotifications.last?.id { Divider().padding(.leading, 18) }
                    }
                }
                .facilityCard(padding: 0)

                if let notification = demo.selectedNotification {
                    NotificationDetailCard(notification: notification) {
                        demo.finishChecks(for: notification)
                    }
                } else if visibleNotifications.isEmpty {
                    EmptyDemoState(symbol: "magnifyingglass", titleKey: "notifications.empty.title", subtitleKey: "notifications.empty.subtitle")
                }
            }
            .padding(28)
            .frame(maxWidth: 1280, alignment: .leading)
        }
    }
}

private struct NotificationRow: View {
    let notification: MaintenanceNotification
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 14) {
                Image(systemName: notification.status == .attention ? "exclamationmark.triangle.fill" : "checklist")
                    .foregroundStyle(notification.status == .attention ? FacilityTheme.red : FacilityTheme.blue)
                    .frame(width: 38, height: 38)
                    .background((notification.status == .attention ? FacilityTheme.red : FacilityTheme.blue).opacity(0.11), in: RoundedRectangle(cornerRadius: 11, style: .continuous))
                VStack(alignment: .leading, spacing: 4) {
                    Text(notification.title)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(FacilityTheme.ink)
                    Text("\(notification.id) · \(notification.location) · \(notification.equipment)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                VStack(alignment: .trailing, spacing: 6) {
                    StatusPill(status: notification.status)
                    Text("\(notification.completedChecks)/\(notification.totalChecks) · \(notification.dueDate)")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
                Image(systemName: "chevron.right")
                    .font(.caption.weight(.bold))
                    .foregroundStyle(.tertiary)
            }
            .padding(18)
            .background(isSelected ? FacilityTheme.accentSoft.opacity(0.6) : .clear)
        }
        .buttonStyle(.plain)
    }
}

private struct NotificationDetailCard: View {
    let notification: MaintenanceNotification
    let finish: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("notifications.detail.title")
                        .font(.title3.weight(.bold))
                    Text("\(notification.id) · \(notification.location)")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                StatusPill(status: notification.status)
            }
            Divider()
            ForEach(1...notification.totalChecks, id: \.self) { index in
                HStack(spacing: 12) {
                    Image(systemName: index <= notification.completedChecks ? "checkmark.circle.fill" : "circle")
                        .foregroundStyle(index <= notification.completedChecks ? FacilityTheme.accent : .secondary)
                    Text("\(index). \(index == 1 ? "Visual condition and access" : "Equipment inspection point")")
                        .font(.subheadline)
                    Spacer()
                    Text(index <= notification.completedChecks ? "status.complete" : "status.open")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .padding(.vertical, 3)
            }
            HStack {
                Text("notifications.detail.localOnly")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer()
                Button("notifications.detail.finish", action: finish)
                    .buttonStyle(.borderedProminent)
                    .tint(FacilityTheme.accent)
            }
        }
        .facilityCard()
    }
}
