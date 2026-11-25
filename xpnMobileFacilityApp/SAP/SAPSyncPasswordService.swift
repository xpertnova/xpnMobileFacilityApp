import Foundation

/// Replacing the legacy MTFM synchronization password. Checking it is part
/// of the synchronization itself (`M0153003`).
protocol SAPSyncPasswordService: Sendable {
    /// `M0153002` (`onChangePwdSubmit`): replaces an initial password. SAP
    /// answers like the password check, so the new password's token comes
    /// back with it.
    func changeInitialPassword(oldPassword: String, newPassword: String) async throws -> String?
}

enum SAPSyncPasswordError: LocalizedError, Equatable, Sendable {
    /// SAP did not answer `CHECKPW = X`: the old password was wrong or SAP
    /// refused the new one (`msg.inital.pwd.error`).
    case changeRejected

    var errorDescription: String? {
        switch self {
        case .changeRejected: "The password could not be changed."
        }
    }
}

struct SAPLiveSyncPasswordService: SAPSyncPasswordService {
    let connection: SAPReadConnection
    /// The worker ID entered at the app login, the legacy `getUserId()`.
    let synchronizationUserID: String

    private var sapWorkerID: String {
        synchronizationUserID
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .uppercased(with: Locale(identifier: "en_US_POSIX"))
    }

    func changeInitialPassword(oldPassword: String, newPassword: String) async throws -> String? {
        guard !sapWorkerID.isEmpty else { throw SAPReadError.authenticatedConnectionUnavailable }
        let session = connection.newSynchronizationConnection()
        defer { session.finishSynchronizationSession() }
        let client = SAPLiveLegacyDataExchangeClient(connection: session, sapWorkerID: sapWorkerID)
        guard let response = try await client.call(
            method: "M0153002",
            parameters: SAPReadParameters(values: [
                "PARAMETER1": sapWorkerID,
                "PARAMETER2": oldPassword,
                "PARAMETER3": newPassword,
                "PARAMETER4": session.deviceID
            ]),
            usesLegacyAuthenticationEnvelope: true
        ) else {
            throw SAPReadError.malformedPayload
        }
        let authorization: SAPReadAuthorization
        do {
            authorization = try SAPLegacyDataExchangeCodec.authorization(from: response)
        } catch {
            SAPSynchronizationDiagnostics.logRequestFailure(method: "M0153002", error: error)
            throw error
        }
        SAPSynchronizationDiagnostics.logPasswordCheckAnswer(method: "M0153002", authorization)
        guard authorization.isAccepted else { throw SAPSyncPasswordError.changeRejected }
        return authorization.token
    }
}
