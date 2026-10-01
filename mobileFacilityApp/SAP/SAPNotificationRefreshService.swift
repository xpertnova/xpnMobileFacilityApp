import Compression
import Foundation
import SAPFioriFlows
import SAPFoundation
import zlib

enum SAPSynchronizationDiagnostics {
    private static let prefix = "[SAP Sync Debug]"

    static func logResolvedIdentity(
        host: String,
        synchronizationUserID: String,
        onboardingPrincipal: String,
        deviceID: String
    ) {
        print(
            "\(prefix) Resolved legacy synchronization ID from SAP profile ID: " +
                "sync user \(redacted(synchronizationUserID)), " +
                "OAuth principal \(redacted(onboardingPrincipal)), " +
                "registered device \(redactedDeviceID(deviceID)), " +
                "environment \(host)."
        )
    }

    static func logPasswordCheckStarted(
        host: String,
        userID: String,
        deviceID: String
    ) {
        print(
            "\(prefix) Starting M0153003: user \(redacted(userID)), " +
                "device \(redactedDeviceID(deviceID)), " +
                "environment \(host)."
        )
    }

    static func logPasswordAccepted(hasToken: Bool) {
        print("\(prefix) M0153003 accepted credentials; token returned: \(hasToken ? "yes" : "no").")
    }

    static func logPasswordRejected() {
        print("\(prefix) M0153003 rejected the synchronization credentials.")
    }

    static func logInitialPasswordChangeRequired() {
        print("\(prefix) M0153003 requires an initial password change before synchronization.")
    }

    static func logTokenCheckStarted(
        host: String,
        userID: String,
        deviceID: String
    ) {
        print(
            "\(prefix) Starting M0155003: user \(redacted(userID)), " +
                "device \(redactedDeviceID(deviceID)), " +
                "environment \(host)."
        )
    }

    static func logTokenAccepted() {
        print("\(prefix) M0155003 accepted token.")
    }

    static func logTokenRejected() {
        print("\(prefix) M0155003 rejected token (invalid, expired, or active on another device).")
    }

    static func logBackendMessage(method: String, message: String) {
        print("\(prefix) \(method) SAP business response: \(message)")
    }

    static func logUnavailableUser(_ userID: String) {
        print(
            "\(prefix) SAP stopped before password or device validation: " +
                "synchronization user \(redacted(userID)) is missing or inactive."
        )
    }

    static func logRequestFailure(method: String, error: Error) {
        print("\(prefix) \(method) failed: \(error.localizedDescription)")
    }

    /// Produces a support-safe summary for an HTTP error response. In
    /// particular, this must never include the request body, password, OAuth
    /// token, cookie, complete endpoint, or the raw response body.
    static func httpFailureSummary(
        method: String,
        response: HTTPURLResponse,
        responseBody: Data = Data()
    ) -> String {
        var details = ["HTTP \(response.statusCode)"]

        if let correlationID = response.value(forHTTPHeaderField: "X-Correlation-ID")
            ?? response.value(forHTTPHeaderField: "X-CorrelationID")
            ?? response.value(forHTTPHeaderField: "X-Request-ID")
            ?? response.value(forHTTPHeaderField: "X-Vcap-Request-Id"),
           let safeCorrelationID = safeCorrelationID(from: correlationID) {
            details.append("correlation ID=\(safeCorrelationID)")
        }

        if let challenge = response.value(forHTTPHeaderField: "WWW-Authenticate"),
           let scheme = authenticationScheme(from: challenge) {
            details.append("authentication challenge=\(scheme)")
        }

        if let odataError = safeODataErrorSummary(from: responseBody) {
            details.append(odataError)
        }

        let summary = "\(prefix) \(method) received \(details.joined(separator: "; "))"
        return summary.hasSuffix(".") ? summary : summary + "."
    }

    static func logHTTPFailure(
        method: String,
        response: HTTPURLResponse,
        responseBody: Data
    ) {
        print(httpFailureSummary(method: method, response: response, responseBody: responseBody))
    }

    static func logSynchronizationTransport(reusesOnboardingSession: Bool) {
        let mode = reusesOnboardingSession
            ? "Debug transport: reusing the authenticated onboarding session."
            : "Transport: using an isolated copy of the authenticated onboarding session."
        print("\(prefix) \(mode)")
    }

    static func logOnboardingIdentityFailure(_ error: Error) {
        print("\(prefix) Could not resolve the SAP synchronization identity: \(error.localizedDescription)")
    }

    static func logSynchronizationStarted(userID: String) {
        print("\(prefix) Starting production synchronization for user \(redacted(userID)).")
    }

    static func logSynchronizationStep(_ step: String) {
        print("\(prefix) \(step).")
    }

    /// Follows the I2 notifications of one synchronization from the TO
    /// request to the FROM package, so it shows whether SAP created them.
    static func logI2(_ detail: String) {
        print("\(prefix) I2: \(detail)")
    }

    static func logSynchronizationStage(_ stage: Int, _ detail: String) {
        print("\(prefix) Stage \(stage)/5: \(detail).")
    }

    static func logDownloadRequest(
        method: String,
        fromRequestID: String,
        toRequestID: String
    ) {
        let requestIDs = [
            fromRequestID.isEmpty ? nil : "FROM=\(fromRequestID)",
            toRequestID.isEmpty ? nil : "TO=\(toRequestID)"
        ]
        .compactMap { $0 }
        .joined(separator: ", ")
        print("\(prefix) Calling \(method)\(requestIDs.isEmpty ? "" : ": \(requestIDs)").")
    }

    static func logSynchronizationCompleted(_ summary: SAPIncomingCacheSummary) {
        print(
            "\(prefix) Synchronization completed: persisted \(summary.notificationRowCount) notification rows; " +
                "mapped \(summary.actionableNotificationCount) actionable notifications, " +
                "\(summary.businessEntityCount) business entities, and " +
                "\(summary.elevatorInspectionCount) TFM2 elevator inspections."
        )
    }

    static func logElevatorAssetCacheResolution(_ detail: String) {
        print("\(prefix) TFM2 asset cache: \(detail).")
    }

    static func logIncomingPackage(_ tables: [String: [LegacySAPRow]]) {
        let summary = tables
            .map { "\($0.key): \($0.value.count)" }
            .sorted()
            .joined(separator: ", ")
        print("\(prefix) Incoming legacy package tables: \(summary.isEmpty ? "none" : summary).")
    }

    static func logIgnoredColumns(_ columns: Set<String>, table: String) {
        guard !columns.isEmpty else { return }
        print(
            "\(prefix) \(table): ignored server-only columns not present in the legacy schema: " +
                columns.sorted().joined(separator: ", ") + "."
        )
    }

    static func logRejectedColumns(_ columns: Set<String>, table: String) {
        guard !columns.isEmpty else { return }
        print(
            "\(prefix) \(table): rejected columns not present in the legacy schema: " +
                columns.sorted().joined(separator: ", ") + "."
        )
    }

    static func logRejectedValueType(column: String, table: String, type: Any.Type) {
        print("\(prefix) \(table).\(column): rejected non-scalar value type \(type).")
    }

    static func logRejectedStructure(table: String, location: String, type: Any.Type) {
        print("\(prefix) \(table): rejected \(location) structure of type \(type).")
    }

    private static func redacted(_ value: String) -> String {
        guard value.count > 4 else { return "••••" }
        return "\(value.prefix(2))••••\(value.suffix(2))"
    }

    private static func redactedDeviceID(_ value: String) -> String {
        guard value.count > 6 else { return "••••" }
        return "••••\(value.suffix(6))"
    }

    private static func safeCorrelationID(from value: String) -> String? {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, trimmed.count <= 128 else { return nil }
        let allowed = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "-_.:"))
        guard trimmed.unicodeScalars.allSatisfy({ allowed.contains($0) }) else { return nil }
        return trimmed
    }

    private static func authenticationScheme(from value: String) -> String? {
        let scheme = value
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .split(whereSeparator: { $0 == " " || $0 == "," })
            .first
            .map(String.init) ?? ""
        guard !scheme.isEmpty, scheme.count <= 32,
              scheme.unicodeScalars.allSatisfy({ CharacterSet.letters.contains($0) })
        else {
            return nil
        }
        return scheme
    }

    /// Extracts only standard OData error fields. Raw error pages are not
    /// printed: they can contain gateway configuration or sensitive data.
    private static func safeODataErrorSummary(from data: Data) -> String? {
        guard !data.isEmpty, data.count <= 64 * 1024,
              let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let error = root["error"] as? [String: Any]
        else {
            return nil
        }

        let code = safeODataErrorCode(error["code"] as? String)
        let rawMessage: String?
        if let message = error["message"] as? [String: Any] {
            rawMessage = message["value"] as? String
        } else {
            rawMessage = error["message"] as? String
        }
        let message = safeODataErrorMessage(rawMessage)

        switch (code, message) {
        case let (code?, message?):
            return "SAP error code=\(code); SAP reason=\(message)"
        case let (code?, nil):
            return "SAP error code=\(code)"
        case let (nil, message?):
            return "SAP reason=\(message)"
        case (nil, nil):
            return nil
        }
    }

    private static func safeODataErrorCode(_ value: String?) -> String? {
        guard let value else { return nil }
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, trimmed.count <= 128 else { return nil }
        let allowed = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "/_.:-"))
        guard trimmed.unicodeScalars.allSatisfy({ allowed.contains($0) }) else { return nil }
        return trimmed
    }

    private static func safeODataErrorMessage(_ value: String?) -> String? {
        guard let value else { return nil }
        let normalized = value
            .components(separatedBy: .whitespacesAndNewlines)
            .filter { !$0.isEmpty }
            .joined(separator: " ")
        guard !normalized.isEmpty, normalized.count <= 280 else { return nil }

        let lowered = normalized.lowercased()
        let unsafeMarkers = [
            "bearer ", "basic ", "token", "password", "cookie", "authorization:",
            "http://", "https://", "/sap/", "@", "user=", "username=", "device="
        ]
        guard !unsafeMarkers.contains(where: { lowered.contains($0) }) else { return nil }
        return normalized
    }
}
struct SAPReadConnection: @unchecked Sendable {
    let backendURL: URL
    let sapURLSession: SAPURLSession
    let deviceID: String
    private let invalidatesSessionWhenFinished: Bool

    static func resolve(from context: OnboardingContext) async throws -> SAPReadConnection {
        guard
            let settings = context.info[.sapcpmsSettingsParameters] as? SAPcpmsSettingsParameters,
            let deviceID = settings.deviceID?.trimmingCharacters(in: .whitespacesAndNewlines),
            !deviceID.isEmpty
        else {
            throw SAPReadError.authenticatedConnectionUnavailable
        }

        return SAPReadConnection(
            backendURL: settings.backendURL,
            sapURLSession: context.sapURLSession,
            deviceID: deviceID,
            invalidatesSessionWhenFinished: false
        )
    }

    /// Each synchronization gets its own session. The retained onboarding
    /// session remains the authenticated template for a later refresh.
    func newSynchronizationConnection(reusingOnboardingSession: Bool = false) -> SAPReadConnection {
        if reusingOnboardingSession {
            return self
        }
        let synchronizationSession = sapURLSession.copy(
            configuration: sapURLSession.configuration,
            delegate: sapURLSession.delegate,
            delegateQueue: sapURLSession.delegateQueue
        )
        synchronizationSession.sessionDescription = "Mobile Facility SAP refresh"
        return SAPReadConnection(
            backendURL: backendURL,
            sapURLSession: synchronizationSession,
            deviceID: deviceID,
            invalidatesSessionWhenFinished: true
        )
    }

    func finishSynchronizationSession() {
        guard invalidatesSessionWhenFinished else { return }
        sapURLSession.finishTasksAndInvalidate()
    }
}

/// Debug-only transport diagnostics. Do not add passwords, raw request bodies,
/// response payloads, tokens, or complete device/user identifiers here.

struct SAPInboundNotificationRefreshService: SAPNotificationRefreshService {
    private let connection: SAPReadConnection
    private let synchronizationUserID: String
    private let synchronizationStore: any SAPLegacySynchronizationStore
    private let tokenStore: (any SAPSyncTokenStore)?
    private let tokenStoreAccountID: String
    private let outgoingWork: (any SAPOutgoingWorkCoordinating)?

    init(
        connection: SAPReadConnection,
        synchronizationUserID: String,
        tokenStore: (any SAPSyncTokenStore)? = nil,
        tokenStoreAccountID: String? = nil,
        synchronizationStore: any SAPLegacySynchronizationStore,
        notificationOutgoingCoordinator: (any SAPOutgoingWorkCoordinating)? = nil
    ) {
        self.connection = connection
        self.synchronizationUserID = synchronizationUserID
        self.synchronizationStore = synchronizationStore
        self.tokenStore = tokenStore
        self.tokenStoreAccountID = tokenStoreAccountID ?? synchronizationUserID
        self.outgoingWork = notificationOutgoingCoordinator
    }

    private var sapWorkerID: String {
        synchronizationUserID
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .uppercased(with: Locale(identifier: "en_US_POSIX"))
    }

    /// A narrow A/B transport check for diagnosing an OAuth/session failure.
    /// It is available only in Debug builds and must be enabled explicitly in
    /// Xcode with the launch argument `-SAPSyncReuseOnboardingSession`.
    private static var reusesOnboardingSessionForDebugging: Bool {
        #if DEBUG
        ProcessInfo.processInfo.arguments.contains("-SAPSyncReuseOnboardingSession")
        #else
        false
        #endif
    }

    func refresh(
        sapPassword: String,
        progress: @escaping SAPReadRefreshProgressHandler
    ) async throws -> SAPCachedData {
        let password = sapPassword.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !password.isEmpty else { throw SAPReadError.passwordRequired }
        guard !sapWorkerID.isEmpty else { throw SAPReadError.authenticatedConnectionUnavailable }

        let reusesOnboardingSession = Self.reusesOnboardingSessionForDebugging
        let synchronizationConnection = connection.newSynchronizationConnection(
            reusingOnboardingSession: reusesOnboardingSession
        )
        defer { synchronizationConnection.finishSynchronizationSession() }

        SAPSynchronizationDiagnostics.logSynchronizationTransport(
            reusesOnboardingSession: reusesOnboardingSession
        )
        SAPSynchronizationDiagnostics.logSynchronizationStarted(userID: sapWorkerID)
        SAPSynchronizationDiagnostics.logPasswordCheckStarted(
            host: connection.backendURL.host ?? "unknown host",
            userID: sapWorkerID,
            deviceID: synchronizationConnection.deviceID
        )
        await progress(.authenticating)
        let client = SAPLiveLegacyDataExchangeClient(connection: synchronizationConnection, sapWorkerID: sapWorkerID)
        let token = try await verify(password: password, client: client)
        if let token, !token.isEmpty {
            try? tokenStore?.save(token: token, for: tokenStoreAccountID)
        }

        return try await synchronize(client: client, progress: progress)
    }

    func refresh(
        usingToken token: String,
        progress: @escaping SAPReadRefreshProgressHandler
    ) async throws -> SAPCachedData {
        let trimmedToken = token.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedToken.isEmpty else { throw SAPReadError.tokenInvalidOrExpired }
        guard !sapWorkerID.isEmpty else { throw SAPReadError.authenticatedConnectionUnavailable }

        let reusesOnboardingSession = Self.reusesOnboardingSessionForDebugging
        let synchronizationConnection = connection.newSynchronizationConnection(
            reusingOnboardingSession: reusesOnboardingSession
        )
        defer { synchronizationConnection.finishSynchronizationSession() }

        SAPSynchronizationDiagnostics.logSynchronizationTransport(
            reusesOnboardingSession: reusesOnboardingSession
        )
        SAPSynchronizationDiagnostics.logSynchronizationStarted(userID: sapWorkerID)
        SAPSynchronizationDiagnostics.logTokenCheckStarted(
            host: connection.backendURL.host ?? "unknown host",
            userID: sapWorkerID,
            deviceID: synchronizationConnection.deviceID
        )
        await progress(.authenticating)
        let client = SAPLiveLegacyDataExchangeClient(connection: synchronizationConnection, sapWorkerID: sapWorkerID)
        do {
            try await verify(token: trimmedToken, client: client)
        } catch {
            if Self.discardsSavedToken(after: error) {
                tokenStore?.deleteToken(for: tokenStoreAccountID)
            }
            throw error
        }

        return try await synchronize(client: client, progress: progress)
    }

    /// Only SAP's answer that the token is no longer valid ends it. A lost
    /// network, a timeout or an unavailable gateway says nothing about the
    /// token, so it is kept for the next attempt instead of asking for the
    /// SAP password again. HTTP 401/403 are left to `SAPDataStore`.
    static func discardsSavedToken(after error: Error) -> Bool {
        if case SAPReadError.tokenInvalidOrExpired = error { return true }
        return false
    }

    private func synchronize(
        client: SAPLiveLegacyDataExchangeClient,
        progress: @escaping SAPReadRefreshProgressHandler
    ) async throws -> SAPCachedData {
        let lifecycle = SAPLegacySynchronizationLifecycle(
            sapWorkerID: sapWorkerID,
            client: client,
            store: synchronizationStore,
            outgoingWork: outgoingWork
        )
        return try await lifecycle.run(progress: progress)
    }

    private func verify(password: String, client: SAPLiveLegacyDataExchangeClient) async throws -> String? {
        guard let response = try await client.call(
            method: "M0153003",
            parameters: SAPReadParameters(values: [
                "PARAMETER1": sapWorkerID,
                "PARAMETER2": password,
                "PARAMETER3": client.connection.deviceID
            ]),
            usesLegacyAuthenticationEnvelope: true
        ) else {
            throw SAPReadError.malformedPayload
        }
        let authorization: SAPReadAuthorization
        do {
            authorization = try SAPLegacyDataExchangeCodec.authorization(from: response)
        } catch {
            SAPSynchronizationDiagnostics.logRequestFailure(method: "M0153003", error: error)
            throw error
        }
        if authorization.requiresInitialPasswordChange {
            let error = SAPReadError.initialPasswordChangeRequired
            SAPSynchronizationDiagnostics.logInitialPasswordChangeRequired()
            throw error
        }
        guard authorization.isAccepted else {
            let error = SAPReadError.invalidCredentials
            SAPSynchronizationDiagnostics.logPasswordRejected()
            throw error
        }
        SAPSynchronizationDiagnostics.logPasswordAccepted(hasToken: authorization.token != nil)
        return authorization.token
    }

    private func verify(token: String, client: SAPLiveLegacyDataExchangeClient) async throws {
        guard let response = try await client.call(
            method: "M0155003",
            parameters: SAPReadParameters(values: [
                "PARAMETER1": sapWorkerID,
                "PARAMETER2": client.connection.deviceID,
                "PARAMETER3": token
            ]),
            usesLegacyAuthenticationEnvelope: true
        ) else {
            throw SAPReadError.malformedPayload
        }
        let isValid: Bool
        do {
            isValid = try SAPLegacyDataExchangeCodec.tokenAuthorization(from: response)
        } catch {
            SAPSynchronizationDiagnostics.logRequestFailure(method: "M0155003", error: error)
            throw SAPReadError.tokenInvalidOrExpired
        }
        guard isValid else {
            SAPSynchronizationDiagnostics.logTokenRejected()
            throw SAPReadError.tokenInvalidOrExpired
        }
        SAPSynchronizationDiagnostics.logTokenAccepted()
    }
}

/// The `DATAEXCHANGESet` calls of one synchronization session.
private struct SAPLiveLegacyDataExchangeClient: SAPLegacyDataExchangeClient {
    /// The app, build and database version ABAP checks (`gAppVersion`).
    private static let downloadSchemaVersion = "1.3.8-58-358"
    let connection: SAPReadConnection
    let sapWorkerID: String

    func sendOutgoingMetadata(_ payload: LegacySAPOutgoingPayload, requestID: String) async throws {
        do {
            let response = try await call(
                method: "M0002001",
                parameters: SAPReadParameters(values: [
                    "PARAMETER1": sapWorkerID,
                    "PARAMETER2": requestID
                ]),
                synchronizationData: payload,
                responseMayBeEmpty: true
            )
            if let response {
                try SAPLegacyDataExchangeCodec.validateNoBackendError(response)
            }
        } catch let error as SAPReadError {
            // The legacy client lets MMTFM002 establish whether ABAP accepted
            // an M0002001 request whose gateway response timed out.
            guard SAPLegacySynchronizationLifecycle.isTransient(error) else { throw error }
        }
    }

    func sendOutgoingDocument(
        _ document: SAPNotificationOutgoingDocument,
        notificationType: String,
        requestID: String
    ) async throws {
        var row = document.metadata
        row["REQID"] = requestID
        row["FELDWERT"] = document.data.base64EncodedString()
        // A reference row legitimately has no content: SAP resolves the file
        // from its own DMS by `DOKNR`. Every other document without bytes is
        // a lost photo or an unbuilt report and must not reach SAP.
        if !document.referencesExistingDocument {
            guard !row["FELDWERT", default: ""].isEmpty else {
                throw SAPReadError.malformedPayload
            }
        }
        let response = try await call(
            method: "M0002031",
            parameters: SAPReadParameters(values: [
                "PARAMETER1": sapWorkerID,
                "PARAMETER2": requestID,
                "PARAMETER3": notificationType
            ]),
            document: row,
            responseMayBeEmpty: true
        )
        if let response { try SAPLegacyDataExchangeCodec.validateNoBackendError(response) }
    }

    func triggerOutgoingPost(requestID: String) throws {
        try trigger(method: "M0002021", parameters: SAPReadParameters(values: [
            "PARAMETER1": sapWorkerID,
            "PARAMETER2": requestID,
            "PARAMETER3": "D",
            "PARAMETER4": Self.downloadSchemaVersion
        ]))
    }

    func outgoingPostStatus(requestID: String) async throws -> SAPLegacyRequestStatus {
        try await status(method: "MMTFM002", requestID: requestID)
    }

    func clearOutgoingRequest(requestID: String) async throws -> Bool {
        guard let response = try await call(
            method: "MMTFM001",
            parameters: SAPReadParameters(values: [
                "PARAMETER1": sapWorkerID,
                "PARAMETER2": requestID,
                "PARAMETER3": "D"
            ]),
            responseMayBeEmpty: true
        ) else {
            return false
        }
        return try SAPLegacyDataExchangeCodec.lifecycleStatus(from: response) == .completed
    }

    func checkAppVersion(requestID: String) async throws {
        let response = try await call(
            method: "MMTFM008",
            parameters: SAPReadParameters(values: [
                "PARAMETER1": sapWorkerID,
                "PARAMETER2": requestID,
                "PARAMETER3": "D",
                "PARAMETER4": Self.downloadSchemaVersion
            ]),
            responseMayBeEmpty: true
        )
        try SAPLegacyDataExchangeCodec.validateAppVersion(response)
    }

    func prepareIncomingData(fromRequestID: String, toRequestID: String) throws {
        try trigger(method: "MMTFM004", parameters: SAPReadParameters(values: [
            "PARAMETER1": sapWorkerID,
            "PARAMETER2": fromRequestID,
            "PARAMETER3": "D",
            "PARAMETER4": Self.downloadSchemaVersion,
            "PARAMETER5": toRequestID
        ]))
    }

    func incomingPreparationStatus(requestID: String) async throws -> SAPLegacyRequestStatus {
        try await status(method: "MMTFM003", requestID: requestID)
    }

    func incomingPackage(requestID: String) async throws -> LegacySAPIncomingPackage {
        guard let response = try await call(method: "M0002003", parameters: SAPReadParameters(values: [
            "PARAMETER1": sapWorkerID,
            "PARAMETER2": requestID,
            "PARAMETER3": "D"
        ])) else {
            throw SAPReadError.malformedPayload
        }
        return try SAPLegacyDataExchangeCodec.inboundPack(from: response)
    }

    func discardIncomingRequest(requestID: String) async throws {
        let response = try await call(
            method: "MMTFM005",
            parameters: SAPReadParameters(values: [
                "PARAMETER1": sapWorkerID,
                "PARAMETER2": requestID,
                "PARAMETER3": "D"
            ]),
            responseMayBeEmpty: true
        )
        if let response { try SAPLegacyDataExchangeCodec.validateNoBackendError(response) }
    }

    private func status(method: String, requestID: String) async throws -> SAPLegacyRequestStatus {
        guard let response = try await call(method: method, parameters: SAPReadParameters(values: [
            "PARAMETER1": sapWorkerID,
            "PARAMETER2": requestID,
            "PARAMETER3": "D"
        ])) else {
            throw SAPReadError.malformedPayload
        }
        SAPSynchronizationDiagnostics.logSynchronizationStep(
            "\(method) answered: \(SAPLegacyDataExchangeCodec.envelopeSummary(of: response))"
        )
        return try SAPLegacyDataExchangeCodec.lifecycleStatus(from: response)
    }

    /// Starts a long-running ABAP operation without waiting for its response,
    /// as the legacy client does. The MMTFM002 or MMTFM003 check that follows
    /// is the source of truth, so a delayed or empty response is ignored.
    private func trigger(method: String, parameters: SAPReadParameters) throws {
        SAPSynchronizationDiagnostics.logDownloadRequest(
            method: method,
            fromRequestID: method == "MMTFM004" ? parameters.PARAMETER2 : "",
            toRequestID: method == "MMTFM004" ? parameters.PARAMETER5 : parameters.PARAMETER2
        )
        let ivData = try SAPLegacyDataExchangeCodec.pack(method: method, parameters: parameters)
        let request = try dataExchangeRequest(ivData: ivData)
        // Resumed before this returns and independent of the calling task:
        // the session finishes it even when the synchronization stops early,
        // so a trigger SAP may act on is never withdrawn.
        connection.sapURLSession.dataTask(with: request) { data, response, error in
            do {
                if let error { throw error }
                guard let data,
                      let httpResponse = response as? HTTPURLResponse,
                      (200...299).contains(httpResponse.statusCode),
                      !data.isEmpty,
                      let object = try JSONSerialization.jsonObject(with: data) as? [String: Any]
                else { return }
                let payload = (object["d"] as? [String: Any]) ?? object
                let evData = payload["EvData"] as? String ?? ""
                if !evData.isEmpty {
                    try SAPLegacyDataExchangeCodec.validateNoBackendError(evData)
                }
            } catch {
                SAPSynchronizationDiagnostics.logRequestFailure(method: method, error: error)
            }
        }
        .resume()
    }

    func call(
        method: String,
        parameters: SAPReadParameters,
        usesLegacyAuthenticationEnvelope: Bool = false,
        synchronizationData: LegacySAPOutgoingPayload? = nil,
        document: [String: String]? = nil,
        responseMayBeEmpty: Bool = false
    ) async throws -> String? {
        let fromRequestID = ["M0002003", "MMTFM003", "MMTFM005"].contains(method) ? parameters.PARAMETER2 : ""
        let toRequestID = ["M0002001", "MMTFM001", "MMTFM002", "MMTFM008"].contains(method) ? parameters.PARAMETER2 : ""
        if !["M0153003", "M0155003"].contains(method) {
            SAPSynchronizationDiagnostics.logDownloadRequest(method: method, fromRequestID: fromRequestID, toRequestID: toRequestID)
        }

        let ivData: String
        if let document {
            ivData = try SAPLegacyDataExchangeCodec.packDocument(
                method: method, parameters: parameters, document: document
            )
        } else if let synchronizationData {
            ivData = try SAPLegacyDataExchangeCodec.pack(
                method: method,
                parameters: parameters,
                synchronizationData: synchronizationData
            )
        } else if usesLegacyAuthenticationEnvelope {
            ivData = try SAPLegacyDataExchangeCodec.packLegacyAuthentication(method: method, parameters: parameters)
        } else {
            ivData = try SAPLegacyDataExchangeCodec.pack(method: method, parameters: parameters)
        }
        let isAuthentication = (method == "M0153003" || method == "M0155003")
        let timeout: TimeInterval = isAuthentication ? 60 : 300
        let request = try dataExchangeRequest(ivData: ivData, timeoutInterval: timeout)
        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await connection.sapURLSession.data(for: request)
        } catch let error as URLError {
            if error.code == .cancelled || Task.isCancelled { throw CancellationError() }
            switch error.code {
            case .timedOut:
                throw SAPReadError.requestTimedOut
            case .notConnectedToInternet, .networkConnectionLost, .cannotConnectToHost,
                    .cannotFindHost, .dnsLookupFailed:
                throw SAPReadError.networkUnavailable
            default:
                throw SAPReadError.serviceUnavailable
            }
        } catch {
            if error is CancellationError || Task.isCancelled { throw CancellationError() }
            throw SAPReadError.serviceUnavailable
        }
        guard let httpResponse = response as? HTTPURLResponse else {
            throw SAPReadError.serviceUnavailable
        }
        let payload: [String: Any]?
        if let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
            payload = (object["d"] as? [String: Any]) ?? object
        } else {
            payload = nil
        }
        guard (200...299).contains(httpResponse.statusCode) else {
            SAPSynchronizationDiagnostics.logHTTPFailure(
                method: method,
                response: httpResponse,
                responseBody: data
            )
            throw SAPReadError.httpStatus(httpResponse.statusCode)
        }
        guard !data.isEmpty else {
            if responseMayBeEmpty { return nil }
            throw SAPReadError.malformedPayload
        }
        guard let payload else {
            throw SAPReadError.malformedPayload
        }
        guard let evData = payload["EvData"] as? String, !evData.isEmpty else {
            if responseMayBeEmpty { return nil }
            throw SAPReadError.malformedPayload
        }
        return evData
    }

    private func dataExchangeRequest(
        ivData: String,
        timeoutInterval: TimeInterval = 300
    ) throws -> URLRequest {
        guard let serviceRoot = SAPDataExchangeEndpoint.configuredServiceRoot(
            backendURL: connection.backendURL
        ) else {
            throw SAPReadError.configurationUnavailable
        }
        var request = URLRequest(url: serviceRoot.appendingPathComponent("DATAEXCHANGESet"))
        request.httpMethod = "POST"
        request.timeoutInterval = timeoutInterval
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue("X", forHTTPHeaderField: "X-Requested-With")
        let encoder = JSONEncoder()
        encoder.outputFormatting = .withoutEscapingSlashes
        request.httpBody = try encoder.encode(SAPDataExchangeRequest(IvData: ivData, EvData: "", IvKey: false))
        return request
    }
}

private struct SAPDataExchangeRequest: Encodable {
    let IvData: String
    let EvData: String
    let IvKey: Bool
}

private struct SAPReadParameters: Encodable {
    let PARAMETER1: String
    let PARAMETER2: String
    let PARAMETER3: String
    let PARAMETER4: String
    let PARAMETER5: String
    let PARAMETER6: String
    let PARAMETER7: String
    let PARAMETER8: String
    let PARAMETER9: String
    let PARAMETER10: String

    init(values: [String: String]) {
        PARAMETER1 = values["PARAMETER1"] ?? ""
        PARAMETER2 = values["PARAMETER2"] ?? ""
        PARAMETER3 = values["PARAMETER3"] ?? ""
        PARAMETER4 = values["PARAMETER4"] ?? ""
        PARAMETER5 = values["PARAMETER5"] ?? ""
        PARAMETER6 = values["PARAMETER6"] ?? ""
        PARAMETER7 = values["PARAMETER7"] ?? ""
        PARAMETER8 = values["PARAMETER8"] ?? ""
        PARAMETER9 = values["PARAMETER9"] ?? ""
        PARAMETER10 = values["PARAMETER10"] ?? ""
    }
}

struct SAPReadAuthorization {
    let isAccepted: Bool
    let requiresInitialPasswordChange: Bool
    let token: String?
}

enum SAPLegacyDataExchangeCodec {
    private static let parameterStructureName = "/EZO/MTFMS_PARAMETER"
    private static let synchronizationStructureName = "/EZO/MTFMS_IP4SYNCH"
    private static let notificationDocumentStructureName = "/EZO/MTFMT_0282"

    static func cachedNotificationPayload(fromFeldwert feldwert: String) -> [String: Any]? {
        notificationData(fromFeldwert: feldwert)
    }

    /// The long text of a downloaded I2 notification. Its `FELDWERT` holds
    /// the `TLINE` list itself; `select.formatLongText(..., true)` joins every
    /// `TDLINE` without a separator and accepts a plain string as well.
    static func longText(fromFeldwert feldwert: String) -> String {
        switch feldwertValue(from: feldwert) {
        case let text as String:
            return text
        case let lines as [Any]:
            return lines.compactMap { line -> String? in
                // Not trimmed: the lines are joined without a separator, so a
                // blank at a line boundary is the only space between words.
                guard let line = line as? [String: Any],
                      let text = value(named: "TDLINE", in: line) as? String,
                      !text.isEmpty
                else { return nil }
                return text
            }
            .joined()
        default:
            return ""
        }
    }

    static func decodedFeldwertObject(_ feldwert: String) -> [String: Any]? {
        decodedFeldwertObjects(feldwert).first
    }

    static func decodedFeldwertObjects(_ feldwert: String) -> [[String: Any]] {
        let value = feldwertValue(from: feldwert)
        if let object = value as? [String: Any] {
            return [object]
        }
        if let array = value as? [[String: Any]] {
            return array
        }
        if let array = value as? [Any] {
            return array.compactMap { $0 as? [String: Any] }
        }
        return []
    }

    private struct Envelope: Codable {
        let KEY: String
        let PAR: String?
        let VALUE: String
    }

    private struct LegacyEnvelope: Encodable {
        let KEY: String
        let PAR: String
        let VALUE: String
    }

    static func packLegacyAuthentication(method: String, parameters: Encodable) throws -> String {
        try packed(method: method, parameters: parameters)
    }

    static func pack(method: String, parameters: Encodable) throws -> String {
        try packed(method: method, parameters: parameters)
    }

    static func pack(
        method: String,
        parameters: Encodable,
        synchronizationData: Encodable
    ) throws -> String {
        let envelope = [
            LegacyEnvelope(KEY: "METHODNAME", PAR: "", VALUE: method),
            LegacyEnvelope(KEY: "STRUCTURE", PAR: parameterStructureName, VALUE: try jsonString(parameters)),
            LegacyEnvelope(
                KEY: "STRUCTURE",
                PAR: synchronizationStructureName,
                VALUE: try jsonString(synchronizationData)
            )
        ]
        let data = try JSONEncoder().encode(envelope)
        return try rawDeflate(Data(data.base64EncodedString().utf8)).base64EncodedString()
    }

    static func packDocument(
        method: String,
        parameters: Encodable,
        document: Encodable
    ) throws -> String {
        let envelope = [
            LegacyEnvelope(KEY: "METHODNAME", PAR: "", VALUE: method),
            LegacyEnvelope(KEY: "STRUCTURE", PAR: parameterStructureName, VALUE: try jsonString(parameters)),
            LegacyEnvelope(
                KEY: "STRUCTURE", PAR: notificationDocumentStructureName,
                VALUE: try jsonString(document)
            )
        ]
        let data = try JSONEncoder().encode(envelope)
        return try rawDeflate(Data(data.base64EncodedString().utf8)).base64EncodedString()
    }

    static func packedFeldwert(_ object: Any) throws -> String {
        let data = try JSONSerialization.data(withJSONObject: object, options: [.sortedKeys])
        return try rawDeflate(Data(data.base64EncodedString().utf8)).base64EncodedString()
    }

    static func mobileLadderTemplates(
        planRows: [[String: Any]],
        classRows: [[String: Any]],
        equipmentRows: [[String: Any]]
    ) -> [MobileLadderLegacyTemplate] {
        let classRow = classRows.first {
            firstSAPString(["CLASS", "KLASSE"], from: $0).uppercased() == "TFMMOBLEITER"
        }
        let classPayload = classRow.flatMap {
            decodedFeldwertObject(stringValue(value(named: "FELDWERT", in: $0)))
        } ?? [:]
        let classJSON = jsonStringValue(classPayload) ?? "{}"
        let characteristicRows = value(named: "T_CHARA", in: classPayload) as? [[String: Any]] ?? []
        let topLevelValues = value(named: "T_CHARVAL", in: classPayload) as? [[String: Any]] ?? []
        let characteristics = characteristicRows.enumerated().compactMap { index, row -> MobileLadderLegacyCharacteristic? in
            let name = firstSAPString(["ATNAM", "CHARACTERISTIC"], from: row)
            guard !name.isEmpty else { return nil }
            // SAP delivers each value list inside its characteristic, which
            // `_buildHeaderForm` reads as `fieldRow.T_CHARVAL`. A class-level
            // list filtered by `ATNAM` is only a fallback.
            let nestedValues = value(named: "T_CHARVAL", in: row) as? [[String: Any]] ?? []
            let valueRows = nestedValues.isEmpty
                ? topLevelValues.filter { firstSAPString(["ATNAM", "CHARACTERISTIC"], from: $0) == name }
                : nestedValues
            let values = valueRows.compactMap { value -> MobileLadderLegacyValue? in
                let code = firstSAPString(["ATWRT", "VALUE"], from: value)
                guard !code.isEmpty else { return nil }
                let title = firstSAPString(["ATWTB", "VALUE_TEXT"], from: value)
                return MobileLadderLegacyValue(value: code, title: title.isEmpty ? code : title)
            }
            return MobileLadderLegacyCharacteristic(
                position: Int(firstSAPString(["POSNR", "ATINN"], from: row)) ?? index,
                name: name, title: firstSAPString(["ATBEZ", "TITLE"], from: row),
                unit: firstSAPString(["MSEHI", "UNIT"], from: row),
                required: firstSAPString(["ATERF", "PFLICHT", "REQUIRED"], from: row).uppercased() == "X",
                values: values
            )
        }

        let equipmentPayload = equipmentRows.compactMap { row -> [String: Any]? in
            guard let decoded = feldwertValue(
                from: stringValue(value(named: "FELDWERT", in: row))
            ) as? [String: Any] else { return nil }
            let type = firstSAPString(["EQART", "EQART_TO"], from: row, fallback: decoded)
            return type.uppercased() == "TFMLEITERN" ? decoded : nil
        }.first ?? [:]
        let equipmentJSON = jsonStringValue(equipmentPayload) ?? "{}"

        return planRows.compactMap { row in
            guard let decoded = feldwertValue(
                from: stringValue(value(named: "FELDWERT", in: row))
            ) else { return nil }
            let payload = decoded as? [String: Any] ?? [:]
            let rawPositions = (value(named: "T_PLPOD", in: payload) as? [Any]) ?? (decoded as? [Any]) ?? []
            let equipmentType = firstSAPString(["EQART"], from: row, fallback: payload)
            guard equipmentType.uppercased() == "TFMLEITERN" else { return nil }
            let positions = rawPositions.compactMap { raw -> MobileLadderLegacyInspectionDefinition? in
                guard let position = raw as? [String: Any] else { return nil }
                let rowType = firstSAPString(["USR00", "DNAME"], from: position).uppercased()
                guard rowType.isEmpty || rowType == "POSITION" else { return nil }
                let form = firstSAPString(["STEUS"], from: position)
                let operation = firstSAPString(["VORNR"], from: position)
                guard !form.isEmpty, !operation.isEmpty else { return nil }
                return MobileLadderLegacyInspectionDefinition(
                    operation: operation,
                    title: firstSAPString(["LTXA1", "KTEX1"], from: position),
                    information: firstSAPString(["LTXA2"], from: position),
                    resultElementID: "\(form)-\(operation)-1",
                    actionElementID: "\(form)-\(operation)-2",
                    commentElementID: "\(form)-\(operation)-9B"
                )
            }
            guard let first = positions.first else { return nil }
            let formCode = first.resultElementID.split(separator: "-", maxSplits: 1).first.map(String.init) ?? ""
            let planType = firstSAPString(["PLNTY"], from: row, fallback: payload)
            let planNumber = firstSAPString(["PLNNR"], from: row, fallback: payload)
            let planVersion = firstSAPString(["PLNAL", "ZAEHL"], from: row, fallback: payload)
            return MobileLadderLegacyTemplate(
                id: [equipmentType, planType, planNumber, planVersion].joined(separator: "|"),
                equipmentType: equipmentType, formCode: formCode, planType: planType,
                planNumber: planNumber, planVersion: planVersion,
                title: firstSAPString(["KTEXT", "PLANTEXT", "LTXA1"], from: row, fallback: payload),
                plant: firstSAPString(["IWERK"], from: row, fallback: payload),
                plannerGroup: firstSAPString(["INGRP"], from: row, fallback: payload),
                workCenter: firstSAPString(["GEWRK", "ARBPL"], from: row, fallback: payload),
                className: firstSAPString(["CLASS", "KLASSE"], from: classRow ?? [:], fallback: classPayload).ifEmpty("TFMMOBLEITER"),
                classType: firstSAPString(["KLART"], from: classRow ?? [:], fallback: classPayload).ifEmpty("002"),
                classGroup: firstSAPString(["KLAGR"], from: classPayload).ifEmpty("TFM"),
                classDataJSON: classJSON, equipmentDataJSON: equipmentJSON,
                characteristics: characteristics, inspectionItems: positions
            )
        }
    }

    /// Decodes the TFM7 schema as delivered by SAP. Unlike the historical
    /// Cordova screen, this returns no static field/value fallback: a missing
    /// plan, class or value-help means the caller presents "unavailable".
    ///
    /// The legacy source named `TFM7_001` as the plan, but the synchronized
    /// SAP payload identifies valid TFM7 plans by their equipment type, plan
    /// type and position form (`STEUS`). The actual plan number is retained
    /// with the draft and used again for the outgoing package.
    static func subdistributionTemplates(
        planRows: [[String: Any]],
        classRows: [[String: Any]],
        equipmentRows: [[String: Any]]
    ) -> [SubdistributionLegacyTemplate] {
        let allowedTypes = Set(["TFMNSPV"])
        let classDefinition = classRows.lazy.compactMap { row -> (row: [String: Any], payload: [String: Any])? in
            guard let payload = firstDictionary(in: feldwertValue(
                from: stringValue(value(named: "FELDWERT", in: row))
            )) else { return nil }
            let type = firstSAPString(["EQART", "EQART_TO"], from: row, fallback: payload).uppercased()
            let name = firstSAPString(["CLASS", "KLASSE"], from: row, fallback: payload).uppercased()
            guard allowedTypes.contains(type) || name.contains("UNTERVERT") else { return nil }
            return (row, payload)
        }.first
        guard let classDefinition else { return [] }
        let classRow = classDefinition.row
        let classPayload = classDefinition.payload

        let classJSON = jsonStringValue(classPayload) ?? "{}"
        let characteristicRows = value(named: "T_CHARA", in: classPayload) as? [[String: Any]] ?? []
        let topLevelValues = value(named: "T_CHARVAL", in: classPayload) as? [[String: Any]] ?? []
        let characteristics = characteristicRows.enumerated().compactMap { index, row -> SubdistributionCharacteristic? in
            let name = firstSAPString(["ATNAM", "CHARACTERISTIC"], from: row)
            guard !name.isEmpty else { return nil }
            // As for TFM5: SAP nests each value list in its characteristic
            // (`fieldRow.T_CHARVAL`); a class-level list is only a fallback.
            let nestedValues = value(named: "T_CHARVAL", in: row) as? [[String: Any]] ?? []
            let valueRows = nestedValues.isEmpty
                ? topLevelValues.filter { firstSAPString(["ATNAM", "CHARACTERISTIC"], from: $0) == name }
                : nestedValues
            let values = valueRows.compactMap { value -> SubdistributionValue? in
                let code = firstSAPString(["ATWRT", "VALUE"], from: value)
                guard !code.isEmpty else { return nil }
                let title = firstSAPString(["ATWTB", "VALUE_TEXT"], from: value)
                return SubdistributionValue(value: code, title: title.isEmpty ? code : title)
            }
            let dataType = firstSAPString(["ATFOR", "DATA_TYPE"], from: row).uppercased()
            let kind: SubdistributionCharacteristicKind = !values.isEmpty ? .choice : (dataType == "NUM" ? .numeric : .text)
            return SubdistributionCharacteristic(
                // `_buildHeaderForm` sorts by `POSNR`; `ATINN` is SAP's
                // internal characteristic number.
                position: Int(firstSAPString(["POSNR", "ATINN"], from: row)) ?? index,
                name: name, title: firstSAPString(["ATBEZ", "TITLE"], from: row), kind: kind,
                maximumLength: Int(firstSAPString(["ANZST", "LENGTH"], from: row)) ?? 0,
                unit: firstSAPString(["MSEHI", "UNIT"], from: row),
                required: ["X", "1", "TRUE"].contains(firstSAPString(["ATERF", "PFLICHT", "REQUIRED"], from: row).uppercased()),
                values: values
            )
        }.sorted { $0.position < $1.position }
        guard !characteristics.isEmpty,
              characteristics.contains(where: {
                  $0.name.caseInsensitiveCompare("TFMUNTERVERT_BEZUNTERVERT") == .orderedSame
                      || $0.name.caseInsensitiveCompare("TFMSCHUTZSCH_UNTERVERTEILUNG") == .orderedSame
              })
        else { return [] }

        let equipmentPayload = equipmentRows.compactMap { row -> [String: Any]? in
            let key = firstSAPString(["LKEY"], from: row).uppercased()
            let parameter = firstSAPString(["LPAR"], from: row).uppercased()
            guard key == "EQUIPMENT" || parameter == "EQUIPMENT" else { return nil }
            return firstDictionary(in: feldwertValue(
                from: stringValue(value(named: "FELDWERT", in: row))
            ))
        }.first
        guard let equipmentPayload else { return [] }
        let equipmentJSON = jsonStringValue(equipmentPayload) ?? "{}"

        return planRows.compactMap { row -> SubdistributionLegacyTemplate? in
            guard let decoded = feldwertValue(
                from: stringValue(value(named: "FELDWERT", in: row))
            ) else { return nil }
            let payload = decoded as? [String: Any] ?? [:]
            let equipmentType = firstSAPString(["EQART"], from: row, fallback: payload).uppercased()
            let planType = firstSAPString(["PLNTY"], from: row, fallback: payload)
            let planNumber = firstSAPString(["PLNNR"], from: row, fallback: payload)
            guard equipmentType == "TFMNSPV", planType == "A", !planNumber.isEmpty else { return nil }
            let rawPositions = (value(named: "T_PLPOD", in: payload) as? [Any]) ?? (decoded as? [Any]) ?? []
            let positions = rawPositions.compactMap { raw -> SubdistributionInspectionDefinition? in
                guard let position = raw as? [String: Any] else { return nil }
                let rowType = firstSAPString(["USR00", "DNAME"], from: position).uppercased()
                guard rowType.isEmpty || rowType == "POSITION" || rowType == "FOTO" else { return nil }
                let form = firstSAPString(["STEUS"], from: position)
                let operation = firstSAPString(["VORNR"], from: position)
                guard form == "TFM7", !operation.isEmpty else { return nil }
                let properties = value(named: "T_PROPS", in: position) as? [Any] ?? []
                func options(at index: Int) -> [SubdistributionValue] {
                    guard properties.indices.contains(index), let property = properties[index] as? [String: Any] else { return [] }
                    let keys = semicolonSeparatedValues(stringValue(value(named: "DFVAL", in: property)))
                    let titles = semicolonSeparatedValues(stringValue(value(named: "DFVAL_TXT", in: property)))
                    return keys.enumerated().compactMap { offset, rawValue in
                        let value = rawValue.trimmingCharacters(in: .whitespacesAndNewlines)
                        guard !value.isEmpty else { return nil }
                        let title = titles.indices.contains(offset) ? titles[offset].trimmingCharacters(in: .whitespacesAndNewlines) : ""
                        return SubdistributionValue(value: value, title: title.isEmpty ? value : title)
                    }
                }
                let isPhotoPosition = rowType == "FOTO"
                let results = isPhotoPosition ? [] : options(at: 0)
                let actions = isPhotoPosition ? [] : options(at: 1)
                return SubdistributionInspectionDefinition(
                    operation: operation, title: firstSAPString(["LTXA1", "KTEX1"], from: position),
                    information: firstSAPString(["LTXA2"], from: position),
                    resultElementID: "TFM7-\(operation)-1", actionElementID: "TFM7-\(operation)-2",
                    commentElementID: "TFM7-\(operation)-9B", resultValues: results, actionValues: actions,
                    requiresResult: !results.isEmpty,
                    requiresPhotoAndComment: isPhotoPosition
                )
            }.sorted { $0.operation < $1.operation }
            // A TFM7 plan without result value-help cannot safely offer the
            // "Alles OK" action, and is therefore unavailable in production.
            guard positions.contains(where: \.requiresResult),
                  positions.filter(\.requiresResult).allSatisfy({
                      $0.resultValues.contains(where: { $0.value == "1" })
                  })
            else { return nil }
            let formCode = "TFM7"
            let planVersion = firstSAPString(["PLNAL", "ZAEHL"], from: row, fallback: payload)
            return SubdistributionLegacyTemplate(
                id: [equipmentType, planType, planNumber, planVersion].joined(separator: "|"),
                equipmentType: equipmentType, formCode: formCode, planType: planType, planNumber: planNumber,
                planVersion: planVersion, title: firstSAPString(["KTEXT", "PLANTEXT", "LTXA1"], from: row, fallback: payload),
                plant: firstSAPString(["IWERK"], from: row, fallback: payload),
                plannerGroup: firstSAPString(["INGRP"], from: row, fallback: payload),
                workCenter: firstSAPString(["GEWRK", "ARBPL"], from: row, fallback: payload),
                className: firstSAPString(["CLASS", "KLASSE"], from: classRow, fallback: classPayload),
                classType: firstSAPString(["KLART"], from: classRow, fallback: classPayload),
                classGroup: firstSAPString(["KLAGR"], from: classPayload),
                classDataJSON: classJSON, equipmentDataJSON: equipmentJSON,
                characteristics: characteristics, inspectionItems: positions
            )
        }
    }

    private static func firstDictionary(in value: Any?) -> [String: Any]? {
        if let dictionary = value as? [String: Any] { return dictionary }
        return (value as? [Any])?.first { $0 is [String: Any] } as? [String: Any]
    }

    private static func packed(method: String, parameters: Encodable) throws -> String {
        let envelope = [
            LegacyEnvelope(KEY: "METHODNAME", PAR: "", VALUE: method),
            LegacyEnvelope(KEY: "STRUCTURE", PAR: parameterStructureName, VALUE: try jsonString(parameters))
        ]
        let data = try JSONEncoder().encode(envelope)
        return try rawDeflate(Data(data.base64EncodedString().utf8)).base64EncodedString()
    }

    static func authorization(from response: String) throws -> SAPReadAuthorization {
        let envelopes = try decodeEnvelopes(response)
        try throwBackendMessage(in: envelopes)
        for envelope in envelopes {
            guard let fields = try? dictionary(from: envelope.VALUE) else { continue }
            let hasAuthorizationFields = ["CHECKPW", "PWINITIAL", "MELDUNG", "0155"].contains {
                value(named: $0, in: fields) != nil
            }
            guard hasAuthorizationFields else { continue }
            let checkPassword = stringValue(value(named: "CHECKPW", in: fields)).uppercased()
            let initialPassword = stringValue(value(named: "PWINITIAL", in: fields)).uppercased()
            let requiresInitialChange = isSAPTrue(initialPassword)

            var extractedToken: String?
            if let tokenField = value(named: "0155", in: fields) {
                if let tokenDict = tokenField as? [String: Any] {
                    let tok = stringValue(value(named: "TOKEN", in: tokenDict)).trimmingCharacters(in: .whitespacesAndNewlines)
                    if !tok.isEmpty { extractedToken = tok }
                } else if let tokenString = tokenField as? String {
                    if let nestedDict = try? dictionary(from: tokenString) {
                        let tok = stringValue(value(named: "TOKEN", in: nestedDict)).trimmingCharacters(in: .whitespacesAndNewlines)
                        if !tok.isEmpty { extractedToken = tok }
                    } else if !tokenString.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                        extractedToken = tokenString.trimmingCharacters(in: .whitespacesAndNewlines)
                    }
                }
            }

            return SAPReadAuthorization(
                isAccepted: isSAPTrue(checkPassword) || requiresInitialChange,
                requiresInitialPasswordChange: requiresInitialChange,
                token: extractedToken
            )
        }
        throw SAPReadError.malformedPayload
    }

    static func tokenAuthorization(from response: String) throws -> Bool {
        let envelopes = try decodeEnvelopes(response)
        if envelopes.contains(where: { $0.KEY.uppercased() == "TEXT" }) {
            return false
        }
        for envelope in envelopes {
            guard let fields = try? dictionary(from: envelope.VALUE) else { continue }
            if let checkPassword = value(named: "CHECKPW", in: fields) {
                return isSAPTrue(stringValue(checkPassword).uppercased())
            }
        }
        return false
    }

    static func validateNoBackendError(_ response: String) throws {
        try throwBackendMessage(in: decodeEnvelopes(response))
    }

    static func validateAppVersion(_ response: String?) throws {
        guard let response, !response.isEmpty else { return }
        let envelopes = try decodeEnvelopes(response)
        try throwBackendMessage(in: envelopes)
        for envelope in envelopes {
            guard let fields = try? dictionary(from: envelope.VALUE) else { continue }
            let message = stringValue(value(named: "PARAMETER1", in: fields))
            if !message.isEmpty {
                throw SAPReadError.backendMessage(message)
            }
        }
    }

    /// `MMTFM001`, `MMTFM002` and `MMTFM003` answer in one parameter
    /// structure: `PARAMETER2` once ABAP is done, `PARAMETER4` while it works.
    /// Every envelope of a status response, for the diagnostics log.
    static func envelopeSummary(of response: String) -> String {
        guard let envelopes = try? decodeEnvelopes(response) else { return "undecodable response" }
        return envelopes.map { "\($0.KEY)[\($0.PAR ?? "")]=\($0.VALUE.prefix(600))" }.joined(separator: " | ")
    }

    static func lifecycleStatus(from response: String) throws -> SAPLegacyRequestStatus {
        let envelopes = try decodeEnvelopes(response)
        try throwBackendMessage(in: envelopes)
        let parameterSets = envelopes.compactMap { envelope -> [String: Any]? in
            guard let fields = try? dictionary(from: envelope.VALUE),
                  fields.keys.contains(where: { $0.uppercased().hasPrefix("PARAMETER") }) else { return nil }
            return fields
        }
        if parameterSets.contains(where: { !stringValue(value(named: "PARAMETER2", in: $0)).isEmpty }) {
            return .completed
        }
        if let working = parameterSets.first(where: { !stringValue(value(named: "PARAMETER4", in: $0)).isEmpty }) {
            let statusText = stringValue(value(named: "PARAMETER5", in: working))
            return .processing(statusText: statusText.isEmpty ? nil : statusText)
        }
        return .notAccepted
    }

    fileprivate static func inboundPack(from response: String) throws -> LegacySAPIncomingPackage {
        let envelopes = try decodeEnvelopes(response)
        try throwBackendMessage(in: envelopes)
        let structures = try envelopes.compactMap { envelope -> [String: Any]? in
            guard envelope.KEY.uppercased() == "STRUCTURE" else { return nil }
            return try dictionary(from: envelope.VALUE)
        }
        let parameterStructures = structures.filter {
            $0.keys.contains(where: { $0.uppercased().hasPrefix("PARAMETER") })
        }
        guard !parameterStructures.isEmpty else { throw SAPReadError.malformedPayload }
        let isLastPack = parameterStructures.contains {
            stringValue(value(named: "PARAMETER1", in: $0)).uppercased() == "X"
        }
        var tables: [String: [LegacySAPRow]] = [:]
        for structure in structures {
            for (rawName, rawValue) in structure {
                let tableName = rawName.uppercased()
                let compactName = tableName.replacingOccurrences(of: "_", with: "")
                let isUserTable = compactName == "T0153"
                let isExcluded = compactName.hasPrefix("T025")
                let inboundTableName = compactName.hasPrefix("T")
                    ? "FROM_T\(compactName.dropFirst())"
                    : ""
                guard !isExcluded else { continue }
                let schemaName = isUserTable ? "USER" : inboundTableName
                guard let schema = LegacySQLiteSchema.byName[schemaName] else {
                    continue
                }
                let rawRows: [Any]
                switch rawValue {
                case let rows as [Any]:
                    rawRows = rows
                case is NSNull:
                    rawRows = []
                default:
                    SAPSynchronizationDiagnostics.logRejectedStructure(
                        table: tableName,
                        location: "table",
                        type: Swift.type(of: rawValue)
                    )
                    throw SAPReadError.malformedPayload
                }
                var rows: [LegacySAPRow] = []
                var ignoredColumns = Set<String>()
                let allowedColumns = Set(schema.columns.map(\.name))
                for (rowIndex, rawRow) in rawRows.enumerated() {
                    guard let dictionary = rawRow as? [String: Any] else {
                        SAPSynchronizationDiagnostics.logRejectedStructure(
                            table: tableName,
                            location: "row \(rowIndex)",
                            type: Swift.type(of: rawRow)
                        )
                        throw SAPReadError.malformedPayload
                    }
                    let unknownColumns = Set(
                        dictionary.keys.map { $0.uppercased() }.filter { !allowedColumns.contains($0) }
                    )
                    if isUserTable {
                        ignoredColumns.formUnion(unknownColumns)
                    } else if !unknownColumns.isEmpty {
                        SAPSynchronizationDiagnostics.logRejectedColumns(unknownColumns, table: tableName)
                        throw SAPReadError.malformedPayload
                    }
                    rows.append(try scalarLegacyRow(
                        from: dictionary,
                        allowedColumns: allowedColumns,
                        ignoringUnknownColumns: isUserTable,
                        tableName: tableName
                    ))
                }
                SAPSynchronizationDiagnostics.logIgnoredColumns(ignoredColumns, table: tableName)
                tables[tableName, default: []].append(contentsOf: rows)
            }
        }
        SAPSynchronizationDiagnostics.logIncomingPackage(tables)
        return LegacySAPIncomingPackage(tables: tables, isLastPackage: isLastPack)
    }

    /// The Cordova `T_0153` importer selects the fixed USER fields, while the
    /// regular table importers remain strict. Known columns must stay scalar.
    static func legacyRow(
        from dictionary: [String: Any],
        for schema: LegacySQLiteTable,
        ignoringUnknownColumns: Bool = false,
        sourceTableName: String? = nil
    ) throws -> LegacySAPRow {
        try scalarLegacyRow(
            from: dictionary,
            allowedColumns: Set(schema.columns.map(\.name)),
            ignoringUnknownColumns: ignoringUnknownColumns,
            tableName: sourceTableName ?? schema.name
        )
    }

    private static func scalarLegacyRow(
        from dictionary: [String: Any],
        allowedColumns: Set<String>,
        ignoringUnknownColumns: Bool,
        tableName: String
    ) throws -> LegacySAPRow {
        var row: LegacySAPRow = [:]
        for (rawColumn, value) in dictionary {
            let column = rawColumn.uppercased()
            guard allowedColumns.contains(column) else {
                if ignoringUnknownColumns { continue }
                throw SAPReadError.malformedPayload
            }
            switch value {
            case is NSNull:
                row[column] = .some(nil)
            case let string as String:
                row[column] = string
            case let number as NSNumber:
                row[column] = number.stringValue
            default:
                SAPSynchronizationDiagnostics.logRejectedValueType(
                    column: column,
                    table: tableName,
                    type: Swift.type(of: value)
                )
                throw SAPReadError.malformedPayload
            }
        }
        return row
    }

    static func notification(from row: [String: Any]) -> SAPNotificationSummary? {
        let mergedNotificationData = mergedNotificationRow(from: row)

        let type = stringValue(value(named: "QMART", in: mergedNotificationData)).uppercased()
        let systemStatus = stringValue(value(named: "STTXT", in: mergedNotificationData)).uppercased()
        let id = stringValue(value(named: "QMNUM", in: mergedNotificationData))
        guard type == "I1", systemStatus != "MMAB", !id.isEmpty else { return nil }
        let rawPayloadJSON = (try? JSONSerialization.data(withJSONObject: mergedNotificationData))
            .flatMap { String(data: $0, encoding: .utf8) } ?? "{}"
        let functionalLocationName = stringValue(value(named: "PLTXT", in: mergedNotificationData))
        return SAPNotificationSummary(
            id: id,
            client: stringValue(value(named: "MANDT", in: mergedNotificationData)),
            title: stringValue(value(named: "QMTXT", in: mergedNotificationData)),
            functionalLocationID: stringValue(value(named: "STRNO", in: mergedNotificationData)),
            functionalLocationName: functionalLocationName,
            equipmentID: stringValue(value(named: "EQUNR", in: mergedNotificationData)),
            startDate: stringValue(value(named: "STRMN", in: mergedNotificationData)),
            endDate: stringValue(value(named: "LTRMN", in: mergedNotificationData)),
            systemStatus: systemStatus,
            userStatus: stringValue(value(named: "USTXT", in: mergedNotificationData)),
            rawPayloadJSON: rawPayloadJSON,
            structuralFilterMetadata: SAPNotificationSummary.structuralFilterMetadata(
                from: mergedNotificationData,
                functionalLocationName: functionalLocationName
            )
        )
    }

    private static func mergedNotificationRow(from row: [String: Any]) -> [String: Any] {
        guard let planData = notificationData(
            fromFeldwert: stringValue(value(named: "FELDWERT", in: row))
        ) else {
            return row
        }
        return row.merging(planData) { _, planValue in planValue }
    }

    static func workerProfile(from row: [String: Any]) -> SAPWorkerProfile? {
        let personnelNumber = stringValue(value(named: "PERSNR", in: row))
        guard !personnelNumber.isEmpty else { return nil }
        return SAPWorkerProfile(
            personnelNumber: personnelNumber,
            firstName: stringValue(value(named: "VORNAME", in: row)),
            lastName: stringValue(value(named: "NAME", in: row)),
            organizationUnit: stringValue(value(named: "GESELLSCHAFT", in: row)),
            role: stringValue(value(named: "ROLLE", in: row)),
            email: stringValue(value(named: "EMAIL", in: row)),
            isActive: stringValue(value(named: "AKTIV", in: row)),
            roleCode: stringValue(value(named: "RCDEX", in: row))
        )
    }

    static func userProfile(from row: [String: Any]) -> SAPUserProfile? {
        let persnr = stringValue(value(named: "PERSNR", in: row))
        guard !persnr.isEmpty else { return nil }
        let name = stringValue(value(named: "NAME", in: row))
        let vorname = stringValue(value(named: "VORNAME", in: row))
        let company = stringValue(value(named: "GESELLSCHAFT", in: row))
        let email = stringValue(value(named: "EMAIL", in: row))
        let i2 = stringValue(value(named: "I2", in: row))
        return SAPUserProfile(
            personalNumber: persnr,
            name: name,
            firstName: vorname,
            company: company,
            email: email,
            canCreateI2: i2.uppercased() == "X"
        )
    }

    static func briefingPartner(from row: [String: Any]) -> SAPBriefingPartner? {
        var data = row
        if let payload = feldwertValue(from: stringValue(value(named: "FELDWERT", in: row))) as? [String: Any] {
            data.merge(payload) { _, payloadValue in payloadValue }
        }
        let identifier = stringValue(value(named: "ADDRNUMBER", in: data))
        let name = stringValue(value(named: "NAME1", in: data))
        guard !identifier.isEmpty, !name.isEmpty else { return nil }
        return SAPBriefingPartner(
            id: identifier,
            client: firstSAPString(["MANDT", "CLIENT"], from: data),
            function: stringValue(value(named: "PARVW", in: data)),
            name: name,
            contactName: stringValue(value(named: "NAME2", in: data)),
            searchTerm1: stringValue(value(named: "SORT1", in: data)),
            searchTerm2: stringValue(value(named: "SORT2", in: data)),
            street: stringValue(value(named: "STREET", in: data)),
            houseNumber: stringValue(value(named: "HOUSE_NUM1", in: data)),
            postalCode: stringValue(value(named: "POST_CODE1", in: data)),
            city: stringValue(value(named: "CITY1", in: data)),
            country: stringValue(value(named: "COUNTRY", in: data)),
            email: stringValue(value(named: "SMTP_ADDR", in: data))
        )
    }

    static func briefingTemplate(from row: [String: Any]) -> SAPBriefingTemplate? {
        guard let decodedPayload = feldwertValue(from: stringValue(value(named: "FELDWERT", in: row))) else {
            return nil
        }
        let payload: [String: Any]
        let rawRows: [Any]
        if let objectPayload = decodedPayload as? [String: Any],
           let nestedRows = value(named: "T_PLPOD", in: objectPayload) as? [Any] {
            payload = objectPayload
            rawRows = nestedRows
        } else if let directRows = decodedPayload as? [Any] {
            payload = [:]
            rawRows = directRows
        } else {
            return nil
        }

        let equipmentType = firstSAPString(["EQART"], from: row, fallback: payload)
        let plannerGroup = firstSAPString(["INGRP"], from: row, fallback: payload)
        let planType = firstSAPString(["PLNTY"], from: row, fallback: payload)
        let planNumber = firstSAPString(["PLNNR"], from: row, fallback: payload)
        let sortedRows = rawRows.enumerated().sorted { left, right in
            let leftPosition = stringValue(value(named: "VORNR", in: left.element as? [String: Any] ?? [:]))
            let rightPosition = stringValue(value(named: "VORNR", in: right.element as? [String: Any] ?? [:]))
            let leftOrder = Int(leftPosition) ?? Int.max
            let rightOrder = Int(rightPosition) ?? Int.max
            if leftOrder != rightOrder { return leftOrder < rightOrder }
            if leftPosition != rightPosition { return leftPosition < rightPosition }
            return left.offset < right.offset
        }

        var sections: [SAPBriefingTemplateSection] = []
        var activeSectionID: String?
        for (index, rawValue) in sortedRows {
            guard let position = rawValue as? [String: Any] else { continue }
            let userType = stringValue(value(named: "USR00", in: position))
            let rowTypeValue = (userType.isEmpty ? stringValue(value(named: "DNAME", in: position)) : userType).uppercased()
            let control = stringValue(value(named: "STEUS", in: position))
            let operation = stringValue(value(named: "VORNR", in: position))
            let identifier = "\(control)\(operation)"
            let title = briefingPositionTitle(position)

            if rowTypeValue == "HEADER" {
                let sectionID = identifier.isEmpty ? "section-\(index)" : identifier
                let rawTitle = stringValue(value(named: "LTXA1", in: position))
                let rawSubtitle = stringValue(value(named: "LTXA2", in: position))
                let sectionTitle = rawTitle.isEmpty ? title : rawTitle
                let sectionSubtitle = rawSubtitle.isEmpty ? nil : rawSubtitle
                sections.append(SAPBriefingTemplateSection(
                    id: sectionID,
                    title: sectionTitle,
                    subtitle: sectionSubtitle,
                    isOptional: stringValue(value(named: "USR10", in: position)).uppercased() == "X",
                    items: []
                ))
                activeSectionID = sectionID
                continue
            }

            guard !title.isEmpty else { continue }
            if activeSectionID == nil {
                let sectionID = "section-default"
                sections.append(SAPBriefingTemplateSection(id: sectionID, title: "", isOptional: false, items: []))
                activeSectionID = sectionID
            }
            guard let activeSectionID,
                  let sectionIndex = sections.lastIndex(where: { $0.id == activeSectionID })
            else { continue }

            let symbols = briefingSymbols(from: position)
            let item = SAPBriefingTemplateItem(
                id: identifier.isEmpty ? "item-\(index)" : identifier,
                orderIdentifier: operation,
                rowType: SAPBriefingTemplateRowType(sapValue: rowTypeValue),
                title: title,
                answerOptions: briefingAnswerOptions(from: position),
                documentSymbolID: symbols.document,
                warningSymbolID: symbols.warning
            )
            let section = sections[sectionIndex]
            sections[sectionIndex] = SAPBriefingTemplateSection(
                id: section.id,
                title: section.title,
                subtitle: section.subtitle,
                isOptional: section.isOptional,
                items: section.items + [item]
            )
        }

        guard sections.contains(where: { !$0.items.isEmpty }) else { return nil }
        let identifier = [equipmentType, plannerGroup, planType, planNumber, sections.first?.id ?? ""]
            .filter { !$0.isEmpty }
            .joined(separator: "|")
        return SAPBriefingTemplate(
            id: identifier.isEmpty ? "briefing-template" : identifier,
            equipmentType: equipmentType,
            plannerGroup: plannerGroup,
            planType: planType,
            planNumber: planNumber,
            sections: sections
        )
    }

    private static func firstSAPString(
        _ keys: [String],
        from primary: [String: Any],
        fallback: [String: Any] = [:]
    ) -> String {
        for key in keys {
            let primaryValue = stringValue(value(named: key, in: primary))
            if !primaryValue.isEmpty { return primaryValue }
            let fallbackValue = stringValue(value(named: key, in: fallback))
            if !fallbackValue.isEmpty { return fallbackValue }
        }
        return ""
    }

    private static func briefingPositionTitle(_ row: [String: Any]) -> String {
        let title = stringValue(value(named: "LTXA1", in: row))
        let details = stringValue(value(named: "LTXA2", in: row))
        guard !details.isEmpty else { return title }
        guard !title.isEmpty else { return details }
        return "\(title):\n\(details)"
    }

    private static func briefingSymbols(from row: [String: Any]) -> (document: String?, warning: String?) {
        var warning = stringValue(value(named: "USR01", in: row))
        var document = stringValue(value(named: "USR02", in: row))
        if warning.count == 1 || document.count > 1 { swap(&warning, &document) }
        return (document.isEmpty ? nil : document, warning.isEmpty ? nil : warning)
    }

    private static func briefingAnswerOptions(from row: [String: Any]) -> [SAPBriefingAnswerOption] {
        guard let properties = value(named: "T_PROPS", in: row) as? [Any],
              let property = properties.first as? [String: Any]
        else { return [] }
        let keys = semicolonSeparatedValues(stringValue(value(named: "DFVAL", in: property)))
        let titles = semicolonSeparatedValues(stringValue(value(named: "DFVAL_TXT", in: property)))
        var seen: Set<String> = []
        return keys.enumerated().compactMap { index, key in
            let trimmedKey = key.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmedKey.isEmpty, seen.insert(trimmedKey).inserted else { return nil }
            let title = titles.indices.contains(index)
                ? titles[index].trimmingCharacters(in: .whitespacesAndNewlines)
                : ""
            return SAPBriefingAnswerOption(key: trimmedKey, title: title.isEmpty ? trimmedKey : title)
        }
    }

    private static func semicolonSeparatedValues(_ value: String) -> [String] {
        var normalized = value
        if normalized.hasSuffix(";") { normalized.removeLast() }
        return normalized.isEmpty ? [] : normalized.components(separatedBy: ";")
    }

    private static func throwBackendMessage(in envelopes: [Envelope]) throws {
        if let message = envelopes.first(where: { $0.KEY.uppercased() == "TEXT" })?.VALUE,
           !message.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            throw SAPReadError.backendMessage(message)
        }
    }

    private static func decodeEnvelopes(_ response: String) throws -> [Envelope] {
        var candidates: [Data] = []
        var seen: Set<Data> = []

        func appendCandidate(_ data: Data) {
            guard !data.isEmpty, seen.insert(data).inserted else { return }
            candidates.append(data)
        }

        appendCandidate(Data(response.utf8))
        var index = 0
        while index < candidates.count, candidates.count < 16 {
            let candidate = candidates[index]
            if let envelopes = parseEnvelopeJSON(candidate) { return envelopes }

            if let string = String(data: candidate, encoding: .utf8) {
                base64Candidates(from: string).forEach(appendCandidate)
            }

            // The legacy client accepts both normal zlib/gzip envelopes and
            // a gzip member followed by SAP-specific trailer bytes. Retain
            // those decoding paths so a valid SAP pack is not rejected before
            // the read-only cache can be replaced.
            if let gzipStream = gzipDeflateStream(candidate) {
                if let decoded = try? compressionTransform(gzipStream, operation: COMPRESSION_STREAM_DECODE) {
                    appendCandidate(decoded)
                }
                if let decoded = try? zlibDecompress(gzipStream, windowBits: -MAX_WBITS) {
                    appendCandidate(decoded)
                }
            }

            if let decoded = try? compressionTransform(candidate, operation: COMPRESSION_STREAM_DECODE) {
                appendCandidate(decoded)
            }

            for windowBits in [MAX_WBITS + 32, MAX_WBITS, -MAX_WBITS] {
                if let decoded = try? zlibDecompress(candidate, windowBits: windowBits) {
                    appendCandidate(decoded)
                }
            }
            index += 1
        }
        throw SAPReadError.malformedPayload
    }

    private static func parseEnvelopeJSON(_ data: Data) -> [Envelope]? {
        if let values = try? JSONDecoder().decode([Envelope].self, from: data) { return values }
        if let string = try? JSONDecoder().decode(String.self, from: data),
           let nested = string.data(using: .utf8),
           let values = try? JSONDecoder().decode([Envelope].self, from: nested) { return values }

        guard let objects = try? JSONSerialization.jsonObject(with: data) as? [[String: Any]] else {
            return nil
        }

        var envelopes: [Envelope] = []
        for object in objects {
            guard
                let key = value(named: "KEY", in: object) as? String,
                let rawValue = value(named: "VALUE", in: object),
                let serializedValue = jsonStringValue(rawValue)
            else {
                return nil
            }
            envelopes.append(Envelope(
                KEY: key,
                PAR: value(named: "PAR", in: object) as? String,
                VALUE: serializedValue
            ))
        }
        return envelopes
    }

    private static func base64Candidates(from string: String) -> [Data] {
        let compact = String(string.filter { !$0.isWhitespace })
        guard !compact.isEmpty else { return [] }
        var encodings = [compact]
        if compact.contains("-") || compact.contains("_") {
            encodings.append(compact.replacingOccurrences(of: "-", with: "+").replacingOccurrences(of: "_", with: "/"))
        }
        return encodings.compactMap { value in
            let padding = (4 - value.count % 4) % 4
            return Data(base64Encoded: value + String(repeating: "=", count: padding))
        }
    }

    /// Decodes the common SAP `FELDWERT` transport used by both notification
    /// rows and briefing master data: Base64, DEFLATE/gzip, Base64, then JSON.
    private static func feldwertValue(from feldwert: String) -> Any? {
        guard !feldwert.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return nil
        }

        var candidates: [Data] = []
        var seen: Set<Data> = []
        func appendCandidate(_ data: Data) {
            guard !data.isEmpty, seen.insert(data).inserted else { return }
            candidates.append(data)
        }

        appendCandidate(Data(feldwert.utf8))
        var index = 0
        while index < candidates.count, candidates.count < 16 {
            let candidate = candidates[index]
            if let payload = try? JSONSerialization.jsonObject(with: candidate) { return payload }
            if let string = String(data: candidate, encoding: .utf8) {
                base64Candidates(from: string).forEach(appendCandidate)
            }
            if let gzipStream = gzipDeflateStream(candidate) {
                if let decoded = try? compressionTransform(gzipStream, operation: COMPRESSION_STREAM_DECODE) {
                    appendCandidate(decoded)
                }
                if let decoded = try? zlibDecompress(gzipStream, windowBits: -MAX_WBITS) {
                    appendCandidate(decoded)
                }
            }
            if let decoded = try? compressionTransform(candidate, operation: COMPRESSION_STREAM_DECODE) {
                appendCandidate(decoded)
            }
            for windowBits in [MAX_WBITS + 32, MAX_WBITS, -MAX_WBITS] {
                if let decoded = try? zlibDecompress(candidate, windowBits: windowBits) {
                    appendCandidate(decoded)
                }
            }
            index += 1
        }
        return nil
    }

    /// Decodes the SAP `T_0271.FELDWERT` structure using the shared legacy
    /// transport decoder and retains only payloads with inspection positions.
    private static func notificationData(fromFeldwert feldwert: String) -> [String: Any]? {
        guard let payload = feldwertValue(from: feldwert) as? [String: Any],
              value(named: "T_PLPOD", in: payload) != nil
        else { return nil }
        return payload
    }

    /// Extract the RFC 1952 DEFLATE member without requiring SAP's response
    /// to end immediately after its gzip trailer. Raw inflate stops cleanly at
    /// the member boundary, matching the legacy application.
    private static func gzipDeflateStream(_ data: Data) -> Data? {
        let bytes = [UInt8](data)
        guard
            bytes.count > 10,
            bytes[0] == 0x1F,
            bytes[1] == 0x8B,
            bytes[2] == 0x08,
            bytes[3] & 0xE0 == 0
        else {
            return nil
        }

        let flags = bytes[3]
        var offset = 10

        if flags & 0x04 != 0 {
            guard offset + 2 <= bytes.count else { return nil }
            let extraLength = Int(bytes[offset]) | (Int(bytes[offset + 1]) << 8)
            offset += 2
            guard extraLength <= bytes.count - offset else { return nil }
            offset += extraLength
        }
        if flags & 0x08 != 0,
           !advancePastNullTerminatedField(in: bytes, offset: &offset, limit: bytes.count) {
            return nil
        }
        if flags & 0x10 != 0,
           !advancePastNullTerminatedField(in: bytes, offset: &offset, limit: bytes.count) {
            return nil
        }
        if flags & 0x02 != 0 {
            guard offset + 2 <= bytes.count else { return nil }
            offset += 2
        }

        guard offset < bytes.count else { return nil }
        return data.subdata(in: offset..<bytes.count)
    }

    private static func advancePastNullTerminatedField(
        in bytes: [UInt8],
        offset: inout Int,
        limit: Int
    ) -> Bool {
        while offset < limit {
            let byte = bytes[offset]
            offset += 1
            if byte == 0 { return true }
        }
        return false
    }

    private static func rawDeflate(_ data: Data) throws -> Data {
        var stream = z_stream()
        guard deflateInit2_(&stream, Z_DEFAULT_COMPRESSION, Z_DEFLATED, -MAX_WBITS, 8, Z_DEFAULT_STRATEGY, ZLIB_VERSION, Int32(MemoryLayout<z_stream>.size)) == Z_OK else {
            throw SAPReadError.malformedPayload
        }
        defer { deflateEnd(&stream) }
        return try transform(data, stream: &stream, operation: { stream in deflate(&stream, Z_FINISH) })
    }

    private static func zlibDecompress(_ data: Data, windowBits: Int32) throws -> Data {
        var stream = z_stream()
        guard inflateInit2_(&stream, windowBits, ZLIB_VERSION, Int32(MemoryLayout<z_stream>.size)) == Z_OK else {
            throw SAPReadError.malformedPayload
        }
        defer { inflateEnd(&stream) }
        return try transform(data, stream: &stream, operation: { stream in inflate(&stream, Z_NO_FLUSH) })
    }

    private static func transform(
        _ data: Data,
        stream: inout z_stream,
        operation: (inout z_stream) -> Int32
    ) throws -> Data {
        let bufferSize = 64 * 1024
        let outputLimit = 50 * 1_024 * 1_024
        return try data.withUnsafeBytes { bytes in
            guard let source = bytes.bindMemory(to: Bytef.self).baseAddress else { throw SAPReadError.malformedPayload }
            stream.next_in = UnsafeMutablePointer(mutating: source)
            stream.avail_in = uInt(data.count)
            let buffer = UnsafeMutablePointer<UInt8>.allocate(capacity: bufferSize)
            defer { buffer.deallocate() }
            var output = Data()
            var status: Int32 = Z_OK
            repeat {
                stream.next_out = buffer
                stream.avail_out = uInt(bufferSize)
                status = operation(&stream)
                guard status == Z_OK || status == Z_STREAM_END else { throw SAPReadError.malformedPayload }
                output.append(buffer, count: bufferSize - Int(stream.avail_out))
                guard output.count <= outputLimit else { throw SAPReadError.malformedPayload }
            } while status != Z_STREAM_END
            return output
        }
    }

    private static func compressionTransform(
        _ data: Data,
        operation: compression_stream_operation
    ) throws -> Data {
        var placeholderSource: UInt8 = 0
        var placeholderDestination: UInt8 = 0
        var stream = withUnsafeMutablePointer(to: &placeholderDestination) { destination in
            withUnsafePointer(to: &placeholderSource) { source in
                compression_stream(
                    dst_ptr: destination,
                    dst_size: 0,
                    src_ptr: source,
                    src_size: 0,
                    state: nil
                )
            }
        }
        guard compression_stream_init(&stream, operation, COMPRESSION_ZLIB) != COMPRESSION_STATUS_ERROR else {
            throw SAPReadError.malformedPayload
        }
        defer { compression_stream_destroy(&stream) }

        let bufferSize = 64 * 1024
        let outputLimit = 50 * 1_024 * 1_024
        var output = Data()
        return try data.withUnsafeBytes { source in
            guard let sourcePointer = source.bindMemory(to: UInt8.self).baseAddress else {
                throw SAPReadError.malformedPayload
            }
            stream.src_ptr = sourcePointer
            stream.src_size = data.count

            repeat {
                var buffer = [UInt8](repeating: 0, count: bufferSize)
                let status = buffer.withUnsafeMutableBytes { destination in
                    stream.dst_ptr = destination.bindMemory(to: UInt8.self).baseAddress!
                    stream.dst_size = bufferSize
                    return compression_stream_process(&stream, Int32(COMPRESSION_STREAM_FINALIZE.rawValue))
                }
                output.append(buffer, count: bufferSize - stream.dst_size)
                guard output.count <= outputLimit, status != COMPRESSION_STATUS_ERROR else {
                    throw SAPReadError.malformedPayload
                }
                if status == COMPRESSION_STATUS_END { break }
            } while true

            return output
        }
    }

    private static func dictionary(from string: String) throws -> [String: Any] {
        guard let data = string.data(using: .utf8),
              let object = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw SAPReadError.malformedPayload
        }
        return object
    }

    private static func jsonString(_ value: Encodable) throws -> String {
        let data = try JSONEncoder().encode(AnyEncodable(value))
        guard let string = String(data: data, encoding: .utf8) else { throw SAPReadError.malformedPayload }
        return string
    }

    private static func value(named name: String, in dictionary: [String: Any]) -> Any? {
        dictionary.first { $0.key.caseInsensitiveCompare(name) == .orderedSame }?.value
    }

    private static func stringValue(_ value: Any?) -> String {
        switch value {
        case let string as String: string.trimmingCharacters(in: .whitespacesAndNewlines)
        case let number as NSNumber: number.stringValue
        default: ""
        }
    }

    private static func jsonStringValue(_ value: Any) -> String? {
        if let string = value as? String { return string }
        guard JSONSerialization.isValidJSONObject(value),
              let data = try? JSONSerialization.data(withJSONObject: value) else {
            return nil
        }
        return String(data: data, encoding: .utf8)
    }

    private static func isSAPTrue(_ value: String) -> Bool {
        ["X", "1", "TRUE", "YES", "OK"].contains(value)
    }
}

func decodeSAPNotificationPayload(fromFeldwert feldwert: String) -> [String: Any]? {
    SAPLegacyDataExchangeCodec.cachedNotificationPayload(fromFeldwert: feldwert)
}

private struct AnyEncodable: Encodable {
    let value: Encodable

    init(_ value: Encodable) {
        self.value = value
    }

    func encode(to encoder: Encoder) throws {
        try value.encode(to: encoder)
    }
}
