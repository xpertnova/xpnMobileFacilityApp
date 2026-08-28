import SwiftUI

struct ManualCaptureView: View {
    let demo: FacilityDemoViewModel
    @State private var category = "manual.category.issue"
    @State private var location = "Building A · Level 02"
    @State private var note = ""
    @State private var saved = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                PageHeader("manual.title", subtitle: "manual.subtitle")

                HStack(alignment: .top, spacing: 18) {
                    form
                    guidance
                }
            }
            .padding(28)
            .frame(maxWidth: 1280, alignment: .leading)
        }
        .alert("manual.saved.title", isPresented: $saved) {
            Button("common.ok", role: .cancel) { }
        } message: {
            Text("manual.saved.message")
        }
    }

    private var form: some View {
        VStack(alignment: .leading, spacing: 18) {
            SectionTitle("manual.form.title", subtitle: "manual.form.subtitle")

            VStack(alignment: .leading, spacing: 7) {
                Text("manual.category")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                Picker("manual.category", selection: $category) {
                    Text("manual.category.issue").tag("manual.category.issue")
                    Text("manual.category.reading").tag("manual.category.reading")
                    Text("manual.category.note").tag("manual.category.note")
                }
                .pickerStyle(.segmented)
            }

            VStack(alignment: .leading, spacing: 7) {
                Text("manual.location")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                TextField("manual.location.placeholder", text: $location)
                    .textFieldStyle(.plain)
                    .padding(12)
                    .background(FacilityTheme.canvas, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            }

            VStack(alignment: .leading, spacing: 7) {
                Text("manual.note")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                TextEditor(text: $note)
                    .frame(minHeight: 130)
                    .padding(8)
                    .scrollContentBackground(.hidden)
                    .background(FacilityTheme.canvas, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                    .overlay(alignment: .topLeading) {
                        if note.isEmpty {
                            Text("manual.note.placeholder")
                                .font(.body)
                                .foregroundStyle(.tertiary)
                                .padding(.horizontal, 14)
                                .padding(.vertical, 18)
                                .allowsHitTesting(false)
                        }
                    }
            }

            HStack {
                Label("manual.photo", systemImage: "camera")
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(FacilityTheme.blue)
                    .padding(11)
                    .background(FacilityTheme.blue.opacity(0.1), in: RoundedRectangle(cornerRadius: 11, style: .continuous))
                Spacer()
                Button("manual.save") {
                    demo.saveManualDraft()
                    saved = true
                }
                .buttonStyle(.borderedProminent)
                .tint(FacilityTheme.accent)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .facilityCard()
    }

    private var guidance: some View {
        VStack(alignment: .leading, spacing: 14) {
            Image(systemName: "tray.and.arrow.down.fill")
                .font(.title2)
                .foregroundStyle(FacilityTheme.orange)
                .frame(width: 48, height: 48)
                .background(FacilityTheme.orange.opacity(0.12), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
            Text("manual.guidance.title")
                .font(.title3.weight(.bold))
            Text("manual.guidance.body")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            Divider()
            Label("manual.guidance.demo", systemImage: "theatermasks.fill")
                .font(.caption.weight(.semibold))
                .foregroundStyle(FacilityTheme.accent)
        }
        .frame(width: 280, alignment: .leading)
        .facilityCard()
    }
}
