import SwiftUI

/// 豆瓣 / TMDB 卡片点击后的“找片源”页：按标题做全源聚合搜索。
struct TitleSearchView: View {
    let title: String

    @EnvironmentObject private var app: AppState

    @State private var results: [SearchResult] = []
    @State private var isLoading = true
    @State private var didLoad = false
    @State private var errorMessage: String?

    var body: some View {
        List {
            if isLoading && results.isEmpty {
                HStack(spacing: 10) {
                    ProgressView().tint(Theme.textSecondary)
                    Text("正在搜索片源…")
                        .font(.system(size: 13))
                        .foregroundColor(Theme.textTertiary)
                }
                .listRowBackground(Color.clear)
                .padding(.vertical, 16)
            } else if let errorMessage, results.isEmpty {
                ErrorStateView(message: errorMessage) {
                    Task { await search() }
                }
                .listRowBackground(Color.clear)
                .listRowSeparator(.hidden)
            } else if results.isEmpty {
                EmptyStateView(
                    symbol: "magnifyingglass",
                    title: "没有找到「\(title)」的片源",
                    subtitle: "可以换个关键词，或到频道里按分类找"
                )
                .listRowBackground(Color.clear)
                .listRowSeparator(.hidden)
            } else {
                Section {
                    ForEach(results) { item in
                        NavigationLink {
                            DetailView(
                                sourceKey: item.source ?? "",
                                videoID: item.id,
                                previewTitle: item.title,
                                previewPoster: item.poster
                            )
                        } label: {
                            resultRow(item)
                        }
                        .listRowBackground(Theme.surface)
                    }
                } header: {
                    Text("\(results.count) 个片源")
                        .font(.system(size: 12))
                        .foregroundColor(Theme.textTertiary)
                } footer: {
                    Text("数据来自已配置的采集源，点击选择片源后进入详情。")
                        .font(.system(size: 10.5))
                        .foregroundColor(Theme.textTertiary.opacity(0.85))
                }
            }
        }
        .listStyle(.plain)
        .scrollContentBackground(.hidden)
        .background(Theme.background.ignoresSafeArea())
        .navigationTitle(title)
        .navigationBarTitleDisplayMode(.inline)
        .refreshable {
            await search()
        }
        .task {
            guard !didLoad else { return }
            didLoad = true
            await search()
        }
    }

    private func resultRow(_ item: SearchResult) -> some View {
        let aspect = AppState.posterAspect(forSourceKey: item.source ?? "")
        let imageWidth: CGFloat = aspect > 1.1 ? 96 : 56

        return HStack(spacing: 12) {
            RemoteImage(url: app.imageURL(item.poster))
                .frame(width: imageWidth, height: imageWidth / aspect)
                .clipShape(RoundedRectangle(cornerRadius: 7, style: .continuous))

            VStack(alignment: .leading, spacing: 5) {
                Text(item.title)
                    .font(.system(size: 14, weight: .medium))
                    .foregroundColor(.white.opacity(0.94))
                    .lineLimit(2)

                Text(item.source_name ?? item.source ?? "未知来源")
                    .font(.system(size: 11.5))
                    .foregroundColor(Theme.textSecondary)
                    .lineLimit(1)

                HStack(spacing: 8) {
                    if let year = item.year, !year.isEmpty, year != "unknown" {
                        Text(year)
                    }
                    if item.episodeCount > 0 {
                        Text("\(item.episodeCount) 集")
                    }
                    if let remarks = item.vod_remarks, !remarks.isEmpty {
                        Text(remarks)
                    }
                }
                .font(.system(size: 10.5))
                .foregroundColor(Theme.textTertiary)
                .lineLimit(1)
            }

            Spacer(minLength: 0)

            Image(systemName: "chevron.right")
                .font(.system(size: 11, weight: .semibold))
                .foregroundColor(Theme.textTertiary)
        }
        .padding(.vertical, 5)
    }

    @MainActor
    private func search() async {
        isLoading = true
        errorMessage = nil
        do {
            let items = try await app.globalSearch(title)
            var seen = Set<String>()
            results = items.filter { item in
                let key = "\(item.source ?? "")+\(item.id)"
                guard !seen.contains(key) else { return false }
                seen.insert(key)
                return true
            }
        } catch APIError.unauthorized {
            app.logout()
        } catch {
            results = []
            errorMessage = error.localizedDescription
        }
        isLoading = false
    }
}
