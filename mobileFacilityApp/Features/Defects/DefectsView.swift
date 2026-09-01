import SwiftUI

struct DefectsView: View {
    let demo: FacilityDemoViewModel
    @Environment(\.accessibilityReduceMotion) private var accessibilityReduceMotion
    @State private var showsUnavailableNotificationAlert = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                PageHeader(
                    "defects.title",
                    subtitle: "defects.subtitle",
                    trailing: AnyView(recordDefectButton)
                )

                switch demo.offlineWorkStore.state {
                case .loading:
                    ProgressView()
                        .frame(maxWidth: .infinity, minHeight: 180)
                        .transition(.opacity)
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
                    .transition(.opacity.combined(with: .scale(scale: 0.98)))
                case .empty, .loaded:
                    defectContent
                        .transition(.opacity.combined(with: .scale(scale: 0.98, anchor: .topLeading)))
                }
            }
            .padding(28)
            .frame(maxWidth: 1280, alignment: .leading)
            .animation(defectContentAnimation, value: demo.offlineWorkStore.state)
            .animation(defectContentAnimation, value: demo.offlineWorkStore.closedDefectNotificationItems)
        }
        .task {
            guard demo.offlineWorkStore.state == .loading else { return }
            await demo.offlineWorkStore.load()
        }
        .alert("drafts.notification.unavailable.title", isPresented: $showsUnavailableNotificationAlert) {
            Button("common.ok", role: .cancel) { }
        } message: {
            Text("drafts.notification.unavailable.message")
        }
    }

    private var recordDefectButton: some View {
        Button {
            // Defect capture is intentionally deferred until its workflow is verified.
        } label: {
            Label("defects.capture", systemImage: "plus")
        }
        .buttonStyle(.borderedProminent)
        .tint(FacilityTheme.accent)
        .disabled(true)
    }

    @ViewBuilder
    private var defectContent: some View {
        if demo.offlineWorkStore.closedDefectNotificationItems.isEmpty {
            EmptyDemoState(
                symbol: "checkmark.circle",
                titleKey: "defects.empty.title",
                subtitleKey: "defects.empty.subtitle"
            )
        } else {
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 300), spacing: 15)], spacing: 15) {
                ForEach(demo.offlineWorkStore.closedDefectNotificationItems) { item in
                    if let review = item.payload.notificationReview {
                        ClosedDefectNotificationCard(item: item, review: review) {
                            open(review)
                        }
                        .transition(.opacity.combined(with: .scale(scale: 0.94, anchor: .topLeading)))
                    }
                }
            }
        }
    }

    private func open(_ review: NotificationReviewDraftPayload) {
        Task {
            guard await demo.openSavedNotificationReview(review) else {
                showsUnavailableNotificationAlert = true
                return
            }
        }
    }

    private var defectContentAnimation: Animation? {
        accessibilityReduceMotion ? nil : .snappy(duration: 0.32, extraBounce: 0.04)
    }
}

private struct ClosedDefectNotificationCard: View {
    let item: OfflineWorkItem
    let review: NotificationReviewDraftPayload
    let action: () -> Void

    private var title: String {
        let title = review.notificationSnapshot?.title.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return title.isEmpty ? String(localized: "drafts.notification.title") : title
    }

    private var location: String {
        guard let snapshot = review.notificationSnapshot else { return review.notificationID }
        return snapshot.functionalLocationName.isEmpty ? snapshot.functionalLocationID : snapshot.functionalLocationName
    }

    private var defectCount: Int {
        review.results.values.filter { $0 == .yes }.count
    }

    var body: some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 14) {
                HStack(alignment: .top) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundStyle(FacilityTheme.red)
                        .frame(width: 42, height: 42)
                        .background(FacilityTheme.red.opacity(0.12), in: RoundedRectangle(cornerRadius: 13, style: .continuous))
                    Spacer()
                    VStack(alignment: .trailing, spacing: 6) {
                        StatusPill(status: .attention)
                        StatusPill(status: .closedLocally)
                    }
                }

                VStack(alignment: .leading, spacing: 5) {
                    Text(title)
                        .font(.headline)
                        .foregroundStyle(FacilityTheme.ink)
                    Text(location)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Text("\(defectCount) \(String(localized: "defects.findings"))")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .padding(.top, 4)
                }

                Divider()

                HStack {
                    Text(review.notificationID)
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(FacilityTheme.blue)
                    Spacer()
                    Text(item.updatedAt, format: .dateTime.day().month().year().hour().minute())
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                }
            }
            .padding(18)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityHint(Text("drafts.accessibility.openNotification"))
        .facilityCard(padding: 0)
    }
}
