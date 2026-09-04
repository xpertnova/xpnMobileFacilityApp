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
            .animation(defectContentAnimation, value: demo.offlineWorkStore.defectItems)
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
            demo.openManualDefect()
        } label: {
            Label("defects.capture", systemImage: "plus")
        }
        .buttonStyle(.borderedProminent)
        .tint(FacilityTheme.accent)
    }

    @ViewBuilder
    private var defectContent: some View {
        if demo.offlineWorkStore.closedDefectNotificationItems.isEmpty
            && demo.offlineWorkStore.defectItems.isEmpty {
            EmptyDemoState(
                symbol: "checkmark.circle",
                titleKey: "defects.empty.title",
                subtitleKey: "defects.empty.subtitle"
            )
        } else {
            LazyVStack(spacing: 12) {
                ForEach(demo.offlineWorkStore.defectItems) { item in
                    if let defect = item.payload.defect {
                        ManualDefectCard(item: item, defect: defect) {
                            demo.openManualDefect(item.id)
                        }
                    }
                }
                ForEach(demo.offlineWorkStore.closedDefectNotificationItems) { item in
                    if let review = item.payload.notificationReview {
                        ClosedDefectNotificationCard(item: item, review: review) {
                            open(review)
                        }
                        .transition(.opacity.combined(with: .scale(scale: 0.94, anchor: .topLeading)))
                    }
                }
            }
            .frame(maxWidth: .infinity)
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

private struct ManualDefectCard: View {
    let item: OfflineWorkItem
    let defect: DefectDraftPayload
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 16) {
                DefectPhotoTile(photoCount: defect.attachmentIDs.count)
                VStack(alignment: .leading, spacing: 5) {
                    Text(defect.shortText)
                        .font(.headline)
                        .foregroundStyle(FacilityTheme.ink)
                    Text("\(defect.technicalObject.objectID) · \(defect.technicalObjectName)")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                    Text(item.updatedAt, format: .dateTime.day().month(.twoDigits).year())
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer(minLength: 12)
                HStack(spacing: 8) {
                    if let din = defect.dinGroup {
                        FacilityTemplateBadge(text: "KG \(din)", style: .open)
                    }
                    FacilityTemplateBadge(
                        localized: .init(defect.priority.titleKey),
                        style: defect.priority == .high ? .attention : .temporarilySaved
                    )
                    FacilityTemplateBadge(
                        localized: .init(item.status.titleKey),
                        style: item.status == .draft ? .temporarilySaved : .open
                    )
                }
                .fixedSize(horizontal: true, vertical: false)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .facilityCard()
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

    private var technicalPlace: String {
        guard let snapshot = review.notificationSnapshot else { return review.notificationID }
        return snapshot.functionalLocationID.isEmpty ? snapshot.functionalLocationName : snapshot.functionalLocationID
    }

    var body: some View {
        Button(action: action) {
            HStack(alignment: .center, spacing: 16) {
                DefectPhotoTile(photoCount: review.photoItemIDs.count)

                VStack(alignment: .leading, spacing: 5) {
                    Text(title)
                        .font(.headline)
                        .foregroundStyle(FacilityTheme.ink)
                        .lineLimit(2)

                    ViewThatFits(in: .horizontal) {
                        HStack(spacing: 14) {
                            notificationMetadata
                            technicalPlaceMetadata
                            updatedAtMetadata
                        }

                        VStack(alignment: .leading, spacing: 2) {
                            HStack(spacing: 14) {
                                notificationMetadata
                                technicalPlaceMetadata
                            }
                            updatedAtMetadata
                        }
                    }
                }

                Spacer(minLength: 12)

                HStack(spacing: 8) {
                    FacilityTemplateBadge(
                        localized: .init(WorkStatus.attention.titleKey),
                        style: .attention
                    )
                    FacilityTemplateBadge(
                        localized: .init(WorkStatus.closedLocally.titleKey),
                        style: .complete
                    )
                }
                .fixedSize(horizontal: true, vertical: false)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityHint(Text("drafts.accessibility.openNotification"))
        .facilityCard()
    }

    private var notificationMetadata: some View {
        Text(review.notificationID)
            .font(.subheadline)
            .foregroundStyle(.secondary)
            .lineLimit(1)
    }

    private var technicalPlaceMetadata: some View {
        Text(technicalPlace)
            .font(.subheadline.monospaced())
            .foregroundStyle(.secondary)
            .lineLimit(1)
    }

    private var updatedAtMetadata: some View {
        Text(item.updatedAt, format: .dateTime.day().month(.twoDigits).year())
            .font(.subheadline)
            .foregroundStyle(.secondary)
            .lineLimit(1)
    }
}

private struct DefectPhotoTile: View {
    let photoCount: Int

    var body: some View {
        Text("📷")
            .font(.title3)
            .frame(width: 52, height: 52)
            .background(
                LinearGradient(
                    colors: [
                        Color(red: 201 / 255, green: 214 / 255, blue: 226 / 255),
                        Color(red: 143 / 255, green: 168 / 255, blue: 189 / 255)
                    ],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                ),
                in: RoundedRectangle(cornerRadius: 12, style: .continuous)
            )
            .overlay(alignment: .topTrailing) {
                if photoCount > 0 {
                    Text(photoCount, format: .number)
                        .font(.caption2.weight(.bold))
                        .foregroundStyle(.white)
                        .frame(minWidth: 20, minHeight: 20)
                        .background(FacilityTheme.accent, in: Circle())
                        .offset(x: 6, y: -6)
                }
            }
            .accessibilityHidden(true)
    }
}
