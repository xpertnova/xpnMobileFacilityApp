import SwiftUI

struct AppRootView: View {
    @State private var phase: AppPhase = .launching
    @State private var onboarding = SAPOnboardingState()
    @State private var demo: FacilityDemoViewModel?
    @State private var productionWorkspace: FacilityDemoViewModel?
    @State private var productionSession: FacilityUserSession?

    var body: some View {
        Group {
            switch phase {
            case .launching:
                onboardingContent
            case .authentication:
                if let productionWorkspace {
                    ZStack {
                        FacilityShellView(demo: productionWorkspace, onSignOut: signOut)
                        Color.black.opacity(0.62)
                            .ignoresSafeArea()
                        RoleSelectionView { role, username in
                            productionSession = FacilityUserSession(role: role, displayName: username)
                            phase = .ready
                        }
                    }
                } else {
                    ProgressView()
                }
            case .ready:
                if let productionWorkspace {
                    FacilityShellView(demo: productionWorkspace, onSignOut: signOut)
                        .tint(FacilityTheme.accent)
                        .background(FacilityTheme.canvas)
                } else {
                    ProgressView()
                }
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
                productionWorkspace = FacilityDemoViewModel(isDemoMode: false)
                phase = .authentication
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

    private func signOut() {
        productionSession = nil
        phase = .authentication
    }
}
