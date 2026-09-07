import SwiftUI

struct AppRootView: View {
    let productionOfflineWorkRepository: any OfflineWorkRepository
    let productionSAPDataCacheRepository: any SAPDataCacheRepository
    let productionPhotoAttachmentStore: any PhotoAttachmentStore
    @State private var phase: AppPhase = .launching
    @State private var onboarding = SAPOnboardingState()
    @State private var demo: FacilityDemoViewModel?
    @State private var authenticationWorkspace: FacilityDemoViewModel?
    @State private var productionWorkspace: FacilityDemoViewModel?
    @State private var productionSession: FacilityUserSession?

    var body: some View {
        Group {
            switch phase {
            case .launching:
                onboardingContent
            case .authentication:
                if let authenticationWorkspace {
                    ZStack {
                        FacilityShellView(demo: authenticationWorkspace)
                        Color.black.opacity(0.62)
                            .ignoresSafeArea()
                        RoleSelectionView { role, user in
                            let session = FacilityUserSession(
                                role: role,
                                workerID: user.workerID,
                                displayName: user.displayName
                            )
                            productionSession = session
                            productionWorkspace = FacilityDemoViewModel(
                                isDemoMode: false,
                                offlineWorkStore: OfflineWorkStore(
                                    repository: productionOfflineWorkRepository,
                                    workerID: session.workerID
                                ),
                                sapDataStore: productionSAPDataStore(for: session),
                                meterReferenceProvider: FrontendPreviewMeterReferenceProvider(),
                                photoAttachmentStore: productionPhotoAttachmentStore,
                                workerDisplayName: session.displayName,
                                workerRole: session.role
                            )
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
                authenticationWorkspace = FacilityDemoViewModel(
                    isDemoMode: false,
                    offlineWorkStore: OfflineWorkStore(
                        repository: InMemoryOfflineWorkRepository(),
                        workerID: "unauthenticated"
                    ),
                    sapDataStore: SAPDataStore(
                        repository: InMemorySAPDataCacheRepository(),
                        refreshService: nil,
                        localWorkerID: "unauthenticated"
                    ),
                    meterReferenceProvider: FrontendPreviewMeterReferenceProvider(),
                    photoAttachmentStore: InMemoryPhotoAttachmentStore()
                )
                phase = .authentication
            case .demo:
                demo = FacilityDemoViewModel(
                    isDemoMode: true,
                    offlineWorkStore: OfflineWorkStore(
                        repository: InMemoryOfflineWorkRepository(),
                        workerID: "demo"
                    ),
                    sapDataStore: SAPDataStore(
                        repository: InMemorySAPDataCacheRepository(seed: TechnicalObjectDemoData.cachedData),
                        refreshService: nil,
                        localWorkerID: "demo"
                    ),
                    meterReferenceProvider: DemoMeterReferenceProvider(),
                    photoAttachmentStore: InMemoryPhotoAttachmentStore(),
                    workerDisplayName: "Alex Morgan",
                    workerRole: .technician
                )
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
        productionWorkspace = nil
        phase = .authentication
    }

    private func productionSAPDataStore(for session: FacilityUserSession) -> SAPDataStore {
        let refreshService = onboarding.readConnection.map {
            SAPInboundNotificationRefreshService(
                connection: $0,
                synchronizationUserID: session.displayName
            )
        }
        return SAPDataStore(
            repository: productionSAPDataCacheRepository,
            refreshService: refreshService,
            localWorkerID: session.workerID
        )
    }
}
