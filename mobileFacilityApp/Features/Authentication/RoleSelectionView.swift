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
    let workerID: String
    let displayName: String
}

struct RoleSelectionView: View {
    let onSignIn: (FacilityUserRole, LocalAuthenticatedUser) -> Void
    @State private var selectedRole: FacilityUserRole = .technician
    @State private var authenticationSection: AuthenticationSection = .signIn
    @State private var username = ""
    @State private var password = ""
    @State private var confirmedPassword = ""
    @State private var validationMessage: LocalizedStringKey?
    @FocusState private var focusedField: CredentialField?

    /// Height of this screen the docked keyboard covers.
    @State private var keyboardOverlap: CGFloat = 0
    /// Height of the whole card, measured while its introduction is shown.
    @State private var fullCardHeight: CGFloat = 0

    private static let cardOuterPadding: CGFloat = 16
    private static let keyboardCardOuterPadding: CGFloat = 8

    var body: some View {
        GeometryReader { proxy in
            // The screen ignores the keyboard's safe area, so its size, and
            // the card metrics with it, stay the same while typing. The
            // keyboard is handled below from its reported frame instead.
            let metrics = LoginCardMetrics.metrics(for: proxy.size)
            let visibleHeight = max(0, proxy.size.height - keyboardOverlap)
            // With the keyboard up, the logo, title and roles make way for
            // the sign-in fields when the whole card would not fit above it.
            let showsIntroduction = keyboardOverlap == 0
                || fullCardHeight + Self.cardOuterPadding * 2 <= visibleHeight

            ScrollView(.vertical, showsIndicators: false) {
                VStack(spacing: 0) {
                    if showsIntroduction {
                        introduction(metrics: metrics)
                    }

                    VStack(spacing: 0) {
                        authenticationSectionPicker
                            .padding(.top, metrics.pickerTopPadding)

                        credentials(metrics: metrics)

                        Button {
                            focusedField = nil
                            submit()
                        } label: {
                            Text(authenticationSection.actionKey)
                                .font(.headline.weight(.semibold))
                                .frame(maxWidth: .infinity, minHeight: metrics.buttonMinHeight)
                        }
                        .buttonStyle(.borderedProminent)
                        .tint(FacilityTheme.accent)
                        .padding(.top, metrics.buttonTopPadding)
                    }

                    if showsIntroduction {
                        Text("role.selection.footer")
                            .font(metrics.footerFont)
                            .foregroundStyle(.secondary)
                            .multilineTextAlignment(.center)
                            .padding(.top, metrics.footerTopPadding)
                    }
                }
                .padding(.horizontal, metrics.cardHorizontalPadding)
                .padding(
                    .vertical,
                    showsIntroduction ? metrics.cardVerticalPadding : min(metrics.cardVerticalPadding, 16)
                )
                .frame(width: metrics.cardWidth)
                .background(.white, in: RoundedRectangle(cornerRadius: metrics.cardCornerRadius, style: .continuous))
                .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { height in
                    if showsIntroduction {
                        fullCardHeight = height
                    }
                }
                .shadow(color: .black.opacity(0.22), radius: 24, y: 10)
                .padding(
                    .vertical,
                    showsIntroduction ? Self.cardOuterPadding : Self.keyboardCardOuterPadding
                )
                .padding(.horizontal, Self.cardOuterPadding)
                .frame(maxWidth: .infinity, minHeight: visibleHeight, alignment: .center)
                .background {
                    // Tapping the dimmed area around the card dismisses the
                    // keyboard. A tap gesture over the whole screen also fired
                    // for taps on the fields and could clear their focus again.
                    Color.clear
                        .contentShape(Rectangle())
                        .onTapGesture { focusedField = nil }
                }
            }
            .frame(height: visibleHeight)
            .frame(maxHeight: .infinity, alignment: .top)
            .scrollBounceBehavior(.basedOnSize)
            .scrollDismissesKeyboard(.interactively)
        }
        .background {
            KeyboardOverlapReader { overlap, animationDuration in
                withAnimation(animationDuration > 0 ? .easeOut(duration: animationDuration) : nil) {
                    keyboardOverlap = overlap
                }
            }
        }
        .ignoresSafeArea(.keyboard)
    }

    private func introduction(metrics: LoginCardMetrics) -> some View {
        VStack(spacing: 0) {
            XPNMark(height: metrics.badgeHeight)
                .padding(.bottom, metrics.badgeBottomPadding)

            Text("role.selection.title")
                .font(.system(size: metrics.titleSize, weight: .bold, design: .rounded))
                .multilineTextAlignment(.center)
                .foregroundStyle(FacilityTheme.ink)

            Text("role.selection.subtitle")
                .font(metrics.subtitleSize)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.top, 4)
                .padding(.bottom, metrics.subtitleBottomPadding)

            VStack(spacing: metrics.roleSpacing) {
                ForEach(FacilityUserRole.allCases) { role in
                    RoleChoiceCard(
                        role: role,
                        isSelected: selectedRole == role,
                        isEnabled: role == .technician,
                        metrics: metrics
                    ) {
                        selectedRole = role
                    }
                }
            }
        }
    }

    private var authenticationSectionPicker: some View {
        Picker("role.selection.authentication", selection: $authenticationSection) {
            ForEach(AuthenticationSection.allCases) { section in
                Text(section.titleKey).tag(section)
            }
        }
        .pickerStyle(.segmented)
        .onChange(of: authenticationSection) { _, _ in
            password = ""
            confirmedPassword = ""
            validationMessage = nil
        }
    }

    private func credentials(metrics: LoginCardMetrics) -> some View {
        VStack(alignment: .leading, spacing: metrics.fieldSpacing) {
            TextField(
                "role.selection.username",
                text: $username,
                prompt: Text("role.selection.username")
            )
            // These are local shared-device credentials. Use the neutral
            // one-time-code content type to opt this complete form out of
            // Passwords AutoFill; `nil` still allows iPadOS to infer a
            // username/password pair from adjacent secure fields.
            .textContentType(.oneTimeCode)
            .textInputAutocapitalization(.never)
            .autocorrectionDisabled()
            .focused($focusedField, equals: .username)
            .credentialFieldStyle(height: metrics.fieldHeight)
            .submitLabel(.next)
            .onSubmit { focusedField = .password }

            SecureField(
                authenticationSection.passwordPromptKey,
                text: $password,
                prompt: Text(authenticationSection.passwordPromptKey)
            )
            .textContentType(.oneTimeCode)
            .focused($focusedField, equals: .password)
            .credentialFieldStyle(height: metrics.fieldHeight)
            .submitLabel(authenticationSection == .signIn ? .go : .next)
            .onSubmit {
                if authenticationSection == .signIn {
                    focusedField = nil
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
                .textContentType(.oneTimeCode)
                .focused($focusedField, equals: .confirmation)
                .credentialFieldStyle(height: metrics.fieldHeight)
                .submitLabel(.go)
                .onSubmit {
                    focusedField = nil
                    submit()
                }
            }

            if let validationMessage {
                Label {
                    Text(validationMessage)
                } icon: {
                    Image(systemName: "exclamationmark.circle.fill")
                }
                .font(.caption)
                .foregroundStyle(.red)
                .accessibilityElement(children: .combine)
            }
        }
        .padding(.top, metrics.credentialsTopPadding)
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
            let user: LocalAuthenticatedUser
            switch authenticationSection {
            case .signIn:
                user = try LocalCredentialStore.authenticate(
                    username: trimmedUsername,
                    password: password
                )
            case .createPassword:
                guard password == confirmedPassword else {
                    validationMessage = "role.selection.passwordMismatch"
                    focusedField = .confirmation
                    return
                }
                user = try LocalCredentialStore.createAccount(
                    username: trimmedUsername,
                    password: password
                )
            }

            password = ""
            confirmedPassword = ""
            focusedField = nil
            onSignIn(selectedRole, user)
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
        case .storageUnavailable: "role.selection.authenticationUnavailable"
        }
    }
}

private struct LoginCardMetrics {
    let cardWidth: CGFloat
    let cardCornerRadius: CGFloat
    let cardHorizontalPadding: CGFloat
    let cardVerticalPadding: CGFloat
    let badgeHeight: CGFloat
    let badgeBottomPadding: CGFloat
    let titleSize: CGFloat
    let subtitleSize: Font
    let subtitleBottomPadding: CGFloat
    let roleCardMinHeight: CGFloat
    let roleIconSize: CGFloat
    let roleSpacing: CGFloat
    let rolePaddingH: CGFloat
    let rolePaddingV: CGFloat
    let roleTitleFont: Font
    let roleSubtitleFont: Font
    let pickerTopPadding: CGFloat
    let credentialsTopPadding: CGFloat
    let fieldHeight: CGFloat
    let fieldSpacing: CGFloat
    let buttonMinHeight: CGFloat
    let buttonTopPadding: CGFloat
    let footerTopPadding: CGFloat
    let footerFont: Font

    static func metrics(for size: CGSize) -> LoginCardMetrics {
        // iPad Mini (landscape height ~744 pt) or narrow Multitasking Split View
        if size.height < 780 || size.width < 900 {
            return LoginCardMetrics(
                cardWidth: min(500, max(360, size.width - 48)),
                cardCornerRadius: 26,
                cardHorizontalPadding: 32,
                cardVerticalPadding: 22,
                badgeHeight: 38,
                badgeBottomPadding: 12,
                titleSize: 22,
                subtitleSize: .subheadline,
                subtitleBottomPadding: 14,
                roleCardMinHeight: 56,
                roleIconSize: 40,
                roleSpacing: 8,
                rolePaddingH: 14,
                rolePaddingV: 8,
                roleTitleFont: .subheadline.weight(.bold),
                roleSubtitleFont: .caption,
                pickerTopPadding: 14,
                credentialsTopPadding: 10,
                fieldHeight: 44,
                fieldSpacing: 8,
                buttonMinHeight: 48,
                buttonTopPadding: 16,
                footerTopPadding: 12,
                footerFont: .caption2
            )
        } else if size.height < 920 {
            // Standard iPad (10.2", 10.9", 11" Pro — landscape height 810–834 pt)
            let width = min(580, max(520, size.width * 0.48))
            return LoginCardMetrics(
                cardWidth: width,
                cardCornerRadius: 30,
                cardHorizontalPadding: 42,
                cardVerticalPadding: 28,
                badgeHeight: 46,
                badgeBottomPadding: 16,
                titleSize: 26,
                subtitleSize: .callout,
                subtitleBottomPadding: 18,
                roleCardMinHeight: 68,
                roleIconSize: 46,
                roleSpacing: 10,
                rolePaddingH: 16,
                rolePaddingV: 11,
                roleTitleFont: .headline.weight(.bold),
                roleSubtitleFont: .subheadline,
                pickerTopPadding: 18,
                credentialsTopPadding: 14,
                fieldHeight: 48,
                fieldSpacing: 10,
                buttonMinHeight: 52,
                buttonTopPadding: 18,
                footerTopPadding: 16,
                footerFont: .footnote
            )
        } else {
            // Large iPad Pro (12.9" / 13" — landscape height 1024 pt)
            let width = min(630, max(560, size.width * 0.46))
            return LoginCardMetrics(
                cardWidth: width,
                cardCornerRadius: 32,
                cardHorizontalPadding: 46,
                cardVerticalPadding: 32,
                badgeHeight: 52,
                badgeBottomPadding: 20,
                titleSize: 28,
                subtitleSize: .body,
                subtitleBottomPadding: 20,
                roleCardMinHeight: 74,
                roleIconSize: 50,
                roleSpacing: 12,
                rolePaddingH: 18,
                rolePaddingV: 13,
                roleTitleFont: .headline.weight(.bold),
                roleSubtitleFont: .subheadline,
                pickerTopPadding: 20,
                credentialsTopPadding: 14,
                fieldHeight: 50,
                fieldSpacing: 11,
                buttonMinHeight: 56,
                buttonTopPadding: 20,
                footerTopPadding: 18,
                footerFont: .subheadline
            )
        }
    }
}

/// The brand mark on the sign-in card. It carries no action: a pointer
/// hovering over it lifts it slightly, and a tap plays a short spring bounce.
/// Both are skipped under Reduce Motion.
private struct XPNMark: View {
    let height: CGFloat

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var isHovering = false
    @State private var bounceCount = 0

    /// Dip, overshoot, settle — the phases one tap runs through.
    private static let bouncePhases: [CGFloat] = [1, 0.93, 1.06, 1]

    private var shape: RoundedRectangle {
        RoundedRectangle(cornerRadius: height * 0.28, style: .continuous)
    }

    var body: some View {
        Text(".XPN")
            .font(height > 44 ? .title3.weight(.heavy) : .headline.weight(.heavy))
            .foregroundStyle(.white)
            .padding(.horizontal, height * 0.42)
            .frame(height: height)
            .background(FacilityTheme.navy, in: shape)
            .phaseAnimator(Self.bouncePhases, trigger: bounceCount) { mark, scale in
                mark.scaleEffect(scale)
            } animation: { _ in
                .spring(response: 0.24, dampingFraction: 0.55)
            }
            .scaleEffect(isHovering ? 1.04 : 1)
            .shadow(
                color: FacilityTheme.navy.opacity(isHovering ? 0.28 : 0),
                radius: isHovering ? 14 : 0,
                y: isHovering ? 8 : 0
            )
            .animation(.snappy(duration: 0.20), value: isHovering)
            .contentShape(shape)
            .onHover { hovering in
                isHovering = hovering && !reduceMotion
            }
            .onTapGesture {
                guard !reduceMotion else { return }
                bounceCount += 1
            }
    }
}

private struct RoleChoiceCard: View {
    let role: FacilityUserRole
    let isSelected: Bool
    let isEnabled: Bool
    let metrics: LoginCardMetrics
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 14) {
                Image(systemName: role.symbol)
                    .font(.system(size: metrics.roleIconSize * 0.45, weight: .semibold))
                    .foregroundStyle(FacilityTheme.accent)
                    .frame(width: metrics.roleIconSize, height: metrics.roleIconSize)
                    .background(FacilityTheme.accentSoft, in: RoundedRectangle(cornerRadius: metrics.roleIconSize * 0.28, style: .continuous))

                VStack(alignment: .leading, spacing: 2) {
                    Text(LocalizedStringKey(role.titleKey))
                        .font(metrics.roleTitleFont)
                        .foregroundStyle(FacilityTheme.ink)
                    Text(LocalizedStringKey(role.subtitleKey))
                        .font(metrics.roleSubtitleFont)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.leading)
                        .lineLimit(2)
                }

                Spacer(minLength: 0)
                if isSelected {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundStyle(FacilityTheme.accent)
                        .font(.body)
                        .accessibilityHidden(true)
                }
            }
            .padding(.horizontal, metrics.rolePaddingH)
            .padding(.vertical, metrics.rolePaddingV)
            .frame(maxWidth: .infinity, minHeight: metrics.roleCardMinHeight, alignment: .leading)
            .background(isSelected ? FacilityTheme.accentSoft : .white, in: RoundedRectangle(cornerRadius: metrics.cardCornerRadius * 0.5, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: metrics.cardCornerRadius * 0.5, style: .continuous)
                    .stroke(isSelected ? FacilityTheme.accent : .black.opacity(0.12), lineWidth: isSelected ? 2 : 1)
            }
        }
        .buttonStyle(.plain)
        .disabled(!isEnabled)
        .opacity(isEnabled ? 1.0 : 0.6)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }
}

private extension View {
    func credentialFieldStyle(height: CGFloat = 44) -> some View {
        self
            .font(.body)
            .padding(.horizontal, 14)
            .frame(height: height)
            .background(FacilityTheme.canvas, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .stroke(.black.opacity(0.12), lineWidth: 1)
            }
    }
}
