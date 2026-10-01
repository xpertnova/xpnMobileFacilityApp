import SwiftUI

struct SAPRefreshPasswordDialog: View {
    @Binding var password: String
    let isRefreshing: Bool
    let stage: SAPReadRefreshStage?
    let error: SAPReadError?
    let failureContext: SAPRefreshFailureContext?
    let refresh: () -> Void
    let cancel: () -> Void
    @FocusState private var isPasswordFocused: Bool

    var body: some View {
        Group {
            if isRefreshing {
                SAPRefreshProgressDialog(stage: stage ?? .authenticating)
            } else {
                passwordEntry
            }
        }
        .animation(.snappy(duration: 0.25), value: isRefreshing)
    }

    private var passwordEntry: some View {
        VStack(alignment: .leading, spacing: 22) {
            HStack(alignment: .top, spacing: 16) {
                VStack(alignment: .leading, spacing: 8) {
                    Text("sap.refresh.password.title")
                        .font(.system(size: 30, weight: .bold, design: .rounded))
                        .foregroundStyle(FacilityTheme.ink)
                    Text("sap.refresh.password.description")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Button("common.cancel", action: cancel)
                    .buttonStyle(.bordered)
                    .disabled(isRefreshing)
            }

            SecureField("sap.refresh.password.placeholder", text: $password)
                .textContentType(.password)
                .focused($isPasswordFocused)
                .textFieldStyle(.roundedBorder)
                .submitLabel(.go)
                .onSubmit {
                    guard !password.isEmpty, !isRefreshing else { return }
                    refresh()
                }

            if let error {
                VStack(alignment: .leading, spacing: 10) {
                    Label {
                        Text(sapRefreshErrorMessage(error))
                    } icon: {
                        Image(systemName: "exclamationmark.circle.fill")
                    }
                    .font(.footnote)
                    .foregroundStyle(FacilityTheme.red)

                    if let failureContext {
                        SAPRefreshFailureDetailsView(context: failureContext)
                    }
                }
            }

            HStack(spacing: 12) {
                if isRefreshing {
                    ProgressView()
                    Text("sap.refresh.progress")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Button("sap.refresh.action", action: refresh)
                    .buttonStyle(.borderedProminent)
                    .tint(FacilityTheme.accent)
                    .disabled(password.isEmpty || isRefreshing)
            }
        }
        .facilityDialogFrame(width: 520, padding: 32)
        .background(.white, in: RoundedRectangle(cornerRadius: 28, style: .continuous))
        .shadow(color: .black.opacity(0.28), radius: 32, y: 18)
        .onAppear { isPasswordFocused = true }
    }
}

private struct SAPRefreshFailureDetailsView: View {
    let context: SAPRefreshFailureContext

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label("sap.refresh.details.title", systemImage: "info.circle")
                .font(.footnote.weight(.semibold))
                .foregroundStyle(FacilityTheme.ink)

            detailRow("sap.refresh.details.stage", value: context.stage.messageText)
            detailRow("sap.refresh.details.operation", value: context.operationText)

            if case let .httpStatus(status) = context.error {
                detailRow(
                    "sap.refresh.details.response",
                    value: String.localizedStringWithFormat(
                        String(localized: "sap.refresh.details.httpStatus", bundle: .appLanguage),
                        status
                    )
                )
            }

            if context.isForbidden {
                Text("sap.refresh.details.forbiddenExplanation")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(FacilityTheme.red.opacity(0.07), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        .accessibilityElement(children: .combine)
    }

    private func detailRow(_ title: LocalizedStringKey, value: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 6) {
            Text(title)
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
            Text(value)
                .font(.caption)
                .foregroundStyle(FacilityTheme.ink)
        }
    }
}

private struct SAPRefreshProgressDialog: View {
    let stage: SAPReadRefreshStage

    var body: some View {
        VStack(spacing: 24) {
            VStack(spacing: 8) {
                Text(stage.messageText)
                    .font(.title3)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .contentTransition(.opacity)
                if let statusText = stage.sapStatusText {
                    Text(statusText)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            ProgressView()
                .controlSize(.large)
                .tint(FacilityTheme.accent)
        }
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.updatesFrequently)
        .frame(maxWidth: .infinity, minHeight: 150)
        .facilityDialogFrame(width: 476, padding: 28, alignment: .center)
        .background(.white, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .stroke(.primary.opacity(0.14), lineWidth: 1)
        }
        .shadow(color: .black.opacity(0.24), radius: 26, y: 12)
    }
}

private extension SAPReadRefreshStage {
    var messageText: String {
        switch self {
        case .authenticating:
            String(localized: "sap.refresh.stage.authenticating", bundle: .appLanguage)
        case .resumingInterruptedSynchronization:
            String(localized: "sap.refresh.stage.resuming", bundle: .appLanguage)
        case .uploadingOutgoingMetadata:
            String(localized: "sap.refresh.stage.uploading", bundle: .appLanguage)
        case let .uploadingOutgoingDocuments(current, total):
            String(
                format: String(localized: "sap.refresh.stage.uploadingDocuments", bundle: .appLanguage),
                current,
                total
            )
        case .postingOutgoingData:
            String(localized: "sap.refresh.stage.posting", bundle: .appLanguage)
        case .waitingForOutgoingAcknowledgement:
            String(localized: "sap.refresh.stage.waitingForPost", bundle: .appLanguage)
        case .checkingAppVersion:
            String(localized: "sap.refresh.stage.version", bundle: .appLanguage)
        case .preparingIncomingData:
            String(localized: "sap.refresh.stage.preparing", bundle: .appLanguage)
        case .waitingForIncomingData:
            String(localized: "sap.refresh.stage.waiting", bundle: .appLanguage)
        case .receivingIncomingPackages(let packageNumber):
            String(format: String(localized: "sap.refresh.stage.receivingPackage", bundle: .appLanguage), packageNumber)
        case .savingSnapshot:
            String(localized: "sap.refresh.stage.saving", bundle: .appLanguage)
        }
    }

    /// The progress text SAP sends while it works (`PARAMETER5`).
    var sapStatusText: String? {
        switch self {
        case let .waitingForOutgoingAcknowledgement(statusText), let .waitingForIncomingData(statusText):
            statusText
        default:
            nil
        }
    }
}

private extension SAPRefreshFailureContext {
    var operationText: String {
        switch stage {
        case .authenticating:
            switch authenticationMethod {
            case .password:
                String(localized: "sap.refresh.details.passwordOperation", bundle: .appLanguage)
            case .savedToken:
                String(localized: "sap.refresh.details.savedTokenOperation", bundle: .appLanguage)
            }
        case .resumingInterruptedSynchronization:
            String(localized: "sap.refresh.details.resumeOperation", bundle: .appLanguage)
        case .uploadingOutgoingMetadata:
            String(localized: "sap.refresh.details.uploadMetadataOperation", bundle: .appLanguage)
        case .uploadingOutgoingDocuments:
            String(localized: "sap.refresh.details.uploadDocumentOperation", bundle: .appLanguage)
        case .postingOutgoingData:
            String(localized: "sap.refresh.details.postOperation", bundle: .appLanguage)
        case .waitingForOutgoingAcknowledgement:
            String(localized: "sap.refresh.details.postAcknowledgementOperation", bundle: .appLanguage)
        case .checkingAppVersion:
            String(localized: "sap.refresh.details.versionOperation", bundle: .appLanguage)
        case .preparingIncomingData:
            String(localized: "sap.refresh.details.prepareIncomingOperation", bundle: .appLanguage)
        case .waitingForIncomingData:
            String(localized: "sap.refresh.details.incomingAcknowledgementOperation", bundle: .appLanguage)
        case .receivingIncomingPackages:
            String(localized: "sap.refresh.details.receivePackageOperation", bundle: .appLanguage)
        case .savingSnapshot:
            String(localized: "sap.refresh.details.saveSnapshotOperation", bundle: .appLanguage)
        }
    }

    var isForbidden: Bool {
        if case .httpStatus(403) = error {
            return true
        }
        return false
    }
}

func sapRefreshErrorMessage(_ error: SAPReadError?) -> String {
    switch error {
    case .configurationUnavailable:
        String(localized: "sap.refresh.error.configuration", bundle: .appLanguage)
    case .authenticatedConnectionUnavailable:
        String(localized: "sap.refresh.error.connection", bundle: .appLanguage)
    case .passwordRequired:
        String(localized: "sap.refresh.error.password", bundle: .appLanguage)
    case .invalidCredentials:
        String(localized: "sap.refresh.error.credentials", bundle: .appLanguage)
    case .initialPasswordChangeRequired:
        String(localized: "sap.refresh.error.initialPassword", bundle: .appLanguage)
    case .tokenInvalidOrExpired:
        String(localized: "sap.refresh.error.tokenExpired", bundle: .appLanguage)
    case .preparationTimedOut:
        String(localized: "sap.refresh.error.timeout", bundle: .appLanguage)
    case .networkUnavailable:
        String(localized: "sap.refresh.error.network", bundle: .appLanguage)
    case .requestTimedOut:
        String(localized: "sap.refresh.error.requestTimeout", bundle: .appLanguage)
    case let .httpStatus(status):
        String.localizedStringWithFormat(String(localized: "sap.refresh.error.httpStatus", bundle: .appLanguage), status)
    case .malformedPayload:
        String(localized: "sap.refresh.error.malformed", bundle: .appLanguage)
    case .serviceUnavailable:
        String(localized: "sap.refresh.error.service", bundle: .appLanguage)
    case let .backendMessage(message):
        message
    case .none:
        String(localized: "sap.refresh.error.generic", bundle: .appLanguage)
    }
}

#if DEBUG
/// An iPad mini with the keyboard up leaves roughly this much room.
#Preview("iPad mini with keyboard", traits: .fixedLayout(width: 1_133, height: 330)) {
    ZStack {
        Color.black.opacity(0.42)
        SAPRefreshPasswordDialog(
            password: .constant(""),
            isRefreshing: false,
            stage: nil,
            error: .invalidCredentials,
            failureContext: nil,
            refresh: {},
            cancel: {}
        )
    }
    .facilityLayoutRoot()
}
#endif
