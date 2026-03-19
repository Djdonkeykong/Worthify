import SwiftUI

@main
struct WorthifyNativeApp: App {
    @StateObject private var environment = AppEnvironment.bootstrap()

    var body: some Scene {
        WindowGroup {
            RootView()
                .environmentObject(environment)
                .tint(AppTheme.accent)
        }
    }
}
