import SwiftUI

struct DraftsView: View {
    let demo: FacilityDemoViewModel

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                PageHeader("drafts.title", subtitle: "drafts.subtitle")
                switch demo.offlineWorkStore.state {
                case .loading:
                    ProgressView()
                        .frame(maxWidth: .infinity, minHeight: 180)
                case .empty:
                    EmptyDemoState(symbol: "checkmark.circle", titleKey: "drafts.empty.title", subtitleKey: "drafts.empty.subtitle")
                case .failed:
                    ContentUnavailableView {
                        Label("offline.load.error.title", systemImage: "exclamationmark.triangle")
                    } description: {
                        Text("offline.load.error.message")
                    } actions: {
                        Button("common.retry") {
                            Task { await demo.offlineWorkStore.load() }
                        }
                        .buttonStyle(.borderedProminent)
                    }
                    .frame(maxWidth: .infinity, minHeight: 240)
                case .loaded:
                    VStack(spacing: 0) {
                        ForEach(demo.offlineWorkStore.items) { draft in
                            Button {
                                if draft.type == .manualCapture {
                                    demo.openManualCapture(draft.id)
                                }
                            } label: {
                                HStack(spacing: 13) {
                                Image(systemName: "tray.and.arrow.down.fill")
                                    .foregroundStyle(FacilityTheme.orange)
                                    .frame(width: 40, height: 40)
                                    .background(FacilityTheme.orange.opacity(0.12), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                                VStack(alignment: .leading, spacing: 4) {
                                    Text("manual.title")
                                        .font(.subheadline.weight(.semibold))
                                    Text(draft.payload.location)
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                                Spacer()
                                VStack(alignment: .trailing, spacing: 5) {
                                    OfflineStatusPill(status: draft.status)
                                    Text(draft.updatedAt, format: .dateTime.day().month().hour().minute())
                                        .font(.caption2)
                                        .foregroundStyle(.tertiary)
                                }
                            }
                            }
                            .buttonStyle(.plain)
                            .padding(17)
                            if draft.id != demo.offlineWorkStore.items.last?.id { Divider().padding(.leading, 18) }
                        }
                    }
                    .facilityCard(padding: 0)
                }
                if demo.isDemoMode {
                    Label("drafts.demoNotice", systemImage: "info.circle")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .padding(28)
            .frame(maxWidth: 1280, alignment: .leading)
        }
        .task {
            await demo.offlineWorkStore.load()
        }
    }
}
