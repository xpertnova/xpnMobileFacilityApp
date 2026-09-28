import SwiftUI

// MARK: - Defect selection after closing

/// Column geometry of the defect selection table.
///
/// On a compact window the dialog sits beside the sidebar in roughly 750 pt,
/// so the wide columns and the list height give way there instead of
/// overflowing the frame.
private struct I2DefectSelectionMetrics {
    static let dialogWidth: CGFloat = 980
    static let numberColumn: CGFloat = 40
    static let columnSpacing: CGFloat = 12
    static let horizontalPadding: CGFloat = 16

    let flexibleColumnMinimum: CGFloat
    let resultColumn: CGFloat
    let categoryColumn: CGFloat
    let maximumListHeight: CGFloat

    init(layout: FacilityLayoutMetrics) {
        flexibleColumnMinimum = layout.isCompact ? 100 : 160
        resultColumn = layout.isCompact ? 140 : 170
        categoryColumn = layout.isCompact ? 210 : 250
        maximumListHeight = layout.isCompact ? 240 : 380
    }
}

private struct I2DefectSelectionDialogModifier: ViewModifier {
    let selection: I2DefectSelection
    let accept: () -> Void
    let cancel: () -> Void

    @Environment(\.accessibilityReduceMotion) private var accessibilityReduceMotion

    func body(content: Content) -> some View {
        content.overlay {
            if selection.isPresented {
                ZStack {
                    // The I1 is already closed, so the only ways out are the
                    // two buttons — the legacy dialog has no backdrop dismiss.
                    Color.black.opacity(0.32)
                        .ignoresSafeArea()

                    FacilityConfirmationDialog(
                        titleKey: "i2.selection.title",
                        messageKey: "i2.selection.message",
                        tint: FacilityTheme.red,
                        width: I2DefectSelectionMetrics.dialogWidth,
                        actions: [
                            FacilityDialogAction(titleKey: "i2.selection.accept", emphasis: .primary, perform: accept)
                        ],
                        cancel: cancel
                    ) {
                        I2DefectSelectionTable(selection: selection)
                    }
                }
                .transition(.opacity)
            }
        }
        .animation(
            accessibilityReduceMotion ? nil : .easeOut(duration: 0.18),
            value: selection.isPresented
        )
    }
}

extension View {
    /// Presents the "Mangelbehaftete Positionen" dialog of the legacy
    /// `DefectPosItem` fragment while `selection` is presented.
    func i2DefectSelectionDialog(
        _ selection: I2DefectSelection,
        accept: @escaping () -> Void,
        cancel: @escaping () -> Void
    ) -> some View {
        modifier(I2DefectSelectionDialogModifier(selection: selection, accept: accept, cancel: cancel))
    }
}

/// The deficient positions with a category picker per row.
private struct I2DefectSelectionTable: View {
    let selection: I2DefectSelection

    @State private var expandedCandidateID: String?
    @Environment(\.facilityLayout) private var layout

    private var metrics: I2DefectSelectionMetrics { I2DefectSelectionMetrics(layout: layout) }

    var body: some View {
        VStack(spacing: 0) {
            headerRow
            Divider()
            ScrollView {
                LazyVStack(spacing: 0) {
                    ForEach(Array(selection.candidates.enumerated()), id: \.element.id) { index, candidate in
                        row(for: candidate)
                        if index < selection.candidates.count - 1 {
                            Divider().padding(.leading, I2DefectSelectionMetrics.horizontalPadding)
                        }
                    }
                }
            }
            .frame(maxHeight: metrics.maximumListHeight)
            .fixedSize(horizontal: false, vertical: true)
        }
        .background(FacilityTheme.surface, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .stroke(.gray.opacity(0.22))
        }
    }

    private var headerRow: some View {
        HStack(spacing: I2DefectSelectionMetrics.columnSpacing) {
            Text(LocalizedStringKey(InspectionFormColumn.number))
                .frame(width: I2DefectSelectionMetrics.numberColumn, alignment: .leading)
            Text(LocalizedStringKey(InspectionFormColumn.asset))
                .frame(minWidth: metrics.flexibleColumnMinimum, maxWidth: .infinity, alignment: .leading)
            Text(LocalizedStringKey(InspectionFormColumn.result))
                .frame(width: metrics.resultColumn, alignment: .leading)
            Text(LocalizedStringKey(InspectionFormColumn.comment))
                .frame(minWidth: metrics.flexibleColumnMinimum, maxWidth: .infinity, alignment: .leading)
            Text("i2.selection.column.category")
                .frame(width: metrics.categoryColumn, alignment: .leading)
        }
        .font(.caption.weight(.bold))
        .foregroundStyle(.secondary)
        .lineLimit(1)
        .minimumScaleFactor(0.85)
        .padding(.horizontal, I2DefectSelectionMetrics.horizontalPadding)
        .padding(.vertical, 12)
        .background(Color(white: 0.97))
    }

    private func row(for candidate: I2DefectCandidate) -> some View {
        let category = selection.category(for: candidate.id)
        return HStack(alignment: .firstTextBaseline, spacing: I2DefectSelectionMetrics.columnSpacing) {
            Text(candidate.number, format: .number)
                .font(.body.weight(.semibold))
                .foregroundStyle(.secondary)
                .frame(width: I2DefectSelectionMetrics.numberColumn, alignment: .leading)

            Text(candidate.title)
                .font(.body)
                .foregroundStyle(FacilityTheme.ink)
                .fixedSize(horizontal: false, vertical: true)
                .frame(minWidth: metrics.flexibleColumnMinimum, maxWidth: .infinity, alignment: .leading)

            resultText(for: candidate)
                .frame(width: metrics.resultColumn, alignment: .leading)

            Text(candidate.note.isEmpty ? "—" : candidate.note)
                .font(.subheadline)
                .foregroundStyle(candidate.note.isEmpty ? .secondary : FacilityTheme.ink)
                .fixedSize(horizontal: false, vertical: true)
                .frame(minWidth: metrics.flexibleColumnMinimum, maxWidth: .infinity, alignment: .leading)

            InspectionCodePicker(
                picker: candidate.id,
                expandedPicker: $expandedCandidateID,
                selection: "\(category.code) · \(String(localized: String.LocalizationValue(category.titleKey), bundle: .appLanguage))",
                options: I2NotificationCategory.allCases.map {
                    InspectionCodeOption(code: $0.code, titleKey: $0.titleKey)
                },
                accessibilityLabel: Text("i2.selection.column.category"),
                onSelect: { code in
                    guard let category = I2NotificationCategory(rawValue: code) else { return }
                    selection.setCategory(category, for: candidate.id)
                }
            )
            .frame(width: metrics.categoryColumn)
        }
        .padding(.horizontal, I2DefectSelectionMetrics.horizontalPadding)
        .padding(.vertical, 12)
        .background(category.createsNotification ? FacilityTheme.accentSoft.opacity(0.6) : .clear)
    }

    /// `assistmethods.getFormatBefund`: the result, and the action below it
    /// when the form has one.
    private func resultText(for candidate: I2DefectCandidate) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(verbatim: "\(String(localized: "inspection.column.result", bundle: .appLanguage)): \(codeAndText(candidate.resultCode, candidate.resultText))")
            if !candidate.actionCode.isEmpty {
                Text(verbatim: "\(String(localized: "inspection.column.action", bundle: .appLanguage)): \(codeAndText(candidate.actionCode, candidate.actionText))")
            }
        }
        .font(.subheadline)
        .foregroundStyle(FacilityTheme.ink)
        .fixedSize(horizontal: false, vertical: true)
    }

    private func codeAndText(_ code: String, _ text: String) -> String {
        text.isEmpty ? code : "\(code) – \(text)"
    }
}

// MARK: - Existing notifications of a position

/// The wrench next to a checklist position that already has I2 notifications
/// in SAP. It opens the read-only list of the legacy `I2MeldungList` popover.
struct I2NotificationButton: View {
    let notifications: [SAPI2NotificationSummary]
    let positionTitle: String
    let groupTitle: String

    @State private var isPresented = false

    var body: some View {
        Button {
            isPresented = true
        } label: {
            Image(systemName: "wrench.adjustable.fill")
                .font(.title3.weight(.semibold))
                .foregroundStyle(FacilityTheme.orange)
                .frame(width: 44, height: 44)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(Text("i2.existing.show"))
        .accessibilityValue(Text(verbatim: "\(notifications.count)"))
        .popover(isPresented: $isPresented) {
            I2NotificationListPopoverContent(
                notifications: notifications,
                positionTitle: positionTitle,
                groupTitle: groupTitle,
                close: { isPresented = false }
            )
            .presentationCompactAdaptation(.popover)
        }
    }
}

private enum I2NotificationListMetrics {
    static let width: CGFloat = 820
    static let numberColumn: CGFloat = 130
    static let reporterColumn: CGFloat = 96
    static let dateColumn: CGFloat = 150
    static let referenceColumn: CGFloat = 130
    static let statusColumn: CGFloat = 72
    static let detailColumn: CGFloat = 32
    static let columnSpacing: CGFloat = 10
    /// Gap kept between the popover and the window's side edges.
    static let windowMargin: CGFloat = 40

    /// A popover cannot scroll as a whole, so on a short window the list and
    /// the long text give up height to keep the popover on screen.
    static func maximumListHeight(_ layout: FacilityLayoutMetrics) -> CGFloat {
        layout.isCompact ? 180 : 260
    }

    static func longTextHeight(_ layout: FacilityLayoutMetrics) -> CGFloat {
        layout.isCompact ? 100 : 130
    }

    static func width(_ layout: FacilityLayoutMetrics) -> CGFloat {
        guard layout.windowSize.width > 0 else { return width }
        return max(0, min(width, layout.windowSize.width - windowMargin * 2))
    }
}

/// Read-only list of the I2 notifications of one position, with the long text
/// of the selected one below it.
struct I2NotificationListPopoverContent: View {
    let notifications: [SAPI2NotificationSummary]
    let positionTitle: String
    let groupTitle: String
    let close: () -> Void

    @State private var selectedID: SAPI2NotificationSummary.ID?
    @Environment(\.facilityLayout) private var layout

    /// The legacy title is `<group> - <position>` and prints `undefined` for
    /// a position without a group; the group is simply left out here.
    private var title: String {
        groupTitle.isEmpty ? positionTitle : "\(groupTitle) – \(positionTitle)"
    }

    private var selectedNotification: SAPI2NotificationSummary? {
        notifications.first { $0.id == selectedID }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            header
            table
            longText
        }
        .padding(22)
        .frame(width: I2NotificationListMetrics.width(layout), alignment: .leading)
        .background(FacilityTheme.surface)
    }

    private var header: some View {
        HStack(alignment: .top, spacing: 14) {
            ZStack {
                Circle()
                    .fill(FacilityTheme.orange.opacity(0.12))
                    .frame(width: 44, height: 44)
                Image(systemName: "wrench.adjustable.fill")
                    .font(.title3.weight(.bold))
                    .foregroundStyle(FacilityTheme.orange)
            }
            .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 3) {
                Text("i2.existing.title")
                    .font(.system(size: 21, weight: .bold, design: .rounded))
                    .foregroundStyle(FacilityTheme.ink)
                Text(title)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            Button("app.button.close", action: close)
                .buttonStyle(.bordered)
                .tint(FacilityTheme.ink)
        }
    }

    private var table: some View {
        VStack(spacing: 0) {
            HStack(spacing: I2NotificationListMetrics.columnSpacing) {
                Text("i2.existing.column.number")
                    .frame(width: I2NotificationListMetrics.numberColumn, alignment: .leading)
                Text("i2.existing.column.description")
                    .frame(maxWidth: .infinity, alignment: .leading)
                Text("i2.existing.column.reporter")
                    .frame(width: I2NotificationListMetrics.reporterColumn, alignment: .leading)
                Text("i2.existing.column.date")
                    .frame(width: I2NotificationListMetrics.dateColumn, alignment: .leading)
                Text("i2.existing.column.reference")
                    .frame(width: I2NotificationListMetrics.referenceColumn, alignment: .leading)
                Text("i2.existing.column.status")
                    .frame(width: I2NotificationListMetrics.statusColumn, alignment: .leading)
                Color.clear
                    .frame(width: I2NotificationListMetrics.detailColumn, height: 1)
            }
            .font(.caption.weight(.bold))
            .foregroundStyle(.secondary)
            .lineLimit(1)
            .minimumScaleFactor(0.85)
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
            .background(Color(white: 0.97))

            Divider()

            ScrollView {
                LazyVStack(spacing: 0) {
                    ForEach(Array(notifications.enumerated()), id: \.element.id) { index, notification in
                        row(for: notification)
                        if index < notifications.count - 1 {
                            Divider().padding(.leading, 14)
                        }
                    }
                }
            }
            .frame(maxHeight: I2NotificationListMetrics.maximumListHeight(layout))
            .fixedSize(horizontal: false, vertical: true)
        }
        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .stroke(.gray.opacity(0.22))
        }
    }

    private func row(for notification: SAPI2NotificationSummary) -> some View {
        let isSelected = notification.id == selectedID
        return Button {
            selectedID = notification.id
        } label: {
            HStack(spacing: I2NotificationListMetrics.columnSpacing) {
                Text(notification.id)
                    .font(.subheadline.monospacedDigit())
                    .frame(width: I2NotificationListMetrics.numberColumn, alignment: .leading)
                Text(notification.shortText)
                    .font(.subheadline)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity, alignment: .leading)
                Text(notification.reporter)
                    .font(.subheadline)
                    .frame(width: I2NotificationListMetrics.reporterColumn, alignment: .leading)
                Text(dateText(for: notification))
                    .font(.subheadline.monospacedDigit())
                    .frame(width: I2NotificationListMetrics.dateColumn, alignment: .leading)
                Text(notification.referenceID)
                    .font(.subheadline.monospacedDigit())
                    .frame(width: I2NotificationListMetrics.referenceColumn, alignment: .leading)
                statusText(notification.systemStatus)
                    .frame(width: I2NotificationListMetrics.statusColumn, alignment: .leading)
                Image(systemName: "text.alignleft")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(FacilityTheme.blue)
                    .frame(width: I2NotificationListMetrics.detailColumn)
                    .accessibilityHidden(true)
            }
            .foregroundStyle(FacilityTheme.ink)
            .lineLimit(2)
            .padding(.horizontal, 14)
            .frame(minHeight: 52)
            .background(isSelected ? FacilityTheme.blue.opacity(0.08) : .clear)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
        .accessibilityHint(Text("i2.existing.showLongText"))
    }

    @ViewBuilder
    private func statusText(_ status: String) -> some View {
        if status.isEmpty {
            Text(verbatim: "—")
                .font(.subheadline)
                .foregroundStyle(.secondary)
        } else {
            Text(status)
                .font(.caption.weight(.bold).monospaced())
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(Color.black.opacity(0.06), in: Capsule())
        }
    }

    private func dateText(for notification: SAPI2NotificationSummary) -> String {
        [notification.startDate, notification.startTime]
            .filter { !$0.isEmpty }
            .joined(separator: " – ")
    }

    private var longText: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("i2.existing.longText")
                .font(.caption.weight(.bold))
                .foregroundStyle(.secondary)

            ScrollView {
                Group {
                    if let selectedNotification {
                        let text = I2NotificationRules.displayLongText(selectedNotification.longText)
                        Text(text.isEmpty ? String(localized: "i2.existing.longText.empty", bundle: .appLanguage) : text)
                            .foregroundStyle(text.isEmpty ? .secondary : FacilityTheme.ink)
                            .textSelection(.enabled)
                    } else {
                        Text("i2.existing.longText.placeholder")
                            .foregroundStyle(.secondary)
                    }
                }
                .font(.body)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(14)
            }
            .frame(height: I2NotificationListMetrics.longTextHeight(layout))
            .background(FacilityTheme.canvas, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .stroke(.gray.opacity(0.22))
            }
        }
    }
}
