import Foundation

/// The per-position business rules every MTFM inspection form shares.
///
/// Traced from the legacy Cordova client, where they live in exactly one place
/// for every form code: `HeaderFormBuilder.checkInputConstraints` for the
/// dropdown forms (TFM2/TFM4–TFM8) and the `checkInputConstraints` overrides in
/// `Rundgang.controller.js` / `WartungsPlan.controller.js` for the segmented
/// forms (TFM1/TFM3). They are kept out of the view so a form cannot quietly
/// disagree with its neighbours about what a code means.
enum InspectionFormRules {
    /// The SAP `Befund` code the segmented forms post for a defect.
    ///
    /// `Rundgang`/`WartungsPlan` both compare the selected key against `"X"`
    /// to decide whether a position is defective, whether the comment popover
    /// opens, and whether an I2 defect may be created.
    static let segmentedDefectCode = "X"

    /// What is wrong with one position. Each case maps to the legacy message
    /// the exception popover shows for that constraint.
    enum Issue: Equatable, Sendable {
        /// `msg.viewForm.befund.leer`
        case resultMissing
        /// `msg.viewForm.bemerkungException`
        case commentRequired
        /// `msg.viewForm.befundException`
        case actionAndCommentRequired
        /// `msg.viewForm.massnahmeException`
        case actionNotAllowedForResult
        /// `msg.viewForm.massnahmeMaterialException`
        case materialNotAllowedForResult
        /// `msg.viewForm.befund.leerOutOfOrder`
        case outOfServiceCommentRequired

        var messageKey: String {
            switch self {
            case .resultMissing: "inspection.validation.resultMissing"
            case .commentRequired: "inspection.validation.commentRequired"
            case .actionAndCommentRequired: "inspection.validation.actionAndCommentRequired"
            case .actionNotAllowedForResult: "inspection.validation.actionNotAllowed"
            case .materialNotAllowedForResult: "inspection.validation.materialNotAllowed"
            case .outOfServiceCommentRequired: "inspection.validation.outOfServiceCommentRequired"
            }
        }
    }

    /// Whether a position counts as a defect.
    ///
    /// Dropdown forms: codes `2` and `4` are always defects, `3` is a defect
    /// unless the action is `8` (repaired on site), everything else — including
    /// `1` (in order) and `5` (not present) — is not.
    ///
    /// Segmented forms: the single `X` code is the defect.
    static func isDefective(
        resultCode: String?,
        actionCode: String? = nil,
        style: InspectionControlStyle
    ) -> Bool {
        let result = normalized(resultCode)
        guard !result.isEmpty else { return false }
        switch style {
        case .segmented:
            return result == segmentedDefectCode
        case .dropdown:
            switch result {
            case "2", "4":
                return true
            case "3":
                return normalized(actionCode) != "8"
            default:
                return false
            }
        }
    }

    /// Validates one position. An empty result is only reported when the
    /// position actually carries a result control — the legacy photo-only rows
    /// (`USR00 == "FOTO"`) have none.
    static func issues(
        resultCode: String?,
        actionCode: String? = nil,
        isMaterialSelected: Bool = false,
        comment: String = "",
        requiresResult: Bool = true,
        variant: InspectionFormVariant
    ) -> [Issue] {
        let result = normalized(resultCode)
        let action = normalized(actionCode)
        let hasComment = !comment.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty

        guard !result.isEmpty else {
            return requiresResult ? [.resultMissing] : []
        }

        switch variant.resultStyle {
        case .segmented:
            // `Rundgang` line 621 / `WartungsPlan` line 450: a defect without a
            // comment blocks closing the notification.
            guard variant.requiresCommentForDefect,
                  result == segmentedDefectCode,
                  !hasComment
            else { return [] }
            return [.commentRequired]

        case .dropdown:
            var issues: [Issue] = []
            switch result {
            case "1", "5":
                if isMaterialSelected {
                    issues.append(.materialNotAllowedForResult)
                }
            case "3", "4":
                if action.isEmpty || !hasComment {
                    issues.append(.actionAndCommentRequired)
                } else if result == "4", action == "8" {
                    // A major defect cannot have been repaired on site.
                    issues.append(.actionNotAllowedForResult)
                }
            default:
                break
            }
            return issues
        }
    }

    /// Whether the header-level out-of-service status is documented well enough
    /// to close the form.
    ///
    /// `HeaderFormBuilder.validateFormValues` skips every position while the
    /// status is set and validates only its comment, so this is the whole
    /// closing rule for an out-of-service form.
    static func outOfServiceIssues(comment: String?) -> [Issue] {
        let hasComment = !(comment ?? "").trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        return hasComment ? [] : [.outOfServiceCommentRequired]
    }

    /// Clears the action and material an answered result no longer permits.
    ///
    /// `BaseFormController.onBefundChange` resets the action when the result
    /// becomes `1`, and resets material for `1` and `5`. Returning the changes
    /// instead of mutating keeps this usable from every view model shape.
    static func resolvedSelection(
        resultCode: String?,
        actionCode: String?,
        isMaterialSelected: Bool,
        style: InspectionControlStyle
    ) -> (actionCode: String?, isMaterialSelected: Bool) {
        guard style == .dropdown else { return (actionCode, isMaterialSelected) }
        let result = normalized(resultCode)
        var action = actionCode
        var material = isMaterialSelected
        if result == "1" {
            action = nil
        }
        if result == "1" || result == "5" {
            material = false
        }
        return (action, material)
    }

    private static func normalized(_ value: String?) -> String {
        value?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
    }
}
