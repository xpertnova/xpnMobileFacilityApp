import SwiftUI

@main
struct MobileFacilityApp: App {
    @AppStorage(AppLanguage.storageKey) private var languageCode = AppLanguage.resolved(from: nil).rawValue

    var body: some Scene {
        WindowGroup {
            AppRootView()
            .environment(\.locale, AppLanguage.resolved(from: languageCode).locale)
        }
    }
}
