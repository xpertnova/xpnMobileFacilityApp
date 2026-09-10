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
        .padding(32)
        .frame(width: 520, alignment: .leading)
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
                        String(localized: "sap.refresh.details.httpStatus"),
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
            Text(stage.messageText)
                .font(.title3)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .contentTransition(.opacity)
            ProgressView()
                .controlSize(.large)
                .tint(FacilityTheme.accent)
        }
        .frame(width: 420)
        .frame(minHeight: 150)
        .padding(28)
        .background(.white, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .stroke(.primary.opacity(0.14), lineWidth: 1)
        }
        .shadow(color: .black.opacity(0.24), radius: 26, y: 12)
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.updatesFrequently)
    }
}

private extension SAPReadRefreshStage {
    var messageText: String {
        switch self {
        case .authenticating:
            String(localized: "sap.refresh.stage.authenticating")
        case .uploadingOutgoingMetadata:
            String(localized: "sap.refresh.stage.uploading")
        case .postingOutgoingData:
            String(localized: "sap.refresh.stage.posting")
        case .waitingForOutgoingAcknowledgement:
            String(localized: "sap.refresh.stage.waitingForPost")
        case .checkingAppVersion:
            String(localized: "sap.refresh.stage.version")
        case .preparingIncomingData:
            String(localized: "sap.refresh.stage.preparing")
        case .waitingForIncomingData:
            String(localized: "sap.refresh.stage.waiting")
        case .receivingIncomingPackages(let packageNumber):
            String(format: String(localized: "sap.refresh.stage.receivingPackage"), packageNumber)
        case .savingSnapshot:
            String(localized: "sap.refresh.stage.saving")
        }
    }
}

private extension SAPRefreshFailureContext {
    var operationText: String {
        switch authenticationMethod {
        case .password:
            String(localized: "sap.refresh.details.passwordOperation")
        case .savedToken:
            String(localized: "sap.refresh.details.savedTokenOperation")
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
        String(localized: "sap.refresh.error.configuration")
    case .authenticatedConnectionUnavailable:
        String(localized: "sap.refresh.error.connection")
    case .passwordRequired:
        String(localized: "sap.refresh.error.password")
    case .invalidCredentials:
        String(localized: "sap.refresh.error.credentials")
    case .initialPasswordChangeRequired:
        String(localized: "sap.refresh.error.initialPassword")
    case .tokenInvalidOrExpired:
        String(localized: "The SAP session token is invalid or has expired on another device.")
    case .preparationTimedOut:
        String(localized: "sap.refresh.error.timeout")
    case .networkUnavailable:
        String(localized: "sap.refresh.error.network")
    case .requestTimedOut:
        String(localized: "sap.refresh.error.requestTimeout")
    case let .httpStatus(status):
        String.localizedStringWithFormat(String(localized: "sap.refresh.error.httpStatus"), status)
    case .malformedPayload:
        String(localized: "sap.refresh.error.malformed")
    case .serviceUnavailable:
        String(localized: "sap.refresh.error.service")
    case let .backendMessage(message):
        message
    case .none:
        String(localized: "sap.refresh.error.generic")
    }
}
