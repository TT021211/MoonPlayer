import SwiftUI

struct SettingsView: View {
    @EnvironmentObject private var app: AppState

    @State private var localCacheText = "计算中…"

    var body: some View {
        List {
            Section {
                Toggle(isOn: $app.forceProxy) {
                    VStack(alignment: .leading, spacing: 3) {
                        Text("边看边缓存（服务端代理）")
                            .font(.system(size: 15))
                            .foregroundColor(.white.opacity(0.92))
                        Text("播放列表和分片经服务器边下边存：列表 1 小时、分片 72 小时，手机不占空间")
                            .font(.system(size: 11))
                            .foregroundColor(Theme.textTertiary)
                    }
                }
                .tint(Theme.accent)
                .listRowBackground(Theme.surface)

                Toggle(isOn: $app.localCacheEnabled) {
                    VStack(alignment: .leading, spacing: 3) {
                        Text("手机本地缓存（边看边存）")
                            .font(.system(size: 15))
                            .foregroundColor(.white.opacity(0.92))
                        Text("播放列表和分片存到手机，提前预取；网络抖动时直接读本地，最多 2GB")
                            .font(.system(size: 11))
                            .foregroundColor(Theme.textTertiary)
                    }
                }
                .tint(Theme.accent)
                .listRowBackground(Theme.surface)
            } header: {
                Text("播放")
            } footer: {
                Text("服务端缓存解决 VPS 到源站；手机本地缓存解决手机到 VPS，并支持已缓存部分离线播放。播放失败会自动逐级降级。")
                    .font(.system(size: 11))
                    .foregroundColor(Theme.textTertiary.opacity(0.85))
            }

            Section("服务器") {
                infoRow("地址", app.serverURL)
                infoRow("站点", app.siteName)
                infoRow("频道", "\(app.sources.count) 个")
                infoRow("账号", app.username)
            }

            Section("缓存") {
                infoRow("本地视频缓存", localCacheText)

                Button {
                    LocalHLSServer.shared.clearCache()
                    refreshLocalCacheSize()
                    app.showToast("本地视频缓存已清除")
                } label: {
                    Text("清除本地视频缓存")
                        .font(.system(size: 15))
                        .foregroundColor(Theme.accent)
                }
                .listRowBackground(Theme.surface)

                Button {
                    ImageCache.shared.clear()
                    app.showToast("图片缓存已清除")
                } label: {
                    Text("清除图片缓存")
                        .font(.system(size: 15))
                        .foregroundColor(Theme.accent)
                }
                .listRowBackground(Theme.surface)
            }

            Section("关于") {
                infoRow("客户端", "MoonPlayer iOS 1.0.0")
                infoRow("构建", "Unsigned / GitHub Actions")
                infoRow("说明", "内容来自第三方采集源，本站不存储任何视频")
            }
        }
        .listStyle(.insetGrouped)
        .scrollContentBackground(.hidden)
        .background(Theme.background.ignoresSafeArea())
        .navigationTitle("播放与服务器")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear {
            refreshLocalCacheSize()
        }
    }

    private func refreshLocalCacheSize() {
        let bytes = LocalHLSServer.shared.cacheSizeBytes
        localCacheText = ByteCountFormatter.string(fromByteCount: bytes, countStyle: .file)
    }

    private func infoRow(_ title: String, _ value: String) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Text(title)
                .font(.system(size: 14))
                .foregroundColor(Theme.textSecondary)
                .frame(width: 54, alignment: .leading)
            Text(value)
                .font(.system(size: 13.5))
                .foregroundColor(.white.opacity(0.9))
                .multilineTextAlignment(.trailing)
                .frame(maxWidth: .infinity, alignment: .trailing)
        }
        .padding(.vertical, 2)
        .listRowBackground(Theme.surface)
    }
}
