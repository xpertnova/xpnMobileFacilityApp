import SwiftUI

@main
struct MobileFacilityApp: App {
    private let productionOfflineWorkRepository: any OfflineWorkRepository
    private let productionSAPDataCacheRepository: any SAPDataCacheRepository

    init() {
        do {
            productionOfflineWorkRepository = try SQLiteOfflineWorkRepository()
        } catch {
            productionOfflineWorkRepository = UnavailableOfflineWorkRepository()
        }
        do {
            productionSAPDataCacheRepository = try SQLiteSAPDataCacheRepository()
        } catch {
            productionSAPDataCacheRepository = UnavailableSAPDataCacheRepository()
        }
    }

    var body: some Scene {
        WindowGroup {
            AppRootView(
                productionOfflineWorkRepository: productionOfflineWorkRepository,
                productionSAPDataCacheRepository: productionSAPDataCacheRepository
            )
        }
    }
}
