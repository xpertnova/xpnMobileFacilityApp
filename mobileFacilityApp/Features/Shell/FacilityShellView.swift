import SwiftUI

struct FacilityShellView: View {
    let demo: FacilityDemoViewModel
    @State private var isSidebarVisible = true
    @State private var isSimulatingSync = false
    @State private var didCompleteSyncSimulation = false

    private let expandedSidebarWidth: CGFloat = 340
    private let sidebarAnimation = Animation.easeInOut(duration: 0.42)

    var body: some View {
        @Bindable var demo = demo

        ZStack(alignment: .topLeading) {
            HStack(spacing: 0) {
                sidebar(selection: $demo.selection)
                    .opacity(isSidebarVisible ? 1 : 0)
                    .offset(x: isSidebarVisible ? 0 : -expandedSidebarWidth)
                    .allowsHitTesting(isSidebarVisible)
                    .frame(width: isSidebarVisible ? expandedSidebarWidth : 0, alignment: .leading)
                    .clipped()

                if isSidebarVisible {
                    Divider()
                }

                VStack(spacing: 0) {
                    header
                    Divider()
                    mainContent
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }

            if !isSidebarVisible {
                sidebarToggleButton(symbol: "sidebar.right", labelKey: "sidebar.show") {
                    isSidebarVisible = true
                }
                .padding(.top, 14)
                .padding(.leading, 16)
                .zIndex(1)
            }
        }
        .background(FacilityTheme.canvas)
        .animation(sidebarAnimation, value: isSidebarVisible)
        .simultaneousGesture(
            DragGesture(minimumDistance: 28)
                .onEnded { value in
                    if isSidebarVisible, value.translation.width < -70 {
                        isSidebarVisible = false
                    } else if !isSidebarVisible,
                              value.startLocation.x < 72,
                              value.translation.width > 70 {
                        isSidebarVisible = true
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
                    isSidebarVisible = false
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

            syncStatusCard

            HStack(spacing: 9) {
                Text("AM")
                    .font(.caption.weight(.bold))
                    .foregroundStyle(.white)
                    .frame(width: 32, height: 32)
                    .background(FacilityTheme.accent, in: Circle())
                VStack(alignment: .leading, spacing: 1) {
                    Text("Alex Morgan")
                        .font(.caption.weight(.semibold))
                    Text("Technician")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }
            .padding(.top, 8)
        }
        .padding(16)
        .frame(width: expandedSidebarWidth)
        .background(FacilityTheme.sidebar)
    }

    private var syncStatusCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top) {
                Text("sidebar.localWork.lastSaved")
                    .foregroundStyle(.secondary)
                Spacer()
                Text("sidebar.localWork.lastSaved.value")
                    .fontWeight(.bold)
            }
            .font(.subheadline)

            HStack {
                Text("sidebar.localWork.pending")
                    .foregroundStyle(.secondary)
                Spacer()
                Text("\(demo.drafts.count)")
                    .font(.subheadline.weight(.bold))
            }

            Button(action: simulateSync) {
                HStack(spacing: 9) {
                    if isSimulatingSync {
                        ProgressView()
                            .tint(.white)
                    } else {
                        Image(systemName: didCompleteSyncSimulation ? "checkmark" : "arrow.triangle.2.circlepath")
                    }
                    if isSimulatingSync {
                        Text("sidebar.sync.simulating")
                    } else if didCompleteSyncSimulation {
                        Text("sidebar.sync.complete")
                    } else {
                        Text("sidebar.localWork.review")
                    }
                }
                    .font(.subheadline.weight(.semibold))
                    .frame(maxWidth: .infinity, minHeight: 46)
                    .foregroundStyle(.white)
                    .background(FacilityTheme.navy, in: RoundedRectangle(cornerRadius: 13, style: .continuous))
            }
            .buttonStyle(.plain)
            .disabled(isSimulatingSync)
        }
        .facilityCard(padding: 14)
    }

    private func simulateSync() {
        guard !isSimulatingSync else { return }

        withAnimation(.easeInOut(duration: 0.2)) {
            isSimulatingSync = true
            didCompleteSyncSimulation = false
        }

        Task {
            try? await Task.sleep(nanoseconds: 1_100_000_000)
            guard !Task.isCancelled else { return }
            withAnimation(.easeInOut(duration: 0.2)) {
                isSimulatingSync = false
                didCompleteSyncSimulation = true
            }
        }
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
        case .notifications: demo.openNotifications
        case .defects: demo.defects.count
        case .drafts: demo.drafts.count
        default: nil
        }
    }

    private var header: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text("header.workspace")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Text("header.site")
                    .font(.subheadline.weight(.semibold))
            }
            Spacer()
            DemoBadge()
            Image(systemName: "bell")
                .font(.body.weight(.medium))
                .frame(width: 38, height: 38)
                .background(.white, in: Circle())
                .accessibilityLabel("header.notifications")
        }
        .padding(.leading, isSidebarVisible ? 28 : 82)
        .padding(.trailing, 28)
        .padding(.vertical, 14)
        .background(FacilityTheme.canvas)
    }

    @ViewBuilder
    private var mainContent: some View {
        switch demo.selection {
        case .overview: DashboardView(demo: demo)
        case .scan: ScanView()
        case .notifications: NotificationsView(demo: demo)
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
    }

    private var badgeTint: Color {
        destination == .drafts ? FacilityTheme.orange : FacilityTheme.red
    }
}
