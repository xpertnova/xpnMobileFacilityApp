import SwiftUI

struct DraftsView: View {
    let demo: FacilityDemoViewModel
    @Environment(\.accessibilityReduceMotion) private var accessibilityReduceMotion
    @State private var showsUnavailableNotificationAlert = false
    @State private var photoWorkspaceScope: LocalPhotoScope?

    var body: some View {
        ZStack {
            if let photoWorkspaceScope {
                LocalPhotoWorkspace(
                    scope: photoWorkspaceScope,
                    offlineWorkStore: demo.offlineWorkStore,
                    photoStore: demo.photoAttachmentStore,
                    close: { self.photoWorkspaceScope = nil }
                )
                .transition(PhotoWorkspaceMotion.destination)
                .zIndex(1)
            } else {
                ScrollView {
                    VStack(alignment: .leading, spacing: 20) {
                PageHeader(
                    "drafts.title",
                    subtitle: "drafts.subtitle",
                    trailing: AnyView(syncControl)
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
                        && demo.offlineWorkStore.electricalSafetyItems.isEmpty
                        && demo.offlineWorkStore.defectItems.isEmpty
                        && demo.offlineWorkStore.meterReadingItems.isEmpty
                        && demo.offlineWorkStore.technicalObjectEditItems.isEmpty
                        && demo.offlineWorkStore.proofOfQualificationItems.isEmpty
                        && demo.offlineWorkStore.firePermitItems.isEmpty
                        && demo.offlineWorkStore.mobileLadderItems.isEmpty
                        && demo.offlineWorkStore.subdistributionItems.isEmpty
                        && demo.offlineWorkStore.photoCollectionItems.isEmpty {
                        emptyState
                    } else {
                        savedWorkList
                    }
                }

                if demo.isDemoMode {
                    Label("drafts.demoNotice", systemImage: "info.circle")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                    }
                    .facilityPageContent()
                }
                .transition(PhotoWorkspaceMotion.source)
            }
        }
        .animation(
            accessibilityReduceMotion ? nil : PhotoWorkspaceMotion.navigation,
            value: photoWorkspaceScope
        )
        .task {
            await demo.offlineWorkStore.load()
        }
        .alert("drafts.notification.unavailable.title", isPresented: $showsUnavailableNotificationAlert) {
            Button("common.ok", role: .cancel) { }
        } message: {
            Text("drafts.notification.unavailable.message")
        }
    }

    private var syncControl: some View {
        Button {
            demo.requestSAPRefresh()
        } label: {
            Label("drafts.sync.action", systemImage: "arrow.triangle.2.circlepath")
        }
        .buttonStyle(.borderedProminent)
        .tint(FacilityTheme.navy)
        .disabled(!demo.canSync)
    }

    private var emptyState: some View {
        EmptyDemoState(
            symbol: "checkmark.circle",
            titleKey: "drafts.empty.title",
            subtitleKey: "drafts.empty.subtitle"
        )
    }

    private var savedWorkList: some View {
        LazyVStack(spacing: 12) {
            savedNotificationRows
            savedMobileLadderRows
            savedSubdistributionRows
            savedDefectRows
            savedMeterReadingRows
            savedBriefingRows
            savedElectricalSafetyRows
            savedFirePermitRows
            savedTechnicalObjectEditList
            savedProofOfQualificationList
            savedPhotoCollections
        }
        .frame(maxWidth: .infinity)
    }

    @ViewBuilder
    private var savedMobileLadderRows: some View {
        ForEach(demo.offlineWorkStore.mobileLadderItems) { item in
            if let ladder = item.payload.mobileLadder {
                LocalWorkTemplateRow(
                    icon: "🪜",
                    title: Text(ladder.designation.isEmpty ? String(localized: "mobileLadder.title", bundle: .appLanguage) : ladder.designation),
                    subtitle: Text(ladder.context?.legacyContext.functionalLocation ?? String(localized: "mobileLadder.address.notSelected", bundle: .appLanguage)),
                    status: demo.isDemoMode ? .demoLocal : .offline(item.status),
                    syncError: item.syncError,
                    action: { demo.openMobileLadder(item.id) }
                )
            }
        }
    }

    @ViewBuilder
    private var savedSubdistributionRows: some View {
        ForEach(demo.offlineWorkStore.subdistributionItems) { item in
            if let subdistribution = item.payload.subdistribution {
                let name = subdistribution.characteristicValues["TFMUNTERVERT_BEZUNTERVERT"]
                    ?? subdistribution.characteristicValues["TFMSCHUTZSCH_UNTERVERTEILUNG"]
                    ?? ""
                LocalWorkTemplateRow(
                    icon: "⚡",
                    title: Text(name.isEmpty ? String(localized: "subdistribution.title", bundle: .appLanguage) : name),
                    subtitle: Text(subdistribution.context?.legacyContext.functionalLocation ?? String(localized: "subdistribution.context.notSelected", bundle: .appLanguage)),
                    status: demo.isDemoMode ? .demoLocal : .offline(item.status),
                    syncError: item.syncError,
                    action: { demo.openSubdistribution(item.id) }
                )
            }
        }
    }

    @ViewBuilder
    private var savedPhotoCollections: some View {
        ForEach(demo.offlineWorkStore.photoCollectionItems.filter {
            let workflow = $0.payload.photoCollection?.scope.workflow
            return workflow != .mobileLadder && workflow != .subdistribution
        }) { item in
            if let collection = item.payload.photoCollection, !collection.attachments.isEmpty {
                LocalWorkTemplateRow(
                    icon: "📷",
                    title: Text(collection.scope.localizedTitle.isEmpty
                        ? String(localized: "photos.workspace.title", bundle: .appLanguage)
                        : collection.scope.localizedTitle),
                    subtitle: Text(photoCollectionSubtitle(collection)),
                    status: demo.isDemoMode ? .demoLocal : .offline(.draft),
                    syncError: nil,
                    action: { photoWorkspaceScope = collection.scope }
                )
            }
        }
    }

    private func photoCollectionSubtitle(_ collection: PhotoCollectionDraftPayload) -> String {
        let count = String(format: String(localized: "photos.workspace.count", bundle: .appLanguage), collection.attachments.count)
        return [collection.scope.localizedSubtitle, count]
            .filter { !$0.isEmpty }
            .joined(separator: " · ")
    }

    @ViewBuilder
    private var savedDefectRows: some View {
        ForEach(demo.offlineWorkStore.defectItems) { item in
            if let defect = item.payload.defect {
                LocalWorkTemplateRow(
                    icon: "⚠️",
                    title: Text(defect.shortText),
                    subtitle: Text("\(defect.technicalObject.objectID) · \(defect.technicalObjectName)"),
                    status: .for(item),
                    syncError: item.syncError,
                    action: { demo.openManualDefect(item.id) }
                )
            }
        }
    }

    @ViewBuilder
    private var savedMeterReadingRows: some View {
        ForEach(demo.offlineWorkStore.meterReadingItems) { item in
            if let reading = item.payload.meterReading {
                LocalWorkTemplateRow(
                    icon: reading.meter.kind == .electricity ? "⚡" : (reading.meter.kind == .gas ? "🔥" : "💧"),
                    title: Text("manual.localWork.meter.title"),
                    subtitle: Text("\(reading.meter.id) · \(MeterReadingViewModel.displayString(reading.value)) \(reading.meter.unit)"),
                    status: demo.isDemoMode ? .demoLocal : .for(item),
                    syncError: item.syncError,
                    action: { demo.openMeterReading(item.id) }
                )
            }
        }
    }

    @ViewBuilder
    private var savedNotificationRows: some View {
            ForEach(demo.offlineWorkStore.localWorkNotificationItems) { item in
                if let review = item.payload.notificationReview {
                    SavedNotificationRow(item: item, review: review) {
                        open(review)
                    }
                } else if let inspection = item.payload.elevatorInspection {
                    SavedEquipmentInspectionRow(item: item, inspection: inspection) {
                        open(inspection)
                    }
                }
            }
    }

    @ViewBuilder
    private var savedBriefingRows: some View {
        ForEach(demo.offlineWorkStore.briefingItems) { item in
            if let briefing = item.payload.briefing {
                LocalWorkTemplateRow(
                    icon: "📄",
                    title: Text("forms.briefing.title"),
                    subtitle: Text("\(briefing.businessEntityTitle) · \(briefing.buildingTitle)"),
                    status: .offline(item.status),
                    syncError: item.syncError,
                    action: { demo.openBriefingDraft(item.id) }
                )
            }
        }
    }

    @ViewBuilder
    private var savedElectricalSafetyRows: some View {
        ForEach(demo.offlineWorkStore.electricalSafetyItems) { item in
            if let electrical = item.payload.electricalSafety {
                LocalWorkTemplateRow(
                    icon: "⚡",
                    title: Text("forms.electrical.title"),
                    subtitle: Text(electrical.context.map { "\($0.businessEntityTitle) · \($0.buildingTitle)" } ?? electrical.workDescription),
                    status: .offline(item.status),
                    syncError: item.syncError,
                    action: { demo.openElectricalSafetyDraft(item.id) }
                )
            }
        }
    }

    /// A closed fire permit only waits for SAP; it is not reopened.
    @ViewBuilder
    private var savedFirePermitRows: some View {
        ForEach(demo.offlineWorkStore.firePermitItems) { item in
            if let firePermit = item.payload.firePermit {
                LocalWorkTemplateRow(
                    icon: "🔥",
                    title: Text("forms.fire.title"),
                    subtitle: Text(firePermit.context.map { "\($0.businessEntityTitle) · \($0.buildingTitle)" } ?? firePermit.workDescription),
                    status: .offline(item.status),
                    syncError: item.syncError,
                    action: nil
                )
            }
        }
    }

    @ViewBuilder
    private var savedTechnicalObjectEditList: some View {
        ForEach(demo.offlineWorkStore.technicalObjectEditItems) { item in
            if let edit = item.payload.technicalObjectEdit {
                Button {
                    demo.open(.technicalPlaces)
                    Task {
                        await demo.technicalPlacesStore.open(
                            .init(kind: .equipment, objectID: edit.equipmentID)
                        )
                    }
                } label: {
                    HStack(spacing: 15) {
                        Image(systemName: "gearshape.2.fill")
                            .foregroundStyle(FacilityTheme.orange)
                            .frame(width: 44, height: 44)
                            .background(FacilityTheme.orange.opacity(0.12), in: RoundedRectangle(cornerRadius: 13))
                        VStack(alignment: .leading, spacing: 4) {
                            Text("drafts.technicalEdit.title").font(.headline).foregroundStyle(FacilityTheme.ink)
                            Text(edit.designation.isEmpty ? edit.equipmentID : edit.designation).font(.subheadline).foregroundStyle(.secondary)
                            Text("\(edit.equipmentID) · \(edit.functionalLocationID)").font(.caption.monospaced()).foregroundStyle(.secondary).lineLimit(1)
                        }
                        Spacer()
                        if item.type.staysLocal, item.status != .draft {
                            FacilityTemplateBadge(localized: .init(item.statusTitleKey), style: .temporarilySaved)
                        } else {
                            OfflineStatusPill(status: item.status)
                        }
                    }.padding(17).contentShape(Rectangle())
                }.buttonStyle(.plain).facilityCard(padding: 0)
            }
        }
    }

    @ViewBuilder
    private var savedProofOfQualificationList: some View {
        ForEach(demo.offlineWorkStore.proofOfQualificationItems) { item in
            if let qualification = item.payload.proofOfQualification {
                LocalWorkTemplateRow(
                    icon: "📄",
                    title: Text("forms.qualification.title"),
                    subtitle: Text(qualification.workLocation),
                    status: .offline(item.status),
                    syncError: item.syncError,
                    action: { demo.openProofOfQualificationDraft(item.id) }
                )
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

    private func open(_ inspection: ElevatorInspectionDraftPayload) {
        Task {
            guard await demo.openSavedElevatorInspection(inspection) else {
                showsUnavailableNotificationAlert = true
                return
            }
        }
    }
}

/// Saved TFM2/TFM4/TFM6/TFM8 equipment inspection.
private struct SavedEquipmentInspectionRow: View {
    let item: OfflineWorkItem
    let inspection: ElevatorInspectionDraftPayload
    let action: () -> Void

    private var title: String {
        let savedTitle = inspection.notificationSnapshot?.title.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return savedTitle.isEmpty
            ? String(localized: String.LocalizationValue(inspection.form.titleKey), bundle: .appLanguage)
            : savedTitle
    }

    /// The stored report, offered only once the inspection is closed.
    private var report: FormReportPDFArtifact? {
        guard inspection.isClosedLocally else { return nil }
        return FormReportPDFArtifact(notificationID: inspection.notificationID, data: inspection.pdfBytes)
    }

    var body: some View {
        LocalWorkTemplateRow(
            icon: inspection.form.draftIcon,
            title: Text(title),
            subtitle: Text("\(inspection.notificationID) · \(inspection.elementValues.count) \(String(localized: "drafts.notification.checks", bundle: .appLanguage))"),
            status: inspection.isClosedLocally ? .closedLocally : .offline(item.status),
            syncError: item.syncError,
            report: report,
            action: action
        )
        .accessibilityHint(Text("drafts.accessibility.openNotification"))
    }
}

private struct SavedNotificationRow: View {
    let item: OfflineWorkItem
    let review: NotificationReviewDraftPayload
    let action: () -> Void

    private var title: String {
        let savedTitle = review.notificationSnapshot?.title.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return savedTitle.isEmpty ? String(localized: "drafts.notification.title", bundle: .appLanguage) : savedTitle
    }

    /// The stored report, offered only once the review is closed.
    private var report: FormReportPDFArtifact? {
        guard review.isClosedLocally else { return nil }
        return FormReportPDFArtifact(notificationID: review.notificationID, data: review.pdfData)
    }

    var body: some View {
        LocalWorkTemplateRow(
            icon: "📋",
            title: Text(title),
            subtitle: Text("\(review.notificationID) · \(review.results.count) \(String(localized: "drafts.notification.checks", bundle: .appLanguage))"),
            status: review.isClosedLocally ? .closedLocally : .offline(item.status),
            syncError: item.syncError,
            report: report,
            action: action
        )
        .accessibilityHint(Text("drafts.accessibility.openNotification"))
    }
}

private enum LocalWorkTemplateStatus {
    case offline(OfflineWorkStatus)
    case closedLocally
    case demoLocal
    /// Closed work that is not sent to SAP (`OfflineWorkType.staysLocal`).
    case localOnly

    static func `for`(_ item: OfflineWorkItem) -> Self {
        item.type.staysLocal && item.status != .draft ? .localOnly : .offline(item.status)
    }

    var titleKey: String {
        switch self {
        case let .offline(status): status.titleKey
        case .closedLocally: WorkStatus.closedLocally.titleKey
        case .demoLocal: "offline.status.demoLocal"
        case .localOnly: "offline.status.localOnly"
        }
    }

    var badgeStyle: FacilityTemplateBadgeStyle {
        switch self {
        case .closedLocally, .offline(.synchronized): .complete
        case .demoLocal: .open
        case .localOnly: .temporarilySaved
        case .offline(.failed), .offline(.conflict): .attention
        case .offline(.draft): .temporarilySaved
        case .offline(.pendingSynchronization), .offline(.synchronizing): .open
        }
    }
}

private struct LocalWorkTemplateRow: View {
    let icon: String
    let title: Text
    let subtitle: Text
    let status: LocalWorkTemplateStatus
    let syncError: String?
    /// Report of a closed notification; nil while it is still a draft.
    var report: FormReportPDFArtifact? = nil
    /// Nil for work that cannot be opened again once closed.
    let action: (() -> Void)?

    var body: some View {
        HStack(spacing: FormReportPaperclipButton.rowSpacing) {
            if let action {
                Button(action: action) { content }
                    .buttonStyle(.plain)
            } else {
                content
            }
            if let report {
                FormReportPaperclipButton(report: report)
            }
        }
        .facilityCard()
    }

    private var content: some View {
        HStack(alignment: .center, spacing: 16) {
            LocalWorkTemplateIcon(icon: icon)

            VStack(alignment: .leading, spacing: 4) {
                title
                    .font(.headline)
                    .foregroundStyle(FacilityTheme.ink)
                    .lineLimit(2)
                subtitle
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }

            Spacer(minLength: 12)

            VStack(alignment: .trailing, spacing: 6) {
                FacilityTemplateBadge(
                    localized: .init(status.titleKey),
                    style: status.badgeStyle
                )

                if let syncError, !syncError.isEmpty {
                    HStack(spacing: 4) {
                        Text("⚠")
                            .accessibilityHidden(true)
                        Text(syncError)
                    }
                    .font(.caption2)
                    .foregroundStyle(FacilityTheme.red)
                    .lineLimit(2)
                    .multilineTextAlignment(.trailing)
                    .frame(maxWidth: 190, alignment: .trailing)
                }
            }
            .fixedSize(horizontal: false, vertical: true)
        }
        .contentShape(Rectangle())
    }
}

private struct LocalWorkTemplateIcon: View {
    let icon: String

    var body: some View {
        Text(icon)
            .font(.title3)
            .frame(width: 44, height: 44)
            .background(
                Color(red: 1, green: 244 / 255, blue: 224 / 255),
                in: RoundedRectangle(cornerRadius: 13, style: .continuous)
            )
            .accessibilityHidden(true)
    }
}
