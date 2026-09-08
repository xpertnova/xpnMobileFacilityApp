import SwiftUI

@main
struct MobileFacilityApp: App {
    @AppStorage(AppLanguage.storageKey) private var languageCode = AppLanguage.resolved(from: nil).rawValue
    private let productionOfflineWorkRepository: any OfflineWorkRepository
    private let productionPhotoAttachmentStore: any PhotoAttachmentStore

    init() {
        do {
            productionOfflineWorkRepository = try SQLiteOfflineWorkRepository()
        } catch {
            productionOfflineWorkRepository = UnavailableOfflineWorkRepository()
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
                productionPhotoAttachmentStore: productionPhotoAttachmentStore
            )
            .environment(\.locale, AppLanguage.resolved(from: languageCode).locale)
        }
    }
}
