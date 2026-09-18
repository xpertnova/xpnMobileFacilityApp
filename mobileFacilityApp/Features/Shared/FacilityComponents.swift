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
    /// `nil` while the counter is not known yet. It is drawn as a placeholder
    /// bar rather than as `0`, which would read as "nothing to do".
    let count: Int?
    let titleKey: String
    let icon: String
    let tint: Color
    let action: () -> Void

    @Environment(\.accessibilityReduceMotion) private var accessibilityReduceMotion

    var body: some View {
        Button(action: action) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(verbatim: count.map(String.init) ?? "000")
                        .font(.system(size: 32, weight: .bold, design: .rounded))
                        .foregroundStyle(FacilityTheme.ink)
                        .redacted(reason: count == nil ? .placeholder : [])
                        // A counter that changes — the saved value replaced by
                        // a different fresh one, or a sync — rolls to its new
                        // value instead of jumping.
                        .contentTransition(.numericText(value: Double(count ?? 0)))
                        .animation(accessibilityReduceMotion ? nil : .snappy(duration: 0.35), value: count)
                        .accessibilityLabel(
                            count.map { Text(verbatim: String($0)) } ?? Text("dashboard.metrics.loading")
                        )
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
    /// Inspection-form chips. They keep clear of the red/orange/green/blue the
    /// status chips beside them own, so a form name never reads as a status.
    case formMaintenancePlan
    case formElevator
    case formRoundInspection
    case formFixedLadder
    case formMobileLadder
    case formHoldOpenSystem
    case formSubdistribution
    case formRoofSystem
    /// A value the app can only show verbatim, such as an SAP control key it
    /// has no screen for.
    case neutral

    var foreground: Color {
        switch self {
        case .costGroup, .formMaintenancePlan:
            Color(red: 94 / 255, green: 92 / 255, blue: 230 / 255)
        case .open:
            Color(red: 0, green: 122 / 255, blue: 1)
        case .attention:
            Color(red: 1, green: 59 / 255, blue: 48 / 255)
        case .temporarilySaved:
            Color(red: 181 / 255, green: 106 / 255, blue: 0)
        case .complete:
            Color(red: 11 / 255, green: 125 / 255, blue: 87 / 255)
        case .formElevator:
            Color(red: 142 / 255, green: 68 / 255, blue: 173 / 255)
        case .formRoundInspection:
            Color(red: 0, green: 138 / 255, blue: 130 / 255)
        case .formFixedLadder:
            Color(red: 140 / 255, green: 94 / 255, blue: 60 / 255)
        case .formMobileLadder:
            Color(red: 156 / 255, green: 63 / 255, blue: 126 / 255)
        case .formHoldOpenSystem:
            Color(red: 194 / 255, green: 24 / 255, blue: 91 / 255)
        case .formSubdistribution:
            Color(red: 72 / 255, green: 94 / 255, blue: 160 / 255)
        case .formRoofSystem:
            Color(red: 58 / 255, green: 110 / 255, blue: 120 / 255)
        case .neutral:
            Color(red: 100 / 255, green: 110 / 255, blue: 125 / 255)
        }
    }

    var background: Color {
        switch self {
        case .costGroup, .formMaintenancePlan:
            Color(red: 240 / 255, green: 236 / 255, blue: 253 / 255)
        case .open:
            Color(red: 234 / 255, green: 243 / 255, blue: 1)
        case .attention:
            Color(red: 1, green: 236 / 255, blue: 235 / 255)
        case .temporarilySaved:
            Color(red: 1, green: 244 / 255, blue: 224 / 255)
        case .complete:
            Color(red: 230 / 255, green: 246 / 255, blue: 240 / 255)
        case .formElevator:
            Color(red: 245 / 255, green: 238 / 255, blue: 250 / 255)
        case .formRoundInspection:
            Color(red: 232 / 255, green: 248 / 255, blue: 247 / 255)
        case .formFixedLadder:
            Color(red: 248 / 255, green: 241 / 255, blue: 233 / 255)
        case .formMobileLadder:
            Color(red: 250 / 255, green: 236 / 255, blue: 246 / 255)
        case .formHoldOpenSystem:
            Color(red: 253 / 255, green: 235 / 255, blue: 241 / 255)
        case .formSubdistribution:
            Color(red: 236 / 255, green: 240 / 255, blue: 250 / 255)
        case .formRoofSystem:
            Color(red: 233 / 255, green: 244 / 255, blue: 246 / 255)
        case .neutral:
            Color(red: 240 / 255, green: 242 / 255, blue: 245 / 255)
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
