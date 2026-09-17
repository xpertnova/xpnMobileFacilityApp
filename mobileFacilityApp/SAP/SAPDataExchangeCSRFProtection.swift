import Foundation
import SAPFioriFlows
import SAPFoundation

enum SAPDataExchangeEndpoint {
    static func configuredServiceRoot(
        backendURL: URL,
        bundle: Bundle = .main
    ) -> URL? {
        guard
            let parametersURL = bundle.url(forResource: "AppParameters", withExtension: "plist"),
            let parametersData = try? Data(contentsOf: parametersURL),
            let parameters = try? PropertyListSerialization.propertyList(
                from: parametersData,
                format: nil
            ) as? [String: Any],
            let destinations = parameters["Destinations"] as? [String: Any],
            let destinationPath = destinations["XPNMTFMODDAEXSRVEntities"] as? String
        else {
            return nil
        }

        return serviceRoot(backendURL: backendURL, destinationPath: destinationPath)
    }

    static func serviceRoot(backendURL: URL, destinationPath: String) -> URL? {
        let normalizedPath = destinationPath.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        guard !normalizedPath.isEmpty else { return nil }
        return backendURL.appendingPathComponent(normalizedPath, isDirectory: true)
    }
}

/// Resolves a CSRF-token endpoint for the authenticated SAP Mobile Services
/// session. DATAEXCHANGE uses its service root; other SDK traffic retains the
/// SDK's normal Mobile Services root behavior.
struct SAPDataExchangeCSRFTokenURLProvider: CSRFTokenURLProviding {
    let mobileServicesRoot: URL
    let dataExchangeServiceRoot: URL?

    func csrfTokenURL(for requestURL: URL) -> URL {
        if let dataExchangeServiceRoot,
           Self.hasSameOrigin(requestURL, mobileServicesRoot),
           Self.isWithin(requestURL, root: dataExchangeServiceRoot) {
            return dataExchangeServiceRoot
        }

        return mobileServicesRoot
    }

    private static func hasSameOrigin(_ lhs: URL, _ rhs: URL) -> Bool {
        lhs.scheme?.lowercased() == rhs.scheme?.lowercased()
            && lhs.host?.lowercased() == rhs.host?.lowercased()
            && normalizedPort(for: lhs) == normalizedPort(for: rhs)
    }

    private static func normalizedPort(for url: URL) -> Int? {
        if let port = url.port { return port }
        switch url.scheme?.lowercased() {
        case "https": return 443
        case "http": return 80
        default: return nil
        }
    }

    private static func isWithin(_ url: URL, root: URL) -> Bool {
        guard hasSameOrigin(url, root) else { return false }
        let rootPath = root.path.hasSuffix("/") ? root.path : root.path + "/"
        return url.path == root.path || url.path.hasPrefix(rootPath)
    }
}

/// Replaces the SDK's default Mobile Services-only CSRF observer with one that
/// also fetches the correct token for the protected DATAEXCHANGE OData route.
final class SAPDataExchangeCSRFTokenConfigurationStep: SAPcpmsCSRFTokenConfigurationStep {
    override func createCSRFTokenObserver(
        settingsParameters: SAPcpmsSettingsParameters
    ) -> CSRFTokenObserver {
        let provider = SAPDataExchangeCSRFTokenURLProvider(
            mobileServicesRoot: settingsParameters.backendURL,
            dataExchangeServiceRoot: SAPDataExchangeEndpoint.configuredServiceRoot(
                backendURL: settingsParameters.backendURL
            )
        )
        return CSRFTokenObserver(tokenUrlProvider: provider)
    }
}
