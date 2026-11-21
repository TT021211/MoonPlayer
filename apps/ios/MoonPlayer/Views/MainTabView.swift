import SwiftUI

struct MainTabView: View {
    @EnvironmentObject private var app: AppState

    var body: some View {
        TabView {
            HomeView()
                .tabItem { Label("首页", systemImage: "house.fill") }

            ChannelsView()
                .tabItem { Label("频道", systemImage: "square.grid.2x2.fill") }

            SearchView()
                .tabItem { Label("搜索", systemImage: "magnifyingglass") }

            ProfileView()
                .tabItem { Label("我的", systemImage: "person.crop.circle.fill") }
        }
        .tint(Theme.accent)
    }
}
