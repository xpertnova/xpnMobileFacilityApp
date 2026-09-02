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

    static func logOnboardingIdentityFailure(_ error: Error) {
        print("\(prefix) Could not resolve the SAP synchronization identity: \(error.localizedDescription)")
    }

    static func logSynchronizationStarted(userID: String) {
        print("\(prefix) Starting production synchronization for user \(redacted(userID)).")
    }

    static func logSynchronizationStep(_ step: String) {
        print("\(prefix) \(step).")
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

    static func logSynchronizationCompleted(
        notificationCount: Int,
        businessEntityCount: Int
    ) {
        print(
            "\(prefix) Synchronization completed: \(notificationCount) notifications, " +
                "\(businessEntityCount) business entities."
        )
    }

    private static func redacted(_ value: String) -> String {
        guard value.count > 4 else { return "••••" }
        return "\(value.prefix(2))••••\(value.suffix(2))"
    }

    private static func redactedDeviceID(_ value: String) -> String {
        guard value.count > 6 else { return "••••" }
        return "••••\(value.suffix(6))"
    }
}
struct SAPReadConnection: @unchecked Sendable {
    let backendURL: URL
    let sapURLSession: SAPURLSession
    let deviceID: String

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
            deviceID: deviceID
        )
    }

    /// Each synchronization gets its own session. The retained onboarding
    /// session remains the authenticated template for a later refresh.
    func newSynchronizationConnection() -> SAPReadConnection {
        let synchronizationSession = sapURLSession.copy(
            configuration: sapURLSession.configuration,
            delegate: sapURLSession.delegate,
            delegateQueue: sapURLSession.delegateQueue
        )
        synchronizationSession.sessionDescription = "Mobile Facility SAP refresh"
        return SAPReadConnection(
            backendURL: backendURL,
            sapURLSession: synchronizationSession,
            deviceID: deviceID
        )
    }

    func finishSynchronizationSession() {
        sapURLSession.finishTasksAndInvalidate()
    }
}

/// Debug-only transport diagnostics. Do not add passwords, raw request bodies,
/// response payloads, tokens, or complete device/user identifiers here.

struct SAPInboundNotificationRefreshService: SAPNotificationRefreshService {
    private static let downloadSchemaVersion = "1.3.2-21-121"
    private let connection: SAPReadConnection
    private let synchronizationUserID: String

    init(connection: SAPReadConnection, synchronizationUserID: String) {
        self.connection = connection
        self.synchronizationUserID = synchronizationUserID
    }

    private var sapWorkerID: String {
        synchronizationUserID
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .uppercased(with: Locale(identifier: "en_US_POSIX"))
    }

    func refresh(
        sapPassword: String,
        progress: @escaping SAPReadRefreshProgressHandler
    ) async throws -> SAPReadSnapshot {
        let password = sapPassword.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !password.isEmpty else { throw SAPReadError.passwordRequired }
        guard !sapWorkerID.isEmpty else { throw SAPReadError.authenticatedConnectionUnavailable }

        let synchronizationConnection = connection.newSynchronizationConnection()
        defer { synchronizationConnection.finishSynchronizationSession() }

        SAPSynchronizationDiagnostics.logSynchronizationStarted(userID: sapWorkerID)
        SAPSynchronizationDiagnostics.logPasswordCheckStarted(
            host: connection.backendURL.host ?? "unknown host",
            userID: sapWorkerID,
            deviceID: synchronizationConnection.deviceID
        )
        await progress(.authenticating)
        try await verify(password: password, connection: synchronizationConnection)

        // SAP prepares the FROM package only after the regular TO lifecycle,
        // including an otherwise-empty M0002001 payload. The old SwiftUI app
        // sends it even when there are no pending supported records.
        let fromRequestID = Self.makeRequestID(prefix: "MTFMSYNCFROM")
        let toRequestID = Self.makeRequestID(prefix: "MTFMSYNCTO")
        SAPSynchronizationDiagnostics.logSynchronizationStage(1, "Uploading TO metadata")
        await progress(.uploadingOutgoingMetadata)
        try await submitEmptyOutgoingMetadata(
            requestID: toRequestID,
            connection: synchronizationConnection
        )
        SAPSynchronizationDiagnostics.logSynchronizationStage(2, "TO documents have no pending payload")
        
        SAPSynchronizationDiagnostics.logSynchronizationStage(3, "Triggering TO post")
        await progress(.postingOutgoingData)
        try triggerOutgoingPost(requestID: toRequestID, connection: synchronizationConnection)
        
        SAPSynchronizationDiagnostics.logSynchronizationStep("Waiting for TO acknowledgement")
        await progress(.waitingForOutgoingAcknowledgement)
        try await waitForOutgoingAcknowledgement(
            requestID: toRequestID,
            connection: synchronizationConnection
        )
        
        SAPSynchronizationDiagnostics.logSynchronizationStep("Checking app version")
        await progress(.checkingAppVersion)
        try await checkAppVersion(requestID: toRequestID, connection: synchronizationConnection)

        SAPSynchronizationDiagnostics.logSynchronizationStage(4, "Preparing FROM package")
        await progress(.preparingIncomingData)
        try prepareIncomingData(
            fromRequestID: fromRequestID,
            toRequestID: toRequestID,
            connection: synchronizationConnection
        )
        await progress(.waitingForIncomingData)
        try await waitForIncomingData(requestID: fromRequestID, connection: synchronizationConnection)

        var notificationsByID: [String: SAPNotificationSummary] = [:]
        var briefingPartnersByID: [String: SAPBriefingPartner] = [:]
        var briefingTemplatesByID: [String: SAPBriefingTemplate] = [:]
        var workerProfile: SAPWorkerProfile?
        var openInspectionRowCount = 0
        var isLastPack = false

        for _ in 1...256 {
            await progress(.receivingIncomingPackages)
            guard let response = try await call(method: "M0002003", parameters: Self.parameters([
                "PARAMETER1": sapWorkerID,
                "PARAMETER2": fromRequestID,
                "PARAMETER3": "D"
            ]), connection: synchronizationConnection) else {
                throw SAPReadError.malformedPayload
            }
            let pack = try SAPLegacyDataExchangeCodec.inboundPack(from: response)
            for notification in pack.notifications {
                notificationsByID[notification.id] = notification
            }
            for partner in pack.briefingPartners {
                briefingPartnersByID[partner.id] = partner
            }
            for template in pack.briefingTemplates {
                briefingTemplatesByID[template.id] = template
            }
            openInspectionRowCount += pack.openInspectionRowCount
            if let profile = pack.workerProfile {
                workerProfile = profile
            }
            isLastPack = pack.isLastPack
            if isLastPack { break }
        }

        guard isLastPack else { throw SAPReadError.malformedPayload }
        guard openInspectionRowCount == 0 || !notificationsByID.isEmpty else {
            throw SAPReadError.malformedPayload
        }
        let snapshot = SAPReadSnapshot(
            sapWorkerID: sapWorkerID,
            notifications: notificationsByID.values.sorted { $0.id < $1.id },
            workerProfile: workerProfile,
            briefingPartners: briefingPartnersByID.values.sorted {
                $0.name.localizedStandardCompare($1.name) == .orderedAscending
            },
            briefingTemplates: briefingTemplatesByID.values.sorted { $0.id < $1.id }
        )
        SAPSynchronizationDiagnostics.logSynchronizationCompleted(notificationCount: snapshot.notifications.count, businessEntityCount: 0)
        return snapshot
    }

    private func verify(password: String, connection: SAPReadConnection) async throws {
        guard let response = try await call(
            method: "M0153003",
            parameters: Self.parameters([
                "PARAMETER1": sapWorkerID,
                "PARAMETER2": password,
                "PARAMETER3": connection.deviceID
            ]),
            usesLegacyAuthenticationEnvelope: true,
            connection: connection
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
        SAPSynchronizationDiagnostics.logPasswordAccepted(hasToken: false)
    }

    private func submitEmptyOutgoingMetadata(
        requestID: String,
        connection: SAPReadConnection
    ) async throws {
        do {
            let response = try await call(
                method: "M0002001",
                parameters: Self.parameters([
                    "PARAMETER1": sapWorkerID,
                    "PARAMETER2": requestID
                ]),
                synchronizationData: SAPEmptyOutgoingSynchronizationData(),
                connection: connection,
                responseMayBeEmpty: true
            )
            if let response {
                try SAPLegacyDataExchangeCodec.validateNoBackendError(response)
            }
        } catch let error as SAPReadError {
            // The legacy client lets MMTFM002 establish whether ABAP accepted
            // an M0002001 request whose gateway response timed out.
            guard Self.isRecoverableLifecyclePollingError(error) else { throw error }
        }
    }

    private func triggerOutgoingPost(requestID: String, connection: SAPReadConnection) throws {
        let ivData = try SAPLegacyDataExchangeCodec.pack(
            method: "M0002021",
            parameters: Self.parameters([
                "PARAMETER1": sapWorkerID,
                "PARAMETER2": requestID,
                "PARAMETER3": "D",
                "PARAMETER4": Self.downloadSchemaVersion
            ])
        )
        let request = try dataExchangeRequest(ivData: ivData, connection: connection)

        // M0002021 is a trigger. Its separate completion check below is the
        // source of truth, matching the legacy client.
        Task {
            do {
                let (data, response) = try await connection.sapURLSession.data(for: request)
                guard let httpResponse = response as? HTTPURLResponse,
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
                // MMTFM002 below determines whether ABAP accepted the TO post.
            }
        }
    }

    private func waitForOutgoingAcknowledgement(
        requestID: String,
        connection: SAPReadConnection
    ) async throws {
        // MMTFM002 is first polled one second after the asynchronous M0002021
        // trigger, then every 30 seconds, as in the old SwiftUI application.
        for attempt in 1...10 {
            try await Task.sleep(for: .seconds(attempt == 1 ? 1 : 30))
            do {
                guard let response = try await call(method: "MMTFM002", parameters: Self.parameters([
                    "PARAMETER1": sapWorkerID,
                    "PARAMETER2": requestID,
                    "PARAMETER3": "D"
                ]), connection: connection) else {
                    throw SAPReadError.malformedPayload
                }
                switch try SAPLegacyDataExchangeCodec.outgoingPostAcknowledgement(from: response) {
                case .confirmed:
                    return
                case .processing:
                    continue
                case .rejected:
                    throw SAPReadError.malformedPayload
                }
            } catch is CancellationError {
                throw CancellationError()
            } catch let error as SAPReadError {
                guard Self.isRecoverableLifecyclePollingError(error) else { throw error }
            }
        }
        throw SAPReadError.preparationTimedOut
    }

    private func checkAppVersion(requestID: String, connection: SAPReadConnection) async throws {
        let response = try await call(
            method: "MMTFM008",
            parameters: Self.parameters([
                "PARAMETER1": sapWorkerID,
                "PARAMETER2": requestID,
                "PARAMETER3": "D",
                "PARAMETER4": Self.downloadSchemaVersion
            ]),
            connection: connection,
            responseMayBeEmpty: true
        )
        try SAPLegacyDataExchangeCodec.validateAppVersion(response)
    }

    private func prepareIncomingData(
        fromRequestID: String,
        toRequestID: String,
        connection: SAPReadConnection
    ) throws {
        let ivData = try SAPLegacyDataExchangeCodec.pack(
            method: "MMTFM004",
            parameters: Self.parameters([
                "PARAMETER1": sapWorkerID,
                "PARAMETER2": fromRequestID,
                "PARAMETER3": "D",
                "PARAMETER4": Self.downloadSchemaVersion,
                "PARAMETER5": toRequestID
            ])
        )
        let request = try dataExchangeRequest(ivData: ivData, connection: connection)
        
        // The legacy app starts this long-running ABAP operation without
        // waiting for its response. MMTFM003 is the authoritative completion
        // check, so an empty or delayed MMTFM004 response cannot replace a
        // previously cached notification snapshot.
        Task {
            do {
                let (data, response) = try await connection.sapURLSession.data(for: request)
                guard let httpResponse = response as? HTTPURLResponse,
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
                // MMTFM003 below determines whether SAP completed the read.
            }
        }
    }

    private func waitForIncomingData(
        requestID: String,
        connection: SAPReadConnection
    ) async throws {
        for attempt in 1...10 {
            try await Task.sleep(for: .seconds(attempt == 1 ? 10 : 30))
            do {
                guard let response = try await call(method: "MMTFM003", parameters: Self.parameters([
                    "PARAMETER1": sapWorkerID,
                    "PARAMETER2": requestID,
                    "PARAMETER3": "D"
                ]), connection: connection) else {
                    throw SAPReadError.malformedPayload
                }
                if try SAPLegacyDataExchangeCodec.isPreparationComplete(response) {
                    return
                }
            } catch is CancellationError {
                throw CancellationError()
            } catch let error as SAPReadError {
                guard Self.isRecoverableLifecyclePollingError(error) else { throw error }
            }
        }
        throw SAPReadError.preparationTimedOut
    }

    private func call(
        method: String,
        parameters: SAPReadParameters,
        usesLegacyAuthenticationEnvelope: Bool = false,
        synchronizationData: SAPEmptyOutgoingSynchronizationData? = nil,
        connection: SAPReadConnection,
        responseMayBeEmpty: Bool = false
    ) async throws -> String? {
        let fromRequestID = ["M0002003", "MMTFM003", "MMTFM004"].contains(method) ? parameters.PARAMETER2 : ""
        let toRequestID = method == "MMTFM004" ? parameters.PARAMETER5 : (["M0002001", "MMTFM002", "MMTFM008"].contains(method) ? parameters.PARAMETER2 : "")
        if method != "M0153003" {
            SAPSynchronizationDiagnostics.logDownloadRequest(method: method, fromRequestID: fromRequestID, toRequestID: toRequestID)
        }
        
        let ivData: String
        if let synchronizationData {
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
        let request = try dataExchangeRequest(ivData: ivData, connection: connection)
        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await connection.sapURLSession.data(for: request)
        } catch let error as URLError {
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
        let evData = payload?["EvData"] as? String ?? ""
        let hasEvData = !evData.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        guard (200...299).contains(httpResponse.statusCode) else {
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
        connection: SAPReadConnection
    ) throws -> URLRequest {
        let url = try serviceRoot(connection: connection).appendingPathComponent("DATAEXCHANGESet")
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.timeoutInterval = 300
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue("X", forHTTPHeaderField: "X-Requested-With")
        let encoder = JSONEncoder()
        encoder.outputFormatting = .withoutEscapingSlashes
        request.httpBody = try encoder.encode(SAPDataExchangeRequest(IvData: ivData, EvData: "", IvKey: false))
        return request
    }

    private func serviceRoot(connection: SAPReadConnection) throws -> URL {
        guard
            let parametersURL = Bundle.main.url(forResource: "AppParameters", withExtension: "plist"),
            let parametersData = try? Data(contentsOf: parametersURL),
            let parameters = try? PropertyListSerialization.propertyList(from: parametersData, format: nil) as? [String: Any],
            let destinations = parameters["Destinations"] as? [String: Any],
            let destination = destinations["XPNMTFMODDAEXSRVEntities"] as? String
        else {
            throw SAPReadError.configurationUnavailable
        }
        let path = destination.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        guard !path.isEmpty else { throw SAPReadError.configurationUnavailable }
        return connection.backendURL.appendingPathComponent(path, isDirectory: true)
    }

    private static func parameters(_ overrides: [String: String]) -> SAPReadParameters {
        SAPReadParameters(values: overrides)
    }

    private static func makeRequestID(prefix: String) -> String {
        let identifier = UUID().uuidString.replacingOccurrences(of: "-", with: "").prefix(16).uppercased()
        return "\(prefix)-\(identifier)"
    }

    private static func isRecoverableLifecyclePollingError(_ error: SAPReadError) -> Bool {
        switch error {
        case .httpStatus(504), .requestTimedOut:
            true
        default:
            false
        }
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

/// The legacy M0002001 contract requires all tables to be present, even when
/// this read-only refresh has no approved local records to upload.
private struct SAPEmptyOutgoingSynchronizationData: Encodable {
    let T_0281: [[String: String]] = []
    let T_0283: [[String: String]] = []
    let T_0152R: [[String: String]] = []
    let T_0154R: [[String: String]] = []
    let T_0211R: [[String: String]] = []
    let T_0212R: [[String: String]] = []
    let T_0265: [[String: String]] = []
    let T_0266: [[String: String]] = []
    let T_0282: [[String: String]] = []
    let T_0284: [[String: String]] = []
    let T_0285: [[String: String]] = []
    let T_0286: [[String: String]] = []
    let T_0300: [[String: String]] = []
    let T_0302: [[String: String]] = []
}

fileprivate struct SAPReadAuthorization {
    let isAccepted: Bool
    let requiresInitialPasswordChange: Bool
}

fileprivate struct SAPInboundPack {
    let notifications: [SAPNotificationSummary]
    let workerProfile: SAPWorkerProfile?
    let briefingPartners: [SAPBriefingPartner]
    let briefingTemplates: [SAPBriefingTemplate]
    let openInspectionRowCount: Int
    let isLastPack: Bool
}

private enum SAPOutgoingPostAcknowledgement {
    case confirmed
    case processing
    case rejected
}

private enum SAPLegacyDataExchangeCodec {
    private static let parameterStructureName = "/EZO/MTFMS_PARAMETER"
    private static let synchronizationStructureName = "/EZO/MTFMS_IP4SYNCH"

    static func cachedNotificationPayload(fromFeldwert feldwert: String) -> [String: Any]? {
        notificationData(fromFeldwert: feldwert)
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

    private static func packed(method: String, parameters: Encodable) throws -> String {
        let envelope = [
            LegacyEnvelope(KEY: "METHODNAME", PAR: "", VALUE: method),
            LegacyEnvelope(KEY: "STRUCTURE", PAR: parameterStructureName, VALUE: try jsonString(parameters))
        ]
        let data = try JSONEncoder().encode(envelope)
        return try rawDeflate(Data(data.base64EncodedString().utf8)).base64EncodedString()
    }

    fileprivate static func authorization(from response: String) throws -> SAPReadAuthorization {
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
            return SAPReadAuthorization(
                isAccepted: isSAPTrue(checkPassword) || requiresInitialChange,
                requiresInitialPasswordChange: requiresInitialChange
            )
        }
        throw SAPReadError.malformedPayload
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

    static func outgoingPostAcknowledgement(
        from response: String
    ) throws -> SAPOutgoingPostAcknowledgement {
        let envelopes = try decodeEnvelopes(response)
        try throwBackendMessage(in: envelopes)
        for envelope in envelopes {
            guard let fields = try? dictionary(from: envelope.VALUE) else { continue }
            if !stringValue(value(named: "PARAMETER2", in: fields)).isEmpty {
                return .confirmed
            }
            if !stringValue(value(named: "PARAMETER4", in: fields)).isEmpty {
                return .processing
            }
        }
        return .rejected
    }

    static func isPreparationComplete(_ response: String) throws -> Bool {
        let envelopes = try decodeEnvelopes(response)
        try throwBackendMessage(in: envelopes)
        let parameterSets = envelopes.compactMap { envelope -> [String: Any]? in
            guard let fields = try? dictionary(from: envelope.VALUE),
                  fields.keys.contains(where: { $0.uppercased().hasPrefix("PARAMETER") }) else { return nil }
            return fields
        }
        guard !parameterSets.isEmpty else { throw SAPReadError.malformedPayload }
        if parameterSets.contains(where: { !stringValue(value(named: "PARAMETER2", in: $0)).isEmpty }) {
            return true
        }
        if parameterSets.contains(where: { !stringValue(value(named: "PARAMETER4", in: $0)).isEmpty }) {
            return false
        }
        throw SAPReadError.malformedPayload
    }

    fileprivate static func inboundPack(from response: String) throws -> SAPInboundPack {
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
        let notificationRows = structures.flatMap {
            value(named: "T_0271", in: $0) as? [[String: Any]] ?? []
        }
        let profileRows = structures.flatMap {
            value(named: "T_0153", in: $0) as? [[String: Any]] ?? []
        }
        let briefingPartnerRows = structures.flatMap {
            value(named: "T_0298", in: $0) as? [[String: Any]] ?? []
        }
        let briefingTemplateRows = structures.flatMap {
            value(named: "T_0267", in: $0) as? [[String: Any]] ?? []
        }
        let openInspectionRowCount = notificationRows.filter {
            stringValue(value(named: "QMART", in: $0)).uppercased() == "I1" &&
                stringValue(value(named: "STTXT", in: $0)).uppercased() != "MMAB"
        }.count
        return SAPInboundPack(
            notifications: notificationRows.compactMap(notification(from:)),
            workerProfile: profileRows.compactMap(workerProfile(from:)).first,
            briefingPartners: briefingPartnerRows.compactMap(briefingPartner(from:)),
            briefingTemplates: briefingTemplateRows.compactMap(briefingTemplate(from:)),
            openInspectionRowCount: openInspectionRowCount,
            isLastPack: isLastPack
        )
    }

    private static func notification(from row: [String: Any]) -> SAPNotificationSummary? {
        var mergedNotificationData = row
        if let planData = notificationData(fromFeldwert: stringValue(value(named: "FELDWERT", in: row))) {
            mergedNotificationData.merge(planData) { _, planValue in planValue }
        }

        let type = stringValue(value(named: "QMART", in: mergedNotificationData)).uppercased()
        let systemStatus = stringValue(value(named: "STTXT", in: mergedNotificationData)).uppercased()
        let id = stringValue(value(named: "QMNUM", in: mergedNotificationData))
        guard type == "I1", systemStatus != "MMAB", !id.isEmpty else { return nil }
        let rawPayloadJSON = (try? JSONSerialization.data(withJSONObject: mergedNotificationData))
            .flatMap { String(data: $0, encoding: .utf8) } ?? "{}"
        return SAPNotificationSummary(
            id: id,
            client: stringValue(value(named: "MANDT", in: mergedNotificationData)),
            title: stringValue(value(named: "QMTXT", in: mergedNotificationData)),
            functionalLocationID: stringValue(value(named: "STRNO", in: mergedNotificationData)),
            functionalLocationName: stringValue(value(named: "PLTXT", in: mergedNotificationData)),
            startDate: stringValue(value(named: "STRMN", in: mergedNotificationData)),
            endDate: stringValue(value(named: "LTRMN", in: mergedNotificationData)),
            systemStatus: systemStatus,
            userStatus: stringValue(value(named: "USTXT", in: mergedNotificationData)),
            rawPayloadJSON: rawPayloadJSON
        )
    }

    private static func workerProfile(from row: [String: Any]) -> SAPWorkerProfile? {
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

    private static func briefingPartner(from row: [String: Any]) -> SAPBriefingPartner? {
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

    private static func briefingTemplate(from row: [String: Any]) -> SAPBriefingTemplate? {
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
                sections.append(SAPBriefingTemplateSection(
                    id: sectionID,
                    title: title,
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
