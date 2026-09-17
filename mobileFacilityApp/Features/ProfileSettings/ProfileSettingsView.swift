import SwiftUI

struct ProfileSettingsView: View {
    let backDestination: AppDestination?
    let onBack: (() -> Void)?

    @AppStorage(AppLanguage.storageKey) private var languageCode = AppLanguage.resolved(from: nil).rawValue

    init(
        backDestination: AppDestination? = nil,
        onBack: (() -> Void)? = nil
    ) {
        self.backDestination = backDestination
        self.onBack = onBack
    }

    init(demo: FacilityDemoViewModel) {
        self.init(
            backDestination: demo.profileSettingsReturnDestination,
            onBack: { demo.closeProfileSettings() }
        )
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                header
                languageCard
            }
            .facilityPageContent()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(FacilityTheme.canvas.ignoresSafeArea())
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 7) {
            if let backDestination, let onBack {
                Button(action: onBack) {
                    Label(LocalizedStringKey(backDestination.titleKey), systemImage: "chevron.left")
                        .font(.subheadline.weight(.semibold))
                }
                .buttonStyle(.plain)
                .foregroundStyle(FacilityTheme.blue)
                .frame(minHeight: 44, alignment: .leading)
            }

            PageHeader("profile.settings.title", subtitle: "profile.settings.subtitle")
        }
    }

    private var languageCard: some View {
        ViewThatFits(in: .horizontal) {
            HStack(spacing: 22) {
                languageDescription
                Spacer(minLength: 32)
                languagePicker
                    .frame(width: 320)
            }

            VStack(alignment: .leading, spacing: 20) {
                languageDescription
                languagePicker
                    .frame(maxWidth: 420)
            }
        }
        .facilityCard()
    }

    private var languageDescription: some View {
        HStack(alignment: .top, spacing: 14) {
            Image(systemName: "globe")
                .font(.title2.weight(.semibold))
                .foregroundStyle(FacilityTheme.accent)
                .frame(width: 46, height: 46)
                .background(FacilityTheme.accentSoft, in: RoundedRectangle(cornerRadius: 13, style: .continuous))
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 4) {
                Text("profile.settings.language.title")
                    .font(.headline)
                    .foregroundStyle(FacilityTheme.ink)
                Text("profile.settings.language.description")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private var languagePicker: some View {
        Picker("profile.settings.language.picker", selection: selectedLanguage) {
            ForEach(AppLanguage.allCases) { language in
                Text(LocalizedStringKey(language.titleKey))
                    .tag(language)
            }
        }
        .pickerStyle(.segmented)
        .tint(FacilityTheme.accent)
        .frame(minHeight: 44)
    }

    private var selectedLanguage: Binding<AppLanguage> {
        Binding(
            get: { AppLanguage.resolved(from: languageCode) },
            set: { languageCode = $0.rawValue }
        )
    }
}

#Preview {
    ProfileSettingsView(
        backDestination: .notifications,
        onBack: {}
    )
    .frame(width: 900, height: 600)
}
