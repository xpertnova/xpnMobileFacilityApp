import SwiftUI

struct NotificationsView: View {
    let demo: FacilityDemoViewModel
    @State private var query = ""
    @State private var filterSelection: NotificationFilter = .all
    @State private var lastVisibleNotificationID: String?
    @State private var scrollRestoreID: String?

    private let notificationPrefetchThreshold = 8

    enum NotificationFilter {
        case all, attention, draft
    }

    private var visibleNotifications: [MaintenanceNotification] {
        let filtered = demo.visibleNotifications.filter { notification in
            switch filterSelection {
            case .all: return true
            case .attention: return notification.status == .attention || notification.hasLocalDefect
            case .draft: return notification.status == .draft
            }
        }
        guard !query.isEmpty else { return filtered }
        return filtered.filter {
            $0.title.localizedCaseInsensitiveContains(query) ||
            $0.location.localizedCaseInsensitiveContains(query) ||
            $0.id.localizedCaseInsensitiveContains(query)
        }
    }

    var body: some View {
        ZStack {
            if let selectedSAPNotification = demo.selectedSAPNotification {
                SAPNotificationDetailScreen(
                    summary: selectedSAPNotification,
                    offlineWorkStore: demo.offlineWorkStore,
                    dismiss: { demo.selectedNotificationID = nil }
                )
                .id(selectedSAPNotification.id)
                .transition(.move(edge: .trailing).combined(with: .opacity))
                .zIndex(1)
            } else {
                notificationOverview
                    .transition(.opacity)
            }
        }
        .animation(.snappy(duration: 0.32, extraBounce: 0), value: demo.selectedNotificationID)
    }

    private var notificationOverview: some View {
        VStack(spacing: 0) {
            VStack(alignment: .leading, spacing: 20) {
                PageHeader("notifications.title", subtitle: "notifications.subtitle", trailing: AnyView(headerTrailing))
                searchBar
            }
            .padding(28)
            .frame(maxWidth: 1280, alignment: .leading)
            
            ScrollViewReader { proxy in
                ScrollView {
                    notificationContent
                        .padding(.horizontal, 28)
                        .padding(.bottom, 28)
                        .frame(maxWidth: 1280, alignment: .leading)
                }
                .task(id: scrollRestoreID) {
                    guard let scrollRestoreID else { return }
                    await Task.yield()
                    withAnimation(.snappy(duration: 0.24, extraBounce: 0)) {
                        proxy.scrollTo(scrollRestoreID, anchor: .center)
                    }
                    self.scrollRestoreID = nil
                }
            }
        }
        .background(Color(white: 0.97).ignoresSafeArea())
        .task(id: demo.sapDataStore.localWorkerID) {
            guard !demo.isDemoMode else { return }
            await demo.sapDataStore.loadCachedData()
        }
        .task(id: query) {
            guard !demo.isDemoMode else { return }
            try? await Task.sleep(for: .milliseconds(250))
            guard !Task.isCancelled else { return }
            await demo.sapDataStore.updateNotificationSearch(query)
        }
    }

    @ViewBuilder
    private var headerTrailing: some View {
        Picker("notifications.filter.accessibility", selection: $filterSelection) {
            Text("notifications.filter.all").tag(NotificationFilter.all)
            Text("notifications.filter.attention").tag(NotificationFilter.attention)
            Text("notifications.filter.draft").tag(NotificationFilter.draft)
        }
        .pickerStyle(.segmented)
        .frame(width: 380)
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

    private var searchBar: some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass")
                .foregroundColor(.secondary)
            TextField("notifications.search", text: $query)
                .textFieldStyle(.plain)
        }
        .padding(.horizontal, 12)
        .frame(maxWidth: .infinity, minHeight: 40)
        .background(Color(white: 0.92), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
    }

    private var notificationList: some View {
        LazyVStack(spacing: 16) {
            if visibleNotifications.isEmpty {
                EmptyDemoState(
                    symbol: "tray",
                    titleKey: "notifications.empty.title",
                    subtitleKey: "notifications.empty.subtitle"
                )
            } else {
                ForEach(visibleNotifications) { notification in
                    NotificationRow(notification: notification, isSelected: demo.selectedNotificationID == notification.id) {
                        scrollRestoreID = lastVisibleNotificationID ?? notification.id
                        demo.selectedNotificationID = notification.id
                    }
                    .id(notification.id)
                    .onAppear {
                        lastVisibleNotificationID = notification.id
                        prefetchNextPageIfNeeded(for: notification)
                    }
                }

                if !demo.isDemoMode, demo.sapDataStore.isLoadingMoreNotifications {
                    ProgressView()
                        .controlSize(.small)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 8)
                }
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

    private func prefetchNextPageIfNeeded(for notification: MaintenanceNotification) {
        guard !demo.isDemoMode, demo.sapDataStore.hasMoreNotifications else { return }
        guard let index = visibleNotifications.firstIndex(where: { $0.id == notification.id }) else { return }
        let prefetchStartIndex = max(visibleNotifications.count - notificationPrefetchThreshold, 0)
        guard index >= prefetchStartIndex else { return }

        Task {
            await demo.sapDataStore.loadMoreNotifications()
        }
    }
}

/// Holds the decoded `FELDWERT` detail for the lifetime of one selected
/// notification. Rebuilding it in `NotificationsView.body` made decoding part
/// of unrelated SwiftUI invalidations while the user was reading the checklist.
private struct SAPNotificationDetailScreen: View {
    @State private var detail: SAPNotificationDetail
    let offlineWorkStore: OfflineWorkStore
    let dismiss: () -> Void

    init(
        summary: SAPNotificationSummary,
        offlineWorkStore: OfflineWorkStore,
        dismiss: @escaping () -> Void
    ) {
        _detail = State(initialValue: SAPNotificationDetail(summary: summary))
        self.offlineWorkStore = offlineWorkStore
        self.dismiss = dismiss
    }

    var body: some View {
        NotificationDetailView(detail: detail, offlineWorkStore: offlineWorkStore, dismiss: dismiss)
    }
}

private struct NotificationRow: View {
    let notification: MaintenanceNotification
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(alignment: .top, spacing: 16) {
                let iconConfig = iconFor(status: notification.status)
                
                Image(systemName: iconConfig.name)
                    .foregroundStyle(iconConfig.tint)
                    .frame(width: 44, height: 44)
                    .background(iconConfig.tint.opacity(0.12), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                
                VStack(alignment: .leading, spacing: 10) {
                    Text("\(notification.title) · Meldung \(notification.id.replacingOccurrences(of: "M-", with: "47100000"))")
                        .font(.headline)
                        .foregroundStyle(FacilityTheme.ink)
                    
                    VStack(alignment: .leading, spacing: 6) {
                        Text(notification.equipment)
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                        
                        Text(notification.location)
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                    
                    HStack(alignment: .bottom) {
                        Text(notification.dueDate)
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                        
                        Spacer()
                        
                        Text("KG 300")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(Color.purple)
                            .padding(.horizontal, 9)
                            .padding(.vertical, 5)
                            .background(Color.purple.opacity(0.12), in: Capsule())
                        
                        NotificationStatusBadges(notification: notification)
                        
                        Image(systemName: "chevron.right")
                            .font(.caption.weight(.bold))
                            .foregroundStyle(.tertiary)
                            .padding(.leading, 8)
                    }
                }
            }
            .padding(20)
            .background(.white, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
            .shadow(color: Color.black.opacity(0.04), radius: 8, x: 0, y: 2)
            .overlay(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .stroke(isSelected ? FacilityTheme.accent : Color.clear, lineWidth: 2)
            )
        }
        .buttonStyle(.plain)
    }
    
    private func iconFor(status: WorkStatus) -> (name: String, tint: Color) {
        switch status {
        case .attention:
            return ("exclamationmark.triangle", FacilityTheme.red)
        case .draft:
            return ("floppy.disk", FacilityTheme.orange)
        case .closedLocally:
            return ("checkmark.circle", FacilityTheme.accent)
        default:
            return ("list.clipboard", FacilityTheme.blue)
        }
    }
}

/// Mirrors the legacy overview: a local closure remains visibly local and a
/// defect found during that review stays visible beside it.
private struct NotificationStatusBadges: View {
    let notification: MaintenanceNotification

    var body: some View {
        HStack(spacing: 6) {
            if notification.hasLocalDefect {
                StatusPill(status: .attention)
            }
            StatusPill(status: notification.status)
        }
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
