import Foundation
import UniformTypeIdentifiers

struct ImportedDocumentFile: Equatable, Sendable {
    let id: String
    let fileName: String
    let contentType: String
    let byteCount: Int
}

/// Stores files a technician attaches to a technical place. The files never
/// leave the device; see `LocalDocumentAttachment`.
protocol DocumentAttachmentStore: Sendable {
    /// Copies the file at `url` into app storage. The caller keeps any
    /// security-scoped access to `url` open for the duration of the call.
    func importFile(from url: URL, maximumByteCount: Int) async throws -> ImportedDocumentFile
    /// A readable file named like the original, for Quick Look.
    func fileURL(id: String, fileName: String) async throws -> URL
    func delete(id: String) async throws
    func reset() async throws
}

enum DocumentAttachmentStoreError: Error {
    case unavailable
    case tooLarge
}

private extension URL {
    /// Size and type of a picked file, read before it is copied.
    func documentMetadata() throws -> (byteCount: Int, contentType: String) {
        let values = try resourceValues(forKeys: [.fileSizeKey, .contentTypeKey])
        let contentType = values.contentType
            ?? UTType(filenameExtension: pathExtension)
            ?? .data
        return (values.fileSize ?? 0, contentType.identifier)
    }
}

actor FileDocumentAttachmentStore: DocumentAttachmentStore {
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
            self.directory = applicationSupport.appendingPathComponent("LocalDocuments", isDirectory: true)
        }
        try FileManager.default.createDirectory(at: self.directory, withIntermediateDirectories: true)
    }

    func importFile(from url: URL, maximumByteCount: Int) async throws -> ImportedDocumentFile {
        let metadata = try url.documentMetadata()
        guard metadata.byteCount <= maximumByteCount else { throw DocumentAttachmentStoreError.tooLarge }

        let id = UUID().uuidString
        let fileName = url.lastPathComponent
        // One folder per document keeps the original file name for Quick Look
        // and the share sheet, even when two files share a name.
        let folder = directory.appendingPathComponent(id, isDirectory: true)
        do {
            try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
            try FileManager.default.copyItem(at: url, to: folder.appendingPathComponent(fileName))
        } catch {
            try? FileManager.default.removeItem(at: folder)
            throw DocumentAttachmentStoreError.unavailable
        }
        return ImportedDocumentFile(
            id: id,
            fileName: fileName,
            contentType: metadata.contentType,
            byteCount: metadata.byteCount
        )
    }

    func fileURL(id: String, fileName: String) async throws -> URL {
        let file = directory.appendingPathComponent(id, isDirectory: true).appendingPathComponent(fileName)
        guard FileManager.default.fileExists(atPath: file.path) else {
            throw DocumentAttachmentStoreError.unavailable
        }
        return file
    }

    func delete(id: String) async throws {
        let folder = directory.appendingPathComponent(id, isDirectory: true)
        guard FileManager.default.fileExists(atPath: folder.path) else { return }
        try FileManager.default.removeItem(at: folder)
    }

    func reset() async throws {
        guard FileManager.default.fileExists(atPath: directory.path) else { return }
        for folder in try FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil) {
            try FileManager.default.removeItem(at: folder)
        }
    }
}

/// Demo storage. Files live in memory and are written to a temporary folder
/// only when someone opens one.
actor InMemoryDocumentAttachmentStore: DocumentAttachmentStore {
    private var values: [String: Data] = [:]
    private let previewDirectory = FileManager.default.temporaryDirectory
        .appendingPathComponent("DemoDocuments-\(UUID().uuidString)", isDirectory: true)

    func importFile(from url: URL, maximumByteCount: Int) async throws -> ImportedDocumentFile {
        let metadata = try url.documentMetadata()
        guard metadata.byteCount <= maximumByteCount else { throw DocumentAttachmentStoreError.tooLarge }
        guard let data = try? Data(contentsOf: url) else { throw DocumentAttachmentStoreError.unavailable }
        let id = UUID().uuidString
        values[id] = data
        return ImportedDocumentFile(
            id: id,
            fileName: url.lastPathComponent,
            contentType: metadata.contentType,
            byteCount: data.count
        )
    }

    func fileURL(id: String, fileName: String) async throws -> URL {
        guard let data = values[id] else { throw DocumentAttachmentStoreError.unavailable }
        let folder = previewDirectory.appendingPathComponent(id, isDirectory: true)
        let file = folder.appendingPathComponent(fileName)
        do {
            try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
            try data.write(to: file, options: .atomic)
        } catch {
            throw DocumentAttachmentStoreError.unavailable
        }
        return file
    }

    func delete(id: String) async throws {
        values[id] = nil
        try? FileManager.default.removeItem(at: previewDirectory.appendingPathComponent(id, isDirectory: true))
    }

    func reset() async throws {
        values = [:]
        try? FileManager.default.removeItem(at: previewDirectory)
    }
}

struct UnavailableDocumentAttachmentStore: DocumentAttachmentStore {
    func importFile(from url: URL, maximumByteCount: Int) async throws -> ImportedDocumentFile {
        throw DocumentAttachmentStoreError.unavailable
    }
    func fileURL(id: String, fileName: String) async throws -> URL { throw DocumentAttachmentStoreError.unavailable }
    func delete(id: String) async throws { throw DocumentAttachmentStoreError.unavailable }
    func reset() async throws { throw DocumentAttachmentStoreError.unavailable }
}
