import SwiftUI

struct FormsView: View {
    let demo: FacilityDemoViewModel
    @State private var selectedForm: FacilityForm?

    private let columns = [
        GridItem(.flexible(minimum: 240), spacing: 15),
        GridItem(.flexible(minimum: 240), spacing: 15),
        GridItem(.flexible(minimum: 240), spacing: 15)
    ]

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                PageHeader("forms.title", subtitle: "forms.subtitle")

                LazyVGrid(columns: columns, spacing: 15) {
                    ForEach(demo.forms) { form in
                        Button {
                            selectedForm = form
                        } label: {
                            FormCard(form: form)
                        }
                        .buttonStyle(.plain)
                        .accessibilityHint("forms.openPreview")
                    }
                }
            }
            .padding(28)
            .frame(maxWidth: 1280, alignment: .leading)
        }
        .sheet(item: $selectedForm) { form in
            FormWorkflowPreview(form: form)
                .presentationDetents([.medium, .large])
        }
    }
}

private struct FormCard: View {
    let form: FacilityForm

    private var tint: Color {
        switch form.tint {
        case "red": FacilityTheme.red
        case "orange": FacilityTheme.orange
        case "green": FacilityTheme.accent
        default: FacilityTheme.blue
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Image(systemName: form.symbol)
                .font(.title2.weight(.semibold))
                .foregroundStyle(tint)
                .frame(width: 50, height: 50)
                .background(tint.opacity(0.12), in: RoundedRectangle(cornerRadius: 15, style: .continuous))
            Text(LocalizedStringKey(form.titleKey))
                .font(.headline)
                .foregroundStyle(FacilityTheme.ink)
            Text(LocalizedStringKey(form.subtitleKey))
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.leading)
            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, minHeight: 205, alignment: .leading)
        .facilityCard()
    }
}

private struct FormWorkflowPreview: View {
    let form: FacilityForm
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            List {
                Section("forms.preview.scope") {
                    Text(LocalizedStringKey(form.subtitleKey))
                        .foregroundStyle(.secondary)
                    ForEach(form.coverageKeys, id: \.self) { key in
                        Label(LocalizedStringKey(key), systemImage: "checkmark.circle.fill")
                            .foregroundStyle(FacilityTheme.ink)
                    }
                }

                Section {
                    Label("forms.preview.notice", systemImage: "lock.shield")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }
            .navigationTitle(Text(LocalizedStringKey(form.titleKey)))
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("forms.preview.done", action: dismiss.callAsFunction)
                }
            }
        }
    }
}
