import SwiftUI

enum FacilityUserRole: String, CaseIterable, Identifiable {
    case technician
    case contractor
    case centralControl

    var id: String { rawValue }

    var titleKey: String {
        switch self {
        case .technician: "role.technician.title"
        case .contractor: "role.contractor.title"
        case .centralControl: "role.centralControl.title"
        }
    }

    var subtitleKey: String {
        switch self {
        case .technician: "role.technician.subtitle"
        case .contractor: "role.contractor.subtitle"
        case .centralControl: "role.centralControl.subtitle"
        }
    }

    var symbol: String {
        switch self {
        case .technician: "wrench.and.screwdriver.fill"
        case .contractor: "person.2.fill"
        case .centralControl: "chart.bar.fill"
        }
    }
}

struct FacilityUserSession: Equatable {
    let role: FacilityUserRole
    let displayName: String
}

struct RoleSelectionView: View {
    let onSignIn: (FacilityUserRole, String) -> Void
    @State private var selectedRole: FacilityUserRole = .technician
    @State private var authenticationSection: AuthenticationSection = .signIn
    @State private var username = ""
    @State private var password = ""
    @State private var confirmedPassword = ""
    @State private var validationMessage: LocalizedStringKey?
    @FocusState private var focusedField: CredentialField?

    var body: some View {
        GeometryReader { proxy in
            VStack {
                VStack(spacing: 0) {
                    XPNMark()
                        .padding(.bottom, 25)

                    Text("role.selection.title")
                        .font(.system(size: 29, weight: .bold, design: .rounded))
                        .multilineTextAlignment(.center)
                        .foregroundStyle(FacilityTheme.ink)
                    Text("role.selection.subtitle")
                        .font(.title3)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                        .padding(.top, 6)
                        .padding(.bottom, 28)

                    VStack(spacing: 13) {
                        ForEach(FacilityUserRole.allCases) { role in
                            RoleChoiceCard(role: role, isSelected: selectedRole == role) {
                                selectedRole = role
                            }
                        }
                    }

                    authenticationSectionPicker
                    credentials

                    Button {
                        submit()
                    } label: {
                        Text(authenticationSection.actionKey)
                            .font(.headline.weight(.semibold))
                            .frame(maxWidth: .infinity, minHeight: 58)
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(FacilityTheme.accent)
                    .padding(.top, 20)

                    Text("role.selection.footer")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                        .padding(.top, 22)
                }
                .padding(.horizontal, 48)
                .padding(.vertical, 32)
                .frame(width: min(610, max(440, proxy.size.width - 48)))
                .background(.white, in: RoundedRectangle(cornerRadius: 32, style: .continuous))
                .shadow(color: .black.opacity(0.32), radius: 32, y: 18)
                .padding(24)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    private var authenticationSectionPicker: some View {
        Picker("role.selection.authentication", selection: $authenticationSection) {
            ForEach(AuthenticationSection.allCases) { section in
                Text(section.titleKey).tag(section)
            }
        }
        .pickerStyle(.segmented)
        .padding(.top, 20)
        .onChange(of: authenticationSection) { _, _ in
            password = ""
            confirmedPassword = ""
            validationMessage = nil
        }
    }

    private var credentials: some View {
        VStack(alignment: .leading, spacing: 10) {
            TextField(
                "role.selection.username",
                text: $username,
                prompt: Text("role.selection.username")
            )
            .textContentType(.username)
            .textInputAutocapitalization(.never)
            .autocorrectionDisabled()
            .focused($focusedField, equals: .username)
            .credentialFieldStyle()
            .submitLabel(.next)
            .onSubmit { focusedField = .password }

            SecureField(
                authenticationSection.passwordPromptKey,
                text: $password,
                prompt: Text(authenticationSection.passwordPromptKey)
            )
            .textContentType(authenticationSection == .signIn ? .password : .newPassword)
            .focused($focusedField, equals: .password)
            .credentialFieldStyle()
            .submitLabel(authenticationSection == .signIn ? .go : .next)
            .onSubmit {
                if authenticationSection == .signIn {
                    submit()
                } else {
                    focusedField = .confirmation
                }
            }

            if authenticationSection == .createPassword {
                SecureField(
                    "role.selection.confirmPassword",
                    text: $confirmedPassword,
                    prompt: Text("role.selection.confirmPassword")
                )
                .textContentType(.newPassword)
                .focused($focusedField, equals: .confirmation)
                .credentialFieldStyle()
                .submitLabel(.go)
                .onSubmit(submit)

                Text("role.selection.passwordRequirement")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }

            if let validationMessage {
                Label {
                    Text(validationMessage)
                } icon: {
                    Image(systemName: "exclamationmark.circle.fill")
                }
                .font(.footnote)
                .foregroundStyle(.red)
                .accessibilityElement(children: .combine)
            }
        }
        .padding(.top, 14)
        .onChange(of: username) { _, _ in validationMessage = nil }
        .onChange(of: password) { _, _ in validationMessage = nil }
        .onChange(of: confirmedPassword) { _, _ in validationMessage = nil }
    }

    private func submit() {
        let trimmedUsername = username.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedUsername.isEmpty, !password.isEmpty else {
            validationMessage = "role.selection.missingCredentials"
            focusedField = trimmedUsername.isEmpty ? .username : .password
            return
        }

        do {
            let displayName: String
            switch authenticationSection {
            case .signIn:
                displayName = try LocalCredentialStore.authenticate(
                    username: trimmedUsername,
                    password: password
                )
            case .createPassword:
                guard password == confirmedPassword else {
                    validationMessage = "role.selection.passwordMismatch"
                    focusedField = .confirmation
                    return
                }
                displayName = try LocalCredentialStore.createAccount(
                    username: trimmedUsername,
                    password: password
                )
            }

            password = ""
            confirmedPassword = ""
            focusedField = nil
            onSignIn(selectedRole, displayName)
        } catch let error as LocalCredentialStoreError {
            validationMessage = error.localizedKey
        } catch {
            validationMessage = "role.selection.authenticationUnavailable"
        }
    }
}

private enum AuthenticationSection: CaseIterable, Identifiable {
    case signIn
    case createPassword

    var id: Self { self }

    var titleKey: LocalizedStringKey {
        switch self {
        case .signIn: "role.selection.signIn"
        case .createPassword: "role.selection.createPassword"
        }
    }

    var actionKey: LocalizedStringKey {
        switch self {
        case .signIn: "role.selection.signIn"
        case .createPassword: "role.selection.createPassword.action"
        }
    }

    var passwordPromptKey: LocalizedStringKey {
        switch self {
        case .signIn: "role.selection.password"
        case .createPassword: "role.selection.newPassword"
        }
    }
}

private enum CredentialField {
    case username
    case password
    case confirmation
}

private extension LocalCredentialStoreError {
    var localizedKey: LocalizedStringKey {
        switch self {
        case .usernameAlreadyExists: "role.selection.usernameAlreadyExists"
        case .invalidCredentials: "role.selection.invalidCredentials"
        case .passwordRequirementsNotMet: "role.selection.passwordRequirement"
        case .storageUnavailable: "role.selection.authenticationUnavailable"
        }
    }
}

private struct XPNMark: View {
    var body: some View {
        Text(".XPN")
            .font(.title2.weight(.heavy))
            .foregroundStyle(.white)
            .padding(.horizontal, 20)
            .frame(height: 62)
            .background(FacilityTheme.navy, in: RoundedRectangle(cornerRadius: 17, style: .continuous))
    }
}

private struct RoleChoiceCard: View {
    let role: FacilityUserRole
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 17) {
                Image(systemName: role.symbol)
                    .font(.title3.weight(.semibold))
                    .foregroundStyle(FacilityTheme.accent)
                    .frame(width: 54, height: 54)
                    .background(FacilityTheme.accentSoft, in: RoundedRectangle(cornerRadius: 14, style: .continuous))

                VStack(alignment: .leading, spacing: 4) {
                    Text(LocalizedStringKey(role.titleKey))
                        .font(.headline.weight(.bold))
                        .foregroundStyle(FacilityTheme.ink)
                    Text(LocalizedStringKey(role.subtitleKey))
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.leading)
                }

                Spacer(minLength: 0)
                if isSelected {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundStyle(FacilityTheme.accent)
                        .font(.title3)
                        .accessibilityHidden(true)
                }
            }
            .padding(15)
            .frame(maxWidth: .infinity, minHeight: 88, alignment: .leading)
            .background(isSelected ? FacilityTheme.accentSoft : .white, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .stroke(isSelected ? FacilityTheme.accent : .black.opacity(0.12), lineWidth: isSelected ? 2 : 1)
            }
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }
}

private extension View {
    func credentialFieldStyle() -> some View {
        self
            .font(.body)
            .padding(.horizontal, 16)
            .frame(height: 48)
            .background(FacilityTheme.canvas, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .stroke(.black.opacity(0.12), lineWidth: 1)
            }
    }
}
