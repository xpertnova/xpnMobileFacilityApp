import SwiftUI

struct FormsView: View {
    let demo: FacilityDemoViewModel
    @Environment(\.accessibilityReduceMotion) private var accessibilityReduceMotion
    @State private var selectedPreviewForm: FacilityForm?
    @State private var selectedActiveForm: FacilityForm?

    private let columns = [
        GridItem(.flexible(minimum: 240), spacing: 15),
        GridItem(.flexible(minimum: 240), spacing: 15),
        GridItem(.flexible(minimum: 240), spacing: 15)
    ]

    var body: some View {
        Group {
            if let selectedActiveForm {
                activeWorkflow(for: selectedActiveForm)
                    .transition(.move(edge: .trailing).combined(with: .opacity))
            } else {
                ScrollView {
                    VStack(alignment: .leading, spacing: 22) {
                        PageHeader("forms.title", subtitle: "forms.subtitle")

                        LazyVGrid(columns: columns, spacing: 15) {
                            ForEach(demo.forms) { form in
                                Button {
                                    demo.selectedBriefingDraftID = nil
                                    demo.selectedElectricalSafetyDraftID = nil
                                    demo.selectedProofOfQualificationDraftID = nil
                                    if form.id == "briefing" || form.id == "qualification" || (!demo.isDemoMode && (form.id == "fire" || form.id == "electrical")) {
                                        selectedActiveForm = form
                                    } else {
                                        selectedPreviewForm = form
                                    }
                                } label: {
                                    FormCard(form: form)
                                }
                                .buttonStyle(.plain)
                                .accessibilityHint("forms.openPreview")
                                .disabled(demo.isDemoMode && (form.id == "fire" || form.id == "electrical"))
                            }
                        }
                    }
                    .padding(28)
                    .frame(maxWidth: 1280, alignment: .leading)
                }
                .transition(.opacity)
            }
        }
        .animation(
            accessibilityReduceMotion ? nil : .snappy(duration: 0.32, extraBounce: 0),
            value: selectedActiveForm?.id
        )
        .sheet(item: $selectedPreviewForm) { form in
            FormWorkflowPreview(form: form)
                .presentationDetents([.medium, .large])
        }
        .onAppear {
            if let draftID = demo.selectedProofOfQualificationDraftID,
               demo.offlineWorkStore.item(id: draftID)?.payload.proofOfQualification != nil {
                selectedActiveForm = demo.forms.first(where: { $0.id == "qualification" })
            } else if let draftID = demo.selectedElectricalSafetyDraftID,
               demo.offlineWorkStore.item(id: draftID)?.payload.electricalSafety != nil {
                selectedActiveForm = demo.forms.first(where: { $0.id == "electrical" })
            } else if let draftID = demo.selectedBriefingDraftID,
                      demo.offlineWorkStore.item(id: draftID)?.payload.briefing != nil {
                selectedActiveForm = demo.forms.first(where: { $0.id == "briefing" })
            }
        }
    }

    @ViewBuilder
    private func activeWorkflow(for form: FacilityForm) -> some View {
        switch form.id {
        case "briefing":
            BriefingWorkflowView(
                workspace: demo,
                existingDraft: demo.offlineWorkStore.item(id: demo.selectedBriefingDraftID),
                onClose: closeActiveForm
            )
        case "fire":
            FirePermitWorkflowView(workspace: demo, onClose: closeActiveForm)
        case "electrical":
            ElectricalSafetyWorkflowView(
                workspace: demo,
                existingDraft: demo.offlineWorkStore.item(id: demo.selectedElectricalSafetyDraftID),
                onClose: closeActiveForm
            )
        case "qualification":
            ProofOfQualificationWorkflowView(
                workspace: demo,
                existingDraft: demo.offlineWorkStore.item(id: demo.selectedProofOfQualificationDraftID),
                onClose: closeActiveForm
            )
        default:
            EmptyView()
        }
    }

    private func closeActiveForm() {
        demo.selectedBriefingDraftID = nil
        demo.selectedElectricalSafetyDraftID = nil
        demo.selectedProofOfQualificationDraftID = nil
        selectedActiveForm = nil
    }
}

private struct FormCard: View {
    let form: FacilityForm

    private var icon: String {
        switch form.id {
        case "briefing": "🦺"
        case "fire": "🔥"
        case "electrical": "⚡"
        default: "📄"
        }
    }

    private var iconBackground: Color {
        switch form.id {
        case "briefing":
            Color(red: 234 / 255, green: 243 / 255, blue: 1)
        case "fire":
            Color(red: 1, green: 236 / 255, blue: 235 / 255)
        case "electrical":
            Color(red: 1, green: 244 / 255, blue: 224 / 255)
        default:
            FacilityTheme.accentSoft
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            // The Forms cards use the native Unicode icon set from the MFM HTML
            // reference rather than SF Symbols.
            Text(icon)
                .font(.title3)
                .frame(width: 44, height: 44)
                .background(iconBackground, in: RoundedRectangle(cornerRadius: 13, style: .continuous))
                .accessibilityHidden(true)
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
