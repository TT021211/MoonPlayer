import SwiftUI

struct ChannelView: View {
    let source: SourceItem

    @EnvironmentObject private var app: AppState

    @State private var categories: [CategoryItem] = []
    @State private var selected: CategoryItem?
    @State private var videos: [SearchResult] = []
    @State private var page = 1
    @State private var pageCount = 1
    @State private var hasMore = true
    @State private var isLoadingVideos = false
    @State private var isLoadingCategories = true
    @State private var errorMessage: String?
    @State private var showCategorySheet = false
    @State private var showSearchSheet = false
    @State private var didLoad = false

    private let columns = [
        GridItem(.adaptive(minimum: 102), spacing: 12)
    ]

    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 14) {
                categoryBar

                if isLoadingCategories && categories.isEmpty {
                    loadingBlock
                } else if let errorMessage, videos.isEmpty {
                    ErrorStateView(message: errorMessage) {
                        Task { await loadCategories() }
                    }
                } else if videos.isEmpty && !isLoadingVideos {
                    EmptyStateView(
                        symbol: "film.stack",
                        title: "这个分类还没有内容",
                        subtitle: "换一个分类或稍后再试"
                    )
                } else {
                    grid
                    loadMoreIndicator
                }
            }
            .padding(.horizontal, 14)
            .padding(.bottom, 24)
        }
        .background(Theme.background.ignoresSafeArea())
        .navigationTitle(source.name)
        .navigationBarTitleDisplayMode(.large)
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                Button {
                    showSearchSheet = true
                } label: {
                    Image(systemName: "magnifyingglass")
                }
            }
        }
        .refreshable {
            await loadCategories(force: true)
        }
        .task {
            guard !didLoad else { return }
            didLoad = true
            await loadCategories()
        }
        .sheet(isPresented: $showCategorySheet) {
            CategoryPickerSheet(categories: categories, selected: $selected) { category in
                selected = category
                showCategorySheet = false
                Task { await loadVideos(category: category, reset: true) }
            }
        }
        .sheet(isPresented: $showSearchSheet) {
            SourceSearchView(source: source)
                .environmentObject(app)
        }
    }

    // MARK: - 分类胶囊

    private var categoryBar: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(visibleCategories) { category in
                    ChipButton(
                        title: category.name,
                        selected: category.id == selected?.id
                    ) {
                        guard category.id != selected?.id else { return }
                        selected = category
                        Task { await loadVideos(category: category, reset: true) }
                    }
                }

                if categories.count > visibleCategories.count || categories.first?.id != selected?.id {
                    Button {
                        showCategorySheet = true
                    } label: {
                        HStack(spacing: 4) {
                            Text("全部分类")
                            Image(systemName: "chevron.down")
                                .font(.system(size: 9, weight: .bold))
                        }
                        .font(.system(size: 13, weight: .medium))
                        .foregroundColor(.white.opacity(0.82))
                        .padding(.horizontal, 13)
                        .padding(.vertical, 7)
                        .background(Theme.surface)
                        .clipShape(Capsule())
                        .overlay(Capsule().stroke(Theme.stroke, lineWidth: 0.5))
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.vertical, 4)
            .padding(.horizontal, 1)
        }
    }

    private var visibleCategories: [CategoryItem] {
        guard categories.count > 18 else { return categories }
        var list = Array(categories.prefix(18))
        if let selected, !list.contains(where: { $0.id == selected.id }) {
            list.insert(selected, at: 0)
        }
        return list
    }

    // MARK: - 网格

    private var grid: some View {
        LazyVGrid(columns: columns, alignment: .leading, spacing: 16) {
            ForEach(videos) { item in
                NavigationLink {
                    DetailView(
                        sourceKey: source.key,
                        videoID: item.id,
                        previewTitle: item.title,
                        previewPoster: item.poster
                    )
                } label: {
                    PosterCard(
                        title: item.title,
                        poster: item.poster,
                        badge: item.vod_remarks,
                        year: item.year
                    )
                }
                .buttonStyle(.plain)
                .onAppear {
                    if item.id == videos.last?.id {
                        loadMoreIfNeeded()
                    }
                }
            }
        }
    }

    private var loadingBlock: some View {
        VStack(spacing: 14) {
            ProgressView().tint(Theme.textSecondary)
            Text("正在加载频道…")
                .font(.system(size: 12.5))
                .foregroundColor(Theme.textTertiary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 60)
    }

    private var loadMoreIndicator: some View {
        HStack {
            Spacer()
            if isLoadingVideos {
                ProgressView().tint(Theme.textSecondary)
            } else if !hasMore && !videos.isEmpty {
                Text("没有更多了")
                    .font(.system(size: 11.5))
                    .foregroundColor(Theme.textTertiary)
            }
            Spacer()
        }
        .frame(height: 34)
    }

    // MARK: - 数据

    @MainActor
    private func loadCategories(force: Bool = false) async {
        if !force, !categories.isEmpty { return }
        isLoadingCategories = true
        errorMessage = nil
        do {
            let list = try await app.categories(for: source.key)
            categories = list
            guard !list.isEmpty else {
                isLoadingCategories = false
                errorMessage = "该源暂时没有下发分类"
                return
            }
            let category = selected.flatMap { current in
                list.first { $0.id == current.id }
            } ?? list[0]
            selected = category
            isLoadingCategories = false
            await loadVideos(category: category, reset: true)
        } catch {
            isLoadingCategories = false
            errorMessage = error.localizedDescription
        }
    }

    @MainActor
    private func loadVideos(category: CategoryItem, reset: Bool) async {
        if isLoadingVideos && !reset { return }
        if reset {
            page = 1
            hasMore = true
            videos = []
        }
        guard hasMore || reset else { return }

        isLoadingVideos = true
        errorMessage = nil
        do {
            let response = try await app.videos(
                sourceKey: source.key,
                categoryID: category.id,
                page: page
            )
            let incoming = response.results ?? []
            if reset {
                videos = incoming
            } else {
                let existing = Set(videos.map { $0.id })
                videos.append(contentsOf: incoming.filter { !existing.contains($0.id) })
            }
            pageCount = response.pageCount ?? page
            hasMore = page < pageCount && !incoming.isEmpty
        } catch {
            if reset { errorMessage = error.localizedDescription }
        }
        isLoadingVideos = false
    }

    @MainActor
    private func loadMoreIfNeeded() {
        guard hasMore, !isLoadingVideos, let category = selected else { return }
        page += 1
        Task { await loadVideos(category: category, reset: false) }
    }
}

// MARK: - 分类选择

struct CategoryGroup: Identifiable {
    let id: String
    let title: String
    let items: [CategoryItem]
}

struct CategoryPickerSheet: View {
    let categories: [CategoryItem]
    @Binding var selected: CategoryItem?
    let onSelect: (CategoryItem) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var query = ""

    private var grouped: [CategoryGroup] {
        let filtered = categories.filter {
            query.trimmingCharacters(in: .whitespaces).isEmpty
                || $0.name.localizedCaseInsensitiveContains(query)
        }
        var order: [String] = []
        var buckets: [String: [CategoryItem]] = [:]
        for category in filtered {
            let group = category.displayGroup
            if buckets[group] == nil {
                order.append(group)
                buckets[group] = []
            }
            buckets[group]?.append(category)
        }
        return order.map { CategoryGroup(id: $0, title: $0, items: buckets[$0] ?? []) }
    }

    var body: some View {
        NavigationStack {
            List {
                ForEach(grouped) { group in
                    Section(group.title) {
                        ForEach(group.items) { category in
                            Button {
                                onSelect(category)
                            } label: {
                                HStack {
                                    Text(category.name)
                                        .font(.system(size: 14.5))
                                        .foregroundColor(.white.opacity(0.92))
                                    Spacer()
                                    if category.id == selected?.id {
                                        Image(systemName: "checkmark")
                                            .font(.system(size: 12, weight: .bold))
                                            .foregroundColor(Theme.accent)
                                    }
                                }
                                .contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)
                            .listRowBackground(Theme.surface)
                        }
                    }
                }
            }
            .listStyle(.insetGrouped)
            .scrollContentBackground(.hidden)
            .background(Theme.background.ignoresSafeArea())
            .searchable(
                text: $query,
                placement: .navigationBarDrawer(displayMode: .always),
                prompt: "搜索分类"
            )
            .navigationTitle("全部分类")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("关闭") { dismiss() }
                }
            }
        }
        .presentationDetents([.medium, .large])
    }
}

// MARK: - 源内搜索

struct SourceSearchView: View {
    let source: SourceItem

    @EnvironmentObject private var app: AppState
    @Environment(\.dismiss) private var dismiss

    @State private var query = ""
    @State private var results: [SearchResult] = []
    @State private var isLoading = false
    @State private var didSearch = false
    @State private var errorMessage: String?
    @State private var task: Task<Void, Never>?

    private let columns = [
        GridItem(.adaptive(minimum: 102), spacing: 12)
    ]

    var body: some View {
        NavigationStack {
            ScrollView {
                if isLoading && results.isEmpty {
                    VStack(spacing: 12) {
                        ProgressView().tint(Theme.textSecondary)
                        Text("正在搜索…")
                            .font(.system(size: 12.5))
                            .foregroundColor(Theme.textTertiary)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.top, 80)
                } else if let errorMessage, results.isEmpty {
                    ErrorStateView(message: errorMessage)
                } else if results.isEmpty {
                    EmptyStateView(
                        symbol: "magnifyingglass",
                        title: didSearch ? "没有找到相关影片" : "输入关键词搜索",
                        subtitle: didSearch ? "换个关键词试试" : "只在当前频道「\(source.name)」内搜索"
                    )
                } else {
                    LazyVGrid(columns: columns, alignment: .leading, spacing: 16) {
                        ForEach(results) { item in
                            NavigationLink {
                                DetailView(
                                    sourceKey: source.key,
                                    videoID: item.id,
                                    previewTitle: item.title,
                                    previewPoster: item.poster
                                )
                            } label: {
                                PosterCard(
                                    title: item.title,
                                    poster: item.poster,
                                    badge: item.vod_remarks,
                                    year: item.year
                                )
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(14)
                }
            }
            .background(Theme.background.ignoresSafeArea())
            .navigationTitle(source.name)
            .navigationBarTitleDisplayMode(.inline)
            .searchable(
                text: $query,
                placement: .navigationBarDrawer(displayMode: .always),
                prompt: "在 \(source.name) 中搜索"
            )
            .onSubmit(of: .search) {
                startSearch()
            }
            .onChange(of: query) { value in
                guard value.isEmpty else { return }
                results = []
                didSearch = false
                errorMessage = nil
            }
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("关闭") { dismiss() }
                }
            }
        }
    }

    @MainActor
    private func startSearch() {
        let keyword = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !keyword.isEmpty else { return }
        task?.cancel()
        isLoading = true
        errorMessage = nil
        task = Task {
            do {
                let response = try await app.search(sourceKey: source.key, keyword: keyword, page: 1)
                guard !Task.isCancelled else { return }
                results = response.results ?? []
                didSearch = true
            } catch {
                guard !Task.isCancelled else { return }
                errorMessage = error.localizedDescription
            }
            isLoading = false
        }
    }
}
