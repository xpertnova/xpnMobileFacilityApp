import SwiftUI

/// The report a closed notification kept locally — the same PDF that is sent
/// to SAP as the notification's document. It is only a local preview: the
/// upload keeps building its own copy from the cached source notification.
struct FormReportPDFArtifact: Identifiable, Equatable {
    let id: String
    let fileName: String
    let data: Data

    /// `nil` while the form is still a draft, or when no report was stored
    /// with it (older drafts closed before the report was kept).
    init?(notificationID: String, data: Data?) {
        guard let data, !data.isEmpty else { return nil }
        self.id = notificationID
        self.fileName = "Bericht_\(NotificationReportFormat.withoutLeadingZeros(notificationID)).pdf"
        self.data = data
    }
}

/// Paperclip next to a closed notification in the local-work and defect
/// lists. It sits outside the row's own button so the row stays tappable.
struct FormReportPaperclipButton: View {
    /// Diameter of the button and the spacing a row keeps before it. Rows
    /// lose `rowFootprint` of width to the paperclip, which is what
    /// `FormReportPreviewTests` measures against the narrowest window.
    static let diameter: CGFloat = 34
    static let rowSpacing: CGFloat = 12
    static var rowFootprint: CGFloat { diameter + rowSpacing }

    let report: FormReportPDFArtifact

    @State private var previewedReport: FormReportPDFArtifact?

    var body: some View {
        Button {
            previewedReport = report
        } label: {
            Image(systemName: "paperclip")
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(FacilityTheme.navy)
                .frame(width: Self.diameter, height: Self.diameter)
                .background(FacilityTheme.navy.opacity(0.08), in: Circle())
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(Text("report.preview.open"))
        .fullScreenCover(item: $previewedReport) { report in
            FormReportPDFPreview(report: report)
        }
    }
}

struct FormReportPDFPreview: View {
    let report: FormReportPDFArtifact

    @Environment(\.dismiss) private var dismiss
    @State private var shareURL: URL?

    var body: some View {
        NavigationStack {
            BriefingPDFDocumentView(data: report.data)
                .ignoresSafeArea(edges: .bottom)
                .navigationTitle("report.preview.title")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("app.button.close") { dismiss() }
                    }
                    if let shareURL {
                        ToolbarItem(placement: .primaryAction) {
                            ShareLink(item: shareURL) {
                                Label("briefing.pdf.share", systemImage: "square.and.arrow.up")
                            }
                        }
                    }
                }
        }
        .task { prepareShareFile() }
        .onDisappear(perform: cleanUpShareFile)
    }

    /// `ShareLink` needs a file so the sheet offers the report under its own
    /// name; the folder is removed again with the preview.
    private func prepareShareFile() {
        guard shareURL == nil else { return }
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
            .appendingPathComponent(report.fileName)
        do {
            try FileManager.default.createDirectory(
                at: url.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
            try report.data.write(to: url, options: .atomic)
            shareURL = url
        } catch {
            try? FileManager.default.removeItem(at: url.deletingLastPathComponent())
        }
    }

    private func cleanUpShareFile() {
        guard let shareURL else { return }
        try? FileManager.default.removeItem(at: shareURL.deletingLastPathComponent())
        self.shareURL = nil
    }
}
