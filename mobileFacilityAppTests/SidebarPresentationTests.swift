import XCTest
import SwiftUI
@testable import mobileFacilityApp

final class SidebarPresentationTests: XCTestCase {
    @MainActor
    func testDefectsDestinationRendersAfterNavigationWithOnlyEquipmentDefects() async throws {
        let store = OfflineWorkStore(repository: InMemoryOfflineWorkRepository(), workerID: "demo")
        let summary = try XCTUnwrap(MockFacilityData.sapNotifications.first { $0.id == "4710000012" })
        _ = try await store.saveElevatorInspection(ElevatorInspectionDraftPayload(
            notificationID: summary.id,
            isClosedLocally: true,
            closingUserStatus: "Mnot",
            statusNumber: "2",
            notificationSnapshot: OfflineNotificationSnapshot(detail: SAPNotificationDetail(summary: summary)),
            formCode: "TFM2"
        ))
        let model = FacilityDemoViewModel(
            isDemoMode: true, offlineWorkStore: store,
            sapDataStore: SAPDataStore(repository: InMemorySAPDataCacheRepository(seed: TechnicalObjectDemoData.cachedData), refreshService: nil, localWorkerID: "demo"),
            meterReferenceProvider: DemoMeterReferenceProvider(), photoAttachmentStore: InMemoryPhotoAttachmentStore()
        )
        let size = CGSize(width: 1376, height: 1032)
        let host = UIHostingController(rootView: FacilityShellView(demo: model)
            .environment(\.facilityLayout, FacilityLayoutMetrics(windowSize: size))
            .environment(\.locale, Locale(identifier: "de")))
        let scene = try XCTUnwrap(UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first)
        let previousWindow = scene.keyWindow
        let window = UIWindow(windowScene: scene)
        window.frame = CGRect(origin: .zero, size: size)
        window.rootViewController = host
        window.makeKeyAndVisible()
        defer {
            window.isHidden = true
            previousWindow?.makeKey()
        }
        try await Task.sleep(for: .milliseconds(400))
        model.open(.defects)
        try await Task.sleep(for: .milliseconds(700))
        func assertVisibleDefectsContent(name: String) throws {
            host.view.layoutIfNeeded()
            let format = UIGraphicsImageRendererFormat()
            format.scale = 1
            let image = UIGraphicsImageRenderer(size: size, format: format).image { _ in
                host.view.drawHierarchy(in: CGRect(origin: .zero, size: size), afterScreenUpdates: true)
            }
            let attachment = XCTAttachment(image: image)
            attachment.name = name
            attachment.lifetime = .keepAlways
            add(attachment)
            let cgImage = try XCTUnwrap(image.cgImage)
            let bytes = try XCTUnwrap(cgImage.dataProvider?.data) as Data
            var colors = Set<Data>()
            for y in stride(from: 40, to: 350, by: 4) {
                for x in stride(from: 400, to: 1300, by: 4) {
                    let offset = y * cgImage.bytesPerRow + x * cgImage.bitsPerPixel / 8
                    colors.insert(bytes.subdata(in: offset..<(offset + 3)))
                }
            }
            XCTAssertGreaterThan(colors.count, 20, "The Defects content area must render more than a solid background.")
        }
        try assertVisibleDefectsContent(name: "Defects equipment-only list")
        await store.reset()
        model.open(.overview)
        try await Task.sleep(for: .milliseconds(400))
        model.open(.defects)
        try await Task.sleep(for: .milliseconds(700))
        try assertVisibleDefectsContent(name: "Defects empty state after navigation")
    }

    @MainActor
    func testSidebarStartsExpanded() {
        let viewModel = FacilityDemoViewModel(
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
            photoAttachmentStore: InMemoryPhotoAttachmentStore()
        )

        XCTAssertTrue(viewModel.isSidebarExpanded)
    }

    func testCompactBadgeDisplaysZero() {
        XCTAssertEqual(CompactSidebarBadgeFormatter.text(for: 0), "0")
    }

    func testCompactBadgeDisplaysTwoDigits() {
        XCTAssertEqual(CompactSidebarBadgeFormatter.text(for: 42), "42")
    }

    func testCompactBadgeCapsAtNinetyNinePlus() {
        XCTAssertEqual(CompactSidebarBadgeFormatter.text(for: 100), "99+")
    }
}
