import Foundation
import XCTest
@testable import mobileFacilityApp

final class LocalDocumentTests: XCTestCase {
    private var temporaryURLs: [URL] = []

    override func tearDown() {
        for url in temporaryURLs { try? FileManager.default.removeItem(at: url) }
        temporaryURLs = []
        super.tearDown()
    }

    private func temporaryURL(_ name: String = UUID().uuidString) -> URL {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(name)
        temporaryURLs.append(url)
        return url
    }

    private func samplePDF(named name: String = "Wartungsplan.pdf", byteCount: Int = 64) throws -> URL {
        let folder = temporaryURL()
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let file = folder.appendingPathComponent(name)
        try Data(repeating: 0x25, count: byteCount).write(to: file)
        return file
    }

    private func scope(_ objectID: String = "DR-ZUL-11166") -> LocalPhotoScope {
        LocalPhotoScope(workflow: .technicalObject, ownerID: objectID, displayTitle: "Documents")
    }

    func testFileStoreKeepsOriginalNameAndDeletes() async throws {
        let store = try FileDocumentAttachmentStore(directory: temporaryURL())
        let source = try samplePDF()

        let file = try await store.importFile(from: source, maximumByteCount: 1_024)
        XCTAssertEqual(file.fileName, "Wartungsplan.pdf")
        XCTAssertEqual(file.contentType, "com.adobe.pdf")
        XCTAssertEqual(file.byteCount, 64)

        let stored = try await store.fileURL(id: file.id, fileName: file.fileName)
        XCTAssertEqual(stored.lastPathComponent, "Wartungsplan.pdf")
        XCTAssertEqual(try Data(contentsOf: stored).count, 64)

        try await store.delete(id: file.id)
        do {
            _ = try await store.fileURL(id: file.id, fileName: file.fileName)
            XCTFail("A deleted document must not be readable")
        } catch {}
    }

    func testFileStoreRejectsFilesAboveTheLimit() async throws {
        let store = try FileDocumentAttachmentStore(directory: temporaryURL())
        let source = try samplePDF(byteCount: 2_048)

        do {
            _ = try await store.importFile(from: source, maximumByteCount: 1_024)
            XCTFail("An oversized file must be rejected")
        } catch DocumentAttachmentStoreError.tooLarge {
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
    }

    func testDocumentCollectionRoundTripsThroughSQLite() async throws {
        let url = temporaryURL().appendingPathExtension("sqlite")
        let repository = try SQLiteOfflineWorkRepository(databaseURL: url)
        let now = Date()
        let document = LocalDocumentAttachment(
            localAttachmentID: "doc-1", fileName: "Plan.pdf", contentType: "com.adobe.pdf",
            byteCount: 10, addedAt: now
        )
        let item = OfflineWorkItem(
            id: UUID(), workerID: "worker", type: .documentCollection, status: .draft,
            payload: .documentCollection(.init(scope: scope(), documents: [document])),
            createdAt: now, updatedAt: now, syncError: nil
        )

        try await repository.save(item)
        let loaded = try await repository.loadWork(for: "worker")

        XCTAssertEqual(loaded.first?.payload.documentCollection?.documents.map(\.fileName), ["Plan.pdf"])
        XCTAssertTrue(OfflineWorkType.documentCollection.staysLocal)
    }

    @MainActor
    func testDocumentsAreLocalOnlyAndNotCountedAsLocalWork() async throws {
        let store = OfflineWorkStore(repository: InMemoryOfflineWorkRepository(), workerID: "worker")
        let model = LocalDocumentCollectionViewModel(
            scope: scope(),
            offlineWorkStore: store,
            documentStore: InMemoryDocumentAttachmentStore()
        )
        await model.load()

        await model.importFiles([try samplePDF()])

        XCTAssertEqual(model.documents.map(\.fileName), ["Wartungsplan.pdf"])
        XCTAssertEqual(store.documentCollection(for: scope())?.status, .draft)
        XCTAssertEqual(store.localWorkCount, 0)
        XCTAssertNil(store.documentCollection(for: scope("OTHER")))

        let id = try XCTUnwrap(model.documents.first?.id)
        await model.remove(id: id)
        XCTAssertTrue(model.documents.isEmpty)
        XCTAssertNil(store.documentCollection(for: scope()))
    }
}
