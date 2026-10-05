import Foundation

/// The rules a new MTFM synchronization password must meet, from the legacy
/// `ChangePasswordDialog` (`passwordLiveCheck`, `_validatePassword`,
/// `onChangePwdSubmit` and `nBpmUtil.verifyPwd`). SAP may check more.
enum SyncPasswordRules {
    enum Rule: CaseIterable, Hashable, Sendable {
        /// `text.changeDialog.rule.userId`: the user name, in any case, is
        /// not part of the password.
        case excludesUserName
        case uppercaseLetter
        case lowercaseLetter
        case digit
        case minimumLength
        case specialCharacter
    }

    enum Validation: Equatable, Sendable {
        case valid
        /// `msg.initial.error.whitespace`.
        case containsWhitespace
        /// `msg.inital.pwd.notAllowed`.
        case rulesNotMet
        /// `msg.inital.pwd.diff`.
        case repetitionDiffers
    }

    static let minimumLength = 8
    /// The characters `text.changeDialog.rule.special` names. The legacy
    /// pattern `[!,&,$,#,*,+,-,?,=]` reads `+,-` as a range and so rejects
    /// `-`, which the hint promises; the hint is followed here.
    static let specialCharacters: Set<Character> = ["!", "&", "$", "#", "*", "+", "-", "?", "="]

    /// The rules `password` meets, for the live checklist beside the fields.
    static func satisfiedRules(by password: String, userName: String) -> Set<Rule> {
        var rules: Set<Rule> = []
        let user = userName.trimmingCharacters(in: .whitespacesAndNewlines)
        if user.isEmpty || !password.lowercased().contains(user.lowercased()) {
            rules.insert(.excludesUserName)
        }
        // `verifyPwd` matches ASCII letters only.
        if password.contains(where: { ("A"..."Z").contains($0) }) { rules.insert(.uppercaseLetter) }
        if password.contains(where: { ("a"..."z").contains($0) }) { rules.insert(.lowercaseLetter) }
        if password.contains(where: { ("0"..."9").contains($0) }) { rules.insert(.digit) }
        if password.count >= minimumLength { rules.insert(.minimumLength) }
        if password.contains(where: specialCharacters.contains) { rules.insert(.specialCharacter) }
        return rules
    }

    static func containsWhitespace(_ password: String) -> Bool {
        password.contains(where: \.isWhitespace)
    }

    /// The checks of `onChangePwdSubmit`, in its order.
    static func validate(newPassword: String, repetition: String, userName: String) -> Validation {
        if containsWhitespace(newPassword) { return .containsWhitespace }
        if satisfiedRules(by: newPassword, userName: userName) != Set(Rule.allCases) { return .rulesNotMet }
        if newPassword != repetition { return .repetitionDiffers }
        return .valid
    }
}
