import Foundation

#if DEBUG
/// Debug-only way to see the initial password dialog without an SAP user
/// whose password is initial. Enable the launch argument
/// `-ForceInitialPasswordChange` in the scheme.
///
/// The first synchronization password entered after launch, whatever it is,
/// is answered as if `M0153003` had returned `PWINITIAL = X`, without
/// contacting SAP. Saving in the dialog does not call `M0153002` either, so
/// no real password changes; it succeeds without a token, and the password
/// dialog comes back for a real synchronization. Relaunch to see it again.
enum SAPForcedInitialPasswordChange {
    static let launchArgument = "-ForceInitialPasswordChange"

    static var isEnabled: Bool {
        ProcessInfo.processInfo.arguments.contains(launchArgument)
    }

    static func refreshService(
        wrapping service: any SAPNotificationRefreshService
    ) -> any SAPNotificationRefreshService {
        ForcedInitialPasswordRefreshService(wrapped: service, state: ForcedInitialPasswordState())
    }

    static let passwordService: any SAPSyncPasswordService = ForcedInitialPasswordChangeService()

    fileprivate static func log(_ message: String) {
        print("[SAP Sync Debug] \(launchArgument): \(message)")
    }
}

private actor ForcedInitialPasswordState {
    private var isPending = true

    func consume() -> Bool {
        defer { isPending = false }
        return isPending
    }
}

private struct ForcedInitialPasswordRefreshService: SAPNotificationRefreshService {
    let wrapped: any SAPNotificationRefreshService
    let state: ForcedInitialPasswordState

    func refresh(
        sapPassword: String,
        progress: @escaping SAPReadRefreshProgressHandler
    ) async throws -> SAPCachedData {
        if await state.consume() {
            SAPForcedInitialPasswordChange.log("answering the password as initial without contacting SAP.")
            throw SAPReadError.initialPasswordChangeRequired
        }
        return try await wrapped.refresh(sapPassword: sapPassword, progress: progress)
    }

    func refresh(
        usingToken token: String,
        progress: @escaping SAPReadRefreshProgressHandler
    ) async throws -> SAPCachedData {
        try await wrapped.refresh(usingToken: token, progress: progress)
    }
}

private struct ForcedInitialPasswordChangeService: SAPSyncPasswordService {
    func changeInitialPassword(oldPassword: String, newPassword: String) async throws -> String? {
        try await Task.sleep(for: .seconds(1))
        SAPForcedInitialPasswordChange.log("password change simulated; SAP was not called.")
        return nil
    }
}
#endif
