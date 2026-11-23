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
                    if bannerItems.isEmpty && isLoading {
                        bannerSkeleton
                    } else if !bannerItems.isEmpty {
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
            .onChange(of: bannerItems.count) { _ in
                if bannerIndex >= min(bannerItems.count, 6) {
                    bannerIndex = 0
                }
            }
        }
    }

    // MARK: - 轮播

    private var banner: some View {
        VStack(spacing: 9) {
            ZStack {
                if let item = currentBanner {
                    NavigationLink {
                        TitleSearchView(title: item.title)
                    } label: {
                        bannerSlide(item)
                    }
                    .buttonStyle(.plain)
                    .id(item.id)
                    .transition(.opacity)
                }
            }
            .frame(maxWidth: .infinity)
            .frame(height: 218)
            .contentShape(Rectangle())
            .simultaneousGesture(
                DragGesture(minimumDistance: 24)
                    .onEnded { value in
                        guard bannerItems.count > 1 else { return }
                        if value.translation.width < -40 {
                            withAnimation(.easeInOut(duration: 0.3)) {
                                bannerIndex = (bannerIndex + 1) % bannerItems.count
                            }
                        } else if value.translation.width > 40 {
                            withAnimation(.easeInOut(duration: 0.3)) {
                                bannerIndex = (bannerIndex - 1 + bannerItems.count) % bannerItems.count
                            }
                        }
                    }
            )
            .animation(.easeInOut(duration: 0.3), value: bannerIndex)

            if min(bannerItems.count, 6) > 1 {
                HStack(spacing: 5) {
                    ForEach(0..<min(bannerItems.count, 6), id: \.self) { index in
                        Capsule()
                            .fill(index == bannerIndex ? Theme.accent : Color.white.opacity(0.18))
                            .frame(width: index == bannerIndex ? 16 : 5, height: 5)
                            .animation(.easeInOut(duration: 0.2), value: bannerIndex)
                    }
                }
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.top, 2)
    }

    private var currentBanner: BannerItem? {
        guard !bannerItems.isEmpty else { return nil }
        return bannerItems[min(max(0, bannerIndex), bannerItems.count - 1)]
    }

    private func bannerSlide(_ item: BannerItem) -> some View {
        ZStack(alignment: .bottomLeading) {
            RemoteImage(url: app.imageURL(item.image))
                .frame(maxWidth: .infinity)
                .frame(height: 218)
                .clipped()

            LinearGradient(
                colors: [.clear, .black.opacity(0.35), .black.opacity(0.94)],
                startPoint: .top,
                endPoint: .bottom
            )

            VStack(alignment: .leading, spacing: 6) {
                Text(item.title)
                    .font(.system(size: 20, weight: .bold))
                    .foregroundColor(.white)
                    .lineLimit(2)

                HStack(spacing: 8) {
                    if let rate = item.rate, rate > 0 {
                        Text(String(format: "★ %.1f", rate))
                            .foregroundColor(Color(red: 1.0, green: 0.78, blue: 0.25))
                    }
                    if !item.year.isEmpty {
                        Text(item.year)
                    }
                    Text(item.mediaType == "tv" ? "剧集" : "电影")
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
        .frame(maxWidth: .infinity)
        .frame(height: 218)
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .stroke(Theme.stroke, lineWidth: 0.5)
        )
    }

    // MARK: - 轮播数据（TMDB / 豆瓣 / TX 统一 + 兜底）

    private struct BannerItem: Identifiable {
        let id: String
        let title: String
        let image: String?
        let year: String
        let rate: Double?
        let mediaType: String
        let overview: String?
    }

    private var bannerItems: [BannerItem] {
        if !trending.isEmpty {
            return trending.prefix(6).map { item in
                BannerItem(
                    id: item.id,
                    title: item.displayTitle,
                    image: resolvedTrendingImage(item),
                    year: item.displayYear,
                    rate: item.vote_average,
                    mediaType: item.media_type ?? "movie",
                    overview: item.overview
                )
            }
        }

        // 兜底：/api/tmdb/trending 失败或为空时，用首页热门片单做轮播
        let pool: [DoubanItem]
        if !hotMovies.isEmpty {
            pool = hotMovies
        } else if !hotTVShows.isEmpty {
            pool = hotTVShows
        } else {
            pool = hotVariety
        }
        return pool.prefix(6).map { item in
            BannerItem(
                id: "fallback-\(item.id)",
                title: item.title,
                image: item.poster,
                year: item.year ?? "",
                rate: Double(item.rate ?? ""),
                mediaType: "movie",
                overview: nil
            )
        }
    }

    private func resolvedTrendingImage(_ item: TrendingItem) -> String? {
        guard let raw = item.backdrop_path ?? item.poster_path,
              !raw.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return nil
        }
        if raw.hasPrefix("http://") || raw.hasPrefix("https://") || raw.hasPrefix("//") {
            return raw
        }
        // TMDB 数据源给的是 /xxxx.jpg 路径，必须补 image.tmdb.org 前缀
        return AppState.tmdbImageURL(raw, size: "original")
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

        hotMovies = (try? await movieRequest) ?? []
        hotTVShows = (try? await tvRequest) ?? []
        hotVariety = (try? await varietyRequest) ?? []
        upcoming = (try? await upcomingRequest) ?? []

        // 先让片单/兜底轮播出来，不被 /api/tmdb/trending 的慢请求拖住
        isLoading = false
        saveCache()

        trending = (try? await trendingRequest) ?? []
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
        let count = min(bannerItems.count, 6)
        guard count > 1 else { return }
        withAnimation(.easeInOut(duration: 0.45)) {
            bannerIndex = (bannerIndex + 1) % count
        }
    }
}
