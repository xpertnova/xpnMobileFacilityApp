import SwiftUI

struct FacilityShellView: View {
    let demo: FacilityDemoViewModel
    let onLogout: (() -> Void)?
    @Environment(\.accessibilityReduceMotion) private var accessibilityReduceMotion
    @Environment(\.scenePhase) private var scenePhase
    @State private var sapPassword = ""
    @State private var notificationFilterPresentation = NotificationStructuralFilterPresentationState()
    @State private var networkReachability = NetworkReachabilityMonitor()
    @State private var isShowingUserMenu = false

    private let expandedSidebarWidth: CGFloat = 340
    private let sidebarAnimation = Animation.snappy(duration: 0.28, extraBounce: 0)

    init(
        demo: FacilityDemoViewModel,
        onLogout: (() -> Void)? = nil
    ) {
        self.demo = demo
        self.onLogout = onLogout
    }

    var body: some View {
        @Bindable var demo = demo
        let networkStatus = networkReachability.status

        ZStack(alignment: .topLeading) {
            HStack(spacing: 0) {
                sidebar(selection: $demo.selection)
                    .opacity(demo.isSidebarVisible ? 1 : 0)
                    .offset(x: demo.isSidebarVisible ? 0 : -expandedSidebarWidth)
                    .allowsHitTesting(demo.isSidebarVisible)
                    .frame(width: demo.isSidebarVisible ? expandedSidebarWidth : 0, alignment: .leading)
                    .clipped()

                if demo.isSidebarVisible {
                    Divider()
                }

                ZStack {
                    mainContent(networkStatus: networkStatus)
                        .id(activeMainDestination)
                        .transition(.opacity)

                    if let selectedOfflineNotificationDetail = demo.selectedOfflineNotificationDetail {
                        NotificationDetailView(
                            detail: selectedOfflineNotificationDetail,
                            offlineWorkStore: demo.offlineWorkStore,
                            backDestination: demo.offlineNotificationDetailReturnDestination,
                            dismiss: { demo.dismissOfflineNotificationDetail() }
                        )
                        .id(selectedOfflineNotificationDetail.summary.id)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .transition(.move(edge: .trailing).combined(with: .opacity))
                        .zIndex(1)
                    }

                    if demo.selection == .profileSettings {
                        ProfileSettingsView(demo: demo)
                            .id("profileSettings")
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                            .transition(.move(edge: .trailing).combined(with: .opacity))
                            .zIndex(2)
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .animation(
                    accessibilityReduceMotion ? nil : .smooth(duration: 0.24),
                    value: activeMainDestination
                )
                .animation(
                    accessibilityReduceMotion ? nil : .snappy(duration: 0.32, extraBounce: 0),
                    value: demo.selectedOfflineNotificationDetail
                )
                .animation(
                    accessibilityReduceMotion ? nil : .snappy(duration: 0.32, extraBounce: 0),
                    value: demo.selection == .profileSettings
                )
            }

            if isShowingUserMenu {
                Color.black.opacity(0.001)
                    .contentShape(Rectangle())
                    .ignoresSafeArea()
                    .padding(.leading, demo.isSidebarVisible ? expandedSidebarWidth : 0)
                    .onTapGesture {
                        withAnimation(.snappy(duration: 0.22, extraBounce: 0)) {
                            isShowingUserMenu = false
                        }
                    }
            }

            if !demo.isSidebarVisible {
                sidebarToggleButton(symbol: "sidebar.right", labelKey: "sidebar.show") {
                    demo.isSidebarVisible = true
                }
                .padding(.top, 14)
                .padding(.leading, 16)
                .zIndex(1)
            }

            if demo.selection == .notifications, notificationFilterPresentation.isPresented {
                NotificationStructuralFilterOverlay(
                    demo: demo,
                    presentation: $notificationFilterPresentation
                )
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .transition(.opacity)
                .zIndex(2)
            }

            if !demo.isDemoMode, demo.shouldPresentSAPRefresh {
                Color.black.opacity(0.42)
                    .ignoresSafeArea()
                    .zIndex(3)
                SAPRefreshPasswordDialog(
                    password: $sapPassword,
                    isRefreshing: demo.sapDataStore.isRefreshing,
                    stage: demo.sapDataStore.refreshStage,
                    error: demo.sapDataStore.refreshError,
                    refresh: refreshSAPData,
                    cancel: dismissSAPRefresh
                )
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .zIndex(4)
            }
        }
        .background(FacilityTheme.canvas)
        .animation(sidebarAnimation, value: demo.isSidebarVisible)
        .task(id: demo.offlineWorkStore.workerID) {
            await demo.offlineWorkStore.load()
            if !demo.isDemoMode {
                await demo.sapDataStore.loadCachedData()
            }
            await demo.technicalPlacesStore.load()
        }
        .task(id: scenePhase) {
            print("[SAP Connection] 📱 App scenePhase changed to: \(scenePhase)")
            guard scenePhase == .active else { return }
            networkReachability.refresh()
        }
        .onAppear {
            networkReachability.start()
        }
        .onDisappear {
            networkReachability.stop()
        }
        .simultaneousGesture(
            DragGesture(minimumDistance: 28)
                .onEnded { value in
                    if demo.isSidebarVisible, value.translation.width < -70 {
                        demo.isSidebarVisible = false
                    } else if !demo.isSidebarVisible,
                              value.startLocation.x < 72,
                              value.translation.width > 70 {
                        demo.isSidebarVisible = true
                    }
                }
        )
    }

    private func sidebar(selection: Binding<AppDestination>) -> some View {
        ZStack(alignment: .bottomLeading) {
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 10) {
                    Text(".XPN")
                        .font(.title3.weight(.heavy))
                        .foregroundStyle(.white)
                        .frame(width: 84, height: 40)
                        .background(FacilityTheme.navy, in: RoundedRectangle(cornerRadius: 13, style: .continuous))
    
                    VStack(alignment: .leading, spacing: 2) {
                        Text("app.title")
                            .font(.headline.weight(.bold))
                        Text("app.subtitle")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(2)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    
                    Spacer()
                    
                    sidebarToggleButton(symbol: "sidebar.left", labelKey: "sidebar.hide") {
                        withAnimation(.snappy(duration: 0.22, extraBounce: 0)) {
                            isShowingUserMenu = false
                        }
                        demo.isSidebarVisible = false
                    }
                }
                .padding(.bottom, 28)

                Text("navigation.work")
                    .font(.caption.weight(.heavy))
                    .foregroundStyle(.secondary)
                    .tracking(1)
                    .padding(.horizontal, 12)
                    .padding(.bottom, 4)

                ForEach([AppDestination.overview, .scan, .notifications, .manualCapture, .defects, .drafts]) { destination in
                    SidebarButton(destination: destination, selection: selection, badge: badge(for: destination)) {
                        withAnimation(.snappy(duration: 0.22, extraBounce: 0)) {
                            isShowingUserMenu = false
                        }
                    }
                }

                Text("navigation.library")
                    .font(.caption.weight(.heavy))
                    .foregroundStyle(.secondary)
                    .tracking(1)
                    .padding(.top, 14)
                    .padding(.horizontal, 12)
                    .padding(.bottom, 4)

                ForEach([AppDestination.technicalPlaces, .forms]) { destination in
                    SidebarButton(destination: destination, selection: selection, badge: badge(for: destination)) {
                        withAnimation(.snappy(duration: 0.22, extraBounce: 0)) {
                            isShowingUserMenu = false
                        }
                    }
                }

                Spacer(minLength: 18)

                localWorkStatusCard

                profileButton
                    .padding(.top, 8)
            }
            .padding(16)
            .frame(width: expandedSidebarWidth)

            if isShowingUserMenu {
                userActionMenu
                    .padding(.horizontal, 16)
                    .padding(.bottom, 76)
                    .transition(.scale(scale: 0.95, anchor: .bottom).combined(with: .opacity))
                    .zIndex(2)
            }
        }
        .frame(width: expandedSidebarWidth)
        .background(FacilityTheme.sidebar)
        .animation(.snappy(duration: 0.22, extraBounce: 0), value: isShowingUserMenu)
    }

    private var profileButton: some View {
        Button {
            withAnimation(.snappy(duration: 0.22, extraBounce: 0)) {
                isShowingUserMenu.toggle()
            }
        } label: {
            HStack(spacing: 9) {
                Text(demo.workerInitials)
                    .font(.caption.weight(.bold))
                    .foregroundStyle(.white)
                    .frame(width: 34, height: 34)
                    .background(FacilityTheme.accent, in: Circle())

                VStack(alignment: .leading, spacing: 1) {
                    Text(demo.effectiveWorkerDisplayName)
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(FacilityTheme.ink)
                    Text(LocalizedStringKey(demo.workerRole.titleKey))
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }

                Spacer(minLength: 6)

                Image(systemName: "chevron.up.chevron.down")
                    .font(.caption2.weight(.bold))
                    .foregroundStyle(.secondary)
                    .accessibilityHidden(true)
            }
            .padding(.horizontal, 10)
            .frame(maxWidth: .infinity, minHeight: 52, alignment: .leading)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .background(
            isShowingUserMenu ? FacilityTheme.surface : Color.clear,
            in: RoundedRectangle(cornerRadius: 14, style: .continuous)
        )
        .accessibilityLabel(Text("profile.menu.accessibilityLabel"))
        .accessibilityHint(Text("profile.menu.accessibilityHint"))
    }

    private var userActionMenu: some View {
        VStack(spacing: 4) {
            userMenuButton(
                titleKey: "profile.menu.settings",
                symbol: "person.crop.circle",
                hintKey: "profile.menu.settings.hint"
            ) {
                withAnimation(.snappy(duration: 0.22, extraBounce: 0)) {
                    isShowingUserMenu = false
                }
                demo.openProfileSettings()
            }

            Divider()
                .padding(.horizontal, 6)

            userMenuButton(
                titleKey: "profile.menu.logout",
                symbol: "rectangle.portrait.and.arrow.right",
                hintKey: "profile.menu.logout.hint",
                tint: FacilityTheme.red
            ) {
                withAnimation(.snappy(duration: 0.22, extraBounce: 0)) {
                    isShowingUserMenu = false
                }
                onLogout?()
            }
            .disabled(onLogout == nil)
        }
        .padding(8)
        .frame(maxWidth: .infinity)
        .background(FacilityTheme.surface, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .stroke(Color.black.opacity(0.09), lineWidth: 1)
        }
        .shadow(color: Color.black.opacity(0.12), radius: 14, x: 0, y: -4)
    }

    private func userMenuButton(
        titleKey: String,
        symbol: String,
        hintKey: String,
        tint: Color = FacilityTheme.ink,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Label(LocalizedStringKey(titleKey), systemImage: symbol)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(tint)
                .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
                .padding(.horizontal, 12)
                .contentShape(Rectangle())
        }
        .buttonStyle(UserMenuButtonStyle())
        .accessibilityHint(Text(LocalizedStringKey(hintKey)))
    }

    private var localWorkStatusCard: some View {
        VStack(alignment: .leading, spacing: 9) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text("sidebar.localWork.lastSaved")
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
                Spacer()
                if let latest = demo.offlineWorkStore.items.first?.updatedAt {
                    Text(latest, format: .dateTime.day().month().hour().minute())
                        .fontWeight(.bold)
                        .multilineTextAlignment(.trailing)
                } else {
                    Text("offline.localWork.none")
                        .fontWeight(.bold)
                        .multilineTextAlignment(.trailing)
                }
            }
            .font(.subheadline)

            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text("sidebar.localWork.pending")
                    .foregroundStyle(.secondary)
                Spacer()
                Text("\(demo.offlineWorkStore.localWorkCount)")
                    .font(.subheadline.weight(.bold))
            }

            if !demo.isDemoMode {
                Button {
                    demo.requestSAPRefresh()
                } label: {
                    Label("sap.refresh.sidebarAction", systemImage: "arrow.triangle.2.circlepath")
                }
                .font(.subheadline.weight(.semibold))
                .frame(maxWidth: .infinity, minHeight: 44)
                .buttonStyle(.plain)
                .foregroundStyle(.white)
                .background(FacilityTheme.navy, in: RoundedRectangle(cornerRadius: 11, style: .continuous))
                .opacity(demo.sapDataStore.isRefreshAvailable && !demo.sapDataStore.isRefreshing ? 1 : 0.45)
                .disabled(!demo.sapDataStore.isRefreshAvailable || demo.sapDataStore.isRefreshing)
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(FacilityTheme.surface, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .stroke(Color.black.opacity(0.12), lineWidth: 1)
        }
    }

    private func refreshSAPData() {
        let password = sapPassword
        Task {
            await demo.sapDataStore.refresh(sapPassword: password)
            sapPassword = ""
            if demo.sapDataStore.refreshError == nil {
                demo.shouldPresentSAPRefresh = false
            }
        }
    }

    private func dismissSAPRefresh() {
        guard !demo.sapDataStore.isRefreshing else { return }
        sapPassword = ""
        demo.sapDataStore.dismissError()
        demo.shouldPresentSAPRefresh = false
    }

    private func sidebarToggleButton(symbol: String, labelKey: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.body.weight(.semibold))
                .foregroundStyle(FacilityTheme.ink)
                .frame(width: 38, height: 38)
                .background(.white, in: Circle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(Text(LocalizedStringKey(labelKey)))
    }

    private func badge(for destination: AppDestination) -> Int? {
        switch destination {
        case .notifications: demo.allNotificationCount
        case .defects: demo.offlineWorkStore.defectCount
        case .drafts: demo.offlineWorkStore.localWorkCount
        default: nil
        }
    }

    private var activeMainDestination: AppDestination {
        demo.selection == .profileSettings ? demo.profileSettingsReturnDestination : demo.selection
    }

    @ViewBuilder
    private func mainContent(networkStatus: NetworkReachabilityStatus) -> some View {
        switch activeMainDestination {
        case .overview: DashboardView(demo: demo, networkStatus: networkStatus)
        case .scan: ScanView()
        case .notifications:
            NotificationsView(
                demo: demo,
                filterPresentation: $notificationFilterPresentation
            )
        case .manualCapture: ManualCaptureView(demo: demo)
        case .defects: DefectsView(demo: demo)
        case .technicalPlaces: TechnicalPlacesView(demo: demo)
        case .forms: FormsView(demo: demo)
        case .drafts: DraftsView(demo: demo)
        case .profileSettings: EmptyView()
        }
    }
}

private struct SidebarButton: View {
    let destination: AppDestination
    @Binding var selection: AppDestination
    let badge: Int?
    var onSelect: (() -> Void)? = nil

    private var isSelected: Bool { selection == destination }

    var body: some View {
        Button {
            onSelect?()
            selection = destination
        } label: {
            HStack(spacing: 12) {
                Image(systemName: destination.symbol)
                    .font(.title3)
                    .frame(width: 26)
                Text(LocalizedStringKey(destination.titleKey))
                    .font(.body.weight(isSelected ? .semibold : .regular))
                Spacer()
                if let badge {
                    Text("\(badge)")
                        .font(.caption2.weight(.bold))
                        .foregroundStyle(isSelected ? FacilityTheme.navy : .white)
                        .padding(.horizontal, 7)
                        .padding(.vertical, 3)
                        .background(isSelected ? .white.opacity(0.85) : badgeTint, in: Capsule())
                }
            }
            .foregroundStyle(isSelected ? .white : FacilityTheme.ink)
            .padding(.horizontal, 12)
            .frame(minHeight: 48)
            .background(isSelected ? FacilityTheme.accent : .clear, in: RoundedRectangle(cornerRadius: 15, style: .continuous))
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
        .animation(.smooth(duration: 0.2), value: isSelected)
    }

    private var badgeTint: Color {
        destination == .drafts ? FacilityTheme.orange : FacilityTheme.red
    }
}

private struct UserMenuButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .background(
                configuration.isPressed ? FacilityTheme.canvas : Color.clear,
                in: RoundedRectangle(cornerRadius: 12, style: .continuous)
            )
    }
}
