import SwiftUI

struct SettingsView: View {
    @EnvironmentObject private var app: AppState

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
            } header: {
                Text("播放")
            } footer: {
                Text("默认开启。关闭后直连原片；播放失败会自动在「缓存代理 / 直连」之间切换一次。需要服务端已更新分片代理路由。")
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
