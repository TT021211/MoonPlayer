import Combine
import SwiftUI

struct HomeView: View {
    @EnvironmentObject private var app: AppState

    @State private var trending: [TrendingItem] = []
    @State private var hotMovies: [DoubanItem] = []
    @State private var hotTVShows: [DoubanItem] = []
    @State private var hotVariety: [DoubanItem] = []
    @State private var upcoming: [TrendingItem] = []

    @State private var isLoading = true
    @State private var didLoad = false
    @State private var bannerIndex = 0

    private let bannerTimer = Timer.publish(every: 6, on: .main, in: .common).autoconnect()

    var body: some View {
        NavigationStack {
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 26) {
                    if trending.isEmpty && isLoading {
                        bannerSkeleton
                    } else if !trending.isEmpty {
                        banner
                    }

                    if isLoading {
                        sectionSkeleton(title: "热门电影")
                        sectionSkeleton(title: "热门剧集")
                    } else {
                        if !hotMovies.isEmpty {
                            mediaRow(title: "热门电影", items: hotMovies, kind: "movie")
                        }
                        if !hotTVShows.isEmpty {
                            mediaRow(title: "热门剧集", items: hotTVShows, kind: "tv")
                        }
                        if !hotVariety.isEmpty {
                            mediaRow(title: "热门综艺", items: hotVariety, kind: "show")
                        }
                        if !upcoming.isEmpty {
                            upcomingRow
                        }

                        if hotMovies.isEmpty && hotTVShows.isEmpty && hotVariety.isEmpty && upcoming.isEmpty && trending.isEmpty {
                            ErrorStateView(message: "首页内容加载失败，请检查网络后下拉重试") {
                                Task { await load() }
                            }
                        }
                    }
                }
                .padding(.horizontal, 16)
                .padding(.bottom, 30)
            }
            .background(Theme.background.ignoresSafeArea())
            .navigationTitle("首页")
            .navigationBarTitleDisplayMode(.large)
            .refreshable {
                await load()
            }
            .task {
                guard !didLoad else { return }
                didLoad = true
                _ = loadCache()
                await load()
            }
            .onReceive(bannerTimer) { _ in
                advanceBanner()
            }
            .onChange(of: trending.count) { _ in
                if bannerIndex >= min(trending.count, 6) {
                    bannerIndex = 0
                }
            }
        }
    }

    // MARK: - 轮播

    private var banner: some View {
        VStack(spacing: 9) {
            TabView(selection: $bannerIndex) {
                ForEach(Array(trending.prefix(6).indices), id: \.self) { index in
                    let item = trending[index]
                    NavigationLink {
                        TitleSearchView(title: item.displayTitle)
                    } label: {
                        bannerSlide(item)
                    }
                    .buttonStyle(.plain)
                    .tag(index)
                }
            }
            .tabViewStyle(.page(indexDisplayMode: .never))
            .frame(height: 218)

            if min(trending.count, 6) > 1 {
                HStack(spacing: 5) {
                    ForEach(0..<min(trending.count, 6), id: \.self) { index in
                        Capsule()
                            .fill(index == bannerIndex ? Theme.accent : Color.white.opacity(0.18))
                            .frame(width: index == bannerIndex ? 16 : 5, height: 5)
                            .animation(.easeInOut(duration: 0.2), value: bannerIndex)
                    }
                }
            }
        }
        .padding(.top, 2)
    }

    private func bannerSlide(_ item: TrendingItem) -> some View {
        ZStack(alignment: .bottomLeading) {
            RemoteImage(url: app.imageURL(item.backdrop_path ?? item.poster_path))
                .frame(maxWidth: .infinity)
                .frame(height: 218)
                .clipped()

            LinearGradient(
                colors: [.clear, .black.opacity(0.35), .black.opacity(0.94)],
                startPoint: .top,
                endPoint: .bottom
            )

            VStack(alignment: .leading, spacing: 6) {
                Text(item.displayTitle)
                    .font(.system(size: 20, weight: .bold))
                    .foregroundColor(.white)
                    .lineLimit(2)

                HStack(spacing: 8) {
                    if let rate = item.vote_average, rate > 0 {
                        Text(String(format: "★ %.1f", rate))
                            .foregroundColor(Color(red: 1.0, green: 0.78, blue: 0.25))
                    }
                    if !item.displayYear.isEmpty {
                        Text(item.displayYear)
                    }
                    Text(item.media_type == "tv" ? "剧集" : "电影")
                }
                .font(.system(size: 11, weight: .medium))
                .foregroundColor(.white.opacity(0.72))

                if let overview = item.overview, !overview.isEmpty {
                    Text(overview)
                        .font(.system(size: 11))
                        .foregroundColor(.white.opacity(0.68))
                        .lineLimit(2)
                }

                HStack(spacing: 4) {
                    Image(systemName: "magnifyingglass")
                        .font(.system(size: 9, weight: .bold))
                    Text("搜索片源")
                        .font(.system(size: 11, weight: .semibold))
                }
                .foregroundColor(Theme.accent)
                .padding(.top, 1)
            }
            .padding(14)
        }
        .frame(height: 218)
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .stroke(Theme.stroke, lineWidth: 0.5)
        )
    }

    private var bannerSkeleton: some View {
        RoundedRectangle(cornerRadius: 14, style: .continuous)
            .fill(Theme.surface)
            .frame(height: 218)
            .overlay(ProgressView().tint(Theme.textTertiary))
    }

    // MARK: - 横向片单

    private func mediaRow(title: String, items: [DoubanItem], kind: String) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            SectionHeader(
                title: title,
                trailing: "查看更多",
                destination: AnyView(DoubanListView(kind: kind))
            )

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(alignment: .top, spacing: 12) {
                    ForEach(items) { item in
                        NavigationLink {
                            TitleSearchView(title: item.title)
                        } label: {
                            PosterCard(
                                title: item.title,
                                poster: item.poster,
                                badge: item.rate,
                                year: item.year
                            )
                            .frame(width: 112)
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.horizontal, 1)
            }
        }
    }

    private var upcomingRow: some View {
        VStack(alignment: .leading, spacing: 12) {
            SectionHeader(title: "即将上映", trailing: nil, action: nil)

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(alignment: .top, spacing: 12) {
                    ForEach(upcoming) { item in
                        NavigationLink {
                            TitleSearchView(title: item.displayTitle)
                        } label: {
                            PosterCard(
                                title: item.displayTitle,
                                poster: AppState.tmdbImageURL(item.poster_path),
                                badge: nil,
                                year: item.displayYear.isEmpty ? nil : item.displayYear
                            )
                            .frame(width: 112)
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.horizontal, 1)
            }
        }
    }

    private func sectionSkeleton(title: String) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            SectionHeader(title: title, trailing: nil, action: nil)
            HStack(spacing: 12) {
                ForEach(0..<4, id: \.self) { _ in
                    VStack(alignment: .leading, spacing: 6) {
                        RoundedRectangle(cornerRadius: Theme.posterRadius, style: .continuous)
                            .fill(Theme.surface)
                            .aspectRatio(2.0 / 3.0, contentMode: .fit)
                        RoundedRectangle(cornerRadius: 3)
                            .fill(Theme.surface)
                            .frame(height: 9)
                    }
                    .frame(maxWidth: .infinity)
                }
            }
        }
    }

    // MARK: - 数据

    @MainActor
    private func load() async {
        let hasContent = !trending.isEmpty
            || !hotMovies.isEmpty
            || !hotTVShows.isEmpty
            || !hotVariety.isEmpty
            || !upcoming.isEmpty
        isLoading = !hasContent

        async let trendingRequest = app.fetchTrending()
        async let movieRequest = app.fetchDoubanCategories(
            kind: "movie",
            category: "热门",
            type: "全部",
            start: 0,
            limit: 20
        )
        async let tvRequest = app.fetchDoubanCategories(
            kind: "tv",
            category: "tv",
            type: "tv",
            start: 0,
            limit: 20
        )
        async let varietyRequest = app.fetchDoubanCategories(
            kind: "tv",
            category: "show",
            type: "show",
            start: 0,
            limit: 20
        )
        async let upcomingRequest = app.fetchUpcoming()

        trending = (try? await trendingRequest) ?? []
        hotMovies = (try? await movieRequest) ?? []
        hotTVShows = (try? await tvRequest) ?? []
        hotVariety = (try? await varietyRequest) ?? []
        upcoming = (try? await upcomingRequest) ?? []

        isLoading = false
        saveCache()
    }

    // MARK: - 首页缓存（先显示上次内容，再后台刷新）

    private struct HomeCache: Codable {
        var trending: [TrendingItem]
        var movies: [DoubanItem]
        var tvShows: [DoubanItem]
        var variety: [DoubanItem]
        var upcoming: [TrendingItem]
        var savedAt: Double
    }

    private static let cacheKey = "home.cache.v1"

    @MainActor
    private func loadCache() -> Bool {
        guard
            let data = UserDefaults.standard.data(forKey: Self.cacheKey),
            let cache = try? JSONDecoder().decode(HomeCache.self, from: data)
        else {
            return false
        }
        trending = cache.trending
        hotMovies = cache.movies
        hotTVShows = cache.tvShows
        hotVariety = cache.variety
        upcoming = cache.upcoming
        if !trending.isEmpty || !hotMovies.isEmpty || !hotTVShows.isEmpty || !hotVariety.isEmpty || !upcoming.isEmpty {
            isLoading = false
            return true
        }
        return false
    }

    @MainActor
    private func saveCache() {
        guard !trending.isEmpty || !hotMovies.isEmpty || !hotTVShows.isEmpty || !hotVariety.isEmpty || !upcoming.isEmpty else {
            return
        }
        let cache = HomeCache(
            trending: trending,
            movies: hotMovies,
            tvShows: hotTVShows,
            variety: hotVariety,
            upcoming: upcoming,
            savedAt: Date().timeIntervalSince1970
        )
        if let data = try? JSONEncoder().encode(cache) {
            UserDefaults.standard.set(data, forKey: Self.cacheKey)
        }
    }

    private func advanceBanner() {
        let count = min(trending.count, 6)
        guard count > 1 else { return }
        withAnimation(.easeInOut(duration: 0.45)) {
            bannerIndex = (bannerIndex + 1) % count
        }
    }
}
