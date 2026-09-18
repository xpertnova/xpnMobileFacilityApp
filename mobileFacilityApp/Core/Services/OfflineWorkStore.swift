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
    private(set) var items: [OfflineWorkItem] = [] {
        didSet { revision &+= 1 }
    }
    /// Bumped on every change to `items`. Lists derived from offline work use
    /// it as a cache key instead of rebuilding themselves on every SwiftUI
    /// pass.
    private(set) var revision = 0
    /// Whether `items` has been read from the repository at least once. A
    /// reload keeps the previous items, so counts derived from them stay valid
    /// while `state` is `.loading` again; before the first read they are not
    /// known at all.
    private(set) var hasLoaded = false

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
        activeQueueItems.filter { $0.type == .notificationReview || $0.type == .elevatorInspection }
    }

    /// The Local work screen intentionally contains only notification reviews
    /// that are still drafts or have been closed locally.
    var localWorkNotificationItems: [OfflineWorkItem] {
        savedNotificationItems.filter { item in
            if let review = item.payload.notificationReview {
                return item.status == .draft || review.isClosedLocally
            }
            if let inspection = item.payload.elevatorInspection {
                return item.status == .draft || inspection.isClosedLocally
            }
            return false
        }
    }

    var savedNotificationCount: Int {
        localWorkNotificationItems.count
    }

    var localWorkCount: Int {
        localWorkNotificationItems.count + briefingItems.count + electricalSafetyItems.count
            + technicalObjectEditItems.count + defectItems.count + meterReadingItems.count
            + proofOfQualificationItems.count
            + photoCollectionItems.filter {
                let workflow = $0.payload.photoCollection?.scope.workflow
                return workflow != .mobileLadder && workflow != .subdistribution
            }.count
            + mobileLadderItems.count
            + subdistributionItems.count
    }

    var elevatorInspectionItems: [OfflineWorkItem] {
        activeQueueItems.filter { $0.type == .elevatorInspection }
    }

    var defectItems: [OfflineWorkItem] {
        activeQueueItems.filter { $0.type == .defect }
    }

    var meterReadingItems: [OfflineWorkItem] {
        activeQueueItems.filter { $0.type == .meterReading }
    }

    var briefingItems: [OfflineWorkItem] {
        activeQueueItems.filter { $0.type == .briefing }
    }

    var electricalSafetyItems: [OfflineWorkItem] {
        activeQueueItems.filter { $0.type == .electricalSafety }
    }

    var technicalObjectEditItems: [OfflineWorkItem] {
        activeQueueItems.filter { $0.type == .technicalObjectEdit }
    }

    var proofOfQualificationItems: [OfflineWorkItem] {
        activeQueueItems.filter { $0.type == .proofOfQualification }
    }

    var photoCollectionItems: [OfflineWorkItem] {
        activeQueueItems.filter { $0.type == .photoCollection }
    }

    var mobileLadderItems: [OfflineWorkItem] {
        activeQueueItems.filter { $0.type == .mobileLadder }
    }

    var subdistributionItems: [OfflineWorkItem] {
        activeQueueItems.filter { $0.type == .subdistribution }
    }

    func mobileLadderItem(id: UUID?) -> OfflineWorkItem? {
        guard let id else { return nil }
        return mobileLadderItems.first { $0.id == id }
    }

    func saveMobileLadder(
        id: UUID? = nil,
        payload: MobileLadderDraftPayload,
        status: OfflineWorkStatus
    ) async throws -> OfflineWorkItem {
        let existing = mobileLadderItem(id: id)
        let now = Date()
        let effectiveStatus: OfflineWorkStatus = payload.isClosedLocally == true
            ? .pendingSynchronization
            : status
        let item = OfflineWorkItem(
            id: existing?.id ?? UUID(), workerID: workerID, type: .mobileLadder,
            status: effectiveStatus, payload: .mobileLadder(payload),
            createdAt: existing?.createdAt ?? now, updatedAt: now, syncError: nil
        )
        try await repository.save(item)
        await load()
        return item
    }

    func subdistributionItem(id: UUID?) -> OfflineWorkItem? {
        guard let id else { return nil }
        return subdistributionItems.first { $0.id == id }
    }

    func saveSubdistribution(
        id: UUID? = nil,
        payload: SubdistributionDraftPayload,
        status: OfflineWorkStatus
    ) async throws -> OfflineWorkItem {
        let existing = subdistributionItem(id: id)
        let now = Date()
        let effectiveStatus: OfflineWorkStatus = payload.isClosedLocally
            ? .pendingSynchronization
            : status
        let item = OfflineWorkItem(
            id: existing?.id ?? UUID(), workerID: workerID, type: .subdistribution,
            status: effectiveStatus, payload: .subdistribution(payload),
            createdAt: existing?.createdAt ?? now, updatedAt: now, syncError: nil
        )
        try await repository.save(item)
        await load()
        return item
    }

    func photoCollection(for scope: LocalPhotoScope) -> OfflineWorkItem? {
        photoCollectionItems.first { $0.payload.photoCollection?.scope == scope }
    }

    func savePhotoCollection(
        scope: LocalPhotoScope,
        attachments: [LocalPhotoAttachment],
        retainEmpty: Bool = false
    ) async throws -> OfflineWorkItem? {
        let existing = photoCollection(for: scope)
        if attachments.isEmpty && !retainEmpty {
            if let existing {
                try await repository.delete(ids: [existing.id])
                await load()
            }
            return nil
        }

        let now = Date()
        let item = OfflineWorkItem(
            id: existing?.id ?? UUID(),
            workerID: workerID,
            type: .photoCollection,
            status: .draft,
            payload: .photoCollection(.init(scope: scope, attachments: attachments)),
            createdAt: existing?.createdAt ?? now,
            updatedAt: now,
            syncError: nil
        )
        try await repository.save(item)
        await load()
        return item
    }

    /// A defect is a failed checklist result from a notification that was
    /// closed locally. Open or draft notifications never appear as defects.
    var closedDefectNotificationItems: [OfflineWorkItem] {
        localWorkNotificationItems.filter { item in
            if let review = item.payload.notificationReview {
                return review.isClosedLocally && review.results.values.contains(.yes)
            }
            if let inspection = item.payload.elevatorInspection {
                return inspection.isClosedLocally && (inspection.statusNumber == "2" || inspection.closingUserStatus.contains("Mnot"))
            }
            return false
        }
    }

    var closedDefectNotificationCount: Int {
        closedDefectNotificationItems.count
    }

    var defectCount: Int {
        closedDefectNotificationCount + defectItems.count
    }

    func load() async {
        state = .loading
        do {
            items = try await repository.loadWork(for: workerID)
            hasLoaded = true
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

    func saveDefect(
        id: UUID? = nil,
        payload: DefectDraftPayload,
        status: OfflineWorkStatus
    ) async throws -> OfflineWorkItem {
        let existing = id.flatMap { requestedID in items.first { $0.id == requestedID } }
        let now = Date()
        let item = OfflineWorkItem(
            id: existing?.id ?? UUID(),
            workerID: workerID,
            type: .defect,
            status: status,
            payload: .defect(payload),
            createdAt: existing?.createdAt ?? now,
            updatedAt: now,
            syncError: nil
        )
        try await repository.save(item)
        await load()
        return item
    }

    func saveMeterReading(
        id: UUID? = nil,
        payload: MeterReadingDraftPayload,
        status: OfflineWorkStatus
    ) async throws -> OfflineWorkItem {
        let existing = id.flatMap { requestedID in items.first { $0.id == requestedID } }
        let now = Date()
        let item = OfflineWorkItem(
            id: existing?.id ?? UUID(),
            workerID: workerID,
            type: .meterReading,
            status: status,
            payload: .meterReading(payload),
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
            status: payload.isClosedLocally ? .pendingSynchronization : .draft,
            payload: .notificationReview(payload),
            createdAt: existing?.createdAt ?? now,
            updatedAt: now,
            syncError: nil
        )
        try await repository.save(item)
        await load()
        return item
    }

    func elevatorInspection(notificationID: String) -> ElevatorInspectionDraftPayload? {
        items.first {
            $0.type == .elevatorInspection && $0.payload.elevatorInspection?.notificationID == notificationID
        }?.payload.elevatorInspection
    }

    func saveElevatorInspection(_ payload: ElevatorInspectionDraftPayload) async throws -> OfflineWorkItem {
        let existing = items.first {
            $0.type == .elevatorInspection && $0.payload.elevatorInspection?.notificationID == payload.notificationID
        }
        let now = Date()
        let item = OfflineWorkItem(
            id: existing?.id ?? UUID(),
            workerID: workerID,
            type: .elevatorInspection,
            status: payload.isClosedLocally ? .pendingSynchronization : .draft,
            payload: .elevatorInspection(payload),
            createdAt: existing?.createdAt ?? now,
            updatedAt: now,
            syncError: nil
        )
        try await repository.save(item)
        await load()
        return item
    }

    func deleteElevatorInspection(notificationID: String) async throws {
        let matching = items.filter {
            $0.type == .elevatorInspection && $0.payload.elevatorInspection?.notificationID == notificationID
        }
        if !matching.isEmpty {
            try await repository.delete(ids: matching.map(\.id))
            await load()
        }
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

    func technicalObjectEdit(equipmentID: String) -> OfflineWorkItem? {
        technicalObjectEditItems.first { $0.payload.technicalObjectEdit?.equipmentID == equipmentID }
    }

    func saveTechnicalObjectEdit(
        _ payload: TechnicalObjectEditPayload,
        status: OfflineWorkStatus = .pendingSynchronization
    ) async throws -> OfflineWorkItem {
        let existing = technicalObjectEdit(equipmentID: payload.equipmentID)
        let now = Date()
        let item = OfflineWorkItem(
            id: existing?.id ?? UUID(), workerID: workerID, type: .technicalObjectEdit,
            status: status, payload: .technicalObjectEdit(payload),
            createdAt: existing?.createdAt ?? now, updatedAt: now, syncError: nil
        )
        try await repository.save(item)
        await load()
        return item
    }

    func saveProofOfQualification(
        id: UUID? = nil,
        payload: ProofOfQualificationDraftPayload,
        status: OfflineWorkStatus = .draft
    ) async throws -> OfflineWorkItem {
        let existing = id.flatMap { requestedID in items.first { $0.id == requestedID } }
        let now = Date()
        let item = OfflineWorkItem(
            id: existing?.id ?? UUID(),
            workerID: workerID,
            type: .proofOfQualification,
            status: status,
            payload: .proofOfQualification(payload),
            createdAt: existing?.createdAt ?? now,
            updatedAt: now,
            syncError: nil
        )
        try await repository.save(item)
        await load()
        return item
    }

    func reset() async {
        do {
            try await repository.resetWork(for: workerID)
            await load()
        } catch {
            state = .failed
        }
    }
    func item(id: UUID?) -> OfflineWorkItem? {
        guard let id else { return nil }
        return items.first { $0.id == id }
    }
}
