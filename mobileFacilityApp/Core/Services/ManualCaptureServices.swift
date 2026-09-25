import Foundation

protocol MeterReferenceProviding: Sendable {
    var isPreviewData: Bool { get }
    func references(for kind: MeterKind) async throws -> [MeterReference]
}

extension MeterReferenceProviding {
    var isPreviewData: Bool { false }
}

enum MeterReferenceError: LocalizedError {
    case unavailable

    var errorDescription: String? {
        String(localized: "manual.meter.unavailable.message")
    }
}

private enum MeterReferencePreviewFixtures {
    private static let previousReadingAt = Calendar(identifier: .gregorian).date(
        from: DateComponents(timeZone: TimeZone(secondsFromGMT: 0), year: 2026, month: 8, day: 28, hour: 9)
    ) ?? Date(timeIntervalSince1970: 1_777_370_400)

    static let values: [MeterReference] = [
        MeterReference(
            id: "MP-E-1001",
            kind: .electricity,
            technicalPlaceID: "UN01-ST01-PH01-TECH-440",
            technicalPlaceName: "Elektrotechnik",
            unit: "kWh",
            previousValue: Decimal(48_212),
            previousReadingAt: previousReadingAt
        ),
        MeterReference(
            id: "MP-G-1001",
            kind: .gas,
            technicalPlaceID: "UN01-ST01-BG01-TECH-420-Z",
            technicalPlaceName: "Zentrale Wärmeversorgung",
            unit: "m³",
            previousValue: Decimal(12_842),
            previousReadingAt: previousReadingAt
        ),
        MeterReference(
            id: "MP-W-1001",
            kind: .water,
            technicalPlaceID: "UN01-ST01-BG01-TECH-410-SAN1",
            technicalPlaceName: "Sanitäranlage Erdgeschoss",
            unit: "m³",
            previousValue: Decimal(7_416),
            previousReadingAt: previousReadingAt
        )
    ]
}

struct DemoMeterReferenceProvider: MeterReferenceProviding {
    func references(for kind: MeterKind) async throws -> [MeterReference] {
        MeterReferencePreviewFixtures.values.filter { $0.kind == kind }
    }
}

/// Temporary read-only data source used to review the production UI before
/// the legacy T0274 SAP contract is connected. It is intentionally distinct
/// from both the isolated Demo provider and the future production SAP adapter.
struct FrontendPreviewMeterReferenceProvider: MeterReferenceProviding {
    var isPreviewData: Bool { true }

    func references(for kind: MeterKind) async throws -> [MeterReference] {
        MeterReferencePreviewFixtures.values.filter { $0.kind == kind }
    }
}

/// The measuring points of `FROM_T0274`, the source the Rundgang reading
/// screen uses. A reading saved from them goes to SAP as `TO_T0286`.
struct SAPMeterReferenceProvider: MeterReferenceProviding {
    let sapDataStore: SAPDataStore

    func references(for kind: MeterKind) async throws -> [MeterReference] {
        let pointsByLocation = try await sapDataStore.loadAllMeasuringPoints()
        return pointsByLocation.keys.sorted().flatMap { locationID in
            (pointsByLocation[locationID] ?? []).compactMap { point -> MeterReference? in
                guard MeterKind(position: point.position, unit: point.unit) == kind else { return nil }
                return MeterReference(point: point, locationID: locationID)
            }
        }
    }
}

struct UnavailableMeterReferenceProvider: MeterReferenceProviding {
    func references(for kind: MeterKind) async throws -> [MeterReference] {
        throw MeterReferenceError.unavailable
    }
}

protocol PhotoAttachmentStore: Sendable {
    func saveJPEG(_ data: Data) async throws -> String
    func loadJPEG(id: String) async throws -> Data
    func delete(id: String) async throws
    func reset() async throws
}

enum PhotoAttachmentStoreError: Error {
    case unavailable
}

actor FilePhotoAttachmentStore: PhotoAttachmentStore {
    private let directory: URL

    init(directory: URL? = nil) throws {
        if let directory {
            self.directory = directory
        } else {
            let applicationSupport = try FileManager.default.url(
                for: .applicationSupportDirectory,
                in: .userDomainMask,
                appropriateFor: nil,
                create: true
            )
            self.directory = applicationSupport.appendingPathComponent("ManualCapturePhotos", isDirectory: true)
        }
        try FileManager.default.createDirectory(at: self.directory, withIntermediateDirectories: true)
    }

    func saveJPEG(_ data: Data) async throws -> String {
        let id = UUID().uuidString
        do {
            try data.write(to: url(for: id), options: .atomic)
            return id
        } catch {
            throw PhotoAttachmentStoreError.unavailable
        }
    }

    func loadJPEG(id: String) async throws -> Data {
        do {
            return try Data(contentsOf: url(for: id))
        } catch {
            throw PhotoAttachmentStoreError.unavailable
        }
    }

    func delete(id: String) async throws {
        let file = url(for: id)
        guard FileManager.default.fileExists(atPath: file.path) else { return }
        try FileManager.default.removeItem(at: file)
    }

    func reset() async throws {
        guard FileManager.default.fileExists(atPath: directory.path) else { return }
        let files = try FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil)
        for file in files where file.pathExtension == "jpg" {
            try FileManager.default.removeItem(at: file)
        }
    }

    private func url(for id: String) -> URL {
        directory.appendingPathComponent(id).appendingPathExtension("jpg")
    }
}

actor InMemoryPhotoAttachmentStore: PhotoAttachmentStore {
    private var values: [String: Data] = [:]

    func saveJPEG(_ data: Data) async throws -> String {
        let id = UUID().uuidString
        values[id] = data
        return id
    }

    func loadJPEG(id: String) async throws -> Data {
        guard let data = values[id] else { throw PhotoAttachmentStoreError.unavailable }
        return data
    }

    func delete(id: String) async throws {
        values[id] = nil
    }

    func reset() async throws {
        values = [:]
    }
}

struct UnavailablePhotoAttachmentStore: PhotoAttachmentStore {
    func saveJPEG(_ data: Data) async throws -> String { throw PhotoAttachmentStoreError.unavailable }
    func loadJPEG(id: String) async throws -> Data { throw PhotoAttachmentStoreError.unavailable }
    func delete(id: String) async throws { throw PhotoAttachmentStoreError.unavailable }
    func reset() async throws { throw PhotoAttachmentStoreError.unavailable }
}
