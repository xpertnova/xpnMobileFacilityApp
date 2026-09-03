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
                .font(.system(size: 29, weight: .bold))
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

    var foreground: Color {
        switch self {
        case .costGroup: Color(red: 94 / 255, green: 92 / 255, blue: 230 / 255)
        case .open: Color(red: 0, green: 122 / 255, blue: 1)
        case .attention: Color(red: 1, green: 59 / 255, blue: 48 / 255)
        case .temporarilySaved: Color(red: 181 / 255, green: 106 / 255, blue: 0)
        case .complete: Color(red: 11 / 255, green: 125 / 255, blue: 87 / 255)
        }
    }

    var background: Color {
        switch self {
        case .costGroup: Color(red: 240 / 255, green: 236 / 255, blue: 253 / 255)
        case .open: Color(red: 234 / 255, green: 243 / 255, blue: 1)
        case .attention: Color(red: 1, green: 236 / 255, blue: 235 / 255)
        case .temporarilySaved: Color(red: 1, green: 244 / 255, blue: 224 / 255)
        case .complete: Color(red: 230 / 255, green: 246 / 255, blue: 240 / 255)
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
