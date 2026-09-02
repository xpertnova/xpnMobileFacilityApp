import Foundation
import Observation

@MainActor
@Observable
final class OfflineWorkStore {
    enum State: Equatable {
        case loading
        case empty
        case loaded
        case failed
    }

    private let repository: any OfflineWorkRepository
    let workerID: String
    private(set) var state: State = .loading
    private(set) var items: [OfflineWorkItem] = []

    init(repository: any OfflineWorkRepository, workerID: String) {
        self.repository = repository
        self.workerID = workerID
    }

    /// Work still kept on the device. A server-confirmed item is deliberately
    /// excluded from the temporary-save queue.
    var activeQueueItems: [OfflineWorkItem] {
        items.filter { $0.status != .synchronized }
    }

    var activeQueueCount: Int {
        activeQueueItems.count
    }

    var savedNotificationItems: [OfflineWorkItem] {
        activeQueueItems.filter { $0.type == .notificationReview }
    }

    /// The Local work screen intentionally contains only notification reviews
    /// that are still drafts or have been closed locally.
    var localWorkNotificationItems: [OfflineWorkItem] {
        savedNotificationItems.filter { item in
            guard let review = item.payload.notificationReview else { return false }
            return item.status == .draft || review.isClosedLocally
        }
    }

    var savedNotificationCount: Int {
        localWorkNotificationItems.count
    }

    var localWorkCount: Int {
        localWorkNotificationItems.count + briefingItems.count + electricalSafetyItems.count
    }

    var briefingItems: [OfflineWorkItem] {
        activeQueueItems.filter { $0.type == .briefing }
    }

    var electricalSafetyItems: [OfflineWorkItem] {
        activeQueueItems.filter { $0.type == .electricalSafety }
    }

    /// A defect is a failed checklist result from a notification that was
    /// closed locally. Open or draft notifications never appear as defects.
    var closedDefectNotificationItems: [OfflineWorkItem] {
        localWorkNotificationItems.filter { item in
            guard let review = item.payload.notificationReview else { return false }
            return review.isClosedLocally && review.results.values.contains(.yes)
        }
    }

    var closedDefectNotificationCount: Int {
        closedDefectNotificationItems.count
    }

    func load() async {
        state = .loading
        do {
            items = try await repository.loadWork(for: workerID)
            state = items.isEmpty ? .empty : .loaded
        } catch is CancellationError {
            return
        } catch {
            state = .failed
        }
    }

    func saveManualCapture(
        id: UUID? = nil,
        payload: ManualCaptureDraftPayload
    ) async throws -> OfflineWorkItem {
        let existing = id.flatMap { requestedID in items.first { $0.id == requestedID } }
        let now = Date()
        let item = OfflineWorkItem(
            id: existing?.id ?? UUID(),
            workerID: workerID,
            type: .manualCapture,
            status: .draft,
            payload: .manualCapture(payload),
            createdAt: existing?.createdAt ?? now,
            updatedAt: now,
            syncError: nil
        )
        try await repository.save(item)
        await load()
        return item
    }

    func notificationReview(notificationID: String) -> NotificationReviewDraftPayload? {
        items.first {
            $0.type == .notificationReview && $0.payload.notificationReview?.notificationID == notificationID
        }?.payload.notificationReview
    }

    func saveNotificationReview(_ payload: NotificationReviewDraftPayload) async throws -> OfflineWorkItem {
        let existing = items.first {
            $0.type == .notificationReview && $0.payload.notificationReview?.notificationID == payload.notificationID
        }
        let now = Date()
        let item = OfflineWorkItem(
            id: existing?.id ?? UUID(),
            workerID: workerID,
            type: .notificationReview,
            status: .draft,
            payload: .notificationReview(payload),
            createdAt: existing?.createdAt ?? now,
            updatedAt: now,
            syncError: nil
        )
        try await repository.save(item)
        await load()
        return item
    }

    func saveBriefing(
        id: UUID? = nil,
        payload: BriefingDraftPayload,
        status: OfflineWorkStatus = .draft
    ) async throws -> OfflineWorkItem {
        let existing = id.flatMap { requestedID in items.first { $0.id == requestedID } }
        let now = Date()
        let item = OfflineWorkItem(
            id: existing?.id ?? UUID(),
            workerID: workerID,
            type: .briefing,
            status: status,
            payload: .briefing(payload),
            createdAt: existing?.createdAt ?? now,
            updatedAt: now,
            syncError: nil
        )
        try await repository.save(item)
        await load()
        return item
    }

    func saveElectricalSafety(
        id: UUID? = nil,
        payload: ElectricalSafetyDraftPayload,
        status: OfflineWorkStatus = .draft
    ) async throws -> OfflineWorkItem {
        let existing = id.flatMap { requestedID in items.first { $0.id == requestedID } }
        let now = Date()
        let item = OfflineWorkItem(
            id: existing?.id ?? UUID(),
            workerID: workerID,
            type: .electricalSafety,
            status: status,
            payload: .electricalSafety(payload),
            createdAt: existing?.createdAt ?? now,
            updatedAt: now,
            syncError: nil
        )
        try await repository.save(item)
        await load()
        return item
    }

    func item(id: UUID?) -> OfflineWorkItem? {
        guard let id else { return nil }
        return items.first { $0.id == id }
    }
}
