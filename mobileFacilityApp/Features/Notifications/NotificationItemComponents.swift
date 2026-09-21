import SwiftUI

/// Shared photo button with attachment counter badge reused across notification inspection checklists.
struct NotificationPhotoButton: View {
    let count: Int
    var isLimitReached = false
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            ZStack(alignment: .topTrailing) {
                Image(systemName: count == 0 ? "camera" : "camera.fill")
                    .foregroundStyle(isLimitReached ? FacilityTheme.red : (count == 0 ? FacilityTheme.ink : FacilityTheme.blue))
                    .frame(width: 44, height: 44)
                    .background(.white, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                    .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous).stroke(isLimitReached ? FacilityTheme.red : .gray.opacity(0.25)))

                if count > 0 {
                    Text(count, format: .number)
                        .font(.caption2.bold())
                        .foregroundStyle(.white)
                        .frame(minWidth: 18, minHeight: 18)
                        .background(isLimitReached ? FacilityTheme.red : FacilityTheme.blue, in: Circle())
                        .offset(x: 5, y: -5)
                }
            }
        }
        .buttonStyle(.plain)
        .accessibilityLabel(Text("notifications.detail.photo"))
        .accessibilityValue(Text(String(format: String(localized: "notifications.detail.photo.count"), count)))
    }
}

/// Shared comment button with pencil/note icon and defect highlight state reused across notification checklists.
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
                .background(.white, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .stroke(isMissing ? FacilityTheme.red : .gray.opacity(0.25))
                )
        }
        .buttonStyle(.plain)
        .disabled(isReadOnly)
        .accessibilityLabel(Text("notifications.detail.comment"))
    }
}

/// Shared info button with circular icon and popover presentation reused across notification checklists.
struct NotificationInfoButton: View {
    let information: String
    @State private var isShowingInformation = false

    var body: some View {
        Group {
            if information.isEmpty {
                Image(systemName: "info.circle")
                    .foregroundStyle(.tertiary)
                    .frame(width: 28, height: 28)
            } else {
                Button {
                    isShowingInformation = true
                } label: {
                    Image(systemName: "info.circle.fill")
                        .font(.title2.weight(.semibold))
                        .foregroundStyle(FacilityTheme.blue)
                        .frame(width: 52, height: 52)
                }
                .buttonStyle(.plain)
                .accessibilityLabel(Text("notifications.detail.showInformation"))
                .popover(isPresented: $isShowingInformation) {
                    NotificationInfoPopoverContent(information: information)
                }
            }
        }
    }
}

/// Shared info frame displayed in the info button popover.
struct NotificationInfoPopoverContent: View {
    let information: String

    var body: some View {
        Text(information)
            .font(.body)
            .padding(20)
            .frame(width: 360, alignment: .leading)
    }
}

/// Shared comment editor modal overlay reused across notification checklists.
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
                            .overlay {
                                Circle()
                                    .stroke(.gray.opacity(0.28))
                            }
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
            .background(Color(white: 0.95), in: RoundedRectangle(cornerRadius: 24, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 24, style: .continuous)
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

/// Shared metadata row for notification details cards.
struct NotificationMetadataRow: View {
    let titleKey: String
    let value: String
    var monospaced: Bool = false

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 24) {
            Text(LocalizedStringKey(titleKey))
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .frame(width: 180, alignment: .leading)

            Text(value)
                .font(monospaced ? .subheadline.monospaced() : .body)
                .foregroundStyle(FacilityTheme.ink)
                .fixedSize(horizontal: false, vertical: true)

            Spacer(minLength: 0)
        }
    }
}
