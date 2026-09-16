import Foundation
import Observation

@MainActor
@Observable
final class WartungsplanViewModel {
    static let maximumPhotoCount = 20

    enum Feedback: Identifiable, Equatable {
        case savedLocally
        case closedLocally
        case incomplete
        case commentRequired
        case saveFailed
        case photoFailed
        case photoLimitReached
        case cameraUnavailable
        case cameraPermissionDenied

        var id: String { String(describing: self) }
    }

    let detail: SAPNotificationDetail
    private let offlineWorkStore: OfflineWorkStore
    private let photoStore: any PhotoAttachmentStore
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

    init(
        detail: SAPNotificationDetail,
        offlineWorkStore: OfflineWorkStore,
        photoStore: any PhotoAttachmentStore
    ) {
        self.detail = detail
        self.offlineWorkStore = offlineWorkStore
        self.photoStore = photoStore
    }

    var canClose: Bool {
        guard !detail.inspectionItems.isEmpty else { return false }
        let allAnswered = detail.inspectionItems.allSatisfy { results[$0.id] != nil }
        guard allAnswered else { return false }
        // For Wartungsplan (TFM1), every defective position requires a non-empty comment.
        return detail.inspectionItems.allSatisfy { item in
            guard results[item.id] == .yes else { return true }
            let comment = comments[item.id]?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            return !comment.isEmpty
        }
    }

    var isEditingDisabled: Bool { isLoading || isClosedLocally }

    func isCommentMissing(for itemID: String) -> Bool {
        guard results[itemID] == .yes else { return false }
        let comment = comments[itemID]?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return comment.isEmpty
    }

    func markEverythingOkay() {
        guard !isEditingDisabled, !isSaving else { return }
        for item in detail.inspectionItems {
            results[item.id] = .no
        }
    }

    func attachments(for checklistItemID: String) -> [NotificationPhotoAttachment] {
        photoAttachments.filter { $0.checklistItemID == checklistItemID }
    }

    func load() async {
        isLoading = true
        defer { isLoading = false }
        await discardStagedPhotos()
        await offlineWorkStore.load()
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
        if closed {
            let allAnswered = detail.inspectionItems.allSatisfy { results[$0.id] != nil }
            guard allAnswered else {
                feedback = .incomplete
                return false
            }
            let hasCommentForDefects = detail.inspectionItems.allSatisfy { item in
                guard results[item.id] == .yes else { return true }
                let comment = comments[item.id]?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
                return !comment.isEmpty
            }
            guard hasCommentForDefects else {
                feedback = .commentRequired
                return false
            }
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
            outgoingProcessID: processID
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
            feedback = closed ? .closedLocally : .savedLocally
            return true
        } catch {
            feedback = .saveFailed
            return false
        }
    }

    private func discardStagedPhotos() async {
        let currentIDs = Set(photoAttachments.map(\.localAttachmentID))
        for id in currentIDs.subtracting(originalAttachmentIDs) {
            try? await photoStore.delete(id: id)
        }
    }

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
        draft.results = results
        draft.comments = comments
        draft.performedOn = performedOn
        _ = try await offlineWorkStore.saveNotificationReview(draft)
        persistedDraft = draft
    }
}
