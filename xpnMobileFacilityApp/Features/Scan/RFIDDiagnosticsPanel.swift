#if DEBUG
import SwiftUI
import UIKit

/// Debug builds only: the RFID reader's event log and a manual tag lookup, so
/// hardware testing can tell reader problems from data problems. Developer
/// facing, therefore not localized.
struct RFIDDiagnosticsPanel: View {
    let reader: RFIDReaderService
    let lookUp: (String) -> Void

    @State private var isExpanded = false
    @State private var manualTag = ""

    var body: some View {
        DisclosureGroup(isExpanded: $isExpanded) {
            VStack(alignment: .leading, spacing: 12) {
                HStack(spacing: 8) {
                    TextField(text: $manualTag, prompt: Text(verbatim: "RFID tag")) {
                        Text(verbatim: "RFID tag")
                    }
                    .textFieldStyle(.roundedBorder)
                    .textInputAutocapitalization(.characters)
                    .autocorrectionDisabled()
                    .onSubmit(submit)
                    Button(action: submit) { Text(verbatim: "Look up") }
                        .buttonStyle(.bordered)
                        .disabled(manualTag.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }

                HStack {
                    Text(verbatim: "\(reader.diagnostics.count) events")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Spacer()
                    Button(action: copyLog) { Label { Text(verbatim: "Copy log") } icon: { Image(systemName: "doc.on.doc") } }
                        .font(.caption)
                        .disabled(reader.diagnostics.isEmpty)
                }

                VStack(alignment: .leading, spacing: 6) {
                    ForEach(reader.diagnostics.prefix(40)) { entry in
                        Text(verbatim: Self.line(for: entry))
                            .font(.caption.monospaced())
                            .foregroundStyle(entry.isError ? FacilityTheme.red : FacilityTheme.ink)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .textSelection(.enabled)
                    }
                }
            }
            .padding(.top, 10)
        } label: {
            Label { Text(verbatim: "RFID diagnostics (debug)") } icon: { Image(systemName: "ladybug") }
                .font(.headline)
        }
        .facilityCard()
    }

    private func submit() {
        let tag = manualTag.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !tag.isEmpty else { return }
        lookUp(tag)
    }

    private func copyLog() {
        UIPasteboard.general.string = reader.diagnostics.reversed().map(Self.line(for:)).joined(separator: "\n")
    }

    private static func line(for entry: RFIDDiagnosticEntry) -> String {
        "\(entry.date.formatted(date: .omitted, time: .standard))  \(entry.message)"
    }
}
#endif
