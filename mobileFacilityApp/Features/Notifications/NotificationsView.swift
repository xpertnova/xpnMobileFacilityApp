import SwiftUI

struct NotificationsView: View {
    let demo: FacilityDemoViewModel
    @State private var query = ""

    private var visibleNotifications: [MaintenanceNotification] {
        let notifications = demo.visibleNotifications
        guard !query.isEmpty else { return notifications }
        return notifications.filter {
            $0.title.localizedCaseInsensitiveContains(query) ||
            $0.location.localizedCaseInsensitiveContains(query) ||
            $0.id.localizedCaseInsensitiveContains(query)
        }
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                PageHeader("notifications.title", subtitle: "notifications.subtitle", trailing: AnyView(refreshControl))
                if !demo.isDemoMode, let lastRefresh = demo.sapDataStore.lastSuccessfulRefreshAt {
                    Label {
                        Text(lastRefresh, format: .dateTime.day().month().year().hour().minute())
                    } icon: {
                        Image(systemName: "arrow.triangle.2.circlepath")
                    }
                    .font(.caption)
                    .foregroundStyle(.secondary)
                }
                notificationContent
            }
            .padding(28)
            .frame(maxWidth: 1280, alignment: .leading)
        }
        .task(id: demo.sapDataStore.localWorkerID) {
            guard !demo.isDemoMode else { return }
            await demo.sapDataStore.loadCachedData()
        }
    }

    @ViewBuilder
    private var refreshControl: some View {
        if !demo.isDemoMode {
            Button(action: demo.requestSAPRefresh) {
                Label("sap.refresh.action", systemImage: "arrow.triangle.2.circlepath")
            }
            .buttonStyle(.borderedProminent)
            .tint(FacilityTheme.accent)
            .disabled(!demo.sapDataStore.isRefreshAvailable || demo.sapDataStore.isRefreshing)
        }
    }

    @ViewBuilder
    private var notificationContent: some View {
        if !demo.isDemoMode, demo.sapDataStore.state == .loadingCache {
            ProgressView("sap.cache.loading")
                .frame(maxWidth: .infinity, minHeight: 260)
        } else if !demo.isDemoMode, demo.sapDataStore.state == .noData {
            sapEmptyState
        } else if !demo.isDemoMode, demo.sapDataStore.state == .failed, !demo.sapDataStore.hasCache {
            sapUnavailableState
        } else {
            notificationList
        }
    }

    private var controls: some View {
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
                .frame(maxWidth: 330, minHeight: 44)
                .background(.white, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        }
    }

    private var notificationList: some View {
        VStack(spacing: 20) {
            controls
            if visibleNotifications.isEmpty {
                EmptyDemoState(
                    symbol: "tray",
                    titleKey: "notifications.empty.title",
                    subtitleKey: "notifications.empty.subtitle"
                )
            } else {
                VStack(spacing: 0) {
                    ForEach(visibleNotifications) { notification in
                        NotificationRow(notification: notification, isSelected: demo.selectedNotificationID == notification.id) {
                            demo.selectedNotificationID = notification.id
                        }
                        if notification.id != visibleNotifications.last?.id { Divider().padding(.leading, 18) }
                    }
                }
                .facilityCard(padding: 0)
            }

            if let notification = demo.selectedNotification {
                NotificationDetailCard(notification: notification, isReadOnly: !demo.isDemoMode) {
                    demo.finishChecks(for: notification)
                }
            }
        }
    }

    private var sapEmptyState: some View {
        ContentUnavailableView {
            Label("sap.cache.empty.title", systemImage: "arrow.down.circle")
        } description: {
            Text("sap.cache.empty.message")
        } actions: {
            Button("sap.refresh.action") {
                demo.requestSAPRefresh()
            }
            .buttonStyle(.borderedProminent)
            .tint(FacilityTheme.accent)
            .disabled(!demo.sapDataStore.isRefreshAvailable)
        }
        .frame(maxWidth: .infinity, minHeight: 260)
    }

    private var sapUnavailableState: some View {
        ContentUnavailableView {
            Label("sap.refresh.error.title", systemImage: "exclamationmark.triangle")
        } description: {
            Text(errorMessage)
        } actions: {
            Button("sap.refresh.action") {
                demo.requestSAPRefresh()
            }
            .buttonStyle(.borderedProminent)
            .tint(FacilityTheme.accent)
            .disabled(!demo.sapDataStore.isRefreshAvailable)
        }
        .frame(maxWidth: .infinity, minHeight: 260)
    }

    private var errorMessage: String {
        sapRefreshErrorMessage(demo.sapDataStore.refreshError)
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
                    Text([notification.id, notification.location, notification.equipment]
                        .filter { !$0.isEmpty }
                        .joined(separator: " · "))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                VStack(alignment: .trailing, spacing: 6) {
                    if let sapStatus = notification.sapStatus, !sapStatus.isEmpty {
                        Text(sapStatus)
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(FacilityTheme.blue)
                            .lineLimit(1)
                    } else {
                        StatusPill(status: notification.status)
                    }
                    if !notification.dueDate.isEmpty {
                        Text(notification.dueDate)
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
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
    let isReadOnly: Bool
    let finish: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("notifications.detail.title")
                        .font(.title3.weight(.bold))
                    Text([notification.id, notification.location].filter { !$0.isEmpty }.joined(separator: " · "))
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                if let sapStatus = notification.sapStatus, !sapStatus.isEmpty {
                    Text(sapStatus)
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(FacilityTheme.blue)
                        .multilineTextAlignment(.trailing)
                } else {
                    StatusPill(status: notification.status)
                }
            }
            Divider()
            if isReadOnly {
                Label("sap.notifications.readOnly", systemImage: "lock")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            } else {
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
        }
        .facilityCard()
    }
}
