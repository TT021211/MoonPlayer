import SwiftUI

struct DoubanFilter: Identifiable, Hashable {
    let id: String
    let label: String
    let apiKind: String
    let category: String
    let type: String
    let format: String
    let useRecommends: Bool
}

struct DoubanListView: View {
    let kind: String

    @EnvironmentObject private var app: AppState

    @State private var selected: DoubanFilter
    @State private var items: [DoubanItem] = []
    @State private var start = 0
    @State private var hasMore = true
    @State private var isLoading = false
    @State private var didLoad = false
    @State private var errorMessage: String?
    @State private var loadToken = UUID()

    private let limit = 24
    private let columns = [
        GridItem(.adaptive(minimum: 102), spacing: 12)
    ]

    init(kind: String) {
        self.kind = kind
        _selected = State(initialValue: Self.filters(for: kind).first ?? Self.fallbackFilter)
    }

    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 14) {
                filterBar

                if isLoading && items.isEmpty {
                    loadingView
                } else if let errorMessage, items.isEmpty {
                    ErrorStateView(message: errorMessage) {
                        Task { await load(reset: true) }
                    }
                } else if items.isEmpty {
                    EmptyStateView(
                        symbol: "film.stack",
                        title: "这个分类暂时没有内容",
                        subtitle: "换一个分类或下拉刷新试试"
                    )
                } else {
                    grid
                    loadMoreIndicator
                }
            }
            .padding(.horizontal, 14)
            .padding(.bottom, 26)
        }
        .background(Theme.background.ignoresSafeArea())
        .navigationTitle(pageTitle)
        .navigationBarTitleDisplayMode(.large)
        .refreshable {
            await load(reset: true)
        }
        .task {
            guard !didLoad else { return }
            didLoad = true
            await load(reset: true)
        }
        .onChange(of: selected) { _ in
            Task { await load(reset: true) }
        }
    }

    private var pageTitle: String {
        switch kind {
        case "movie": return "电影"
        case "tv": return "剧集"
        case "anime": return "动漫"
        case "show": return "综艺"
        default: return "豆瓣"
        }
    }

    private var filters: [DoubanFilter] {
        Self.filters(for: kind)
    }

    private var filterBar: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(filters) { filter in
                    ChipButton(title: filter.label, selected: filter.id == selected.id) {
                        selected = filter
                    }
                }
            }
            .padding(.vertical, 4)
            .padding(.horizontal, 1)
        }
    }

    private var grid: some View {
        LazyVGrid(columns: columns, alignment: .leading, spacing: 16) {
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
                }
                .buttonStyle(.plain)
                .onAppear {
                    if item.id == items.last?.id {
                        loadMoreIfNeeded()
                    }
                }
            }
        }
    }

    private var loadingView: some View {
        VStack(spacing: 12) {
            ProgressView().tint(Theme.textSecondary)
            Text("正在加载豆瓣片单…")
                .font(.system(size: 12.5))
                .foregroundColor(Theme.textTertiary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 70)
    }

    private var loadMoreIndicator: some View {
        HStack {
            Spacer()
            if isLoading {
                ProgressView().tint(Theme.textSecondary)
            } else if !hasMore {
                Text("没有更多了")
                    .font(.system(size: 11.5))
                    .foregroundColor(Theme.textTertiary)
            }
            Spacer()
        }
        .frame(height: 36)
    }

    @MainActor
    private func loadMoreIfNeeded() {
        guard hasMore, !isLoading else { return }
        Task { await load(reset: false) }
    }

    @MainActor
    private func load(reset: Bool) async {
        if isLoading && !reset { return }
        if reset {
            start = 0
            items = []
            hasMore = true
            errorMessage = nil
        }
        guard hasMore || reset else { return }

        let token = UUID()
        loadToken = token
        isLoading = true
        do {
            let incoming: [DoubanItem]
            if selected.useRecommends {
                incoming = try await app.fetchDoubanRecommends(
                    kind: selected.apiKind,
                    category: selected.category,
                    format: selected.format,
                    start: start,
                    limit: limit
                )
            } else {
                incoming = try await app.fetchDoubanCategories(
                    kind: selected.apiKind,
                    category: selected.category,
                    type: selected.type,
                    start: start,
                    limit: limit
                )
            }
            guard loadToken == token else { return }

            if reset {
                items = incoming
            } else {
                let existing = Set(items.map { $0.id })
                items.append(contentsOf: incoming.filter { !existing.contains($0.id) })
            }
            start += limit
            hasMore = incoming.count >= limit
        } catch {
            guard loadToken == token else { return }
            errorMessage = error.localizedDescription
            hasMore = false
        }
        isLoading = false
    }

    private static let fallbackFilter = DoubanFilter(
        id: "hot",
        label: "热门",
        apiKind: "movie",
        category: "热门",
        type: "全部",
        format: "",
        useRecommends: false
    )

    static func filters(for kind: String) -> [DoubanFilter] {
        switch kind {
        case "movie":
            return ["热门", "最新", "豆瓣高分", "冷门佳片"].map { value in
                DoubanFilter(
                    id: value,
                    label: value,
                    apiKind: "movie",
                    category: value,
                    type: "全部",
                    format: "",
                    useRecommends: false
                )
            }
        case "tv":
            return [
                ("全部", "tv"),
                ("国产", "tv_domestic"),
                ("欧美", "tv_american"),
                ("日本", "tv_japanese"),
                ("韩国", "tv_korean"),
                ("动漫", "tv_animation"),
                ("纪录片", "tv_documentary")
            ].map { pair in
                DoubanFilter(
                    id: pair.1,
                    label: pair.0,
                    apiKind: "tv",
                    category: "tv",
                    type: pair.1,
                    format: "",
                    useRecommends: false
                )
            }
        case "show":
            return [
                ("全部", "show"),
                ("国内", "show_domestic"),
                ("国外", "show_foreign")
            ].map { pair in
                DoubanFilter(
                    id: pair.1,
                    label: pair.0,
                    apiKind: "tv",
                    category: "show",
                    type: pair.1,
                    format: "",
                    useRecommends: false
                )
            }
        case "anime":
            return [
                DoubanFilter(
                    id: "bangumi",
                    label: "番剧",
                    apiKind: "tv",
                    category: "动画",
                    type: "",
                    format: "电视剧",
                    useRecommends: true
                ),
                DoubanFilter(
                    id: "movie",
                    label: "剧场版",
                    apiKind: "movie",
                    category: "动画",
                    type: "",
                    format: "",
                    useRecommends: true
                )
            ]
        default:
            return [fallbackFilter]
        }
    }
}
