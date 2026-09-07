import SwiftUI

@main
struct MobileFacilityApp: App {
    @AppStorage(AppLanguage.storageKey) private var languageCode = AppLanguage.resolved(from: nil).rawValue
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
            .environment(\.locale, AppLanguage.resolved(from: languageCode).locale)
        }
    }
}
