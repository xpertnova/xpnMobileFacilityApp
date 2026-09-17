import Foundation

/// "Pflege durch Admin" and its `Vorschlag` (proposal), shared by every form
/// whose master-data value lists offer that entry.
///
/// Traced from the legacy `HeaderFormBuilder.js`, which builds the same flow
/// for every form header: `_buildHeaderForm` moves the entry to the top of the
/// list and adds a disabled edit button beside the field; `onChangeHeader`
/// enables that button and opens `VorschlagPopover` when the entry is picked,
/// and deletes the proposal (`deleteVorschlag`) when another value replaces
/// it; `validateMasterData` / `isVorschlagValid` block closing while the
/// entry has no proposal; `insertSaveProcessVorschlag` writes one `TO_T0211`
/// row per proposal, which the next sync sends to SAP.
///
/// The field itself keeps "Pflege durch Admin" as its value. The proposal is
/// free text for the SAP administrator and never becomes a list value.
enum MasterDataProposalRules {
    /// `util.constanten.constSTAMMDATEN_ADMIN`.
    static let adminKey = "PFLEGE DURCH ADMIN"
    static let adminText = "Pflege durch Admin"
    /// `util.constanten.constSTAMMDATEN_UNKNOWN`.
    static let unknownText = "nicht bekannt"
    /// `maxLength` of the `vorschlag.input` field.
    static let maximumLength = 80

    /// `true` for the "Pflege durch Admin" entry, matched by its text or its
    /// SAP key like the legacy comparisons.
    static func isAdmin(text: String, code: String = "") -> Bool {
        matches(text, adminText) || matches(code, adminKey)
    }

    static func isUnknown(text: String) -> Bool {
        matches(text, unknownText)
    }

    /// `_buildHeaderForm` adds the regular entries in SAP order, then calls
    /// `insertItem(unknown, -1)` and `insertItem(admin, -1)`. UI5 clamps a
    /// negative index to 0, so both land on top: "Pflege durch Admin" first,
    /// "nicht bekannt" second.
    static func ordered<Option>(
        _ options: [Option],
        text: (Option) -> String,
        code: (Option) -> String = { _ in "" }
    ) -> [Option] {
        var admin: [Option] = [], unknown: [Option] = [], regular: [Option] = []
        for option in options {
            if isAdmin(text: text(option), code: code(option)) {
                admin.append(option)
            } else if isUnknown(text: text(option)) {
                unknown.append(option)
            } else {
                regular.append(option)
            }
        }
        return admin + unknown + regular
    }

    static func ordered(_ options: [String]) -> [String] {
        ordered(options, text: { $0 })
    }

    /// `onPressVorschlagSave` trims the input; the input allows 80 characters.
    /// An empty result removes the proposal.
    static func normalized(_ proposal: String) -> String {
        String(proposal.trimmingCharacters(in: .whitespacesAndNewlines).prefix(maximumLength))
    }

    /// `isVorschlagValid`: a field holding "Pflege durch Admin" needs a
    /// proposal before the form can be closed.
    static func isMissingProposal(selectsAdmin: Bool, proposal: String?) -> Bool {
        selectsAdmin && normalized(proposal ?? "").isEmpty
    }

    /// What a value change means for the field's proposal (`onChangeHeader`).
    enum SelectionChange: Equatable {
        /// "Pflege durch Admin" was picked: ask for a proposal.
        case requestProposal
        /// "Pflege durch Admin" was replaced: drop the proposal.
        case removeProposal
        case none
    }

    static func selectionChange(wasAdmin: Bool, isAdmin: Bool) -> SelectionChange {
        switch (wasAdmin, isAdmin) {
        case (false, true): .requestProposal
        case (true, false): .removeProposal
        default: .none
        }
    }

    /// `vorschlagBeforeOpen` shows every distinct `FELDWERT` of the unsent
    /// `TO_T0211` rows for the field and object as tokens, newest first.
    static func history(_ proposals: [String]) -> [String] {
        var seen = Set<String>()
        return proposals.map(normalized).filter { !$0.isEmpty && seen.insert($0).inserted }
    }

    private static func matches(_ value: String, _ constant: String) -> Bool {
        value.trimmingCharacters(in: .whitespacesAndNewlines).uppercased() == constant.uppercased()
    }
}
