import SwiftUI

struct DraftsView: View {
    let demo: FacilityDemoViewModel

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                PageHeader("drafts.title", subtitle: "drafts.subtitle")
                if demo.drafts.isEmpty {
                    EmptyDemoState(symbol: "checkmark.circle", titleKey: "drafts.empty.title", subtitleKey: "drafts.empty.subtitle")
                } else {
                    VStack(spacing: 0) {
                        ForEach(demo.drafts) { draft in
                            HStack(spacing: 13) {
                                Image(systemName: draft.status == .pending ? "arrow.triangle.2.circlepath" : "tray.and.arrow.down.fill")
                                    .foregroundStyle(draft.status == .pending ? FacilityTheme.accent : FacilityTheme.orange)
                                    .frame(width: 40, height: 40)
                                    .background((draft.status == .pending ? FacilityTheme.accent : FacilityTheme.orange).opacity(0.12), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                                VStack(alignment: .leading, spacing: 4) {
                                    Text(draft.title)
                                        .font(.subheadline.weight(.semibold))
                                    Text(draft.detail)
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                                Spacer()
                                VStack(alignment: .trailing, spacing: 5) {
                                    StatusPill(status: draft.status)
                                    Text(draft.savedAt)
                                        .font(.caption2)
                                        .foregroundStyle(.tertiary)
                                }
                            }
                            .padding(17)
                            if draft.id != demo.drafts.last?.id { Divider().padding(.leading, 18) }
                        }
                    }
                    .facilityCard(padding: 0)
                }
                Label("drafts.demoNotice", systemImage: "info.circle")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .padding(28)
            .frame(maxWidth: 1280, alignment: .leading)
        }
    }
}
