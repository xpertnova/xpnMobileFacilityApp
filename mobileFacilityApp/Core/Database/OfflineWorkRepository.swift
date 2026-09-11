import Foundation

protocol OfflineWorkRepository: Sendable {
    func loadWork(for workerID: String) async throws -> [OfflineWorkItem]
    func save(_ item: OfflineWorkItem) async throws
    func resetWork(for workerID: String) async throws
    func delete(ids: [UUID]) async throws
}

extension OfflineWorkRepository {
    func delete(ids: [UUID]) async throws {
        throw OfflineWorkRepositoryError.unavailable
    }
}

actor InMemoryOfflineWorkRepository: OfflineWorkRepository {
    private var items: [UUID: OfflineWorkItem] = [:]

    func loadWork(for workerID: String) async throws -> [OfflineWorkItem] {
        items.values
            .filter { $0.workerID == workerID }
            .sorted { $0.updatedAt > $1.updatedAt }
    }

    func save(_ item: OfflineWorkItem) async throws {
        items[item.id] = item
    }

    func resetWork(for workerID: String) async throws {
        items = items.filter { $0.value.workerID != workerID }
    }

    func delete(ids: [UUID]) async throws {
        for id in ids { items[id] = nil }
    }

    func reset() {
        items = [:]
    }
}

struct UnavailableOfflineWorkRepository: OfflineWorkRepository {
    func loadWork(for workerID: String) async throws -> [OfflineWorkItem] {
        throw OfflineWorkRepositoryError.unavailable
    }

    func save(_ item: OfflineWorkItem) async throws {
        throw OfflineWorkRepositoryError.unavailable
    }

    func resetWork(for workerID: String) async throws {
        throw OfflineWorkRepositoryError.unavailable
    }

    func delete(ids: [UUID]) async throws {
        throw OfflineWorkRepositoryError.unavailable
    }
}
