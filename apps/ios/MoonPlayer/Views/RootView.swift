import SwiftUI

struct RootView: View {
    @EnvironmentObject private var app: AppState

    var body: some View {
        ZStack {
            Theme.background.ignoresSafeArea()

            if app.isBooting {
                SplashView()
                    .transition(.opacity)
            } else if app.isLoggedIn {
                MainTabView()
                    .transition(.opacity)
            } else {
                LoginView()
                    .transition(.opacity)
            }

            if let toast = app.toast {
                VStack {
                    Spacer()
                    ToastView(text: toast)
                        .padding(.bottom, 96)
                }
                .transition(.move(edge: .bottom).combined(with: .opacity))
                .zIndex(10)
            }
        }
        .animation(.easeInOut(duration: 0.28), value: app.isLoggedIn)
        .animation(.easeInOut(duration: 0.2), value: app.isBooting)
        .animation(.easeInOut(duration: 0.2), value: app.toast)
        .task {
            await app.bootstrap()
        }
    }
}

struct SplashView: View {
    @State private var appeared = false

    var body: some View {
        VStack(spacing: 18) {
            ZStack {
                Circle()
                    .fill(Theme.accent.opacity(0.16))
                    .frame(width: 96, height: 96)
                Image(systemName: "moon.stars.fill")
                    .font(.system(size: 42, weight: .medium))
                    .foregroundColor(Theme.accent)
            }
            .scaleEffect(appeared ? 1 : 0.86)
            .opacity(appeared ? 1 : 0)

            Text("MoonPlayer")
                .font(.system(size: 24, weight: .bold))
                .foregroundColor(.white)

            ProgressView()
                .tint(Theme.textSecondary)
                .padding(.top, 4)
        }
        .onAppear {
            withAnimation(.easeOut(duration: 0.45)) { appeared = true }
        }
    }
}
