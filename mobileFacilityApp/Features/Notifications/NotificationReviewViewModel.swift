import Foundation
import Observation

@MainActor
@Observable
final class NotificationReviewViewModel {
    static let maximumPhotoCount = 20

    enum Feedback: Identifiable {
        case savedLocally
        case closedLocally
        case incomplete
        case saveFailed
        case photoFailed
        case photoLimitReached
        case cameraUnavailable
        case cameraPermissionDenied
        /// The chosen I2 notifications were stored with the closed review.
        case i2NotificationsQueued

        var id: String { String(describing: self) }
    }

    private let detail: SAPNotificationDetail
    private let offlineWorkStore: OfflineWorkStore
    private let photoStore: any PhotoAttachmentStore
    private let sapDataStore: SAPDataStore?
    private var originalAttachmentIDs = Set<String>()
    private var removedOriginalAttachmentIDs = Set<String>()
    private var persistedDraft: NotificationReviewDraftPayload?

    var performedOn = Date.now
    var comments: [String: String] = [:]
    var results: [String: NotificationReviewResult] = [:]
    private(set) var photoAttachments: [NotificationPhotoAttachment] = []
    private(set) var photoData: [String: Data] = [:]
    private(set) var isSaving = false
    private(set) var isLoading = true
    private(set) var isClosedLocally = false
    var feedback: Feedback?
    private var outgoingProcessID: String?
    /// The defect dialog shown after closing, for users with I2 permission.
    let i2Selection = I2DefectSelection()
    /// I2 notifications SAP already holds for this technical object.
    private(set) var existingI2Notifications: [SAPI2NotificationSummary] = []
    private var canCreateI2 = false
    /// Reporter shown in the report built when the review is closed.
    private var userProfile: SAPUserProfile?

    init(
        detail: SAPNotificationDetail,
        offlineWorkStore: OfflineWorkStore,
        photoStore: any PhotoAttachmentStore,
        sapDataStore: SAPDataStore? = nil
    ) {
        self.detail = detail
        self.offlineWorkStore = offlineWorkStore
        self.photoStore = photoStore
        self.sapDataStore = sapDataStore
    }

    var canClose: Bool {
        guard !detail.inspectionItems.isEmpty else { return false }
        guard detail.inspectionItems.allSatisfy({ results[$0.id] != nil }) else { return false }
        // `Rundgang.controller.js` refuses a defect without a comment in
        // `checkInputConstraints`, exactly as TFM1 does. The two forms share
        // the rule, so they share `InspectionFormRules`.
        return detail.inspectionItems.allSatisfy { !isCommentMissing(for: $0.id) }
    }

    /// Whether this position records a defect but no comment.
    func isCommentMissing(for itemID: String) -> Bool {
        guard results[itemID] == .yes else { return false }
        return comments[itemID]?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ?? true
    }

    var isEditingDisabled: Bool { isLoading || isClosedLocally }

    func attachments(for checklistItemID: String) -> [NotificationPhotoAttachment] {
        photoAttachments.filter { $0.checklistItemID == checklistItemID }
    }

    func load() async {
        isLoading = true
        defer { isLoading = false }
        await discardStagedPhotos()
        await offlineWorkStore.load()
        if let sapDataStore {
            userProfile = await sapDataStore.loadUserProfile()
            canCreateI2 = userProfile?.canCreateI2 ?? false
            existingI2Notifications = await sapDataStore.loadI2Notifications(for: detail)
        }
        guard let draft = offlineWorkStore.notificationReview(notificationID: detail.summary.id) else { return }

        persistedDraft = draft
        performedOn = draft.performedOn
        results = draft.results
        comments = draft.comments
        photoAttachments = draft.photoAttachments
        originalAttachmentIDs = Set(draft.photoAttachments.map(\.localAttachmentID))
        outgoingProcessID = draft.outgoingProcessID
        isClosedLocally = draft.isClosedLocally
        removedOriginalAttachmentIDs.removeAll()
        photoData.removeAll()
        for attachment in draft.photoAttachments {
            if let data = try? await photoStore.loadJPEG(id: attachment.localAttachmentID) {
                photoData[attachment.localAttachmentID] = data
            }
        }
    }

    func addPhoto(jpegData: Data, to item: SAPNotificationDetail.InspectionItem) async {
        guard !isEditingDisabled, !isSaving else { return }
        guard photoAttachments.count < Self.maximumPhotoCount else {
            feedback = .photoLimitReached
            return
        }
        guard !item.commentElementID.isEmpty else {
            feedback = .photoFailed
            return
        }

        isSaving = true
        defer { isSaving = false }

        do {
            let localID = try await photoStore.saveJPEG(jpegData)
            let attachment = NotificationPhotoAttachment(
                localAttachmentID: localID,
                checklistItemID: item.id,
                sapElementID: item.commentElementID,
                capturedAt: .now,
                sapDocumentID: UUID().uuidString.uppercased()
            )
            let updated = photoAttachments + [attachment]
            do {
                try await persistPhotoChanges(updated)
            } catch {
                try? await photoStore.delete(id: localID)
                feedback = .photoFailed
                return
            }
            photoAttachments = updated
            photoData[localID] = jpegData
        } catch {
            feedback = .photoFailed
        }
    }

    func removePhoto(_ attachment: NotificationPhotoAttachment) async {
        guard !isEditingDisabled, !isSaving else { return }
        isSaving = true
        defer { isSaving = false }
        let updated = photoAttachments.filter { $0.id != attachment.id }
        do {
            try await persistPhotoChanges(updated)
            photoAttachments = updated
            photoData[attachment.localAttachmentID] = nil
            try? await photoStore.delete(id: attachment.localAttachmentID)
            originalAttachmentIDs.remove(attachment.localAttachmentID)
            removedOriginalAttachmentIDs.remove(attachment.localAttachmentID)
        } catch {
            feedback = .photoFailed
        }
    }

    func updatePhoto(id: String, name: String, description: String) async {
        guard !isEditingDisabled, !isSaving,
              photoAttachments.contains(where: { $0.id == id }) else { return }
        isSaving = true
        defer { isSaving = false }

        let updated = photoAttachments.map {
            $0.id == id ? $0.updatingMetadata(name: name, description: description) : $0
        }
        do {
            try await persistPhotoChanges(updated)
            photoAttachments = updated
        } catch {
            feedback = .photoFailed
        }
    }

    func cancel() async {
        await discardStagedPhotos()
    }

    @discardableResult
    func save(closed: Bool) async -> Bool {
        guard !isSaving, !isEditingDisabled else { return false }
        guard !closed || canClose else {
            feedback = .incomplete
            return false
        }

        isSaving = true
        defer { isSaving = false }
        let processID = closed ? (outgoingProcessID ?? UUID().uuidString.uppercased()) : outgoingProcessID
        let draft = NotificationReviewDraftPayload(
            notificationID: detail.summary.id,
            performedOn: performedOn,
            results: results,
            comments: comments,
            photoAttachments: photoAttachments,
            isClosedLocally: closed,
            notificationSnapshot: OfflineNotificationSnapshot(detail: detail),
            outgoingProcessID: processID,
            pdfData: closed ? reportPDF() : persistedDraft?.pdfData
        )

        do {
            _ = try await offlineWorkStore.saveNotificationReview(draft)
            for id in removedOriginalAttachmentIDs {
                try? await photoStore.delete(id: id)
            }
            originalAttachmentIDs = Set(photoAttachments.map(\.localAttachmentID))
            removedOriginalAttachmentIDs.removeAll()
            outgoingProcessID = processID
            isClosedLocally = closed
            persistedDraft = draft
            // `Rundgang._afterSetMeldung` offers the deficient positions for
            // I2 notifications instead of finishing the form.
            if closed {
                SAPSynchronizationDiagnostics.logI2(
                    "form closed: user may create I2 \(canCreateI2), " +
                        "\(I2NotificationRules.segmentedCandidates(detail: detail, results: results, comments: comments).count) defective position(s) offered"
                )
            }
            let offersI2 = closed && canCreateI2 && i2Selection.present(
                I2NotificationRules.segmentedCandidates(detail: detail, results: results, comments: comments)
            )
            if !offersI2 {
                feedback = closed ? .closedLocally : .savedLocally
            }
            return true
        } catch {
            feedback = .saveFailed
            return false
        }
    }

    /// `Rundgang.buildPDF` / `WartungsPlan.buildPDF` of the closed review,
    /// kept with the draft so the report stays readable from the local-work
    /// and defect lists after the form is closed.
    private func reportPDF() -> Data {
        NotificationReviewReportPDF.render(
            NotificationReviewReportPayload(
                formCode: detail.formCode,
                notificationID: detail.summary.id,
                fields: NotificationReportFields(rawPayloadJSON: detail.summary.rawPayloadJSON),
                items: detail.inspectionItems,
                results: results,
                comments: comments,
                performedOn: performedOn,
                worker: NotificationReportWorker(profile: userProfile, fallbackPersonnelNumber: "")
            )
        )
    }

    /// Stores the notifications chosen in the defect dialog with the closed
    /// review. Returns `false` when nothing was chosen, so the form can be
    /// left straight away as `onDefectPosItemAccept` does.
    func acceptI2Selection() async -> Bool {
        let requests = i2Selection.accept()
        SAPSynchronizationDiagnostics.logI2(
            "dialog accepted with \(requests.count) request(s), closed draft present: " +
                "\(persistedDraft?.isClosedLocally == true)"
        )
        guard !requests.isEmpty, var draft = persistedDraft, draft.isClosedLocally else { return false }
        isSaving = true
        defer { isSaving = false }
        draft.i2Requests = requests
        do {
            _ = try await offlineWorkStore.saveNotificationReview(draft)
            SAPSynchronizationDiagnostics.logI2("stored \(requests.count) request(s) with the closed form")
            persistedDraft = draft
            feedback = .i2NotificationsQueued
        } catch {
            feedback = .saveFailed
        }
        return true
    }

    func cancelI2Selection() {
        i2Selection.cancel()
    }

    private func discardStagedPhotos() async {
        let currentIDs = Set(photoAttachments.map(\.localAttachmentID))
        for id in currentIDs.subtracting(originalAttachmentIDs) {
            try? await photoStore.delete(id: id)
        }
    }

    /// Photo actions are independently auto-saved. Existing persisted answers,
    /// comments, and date are retained so taking a photo does not accidentally
    /// commit unrelated edits still in the review UI.
    private func persistPhotoChanges(_ attachments: [NotificationPhotoAttachment]) async throws {
        var draft = persistedDraft ?? NotificationReviewDraftPayload(
            notificationID: detail.summary.id,
            performedOn: performedOn,
            results: [:],
            comments: [:],
            photoAttachments: [],
            isClosedLocally: false,
            notificationSnapshot: OfflineNotificationSnapshot(detail: detail),
            outgoingProcessID: nil
        )
        draft.photoAttachments = attachments
        _ = try await offlineWorkStore.saveNotificationReview(draft)
        persistedDraft = draft
        originalAttachmentIDs = Set(attachments.map(\.localAttachmentID))
        removedOriginalAttachmentIDs.removeAll()
    }
}
