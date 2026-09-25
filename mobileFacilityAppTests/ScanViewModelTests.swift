import XCTest
@testable import mobileFacilityApp

@MainActor
final class ScanViewModelTests: XCTestCase {
    private let code = LegacyQRCodeCodec.encodeMTFM(functionalLocationID: "FL-1")

    func testCancellingARescanKeepsEarlierResults() async throws {
        var openedIDs: [String] = []
        let viewModel = try await makeViewModel(notificationIDs: ["4711", "4712"]) { openedIDs.append($0.id) }

        try await scan(code, with: viewModel)
        guard case let .results(lookup) = viewModel.state else {
            return XCTFail("Expected results, got \(viewModel.state)")
        }
        XCTAssertEqual(lookup.matches.map(\.id), ["4711", "4712"])
        XCTAssertTrue(openedIDs.isEmpty)

        viewModel.startQRCodeScan()
        XCTAssertTrue(viewModel.cameraShouldRun)
        viewModel.cancel()

        XCTAssertEqual(viewModel.state, .results(lookup))
    }

    func testSingleMatchOpensOnlyForANewLookup() async throws {
        var openedIDs: [String] = []
        let viewModel = try await makeViewModel(notificationIDs: ["4711"]) { openedIDs.append($0.id) }

        try await scan(code, with: viewModel)
        XCTAssertEqual(openedIDs, ["4711"])

        viewModel.startQRCodeScan()
        viewModel.cancel()

        guard case .results = viewModel.state else {
            return XCTFail("Expected restored results, got \(viewModel.state)")
        }
        XCTAssertEqual(openedIDs, ["4711"])
    }

    func testCodeReadAfterCancelIsIgnored() async throws {
        let viewModel = try await makeViewModel(notificationIDs: ["4711"]) { _ in }

        viewModel.startQRCodeScan()
        viewModel.cancel()
        XCTAssertEqual(viewModel.state, .idle)

        viewModel.accept(code)
        viewModel.cameraFailed(.permissionDenied)
        XCTAssertEqual(viewModel.state, .idle)
    }

    private func scan(_ rawValue: String, with viewModel: ScanViewModel) async throws {
        viewModel.startQRCodeScan()
        viewModel.cameraDidStart()
        viewModel.accept(rawValue)
        var attempts = 0
        while viewModel.state == .resolving, attempts < 200 {
            attempts += 1
            try await Task.sleep(for: .milliseconds(5))
        }
    }

    private func makeViewModel(
        notificationIDs: [String],
        openSingleMatch: @escaping @MainActor (SAPNotificationSummary) -> Void
    ) async throws -> ScanViewModel {
        let notifications = notificationIDs.map { id in
            SAPNotificationSummary(
                id: id, client: "100", title: "Rundgang \(id)",
                functionalLocationID: "FL-1", functionalLocationName: "Building A",
                startDate: "2026-09-01", endDate: "2026-09-30",
                systemStatus: "MOFN", userStatus: "",
                rawPayloadJSON: "{}"
            )
        }
        let store = SAPDataStore(
            repository: InMemorySAPDataCacheRepository(
                seed: SAPCachedData(
                    notifications: notifications,
                    workerProfile: nil,
                    metadata: SAPCacheMetadata(sapWorkerID: "w1", lastSuccessfulRefreshAt: Date())
                ),
                workerID: "w1"
            ),
            refreshService: nil,
            localWorkerID: "w1"
        )
        await store.loadCachedData()
        XCTAssertTrue(store.hasCache)
        return ScanViewModel(sapDataStore: store, isDemoMode: false, openSingleMatch: openSingleMatch)
    }
}
