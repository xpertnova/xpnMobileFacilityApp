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

    var draftCount: Int {
        items.filter { $0.status == .draft }.count
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
            payload: payload,
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
