import SwiftUI

struct ChannelsView: View {
    @EnvironmentObject private var app: AppState

    var body: some View {
        NavigationStack {
            List {
                if app.sources.isEmpty {
                    EmptyStateView(
                        symbol: "antenna.radiowaves.left.and.right.slash",
                        title: "暂无可用频道",
                        subtitle: "请确认服务器已配置视频源，然后下拉刷新"
                    )
                    .listRowBackground(Color.clear)
                    .listRowSeparator(.hidden)
                } else {
                    Section {
                        ForEach(app.sources) { source in
                            NavigationLink {
                                ChannelView(source: source)
                            } label: {
                                HStack(spacing: 12) {
                                    ZStack {
                                        RoundedRectangle(cornerRadius: 10, style: .continuous)
                                            .fill(AppState.channelColor(for: source.key).opacity(0.16))
                                            .frame(width: 40, height: 40)
                                        Image(systemName: AppState.channelSymbol(for: source.key))
                                            .font(.system(size: 16, weight: .semibold))
                                            .foregroundColor(AppState.channelColor(for: source.key))
                                    }

                                    VStack(alignment: .leading, spacing: 3) {
                                        Text(source.name)
                                            .font(.system(size: 15, weight: .medium))
                                            .foregroundColor(.white.opacity(0.94))
                                            .lineLimit(1)
                                        Text(source.host)
                                            .font(.system(size: 11))
                                            .foregroundColor(Theme.textTertiary)
                                            .lineLimit(1)
                                    }
                                }
                                .padding(.vertical, 3)
                            }
                            .listRowBackground(Theme.surface)
                        }
                    } header: {
                        Text("共 \(app.sources.count) 个采集源")
                            .font(.system(size: 12))
                            .foregroundColor(Theme.textTertiary)
                    } footer: {
                        Text("频道由 maccms-hub 自建刮削网关提供，内容来自第三方站点。")
                            .font(.system(size: 11))
                            .foregroundColor(Theme.textTertiary.opacity(0.85))
                    }
                }
            }
            .listStyle(.insetGrouped)
            .scrollContentBackground(.hidden)
            .background(Theme.background.ignoresSafeArea())
            .navigationTitle("频道")
            .navigationBarTitleDisplayMode(.large)
            .refreshable {
                await app.refreshSources()
            }
        }
    }
}
