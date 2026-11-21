import SwiftUI

struct SettingsView: View {
    @EnvironmentObject private var app: AppState

    var body: some View {
        List {
            Section {
                Toggle(isOn: $app.forceProxy) {
                    VStack(alignment: .leading, spacing: 3) {
                        Text("强制服务端代理播放")
                            .font(.system(size: 15))
                            .foregroundColor(.white.opacity(0.92))
                        Text("直连失败或片源限制 Referer 时，改走服务器的 m3u8 代理")
                            .font(.system(size: 11))
                            .foregroundColor(Theme.textTertiary)
                    }
                }
                .tint(Theme.accent)
                .listRowBackground(Theme.surface)
            } header: {
                Text("播放")
            } footer: {
                Text("播放器默认直连；遇到黑屏、403 或一直转圈时会自动尝试一次服务端代理。")
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
