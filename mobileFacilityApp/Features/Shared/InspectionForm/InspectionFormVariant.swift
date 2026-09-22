import Foundation

/// One selectable value of an inspection control, exactly as SAP supplies it in
/// the `T_PROPS` property row (`DFVAL` keys paired with `DFVAL_TXT` texts).
///
/// `code` is the transport value and is never localized. `title` is display
/// text only — the legacy Cordova client shows `DFVAL_TXT` but always posts
/// `DFVAL`, and the same split has to survive here.
struct InspectionFormOption: Identifiable, Equatable, Sendable {
    /// Tint applied to the selected segment of a segmented control.
    ///
    /// Only the segmented variant paints its selection; the dropdown variant
    /// shows the bare SAP code the way `sap.m.Select` does.
    enum Tint: Equatable, Sendable {
        case neutral
        case satisfactory
        case defect
    }

    /// Stable UI identity. It equals `code` for SAP-code controls. The yes/no
    /// controls of TFM1/TFM3 need a separate identity because their
    /// "in Ordnung" transport code is an empty string, which is
    /// indistinguishable from "not yet answered".
    let id: String
    let code: String
    let title: String
    let tint: Tint

    init(id: String? = nil, code: String, title: String, tint: Tint = .neutral) {
        self.id = id ?? code
        self.code = code
        self.title = title
        self.tint = tint
    }

    /// Convenience for options whose text comes from the String Catalog rather
    /// than from SAP metadata (TFM1/TFM3 yes/no, TFM5 fixed code lists).
    init(id: String? = nil, code: String, titleKey: String, tint: Tint = .neutral) {
        self.init(
            id: id,
            code: code,
            title: String(localized: String.LocalizationValue(titleKey)),
            tint: tint
        )
    }
}

/// How an inspection result or action column is rendered.
///
/// Traced from the legacy Cordova controllers, which choose the control per
/// form rather than per value: `Rundgang.controller.js` and
/// `WartungsPlan.controller.js` build a `sap.m.SegmentedButton` from
/// `T_PROPS[0]`, while `Aufzugskontrolle.controller.js`,
/// `MasterDataForm.controller.js` and `CreateNewForm.controller.js` switch on
/// `T_PROPS[i].DTYPE` and build a `sap.m.Select` for `DBOX` and a
/// `sap.m.CheckBox` for `CBOX`.
enum InspectionControlStyle: String, Equatable, Sendable {
    /// Side-by-side buttons. Legacy `sap.m.SegmentedButton`.
    case segmented
    /// Anchored code list. Legacy `sap.m.Select` with `showSecondaryValues`.
    case dropdown

    /// Style a form uses when it is not one of the known form codes.
    ///
    /// A two-value list is a yes/no decision and reads better as buttons; a
    /// longer list needs the anchored popover so the row stays inside the
    /// iPad landscape table width.
    static func resolved(optionCount: Int) -> Self {
        optionCount <= 2 ? .segmented : .dropdown
    }
}

/// Fixed column geometry for every inspection checklist in the app.
///
/// The legacy views declare the same `formPositionTable` column set for every
/// form code (`view/Rundgang.view.xml`, `view/Aufzugskontrolle.view.xml`,
/// `view/WartungsPlan.view.xml`, `view/MasterDataForm.view.xml`); only which
/// columns are present differs. Keeping the widths in one place is what stops
/// the tables drifting apart again.
/// The one column vocabulary every inspection checklist uses.
///
/// The legacy client labels the `formPositionTable` columns from a single set
/// of `tabelle.column.header.*` texts, whichever form is open, so the German
/// and English wording is identical across TFM1–TFM8.
enum InspectionFormColumn {
    static let number = "inspection.column.number"
    static let asset = "inspection.column.asset"
    static let result = "inspection.column.result"
    static let action = "inspection.column.action"
    static let material = "inspection.column.material"
    static let photo = "inspection.column.photo"
    static let comment = "inspection.column.comment"
    static let performedOn = "inspection.performedOn"
}

enum InspectionFormMetrics {
    static let numberColumn: CGFloat = 30
    static let statusColumn: CGFloat = 26
    /// The position number and its status marker read as one unit, so they sit
    /// closer together than the gap between two data columns.
    static let leadingColumnSpacing: CGFloat = 4
    static let itemColumnMinimum: CGFloat = 220
    static let resultColumn: CGFloat = 112
    static let actionColumn: CGFloat = 112
    static let materialColumn: CGFloat = 56
    static let photoColumn: CGFloat = 52
    /// Fits bold caption1 "Bemerkung" (69.2 pt), the widest of the narrow
    /// column labels in either language.
    static let commentColumn: CGFloat = 70
    static let rowSpacing: CGFloat = 12
    static let rowHorizontalPadding: CGFloat = 22
    static let rowMinimumHeight: CGFloat = 68
    static let cornerRadius: CGFloat = 18

    /// Width of the number/status pair including the gap between them, so the
    /// header row can reserve exactly what a row occupies.
    static var leadingColumnWidth: CGFloat {
        numberColumn + leadingColumnSpacing + statusColumn
    }

    /// Intrinsic width of a checklist with every column present. It is what
    /// the table reserves before allowing horizontal scrolling, so the column
    /// labels are never squeezed into wrapping.
    static func intrinsicWidth(for variant: InspectionFormVariant) -> CGFloat {
        var width = rowHorizontalPadding * 2
            + leadingColumnWidth
            + rowSpacing + itemColumnMinimum
            + rowSpacing + resultColumn
            + rowSpacing + photoColumn
            + rowSpacing + commentColumn
        if variant.hasActionColumn { width += rowSpacing + actionColumn }
        if variant.hasMaterialColumn { width += rowSpacing + materialColumn }
        return width
    }
}

/// Per-form configuration of the shared inspection checklist.
///
/// The variant decides which columns exist, how the result control is drawn,
/// and whether the form carries the header-level "Außer Betrieb" / "Demontiert"
/// status. It never decides what the values mean — those come from SAP
/// metadata and from `InspectionFormRules`.
struct InspectionFormVariant: Equatable, Sendable {
    let formCode: String
    let resultStyle: InspectionControlStyle
    let hasActionColumn: Bool
    let hasMaterialColumn: Bool
    /// The legacy `form.date` row of `TableFormHeader.fragment.xml`. It is
    /// visible for every form except TFM1, whose controller hides it.
    let showsPerformedOnDate: Bool
    /// Title of the header status checkbox, or `nil` when the form has none.
    let outOfServiceTitleKey: String?
    /// `true` for the forms whose legacy controller opens the comment popover
    /// as soon as a defect is picked and refuses to close without it.
    let requiresCommentForDefect: Bool

    var supportsOutOfService: Bool { outOfServiceTitleKey != nil }
    /// The form shows the toolbar band above its checklist.
    var hasTableToolbar: Bool { showsPerformedOnDate || supportsOutOfService }

    init(
        formCode: String,
        resultStyle: InspectionControlStyle,
        hasActionColumn: Bool = false,
        hasMaterialColumn: Bool = false,
        showsPerformedOnDate: Bool = true,
        outOfServiceTitleKey: String? = nil,
        requiresCommentForDefect: Bool = false
    ) {
        self.formCode = formCode
        self.resultStyle = resultStyle
        self.hasActionColumn = hasActionColumn
        self.hasMaterialColumn = hasMaterialColumn
        self.showsPerformedOnDate = showsPerformedOnDate
        self.outOfServiceTitleKey = outOfServiceTitleKey
        self.requiresCommentForDefect = requiresCommentForDefect
    }

    /// Returns the checklist configuration for an SAP form code (`STEUS` /
    /// `FORMNR`).
    ///
    /// The control style and the presence of the header status follow
    /// `BaseFormController.buildDefaultElements`, which hides the out-of-order
    /// box for `TFM1`, `TFM3`, `TFM8`, `TFM9` and `TFMQ`, and relabels it to
    /// `form.chkBox.demount` for `TFM5`. `hasMaterialColumn` is only the
    /// *possibility* of the column — the caller still has to confirm that SAP
    /// delivered a `T_PROPS` position 3 for at least one row.
    static func forFormCode(_ formCode: String, optionCount: Int? = nil) -> Self {
        switch formCode.uppercased() {
        case "TFM1":
            // WartungsPlan. Segmented yes/no, no action, no header status, and
            // a mandatory comment for every defect (`WartungsPlan` line 450).
            // It is also the one form that hides the execution date
            // (`tableOutofOrderFragment` → `false`).
            return Self(
                formCode: "TFM1",
                resultStyle: .segmented,
                showsPerformedOnDate: false,
                requiresCommentForDefect: true
            )
        case "TFM3":
            // Rundgang. Same control as TFM1; `Rundgang` line 621 applies the
            // same mandatory-comment rule to a defect.
            return Self(
                formCode: "TFM3",
                resultStyle: .segmented,
                requiresCommentForDefect: true
            )
        case "TFM2", "TFM6":
            // Aufzugskontrolle and Feststellanlage share one legacy controller.
            return Self(
                formCode: formCode.uppercased(),
                resultStyle: .dropdown,
                hasActionColumn: true,
                hasMaterialColumn: true,
                outOfServiceTitleKey: "inspection.outOfService"
            )
        case "TFM5":
            // Mobile ladder. The header status is "Demontiert", not
            // "Außer Betrieb" (`buildDefaultElements`, MobileLeiter branch).
            return Self(
                formCode: "TFM5",
                resultStyle: .dropdown,
                hasActionColumn: true,
                outOfServiceTitleKey: "inspection.outOfService.demounted"
            )
        case "TFM4":
            return Self(
                formCode: "TFM4",
                resultStyle: .dropdown,
                hasActionColumn: true,
                outOfServiceTitleKey: "inspection.outOfService"
            )
        case "TFM7":
            return Self(
                formCode: "TFM7",
                resultStyle: .dropdown,
                hasActionColumn: true,
                outOfServiceTitleKey: "inspection.outOfService"
            )
        case "TFM8":
            // Dachanlagen. Dropdown form, but `buildDefaultElements` returns
            // early for it, so it carries no header status.
            return Self(
                formCode: "TFM8",
                resultStyle: .dropdown,
                hasActionColumn: true
            )
        default:
            return Self(
                formCode: formCode.uppercased(),
                resultStyle: optionCount.map(InspectionControlStyle.resolved) ?? .dropdown
            )
        }
    }

    /// Drops the action or material column when SAP delivered no `T_PROPS`
    /// position for it, so an empty column never reserves table width.
    func adjusted(hasActionValues: Bool, hasMaterialValues: Bool) -> Self {
        Self(
            formCode: formCode,
            resultStyle: resultStyle,
            hasActionColumn: hasActionColumn && hasActionValues,
            hasMaterialColumn: hasMaterialColumn && hasMaterialValues,
            showsPerformedOnDate: showsPerformedOnDate,
            outOfServiceTitleKey: outOfServiceTitleKey,
            requiresCommentForDefect: requiresCommentForDefect
        )
    }
}
