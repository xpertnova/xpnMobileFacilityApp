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
        HStack(alignment: .bottom, spacing: 20) {
            VStack(alignment: .leading, spacing: 5) {
                Text(LocalizedStringKey(titleKey))
                    .font(.system(size: 29, weight: .bold, design: .rounded))
                    .foregroundStyle(FacilityTheme.ink)
                Text(LocalizedStringKey(subtitleKey))
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            Spacer(minLength: 12)
            trailing
        }
    }
}

struct MetricCard: View {
    let count: Int
    let titleKey: String
    let symbol: String
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
                Image(systemName: symbol)
                    .font(.title3.weight(.semibold))
                    .foregroundStyle(tint)
                    .frame(width: 42, height: 42)
                    .background(tint.opacity(0.12), in: RoundedRectangle(cornerRadius: 13, style: .continuous))
            }
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
