import SwiftUI

/// The comment control used by the Aufzugskontrolle inspection and document forms.
struct NotificationCommentButton: View {
    let hasComment: Bool
    var isMissing: Bool = false
    var isReadOnly: Bool = false
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: hasComment ? "note.text" : "pencil")
                .foregroundStyle(
                    isMissing
                        ? FacilityTheme.red
                        : (hasComment ? FacilityTheme.blue : FacilityTheme.ink)
                )
                .frame(width: 44, height: 44)
                .background(.white, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .stroke(isMissing ? FacilityTheme.red : .gray.opacity(0.25))
                )
        }
        .buttonStyle(.plain)
        .disabled(isReadOnly)
        .accessibilityLabel(Text("notifications.detail.comment"))
    }
}

/// The same keyboard-ready comment frame used by Aufzugskontrolle, in the
/// chrome of `FacilityConfirmationDialog` so it looks like the app's other
/// dialogs: icon and title, the editor, then Cancel and Done.
struct NotificationCommentEditorOverlay: View {
    @Binding var comment: String
    let dismiss: () -> Void
    @State private var initialComment: String
    @FocusState private var isEditorFocused: Bool
    @Environment(\.facilityLayout) private var layout

    init(comment: Binding<String>, dismiss: @escaping () -> Void) {
        _comment = comment
        self.dismiss = dismiss
        _initialComment = State(initialValue: comment.wrappedValue)
    }

    var body: some View {
        ZStack {
            FacilityTheme.dialogScrim
                .ignoresSafeArea()
                .onTapGesture(perform: cancel)

            FacilityConfirmationDialog(
                titleKey: "notifications.detail.commentEditor.title",
                messageKey: nil,
                symbol: "text.bubble",
                tint: FacilityTheme.blue,
                actions: [
                    FacilityDialogAction(
                        titleKey: "notifications.detail.commentEditor.done",
                        emphasis: .primary,
                        perform: dismiss
                    )
                ],
                cancel: cancel
            ) {
                editor
            }
        }
        .onAppear { isEditorFocused = true }
    }

    /// The same field chrome as the form inputs, outlined in blue while the
    /// keyboard is up.
    private var editor: some View {
        ZStack(alignment: .topLeading) {
            if comment.isEmpty {
                Text("notifications.detail.commentEditor.placeholder")
                    .font(.body)
                    .foregroundStyle(.tertiary)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 18)
                    .allowsHitTesting(false)
            }

            TextEditor(text: $comment)
                .font(.body)
                .foregroundStyle(FacilityTheme.ink)
                .scrollContentBackground(.hidden)
                .padding(10)
                .focused($isEditorFocused)
                .accessibilityLabel(Text("notifications.detail.commentEditor.placeholder"))
        }
        .frame(height: layout.commentEditorHeight)
        .background(.white, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .stroke(
                    isEditorFocused ? FacilityTheme.blue : Color.black.opacity(0.11),
                    lineWidth: isEditorFocused ? 2 : 1
                )
        }
        .facilityAnimation(FacilityMotion.standard, value: isEditorFocused)
    }

    private func cancel() {
        comment = initialComment
        dismiss()
    }
}

#if DEBUG
#Preview("Comment editor", traits: .fixedLayout(width: 1_133, height: 744)) {
    NotificationCommentEditorOverlay(comment: .constant(""), dismiss: {})
        .facilityLayoutRoot()
}
#endif
