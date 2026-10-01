import SwiftUI

struct AppRootView: View {
    @State private var phase: AppPhase = Self.debugStartsInDemoMode ? .demo : .launching
    @State private var onboarding = SAPOnboardingState()
    @State private var demo: FacilityDemoViewModel? = Self.debugStartsInDemoMode ? Self.makeDemoWorkspace() : nil
    @State private var authenticationWorkspace: FacilityDemoViewModel?
    @State private var productionWorkspace: FacilityDemoViewModel?
    @State private var productionSession: FacilityUserSession?
    @State private var isPreparingProductionWorkspace = false

    var body: some View {
        Group {
            switch phase {
            case .launching:
                onboardingContent
            case .authentication:
                if let authenticationWorkspace {
                    ZStack {
                        // The dimmed workspace behind the login keeps its
                        // keyboard-free size. Otherwise, once the keyboard
                        // leaves less height than the workspace needs, the
                        // stack overflows and is centered, pushing the login
                        // form down behind the keyboard.
                        KeyboardStableContainer(isEnabled: true) {
                            FacilityShellView(demo: authenticationWorkspace)
                        }
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
                        if isPreparingProductionWorkspace {
                            Color.black.opacity(0.25)
                                .ignoresSafeArea()
                            ProgressView()
                                .tint(.white)
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
                    authenticationWorkspace = Self.makeAuthenticationWorkspace()
                    phase = .authentication
                }
            case .demo:
                demo = Self.makeDemoWorkspace()
                phase = .demo
            }
        }
        .animation(.easeInOut(duration: 0.2), value: phase)
        .facilityLayoutRoot()
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
        guard !isPreparingProductionWorkspace else { return }
        isPreparingProductionWorkspace = true
        let workerID = session.workerID
        Task {
            // SQLite opens, legacy schema validation, and directory creation
            // can take long enough to stall the first screen transition.
            let storage = await Task.detached(priority: .userInitiated) {
                ProductionStorage(workerID: workerID)
            }.value
            guard phase == .authentication || phase == .launching else { return }
            productionSession = session
            let sapDataStore = productionSAPDataStore(
                for: session,
                cacheRepository: storage.cacheRepository,
                offlineWorkRepository: storage.offlineWorkRepository,
                photoAttachmentStore: storage.photoAttachmentStore
            )
            productionWorkspace = FacilityDemoViewModel(
                isDemoMode: false,
                offlineWorkStore: OfflineWorkStore(
                    repository: storage.offlineWorkRepository,
                    workerID: workerID
                ),
                sapDataStore: sapDataStore,
                meterReferenceProvider: SAPMeterReferenceProvider(sapDataStore: sapDataStore),
                photoAttachmentStore: storage.photoAttachmentStore,
                documentAttachmentStore: storage.documentAttachmentStore,
                workerDisplayName: session.displayName,
                workerRole: session.role
            )
            isPreparingProductionWorkspace = false
            phase = .ready
        }
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

    /// Debug-only shortcut straight into the demo workspace, skipping SAP
    /// onboarding. It builds exactly the same mock-only workspace as picking
    /// Demo during onboarding, so demo isolation is unchanged. Logout still
    /// returns to onboarding.
    private static var debugStartsInDemoMode: Bool {
        #if DEBUG
        ProcessInfo.processInfo.arguments.contains("-StartInDemoMode")
        #else
        false
        #endif
    }

    /// The dimmed workspace behind the login. Nobody is signed in yet, so it
    /// is mock-only like the demo and never reaches SAP or SQLite.
    static func makeAuthenticationWorkspace() -> FacilityDemoViewModel {
        FacilityDemoViewModel(
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
    }

    static func makeDemoWorkspace() -> FacilityDemoViewModel {
        FacilityDemoViewModel(
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
    }

    private func productionSAPDataStore(
        for session: FacilityUserSession,
        cacheRepository: SQLiteSAPDataCacheRepository?,
        offlineWorkRepository: any OfflineWorkRepository,
        photoAttachmentStore: any PhotoAttachmentStore
    ) -> SAPDataStore {
        if let repository = cacheRepository {
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
                    offlineRepository: offlineWorkRepository,
                    cacheRepository: repository,
                    outgoingStore: repository,
                    photoStore: photoAttachmentStore
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
        } else {
            return SAPDataStore(
                repository: UnavailableSAPDataCacheRepository(),
                refreshService: nil,
                localWorkerID: session.workerID
            )
        }
    }
}

/// Storage is built away from the main actor after authentication. Demo never
/// constructs any of these production repositories.
private struct ProductionStorage: Sendable {
    let offlineWorkRepository: any OfflineWorkRepository
    let photoAttachmentStore: any PhotoAttachmentStore
    let documentAttachmentStore: any DocumentAttachmentStore
    let cacheRepository: SQLiteSAPDataCacheRepository?

    init(workerID: String) {
        if let repository = try? SQLiteOfflineWorkRepository() {
            offlineWorkRepository = repository
        } else {
            offlineWorkRepository = UnavailableOfflineWorkRepository()
        }
        if let store = try? FilePhotoAttachmentStore() {
            photoAttachmentStore = store
        } else {
            photoAttachmentStore = UnavailablePhotoAttachmentStore()
        }
        if let store = try? FileDocumentAttachmentStore() {
            documentAttachmentStore = store
        } else {
            documentAttachmentStore = UnavailableDocumentAttachmentStore()
        }
        cacheRepository = try? SQLiteSAPDataCacheRepository.production(workerID: workerID)
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
