import SwiftUI

/// One action of a `FacilityConfirmationDialog`.
struct FacilityDialogAction: Identifiable {
    /// How prominently the action is drawn. There is at most one `primary` or
    /// `destructive` action in a dialog; the rest are `secondary`.
    enum Emphasis: Equatable {
        case primary
        case destructive
        case secondary
    }

    let id: String
    let titleKey: String
    let emphasis: Emphasis
    let perform: () -> Void

    init(
        titleKey: String,
        emphasis: Emphasis = .secondary,
        perform: @escaping () -> Void
    ) {
        self.id = titleKey
        self.titleKey = titleKey
        self.emphasis = emphasis
        self.perform = perform
    }
}

/// A centered, framed confirmation dialog.
///
/// The inspection forms, the synchronization and the log out use this in
/// place of a system alert so a warning like "Meldung abschließen?" looks the
/// same everywhere and matches the app's own chrome rather than the OS.
///
/// A dialog that needs more than a message, such as the I2 defect selection,
/// passes its own content and a wider frame; it keeps the same header,
/// buttons and chrome.
struct FacilityConfirmationDialog<Content: View>: View {
    static var standardWidth: CGFloat { 460 }

    let titleKey: String
    let messageKey: String
    var symbol: String
    var tint: Color
    /// `nil` makes this an acknowledgement frame: the sole supplied action is
    /// the only way out, matching a blocking legacy validation error.
    var cancelTitleKey: String?
    var width: CGFloat
    let actions: [FacilityDialogAction]
    let cancel: () -> Void
    let content: Content

    init(
        titleKey: String,
        messageKey: String,
        symbol: String = "exclamationmark.triangle.fill",
        tint: Color = FacilityTheme.orange,
        cancelTitleKey: String? = "common.cancel",
        width: CGFloat = 460,
        actions: [FacilityDialogAction],
        cancel: @escaping () -> Void,
        @ViewBuilder content: () -> Content
    ) {
        self.titleKey = titleKey
        self.messageKey = messageKey
        self.symbol = symbol
        self.tint = tint
        self.cancelTitleKey = cancelTitleKey
        self.width = width
        self.actions = actions
        self.cancel = cancel
        self.content = content()
    }

    /// Three or more choices do not fit side by side at a readable width, so
    /// they stack — the same rule a system alert applies.
    private var stacksActions: Bool { actions.count > 2 }

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            header
            message
            content
            actionButtons
        }
        .facilityDialogFrame(width: width, padding: 28)
        .background(.white, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
        // The same defined edge the other centered overlays use
        // (`NotificationCommentEditorOverlay`), not a barely-there hairline.
        .overlay {
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .stroke(.gray.opacity(0.28), lineWidth: 1)
        }
        .shadow(color: .black.opacity(0.24), radius: 28, y: 14)
        .accessibilityElement(children: .contain)
        .accessibilityAddTraits(.isModal)
    }

    private var header: some View {
        HStack(alignment: .top, spacing: 14) {
            ZStack {
                Circle()
                    .fill(tint.opacity(0.12))
                    .frame(width: 44, height: 44)
                Image(systemName: symbol)
                    .font(.title3.weight(.bold))
                    .foregroundStyle(tint)
            }
            .accessibilityHidden(true)

            // No close glyph: the Cancel action already dismisses, and two
            // ways out of one dialog only invite a mis-tap.
            Text(LocalizedStringKey(titleKey))
                .font(.system(size: 21, weight: .bold, design: .rounded))
                .foregroundStyle(FacilityTheme.ink)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.top, 8)
        }
    }

    private var message: some View {
        Text(LocalizedStringKey(messageKey))
            .font(.subheadline)
            .foregroundStyle(FacilityTheme.ink)
            .fixedSize(horizontal: false, vertical: true)
            .frame(maxWidth: .infinity, alignment: .leading)
    }

    @ViewBuilder
    private var actionButtons: some View {
        if stacksActions {
            VStack(spacing: 10) {
                ForEach(actions) { button(for: $0) }
                if let cancelTitleKey {
                    button(for: FacilityDialogAction(titleKey: cancelTitleKey, perform: cancel))
                }
            }
        } else {
            // A wide dialog keeps its buttons at the standard size, on the
            // trailing edge, instead of stretching them across the frame.
            HStack(spacing: 12) {
                if let cancelTitleKey {
                    button(for: FacilityDialogAction(titleKey: cancelTitleKey, perform: cancel))
                }
                ForEach(actions) { button(for: $0) }
            }
            .frame(maxWidth: Self.standardWidth - 56)
            .frame(maxWidth: .infinity, alignment: .trailing)
        }
    }

    private func button(for action: FacilityDialogAction) -> some View {
        Button(action: action.perform) {
            Text(LocalizedStringKey(action.titleKey))
                .font(.subheadline.weight(.semibold))
                .lineLimit(1)
                .minimumScaleFactor(0.85)
                .foregroundStyle(foreground(for: action.emphasis))
                .frame(maxWidth: .infinity, minHeight: 44)
                .background(
                    background(for: action.emphasis),
                    in: RoundedRectangle(cornerRadius: 8, style: .continuous)
                )
                .overlay {
                    if action.emphasis == .secondary {
                        RoundedRectangle(cornerRadius: 8, style: .continuous)
                            .stroke(.gray.opacity(0.28), lineWidth: 1)
                    }
                }
        }
        .buttonStyle(.plain)
    }

    private func foreground(for emphasis: FacilityDialogAction.Emphasis) -> Color {
        switch emphasis {
        case .primary, .destructive: .white
        case .secondary: FacilityTheme.ink
        }
    }

    private func background(for emphasis: FacilityDialogAction.Emphasis) -> Color {
        switch emphasis {
        case .primary: FacilityTheme.accent
        case .destructive: FacilityTheme.red
        case .secondary: Color.black.opacity(0.06)
        }
    }
}

extension FacilityConfirmationDialog where Content == EmptyView {
    init(
        titleKey: String,
        messageKey: String,
        symbol: String = "exclamationmark.triangle.fill",
        tint: Color = FacilityTheme.orange,
        cancelTitleKey: String? = "common.cancel",
        actions: [FacilityDialogAction],
        cancel: @escaping () -> Void
    ) {
        self.init(
            titleKey: titleKey,
            messageKey: messageKey,
            symbol: symbol,
            tint: tint,
            cancelTitleKey: cancelTitleKey,
            actions: actions,
            cancel: cancel,
            content: { EmptyView() }
        )
    }
}

private struct FacilityConfirmationDialogModifier: ViewModifier {
    @Binding var isPresented: Bool
    let titleKey: String
    let messageKey: String
    let symbol: String
    let tint: Color
    let cancelTitleKey: String?
    let dismissOnBackdropTap: Bool
    let actions: [FacilityDialogAction]

    @Environment(\.accessibilityReduceMotion) private var accessibilityReduceMotion

    func body(content: Content) -> some View {
        content.overlay {
            if isPresented {
                ZStack {
                    Color.black.opacity(0.32)
                        .ignoresSafeArea()
                        .onTapGesture {
                            guard dismissOnBackdropTap else { return }
                            isPresented = false
                        }

                    FacilityConfirmationDialog(
                        titleKey: titleKey,
                        messageKey: messageKey,
                        symbol: symbol,
                        tint: tint,
                        cancelTitleKey: cancelTitleKey,
                        actions: actions.map { action in
                            FacilityDialogAction(
                                titleKey: action.titleKey,
                                emphasis: action.emphasis
                            ) {
                                isPresented = false
                                action.perform()
                            }
                        },
                        cancel: { isPresented = false }
                    )
                }
                .transition(.opacity)
            }
        }
        .animation(
            accessibilityReduceMotion ? nil : .easeOut(duration: 0.18),
            value: isPresented
        )
    }
}

extension View {
    /// Shared warning before retaining a notification locally as a draft.
    func facilitySaveDraftConfirmation(
        isPresented: Binding<Bool>,
        saveDraft: @escaping () -> Void
    ) -> some View {
        facilityConfirmationDialog(
            isPresented: isPresented,
            titleKey: "notifications.detail.saveDraftConfirmation.title",
            messageKey: "notifications.detail.saveDraftConfirmation.message",
            confirmTitleKey: "inspection.action.saveDraft",
            confirm: saveDraft
        )
    }

    /// Presents a centered confirmation dialog instead of a system alert.
    ///
    /// Every action dismisses the dialog before it runs, so a call site only
    /// supplies what the choice does.
    func facilityConfirmationDialog(
        isPresented: Binding<Bool>,
        titleKey: String,
        messageKey: String,
        symbol: String = "exclamationmark.triangle.fill",
        tint: Color = FacilityTheme.orange,
        cancelTitleKey: String? = "common.cancel",
        dismissOnBackdropTap: Bool = true,
        actions: [FacilityDialogAction]
    ) -> some View {
        modifier(
            FacilityConfirmationDialogModifier(
                isPresented: isPresented,
                titleKey: titleKey,
                messageKey: messageKey,
                symbol: symbol,
                tint: tint,
                cancelTitleKey: cancelTitleKey,
                dismissOnBackdropTap: dismissOnBackdropTap,
                actions: actions
            )
        )
    }

    /// Convenience for the common confirm/cancel warning.
    func facilityConfirmationDialog(
        isPresented: Binding<Bool>,
        titleKey: String,
        messageKey: String,
        confirmTitleKey: String,
        symbol: String = "exclamationmark.triangle.fill",
        tint: Color = FacilityTheme.orange,
        isDestructive: Bool = false,
        cancelTitleKey: String? = "common.cancel",
        dismissOnBackdropTap: Bool = true,
        confirm: @escaping () -> Void
    ) -> some View {
        facilityConfirmationDialog(
            isPresented: isPresented,
            titleKey: titleKey,
            messageKey: messageKey,
            symbol: symbol,
            tint: tint,
            cancelTitleKey: cancelTitleKey,
            dismissOnBackdropTap: dismissOnBackdropTap,
            actions: [
                FacilityDialogAction(
                    titleKey: confirmTitleKey,
                    emphasis: isDestructive ? .destructive : .primary,
                    perform: confirm
                )
            ]
        )
    }
}
