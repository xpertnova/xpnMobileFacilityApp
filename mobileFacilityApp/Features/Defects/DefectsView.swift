import SwiftUI

struct DefectsView: View {
    let demo: FacilityDemoViewModel

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                PageHeader(
                    "defects.title",
                    subtitle: "defects.subtitle",
                    trailing: AnyView(
                        Button {
                            demo.open(.manualCapture)
                        } label: {
                            Label("defects.capture", systemImage: "plus")
                        }
                        .buttonStyle(.borderedProminent)
                        .tint(FacilityTheme.accent)
                    )
                )

                LazyVGrid(columns: [GridItem(.adaptive(minimum: 270), spacing: 15)], spacing: 15) {
                    ForEach(demo.defects) { defect in
                        DefectCard(defect: defect)
                    }
                }
            }
            .padding(28)
            .frame(maxWidth: 1280, alignment: .leading)
        }
    }
}

private struct DefectCard: View {
    let defect: Defect

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .top) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .foregroundStyle(defect.severity == .attention ? FacilityTheme.red : FacilityTheme.orange)
                    .frame(width: 42, height: 42)
                    .background((defect.severity == .attention ? FacilityTheme.red : FacilityTheme.orange).opacity(0.12), in: RoundedRectangle(cornerRadius: 13, style: .continuous))
                Spacer()
                StatusPill(status: defect.severity)
            }
            VStack(alignment: .leading, spacing: 5) {
                Text(defect.title)
                    .font(.headline)
                    .foregroundStyle(FacilityTheme.ink)
                Text(defect.location)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Text(defect.description)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .lineLimit(3)
                    .padding(.top, 4)
            }
            Divider()
            HStack {
                Text(defect.id)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(FacilityTheme.blue)
                Spacer()
                Text(defect.reportedAt)
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }
        }
        .facilityCard()
    }
}
