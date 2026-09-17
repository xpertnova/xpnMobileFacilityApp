import SwiftUI

/// The SAP-derived, read-only description of one inspection position.
///
/// It is built from a `T_PLPOD` row and its `T_PROPS` properties, so the same
/// value carries a TFM3 yes/no decision and a TFM2 five-code result — the
/// difference is only how many options arrived.
struct InspectionFormItem: Identifiable, Equatable, Sendable {
    let id: String
    let number: Int
    let title: String
    let information: String
    /// Title of the `T_PLPOD` group this position belongs to, or empty when
    /// SAP delivered no `HEADER` / `U1` row before it. Consecutive positions
    /// that share a title are rendered under one band.
    let groupTitle: String
    let resultOptions: [InspectionFormOption]
    let actionOptions: [InspectionFormOption]
    /// `T_PROPS` position 3 exists for this row.
    let supportsMaterial: Bool
    /// `false` for the legacy photo-only and header rows, which carry no
    /// result control and must not be reported as unanswered.
    let requiresResult: Bool
    /// `true` for legacy `USR00 == "FOTO"` rows. The shared row preserves its
    /// photo and comment actions while its result/action cells stay empty.
    let requiresPhoto: Bool
    /// TFM7 photo documentation is complete only when the linked comment is
    /// saved as well as a JPEG.
    let requiresPhotoAndComment: Bool

    init(
        id: String,
        number: Int,
        title: String,
        information: String = "",
        groupTitle: String = "",
        resultOptions: [InspectionFormOption] = [],
        actionOptions: [InspectionFormOption] = [],
        supportsMaterial: Bool = false,
        requiresResult: Bool = true,
        requiresPhoto: Bool = false,
        requiresPhotoAndComment: Bool = false
    ) {
        self.id = id
        self.number = number
        self.title = title
        self.information = information
        self.groupTitle = groupTitle
        self.resultOptions = resultOptions
        self.actionOptions = actionOptions
        self.supportsMaterial = supportsMaterial
        self.requiresResult = requiresResult
        self.requiresPhoto = requiresPhoto
        self.requiresPhotoAndComment = requiresPhotoAndComment
    }
}

/// The technician-entered state of one inspection position.
///
/// The checklist deliberately does not own this. Every form persists its
/// answers in its own offline payload shape, and a shared component that tried
/// to own the state would have to know about all of them.
struct InspectionFormItemState: Equatable, Sendable {
    /// The selected result option's `id`.
    var resultID: String?
    /// The selected action option's `id`.
    var actionID: String?
    var isMaterialSelected: Bool
    var comment: String
    var photoCount: Int
    /// Set by the caller after a failed close attempt so the row shows the
    /// legacy red exception marker.
    var isFlagged: Bool

    init(
        resultID: String? = nil,
        actionID: String? = nil,
        isMaterialSelected: Bool = false,
        comment: String = "",
        photoCount: Int = 0,
        isFlagged: Bool = false
    ) {
        self.resultID = resultID
        self.actionID = actionID
        self.isMaterialSelected = isMaterialSelected
        self.comment = comment
        self.photoCount = photoCount
        self.isFlagged = isFlagged
    }
}

/// Callbacks a checklist row needs. Grouped so adding one does not change the
/// signature at all five call sites.
struct InspectionFormActions {
    var selectResult: (InspectionFormItem, InspectionFormOption) -> Void
    var selectAction: (InspectionFormItem, InspectionFormOption) -> Void
    var toggleMaterial: (InspectionFormItem) -> Void
    var openPhotos: (InspectionFormItem) -> Void
    var editComment: (InspectionFormItem) -> Void

    init(
        selectResult: @escaping (InspectionFormItem, InspectionFormOption) -> Void,
        selectAction: @escaping (InspectionFormItem, InspectionFormOption) -> Void = { _, _ in },
        toggleMaterial: @escaping (InspectionFormItem) -> Void = { _ in },
        openPhotos: @escaping (InspectionFormItem) -> Void,
        editComment: @escaping (InspectionFormItem) -> Void
    ) {
        self.selectResult = selectResult
        self.selectAction = selectAction
        self.toggleMaterial = toggleMaterial
        self.openPhotos = openPhotos
        self.editComment = editComment
    }
}

/// What the checklist shows instead of rows when a form has no positions yet.
struct InspectionFormEmptyState {
    let titleKey: String
    let messageKey: String
    var systemImage: String = "list.bullet.clipboard"
    var retry: (() -> Void)?
    var retryTitleKey: String = "elevator.unavailable.retry"
}

/// The shared inspection checklist.
///
/// Every MTFM form — Rundgang, Wartungsplan, Aufzugskontrolle, mobile ladder,
/// subdistribution — renders its inspection points through this one table. The
/// legacy views already declared an identical `formPositionTable` for all of
/// them and differed only in which columns were present, which is what
/// `InspectionFormVariant` now expresses.
struct InspectionFormTable: View {
    let variant: InspectionFormVariant
    let items: [InspectionFormItem]
    let state: (InspectionFormItem) -> InspectionFormItemState
    let isEditable: Bool
    var emptyState: InspectionFormEmptyState?
    /// Execution date shown in the toolbar band, for the forms whose variant
    /// asks for it.
    var performedOn: Binding<Date>?
    var isPerformedOnDisabled: Bool = false
    /// Header status shown on the right of the toolbar band.
    var outOfService: InspectionOutOfServiceControls?
    /// I2 notifications SAP already holds for the inspected object. Each row
    /// shows the ones that belong to its position.
    var existingI2Notifications: [SAPI2NotificationSummary] = []
    let actions: InspectionFormActions

    /// A checklist with the action and material columns is wide enough that it
    /// may not fit a narrow window. Reserving its intrinsic width and allowing
    /// horizontal scrolling keeps the column labels on one line instead of
    /// letting SwiftUI compress them until they wrap.
    private var minimumTableWidth: CGFloat? {
        guard variant.hasActionColumn else { return nil }
        return InspectionFormMetrics.intrinsicWidth(for: variant)
    }

    var body: some View {
        VStack(spacing: 0) {
            toolbar

            if items.isEmpty {
                headerRow
                Divider()
                emptyContent
            } else if let minimumTableWidth {
                ScrollView(.horizontal, showsIndicators: true) {
                    VStack(alignment: .leading, spacing: 0) {
                        headerRow
                        Divider()
                        rows
                    }
                    // A horizontal scroll view proposes no width, so the rows
                    // would keep their ideal width and leave an empty strip on
                    // a wide window. Fill the visible width, and scroll only
                    // below the intrinsic width.
                    .containerRelativeFrame(.horizontal, alignment: .leading) { length, _ in
                        max(length, minimumTableWidth)
                    }
                }
                .scrollBounceBehavior(.basedOnSize, axes: .horizontal)
            } else {
                headerRow
                Divider()
                rows
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(FacilityTheme.surface)
        // The toolbar band and the group bands paint to the card edge, so the
        // card has to clip them rather than only round its own background.
        .clipShape(
            RoundedRectangle(cornerRadius: InspectionFormMetrics.cornerRadius, style: .continuous)
        )
        // A shadow around one long scrolling surface forces expensive
        // off-screen compositing. A subtle border keeps the same card edge
        // without making scroll performance depend on checklist height.
        .overlay {
            RoundedRectangle(cornerRadius: InspectionFormMetrics.cornerRadius, style: .continuous)
                .stroke(Color.black.opacity(0.06))
        }
    }

    private var rows: some View {
        ForEach(Array(items.enumerated()), id: \.element.id) { index, item in
            // A band opens whenever the group changes, matching the
            // `GroupHeaderListItem` rows the legacy table factory returns for
            // `USR00 == "HEADER"` / `"U1"`.
            if !item.groupTitle.isEmpty, item.groupTitle != items[safe: index - 1]?.groupTitle {
                InspectionFormGroupBand(title: item.groupTitle)
            }

            InspectionFormRow(
                item: item,
                state: state(item),
                variant: variant,
                isEditable: isEditable,
                existingI2Notifications: existingI2Notifications(for: item),
                actions: actions
            )
            if index < items.count - 1 {
                Divider().padding(.leading, InspectionFormMetrics.rowHorizontalPadding)
            }
        }
    }

    /// `_hasI2Meldung4Position`: TFM1 and TFM3 also compare the group header,
    /// which are exactly the segmented forms.
    private func existingI2Notifications(for item: InspectionFormItem) -> [SAPI2NotificationSummary] {
        guard !existingI2Notifications.isEmpty else { return [] }
        return I2NotificationRules.notifications(
            existingI2Notifications,
            forPositionTitle: item.title,
            groupTitle: item.groupTitle,
            matchesGroupHeader: variant.resultStyle == .segmented
        )
    }

    /// The legacy `TableFormHeader` toolbar: execution date on the left,
    /// "Außer Betrieb" / "Demontiert" and its photo and note on the right, on
    /// one band directly above the checklist.
    @ViewBuilder
    private var toolbar: some View {
        if performedOn != nil || outOfService != nil {
            // The status group moves under the date on a narrow window
            // instead of being clipped at the card edge; the table below
            // scrolls sideways, but this band does not.
            FacilitySideColumnLayout(sideWidth: nil, minimumMainWidth: 280, spacing: 12, alignment: .center) {
                HStack(spacing: 12) {
                    if let performedOn {
                        Text(LocalizedStringKey(InspectionFormColumn.performedOn))
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(FacilityTheme.ink)

                        DatePicker(
                            LocalizedStringKey(InspectionFormColumn.performedOn),
                            selection: performedOn,
                            displayedComponents: .date
                        )
                        .labelsHidden()
                        .datePickerStyle(.compact)
                        .disabled(isPerformedOnDisabled)
                        .padding(.horizontal, 8)
                        .frame(minHeight: 44)
                        .background(.white, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                        .overlay {
                            RoundedRectangle(cornerRadius: 10, style: .continuous)
                                .stroke(.gray.opacity(0.22))
                        }
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)

                outOfService
            }
            .padding(.horizontal, InspectionFormMetrics.rowHorizontalPadding)
            .padding(.vertical, 10)
            .frame(maxWidth: .infinity, alignment: .leading)
            // Neutral chrome, like the legacy `nBpmTranslucentDate` band. It
            // is a shade lighter than a group band so the two bands stay
            // distinguishable.
            .background(Color(white: 0.97))

            Divider()
        }
    }

    @ViewBuilder
    private var emptyContent: some View {
        if let emptyState {
            VStack(spacing: 16) {
                ContentUnavailableView(
                    LocalizedStringKey(emptyState.titleKey),
                    systemImage: emptyState.systemImage,
                    description: Text(LocalizedStringKey(emptyState.messageKey))
                )
                if let retry = emptyState.retry {
                    Button(action: retry) {
                        Label(LocalizedStringKey(emptyState.retryTitleKey), systemImage: "arrow.clockwise")
                    }
                    .buttonStyle(.bordered)
                    .tint(FacilityTheme.blue)
                    .frame(minHeight: 44)
                }
            }
            .frame(maxWidth: .infinity, minHeight: 180)
            .padding(24)
        }
    }

    private var headerRow: some View {
        HStack(spacing: InspectionFormMetrics.rowSpacing) {
            HStack(spacing: InspectionFormMetrics.leadingColumnSpacing) {
                Text(LocalizedStringKey(InspectionFormColumn.number))
                    .frame(width: InspectionFormMetrics.numberColumn, alignment: .leading)

                Color.clear
                    .frame(width: InspectionFormMetrics.statusColumn, height: 1)
            }

            Text(LocalizedStringKey(InspectionFormColumn.asset))
                .frame(
                    minWidth: InspectionFormMetrics.itemColumnMinimum,
                    maxWidth: .infinity,
                    alignment: .leading
                )

            Text(LocalizedStringKey(InspectionFormColumn.result))
                .frame(width: InspectionFormMetrics.resultColumn, alignment: .center)

            if variant.hasActionColumn {
                Text(LocalizedStringKey(InspectionFormColumn.action))
                    .frame(width: InspectionFormMetrics.actionColumn, alignment: .center)
            }

            if variant.hasMaterialColumn {
                Text(LocalizedStringKey(InspectionFormColumn.material))
                    .frame(width: InspectionFormMetrics.materialColumn, alignment: .center)
            }

            Text(LocalizedStringKey(InspectionFormColumn.photo))
                .frame(width: InspectionFormMetrics.photoColumn, alignment: .center)

            Text(LocalizedStringKey(InspectionFormColumn.comment))
                .frame(width: InspectionFormMetrics.commentColumn, alignment: .center)
        }
        // The narrow columns carry words like "Bemerkung" and "Material".
        // A smaller label with a hard one-line limit keeps them readable
        // instead of wrapping them onto a second line.
        .font(.caption.weight(.bold))
        .foregroundStyle(.secondary)
        .lineLimit(1)
        .minimumScaleFactor(0.85)
        .padding(.horizontal, InspectionFormMetrics.rowHorizontalPadding)
        .padding(.vertical, 12)
    }
}

/// One inspection position. Identical for every form code; only the controls
/// the variant asks for are rendered.
struct InspectionFormRow: View {
    let item: InspectionFormItem
    let state: InspectionFormItemState
    let variant: InspectionFormVariant
    let isEditable: Bool
    var existingI2Notifications: [SAPI2NotificationSummary] = []
    let actions: InspectionFormActions

    @State private var expandedField: InspectionResultControl.Field?

    private var selectedResult: InspectionFormOption? {
        item.resultOptions.first { $0.id == state.resultID }
    }

    private var selectedAction: InspectionFormOption? {
        item.actionOptions.first { $0.id == state.actionID }
    }

    private var isDefective: Bool {
        InspectionFormRules.isDefective(
            resultCode: selectedResult?.code,
            actionCode: selectedAction?.code,
            style: variant.resultStyle
        )
    }

    private var issues: [InspectionFormRules.Issue] {
        InspectionFormRules.issues(
            resultCode: selectedResult?.code,
            actionCode: selectedAction?.code,
            isMaterialSelected: state.isMaterialSelected,
            comment: state.comment,
            requiresResult: item.requiresResult,
            requiresPhoto: item.requiresPhoto,
            requiresPhotoAndComment: item.requiresPhotoAndComment,
            photoCount: state.photoCount,
            variant: variant
        )
    }

    var body: some View {
        HStack(spacing: InspectionFormMetrics.rowSpacing) {
            HStack(spacing: InspectionFormMetrics.leadingColumnSpacing) {
                Text(item.number, format: .number)
                    .font(.body.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .frame(width: InspectionFormMetrics.numberColumn, alignment: .leading)

                statusIcon
                    .frame(width: InspectionFormMetrics.statusColumn, height: 44)
            }

            HStack(spacing: 10) {
                NotificationInfoButton(information: item.information)

                Text(item.title)
                    .font(.body)
                    .foregroundStyle(FacilityTheme.ink)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity, alignment: .leading)

                // The legacy wrench cell, kept inside the position column so
                // the shared column geometry does not change.
                if !existingI2Notifications.isEmpty {
                    I2NotificationButton(
                        notifications: existingI2Notifications,
                        positionTitle: item.title,
                        groupTitle: item.groupTitle
                    )
                }
            }
            .frame(
                minWidth: InspectionFormMetrics.itemColumnMinimum,
                maxWidth: .infinity,
                alignment: .leading
            )

            if item.requiresResult {
                resultControl
                    .frame(width: InspectionFormMetrics.resultColumn)
            } else {
                // `USR00 == "FOTO"` has no Befund element. Keep the shared
                // table's columns aligned, but do not render the em-dash
                // placeholder as a result field.
                Color.clear
                    .frame(width: InspectionFormMetrics.resultColumn, height: 44)
            }

            if variant.hasActionColumn {
                if item.requiresResult {
                    actionControl
                        .frame(width: InspectionFormMetrics.actionColumn)
                } else {
                    // Photo-only rows also have no Maßnahme element.
                    Color.clear
                        .frame(width: InspectionFormMetrics.actionColumn, height: 44)
                }
            }

            if variant.hasMaterialColumn {
                materialControl
                    .frame(width: InspectionFormMetrics.materialColumn, alignment: .center)
            }

            NotificationPhotoButton(count: state.photoCount) {
                actions.openPhotos(item)
            }
            .frame(width: InspectionFormMetrics.photoColumn)

            NotificationCommentButton(
                hasComment: !state.comment.isEmpty,
                isMissing: isCommentFlagged,
                isReadOnly: !isEditable,
                action: { actions.editComment(item) }
            )
            .frame(width: InspectionFormMetrics.commentColumn)
        }
        .padding(.horizontal, InspectionFormMetrics.rowHorizontalPadding)
        .padding(.vertical, 10)
        .frame(minHeight: InspectionFormMetrics.rowMinimumHeight)
        // Keep the active row above its neighbours while its anchored popover
        // is visible.
        .zIndex(expandedField == nil ? 0 : 1)
    }

    /// The legacy exception marker. It is red while the position fails a
    /// constraint or records a defect, and shows the in-order check once the
    /// position is answered cleanly.
    @ViewBuilder
    private var statusIcon: some View {
        if state.isFlagged || !issues.isEmpty {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.body.weight(.semibold))
                .foregroundStyle(FacilityTheme.red)
                .accessibilityLabel(Text("notifications.detail.validation.incompleteItem"))
        } else if isDefective {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.body.weight(.semibold))
                .foregroundStyle(FacilityTheme.red)
                .accessibilityLabel(Text("elevator.status.defect"))
        } else if state.resultID != nil {
            Image(systemName: "checkmark.circle.fill")
                .font(.body.weight(.semibold))
                .foregroundStyle(FacilityTheme.accent)
                .accessibilityLabel(Text("elevator.status.inOrder"))
        } else {
            Color.clear
        }
    }

    private var isCommentFlagged: Bool {
        issues.contains(.commentRequired)
            || issues.contains(.actionAndCommentRequired)
            || issues.contains(.photoAndCommentRequired)
    }

    @ViewBuilder
    private var resultControl: some View {
        if item.resultOptions.isEmpty {
            InspectionControlPlaceholder()
        } else {
            InspectionResultControl(
                field: .result,
                style: variant.resultStyle,
                options: item.resultOptions,
                selectionID: state.resultID,
                isEnabled: isEditable,
                accessibilityLabelKey: InspectionFormColumn.result,
                expandedField: $expandedField,
                select: { actions.selectResult(item, $0) }
            )
        }
    }

    @ViewBuilder
    private var actionControl: some View {
        if item.actionOptions.isEmpty {
            InspectionControlPlaceholder()
        } else {
            InspectionResultControl(
                field: .action,
                style: variant.resultStyle,
                options: item.actionOptions,
                selectionID: state.actionID,
                isEnabled: isEditable,
                accessibilityLabelKey: InspectionFormColumn.action,
                expandedField: $expandedField,
                select: { actions.selectAction(item, $0) }
            )
        }
    }

    @ViewBuilder
    private var materialControl: some View {
        if item.supportsMaterial {
            InspectionMaterialCheckbox(
                isSelected: state.isMaterialSelected,
                isEnabled: isEditable,
                toggle: { actions.toggleMaterial(item) }
            )
        } else {
            InspectionControlPlaceholder()
        }
    }
}

/// A `T_PLPOD` group header, rendered as the grey band the legacy
/// `GroupHeaderListItem` produces between the positions it introduces.
struct InspectionFormGroupBand: View {
    let title: String

    var body: some View {
        Text(title)
            .font(.subheadline.weight(.bold))
            .foregroundStyle(FacilityTheme.ink)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, InspectionFormMetrics.rowHorizontalPadding)
            .padding(.vertical, 9)
            .background(Color(white: 0.94))
            .overlay(alignment: .top) { Divider() }
            .overlay(alignment: .bottom) { Divider() }
            .accessibilityAddTraits(.isHeader)
    }
}

private extension Array {
    subscript(safe index: Int) -> Element? {
        indices.contains(index) ? self[index] : nil
    }
}
