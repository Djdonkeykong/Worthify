import SwiftUI

struct RootView: View {
    @EnvironmentObject private var environment: AppEnvironment

    var body: some View {
        Group {
            switch environment.router.rootRoute {
            case .splash:
                SplashView()
            case .auth:
                NavigationStack {
                    LoginView()
                }
            case .main:
                RootTabView()
            }
        }
        .animation(.smooth(duration: 0.28), value: environment.router.rootRoute)
        .task {
            guard environment.router.rootRoute == .splash else { return }
            await environment.sessionStore.restore()
            await environment.shareBridge.syncConfiguration()
            switch environment.sessionStore.state {
            case .restoring:
                environment.router.rootRoute = .splash
            case .signedOut:
                environment.router.rootRoute = .auth
            case .signedIn:
                environment.router.rootRoute = .main
            }
            Task {
                await environment.notificationService.registerForPushIfNeeded()
            }
        }
    }
}
