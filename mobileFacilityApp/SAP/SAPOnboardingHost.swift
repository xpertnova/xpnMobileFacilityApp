import CryptoKit
import Observation
import SAPCommon
import SAPFiori
import SAPFioriFlows
import SAPFoundation
import SwiftUI
import UIKit
import WebKit

@MainActor
@Observable
final class SAPOnboardingState {
    private(set) var completion: SAPOnboardingCompletion?
    private(set) var errorMessage: String?
    private(set) var readConnection: SAPReadConnection?
    private(set) var landscapeFingerprint: String?

    func setAuthenticatedSession(
        connection: SAPReadConnection,
        landscapeFingerprint: String
    ) {
        readConnection = connection
        self.landscapeFingerprint = landscapeFingerprint
    }

    func complete(with completion: SAPOnboardingCompletion) {
        self.completion = completion
        errorMessage = nil
    }

    func fail(_ error: Error) {
        errorMessage = error.localizedDescription
    }

    func retry() {
        completion = nil
        errorMessage = nil
        readConnection = nil
        landscapeFingerprint = nil
    }
}

enum SAPOnboardingCompletion: Equatable {
    case authenticated
    case demo
}

struct SAPOnboardingContainer: UIViewControllerRepresentable {
    let state: SAPOnboardingState

    func makeUIViewController(context: Context) -> SAPOnboardingHostController {
        let controller = SAPOnboardingHostController()
        controller.onCompletion = { result in
            DispatchQueue.main.async {
                switch result {
                case .success(let completion):
                    state.complete(with: completion)
                case .failure(let error):
                    state.fail(error)
                }
            }
        }
        controller.onAuthenticatedSession = { connection, landscapeFingerprint in
            DispatchQueue.main.async {
                state.setAuthenticatedSession(
                    connection: connection,
                    landscapeFingerprint: landscapeFingerprint
                )
            }
        }
        return controller
    }

    func updateUIViewController(_ controller: SAPOnboardingHostController, context: Context) {
        if state.errorMessage == nil {
            controller.startIfNeeded()
        }
    }
}

final class SAPOnboardingHostController: UIViewController, SAPWKNavigationDelegate {
    var onCompletion: ((Result<SAPOnboardingCompletion, Error>) -> Void)?
    var onAuthenticatedSession: ((SAPReadConnection, String) -> Void)?

    private let presentationDelegate = ModalUIViewControllerPresenter()
    private var onboardingContext: OnboardingContext?
    private var activeLandscapeFingerprint: String?
    private var hasStarted = false
    private var hasFinished = false

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .systemBackground
        UINavigationBar.applyFioriStyle()
    }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        startIfNeeded()
    }

    func startIfNeeded() {
        guard !hasStarted else { return }
        hasStarted = true

        guard let configuration = SAPOnboardingConfiguration.load() else {
            finish(.failure(SAPOnboardingError.missingConfiguration))
            return
        }
        activeLandscapeFingerprint = configuration.landscapeFingerprint

        var context = OnboardingContext(presentationDelegate: presentationDelegate)
        onboardingContext = context

        if let onboardingID = SAPOnboardingPersistence.onboardingID(
            for: configuration.landscapeFingerprint
        ) {
            context.onboardingID = onboardingID
            OnboardingFlowController.restore(on: restorationSteps(configuration), context: context) { [weak self] result in
                self?.handle(result)
            }
        } else {
            OnboardingFlowController.onboard(on: onboardingSteps(configuration), context: context) { [weak self] result in
                self?.handle(result)
            }
        }
    }

    private func onboardingSteps(_ configuration: SAPOnboardingConfiguration) -> [OnboardingStep] {
        [
            welcomeStep(configuration),
            CompositeStep(steps: sapConfigurationSteps()),
            SAPcpmsUserBlockedConfigurationStep(userBlockedHandler: { _ in }),
            SAPcpmsUserLockAndWipeConfigurationStep(),
            OAuth2AuthenticationStep(presenter: FioriWKWebViewPresenter(webViewDelegate: self)),
            CompositeStep(steps: SAPcpmsDefaultSteps.settingsDownload),
            CompositeStep(steps: SAPcpmsDefaultSteps.applyDuringOnboard),
            StoreManagerStep()
        ]
    }

    private func restorationSteps(_ configuration: SAPOnboardingConfiguration) -> [OnboardingStep] {
        [
            StoreManagerStep(),
            welcomeStep(configuration),
            CompositeStep(steps: sapConfigurationSteps()),
            SAPcpmsUserBlockedConfigurationStep(userBlockedHandler: { _ in }),
            SAPcpmsUserLockAndWipeConfigurationStep(),
            OAuth2AuthenticationStep(presenter: FioriWKWebViewPresenter(webViewDelegate: self)),
            CompositeStep(steps: SAPcpmsDefaultSteps.settingsDownload),
            CompositeStep(steps: SAPcpmsDefaultSteps.applyDuringRestore)
        ]
    }

    private func sapConfigurationSteps() -> [OnboardingStep] {
        let stepsWithoutDefaultCSRFObserver = SAPcpmsDefaultSteps.configuration.filter {
            !($0 is SAPcpmsCSRFTokenConfigurationStep)
        }
        return stepsWithoutDefaultCSRFObserver + [SAPDataExchangeCSRFTokenConfigurationStep()]
    }

    private func welcomeStep(_ configuration: SAPOnboardingConfiguration) -> WelcomeScreenStep {
        let transformer = DiscoveryServiceConfigurationTransformer(
            applicationID: configuration.appID,
            authenticationPath: configuration.authenticationPath
        )
        let step = WelcomeScreenStep(
            transformer: transformer,
            providers: [FileConfigurationProvider()]
        )
        step.welcomeScreenCustomizationHandler = { welcomeScreen in
            welcomeScreen.isDemoModeAvailable = true
        }
        return step
    }

    private func handle(_ result: OnboardingResult) {
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            switch result {
            case .success(let context):
                Task { [weak self] in
                    do {
                        let connection = try await SAPReadConnection.resolve(from: context)
                        await MainActor.run {
                            guard let self else { return }
                            if let fingerprint = self.activeLandscapeFingerprint {
                                self.onAuthenticatedSession?(connection, fingerprint)
                                SAPOnboardingPersistence.store(
                                    onboardingID: context.onboardingID,
                                    for: fingerprint
                                )
                            }
                            self.finish(.success(.authenticated))
                        }
                    } catch {
                        SAPSynchronizationDiagnostics.logOnboardingIdentityFailure(error)
                        await MainActor.run {
                            self?.finish(.failure(error))
                        }
                    }
                }
            case .failed(let error):
                finish(isDemoModeRequest(error) ? .success(.demo) : .failure(error))
            @unknown default:
                finish(.failure(SAPOnboardingError.unknownResult))
            }
        }
    }

    private func isDemoModeRequest(_ error: Error) -> Bool {
        if let welcomeError = error as? WelcomeScreenError,
           welcomeError == .demoModeRequested {
            return true
        }

        if let onboardingError = error as? OnboardingError,
           case .cancelled(let underlyingError) = onboardingError {
            return isDemoModeRequest(underlyingError)
        }

        return false
    }

    private func finish(_ result: Result<SAPOnboardingCompletion, Error>) {
        guard !hasFinished else { return }
        hasFinished = true
        onCompletion?(result)
    }

    // SAP's OAuth web view can report NSURLErrorCancelled while immediately
    // following an identity-provider redirect. The working QA sample ignores
    // that expected transient navigation failure.
    func webView(_: WKWebView, handleFailed _: WKNavigation!, withError error: Error) -> Error? {
        isCancelledWebNavigation(error) ? nil : error
    }

    func webView(_: WKWebView, handleFailedProvisionalNavigation _: WKNavigation!, withError error: Error) -> Error? {
        isCancelledWebNavigation(error) ? nil : error
    }

    private func isCancelledWebNavigation(_ error: Error) -> Bool {
        let nsError = error as NSError
        return nsError.domain == NSURLErrorDomain && nsError.code == NSURLErrorCancelled
    }
}

private struct SAPOnboardingConfiguration {
    let appID: String
    let authenticationPath: String?
    let landscapeFingerprint: String

    static func load() -> Self? {
        guard
            let url = Bundle.main.url(forResource: "ConfigurationProvider", withExtension: "plist"),
            let values = NSDictionary(contentsOf: url) as? [String: Any],
            let appParameters = loadAppParameters(),
            let appID = (appParameters["Application Identifier"] as? String)
                ?? (values["appId"] as? String)
                ?? (values["appID"] as? String),
            !appID.isEmpty,
            !appID.hasPrefix("YOUR_"),
            let host = values["host"] as? String,
            !host.isEmpty,
            !host.contains("YOUR_")
        else {
            return nil
        }

        let destinations = appParameters["Destinations"] as? [String: Any]
        let baseAuthenticationPath = (destinations?["AuthenticationPath"] as? String)
            ?? (values["authPath"] as? String)
        let authenticationPath = dataExchangeAuthenticationPath(from: baseAuthenticationPath)

        let oauthConfiguration = ((values["auth"] as? [[String: Any]])?.first?["config"] as? [String: Any]) ?? [:]
        let oauthClient = (oauthConfiguration["oauth2.clients"] as? [[String: Any]])?.first ?? [:]
        let fingerprintComponents = [
            values["protocol"] as? String ?? "",
            host,
            String(values["port"] as? Int ?? 0),
            appID,
            authenticationPath ?? "",
            oauthClient["clientID"] as? String ?? "",
            oauthClient["redirectURL"] as? String ?? "",
            oauthConfiguration["oauth2.authorizationEndpoint"] as? String ?? "",
            oauthConfiguration["oauth2.tokenEndpoint"] as? String ?? "",
            oauthConfiguration["oauth2.endUserUI"] as? String ?? ""
        ]
        let fingerprintMaterial = fingerprintComponents.joined(separator: "\u{1F}")
        let digest = SHA256.hash(data: Data(fingerprintMaterial.utf8))
        let landscapeFingerprint = Data(digest).base64EncodedString()

        return Self(
            appID: appID,
            authenticationPath: authenticationPath,
            landscapeFingerprint: landscapeFingerprint
        )
    }

    private static func loadAppParameters() -> [String: Any]? {
        guard
            let url = Bundle.main.url(forResource: "AppParameters", withExtension: "plist"),
            let values = NSDictionary(contentsOf: url) as? [String: Any]
        else {
            return nil
        }
        return values
    }

    /// The confirmed QA flow uses the OData authentication endpoint below the
    /// configured base AuthenticationPath, rather than the base path itself.
    private static func dataExchangeAuthenticationPath(from path: String?) -> String? {
        guard let path = path?.trimmingCharacters(in: .whitespacesAndNewlines), !path.isEmpty else {
            return nil
        }

        let endpoint = "sap/opu/odata/ezo/daex4tu"
        let normalizedPath = path.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        guard !normalizedPath.hasSuffix(endpoint) else {
            return "/" + normalizedPath
        }
        return "/" + normalizedPath + "/" + endpoint
    }
}

enum SAPOnboardingPersistence {
    private static let onboardingIDKey = "userOnboardingID"
    private static let landscapeFingerprintKey = "sapOnboardingLandscapeFingerprint"

    static func onboardingID(
        for landscapeFingerprint: String,
        defaults: UserDefaults = .standard
    ) -> UUID? {
        guard
            let savedID = defaults.string(forKey: onboardingIDKey),
            let onboardingID = UUID(uuidString: savedID),
            defaults.string(forKey: landscapeFingerprintKey) == landscapeFingerprint
        else {
            clear(defaults: defaults)
            return nil
        }
        return onboardingID
    }

    static func store(
        onboardingID: UUID,
        for landscapeFingerprint: String,
        defaults: UserDefaults = .standard
    ) {
        defaults.set(onboardingID.uuidString, forKey: onboardingIDKey)
        defaults.set(landscapeFingerprint, forKey: landscapeFingerprintKey)
    }

    private static func clear(defaults: UserDefaults) {
        defaults.removeObject(forKey: onboardingIDKey)
        defaults.removeObject(forKey: landscapeFingerprintKey)
    }
}

private enum SAPOnboardingError: LocalizedError {
    case missingConfiguration
    case unknownResult

    var errorDescription: String? {
        switch self {
        case .missingConfiguration:
            String(localized: "sap.onboarding.error.configuration")
        case .unknownResult:
            String(localized: "sap.onboarding.error.unknown")
        }
    }
}

struct SAPOnboardingErrorView: View {
    let message: String
    let retry: () -> Void

    var body: some View {
        ContentUnavailableView {
            Label("sap.onboarding.error.title", systemImage: "exclamationmark.triangle")
        } description: {
            Text(message)
        } actions: {
            Button("common.retry", action: retry)
        }
        .padding()
    }
}
