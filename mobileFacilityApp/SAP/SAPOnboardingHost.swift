import Observation
import SAPCommon
import SAPFiori
import SAPFioriFlows
import SAPFoundation
import SwiftUI
import UIKit

@MainActor
@Observable
final class SAPOnboardingState {
    private(set) var completion: SAPOnboardingCompletion?
    private(set) var errorMessage: String?
    private(set) var readConnection: SAPReadConnection?

    func setReadConnection(_ connection: SAPReadConnection) {
        readConnection = connection
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
        controller.onAuthenticatedReadConnection = { connection in
            DispatchQueue.main.async {
                state.setReadConnection(connection)
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

final class SAPOnboardingHostController: UIViewController {
    var onCompletion: ((Result<SAPOnboardingCompletion, Error>) -> Void)?
    var onAuthenticatedReadConnection: ((SAPReadConnection) -> Void)?

    private let presentationDelegate = ModalUIViewControllerPresenter()
    private var onboardingContext: OnboardingContext?
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

        var context = OnboardingContext(presentationDelegate: presentationDelegate)
        onboardingContext = context

        if let savedID = UserDefaults.standard.string(forKey: Self.onboardingIDKey),
           let onboardingID = UUID(uuidString: savedID) {
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
            SAPcpmsSessionConfigurationStep(),
            OAuth2AuthenticationStep(),
            SAPcpmsSettingsDownloadStep(),
            SAPcpmsLogSettingsApplyStep(),
            StoreManagerStep()
        ]
    }

    private func restorationSteps(_ configuration: SAPOnboardingConfiguration) -> [OnboardingStep] {
        [
            StoreManagerStep(),
            welcomeStep(configuration),
            SAPcpmsSessionConfigurationStep(),
            OAuth2AuthenticationStep(),
            SAPcpmsSettingsDownloadStep(),
            SAPcpmsLogSettingsApplyStep()
        ]
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
                            self.onAuthenticatedReadConnection?(connection)
                            UserDefaults.standard.set(context.onboardingID.uuidString, forKey: Self.onboardingIDKey)
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

    private static let onboardingIDKey = "userOnboardingID"
}

private struct SAPOnboardingConfiguration {
    let appID: String
    let authenticationPath: String?

    static func load() -> Self? {
        guard
            let url = Bundle.main.url(forResource: "ConfigurationProvider", withExtension: "plist"),
            let values = NSDictionary(contentsOf: url) as? [String: Any],
            let appID = (values["appId"] as? String) ?? (values["appID"] as? String),
            !appID.isEmpty,
            !appID.hasPrefix("YOUR_"),
            let host = values["host"] as? String,
            !host.isEmpty,
            !host.contains("YOUR_")
        else {
            return nil
        }

        let authenticationPath = (values["authPath"] as? String).flatMap { path in
            path.isEmpty ? nil : path
        }
        return Self(appID: appID, authenticationPath: authenticationPath)
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
