import SwiftUI

struct AppRootView: View {
    let productionOfflineWorkRepository: any OfflineWorkRepository
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
                            enterProductionWorkspace(for: session)
                        }
                    }
                } else {
                    ProgressView()
                }
            case .ready:
                if let productionWorkspace {
                    KeyboardStableContainer(isEnabled: productionWorkspace.suppressesKeyboardAvoidance) {
                        FacilityShellView(
                            demo: productionWorkspace,
                            onLogout: Self.debugLoginBypassSession == nil ? signOut : nil
                        )
                            .tint(FacilityTheme.accent)
                            .background(FacilityTheme.canvas)
                            #if DEBUG
                            .keyboardDebugFrame("root shell suppress=\(productionWorkspace.suppressesKeyboardAvoidance)")
                            #endif
                    }
                } else {
                    ProgressView()
                }
            case .demo:
                if let demo {
                    KeyboardStableContainer(isEnabled: demo.suppressesKeyboardAvoidance) {
                        FacilityShellView(demo: demo, onLogout: exitDemo)
                            .tint(FacilityTheme.accent)
                            .background(FacilityTheme.canvas)
                            #if DEBUG
                            .keyboardDebugFrame("root shell suppress=\(demo.suppressesKeyboardAvoidance)")
                            #endif
                    }
                } else {
                    ProgressView()
                }
            }
        }
        .onChange(of: onboarding.completion) { _, completion in
            guard phase == .launching, let completion else { return }

            switch completion {
            case .authenticated:
                if let testSession = Self.debugLoginBypassSession {
                    enterProductionWorkspace(for: testSession)
                } else {
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
                }
            case .demo:
                demo = Self.makeDemoWorkspace()
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

    private func enterProductionWorkspace(for session: FacilityUserSession) {
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

    private func exitDemo() {
        demo = nil
        onboarding = SAPOnboardingState()
        phase = .launching
    }

    private static var debugLoginBypassSession: FacilityUserSession? {
        #if DEBUG
        guard ProcessInfo.processInfo.arguments.contains("-SkipLoginForTesting") else {
            return nil
        }
        return FacilityUserSession(
            role: .technician,
            workerID: "S50828",
            displayName: "S50828"
        )
        #else
        nil
        #endif
    }

    private static func makeDemoWorkspace() -> FacilityDemoViewModel {
        FacilityDemoViewModel(
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
    }

    private func productionSAPDataStore(for session: FacilityUserSession) -> SAPDataStore {
        do {
            let repository = try SQLiteSAPDataCacheRepository.production(workerID: session.workerID)
            let tokenStore = KeychainSAPSyncTokenStore()
            guard let connection = onboarding.readConnection else {
                return SAPDataStore(
                    repository: UnavailableSAPDataCacheRepository(),
                    refreshService: nil,
                    localWorkerID: session.workerID
                )
            }
            // The confirmed contract uses the worker ID entered at the app
            // login (for example, S50828) for legacy MTFM synchronization.
            // It is distinct from both the display name and the OAuth profile.
            let synchronizationUserID = session.workerID
            let tokenStoreAccountID = SAPSyncTokenScope.account(
                synchronizationUserID: synchronizationUserID,
                landscapeFingerprint: onboarding.landscapeFingerprint ?? "unresolved-landscape"
            )
            let refreshService = SAPInboundNotificationRefreshService(
                connection: connection,
                synchronizationUserID: synchronizationUserID,
                tokenStore: tokenStore,
                tokenStoreAccountID: tokenStoreAccountID,
                synchronizationStore: repository,
                notificationOutgoingCoordinator: SAPNotificationReviewOutgoingCoordinator(
                    workerID: session.workerID,
                    syncUserID: synchronizationUserID,
                    offlineRepository: productionOfflineWorkRepository,
                    cacheRepository: repository,
                    outgoingStore: repository,
                    photoStore: productionPhotoAttachmentStore
                )
            )
            return SAPDataStore(
                repository: repository,
                refreshService: refreshService,
                tokenStore: tokenStore,
                localWorkerID: session.workerID,
                synchronizationUserID: synchronizationUserID,
                tokenStoreAccountID: tokenStoreAccountID
            )
        } catch {
            return SAPDataStore(
                repository: UnavailableSAPDataCacheRepository(),
                refreshService: nil,
                localWorkerID: session.workerID
            )
        }
    }
}

/// Keeps the content at its keyboard-free size and pinned to the top while enabled.
/// `ignoresSafeArea(.keyboard)` directly on the shell is not enough: once the shrunken
/// area is smaller than the shell's minimum height, SwiftUI centers the overflowing shell,
/// which moves the whole screen up. The reader is flexible, so its safe-area expansion
/// works, and the fixed top-aligned frame prevents centering.
private struct KeyboardStableContainer<Content: View>: View {
    let isEnabled: Bool
    @ViewBuilder let content: Content

    var body: some View {
        GeometryReader { proxy in
            content
                .frame(width: proxy.size.width, height: proxy.size.height, alignment: .top)
        }
        .ignoresSafeArea(isEnabled ? .keyboard : [], edges: .bottom)
    }
}
