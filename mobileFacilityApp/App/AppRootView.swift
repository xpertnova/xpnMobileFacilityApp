import SwiftUI

struct AppRootView: View {
    let demo: FacilityDemoViewModel

    var body: some View {
        FacilityShellView(demo: demo)
            .tint(FacilityTheme.accent)
            .background(FacilityTheme.canvas)
    }
}
