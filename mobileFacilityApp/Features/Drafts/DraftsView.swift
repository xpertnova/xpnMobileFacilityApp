import SwiftUI

struct DraftsView: View {
    let demo: FacilityDemoViewModel
    @State private var showsUnavailableNotificationAlert = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                PageHeader(
                    "drafts.title",
                    subtitle: "drafts.subtitle",
                    trailing: demo.isDemoMode ? nil : AnyView(syncUnavailableControl)
                )

                switch demo.offlineWorkStore.state {
                case .loading:
                    ProgressView()
                        .frame(maxWidth: .infinity, minHeight: 180)
                case .empty:
                    emptyState
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
                    if demo.offlineWorkStore.localWorkNotificationItems.isEmpty
                        && demo.offlineWorkStore.briefingItems.isEmpty
                        && demo.offlineWorkStore.electricalSafetyItems.isEmpty {
                        emptyState
                    } else {
                        savedNotificationList
                        savedBriefingList
                        savedElectricalSafetyList
                    }
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
        .alert("drafts.notification.unavailable.title", isPresented: $showsUnavailableNotificationAlert) {
            Button("common.ok", role: .cancel) { }
        } message: {
            Text("drafts.notification.unavailable.message")
        }
    }

    private var syncUnavailableControl: some View {
        Button {
            // SAP writes for offline work have not been verified yet.
        } label: {
            Label("drafts.sync.action", systemImage: "arrow.triangle.2.circlepath")
        }
        .buttonStyle(.borderedProminent)
        .tint(FacilityTheme.navy)
        .disabled(true)
        .accessibilityHint(Text("offline.sync.unavailable"))
    }

    private var emptyState: some View {
        EmptyDemoState(
            symbol: "checkmark.circle",
            titleKey: "drafts.empty.title",
            subtitleKey: "drafts.empty.subtitle"
        )
    }

    private var savedNotificationList: some View {
        VStack(spacing: 12) {
            ForEach(demo.offlineWorkStore.localWorkNotificationItems) { item in
                if let review = item.payload.notificationReview {
                    SavedNotificationRow(item: item, review: review) {
                        open(review)
                    }
                }
            }
        }
    }

    @ViewBuilder
    private var savedBriefingList: some View {
        ForEach(demo.offlineWorkStore.briefingItems) { item in
            if let briefing = item.payload.briefing {
                Button {
                    demo.openBriefingDraft(item.id)
                } label: {
                    HStack(spacing: 15) {
                        Image(systemName: "figure.stand")
                            .font(.body.weight(.semibold))
                            .foregroundStyle(FacilityTheme.blue)
                            .frame(width: 44, height: 44)
                            .background(FacilityTheme.blue.opacity(0.12), in: RoundedRectangle(cornerRadius: 13, style: .continuous))
                        VStack(alignment: .leading, spacing: 4) {
                            Text("Safety briefing")
                                .font(.headline)
                                .foregroundStyle(FacilityTheme.ink)
                            Text("\(briefing.businessEntityTitle) · \(briefing.buildingTitle)")
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                            Text(briefing.taskDescription)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                        }
                        Spacer()
                        VStack(alignment: .trailing, spacing: 6) {
                            OfflineStatusPill(status: item.status)
                            Text(item.updatedAt, format: .dateTime.day().month().year().hour().minute())
                                .font(.caption2)
                                .foregroundStyle(.tertiary)
                        }
                    }
                    .padding(17)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .facilityCard(padding: 0)
            }
        }
    }

    @ViewBuilder
    private var savedElectricalSafetyList: some View {
        ForEach(demo.offlineWorkStore.electricalSafetyItems) { item in
            if let electrical = item.payload.electricalSafety {
                Button {
                    demo.openElectricalSafetyDraft(item.id)
                } label: {
                    HStack(spacing: 15) {
                        Image(systemName: "bolt.fill")
                            .font(.body.weight(.semibold))
                            .foregroundStyle(FacilityTheme.orange)
                            .frame(width: 44, height: 44)
                            .background(FacilityTheme.orange.opacity(0.12), in: RoundedRectangle(cornerRadius: 13, style: .continuous))
                        VStack(alignment: .leading, spacing: 4) {
                            Text("forms.electrical.title")
                                .font(.headline)
                                .foregroundStyle(FacilityTheme.ink)
                            if let context = electrical.context {
                                Text("\(context.businessEntityTitle) · \(context.buildingTitle)")
                                    .font(.subheadline)
                                    .foregroundStyle(.secondary)
                            }
                            Text(electrical.workDescription)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                        }
                        Spacer()
                        VStack(alignment: .trailing, spacing: 6) {
                            OfflineStatusPill(status: item.status)
                            Text(item.updatedAt, format: .dateTime.day().month().year().hour().minute())
                                .font(.caption2)
                                .foregroundStyle(.tertiary)
                        }
                    }
                    .padding(17)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .facilityCard(padding: 0)
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
}

private struct SavedNotificationRow: View {
    let item: OfflineWorkItem
    let review: NotificationReviewDraftPayload
    let action: () -> Void

    private var title: String {
        let savedTitle = review.notificationSnapshot?.title.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return savedTitle.isEmpty ? String(localized: "drafts.notification.title") : savedTitle
    }

    private var technicalPlace: String? {
        guard let snapshot = review.notificationSnapshot else { return nil }
        let values = [snapshot.functionalLocationID, snapshot.functionalLocationName]
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        guard !values.isEmpty else { return nil }
        return values.joined(separator: " · ")
    }

    private var equipment: String? {
        guard let value = review.notificationSnapshot?.equipmentID.trimmingCharacters(in: .whitespacesAndNewlines),
              !value.isEmpty else { return nil }
        return value
    }

    private var dateRange: String? {
        guard let snapshot = review.notificationSnapshot else { return nil }
        let start = snapshot.startDate.trimmingCharacters(in: .whitespacesAndNewlines)
        let end = snapshot.endDate.trimmingCharacters(in: .whitespacesAndNewlines)
        switch (start.isEmpty, end.isEmpty) {
        case (true, true): return nil
        case (false, true): return start
        case (true, false): return end
        case (false, false) where start == end: return start
        case (false, false): return "\(start) – \(end)"
        }
    }

    var body: some View {
        Button(action: action) {
            HStack(alignment: .center, spacing: 15) {
                Image(systemName: "checklist")
                    .font(.body.weight(.semibold))
                    .foregroundStyle(FacilityTheme.blue)
                    .frame(width: 44, height: 44)
                    .background(FacilityTheme.blue.opacity(0.12), in: RoundedRectangle(cornerRadius: 13, style: .continuous))

                VStack(alignment: .leading, spacing: 4) {
                    Text(title)
                        .font(.headline)
                        .foregroundStyle(FacilityTheme.ink)
                    Text(review.notificationID)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                    if let technicalPlace {
                        Label(technicalPlace, systemImage: "mappin.and.ellipse")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                    if equipment != nil || dateRange != nil {
                        HStack(spacing: 14) {
                            if let equipment {
                                Label(equipment, systemImage: "wrench.and.screwdriver")
                            }
                            if let dateRange {
                                Label(dateRange, systemImage: "calendar")
                            }
                        }
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                    }
                    Text("\(review.results.count) \(String(localized: "drafts.notification.checks"))")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Spacer(minLength: 12)

                VStack(alignment: .trailing, spacing: 6) {
                    if review.isClosedLocally {
                        StatusPill(status: .closedLocally)
                    } else {
                        OfflineStatusPill(status: item.status)
                    }
                    Text(item.updatedAt, format: .dateTime.day().month().year().hour().minute())
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                    if let syncError = item.syncError, !syncError.isEmpty {
                        Label(syncError, systemImage: "exclamationmark.circle")
                            .font(.caption2)
                            .foregroundStyle(FacilityTheme.red)
                            .lineLimit(2)
                            .multilineTextAlignment(.trailing)
                            .frame(maxWidth: 190, alignment: .trailing)
                    }
                }
            }
            .padding(17)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityHint(Text("drafts.accessibility.openNotification"))
        .facilityCard(padding: 0)
    }
}
