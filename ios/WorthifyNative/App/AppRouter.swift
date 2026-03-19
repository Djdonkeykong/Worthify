import Foundation

@MainActor
final class AppRouter: ObservableObject {
    enum RootRoute: Equatable {
        case splash
        case auth
        case main
    }

    enum MainTab: Hashable {
        case home
        case collection
        case profile
    }

    @Published var rootRoute: RootRoute = .splash
    @Published var selectedTab: MainTab = .home
}
