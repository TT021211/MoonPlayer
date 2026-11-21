import SwiftUI

struct FavoritesView: View {
    @EnvironmentObject private var app: AppState

    private let columns = [
        GridItem(.adaptive(minimum: 102), spacing: 12)
    ]

    var body: some View {
        ScrollView {
            if app.favorites.isEmpty {
                EmptyStateView(
                    symbol: "heart",
                    title: "还没有收藏",
                    subtitle: "在影片详情页点右上角的心形按钮即可收藏"
                )
                .padding(.top, 70)
            } else {
                LazyVGrid(columns: columns, alignment: .leading, spacing: 16) {
                    ForEach(app.favorites) { favorite in
                        NavigationLink {
                            DetailView(
                                sourceKey: favorite.source,
                                videoID: favorite.id,
                                previewTitle: favorite.title,
                                previewPoster: favorite.cover
                            )
                        } label: {
                            PosterCard(
                                title: favorite.title,
                                poster: favorite.cover,
                                badge: favorite.remarks,
                                year: favorite.year,
                                sourceName: favorite.sourceName
                            )
                        }
                        .buttonStyle(.plain)
                        .contextMenu {
                            Button(role: .destructive) {
                                Task { await app.deleteFavorite(key: favorite.key) }
                            } label: {
                                Label("取消收藏", systemImage: "heart.slash")
                            }
                        }
                    }
                }
                .padding(14)
            }
        }
        .background(Theme.background.ignoresSafeArea())
        .navigationTitle("我的收藏")
        .navigationBarTitleDisplayMode(.inline)
        .refreshable {
            await app.refreshFavorites()
        }
    }
}

struct HistoryView: View {
    @EnvironmentObject private var app: AppState

    var body: some View {
        List {
            if app.records.isEmpty {
                EmptyStateView(
                    symbol: "clock",
                    title: "还没有播放记录",
                    subtitle: "看过的影片会自动出现在这里，方便继续观看"
                )
                .listRowBackground(Color.clear)
                .listRowSeparator(.hidden)
            } else {
                ForEach(app.records) { record in
                    NavigationLink {
                        DetailView(
                            sourceKey: record.source,
                            videoID: record.id,
                            previewTitle: record.title,
                            previewPoster: record.cover
                        )
                    } label: {
                        HStack(spacing: 12) {
                            RemoteImage(url: app.imageURL(record.cover))
                                .frame(width: 62, height: 88)
                                .clipShape(RoundedRectangle(cornerRadius: 7, style: .continuous))

                            VStack(alignment: .leading, spacing: 5) {
                                Text(record.title)
                                    .font(.system(size: 14, weight: .medium))
                                    .foregroundColor(.white.opacity(0.94))
                                    .lineLimit(2)

                                Text("第\(record.index)集 · \(record.sourceName)")
                                    .font(.system(size: 11))
                                    .foregroundColor(Theme.textSecondary)
                                    .lineLimit(1)

                                if record.progress > 0 {
                                    GeometryReader { geo in
                                        ZStack(alignment: .leading) {
                                            Capsule().fill(Color.white.opacity(0.14))
                                            Capsule()
                                                .fill(Theme.accent)
                                                .frame(width: max(2, geo.size.width * record.progress))
                                        }
                                    }
                                    .frame(height: 3)
                                    .padding(.top, 1)

                                    Text(record.progressText)
                                        .font(.system(size: 10).monospacedDigit())
                                        .foregroundColor(Theme.textTertiary)
                                }
                            }
                        }
                        .padding(.vertical, 3)
                    }
                    .listRowBackground(Theme.surface)
                    .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                        Button(role: .destructive) {
                            Task { await app.deleteRecord(key: record.key) }
                        } label: {
                            Label("删除", systemImage: "trash")
                        }
                    }
                }
            }
        }
        .listStyle(.plain)
        .scrollContentBackground(.hidden)
        .background(Theme.background.ignoresSafeArea())
        .navigationTitle("播放历史")
        .navigationBarTitleDisplayMode(.inline)
        .refreshable {
            await app.refreshRecords()
        }
    }
}
