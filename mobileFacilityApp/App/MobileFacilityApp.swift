import SwiftUI

@main
struct MobileFacilityApp: App {
    @State private var demo = FacilityDemoViewModel()

    var body: some Scene {
        WindowGroup {
            AppRootView(demo: demo)
        }
    }
}
