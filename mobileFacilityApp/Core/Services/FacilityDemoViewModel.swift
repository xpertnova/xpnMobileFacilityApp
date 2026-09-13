import Foundation
import Observation

@MainActor
@Observable
final class FacilityDemoViewModel {
    let isDemoMode: Bool
    let offlineWorkStore: OfflineWorkStore
    let sapDataStore: SAPDataStore
    let technicalPlacesStore: TechnicalPlacesViewModel
    let meterReferenceProvider: any MeterReferenceProviding
    let photoAttachmentStore: any PhotoAttachmentStore
    let mobileLadderCreationProvider: any MobileLadderCreationProviding
    let workerDisplayName: String
    let workerRole: FacilityUserRole
    private(set) var profileSettingsReturnDestination: AppDestination = .overview
    var selection: AppDestination = .overview {
        didSet {
            if oldValue != .profileSettings && selection == .profileSettings {
                profileSettingsReturnDestination = oldValue
            }
        }
    }
    var isSidebarExpanded = true
    var manualCaptureRoute: ManualCaptureRoute = .landing
    var technicalPlacesRoute: TechnicalPlacesRoute = .hierarchy
    var selectedBriefingDraftID: UUID?
    var selectedElectricalSafetyDraftID: UUID?
    var selectedProofOfQualificationDraftID: UUID?
    var selectedNotificationID: String?
    var selectedOfflineNotificationDetail: SAPNotificationDetail?
    private var offlineNotificationReturnDestination: AppDestination?
    private var manualDefectReturnDestination: AppDestination?
    var shouldPresentSAPRefresh = false
    var shouldPresentDraftWarningBeforeSync = false
    var notifications = MockFacilityData.notifications
    var defects = MockFacilityData.defects
    let forms = MockFacilityData.forms

    var offlineNotificationDetailReturnDestination: AppDestination {
        offlineNotificationReturnDestination ?? .notifications
    }

    init(
        isDemoMode: Bool,
        offlineWorkStore: OfflineWorkStore,
        sapDataStore: SAPDataStore,
        meterReferenceProvider: any MeterReferenceProviding,
        photoAttachmentStore: any PhotoAttachmentStore,
        mobileLadderCreationProvider: (any MobileLadderCreationProviding)? = nil,
        workerDisplayName: String = "Alex Morgan",
        workerRole: FacilityUserRole = .technician
    ) {
        self.isDemoMode = isDemoMode
        self.offlineWorkStore = offlineWorkStore
        self.sapDataStore = sapDataStore
        self.meterReferenceProvider = meterReferenceProvider
        self.photoAttachmentStore = photoAttachmentStore
        if let mobileLadderCreationProvider {
            self.mobileLadderCreationProvider = mobileLadderCreationProvider
        } else if isDemoMode {
            self.mobileLadderCreationProvider = DemoMobileLadderCreationProvider()
        } else {
            self.mobileLadderCreationProvider = sapDataStore
        }
        self.technicalPlacesStore = TechnicalPlacesViewModel(
            sapDataStore: sapDataStore,
            offlineWorkStore: offlineWorkStore
        )
        self.workerDisplayName = workerDisplayName
        self.workerRole = workerRole
    }

    var selectedNotification: MaintenanceNotification? {
        visibleNotifications.first { $0.id == selectedNotificationID }
    }

    var selectedSAPNotification: SAPNotificationSummary? {
        guard !isDemoMode, let selectedNotificationID else { return nil }
        return sapDataStore.notifications.first { $0.id == selectedNotificationID }
    }

    var openNotifications: Int {
        visibleNotifications.filter { $0.status == .open || $0.status == .attention }.count
    }

    var allNotificationCount: Int {
        isDemoMode ? notifications.count : sapDataStore.totalNotificationCount
    }

    var visibleNotifications: [MaintenanceNotification] {
        guard !isDemoMode else { return notifications }
        return sapDataStore.notifications.map { notification in
            let review = locallySavedNotificationReview(for: notification.id)
            let isClosedLocally = review?.isClosedLocally == true
            let hasLocalDefect = review?.results.values.contains(.yes) == true
            return MaintenanceNotification(
                id: notification.id,
                title: notification.title.isEmpty ? notification.id : notification.title,
                location: notification.displayLocation,
                dueDate: notification.displayDateRange,
                equipment: notification.functionalLocationID,
                sapStatus: notification.displayStatus,
                status: isClosedLocally ? .closedLocally : (review == nil ? .open : .draft),
                completedChecks: 0,
                totalChecks: 0,
                isTemporarilySaved: review != nil && !isClosedLocally,
                isClosedLocally: isClosedLocally,
                hasLocalDefect: hasLocalDefect,
                structuralFilterMetadata: notification.structuralFilterMetadata
            )
        }
    }

    var notificationFilterMetadata: [NotificationStructuralFilterMetadata] {
        isDemoMode
            ? notifications.compactMap(\.structuralFilterMetadata)
            : sapDataStore.notificationFilterMetadata
    }

    private func locallySavedNotificationReview(for notificationID: String) -> NotificationReviewDraftPayload? {
        offlineWorkStore.items.first {
            $0.type == .notificationReview && $0.status != .synchronized &&
            $0.payload.notificationReview?.notificationID == notificationID
        }?.payload.notificationReview
    }

    var effectiveWorkerDisplayName: String {
        let sapDisplayName = sapDataStore.workerProfile?.displayName ?? ""
        return sapDisplayName.isEmpty ? workerDisplayName : sapDisplayName
    }

    var workerInitials: String {
        effectiveWorkerDisplayName
            .split(separator: " ")
            .prefix(2)
            .compactMap(\.first)
            .map(String.init)
            .joined()
            .uppercased()
    }

    func open(_ destination: AppDestination) {
        if destination == .profileSettings {
            openProfileSettings()
            return
        }
        selection = destination
    }

    func openProfileSettings() {
        if selection != .profileSettings {
            profileSettingsReturnDestination = selection
        }
        selectedOfflineNotificationDetail = nil
        selection = .profileSettings
    }

    func closeProfileSettings() {
        let returnDestination = profileSettingsReturnDestination
        selection = returnDestination
    }

    func openManualDefect(_ itemID: UUID? = nil) {
        if selection != .manualCapture {
            manualDefectReturnDestination = selection
        }
        manualCaptureRoute = .defect(itemID)
        selection = .manualCapture
    }

    func closeManualDefect() {
        let returnDestination = manualDefectReturnDestination
        manualDefectReturnDestination = nil
        if let returnDestination {
            selection = returnDestination
        }
        manualCaptureRoute = .landing
    }

    func openManualCapture() {
        manualCaptureRoute = .landing
        selection = .manualCapture
    }

    func openMeterReading(_ itemID: UUID? = nil) {
        manualCaptureRoute = .meterReading(itemID)
        selection = .manualCapture
    }

    func openMobileLadder(_ itemID: UUID? = nil) {
        technicalPlacesRoute = itemID.map(TechnicalPlacesRoute.mobileLadderDraft) ?? .createMobileLadder
        selection = .technicalPlaces
    }

    func closeMobileLadder() {
        technicalPlacesRoute = .hierarchy
    }

    func openBriefingDraft(_ itemID: UUID) {
        selectedBriefingDraftID = itemID
        selection = .forms
    }

    func openElectricalSafetyDraft(_ itemID: UUID) {
        guard !isDemoMode else { return }
        selectedElectricalSafetyDraftID = itemID
        selection = .forms
    }

    func openProofOfQualificationDraft(_ itemID: UUID) {
        selectedProofOfQualificationDraftID = itemID
        selection = .forms
    }

    /// New saved reviews carry their own snapshot and therefore reopen without
    /// a live connection or a matching record in the current SAP cache.
    func openSavedNotificationReview(_ review: NotificationReviewDraftPayload) async -> Bool {
        let returnDestination = selection
        if let snapshot = review.notificationSnapshot {
            selectedNotificationID = nil
            selectedOfflineNotificationDetail = SAPNotificationDetail(
                offlineSnapshot: snapshot,
                notificationID: review.notificationID
            )
            offlineNotificationReturnDestination = returnDestination
            return true
        }

        // Backward compatibility for drafts stored before local snapshots were
        // introduced. They remain available if the original cache still has
        // their source notification.
        let cachedSummary: SAPNotificationSummary?
        if isDemoMode {
            cachedSummary = nil
        } else {
            cachedSummary = await sapDataStore.cachedNotification(id: review.notificationID)
        }
        guard let cachedSummary else { return false }

        selectedNotificationID = nil
        selectedOfflineNotificationDetail = SAPNotificationDetail(summary: cachedSummary)
        offlineNotificationReturnDestination = returnDestination
        return true
    }

    /// Saved reviews are presented over their source screen and return there
    /// when the user closes the detail.
    func dismissOfflineNotificationDetail() {
        selectedOfflineNotificationDetail = nil
        let returnDestination = offlineNotificationReturnDestination ?? .notifications
        offlineNotificationReturnDestination = nil
        selection = returnDestination
    }

    func requestSAPRefresh() {
        guard !isDemoMode, sapDataStore.isRefreshAvailable, !sapDataStore.isRefreshing else { return }
        sapDataStore.dismissError()
        proceedWithSAPRefresh()
    }

    func confirmDiscardDraftsAndSync() {
        shouldPresentDraftWarningBeforeSync = false
        proceedWithSAPRefresh()
    }

    func dismissDraftWarning() {
        shouldPresentDraftWarningBeforeSync = false
    }

    func keepDraftsAndNavigate() {
        shouldPresentDraftWarningBeforeSync = false
        open(.drafts)
    }

    private func proceedWithSAPRefresh() {
        guard !isDemoMode, sapDataStore.isRefreshAvailable, !sapDataStore.isRefreshing else { return }
        sapDataStore.dismissError()
        if sapDataStore.hasValidSavedToken {
            _ = sapDataStore.beginTokenRefresh()
            shouldPresentSAPRefresh = true
            Task {
                let success = await sapDataStore.refreshWithSavedToken()
                if success {
                    await offlineWorkStore.load()
                    shouldPresentSAPRefresh = false
                }
            }
        } else {
            shouldPresentSAPRefresh = true
        }
    }

    func finishChecks(for notification: MaintenanceNotification) {
        guard isDemoMode else { return }
        guard let index = notifications.firstIndex(where: { $0.id == notification.id }) else { return }
        notifications[index].completedChecks = notifications[index].totalChecks
        notifications[index].status = .draft
    }

    func resetDemo() {
        NotificationStructuralFilterPreferences.reset(
            workerID: sapDataStore.localWorkerID,
            isDemoMode: true
        )
        notifications = MockFacilityData.notifications
        defects = MockFacilityData.defects
        manualCaptureRoute = .landing
        technicalPlacesRoute = .hierarchy
        selectedBriefingDraftID = nil
        selectedElectricalSafetyDraftID = nil
        selectedProofOfQualificationDraftID = nil
        selectedNotificationID = nil
        selectedOfflineNotificationDetail = nil
        offlineNotificationReturnDestination = nil
        profileSettingsReturnDestination = .overview
        technicalPlacesStore.reset()
        Task {
            await offlineWorkStore.reset()
            try? await photoAttachmentStore.reset()
        }
        selection = .overview
    }
}

private enum MockFacilityData {
    static let notifications: [MaintenanceNotification] = [
        .init(id: "M-31042", title: "Fire door inspection", location: "Building A · Level 02", dueDate: "Today", equipment: "Door group A2", sapStatus: nil, status: .open, completedChecks: 1, totalChecks: 6, structuralFilterMetadata: .init(countryCode: "DE", locationCode: "ESS", businessEntityCode: "11248", buildingCode: "A", tradeCode: "FM", formCode: "TFM3", functionalLocationName: "Building A")),
        .init(id: "M-31057", title: "Emergency lighting test", location: "Building C · Level 01", dueDate: "Today", equipment: "Lighting circuit C-11", sapStatus: nil, status: .attention, completedChecks: 3, totalChecks: 8, structuralFilterMetadata: .init(countryCode: "DE", locationCode: "ESS", businessEntityCode: "11248", buildingCode: "C", tradeCode: "EL", formCode: "TFM7", functionalLocationName: "Building C")),
        .init(id: "M-30987", title: "Ventilation filter check", location: "Building B · Roof plant", dueDate: "Tomorrow", equipment: "AHU-03", sapStatus: nil, status: .open, completedChecks: 0, totalChecks: 5, structuralFilterMetadata: .init(countryCode: "DE", locationCode: "ESS", businessEntityCode: "11248", buildingCode: "B", tradeCode: "FM", formCode: "TFM1", functionalLocationName: "Building B")),
        .init(id: "M-30965", title: "Water meter reading", location: "Utility room · Level -1", dueDate: "29 Aug", equipment: "WM-120", sapStatus: nil, status: .pending, completedChecks: 4, totalChecks: 4, structuralFilterMetadata: .init(countryCode: "DE", locationCode: "ESS", businessEntityCode: "11248", buildingCode: "U", tradeCode: "UTIL", formCode: "TFM1", functionalLocationName: "Utility room"))
    ]

    static let defects: [Defect] = [
        .init(id: "D-0284", title: "Emergency exit sign dim", location: "Building C · Corridor 1.04", reportedAt: "Today, 08:45", severity: .attention, description: "Illumination is below the visual inspection threshold."),
        .init(id: "D-0279", title: "Door closer requires adjustment", location: "Building A · Door A2-16", reportedAt: "Yesterday", severity: .pending, description: "Door does not close fully without manual support."),
        .init(id: "D-0274", title: "Filter replacement due", location: "Building B · AHU-03", reportedAt: "27 Aug", severity: .draft, description: "Filter service record prepared for the next maintenance window.")
    ]

    static let forms: [FacilityForm] = [
        .init(
            id: "briefing",
            titleKey: "forms.briefing.title",
            subtitleKey: "forms.briefing.subtitle",
            coverageKeys: ["forms.briefing.coverage.context", "forms.briefing.coverage.checklist", "forms.briefing.coverage.signatures"],
            symbol: "figure.stand",
            tint: "blue"
        ),
        .init(
            id: "fire",
            titleKey: "forms.fire.title",
            subtitleKey: "forms.fire.subtitle",
            coverageKeys: ["forms.fire.coverage.work", "forms.fire.coverage.measures", "forms.fire.coverage.signatures"],
            symbol: "flame",
            tint: "red"
        ),
        .init(
            id: "electrical",
            titleKey: "forms.electrical.title",
            subtitleKey: "forms.electrical.subtitle",
            coverageKeys: ["forms.electrical.coverage.work", "forms.electrical.coverage.handover", "forms.electrical.coverage.signatures"],
            symbol: "bolt",
            tint: "orange"
        ),
        .init(
            id: "qualification",
            titleKey: "forms.qualification.title",
            subtitleKey: "forms.qualification.subtitle",
            coverageKeys: ["forms.qualification.coverage.context", "forms.qualification.coverage.checklist", "forms.qualification.coverage.signatures"],
            symbol: "checkmark.seal",
            tint: "green"
        )
    ]
}
