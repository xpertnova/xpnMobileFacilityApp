import SwiftUI

struct FacilityShellView: View {
    let demo: FacilityDemoViewModel
    let onSignOut: (() -> Void)?
    @Environment(\.accessibilityReduceMotion) private var accessibilityReduceMotion
    @State private var sapPassword = ""
    @State private var notificationFilterPresentation = NotificationStructuralFilterPresentationState()

    private let expandedSidebarWidth: CGFloat = 340
    private let sidebarAnimation = Animation.snappy(duration: 0.28, extraBounce: 0)

    init(
        demo: FacilityDemoViewModel,
        onSignOut: (() -> Void)? = nil
    ) {
        self.demo = demo
        self.onSignOut = onSignOut
    }

    var body: some View {
        @Bindable var demo = demo

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
                    mainContent
                        .id(demo.selection)
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
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .animation(
                    accessibilityReduceMotion ? nil : .smooth(duration: 0.24),
                    value: demo.selection
                )
                .animation(
                    accessibilityReduceMotion ? nil : .snappy(duration: 0.32, extraBounce: 0),
                    value: demo.selectedOfflineNotificationDetail
                )
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
                SidebarButton(destination: destination, selection: selection, badge: badge(for: destination))
            }

            Text("navigation.library")
                .font(.caption.weight(.heavy))
                .foregroundStyle(.secondary)
                .tracking(1)
                .padding(.top, 14)
                .padding(.horizontal, 12)
                .padding(.bottom, 4)

            ForEach([AppDestination.technicalPlaces, .forms]) { destination in
                SidebarButton(destination: destination, selection: selection, badge: badge(for: destination))
            }

            Spacer(minLength: 18)

            localWorkStatusCard

            HStack(spacing: 9) {
                Text(demo.workerInitials)
                    .font(.caption.weight(.bold))
                    .foregroundStyle(.white)
                    .frame(width: 32, height: 32)
                    .background(FacilityTheme.accent, in: Circle())
                VStack(alignment: .leading, spacing: 1) {
                    Text(demo.effectiveWorkerDisplayName)
                        .font(.caption.weight(.semibold))
                    Text(LocalizedStringKey(demo.workerRole.titleKey))
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }

                Spacer(minLength: 6)

                if let onSignOut {
                    Button(action: onSignOut) {
                        Text("sidebar.signOut")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(FacilityTheme.accent)
                            .frame(minHeight: 44)
                    }
                    .buttonStyle(.plain)
                    .accessibilityHint(Text("sidebar.signOut.hint"))
                }
            }
            .padding(.top, 8)
        }
        .padding(16)
        .frame(width: expandedSidebarWidth)
        .background(FacilityTheme.sidebar)
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

    @ViewBuilder
    private var mainContent: some View {
        switch demo.selection {
        case .overview: DashboardView(demo: demo)
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
        }
    }
}

private struct SidebarButton: View {
    let destination: AppDestination
    @Binding var selection: AppDestination
    let badge: Int?

    private var isSelected: Bool { selection == destination }

    var body: some View {
        Button {
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
