import Foundation
import XCTest
@testable import mobileFacilityApp

final class ProfileSettingsNavigationTests: XCTestCase {
    @MainActor
    private func makeViewModel() -> FacilityDemoViewModel {
        FacilityDemoViewModel(
            isDemoMode: true,
            offlineWorkStore: OfflineWorkStore(
                repository: InMemoryOfflineWorkRepository(),
                workerID: "demo"
            ),
            sapDataStore: SAPDataStore(
                repository: InMemorySAPDataCacheRepository(seed: TechnicalObjectDemoData.cachedData),
                refreshService: nil,
                localWorkerID: "demo"
            ),
            meterReferenceProvider: DemoMeterReferenceProvider(),
            photoAttachmentStore: InMemoryPhotoAttachmentStore(),
            workerDisplayName: "Alex Morgan",
            workerRole: .technician
        )
    }

    @MainActor
    func testInitialReturnDestinationIsOverview() {
        let viewModel = makeViewModel()
        XCTAssertEqual(viewModel.selection, .overview)
        XCTAssertEqual(viewModel.profileSettingsReturnDestination, .overview)
    }

    @MainActor
    func testOpenProfileSettingsFromNotificationsSetsReturnDestination() {
        let viewModel = makeViewModel()
        viewModel.open(.notifications)
        XCTAssertEqual(viewModel.selection, .notifications)

        viewModel.openProfileSettings()
        XCTAssertEqual(viewModel.selection, .profileSettings)
        XCTAssertEqual(viewModel.profileSettingsReturnDestination, .notifications)

        viewModel.closeProfileSettings()
        XCTAssertEqual(viewModel.selection, .notifications)
    }

    @MainActor
    func testOpenProfileSettingsViaDestinationOpenMethod() {
        let viewModel = makeViewModel()
        viewModel.open(.defects)
        XCTAssertEqual(viewModel.selection, .defects)

        viewModel.open(.profileSettings)
        XCTAssertEqual(viewModel.selection, .profileSettings)
        XCTAssertEqual(viewModel.profileSettingsReturnDestination, .defects)

        viewModel.closeProfileSettings()
        XCTAssertEqual(viewModel.selection, .defects)
    }

    @MainActor
    func testOpenProfileSettingsViaSelectionBinding() {
        let viewModel = makeViewModel()
        viewModel.selection = .forms
        XCTAssertEqual(viewModel.selection, .forms)

        viewModel.selection = .profileSettings
        XCTAssertEqual(viewModel.selection, .profileSettings)
        XCTAssertEqual(viewModel.profileSettingsReturnDestination, .forms)

        viewModel.closeProfileSettings()
        XCTAssertEqual(viewModel.selection, .forms)
    }

    @MainActor
    func testOpenProfileSettingsDismissesSelectedOfflineNotificationDetail() {
        let viewModel = makeViewModel()
        viewModel.selection = .notifications
        if let summary = TechnicalObjectDemoData.notifications.first {
            viewModel.selectedOfflineNotificationDetail = SAPNotificationDetail(summary: summary)
        }
        XCTAssertNotNil(viewModel.selectedOfflineNotificationDetail)

        viewModel.openProfileSettings()
        XCTAssertNil(viewModel.selectedOfflineNotificationDetail)
        XCTAssertEqual(viewModel.selection, .profileSettings)
        XCTAssertEqual(viewModel.profileSettingsReturnDestination, .notifications)
    }

    func testAppDestinationTitleKeysArePopulated() {
        for destination in AppDestination.allCases {
            XCTAssertFalse(destination.titleKey.isEmpty)
        }
        XCTAssertEqual(AppDestination.notifications.titleKey, "navigation.notifications")
        XCTAssertEqual(AppDestination.overview.titleKey, "navigation.overview")
        XCTAssertEqual(AppDestination.profileSettings.titleKey, "profile.settings.title")
    }
}
