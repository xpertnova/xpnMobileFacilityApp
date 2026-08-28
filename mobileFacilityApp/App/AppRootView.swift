import SwiftUI

struct AppRootView: View {
    @State private var phase: AppPhase = .launching
    @State private var onboarding = SAPOnboardingState()

    var body: some View {
        Group {
            switch phase {
            case .launching:
                onboardingContent
            case .ready:
                FacilityHomeView(isDemo: false)
            case .demo:
                FacilityHomeView(isDemo: true)
            }
        }
        .onChange(of: onboarding.completion) { _, completion in
            guard phase == .launching, let completion else { return }

            switch completion {
            case .authenticated:
                phase = .ready
            case .demo:
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
    let isDemo: Bool

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
                Text(isDemo ? "facility.welcome.demo" : "facility.welcome.production")
            }
        }
    }
}
