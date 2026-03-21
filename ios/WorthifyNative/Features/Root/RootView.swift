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
        .alert(
            "Startup Notice",
            isPresented: Binding(
                get: { environment.sessionStore.startupAlertMessage != nil },
                set: { if !$0 { environment.sessionStore.clearStartupAlert() } }
            )
        ) {
            Button("OK", role: .cancel) {
                environment.sessionStore.clearStartupAlert()
            }
        } message: {
            Text(environment.sessionStore.startupAlertMessage ?? "Unknown startup issue.")
        }
        .task {
            guard environment.router.rootRoute == .splash else { return }
            if environment.config.bypassAuth {
                await environment.shareBridge.syncConfiguration()
                await extendSplashDuration()
                environment.router.rootRoute = .main
                Task {
                    await environment.sessionStore.restore()
                    await environment.notificationService.registerForPushIfNeeded()
                }
                return
            }
            if let startupValidationMessage = environment.config.startupValidationMessage {
                environment.sessionStore.setStartupAlert(startupValidationMessage)
                await extendSplashDuration()
                environment.router.rootRoute = .auth
                return
            }
            await environment.sessionStore.restore()
            await environment.shareBridge.syncConfiguration()
            let nextRoute: AppRouter.RootRoute
            switch environment.sessionStore.state {
            case .restoring:
                nextRoute = .splash
            case .signedOut:
                nextRoute = .auth
            case .signedIn:
                nextRoute = .main
            }
            if nextRoute != .splash {
                await extendSplashDuration()
            }
            environment.router.rootRoute = nextRoute
            Task {
                await environment.notificationService.registerForPushIfNeeded()
            }
        }
    }

    private func extendSplashDuration() async {
        try? await Task.sleep(nanoseconds: 500_000_000)
    }
}
