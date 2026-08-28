import SwiftUI

struct AppRootView: View {
    @State private var phase: AppPhase = .launching
    @State private var onboarding = SAPOnboardingState()
    @State private var demo: FacilityDemoViewModel?

    var body: some View {
        Group {
            switch phase {
            case .launching:
                onboardingContent
            case .ready:
                FacilityHomeView()
            case .demo:
                if let demo {
                    FacilityShellView(demo: demo)
                        .tint(FacilityTheme.accent)
                        .background(FacilityTheme.canvas)
                } else {
                    ProgressView()
                }
            }
        }
        .onChange(of: onboarding.completion) { _, completion in
            guard phase == .launching, let completion else { return }

            switch completion {
            case .authenticated:
                phase = .ready
            case .demo:
                demo = FacilityDemoViewModel()
                phase = .demo
            }
        }
        .animation(.easeInOut(duration: 0.2), value: phase)
    }

    @ViewBuilder
    private var onboardingContent: some View {
        if let errorMessage = onboarding.errorMessage {
            SAPOnboardingErrorView(message: errorMessage, retry: onboarding.retry)
        } else {
            SAPOnboardingContainer(state: onboarding)
        }
    }
}

private struct FacilityHomeView: View {
    var body: some View {
        NavigationSplitView {
            List {
                Label("facility.navigation.overview", systemImage: "rectangle.grid.2x2")
                Label("facility.navigation.notifications", systemImage: "bell")
            }
            .navigationTitle("facility.title")
        } detail: {
            ContentUnavailableView {
                Label("facility.welcome.title", systemImage: "building.2")
            } description: {
                Text("facility.welcome.production")
            }
        }
    }
}
