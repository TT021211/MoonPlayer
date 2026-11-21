import SwiftUI

struct ProfileView: View {
    @EnvironmentObject private var app: AppState
    @State private var showLogoutConfirm = false

    var body: some View {
        NavigationStack {
            List {
                Section {
                    HStack(spacing: 14) {
                        ZStack {
                            Circle()
                                .fill(Theme.accent.opacity(0.18))
                                .frame(width: 58, height: 58)
                            Text(String(app.username.prefix(1)).uppercased())
                                .font(.system(size: 22, weight: .bold))
                                .foregroundColor(Theme.accent)
                        }

                        VStack(alignment: .leading, spacing: 4) {
                            Text(app.username.isEmpty ? "已登录" : app.username)
                                .font(.system(size: 17, weight: .semibold))
                                .foregroundColor(.white)
                            Text(app.siteName)
                                .font(.system(size: 12))
                                .foregroundColor(Theme.textSecondary)
                            Text(app.serverURL)
                                .font(.system(size: 10.5))
                                .foregroundColor(Theme.textTertiary)
                                .lineLimit(1)
                        }
                    }
                    .padding(.vertical, 6)
                    .listRowBackground(Color.clear)
                }

                Section("我的") {
                    NavigationLink {
                        FavoritesView()
                    } label: {
                        row(symbol: "heart.fill", color: Theme.accent, title: "我的收藏", count: app.favorites.count)
                    }
                    .listRowBackground(Theme.surface)

                    NavigationLink {
                        HistoryView()
                    } label: {
                        row(symbol: "clock.arrow.circlepath", color: Color(red: 0.30, green: 0.62, blue: 0.95), title: "播放历史", count: app.records.count)
                    }
                    .listRowBackground(Theme.surface)
                }

                Section("设置") {
                    NavigationLink {
                        SettingsView()
                    } label: {
                        HStack(spacing: 12) {
                            Image(systemName: "gearshape.fill")
                                .font(.system(size: 15))
                                .foregroundColor(Color(red: 0.65, green: 0.65, blue: 0.72))
                                .frame(width: 24)
                            Text("播放与服务器")
                                .font(.system(size: 15))
                                .foregroundColor(.white.opacity(0.92))
                        }
                        .padding(.vertical, 2)
                    }
                    .listRowBackground(Theme.surface)
                }

                Section {
                    Button(role: .destructive) {
                        showLogoutConfirm = true
                    } label: {
                        HStack {
                            Spacer()
                            Text("退出登录")
                                .font(.system(size: 15, weight: .medium))
                            Spacer()
                        }
                    }
                    .listRowBackground(Theme.surface)
                }

                Section {
                    VStack(spacing: 5) {
                        Text("MoonPlayer iOS 1.0.0")
                            .font(.system(size: 11))
                            .foregroundColor(Theme.textTertiary)
                        Text("内容来自第三方采集源，本站不存储任何视频")
                            .font(.system(size: 10))
                            .foregroundColor(Theme.textTertiary.opacity(0.8))
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 8)
                    .listRowBackground(Color.clear)
                }
            }
            .listStyle(.insetGrouped)
            .scrollContentBackground(.hidden)
            .background(Theme.background.ignoresSafeArea())
            .navigationTitle("我的")
            .navigationBarTitleDisplayMode(.large)
            .refreshable {
                await app.refreshLibrary()
            }
            .confirmationDialog("确定退出登录？", isPresented: $showLogoutConfirm, titleVisibility: .visible) {
                Button("退出登录", role: .destructive) {
                    app.logout()
                }
                Button("取消", role: .cancel) {}
            }
        }
    }

    private func row(symbol: String, color: Color, title: String, count: Int) -> some View {
        HStack(spacing: 12) {
            Image(systemName: symbol)
                .font(.system(size: 15))
                .foregroundColor(color)
                .frame(width: 24)
            Text(title)
                .font(.system(size: 15))
                .foregroundColor(.white.opacity(0.92))
            Spacer()
            Text("\(count)")
                .font(.system(size: 13))
                .foregroundColor(Theme.textTertiary)
        }
        .padding(.vertical, 2)
    }
}
