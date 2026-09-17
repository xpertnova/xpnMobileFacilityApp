import SwiftUI

struct PageHeader: View {
    let titleKey: String
    let subtitleKey: String
    let trailing: AnyView?

    init(_ titleKey: String, subtitle subtitleKey: String, trailing: AnyView? = nil) {
        self.titleKey = titleKey
        self.subtitleKey = subtitleKey
        self.trailing = trailing
    }

    var body: some View {
        if let trailing {
            ViewThatFits(in: .horizontal) {
                HStack(alignment: .bottom, spacing: 20) {
                    title
                        .fixedSize(horizontal: true, vertical: false)
                    Spacer(minLength: 12)
                    trailing
                }

                VStack(alignment: .leading, spacing: 14) {
                    title
                    trailing
                        .frame(maxWidth: .infinity, alignment: .trailing)
                }
            }
        } else {
            title
        }
    }

    private var title: some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(LocalizedStringKey(titleKey))
                .facilityPageTitleFont()
                .foregroundStyle(FacilityTheme.ink)
            Text(LocalizedStringKey(subtitleKey))
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
    }
}

struct MetricCard: View {
    let count: Int
    let titleKey: String
    let icon: String
    let tint: Color
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("\(count)")
                        .font(.system(size: 32, weight: .bold, design: .rounded))
                        .foregroundStyle(FacilityTheme.ink)
                    Text(LocalizedStringKey(titleKey))
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.leading)
                }
                Spacer(minLength: 6)
                // Keep the visual language of the MFM HTML reference. Its dashboard
                // metrics intentionally use native Unicode icons rather than SF Symbols.
                Text(icon)
                    .font(.title3)
                    .frame(width: 42, height: 42)
                    .background(tint.opacity(0.12), in: RoundedRectangle(cornerRadius: 13, style: .continuous))
                    .accessibilityHidden(true)
            }
            // The localized labels have different line counts. Keep every dashboard
            // metric button aligned to the reference card height in both languages.
            .frame(maxWidth: .infinity, minHeight: 80, alignment: .topLeading)
            .facilityCard()
        }
        .buttonStyle(.plain)
    }
}

struct SectionTitle: View {
    let titleKey: String
    let subtitleKey: String?

    init(_ titleKey: String, subtitle subtitleKey: String? = nil) {
        self.titleKey = titleKey
        self.subtitleKey = subtitleKey
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(LocalizedStringKey(titleKey))
                .font(.title3.weight(.bold))
            if let subtitleKey {
                Text(LocalizedStringKey(subtitleKey))
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
        }
    }
}

struct EmptyDemoState: View {
    let symbol: String
    let titleKey: String
    let subtitleKey: String

    var body: some View {
        VStack(spacing: 11) {
            Image(systemName: symbol)
                .font(.largeTitle)
                .foregroundStyle(FacilityTheme.accent)
            Text(LocalizedStringKey(titleKey))
                .font(.headline)
            Text(LocalizedStringKey(subtitleKey))
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 56)
        .facilityCard()
    }
}

/// Compact status chips shared by list rows that follow the MFM HTML template.
enum FacilityTemplateBadgeStyle {
    case costGroup
    case open
    case attention
    case temporarilySaved
    case complete
    /// Form codes such as `TFM5`, grey like the badge in the notification header.
    case neutral

    var foreground: Color {
        switch self {
        case .costGroup: Color(red: 94 / 255, green: 92 / 255, blue: 230 / 255)
        case .open: Color(red: 0, green: 122 / 255, blue: 1)
        case .attention: Color(red: 1, green: 59 / 255, blue: 48 / 255)
        case .temporarilySaved: Color(red: 181 / 255, green: 106 / 255, blue: 0)
        case .complete: Color(red: 11 / 255, green: 125 / 255, blue: 87 / 255)
        case .neutral: Color.secondary
        }
    }

    var background: Color {
        switch self {
        case .costGroup: Color(red: 240 / 255, green: 236 / 255, blue: 253 / 255)
        case .open: Color(red: 234 / 255, green: 243 / 255, blue: 1)
        case .attention: Color(red: 1, green: 236 / 255, blue: 235 / 255)
        case .temporarilySaved: Color(red: 1, green: 244 / 255, blue: 224 / 255)
        case .complete: Color(red: 230 / 255, green: 246 / 255, blue: 240 / 255)
        case .neutral: Color(white: 0.92)
        }
    }
}

struct FacilityTemplateBadge: View {
    private let title: Text
    let style: FacilityTemplateBadgeStyle

    init(text: String, style: FacilityTemplateBadgeStyle) {
        title = Text(text)
        self.style = style
    }

    init(localized titleKey: LocalizedStringKey, style: FacilityTemplateBadgeStyle) {
        title = Text(titleKey)
        self.style = style
    }

    var body: some View {
        title
            .font(.system(size: 11.5, weight: .bold))
            .foregroundStyle(style.foreground)
            .lineLimit(1)
            .padding(.horizontal, 10)
            .padding(.vertical, 3)
            .background(style.background, in: Capsule())
    }
}

/// Shared comment editor used by inspection workflows. Keeping this surface
/// consistent means a technician gets the same focused, keyboard-ready editor
/// whether they are documenting a notification or a mobile ladder.
struct FacilityCommentEditorOverlay: View {
    @Binding var comment: String
    let dismiss: () -> Void
    @FocusState private var isEditorFocused: Bool
    @Environment(\.facilityLayout) private var layout

    var body: some View {
        ZStack {
            Color.black.opacity(0.14)
                .ignoresSafeArea()
                .onTapGesture(perform: dismiss)

            VStack(alignment: .leading, spacing: 16) {
                Text("notifications.detail.commentEditor.title")
                    .font(.headline)
                    .foregroundStyle(FacilityTheme.ink)

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
                .background(Color(white: 0.89), in: RoundedRectangle(cornerRadius: 12, style: .continuous))

                HStack {
                    Spacer()
                    Button("notifications.detail.commentEditor.done", action: dismiss)
                        .buttonStyle(.borderedProminent)
                        .tint(FacilityTheme.accent)
                }
            }
            .facilityDialogFrame(width: 460, padding: 22)
            .background(Color(white: 0.95), in: RoundedRectangle(cornerRadius: 24, style: .continuous))
            .shadow(color: Color.black.opacity(0.20), radius: 26, y: 12)
        }
        .onAppear { isEditorFocused = true }
    }
}

/// One persistent action bar for every inspection workflow. The order,
/// labels, spacing, and enabled-state treatment deliberately match the
/// Mobile Ladder reference: Everything OK, Save draft, Close notification.
struct FacilityInspectionActionBar: View {
    let markEverythingOkay: () -> Void
    let saveDraft: () -> Void
    let closeNotification: () -> Void
    let isMarkEverythingOkayEnabled: Bool
    let isSaveDraftEnabled: Bool
    let isCloseNotificationEnabled: Bool

    var body: some View {
        HStack(spacing: 14) {
            Spacer(minLength: 12)

            Button("inspection.action.everythingOkay", action: markEverythingOkay)
                .buttonStyle(.plain)
                .foregroundStyle(FacilityTheme.blue)
                .disabled(!isMarkEverythingOkayEnabled)

            Button("inspection.action.saveDraft", action: saveDraft)
                .buttonStyle(.bordered)
                .tint(FacilityTheme.ink)
                .disabled(!isSaveDraftEnabled)

            Button("inspection.action.closeNotification", action: closeNotification)
                .buttonStyle(.borderedProminent)
                .tint(FacilityTheme.accent)
                .disabled(!isCloseNotificationEnabled)
        }
        .facilityPageHorizontalPadding()
        .padding(.vertical, 12)
        .background(.ultraThinMaterial)
        .overlay(alignment: .top) { Divider() }
    }
}
