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

/// The same keyboard-ready comment frame used by Aufzugskontrolle.
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
            Color.black.opacity(0.14)
                .ignoresSafeArea()
                .onTapGesture(perform: cancel)

            VStack(alignment: .leading, spacing: 16) {
                HStack(spacing: 8) {
                    Button(action: cancel) {
                        Image(systemName: "xmark")
                            .font(.body.weight(.bold))
                            .foregroundStyle(FacilityTheme.ink)
                            .frame(width: 44, height: 44)
                            .background(.white, in: Circle())
                            .overlay { Circle().stroke(.gray.opacity(0.28)) }
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(Text("common.cancel"))

                    Text("notifications.detail.commentEditor.title")
                        .font(.headline)
                        .foregroundStyle(FacilityTheme.ink)

                    Spacer(minLength: 0)
                }

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
                        .scrollContentBackground(.hidden)
                        .padding(10)
                        .focused($isEditorFocused)
                        .accessibilityLabel(Text("notifications.detail.commentEditor.placeholder"))
                }
                .frame(height: layout.commentEditorHeight)
                .background(.white, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                .overlay {
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .stroke(.gray.opacity(0.32))
                }

                HStack {
                    Spacer()
                    Button("notifications.detail.commentEditor.done", action: dismiss)
                        .buttonStyle(.borderedProminent)
                        .tint(FacilityTheme.accent)
                }
            }
            .facilityDialogFrame(width: 460, padding: 22)
            .background(Color(white: 0.95), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .stroke(.gray.opacity(0.24))
            }
            .shadow(color: Color.black.opacity(0.20), radius: 26, y: 12)
        }
        .onAppear { isEditorFocused = true }
    }

    private func cancel() {
        comment = initialComment
        dismiss()
    }
}
