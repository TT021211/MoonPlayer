import SwiftUI

struct HomeView: View {
    @EnvironmentObject private var app: AppState

    private let channelColumns = [
        GridItem(.flexible(), spacing: 12),
        GridItem(.flexible(), spacing: 12)
    ]

    var body: some View {
        NavigationStack {
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 24) {
                    greeting

                    if !app.records.isEmpty {
                        continueSection
                    }

                    if !app.sources.isEmpty {
                        channelSection
                    } else {
                        EmptyStateView(
                            symbol: "antenna.radiowaves.left.and.right.slash",
                            title: "还没有可用频道",
                            subtitle: "请确认服务器已配置视频源，然后下拉刷新"
                        )
                    }

                    if !app.favorites.isEmpty {
                        favoriteSection
                    }

                    if app.records.isEmpty && app.favorites.isEmpty {
                        EmptyStateView(
                            symbol: "play.rectangle.on.rectangle",
                            title: "从频道开始探索",
                            subtitle: "进入「频道」选择采集源，或到「搜索」查找想看的影片"
                        )
                    }
                }
                .padding(.horizontal, 16)
                .padding(.bottom, 28)
            }
            .background(Theme.background.ignoresSafeArea())
            .navigationTitle("首页")
            .navigationBarTitleDisplayMode(.large)
            .refreshable {
                await app.refreshAll()
            }
        }
    }

    private var greeting: some View {
        HStack(spacing: 8) {
            Circle()
                .fill(Theme.accent)
                .frame(width: 6, height: 6)
            Text(app.siteName)
                .font(.system(size: 12.5, weight: .medium))
                .foregroundColor(Theme.textSecondary)
            Spacer()
            Text("\(app.sources.count) 个频道")
                .font(.system(size: 11.5))
                .foregroundColor(Theme.textTertiary)
        }
        .padding(.top, 2)
    }

    private var continueSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            SectionHeader(title: "继续观看", trailing: "全部", action: nil)
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 12) {
                    ForEach(app.records.prefix(12)) { record in
                        NavigationLink {
                            DetailView(
                                sourceKey: record.source,
                                videoID: record.id,
                                previewTitle: record.title,
                                previewPoster: record.cover
                            )
                        } label: {
                            ContinueCard(record: record)
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.horizontal, 1)
            }
        }
    }

    private var channelSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            SectionHeader(title: "频道", trailing: "查看全部", action: nil)
            LazyVGrid(columns: channelColumns, spacing: 12) {
                ForEach(app.sources.prefix(8)) { source in
                    NavigationLink {
                        ChannelView(source: source)
                    } label: {
                        ChannelTile(source: source)
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    private var favoriteSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            SectionHeader(title: "我的收藏", trailing: "全部", action: nil)
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(alignment: .top, spacing: 12) {
                    ForEach(app.favorites.prefix(12)) { favorite in
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
                            .frame(width: 112)
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.horizontal, 1)
            }
        }
    }
}

// MARK: - 继续观看卡片

struct ContinueCard: View {
    let record: PlayRecordItem
    @EnvironmentObject private var app: AppState

    var body: some View {
        ZStack(alignment: .bottomLeading) {
            RemoteImage(url: app.imageURL(record.cover))
                .frame(width: 258, height: 145)
                .clipped()

            LinearGradient(
                colors: [.clear, .black.opacity(0.30), .black.opacity(0.92)],
                startPoint: .top,
                endPoint: .bottom
            )

            VStack(alignment: .leading, spacing: 5) {
                Text(record.title)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundColor(.white)
                    .lineLimit(2)

                Text("第\(record.index)集 · \(record.progressText)")
                    .font(.system(size: 10.5))
                    .foregroundColor(.white.opacity(0.68))

                GeometryReader { geo in
                    ZStack(alignment: .leading) {
                        Capsule().fill(Color.white.opacity(0.22))
                        Capsule()
                            .fill(Theme.accent)
                            .frame(width: max(2, geo.size.width * record.progress))
                    }
                }
                .frame(height: 3)
                .padding(.top, 2)
            }
            .padding(12)
        }
        .frame(width: 258, height: 145)
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .stroke(Theme.stroke, lineWidth: 0.5)
        )
    }
}

// MARK: - 频道磁贴

struct ChannelTile: View {
    let source: SourceItem

    var body: some View {
        HStack(spacing: 11) {
            ZStack {
                RoundedRectangle(cornerRadius: 11, style: .continuous)
                    .fill(AppState.channelColor(for: source.key).opacity(0.16))
                    .frame(width: 42, height: 42)
                Image(systemName: AppState.channelSymbol(for: source.key))
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundColor(AppState.channelColor(for: source.key))
            }

            VStack(alignment: .leading, spacing: 3) {
                Text(source.name)
                    .font(.system(size: 13.5, weight: .semibold))
                    .foregroundColor(.white.opacity(0.92))
                    .lineLimit(1)
                Text(source.host)
                    .font(.system(size: 10))
                    .foregroundColor(Theme.textTertiary)
                    .lineLimit(1)
            }

            Spacer(minLength: 0)
        }
        .padding(11)
        .background(Theme.surface)
        .clipShape(RoundedRectangle(cornerRadius: 13, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 13, style: .continuous)
                .stroke(Theme.stroke, lineWidth: 0.5)
        )
    }
}
