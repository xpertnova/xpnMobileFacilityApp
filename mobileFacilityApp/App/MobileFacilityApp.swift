import SwiftUI

@main
struct MobileFacilityApp: App {
    private let productionOfflineWorkRepository: any OfflineWorkRepository
    private let productionSAPDataCacheRepository: any SAPDataCacheRepository
    private let productionPhotoAttachmentStore: any PhotoAttachmentStore

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
        do {
            productionPhotoAttachmentStore = try FilePhotoAttachmentStore()
        } catch {
            productionPhotoAttachmentStore = UnavailablePhotoAttachmentStore()
        }
    }

    var body: some Scene {
        WindowGroup {
            AppRootView(
                productionOfflineWorkRepository: productionOfflineWorkRepository,
                productionSAPDataCacheRepository: productionSAPDataCacheRepository,
                productionPhotoAttachmentStore: productionPhotoAttachmentStore
            )
        }
    }
}
