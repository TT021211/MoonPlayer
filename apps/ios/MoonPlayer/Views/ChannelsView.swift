import SwiftUI

struct ChannelsView: View {
    @EnvironmentObject private var app: AppState

    @State private var missingChannel: ChannelDef?

    private let columns = [
        GridItem(.flexible(), spacing: 12),
        GridItem(.flexible(), spacing: 12)
    ]

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    Text("与网页端一致的频道入口")
                        .font(.system(size: 12))
                        .foregroundColor(Theme.textTertiary)

                    channelSection(title: "影视", channels: ChannelCatalog.video)
                    channelSection(title: "剧场", channels: ChannelCatalog.theater)

                    if app.sources.isEmpty {
                        HStack(spacing: 8) {
                            ProgressView().tint(Theme.textTertiary)
                            Text("正在同步采集源…")
                                .font(.system(size: 12))
                                .foregroundColor(Theme.textTertiary)
                            Spacer()
                            Button("重新加载") {
                                Task { await app.refreshSources() }
                            }
                            .font(.system(size: 12, weight: .medium))
                            .foregroundColor(Theme.accent)
                        }
                        .padding(.top, 4)
                    }
                }
                .padding(.horizontal, 16)
                .padding(.top, 8)
                .padding(.bottom, 28)
            }
            .background(Theme.background.ignoresSafeArea())
            .navigationTitle("频道")
            .navigationBarTitleDisplayMode(.large)
            .refreshable {
                await app.refreshSources()
            }
            .alert(
                "频道未配置",
                isPresented: Binding(
                    get: { missingChannel != nil },
                    set: { if !$0 { missingChannel = nil } }
                )
            ) {
                Button("好", role: .cancel) { missingChannel = nil }
            } message: {
                Text("请先在后台源管理中配置「\(missingChannel?.title ?? "")」对应的采集源，然后下拉刷新。")
            }
        }
    }

    private func channelSection(title: String, channels: [ChannelDef]) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            SectionHeader(title: title, trailing: nil, action: nil)

            LazyVGrid(columns: columns, spacing: 12) {
                ForEach(channels) { channel in
                    channelLink(channel)
                }
            }
        }
    }

    @ViewBuilder
    private func channelLink(_ channel: ChannelDef) -> some View {
        if let kind = channel.doubanKind {
            NavigationLink {
                DoubanListView(kind: kind)
            } label: {
                ChannelCatalogTile(channel: channel, configured: true)
            }
            .buttonStyle(.plain)
        } else if let sourceKey = channel.sourceKey,
                  let source = app.sourceForChannel(sourceKey) {
            NavigationLink {
                ChannelView(
                    source: source,
                    channelTitle: channel.title,
                    posterAspect: ChannelCatalog.posterAspect(for: channel)
                )
            } label: {
                ChannelCatalogTile(channel: channel, configured: true)
            }
            .buttonStyle(.plain)
        } else {
            Button {
                missingChannel = channel
            } label: {
                ChannelCatalogTile(channel: channel, configured: false)
            }
            .buttonStyle(.plain)
        }
    }
}

struct ChannelCatalogTile: View {
    let channel: ChannelDef
    var configured: Bool

    var body: some View {
        HStack(spacing: 11) {
            ZStack {
                RoundedRectangle(cornerRadius: 11, style: .continuous)
                    .fill(ChannelCatalog.color(for: channel).opacity(0.16))
                    .frame(width: 42, height: 42)
                Image(systemName: ChannelCatalog.symbol(for: channel))
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundColor(ChannelCatalog.color(for: channel))
            }

            VStack(alignment: .leading, spacing: 3) {
                Text(channel.title)
                    .font(.system(size: 13.5, weight: .semibold))
                    .foregroundColor(.white.opacity(0.92))
                    .lineLimit(1)
                Text(configured ? channel.subtitle : "未配置采集源")
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
        .opacity(configured ? 1 : 0.55)
    }
}
