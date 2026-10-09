import SwiftUI

/// The legacy `ChangePasswordDialog`: SAP accepted the synchronization
/// password but it is still the initial one, so a new one is set before the
/// synchronization continues. The rules beside the fields tick off while the
/// technician types, which is also why Save is unavailable.
struct SAPInitialPasswordDialog: View {
    /// The worker ID, which the new password must not contain.
    let userName: String
    /// The password SAP just accepted as initial.
    let initialOldPassword: String
    let save: (_ oldPassword: String, _ newPassword: String) async throws -> Void
    let cancel: () -> Void

    @State private var oldPassword = ""
    @State private var newPassword = ""
    @State private var repetition = ""
    @State private var isSaving = false
    @State private var isChanged = false
    @State private var errorMessage: String?
    @FocusState private var focusedField: Field?

    private enum Field {
        case old, new, repetition
    }

    private var satisfiedRules: Set<SyncPasswordRules.Rule> {
        SyncPasswordRules.satisfiedRules(by: newPassword, userName: userName)
    }

    private var validation: SyncPasswordRules.Validation {
        SyncPasswordRules.validate(newPassword: newPassword, repetition: repetition, userName: userName)
    }

    private var canSave: Bool {
        !oldPassword.isEmpty && validation == .valid && !isSaving && !isChanged
    }

    /// The field problem the checklist cannot show: blanks, or a repetition
    /// that differs once it is as long as the new password.
    private var fieldMessage: LocalizedStringKey? {
        if SyncPasswordRules.containsWhitespace(newPassword) {
            return "sap.password.change.error.whitespace"
        }
        if !repetition.isEmpty, repetition.count >= newPassword.count, repetition != newPassword {
            return "sap.password.change.error.mismatch"
        }
        return nil
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 22) {
            HStack(alignment: .top, spacing: 16) {
                VStack(alignment: .leading, spacing: 8) {
                    Text("sap.password.change.title")
                        .font(.system(size: 30, weight: .bold, design: .rounded))
                        .foregroundStyle(FacilityTheme.ink)
                    Text("sap.password.change.description")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer()
                Button("common.cancel", action: cancel)
                    .buttonStyle(.bordered)
                    .disabled(isSaving || isChanged)
            }

            FacilityColumnsLayout(columnCounts: [2, 1], minimumColumnWidth: 250, spacing: 20) {
                fields
                rules
            }

            if let errorMessage {
                Label {
                    Text(errorMessage)
                } icon: {
                    Image(systemName: "exclamationmark.circle.fill")
                }
                .font(.footnote)
                .foregroundStyle(FacilityTheme.red)
            }

            HStack(spacing: 12) {
                if isSaving {
                    ProgressView()
                    Text("sap.password.change.saving")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                } else if isChanged {
                    Label("sap.password.change.success", systemImage: "checkmark.circle.fill")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(FacilityTheme.accent)
                }
                Spacer()
                Button("sap.password.change.save", action: submit)
                    .buttonStyle(.borderedProminent)
                    .tint(FacilityTheme.accent)
                    .disabled(!canSave)
            }
        }
        .facilityDialogFrame(width: 720, padding: 32)
        .background(.white, in: RoundedRectangle(cornerRadius: 28, style: .continuous))
        .shadow(color: .black.opacity(0.28), radius: 32, y: 18)
        .onAppear {
            oldPassword = initialOldPassword
            focusedField = initialOldPassword.isEmpty ? .old : .new
        }
    }

    private var fields: some View {
        VStack(alignment: .leading, spacing: 12) {
            SecureField("sap.password.change.old", text: $oldPassword)
                .textContentType(.password)
                .focused($focusedField, equals: .old)
                .submitLabel(.next)
                .onSubmit { focusedField = .new }
            SecureField("sap.password.change.new", text: $newPassword)
                .textContentType(.newPassword)
                .focused($focusedField, equals: .new)
                .submitLabel(.next)
                .onSubmit { focusedField = .repetition }
            SecureField("sap.password.change.repeat", text: $repetition)
                .textContentType(.newPassword)
                .focused($focusedField, equals: .repetition)
                .submitLabel(.done)
                .onSubmit { if canSave { submit() } }
            if let fieldMessage {
                Label {
                    Text(fieldMessage)
                } icon: {
                    Image(systemName: "exclamationmark.circle.fill")
                }
                .font(.footnote)
                .foregroundStyle(FacilityTheme.red)
            }
        }
        .textFieldStyle(.roundedBorder)
        .autocorrectionDisabled()
        .textInputAutocapitalization(.never)
        .disabled(isSaving || isChanged)
        .onChange(of: oldPassword) { _, _ in errorMessage = nil }
        .onChange(of: newPassword) { _, _ in errorMessage = nil }
    }

    private var rules: some View {
        VStack(alignment: .leading, spacing: 10) {
            Label("sap.password.change.rules.title", systemImage: "info.circle")
                .font(.footnote.weight(.semibold))
                .foregroundStyle(FacilityTheme.ink)
            ForEach(SyncPasswordRules.Rule.allCases, id: \.self) { rule in
                ruleRow(rule)
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(FacilityTheme.canvas, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
    }

    private func ruleRow(_ rule: SyncPasswordRules.Rule) -> some View {
        let isMet = satisfiedRules.contains(rule)
        let state: (symbol: String, color: Color) = newPassword.isEmpty
            ? ("circle", .secondary)
            : isMet ? ("checkmark.circle.fill", FacilityTheme.accent) : ("xmark.circle.fill", FacilityTheme.red)
        return HStack(alignment: .firstTextBaseline, spacing: 8) {
            Image(systemName: state.symbol)
                .foregroundStyle(state.color)
            Text(rule.textKey)
                .font(.footnote)
                .foregroundStyle(FacilityTheme.ink)
                .fixedSize(horizontal: false, vertical: true)
        }
        .accessibilityElement(children: .combine)
        .accessibilityValue(isMet ? Text("sap.password.change.rule.met") : Text("sap.password.change.rule.unmet"))
    }

    private func submit() {
        guard canSave else { return }
        errorMessage = nil
        isSaving = true
        let old = oldPassword
        let new = newPassword
        Task {
            do {
                try await save(old, new)
                isSaving = false
                isChanged = true
            } catch {
                isSaving = false
                errorMessage = sapPasswordChangeErrorMessage(error)
            }
        }
    }
}

private extension SyncPasswordRules.Rule {
    var textKey: LocalizedStringKey {
        switch self {
        case .excludesUserName: "sap.password.change.rule.userName"
        case .uppercaseLetter: "sap.password.change.rule.uppercase"
        case .lowercaseLetter: "sap.password.change.rule.lowercase"
        case .digit: "sap.password.change.rule.digit"
        case .minimumLength: "sap.password.change.rule.length"
        case .specialCharacter: "sap.password.change.rule.special"
        }
    }
}

func sapPasswordChangeErrorMessage(_ error: Error) -> String {
    switch error {
    case SAPSyncPasswordError.changeRejected:
        String(localized: "sap.password.change.error.rejected", bundle: .appLanguage)
    case let error as SAPReadError:
        sapRefreshErrorMessage(error)
    default:
        String(localized: "sap.password.change.error.rejected", bundle: .appLanguage)
    }
}

#if DEBUG
#Preview("Initial password", traits: .fixedLayout(width: 1_133, height: 744)) {
    ZStack {
        FacilityTheme.dialogScrim
        SAPInitialPasswordDialog(
            userName: "S50828",
            initialOldPassword: "Init1234",
            save: { _, _ in },
            cancel: {}
        )
    }
    .facilityLayoutRoot()
}

/// An iPad mini with the keyboard up leaves roughly this much room.
#Preview("iPad mini with keyboard", traits: .fixedLayout(width: 700, height: 330)) {
    ZStack {
        FacilityTheme.dialogScrim
        SAPInitialPasswordDialog(
            userName: "S50828",
            initialOldPassword: "",
            save: { _, _ in throw SAPSyncPasswordError.changeRejected },
            cancel: {}
        )
    }
    .facilityLayoutRoot()
}
#endif
