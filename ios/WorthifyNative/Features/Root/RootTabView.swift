import SwiftUI

struct RootTabView: View {
    @EnvironmentObject private var environment: AppEnvironment

    var body: some View {
        TabView(selection: $environment.router.selectedTab) {
            NavigationStack {
                HomeView()
            }
            .tabItem {
                Label("Home", systemImage: "house")
            }
            .tag(AppRouter.MainTab.home)

            NavigationStack {
                CollectionView()
            }
            .tabItem {
                Label("Collection", systemImage: "heart")
            }
            .tag(AppRouter.MainTab.collection)

            NavigationStack {
                ProfileView()
            }
            .tabItem {
                Label("Profile", systemImage: "person")
            }
            .tag(AppRouter.MainTab.profile)
        }
        .tabViewStyle(.automatic)
    }
}
