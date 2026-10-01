import XCTest
@testable import mobileFacilityApp

/// Demo mode and the workspace behind the login must stay mock-only: no SAP
/// refresh service and nothing written to the device. This is an App Store
/// review requirement (see CLAUDE.md, "Startup routing").
@MainActor
final class WorkspaceIsolationTests: XCTestCase {
    private let manualCapture = ManualCaptureDraftPayload(
        categoryKey: "manual.category.issue",
        location: "Building A",
        note: "Demo note"
    )

    func testDemoWorkspaceIsMockOnly() {
        let demo = AppRootView.makeDemoWorkspace()

        XCTAssertTrue(demo.isDemoMode)
        XCTAssertFalse(demo.sapDataStore.isRefreshAvailable, "demo must never reach SAP")
        XCTAssertTrue(demo.photoAttachmentStore is InMemoryPhotoAttachmentStore)
        XCTAssertTrue(demo.documentAttachmentStore is InMemoryDocumentAttachmentStore)
        XCTAssertTrue(demo.meterReferenceProvider is DemoMeterReferenceProvider)
    }

    func testAuthenticationWorkspaceIsMockOnly() {
        let workspace = AppRootView.makeAuthenticationWorkspace()

        XCTAssertFalse(workspace.isDemoMode)
        XCTAssertFalse(workspace.sapDataStore.isRefreshAvailable, "nobody is signed in yet")
        XCTAssertTrue(workspace.photoAttachmentStore is InMemoryPhotoAttachmentStore)
        XCTAssertTrue(workspace.documentAttachmentStore is InMemoryDocumentAttachmentStore)
        XCTAssertTrue(workspace.meterReferenceProvider is FrontendPreviewMeterReferenceProvider)
    }

    /// With a SQLite repository the draft would still be there after the demo
    /// is left and entered again.
    func testDemoWorkIsNotKeptForTheNextDemoSession() async throws {
        let first = AppRootView.makeDemoWorkspace()
        _ = try await first.offlineWorkStore.saveManualCapture(payload: manualCapture)
        XCTAssertEqual(first.offlineWorkStore.activeQueueCount, 1)

        let second = AppRootView.makeDemoWorkspace()
        await second.offlineWorkStore.load()

        XCTAssertEqual(second.offlineWorkStore.activeQueueCount, 0)
    }

    /// Demo has no SAP; its sync button restores the starting demo data.
    func testDemoSyncRestoresTheStartingData() async throws {
        let demo = AppRootView.makeDemoWorkspace()
        _ = try await demo.offlineWorkStore.saveManualCapture(payload: manualCapture)
        demo.notifications[0].status = .attention
        XCTAssertTrue(demo.canSync)

        demo.requestSAPRefresh()
        XCTAssertTrue(demo.isSyncing)
        XCTAssertFalse(demo.canSync, "a second tap must not start another reset")
        for _ in 0..<100 where demo.isSyncing {
            try await Task.sleep(for: .milliseconds(50))
        }
        try await Task.sleep(for: .milliseconds(100))
        await demo.offlineWorkStore.load()

        XCTAssertFalse(demo.isSyncing)
        XCTAssertEqual(demo.notifications, MockFacilityData.notifications)
        XCTAssertEqual(demo.offlineWorkStore.activeQueueCount, 0)
        XCTAssertEqual(demo.selection, .overview)
    }

    func testSyncWithoutSAPDoesNothingOutsideDemo() async throws {
        let workspace = AppRootView.makeAuthenticationWorkspace()
        _ = try await workspace.offlineWorkStore.saveManualCapture(payload: manualCapture)

        XCTAssertFalse(workspace.canSync)
        workspace.requestSAPRefresh()

        XCTAssertFalse(workspace.isSyncing)
        XCTAssertEqual(workspace.offlineWorkStore.activeQueueCount, 1)
    }

    func testWorkBehindTheLoginIsNotKeptForTheNextSignIn() async throws {
        let first = AppRootView.makeAuthenticationWorkspace()
        _ = try await first.offlineWorkStore.saveManualCapture(payload: manualCapture)

        let second = AppRootView.makeAuthenticationWorkspace()
        await second.offlineWorkStore.load()

        XCTAssertEqual(second.offlineWorkStore.activeQueueCount, 0)
    }
}
