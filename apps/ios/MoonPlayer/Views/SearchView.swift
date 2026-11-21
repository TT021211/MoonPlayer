import SwiftUI

struct SearchView: View {
    @EnvironmentObject private var app: AppState

    @State private var query = ""
    @State private var results: [SearchResult] = []
    @State private var isLoading = false
    @State private var hasSearched = false
    @State private var errorMessage: String?
    @State private var selectedSourceKey: String?
    @State private var searchTask: Task<Void, Never>?
    @State private var recent: [String] = UserDefaults.standard.stringArray(forKey: "search.recent") ?? []

    private let columns = [
        GridItem(.adaptive(minimum: 102), spacing: 12)
    ]

    var body: some View {
        NavigationStack {
            ScrollView {
                if isLoading && results.isEmpty {
                    loadingView
                } else if let errorMessage, results.isEmpty {
                    ErrorStateView(message: errorMessage) {
                        startSearch(query)
                    }
                } else if results.isEmpty {
                    emptyView
                } else {
                    resultGrid
                }
            }
            .background(Theme.background.ignoresSafeArea())
            .navigationTitle("搜索")
            .navigationBarTitleDisplayMode(.large)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    sourceMenu
                }
            }
            .searchable(
                text: $query,
                placement: .navigationBarDrawer(displayMode: .always),
                prompt: "搜索影片、演员、关键词"
            )
            .onSubmit(of: .search) {
                startSearch(query)
            }
            .onChange(of: query) { value in
                searchTask?.cancel()
                if value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    results = []
                    hasSearched = false
                    errorMessage = nil
                    return
                }
                searchTask = Task {
                    try? await Task.sleep(nanoseconds: 550_000_000)
                    guard !Task.isCancelled else { return }
                    startSearch(value)
                }
            }
        }
    }

    // MARK: - 子视图

    private var sourceMenu: some View {
        Menu {
            Button {
                selectedSourceKey = nil
                refreshAfterFilterChange()
            } label: {
                if selectedSourceKey == nil {
                    Label("全部频道", systemImage: "checkmark")
                } else {
                    Text("全部频道")
                }
            }
            Divider()
            ForEach(app.sources) { source in
                Button {
                    selectedSourceKey = source.key
                    refreshAfterFilterChange()
                } label: {
                    if selectedSourceKey == source.key {
                        Label(source.name, systemImage: "checkmark")
                    } else {
                        Text(source.name)
                    }
                }
            }
        } label: {
            Image(systemName: "line.3.horizontal.decrease.circle")
        }
    }

    private var loadingView: some View {
        VStack(spacing: 12) {
            ProgressView().tint(Theme.textSecondary)
            Text("正在搜索多个频道…")
                .font(.system(size: 12.5))
                .foregroundColor(Theme.textTertiary)
        }
        .frame(maxWidth: .infinity)
        .padding(.top, 90)
    }

    private var emptyView: some View {
        VStack(spacing: 22) {
            EmptyStateView(
                symbol: "sparkle.magnifyingglass",
                title: hasSearched ? "没有找到相关影片" : "想看点什么？",
                subtitle: hasSearched
                    ? "试试更短的关键词，或切换搜索范围"
                    : "输入关键词后会同时搜索所有已启用的采集源"
            )

            if !recent.isEmpty {
                VStack(alignment: .leading, spacing: 10) {
                    HStack {
                        Text("最近搜索")
                            .font(.system(size: 12.5, weight: .semibold))
                            .foregroundColor(Theme.textSecondary)
                        Spacer()
                        Button("清除") {
                            recent = []
                            UserDefaults.standard.set([], forKey: "search.recent")
                        }
                        .font(.system(size: 11.5))
                        .foregroundColor(Theme.textTertiary)
                    }

                    FlowChips(items: recent) { keyword in
                        query = keyword
                        startSearch(keyword)
                    }
                }
                .padding(.horizontal, 18)
            }
        }
    }

    private var resultGrid: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("\(results.count) 个结果")
                    .font(.system(size: 12))
                    .foregroundColor(Theme.textTertiary)
                if let selectedSourceKey {
                    Text("· \(app.sourceName(for: selectedSourceKey))")
                        .font(.system(size: 12))
                        .foregroundColor(Theme.textSecondary)
                }
                Spacer()
            }
            .padding(.horizontal, 14)
            .padding(.top, 8)

            LazyVGrid(columns: columns, alignment: .leading, spacing: 16) {
                ForEach(results) { item in
                    NavigationLink {
                        DetailView(
                            sourceKey: item.source ?? selectedSourceKey ?? "",
                            videoID: item.id,
                            previewTitle: item.title,
                            previewPoster: item.poster
                        )
                    } label: {
                        PosterCard(
                            title: item.title,
                            poster: item.poster,
                            badge: item.vod_remarks,
                            year: item.year,
                            sourceName: item.source_name,
                            aspect: AppState.posterAspect(forSourceKey: item.source ?? "")
                        )
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 14)
            .padding(.bottom, 28)
        }
    }

    // MARK: - 行为

    private func refreshAfterFilterChange() {
        guard !query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
        startSearch(query)
    }

    @MainActor
    private func startSearch(_ raw: String) {
        let keyword = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !keyword.isEmpty else { return }

        searchTask?.cancel()
        isLoading = true
        errorMessage = nil
        hasSearched = true

        let sourceKey = selectedSourceKey
        searchTask = Task {
            do {
                let items: [SearchResult]
                if let sourceKey {
                    let response = try await app.search(sourceKey: sourceKey, keyword: keyword, page: 1)
                    items = response.results ?? []
                } else {
                    items = try await app.globalSearch(keyword)
                }
                guard !Task.isCancelled else { return }
                var seen = Set<String>()
                results = items.filter { item in
                    let key = "\(item.source ?? "")+\(item.id)"
                    guard !seen.contains(key) else { return false }
                    seen.insert(key)
                    return true
                }
                remember(keyword)
            } catch {
                guard !Task.isCancelled else { return }
                results = []
                errorMessage = error.localizedDescription
            }
            isLoading = false
        }
    }

    private func remember(_ keyword: String) {
        var list = recent.filter { $0 != keyword }
        list.insert(keyword, at: 0)
        if list.count > 12 { list = Array(list.prefix(12)) }
        recent = list
        UserDefaults.standard.set(list, forKey: "search.recent")
    }
}

// MARK: - 自动换行胶囊

struct FlowChips: View {
    let items: [String]
    let onTap: (String) -> Void

    var body: some View {
        LazyVGrid(columns: [GridItem(.adaptive(minimum: 76), spacing: 8)], alignment: .leading, spacing: 8) {
            ForEach(items, id: \.self) { item in
                Button {
                    onTap(item)
                } label: {
                    Text(item)
                        .font(.system(size: 12.5))
                        .foregroundColor(.white.opacity(0.8))
                        .lineLimit(1)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 7)
                        .frame(maxWidth: .infinity)
                        .background(Theme.surface)
                        .clipShape(Capsule())
                        .overlay(Capsule().stroke(Theme.stroke, lineWidth: 0.5))
                }
                .buttonStyle(.plain)
            }
        }
    }
}
