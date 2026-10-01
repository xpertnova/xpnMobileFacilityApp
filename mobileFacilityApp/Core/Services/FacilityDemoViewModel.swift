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
    let documentAttachmentStore: any DocumentAttachmentStore
    let mobileLadderCreationProvider: any MobileLadderCreationProviding
    let elevatorAssetDataProvider: any ElevatorAssetDataProviding
    let subdistributionCreationProvider: any SubdistributionCreationProviding
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
    var isBriefingValueHelpPresented = false
    var selectedElectricalSafetyDraftID: UUID?
    var selectedProofOfQualificationDraftID: UUID?
    /// Changes for every new detail presentation, even when the technician
    /// reopens the same notification. Detail views use it as their SwiftUI
    /// identity so one-time blocking warnings are evaluated again.
    private(set) var notificationDetailPresentationID = UUID()
    var selectedNotificationID: String? {
        didSet {
            if selectedNotificationID != nil {
                notificationDetailPresentationID = UUID()
            }
        }
    }
    var selectedOfflineNotificationDetail: SAPNotificationDetail? {
        didSet {
            if selectedOfflineNotificationDetail != nil {
                notificationDetailPresentationID = UUID()
            }
        }
    }
    private var offlineNotificationReturnDestination: AppDestination?
    private var manualDefectReturnDestination: AppDestination?
    /// Not observable: it is read once by the defect form's load task and
    /// cleared there, so it must not invalidate any view.
    @ObservationIgnored private var pendingDefectObject: DefectObjectOption?
    /// The building a creation form should open on, set when it is started
    /// from a technical place. Read once by that form's load task, like
    /// `pendingDefectObject`.
    var shouldPresentSAPRefresh = false
    /// Set while the worker confirms a synchronization that deletes local
    /// work, like the legacy `DialogBeforeSync`.
    var shouldConfirmSynchronization = false
    /// Set when the temporarily saved forms could not be deleted; the
    /// synchronization then does not start, as in the legacy app.
    var synchronizationCleanupFailed = false
    var notifications = MockFacilityData.notifications {
        didSet { demoNotificationRevision &+= 1 }
    }
    /// Demo rows are replaced in place (`resetDemo`). This is
    /// observable on purpose: a view that only reads the cached
    /// `visibleNotifications` still has to be told when they change.
    private(set) var demoNotificationRevision = 0
    var defects = MockFacilityData.defects
    let forms = MockFacilityData.forms
    @ObservationIgnored private var cachedVisibleNotifications: [MaintenanceNotification] = []
    @ObservationIgnored private var visibleNotificationsKey: VisibleNotificationsKey?
    @ObservationIgnored private var productionNotificationRows: [MaintenanceNotification] = []
    @ObservationIgnored private var productionNotificationRowsRevision = -1
    /// The dashboard counters the worker saw last time (production only).
    /// See `DashboardMetricsSnapshot`.
    private var savedDashboardMetrics: DashboardMetrics = .unknown

    var offlineNotificationDetailReturnDestination: AppDestination {
        offlineNotificationReturnDestination ?? .notifications
    }

    init(
        isDemoMode: Bool,
        offlineWorkStore: OfflineWorkStore,
        sapDataStore: SAPDataStore,
        meterReferenceProvider: any MeterReferenceProviding,
        photoAttachmentStore: any PhotoAttachmentStore,
        documentAttachmentStore: any DocumentAttachmentStore = InMemoryDocumentAttachmentStore(),
        mobileLadderCreationProvider: (any MobileLadderCreationProviding)? = nil,
        elevatorAssetDataProvider: (any ElevatorAssetDataProviding)? = nil,
        subdistributionCreationProvider: (any SubdistributionCreationProviding)? = nil,
        workerDisplayName: String = "Alex Morgan",
        workerRole: FacilityUserRole = .technician
    ) {
        self.isDemoMode = isDemoMode
        self.offlineWorkStore = offlineWorkStore
        self.sapDataStore = sapDataStore
        self.meterReferenceProvider = meterReferenceProvider
        self.photoAttachmentStore = photoAttachmentStore
        self.documentAttachmentStore = documentAttachmentStore
        if let mobileLadderCreationProvider {
            self.mobileLadderCreationProvider = mobileLadderCreationProvider
        } else if isDemoMode {
            self.mobileLadderCreationProvider = DemoMobileLadderCreationProvider()
        } else {
            self.mobileLadderCreationProvider = sapDataStore
        }
        if let elevatorAssetDataProvider {
            self.elevatorAssetDataProvider = elevatorAssetDataProvider
        } else if isDemoMode {
            self.elevatorAssetDataProvider = DemoElevatorAssetDataProvider()
        } else {
            self.elevatorAssetDataProvider = sapDataStore
        }

        if let subdistributionCreationProvider {
            self.subdistributionCreationProvider = subdistributionCreationProvider
        } else if isDemoMode {
            self.subdistributionCreationProvider = DemoSubdistributionCreationProvider()
        } else {
            self.subdistributionCreationProvider = sapDataStore
        }
        self.technicalPlacesStore = TechnicalPlacesViewModel(
            sapDataStore: sapDataStore,
            offlineWorkStore: offlineWorkStore
        )
        self.workerDisplayName = workerDisplayName
        self.workerRole = workerRole
        if !isDemoMode {
            savedDashboardMetrics = DashboardMetricsSnapshot.load(workerID: sapDataStore.localWorkerID)
        }
    }

    var selectedNotification: MaintenanceNotification? {
        guard let selectedNotificationID else { return nil }
        return visibleNotifications.first { $0.id == selectedNotificationID }
    }

    var selectedSAPNotification: SAPNotificationSummary? {
        guard let selectedNotificationID else { return nil }
        if isDemoMode {
            return MockFacilityData.sapNotifications.first { $0.id == selectedNotificationID }
        }
        return sapDataStore.notifications.first { $0.id == selectedNotificationID }
    }

    var selectedNotificationDetail: SAPNotificationDetail? {
        if isDemoMode {
            guard let selectedNotificationID else { return nil }
            return demoNotificationDetail(for: selectedNotificationID)
        } else {
            return selectedSAPNotification.map { SAPNotificationDetail(summary: $0) }
        }
    }

    /// The notification list and briefing value-help card handle their own
    /// keyboard overlap while the shell keeps its full-height layout.
    var suppressesKeyboardAvoidance: Bool {
        isBriefingValueHelpPresented || (selection == .notifications
            && selectedNotificationDetail == nil
            && selectedOfflineNotificationDetail == nil
            && !(!isDemoMode && shouldPresentSAPRefresh))
    }

    func demoNotificationDetail(for id: String) -> SAPNotificationDetail? {
        guard let notification = notifications.first(where: { $0.id == id }) else { return nil }
        if let summary = MockFacilityData.sapNotifications.first(where: { $0.id == id }),
           summary.equipmentInspectionForm == .subdistribution {
            return SAPNotificationDetail(summary: summary)
        }
        if notification.structuralFilterMetadata?.formCode == "TFM1" {
            let items: [SAPNotificationDetail.InspectionItem] = [
                .init(
                    id: "TFM1-0010-1",
                    title: "Sind die Ansprechpartner noch korrekt?",
                    information: "Überprüfung der hinterlegten Alarmkontakte und Notfall-Ansprechpartner.",
                    resultElementID: "TFM1-0010-1",
                    commentElementID: "TFM1-0010-9B"
                ),
                .init(
                    id: "TFM1-0020-1",
                    title: "Sind die Kontaktdaten noch korrekt?",
                    information: "Prüfung von Telefonnummern, Mobilnummern und E-Mail-Adressen.",
                    resultElementID: "TFM1-0020-1",
                    commentElementID: "TFM1-0020-9B"
                ),
                .init(
                    id: "TFM1-0030-1",
                    title: "Sind die geschalteten Anlagen korrekt?",
                    information: "Abgleich der im Alarmplan aufgeführten Brandmelde- und Lüftungsanlagen.",
                    resultElementID: "TFM1-0030-1",
                    commentElementID: "TFM1-0030-9B"
                )
            ]
            let summary = SAPNotificationSummary(
                id: notification.id,
                client: "100",
                title: notification.title,
                functionalLocationID: notification.equipment.isEmpty ? "DE-SAF-11152-10" : notification.equipment,
                functionalLocationName: notification.location.isEmpty ? "GB10_Rauschermühle_V1 Verwaltungsgebäude" : notification.location,
                startDate: "15.09.2026",
                endDate: "15.09.2026",
                systemStatus: "",
                userStatus: "OPEN",
                rawPayloadJSON: ""
            )
            return SAPNotificationDetail(
                summary: summary,
                structure: notification.equipment,
                equipmentID: "",
                inspectionItems: items,
                address: "Rauschermühle , 56648-Saffig",
                formCode: "TFM1"
            )
        }
        return nil
    }

    var openNotifications: Int {
        visibleNotifications.filter { $0.status == .open || $0.status == .attention }.count
    }

    var allNotificationCount: Int {
        isDemoMode ? notifications.count : sapDataStore.totalNotificationCount
    }

    /// The counters computed from data already read. Each one stays `nil`
    /// until its source has been loaded once, so a counter that is still being
    /// computed is never mistaken for zero.
    var freshDashboardMetrics: DashboardMetrics {
        DashboardMetrics(
            notifications: isDemoMode || sapDataStore.hasLoadedNotificationCount
                ? allNotificationCount
                : nil,
            defects: offlineWorkStore.hasLoaded ? offlineWorkStore.defectCount : nil,
            drafts: offlineWorkStore.hasLoaded ? offlineWorkStore.savedNotificationCount : nil,
            technicalPlaces: technicalPlacesStore.hasLoadedTotalCount
                ? technicalPlacesStore.totalCount
                : nil
        )
    }

    /// What the dashboard shows: each fresh counter as soon as it is known,
    /// the one saved at the previous launch until then.
    var dashboardMetrics: DashboardMetrics {
        freshDashboardMetrics.filled(from: savedDashboardMetrics)
    }

    /// Keeps the counters known so far for the next launch. Production only;
    /// called whenever `freshDashboardMetrics` changes.
    func rememberDashboardMetrics() {
        guard !isDemoMode else { return }
        let merged = freshDashboardMetrics.filled(from: savedDashboardMetrics)
        guard merged != savedDashboardMetrics else { return }
        savedDashboardMetrics = merged
        DashboardMetricsSnapshot.save(merged, workerID: sapDataStore.localWorkerID)
    }

    /// The notification rows every screen shows, with local drafts folded in.
    ///
    /// One SwiftUI pass reads this several times — the list, the selected row,
    /// the counters — and with a few hundred notifications rebuilding it each
    /// time was the bulk of the delay when the tab opened. It is therefore
    /// cached until its inputs change.
    var visibleNotifications: [MaintenanceNotification] {

        let key = VisibleNotificationsKey(
          isDemoMode: isDemoMode,
          offlineWorkRevision: offlineWorkStore.revision,
          notificationPageRevision: isDemoMode ? demoNotificationRevision : sapDataStore.notificationPageRevision
        )
        if visibleNotificationsKey == key {
            return cachedVisibleNotifications
        }
        let rows = applyingLocalWork(to: isDemoMode ? notifications : cachedProductionNotificationRows)
        cachedVisibleNotifications = rows
        visibleNotificationsKey = key
        return rows
    }

    private struct VisibleNotificationsKey: Equatable {
        let isDemoMode: Bool
        let offlineWorkRevision: Int
        /// The SAP page revision in production, the demo revision in demo mode.
        let notificationPageRevision: Int
    }

    /// Rows for the notifications a QR scan found, with the same local
    /// review and inspection state the notification list shows.
    func scanResultRows(for summaries: [SAPNotificationSummary]) -> [MaintenanceNotification] {
        applyingLocalWork(to: summaries.map(Self.notificationRow(from:)))
    }

    private func applyingLocalWork(to baseList: [MaintenanceNotification]) -> [MaintenanceNotification] {
        var elevatorInspectionsByNotificationID: [String: ElevatorInspectionDraftPayload] = [:]
        var reviewsByNotificationID: [String: NotificationReviewDraftPayload] = [:]
        for item in offlineWorkStore.items {
            if item.type == .elevatorInspection,
               let inspection = item.payload.elevatorInspection {
                elevatorInspectionsByNotificationID[inspection.notificationID] = inspection
            }
            if item.type == .notificationReview,
               item.status != .synchronized,
               let review = item.payload.notificationReview {
                reviewsByNotificationID[review.notificationID] = review
            }
        }
        return baseList.map { notification in
            if let inspection = elevatorInspectionsByNotificationID[notification.id] {
                let isClosed = inspection.isClosedLocally
                let isDef = inspection.closingSystemStatus == "MIAR" || inspection.closingUserStatus.contains("Mnot")
                return MaintenanceNotification(
                    id: notification.id,
                    title: notification.title,
                    location: notification.location,
                    dueDate: notification.dueDate,
                    equipment: notification.equipment,
                    sapStatus: notification.sapStatus,
                    status: isClosed ? .closedLocally : .draft,
                    completedChecks: inspection.elementValues.count,
                    totalChecks: notification.totalChecks,
                    isTemporarilySaved: !isClosed,
                    isClosedLocally: isClosed,
                    hasLocalDefect: isDef,
                    structuralFilterMetadata: notification.structuralFilterMetadata
                )
            }
            let review = reviewsByNotificationID[notification.id]
            let isClosedLocally = review?.isClosedLocally == true
            let hasLocalDefect = review?.results.values.contains(.yes) == true
            return MaintenanceNotification(
                id: notification.id,
                title: notification.title,
                location: notification.location,
                dueDate: notification.dueDate,
                equipment: notification.equipment,
                sapStatus: notification.sapStatus,
                status: isClosedLocally ? .closedLocally : (review == nil ? notification.status : .draft),
                completedChecks: notification.completedChecks,
                totalChecks: notification.totalChecks,
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

    /// SAP functional locations for location value helps. The demo forms
    /// bring their own sample locations.
    var functionalLocationDirectory: FunctionalLocationDirectory {
        isDemoMode ? .empty : sapDataStore.functionalLocationDirectory
    }

    var notificationFilterOptions: NotificationStructuralFilterOptions {
        isDemoMode
            ? MockFacilityData.notificationFilterOptions
            : sapDataStore.notificationFilterOptions
    }

    private var cachedProductionNotificationRows: [MaintenanceNotification] {
        let revision = sapDataStore.notificationPageRevision
        guard productionNotificationRowsRevision != revision else {
            return productionNotificationRows
        }
        productionNotificationRows = sapDataStore.notifications.map(Self.notificationRow(from:))
        productionNotificationRowsRevision = revision
        return productionNotificationRows
    }

    private static func notificationRow(from notification: SAPNotificationSummary) -> MaintenanceNotification {
        MaintenanceNotification(
            id: notification.id,
            title: notification.title.isEmpty ? notification.id : notification.title,
            location: notification.displayLocation,
            dueDate: notification.displayDateRange,
            equipment: notification.functionalLocationID,
            sapStatus: notification.displayStatus,
            status: .open,
            completedChecks: 0,
            totalChecks: 0,
            structuralFilterMetadata: notification.structuralFilterMetadata
        )
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

    func openManualDefect(_ itemID: UUID? = nil, preselecting object: DefectObjectOption? = nil) {
        if selection != .manualCapture {
            manualDefectReturnDestination = selection
        }
        pendingDefectObject = object
        manualCaptureRoute = .defect(itemID)
        selection = .manualCapture
    }

    /// Handed to the defect form once, when it loads. The technical object a
    /// new fault notification starts on comes from the screen the technician
    /// left (a technical place detail), not from the form itself.
    func consumePendingDefectObject() -> DefectObjectOption? {
        defer { pendingDefectObject = nil }
        return pendingDefectObject
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

    func openMobileLadder(
        _ itemID: UUID? = nil,
        preselecting anchor: TechnicalPlaceCreationAnchor? = nil
    ) {
        // An existing draft carries its own context; only a new one is placed.
        technicalPlacesRoute = itemID.map(TechnicalPlacesRoute.mobileLadderDraft) ?? .createMobileLadder(anchor)
        selection = .technicalPlaces
    }

    func closeMobileLadder() {
        technicalPlacesRoute = .hierarchy
    }

    func openSubdistribution(
        _ itemID: UUID? = nil,
        preselecting anchor: TechnicalPlaceCreationAnchor? = nil
    ) {
        technicalPlacesRoute = itemID.map(TechnicalPlacesRoute.subdistributionDraft) ?? .createSubdistribution(anchor)
        selection = .technicalPlaces
    }

    /// SAP creates a defect (I2) only under an I1 of the same object.
    func canReportDefect(on reference: TechnicalObjectReference) async -> Bool {
        await sapDataStore.loadDefectParentNotifications().contains { $0.belongs(to: reference) }
    }

    /// What "Equipment einbauen" can offer at `place`, read from the same
    /// creation data the two forms load, so the detail never offers a form
    /// that would open with nothing to choose.
    func equipmentInstallOptions(at place: TechnicalObjectNode) async -> TechnicalPlaceInstallOptions {
        let anchor = TechnicalPlaceCreationAnchor(place)
        let workerID = offlineWorkStore.workerID
        async let ladder = try? mobileLadderCreationProvider.loadMobileLadderCreationData(for: workerID)
        async let subdistribution = try? subdistributionCreationProvider.loadSubdistributionCreationData(for: workerID)
        let ladderContexts = await ladder?.contexts ?? []
        let subdistributionContexts = await subdistribution?.contexts ?? []
        return TechnicalPlaceInstallOptions(
            mobileLadder: TechnicalPlaceInstallOptions.availability(
                at: anchor,
                among: ladderContexts.map {
                    ($0.legacyContext.country, $0.legacyContext.businessEntity, $0.legacyContext.building)
                },
                trade: ladderContexts.first?.legacyContext.trade ?? ""
            ),
            subdistribution: TechnicalPlaceInstallOptions.availability(
                at: anchor,
                among: subdistributionContexts.map {
                    ($0.legacyContext.country, $0.legacyContext.businessEntity, $0.legacyContext.building)
                }
            )
        )
    }

    func closeSubdistribution() {
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

    func openScannedNotification(_ notification: SAPNotificationSummary) {
        selectedNotificationID = nil
        selectedOfflineNotificationDetail = SAPNotificationDetail(summary: notification)
        offlineNotificationReturnDestination = .scan
    }

    /// A notification opened from a linked-processes list returns to the
    /// screen it was opened from, with that screen's own state intact.
    func openLinkedNotification(_ notification: SAPNotificationSummary) {
        let returnDestination = selection
        selectedNotificationID = nil
        selectedOfflineNotificationDetail = SAPNotificationDetail(summary: notification)
        offlineNotificationReturnDestination = returnDestination
    }

    func openSavedElevatorInspection(_ inspection: ElevatorInspectionDraftPayload) async -> Bool {
        let returnDestination = selection
        if let snapshot = inspection.notificationSnapshot {
            // Older snapshots omitted the T_PROPS dropdowns and action/material
            // mappings. Recover those from the local cache, never from SAP.
            var fallbackRawPayloadJSON = ""
            if snapshot.rawPayloadJSON?.isEmpty != false {
                let cachedSummary: SAPNotificationSummary?
                if isDemoMode {
                    cachedSummary = MockFacilityData.sapNotifications.first { $0.id == inspection.notificationID }
                } else {
                    cachedSummary = await sapDataStore.cachedNotification(id: inspection.notificationID)
                }
                guard let cachedSummary else { return false }
                fallbackRawPayloadJSON = cachedSummary.rawPayloadJSON
            }
            selectedNotificationID = nil
            selectedOfflineNotificationDetail = SAPNotificationDetail(
                offlineSnapshot: snapshot,
                notificationID: inspection.notificationID,
                fallbackFormCode: inspection.form.formCode,
                fallbackRawPayloadJSON: fallbackRawPayloadJSON
            )
            offlineNotificationReturnDestination = returnDestination
            return true
        }

        let cachedSummary: SAPNotificationSummary?
        if isDemoMode {
            cachedSummary = MockFacilityData.sapNotifications.first { $0.id == inspection.notificationID }
        } else {
            cachedSummary = await sapDataStore.cachedNotification(id: inspection.notificationID)
        }
        guard let cachedSummary else { return false }

        selectedNotificationID = nil
        selectedOfflineNotificationDetail = SAPNotificationDetail(summary: cachedSummary)
        offlineNotificationReturnDestination = returnDestination
        return true
    }

    /// Saved reviews are presented over their source screen and return there
    /// when the user closes the detail. A legacy invalid-master-data warning
    /// may instead explicitly send the technician to Notifications.
    func dismissOfflineNotificationDetail(returningTo destination: AppDestination? = nil) {
        selectedOfflineNotificationDetail = nil
        let returnDestination = destination ?? offlineNotificationReturnDestination ?? .notifications
        offlineNotificationReturnDestination = nil
        selection = returnDestination
    }

    /// Demo has no SAP. Its sync button plays a short sync and then restores
    /// the demo data to its starting state.
    private(set) var isResettingDemo = false

    var isSyncing: Bool {
        isDemoMode ? isResettingDemo : sapDataStore.isRefreshing
    }

    var canSync: Bool {
        isDemoMode ? !isResettingDemo : sapDataStore.isRefreshAvailable && !sapDataStore.isRefreshing
    }

    /// The local work a synchronization deletes: in production the forms
    /// saved with "Zwischenspeichern" (legacy `REQID = 'X'`), in the demo
    /// everything the reset clears. Completed work is sent, not deleted.
    var synchronizationDeletionCount: Int {
        isDemoMode ? offlineWorkStore.activeQueueCount : offlineWorkStore.temporarilySavedFormItems.count
    }

    /// Like the legacy `check4TempMeldungen`: asks first when the
    /// synchronization would delete local work, and starts at once otherwise.
    func requestSAPRefresh() {
        guard canSync else { return }
        if synchronizationDeletionCount > 0 {
            shouldConfirmSynchronization = true
        } else {
            startSynchronization()
        }
    }

    /// "Ja" of the legacy dialog: the temporarily saved forms are deleted
    /// first, and the synchronization starts only once they are gone.
    func confirmSynchronization() {
        shouldConfirmSynchronization = false
        if isDemoMode {
            simulateDemoSync()
            return
        }
        Task {
            do {
                try await offlineWorkStore.deleteTemporarilySavedForms(photoStore: photoAttachmentStore)
                proceedWithSAPRefresh()
            } catch {
                synchronizationCleanupFailed = true
            }
        }
    }

    func cancelSynchronization() {
        shouldConfirmSynchronization = false
    }

    private func startSynchronization() {
        if isDemoMode {
            simulateDemoSync()
        } else {
            proceedWithSAPRefresh()
        }
    }

    private func proceedWithSAPRefresh() {
        guard !isDemoMode, sapDataStore.isRefreshAvailable, !sapDataStore.isRefreshing else { return }
        sapDataStore.dismissError()
        if sapDataStore.hasValidSavedToken {
            guard sapDataStore.beginTokenRefresh() else { return }
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

    private func simulateDemoSync() {
        guard isDemoMode, !isResettingDemo else { return }
        isResettingDemo = true
        Task {
            try? await Task.sleep(for: .milliseconds(900))
            resetDemo()
            isResettingDemo = false
        }
    }

    func resetDemo() {
        NotificationStructuralFilterPreferences.reset(
            workerID: sapDataStore.localWorkerID,
            isDemoMode: true
        )
        notifications = MockFacilityData.notifications
        defects = MockFacilityData.defects
        manualCaptureRoute = .landing
        pendingDefectObject = nil
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
            try? await documentAttachmentStore.reset()
        }
        selection = .overview
    }
}

enum MockFacilityData {
    static let tfm2PayloadJSON = """
    {
      "QMNUM": "4710000012",
      "QMART": "I1",
      "FORMNR": "TFM2",
      "PLTXT": "Aufzugskontrolle Personenaufzug",
      "STRNO": "UN01-ST01-BG01-TECH-460-AUF1",
      "EQUNR": "EQ-100010",
      "EQKTX": "Personenaufzug Otis 2000",
      "CITY1_TO": "Essen",
      "STREET_TO": "Hauptstraße 12",
      "TPWEH": "WE 01",
      "TPGEB": "Gebäude A",
      "IWERK": "1501",
      "GEWRK": "TFM",
      "T_PLPOD": [
        {
          "USR00": "POSITION",
          "STEUS": "TFM2",
          "VORNR": "0010",
          "LTXA1": "Triebwerksraum / Schachtkopf sauber und frei von Fremdkörpern",
          "LTXA2": "Überprüfung auf Sauberkeit und Brandlasten.",
          "T_PROPS": [
            { "POSNR": "1", "DFVAL": "1;2;3;4;5;", "DFVAL_TXT": "In Ordnung;Mangel beseitigt;Mangel behoben;Mangel vorhanden;entfällt;" },
            { "POSNR": "2", "DFVAL": "7;8;9;", "DFVAL_TXT": "Kleinreparatur;Weiterer Einsatz erforderlich;Keine Maßnahme;" },
            { "POSNR": "3", "DFVAL": "X;", "DFVAL_TXT": "Material bestellen;" }
          ]
        },
        {
          "USR00": "POSITION",
          "STEUS": "TFM2",
          "VORNR": "0020",
          "LTXA1": "Fahrkorbtableau und Notrufeinrichtung funktionsfähig",
          "LTXA2": "Notruftaste betätigen und Sprechverbindung zur Leitstelle prüfen.",
          "T_PROPS": [
            { "POSNR": "1", "DFVAL": "1;2;3;4;5;", "DFVAL_TXT": "In Ordnung;Mangel beseitigt;Mangel behoben;Mangel vorhanden;entfällt;" },
            { "POSNR": "2", "DFVAL": "7;8;9;", "DFVAL_TXT": "Kleinreparatur;Weiterer Einsatz erforderlich;Keine Maßnahme;" }
          ]
        },
        {
          "USR00": "POSITION",
          "STEUS": "TFM2",
          "VORNR": "0030",
          "LTXA1": "Schachttüren und Türverriegelungen mechanisch einwandfrei",
          "LTXA2": "Prüfung auf Leichtgängigkeit und Verriegelungssicherheit.",
          "T_PROPS": [
            { "POSNR": "1", "DFVAL": "1;2;3;4;5;", "DFVAL_TXT": "In Ordnung;Mangel beseitigt;Mangel behoben;Mangel vorhanden;entfällt;" },
            { "POSNR": "2", "DFVAL": "7;8;9;", "DFVAL_TXT": "Kleinreparatur;Weiterer Einsatz erforderlich;Keine Maßnahme;" },
            { "POSNR": "3", "DFVAL": "X;", "DFVAL_TXT": "Material bestellen;" }
          ]
        },
        {
          "USR00": "POSITION",
          "STEUS": "TFM2",
          "VORNR": "0040",
          "LTXA1": "Fahrkorbbeleuchtung und Notbeleuchtung in Ordnung",
          "LTXA2": "",
          "T_PROPS": [
            { "POSNR": "1", "DFVAL": "1;2;3;4;5;", "DFVAL_TXT": "In Ordnung;Mangel beseitigt;Mangel behoben;Mangel vorhanden;entfällt;" }
          ]
        },
        {
          "USR00": "POSITION",
          "STEUS": "TFM2",
          "VORNR": "0050",
          "LTXA1": "Haltegenauigkeit an den Haltestellen innerhalb der Toleranz",
          "LTXA2": "Bündigkeit der Schwelle an allen Etagen kontrollieren.",
          "T_PROPS": [
            { "POSNR": "1", "DFVAL": "1;2;3;4;5;", "DFVAL_TXT": "In Ordnung;Mangel beseitigt;Mangel behoben;Mangel vorhanden;entfällt;" },
            { "POSNR": "2", "DFVAL": "7;8;9;", "DFVAL_TXT": "Kleinreparatur;Weiterer Einsatz erforderlich;Keine Maßnahme;" }
          ]
        }
      ]
    }
    """

    /// TFM4 Steigleitern. Positions are dropdown forms like TFM2; the demo
    /// deliberately carries a position 3 property to show that TFM4 ignores it.
    static let tfm4PayloadJSON = """
    {
      "QMNUM": "4710000024",
      "QMART": "I1",
      "FORMNR": "TFM4",
      "PLTXT": "Steigleiter Dachausstieg",
      "STRNO": "UN01-ST01-BG01-TECH-470-STL1",
      "EQUNR": "EQ-100024",
      "EQKTX": "Steigleiter Dachausstieg Nord",
      "EQART": "TFMLEITER",
      "CITY1_TO": "Essen",
      "STREET_TO": "Hauptstraße 12",
      "TPWEH": "WE 01",
      "TPGEB": "Gebäude A",
      "IWERK": "1501",
      "GEWRK": "TFM",
      "T_PLPOD": [
        {
          "USR00": "HEADER",
          "STEUS": "TFM4",
          "VORNR": "0005",
          "LTXA1": "Leiter und Befestigung"
        },
        {
          "USR00": "POSITION",
          "STEUS": "TFM4",
          "VORNR": "0010",
          "LTXA1": "Holme und Sprossen unbeschädigt und fest",
          "LTXA2": "Auf Verformung, Risse und Korrosion prüfen.",
          "T_PROPS": [
            { "POSNR": "1", "DFVAL": "1;2;3;4;5;", "DFVAL_TXT": "In Ordnung;Mangel beseitigt;Mangel behoben;Mangel vorhanden;entfällt;" },
            { "POSNR": "2", "DFVAL": "7;8;9;", "DFVAL_TXT": "Kleinreparatur;Weiterer Einsatz erforderlich;Keine Maßnahme;" },
            { "POSNR": "3", "DFVAL": "X;", "DFVAL_TXT": "Material bestellen;" }
          ]
        },
        {
          "USR00": "POSITION",
          "STEUS": "TFM4",
          "VORNR": "0020",
          "LTXA1": "Wandbefestigungen und Dübel fest",
          "LTXA2": "",
          "T_PROPS": [
            { "POSNR": "1", "DFVAL": "1;2;3;4;5;", "DFVAL_TXT": "In Ordnung;Mangel beseitigt;Mangel behoben;Mangel vorhanden;entfällt;" },
            { "POSNR": "2", "DFVAL": "7;8;9;", "DFVAL_TXT": "Kleinreparatur;Weiterer Einsatz erforderlich;Keine Maßnahme;" }
          ]
        },
        {
          "USR00": "HEADER",
          "STEUS": "TFM4",
          "VORNR": "0025",
          "LTXA1": "Sicherheitseinrichtungen"
        },
        {
          "USR00": "POSITION",
          "STEUS": "TFM4",
          "VORNR": "0030",
          "LTXA1": "Rückenschutz vollständig und unbeschädigt",
          "LTXA2": "",
          "T_PROPS": [
            { "POSNR": "1", "DFVAL": "1;2;3;4;5;", "DFVAL_TXT": "In Ordnung;Mangel beseitigt;Mangel behoben;Mangel vorhanden;entfällt;" },
            { "POSNR": "2", "DFVAL": "7;8;9;", "DFVAL_TXT": "Kleinreparatur;Weiterer Einsatz erforderlich;Keine Maßnahme;" }
          ]
        },
        {
          "USR00": "POSITION",
          "STEUS": "TFM4",
          "VORNR": "0040",
          "LTXA1": "Steigschutzeinrichtung funktionsfähig",
          "LTXA2": "Läufer und Schiene auf Leichtgängigkeit prüfen.",
          "T_PROPS": [
            { "POSNR": "1", "DFVAL": "1;2;3;4;5;", "DFVAL_TXT": "In Ordnung;Mangel beseitigt;Mangel behoben;Mangel vorhanden;entfällt;" },
            { "POSNR": "2", "DFVAL": "7;8;9;", "DFVAL_TXT": "Kleinreparatur;Weiterer Einsatz erforderlich;Keine Maßnahme;" }
          ]
        }
      ]
    }
    """

    /// TFM7 Unterverteilung. The `FOTO` operation is deliberately present:
    /// Cordova's `MasterDataForm` renders it as a photo-and-note row with no
    /// result selector and blocks close until its JPEG evidence exists.
    static let tfm7PayloadJSON = """
    {
      "QMNUM": "4710000031",
      "QMART": "I1",
      "FORMNR": "TFM7",
      "PLTXT": "Unterverteilung Bürotrakt",
      "STRNO": "UN01-ST01-BG01-TECH-480-UV1",
      "EQUNR": "EQ-100031",
      "EQKTX": "UV Bürotrakt 1. OG",
      "EQART": "TFMNSPV",
      "CITY1_TO": "Essen",
      "STREET_TO": "Hauptstraße 12",
      "TPWEH": "WE 01",
      "TPGEB": "Gebäude A",
      "IWERK": "1501",
      "GEWRK": "TFM",
      "T_PLPOD": [
        {
          "USR00": "HEADER",
          "STEUS": "TFM7",
          "VORNR": "0005",
          "LTXA1": "Prüfung der Unterverteilung"
        },
        {
          "USR00": "POSITION",
          "STEUS": "TFM7",
          "VORNR": "0010",
          "LTXA1": "Prüfung durch Betätigen der Prüftasten",
          "LTXA2": "FI-Schutzschalter gemäß Kennzeichnung prüfen.",
          "T_PROPS": [
            { "POSNR": "1", "DFVAL": "1;2;3;4;5;", "DFVAL_TXT": "In Ordnung;Mangel beseitigt;Mangel behoben;Mangel vorhanden;entfällt;" },
            { "POSNR": "2", "DFVAL": "7;8;9;", "DFVAL_TXT": "Kleinreparatur;Weiterer Einsatz erforderlich;Keine Maßnahme;" }
          ]
        },
        {
          "USR00": "POSITION",
          "STEUS": "TFM7",
          "VORNR": "0020",
          "LTXA1": "Sichtkontrolle",
          "LTXA2": "Gehäuse, Beschriftung und Abdeckungen kontrollieren.",
          "T_PROPS": [
            { "POSNR": "1", "DFVAL": "1;2;3;4;5;", "DFVAL_TXT": "In Ordnung;Mangel beseitigt;Mangel behoben;Mangel vorhanden;entfällt;" },
            { "POSNR": "2", "DFVAL": "7;8;9;", "DFVAL_TXT": "Kleinreparatur;Weiterer Einsatz erforderlich;Keine Maßnahme;" }
          ]
        },
        {
          "USR00": "FOTO",
          "STEUS": "TFM7",
          "VORNR": "0030",
          "LTXA1": "Foto Anlagentechnik (Verteilung)",
          "LTXA2": "Übersichtsaufnahme der Unterverteilung hinzufügen."
        }
      ]
    }
    """

    /// TFM6 Feststellanlage. It runs on the TFM2 `Aufzugskontrolle` screen,
    /// so positions carry the position 3 material flag.
    static let tfm6PayloadJSON = """
    {
      "QMNUM": "4710000036",
      "QMART": "I1",
      "FORMNR": "TFM6",
      "PLTXT": "Feststellanlage Brandschutztür",
      "STRNO": "UN01-ST01-BG01-TECH-480-FSA1",
      "EQUNR": "EQ-100036",
      "EQKTX": "Feststellanlage Flur EG Ost",
      "EQART": "TFMFSA",
      "CITY1_TO": "Essen",
      "STREET_TO": "Hauptstraße 12",
      "TPWEH": "WE 01",
      "TPGEB": "Gebäude A",
      "IWERK": "1501",
      "GEWRK": "TFM",
      "T_PLPOD": [
        {
          "USR00": "HEADER",
          "STEUS": "TFM6",
          "VORNR": "0005",
          "LTXA1": "Feststellvorrichtung"
        },
        {
          "USR00": "POSITION",
          "STEUS": "TFM6",
          "VORNR": "0010",
          "LTXA1": "Haftmagnet und Gegenplatte unbeschädigt und sauber",
          "LTXA2": "Auf Verschmutzung, Verformung und festen Sitz prüfen.",
          "T_PROPS": [
            { "POSNR": "1", "DFVAL": "1;2;3;4;5;", "DFVAL_TXT": "In Ordnung;Mangel beseitigt;Mangel behoben;Mangel vorhanden;entfällt;" },
            { "POSNR": "2", "DFVAL": "7;8;9;", "DFVAL_TXT": "Kleinreparatur;Weiterer Einsatz erforderlich;Keine Maßnahme;" },
            { "POSNR": "3", "DFVAL": "X;", "DFVAL_TXT": "Material bestellen;" }
          ]
        },
        {
          "USR00": "POSITION",
          "STEUS": "TFM6",
          "VORNR": "0020",
          "LTXA1": "Tür schließt nach Auslösung selbsttätig",
          "LTXA2": "",
          "T_PROPS": [
            { "POSNR": "1", "DFVAL": "1;2;3;4;5;", "DFVAL_TXT": "In Ordnung;Mangel beseitigt;Mangel behoben;Mangel vorhanden;entfällt;" },
            { "POSNR": "2", "DFVAL": "7;8;9;", "DFVAL_TXT": "Kleinreparatur;Weiterer Einsatz erforderlich;Keine Maßnahme;" }
          ]
        },
        {
          "USR00": "HEADER",
          "STEUS": "TFM6",
          "VORNR": "0025",
          "LTXA1": "Auslösevorrichtung"
        },
        {
          "USR00": "POSITION",
          "STEUS": "TFM6",
          "VORNR": "0030",
          "LTXA1": "Rauchschalter ausgelöst und Tür freigegeben",
          "LTXA2": "Mit Prüfaerosol auslösen.",
          "T_PROPS": [
            { "POSNR": "1", "DFVAL": "1;2;3;4;5;", "DFVAL_TXT": "In Ordnung;Mangel beseitigt;Mangel behoben;Mangel vorhanden;entfällt;" },
            { "POSNR": "2", "DFVAL": "7;8;9;", "DFVAL_TXT": "Kleinreparatur;Weiterer Einsatz erforderlich;Keine Maßnahme;" },
            { "POSNR": "3", "DFVAL": "X;", "DFVAL_TXT": "Material bestellen;" }
          ]
        },
        {
          "USR00": "POSITION",
          "STEUS": "TFM6",
          "VORNR": "0040",
          "LTXA1": "Handauslösetaster gekennzeichnet und funktionsfähig",
          "LTXA2": "",
          "T_PROPS": [
            { "POSNR": "1", "DFVAL": "1;2;3;4;5;", "DFVAL_TXT": "In Ordnung;Mangel beseitigt;Mangel behoben;Mangel vorhanden;entfällt;" },
            { "POSNR": "2", "DFVAL": "7;8;9;", "DFVAL_TXT": "Kleinreparatur;Weiterer Einsatz erforderlich;Keine Maßnahme;" }
          ]
        }
      ]
    }
    """

    /// TFM8 Dachanlagen. It runs on `MasterDataForm` like TFM4 but carries no
    /// "Außer Betrieb" status; the position 3 property is ignored as for TFM4.
    static let tfm8PayloadJSON = """
    {
      "QMNUM": "4710000048",
      "QMART": "I1",
      "FORMNR": "TFM8",
      "PLTXT": "Dachanlage Absturzsicherung",
      "STRNO": "UN01-ST01-BG01-TECH-490-DACH1",
      "EQUNR": "EQ-100048",
      "EQKTX": "Seilsicherungssystem Dach Nord",
      "EQART": "TFMDACH",
      "CITY1_TO": "Essen",
      "STREET_TO": "Hauptstraße 12",
      "TPWEH": "WE 01",
      "TPGEB": "Gebäude A",
      "IWERK": "1501",
      "GEWRK": "TFM",
      "T_PLPOD": [
        {
          "USR00": "HEADER",
          "STEUS": "TFM8",
          "VORNR": "0005",
          "LTXA1": "Anschlageinrichtungen"
        },
        {
          "USR00": "POSITION",
          "STEUS": "TFM8",
          "VORNR": "0010",
          "LTXA1": "Anschlagpunkte fest verankert und unbeschädigt",
          "LTXA2": "Auf Korrosion, Verformung und festen Sitz prüfen.",
          "T_PROPS": [
            { "POSNR": "1", "DFVAL": "1;2;3;4;5;", "DFVAL_TXT": "In Ordnung;Mangel beseitigt;Mangel behoben;Mangel vorhanden;entfällt;" },
            { "POSNR": "2", "DFVAL": "7;8;9;", "DFVAL_TXT": "Kleinreparatur;Weiterer Einsatz erforderlich;Keine Maßnahme;" },
            { "POSNR": "3", "DFVAL": "X;", "DFVAL_TXT": "Material bestellen;" }
          ]
        },
        {
          "USR00": "POSITION",
          "STEUS": "TFM8",
          "VORNR": "0020",
          "LTXA1": "Seilsystem gespannt und Endbefestigungen fest",
          "LTXA2": "",
          "T_PROPS": [
            { "POSNR": "1", "DFVAL": "1;2;3;4;5;", "DFVAL_TXT": "In Ordnung;Mangel beseitigt;Mangel behoben;Mangel vorhanden;entfällt;" },
            { "POSNR": "2", "DFVAL": "7;8;9;", "DFVAL_TXT": "Kleinreparatur;Weiterer Einsatz erforderlich;Keine Maßnahme;" }
          ]
        },
        {
          "USR00": "HEADER",
          "STEUS": "TFM8",
          "VORNR": "0025",
          "LTXA1": "Dachzugang und Absturzsicherung"
        },
        {
          "USR00": "POSITION",
          "STEUS": "TFM8",
          "VORNR": "0030",
          "LTXA1": "Dachausstieg und Geländer in Ordnung",
          "LTXA2": "",
          "T_PROPS": [
            { "POSNR": "1", "DFVAL": "1;2;3;4;5;", "DFVAL_TXT": "In Ordnung;Mangel beseitigt;Mangel behoben;Mangel vorhanden;entfällt;" },
            { "POSNR": "2", "DFVAL": "7;8;9;", "DFVAL_TXT": "Kleinreparatur;Weiterer Einsatz erforderlich;Keine Maßnahme;" }
          ]
        },
        {
          "USR00": "POSITION",
          "STEUS": "TFM8",
          "VORNR": "0040",
          "LTXA1": "Kennzeichnung und Gebrauchsanleitung vorhanden",
          "LTXA2": "Typenschild und Nutzungshinweise am Dachzugang prüfen.",
          "T_PROPS": [
            { "POSNR": "1", "DFVAL": "1;2;3;4;5;", "DFVAL_TXT": "In Ordnung;Mangel beseitigt;Mangel behoben;Mangel vorhanden;entfällt;" },
            { "POSNR": "2", "DFVAL": "7;8;9;", "DFVAL_TXT": "Kleinreparatur;Weiterer Einsatz erforderlich;Keine Maßnahme;" }
          ]
        }
      ]
    }
    """

    static let sapNotifications: [SAPNotificationSummary] = [
        SAPNotificationSummary(
            id: "4710000012",
            client: "100",
            title: "Aufzugskontrolle Personenaufzug",
            functionalLocationID: "UN01-ST01-BG01-TECH-460-AUF1",
            functionalLocationName: "Personenaufzug Trakt A",
            equipmentID: "EQ-100010",
            startDate: "2026-08-10",
            endDate: "2026-08-20",
            systemStatus: "Offen",
            userStatus: "",
            rawPayloadJSON: tfm2PayloadJSON
        ),
        SAPNotificationSummary(
            id: "4710000024",
            client: "100",
            title: "Steigleiter Dachausstieg",
            functionalLocationID: "UN01-ST01-BG01-TECH-470-STL1",
            functionalLocationName: "Steigleiter Dachausstieg Nord",
            equipmentID: "EQ-100024",
            startDate: "2026-08-10",
            endDate: "2026-08-20",
            systemStatus: "Offen",
            userStatus: "",
            rawPayloadJSON: tfm4PayloadJSON
        ),
        SAPNotificationSummary(
            id: "4710000036",
            client: "100",
            title: "Feststellanlage Brandschutztür",
            functionalLocationID: "UN01-ST01-BG01-TECH-480-FSA1",
            functionalLocationName: "Feststellanlage Flur EG Ost",
            equipmentID: "EQ-100036",
            startDate: "2026-08-10",
            endDate: "2026-08-20",
            systemStatus: "Offen",
            userStatus: "",
            rawPayloadJSON: tfm6PayloadJSON
        ),
        SAPNotificationSummary(
            id: "4710000048",
            client: "100",
            title: "Dachanlage Absturzsicherung",
            functionalLocationID: "UN01-ST01-BG01-TECH-490-DACH1",
            functionalLocationName: "Seilsicherungssystem Dach Nord",
            equipmentID: "EQ-100048",
            startDate: "2026-08-10",
            endDate: "2026-08-20",
            systemStatus: "Offen",
            userStatus: "",
            rawPayloadJSON: tfm8PayloadJSON
        ),
        SAPNotificationSummary(
            id: "4710000031",
            client: "100",
            title: "Unterverteilung Bürotrakt",
            functionalLocationID: "UN01-ST01-BG01-TECH-480-UV1",
            functionalLocationName: "UV Bürotrakt 1. OG",
            equipmentID: "EQ-100031",
            startDate: "2026-08-10",
            endDate: "2026-08-20",
            systemStatus: "Offen",
            userStatus: "",
            rawPayloadJSON: tfm7PayloadJSON
        )
    ]

    static let notifications: [MaintenanceNotification] = [
        .init(id: "4710000012", title: "Aufzugskontrolle Personenaufzug", location: "Gebäude A · Aufzug 1", dueDate: "Heute", equipment: "EQ-100010", sapStatus: nil, status: .open, completedChecks: 0, totalChecks: 5, structuralFilterMetadata: .init(countryCode: "DE", locationCode: "ESS", businessEntityCode: "11248", buildingCode: "A", tradeCode: "FM", formCode: "TFM2", functionalLocationName: "Gebäude A")),
        .init(id: "4710000024", title: "Steigleiter Dachausstieg", location: "Gebäude A · Dachausstieg Nord", dueDate: "Heute", equipment: "EQ-100024", sapStatus: nil, status: .open, completedChecks: 0, totalChecks: 4, structuralFilterMetadata: .init(countryCode: "DE", locationCode: "ESS", businessEntityCode: "11248", buildingCode: "A", tradeCode: "FM", formCode: "TFM4", functionalLocationName: "Gebäude A")),
        .init(id: "4710000036", title: "Feststellanlage Brandschutztür", location: "Gebäude A · Flur EG Ost", dueDate: "Heute", equipment: "EQ-100036", sapStatus: nil, status: .open, completedChecks: 0, totalChecks: 4, structuralFilterMetadata: .init(countryCode: "DE", locationCode: "ESS", businessEntityCode: "11248", buildingCode: "A", tradeCode: "FM", formCode: "TFM6", functionalLocationName: "Gebäude A")),
        .init(id: "4710000048", title: "Dachanlage Absturzsicherung", location: "Gebäude A · Dach Nord", dueDate: "Heute", equipment: "EQ-100048", sapStatus: nil, status: .open, completedChecks: 0, totalChecks: 4, structuralFilterMetadata: .init(countryCode: "DE", locationCode: "ESS", businessEntityCode: "11248", buildingCode: "A", tradeCode: "FM", formCode: "TFM8", functionalLocationName: "Gebäude A")),
        .init(id: "M-31042", title: "Fire door inspection", location: "Building A · Level 02", dueDate: "Today", equipment: "Door group A2", sapStatus: nil, status: .open, completedChecks: 1, totalChecks: 6, structuralFilterMetadata: .init(countryCode: "DE", locationCode: "ESS", businessEntityCode: "11248", buildingCode: "A", tradeCode: "FM", formCode: "TFM3", functionalLocationName: "Building A")),
        .init(id: "4710000031", title: "Unterverteilung Bürotrakt", location: "Gebäude A · Bürotrakt 1. OG", dueDate: "Heute", equipment: "EQ-100031", sapStatus: nil, status: .attention, completedChecks: 0, totalChecks: 3, structuralFilterMetadata: .init(countryCode: "DE", locationCode: "ESS", businessEntityCode: "11248", buildingCode: "A", tradeCode: "EL", formCode: "TFM7", functionalLocationName: "Gebäude A")),
        .init(id: "005140055904", title: "MTFM_Überprüfung Alarmpläne", location: "GB10_Rauschermühle_V1 Verwaltungsgebäude", dueDate: "Tomorrow", equipment: "DE-SAF-11152-10", sapStatus: nil, status: .open, completedChecks: 0, totalChecks: 3, structuralFilterMetadata: .init(countryCode: "DE", locationCode: "SAF", businessEntityCode: "11152", buildingCode: "GB10", tradeCode: "FM", formCode: "TFM1", functionalLocationName: "GB10_Rauschermühle_V1 Verwaltungsgebäude")),
        .init(id: "M-30965", title: "Water meter reading", location: "Utility room · Level -1", dueDate: "29 Aug", equipment: "WM-120", sapStatus: nil, status: .pending, completedChecks: 4, totalChecks: 4, structuralFilterMetadata: .init(countryCode: "DE", locationCode: "ESS", businessEntityCode: "11248", buildingCode: "U", tradeCode: "UTIL", formCode: "TFM1", functionalLocationName: "Utility room"))
    ]

    static let notificationFilterOptions = NotificationStructuralFilterOptions(
        metadata: notifications.compactMap(\.structuralFilterMetadata)
    )

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
