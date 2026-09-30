import SwiftUI

struct FacilityShellView: View {
    let demo: FacilityDemoViewModel
    let onLogout: (() -> Void)?
    @Environment(\.accessibilityReduceMotion) private var accessibilityReduceMotion
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.facilityLayout) private var layout
    @State private var sapPassword = ""
    @State private var notificationFilterPresentation: NotificationStructuralFilterPresentationState
    @State private var networkReachability = NetworkReachabilityMonitor(startMonitoring: false)
    @State private var hasStartedNetworkMonitoring = false
    @State private var isShowingUserMenu = false

    private let sidebarAnimation = Animation.snappy(duration: 0.28, extraBounce: 0)
    private let workDestinations: [AppDestination] = [
        .overview,
        .scan,
        .notifications,
        .manualCapture,
        .defects,
        .drafts,
    ]
    private let libraryDestinations: [AppDestination] = [
        .technicalPlaces,
        .forms,
    ]

    init(
        demo: FacilityDemoViewModel,
        onLogout: (() -> Void)? = nil
    ) {
        self.demo = demo
        self.onLogout = onLogout
        let restoredFilter = NotificationStructuralFilterPreferences.load(
            workerID: demo.sapDataStore.localWorkerID,
            isDemoMode: demo.isDemoMode
        )
        _notificationFilterPresentation = State(
            initialValue: NotificationStructuralFilterPresentationState(
                restoredFilter: restoredFilter
            )
        )
    }

    var body: some View {
        @Bindable var demo = demo
        let networkStatus = networkReachability.status

        ZStack(alignment: .topLeading) {
            HStack(spacing: 0) {
                Group {
                    if demo.isSidebarExpanded && !layout.overlaysExpandedSidebar {
                        sidebar(selection: $demo.selection)
                            .transition(.opacity)
                    } else {
                        compactSidebar(
                            selection: $demo.selection,
                            networkStatus: networkStatus
                        )
                            .transition(.opacity)
                    }
                }
                .frame(width: dockedSidebarWidth, alignment: .leading)
                .clipped()

                Divider()

                ZStack {
                    mainContent(networkStatus: networkStatus)
                        .id(activeMainDestination)
                        .transition(.opacity)

                    if let selectedOfflineNotificationDetail = demo.selectedOfflineNotificationDetail {
                        if let form = selectedOfflineNotificationDetail.equipmentInspectionForm {
                            EquipmentInspectionView(
                                detail: selectedOfflineNotificationDetail,
                                form: form,
                                offlineWorkStore: demo.offlineWorkStore,
                                photoAttachmentStore: demo.photoAttachmentStore,
                                sapDataStore: demo.sapDataStore,
                                elevatorAssetDataProvider: demo.elevatorAssetDataProvider,
                                backDestination: demo.offlineNotificationDetailReturnDestination,
                                dismiss: { demo.dismissOfflineNotificationDetail() },
                                dismissForMissingMasterData: {
                                    demo.dismissOfflineNotificationDetail(returningTo: .notifications)
                                }
                            )
                            .id(demo.notificationDetailPresentationID)
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                            .transition(.move(edge: .trailing).combined(with: .opacity))
                            .zIndex(1)
                        } else if selectedOfflineNotificationDetail.formCode.uppercased() == "TFM1" {
                            WartungsplanDetailView(
                                detail: selectedOfflineNotificationDetail,
                                offlineWorkStore: demo.offlineWorkStore,
                                photoAttachmentStore: demo.photoAttachmentStore,
                                sapDataStore: demo.sapDataStore,
                                backDestination: demo.offlineNotificationDetailReturnDestination,
                                dismiss: { demo.dismissOfflineNotificationDetail() }
                            )
                            .id(demo.notificationDetailPresentationID)
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                            .transition(.move(edge: .trailing).combined(with: .opacity))
                            .zIndex(1)
                        } else {
                            NotificationDetailView(
                                detail: selectedOfflineNotificationDetail,
                                offlineWorkStore: demo.offlineWorkStore,
                                photoAttachmentStore: demo.photoAttachmentStore,
                                sapDataStore: demo.sapDataStore,
                                backDestination: demo.offlineNotificationDetailReturnDestination,
                                dismiss: { demo.dismissOfflineNotificationDetail() }
                            )
                            .id(demo.notificationDetailPresentationID)
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                            .transition(.move(edge: .trailing).combined(with: .opacity))
                            .zIndex(1)
                        }
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

            if demo.isSidebarExpanded && layout.overlaysExpandedSidebar {
                Color.black.opacity(0.18)
                    .ignoresSafeArea()
                    .onTapGesture {
                        withAnimation(.snappy(duration: 0.22, extraBounce: 0)) {
                            isShowingUserMenu = false
                        }
                        demo.isSidebarExpanded = false
                    }
                    .transition(.opacity)

                sidebar(selection: $demo.selection)
                    .shadow(color: Color.black.opacity(0.18), radius: 20, x: 6)
                    .transition(.move(edge: .leading))
            }

            if isShowingUserMenu {
                Color.black.opacity(0.001)
                    .contentShape(Rectangle())
                    .ignoresSafeArea()
                    .padding(.leading, activeSidebarWidth)
                    .onTapGesture {
                        withAnimation(.snappy(duration: 0.22, extraBounce: 0)) {
                            isShowingUserMenu = false
                        }
                    }
                .zIndex(1)

                userActionMenuOverlay
                    .zIndex(2)
            }

            NotificationStructuralFilterOverlayHost(
                demo: demo,
                presentation: notificationFilterPresentation
            )

            if !demo.isDemoMode, demo.shouldPresentDraftWarningBeforeSync {
                Color.black.opacity(0.42)
                    .ignoresSafeArea()
                    .transition(.opacity)
                    .zIndex(5)
                SAPPreSyncDraftWarningDialog(
                    draftCount: demo.offlineWorkStore.localWorkCount,
                    confirm: demo.confirmDiscardDraftsAndSync,
                    keepDrafts: demo.keepDraftsAndNavigate,
                    cancel: demo.dismissDraftWarning
                )
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .transition(.scale(scale: 0.95).combined(with: .opacity))
                .zIndex(6)
            }

            if !demo.isDemoMode, demo.shouldPresentSAPRefresh {
                Color.black.opacity(0.42)
                    .ignoresSafeArea()
                    .transition(.opacity)
                    .zIndex(3)
                SAPRefreshPasswordDialog(
                    password: $sapPassword,
                    isRefreshing: demo.sapDataStore.isRefreshing,
                    stage: demo.sapDataStore.refreshStage,
                    error: demo.sapDataStore.refreshError,
                    failureContext: demo.sapDataStore.refreshFailureContext,
                    refresh: refreshSAPData,
                    cancel: dismissSAPRefresh
                )
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .transition(.scale(scale: 0.95).combined(with: .opacity))
                .zIndex(4)
            }
        }
        .background(FacilityTheme.canvas)
        .animation(accessibilityReduceMotion ? nil : sidebarAnimation, value: demo.isSidebarExpanded)
        .task(id: demo.offlineWorkStore.workerID) {
            let restoredFilter = NotificationStructuralFilterPreferences.load(
                workerID: demo.sapDataStore.localWorkerID,
                isDemoMode: demo.isDemoMode
            )
            // The three sources are independent, so each dashboard counter
            // arrives when its own source is read. They used to load one after
            // another, and the technical places count waited for the whole
            // notification cache. The offline queue has its own database; the
            // technical places interleave with the notification queries on the
            // cache actor instead of queuing behind all of them.
            async let offlineWork: Void = demo.offlineWorkStore.load()
            async let notificationCache: Void = loadNotificationCache(restoredFilter: restoredFilter)
            async let technicalPlaces: Void = demo.technicalPlacesStore.load()
            _ = await (offlineWork, notificationCache, technicalPlaces)
        }
        .onChange(of: demo.freshDashboardMetrics) { _, _ in
            demo.rememberDashboardMetrics()
        }
        .task(id: scenePhase) {
            // The login backdrop has no refresh service. Its connectivity
            // status is never shown, so it must not run SAP reachability checks
            // while the user is opening the keyboard and entering credentials.
            guard !demo.isDemoMode,
                  demo.sapDataStore.isRefreshAvailable,
                  scenePhase == .active else { return }
            if hasStartedNetworkMonitoring {
                networkReachability.refresh()
            } else {
                // Connectivity checks call SAP and system APIs synchronously.
                // Let the initial shell transition finish before starting them.
                try? await Task.sleep(for: .milliseconds(400))
                guard !Task.isCancelled else { return }
                networkReachability.start()
                hasStartedNetworkMonitoring = true
            }
        }
        .onDisappear {
            guard hasStartedNetworkMonitoring else { return }
            networkReachability.stop()
            hasStartedNetworkMonitoring = false
        }
        .onChange(of: layout.tier, initial: true) { _, tier in
            // A compact window starts with the icon rail so the screen keeps
            // its width; the full sidebar stays one tap or swipe away.
            guard tier == .compact, demo.isSidebarExpanded else { return }
            var transaction = Transaction()
            transaction.disablesAnimations = true
            withTransaction(transaction) {
                demo.isSidebarExpanded = false
            }
        }
        .simultaneousGesture(
            DragGesture(minimumDistance: 28)
                .onEnded { value in
                    if demo.isSidebarExpanded, value.translation.width < -70 {
                        withAnimation(.snappy(duration: 0.22, extraBounce: 0)) {
                            isShowingUserMenu = false
                        }
                        demo.isSidebarExpanded = false
                    } else if !demo.isSidebarExpanded,
                              value.startLocation.x < layout.compactSidebarWidth,
                              value.translation.width > 70 {
                        demo.isSidebarExpanded = true
                    }
                }
        )
    }

    private func sidebar(selection: Binding<AppDestination>) -> some View {
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
                    demo.isSidebarExpanded = false
                }
            }
            .padding(.bottom, layout.sidebarHeaderSpacing)

            // The destinations scroll between the pinned header and the
            // local-work card when the window is too short for all of them,
            // rather than making the whole shell taller than the screen.
            ScrollView(.vertical) {
                VStack(alignment: .leading, spacing: layout.sidebarRowSpacing) {
                    Text("navigation.work")
                        .font(.caption.weight(.heavy))
                        .foregroundStyle(.secondary)
                        .tracking(1)
                        .padding(.horizontal, 12)
                        .padding(.bottom, 4)

                    ForEach(workDestinations) { destination in
                        SidebarButton(
                            destination: destination,
                            selection: selection,
                            badge: badge(for: destination),
                            onSelect: didSelectSidebarDestination
                        )
                    }

                    Text("navigation.library")
                        .font(.caption.weight(.heavy))
                        .foregroundStyle(.secondary)
                        .tracking(1)
                        .padding(.top, 14)
                        .padding(.horizontal, 12)
                        .padding(.bottom, 4)

                    ForEach(libraryDestinations) { destination in
                        SidebarButton(
                            destination: destination,
                            selection: selection,
                            badge: badge(for: destination),
                            onSelect: didSelectSidebarDestination
                        )
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .scrollBounceBehavior(.basedOnSize)

            localWorkStatusCard
                .padding(.top, 22)

            profileButton
                .padding(.top, 8)
        }
        .padding(16)
        .safeAreaPadding(.top, 4)
        .frame(width: layout.expandedSidebarWidth)
        .background(FacilityTheme.sidebar)
        .animation(.snappy(duration: 0.22, extraBounce: 0), value: isShowingUserMenu)
    }

    private func compactSidebar(
        selection: Binding<AppDestination>,
        networkStatus: NetworkReachabilityStatus
    ) -> some View {
        VStack(spacing: 0) {
            sidebarToggleButton(
                symbol: "sidebar.right",
                labelKey: "sidebar.show",
                controlSize: 44
            ) {
                demo.isSidebarExpanded = true
            }
            .padding(.bottom, layout.railSectionSpacing - CompactSidebarButton.badgeOverhang)

            // Same rule as the expanded sidebar: scroll the destinations, not
            // the shell, when the window is too short for all of them.
            ScrollView(.vertical) {
                VStack(spacing: 0) {
                    VStack(spacing: layout.railItemSpacing) {
                        ForEach(workDestinations) { destination in
                            CompactSidebarButton(
                                destination: destination,
                                selection: selection,
                                badge: badge(for: destination)
                            ) {
                                withAnimation(.snappy(duration: 0.22, extraBounce: 0)) {
                                    isShowingUserMenu = false
                                }
                            }
                        }
                    }

                    Divider()
                        .frame(width: 32)
                        .padding(.vertical, layout.railDividerPadding)

                    VStack(spacing: layout.railItemSpacing) {
                        ForEach(libraryDestinations) { destination in
                            CompactSidebarButton(
                                destination: destination,
                                selection: selection,
                                badge: badge(for: destination)
                            ) {
                                withAnimation(.snappy(duration: 0.22, extraBounce: 0)) {
                                    isShowingUserMenu = false
                                }
                            }
                        }
                    }
                }
                // Keeps the first button's badge, which sits above its
                // corner, inside the scroll view's clipping bounds.
                .padding(.top, CompactSidebarButton.badgeOverhang)
                .frame(maxWidth: .infinity)
            }
            .scrollBounceBehavior(.basedOnSize)
            .scrollIndicators(.hidden)
            .padding(.bottom, 12)

            if !demo.isDemoMode {
                Divider()
                    .frame(width: 32)
                    .padding(.bottom, 12)

                compactSAPRefreshButton(networkStatus: networkStatus)
                    .padding(.bottom, 8)
            }

            compactProfileButton
        }
        .padding(.vertical, 14)
        .safeAreaPadding(.top, 4)
        .frame(width: layout.compactSidebarWidth)
        .background(FacilityTheme.sidebar)
    }

    private func compactSAPRefreshButton(networkStatus: NetworkReachabilityStatus) -> some View {
        let isRefreshing = demo.sapDataStore.isRefreshing
        let isEnabled = demo.sapDataStore.isRefreshAvailable && networkStatus == .connected && !isRefreshing

        return Button {
            demo.requestSAPRefresh()
        } label: {
            ZStack {
                if isRefreshing {
                    ProgressView()
                        .controlSize(.small)
                        .tint(FacilityTheme.navy)
                } else {
                    Image(systemName: "arrow.triangle.2.circlepath")
                        .font(.body.weight(.semibold))
                        .foregroundStyle(FacilityTheme.navy)
                }
            }
            .frame(width: 48, height: 48)
            .background(FacilityTheme.surface, in: RoundedRectangle(cornerRadius: 15, style: .continuous))
            .overlay(alignment: .topTrailing) {
                if demo.sapDataStore.refreshError != nil {
                    Circle()
                        .fill(FacilityTheme.red)
                        .frame(width: 11, height: 11)
                        .overlay {
                            Circle()
                                .stroke(FacilityTheme.sidebar, lineWidth: 2)
                        }
                        .offset(x: 3, y: -3)
                }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(!isEnabled)
        .opacity(isEnabled || isRefreshing ? 1 : 0.42)
        .accessibilityLabel(Text("sap.refresh.sidebarAction"))
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

    private var compactProfileButton: some View {
        Button {
            withAnimation(.snappy(duration: 0.22, extraBounce: 0)) {
                isShowingUserMenu.toggle()
            }
        } label: {
            Text(demo.workerInitials)
                .font(.caption.weight(.bold))
                .foregroundStyle(.white)
                .frame(width: 40, height: 40)
                .background(FacilityTheme.accent, in: Circle())
                .frame(width: 52, height: 52)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .background(
            isShowingUserMenu || demo.selection == .profileSettings ? FacilityTheme.surface : Color.clear,
            in: RoundedRectangle(cornerRadius: 15, style: .continuous)
        )
        .accessibilityLabel(Text("profile.menu.accessibilityLabel"))
        .accessibilityHint(Text("profile.menu.accessibilityHint"))
    }

    private var userActionMenuOverlay: some View {
        userActionMenu
            .frame(width: demo.isSidebarExpanded ? layout.expandedSidebarWidth - 32 : 280)
            .padding(.leading, demo.isSidebarExpanded ? 16 : layout.compactSidebarWidth + 8)
            .padding(.bottom, demo.isSidebarExpanded ? 76 : 14)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomLeading)
            .transition(.scale(scale: 0.95, anchor: .bottomLeading).combined(with: .opacity))
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
                if layout.overlaysExpandedSidebar {
                    demo.isSidebarExpanded = false
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
                if let latest = demo.sapDataStore.lastSuccessfulRefreshAt {
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

    /// Production only. Restores the selected filter before the one initial
    /// cache query, rather than loading every notification and immediately
    /// querying the cache again when the notifications view appears.
    private func loadNotificationCache(restoredFilter: NotificationStructuralFilter) async {
        guard !demo.isDemoMode else { return }
        await demo.sapDataStore.updateNotificationStructuralFilter(restoredFilter)
        await demo.sapDataStore.loadCachedData()
    }

    private func refreshSAPData() {
        let password = sapPassword
        Task {
            await demo.sapDataStore.refresh(sapPassword: password)
            sapPassword = ""
            if demo.sapDataStore.refreshError == nil {
                await demo.offlineWorkStore.load()
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

    private func sidebarToggleButton(
        symbol: String,
        labelKey: String,
        controlSize: CGFloat = 38,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.body.weight(.semibold))
                .foregroundStyle(FacilityTheme.ink)
                .frame(width: controlSize, height: controlSize)
                .background(.white, in: Circle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(Text(LocalizedStringKey(labelKey)))
    }

    private func badge(for destination: AppDestination) -> Int? {
        switch destination {
        // Same source as the dashboard cards: known on the first frame from the
        // saved counters, and absent rather than zero while still unknown.
        case .notifications: demo.dashboardMetrics.notifications
        case .defects: demo.dashboardMetrics.defects
        case .drafts: demo.offlineWorkStore.localWorkCount
        default: nil
        }
    }

    private var activeMainDestination: AppDestination {
        demo.selection == .profileSettings ? demo.profileSettingsReturnDestination : demo.selection
    }

    private var activeSidebarWidth: CGFloat {
        demo.isSidebarExpanded ? layout.expandedSidebarWidth : layout.compactSidebarWidth
    }

    /// Width the sidebar takes from the screen. An overlaid full sidebar
    /// leaves the rail's width in place underneath it.
    private var dockedSidebarWidth: CGFloat {
        layout.overlaysExpandedSidebar ? layout.compactSidebarWidth : activeSidebarWidth
    }

    private func didSelectSidebarDestination() {
        withAnimation(.snappy(duration: 0.22, extraBounce: 0)) {
            isShowingUserMenu = false
        }
        // A sidebar laid over the screen has done its job once a
        // destination is picked.
        if layout.overlaysExpandedSidebar {
            demo.isSidebarExpanded = false
        }
    }

    @ViewBuilder
    private func mainContent(networkStatus: NetworkReachabilityStatus) -> some View {
        switch activeMainDestination {
        case .overview: DashboardView(demo: demo, networkStatus: networkStatus)
        case .scan: ScanView(demo: demo)
        case .notifications:
            NotificationsView(
                demo: demo,
                filterPresentation: notificationFilterPresentation
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

private struct CompactSidebarButton: View {
    /// How far the badge reaches above the button's top edge.
    static let badgeOverhang: CGFloat = 5

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
            Image(systemName: destination.symbol)
                .font(.title3)
                .foregroundStyle(isSelected ? .white : FacilityTheme.ink)
                .frame(width: 48, height: 48)
                .background(
                    isSelected ? FacilityTheme.accent : Color.clear,
                    in: RoundedRectangle(cornerRadius: 15, style: .continuous)
                )
                .overlay(alignment: .topTrailing) {
                    if let badge {
                        Text(CompactSidebarBadgeFormatter.text(for: badge))
                            .font(.system(size: 10, weight: .bold))
                            .foregroundStyle(isSelected ? FacilityTheme.navy : .white)
                            .lineLimit(1)
                            .minimumScaleFactor(0.75)
                            .padding(.horizontal, 5)
                            .frame(minWidth: 18, minHeight: 18)
                            .background(isSelected ? .white : badgeTint, in: Capsule())
                            .offset(x: 6, y: -Self.badgeOverhang)
                    }
                }
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .frame(width: 56)
        .frame(minHeight: 48)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text(LocalizedStringKey(destination.titleKey)))
        .accessibilityValue(Text(badge.map { String($0) } ?? ""))
        .accessibilityAddTraits(isSelected ? .isSelected : [])
        .animation(.smooth(duration: 0.2), value: isSelected)
    }

    private var badgeTint: Color {
        destination == .drafts ? FacilityTheme.orange : FacilityTheme.red
    }
}

enum CompactSidebarBadgeFormatter {
    static func text(for count: Int) -> String {
        count > 99 ? "99+" : String(count)
    }
}

private struct SidebarButton: View {
    let destination: AppDestination
    @Binding var selection: AppDestination
    let badge: Int?
    var onSelect: (() -> Void)? = nil
    @Environment(\.facilityLayout) private var layout

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
            .frame(minHeight: layout.sidebarRowMinHeight)
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

#if DEBUG
/// Mock-only workspace for layout previews, built exactly like the demo route.
@MainActor
private func makeLayoutPreviewWorkspace(selection: AppDestination = .overview) -> FacilityDemoViewModel {
    let workspace = FacilityDemoViewModel(
        isDemoMode: true,
        offlineWorkStore: OfflineWorkStore(
            repository: InMemoryOfflineWorkRepository(),
            workerID: "demo"
        ),
        sapDataStore: SAPDataStore(
            repository: InMemorySAPDataCacheRepository(
                seed: TechnicalObjectDemoData.cachedData,
                i2NotificationsByObjectID: I2NotificationDemoData.notificationsByObjectID
            ),
            refreshService: nil,
            localWorkerID: "demo"
        ),
        meterReferenceProvider: DemoMeterReferenceProvider(),
        photoAttachmentStore: InMemoryPhotoAttachmentStore(),
        workerDisplayName: "Alex Morgan",
        workerRole: .technician
    )
    workspace.selection = selection
    return workspace
}

#Preview("iPad mini, landscape", traits: .fixedLayout(width: 1_133, height: 744)) {
    FacilityShellView(demo: makeLayoutPreviewWorkspace())
        .facilityLayoutRoot()
}

#Preview("iPad Pro 13-inch, landscape", traits: .fixedLayout(width: 1_376, height: 1_032)) {
    FacilityShellView(demo: makeLayoutPreviewWorkspace())
        .facilityLayoutRoot()
}

#Preview("Narrowest window", traits: .fixedLayout(width: 700, height: 744)) {
    FacilityShellView(demo: makeLayoutPreviewWorkspace())
        .facilityLayoutRoot()
}

#Preview("Notifications, iPad mini", traits: .fixedLayout(width: 1_133, height: 744)) {
    FacilityShellView(demo: makeLayoutPreviewWorkspace(selection: .notifications))
        .facilityLayoutRoot()
}

#Preview("Notifications, narrowest window", traits: .fixedLayout(width: 700, height: 744)) {
    FacilityShellView(demo: makeLayoutPreviewWorkspace(selection: .notifications))
        .facilityLayoutRoot()
}
#endif
