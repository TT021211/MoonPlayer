import SwiftUI

struct LoginView: View {
    @EnvironmentObject private var app: AppState

    @State private var server = AppState.defaultServer
    @State private var username = ""
    @State private var password = ""
    @State private var isLoading = false
    @State private var errorMessage: String?
    @FocusState private var focused: Field?

    private enum Field {
        case server
        case username
        case password
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 0) {
                header
                form
                footer
            }
            .padding(.horizontal, 24)
            .padding(.top, 56)
            .padding(.bottom, 32)
            .frame(maxWidth: 520)
            .frame(maxWidth: .infinity)
        }
        .scrollDismissesKeyboard(.interactively)
        .background(background)
        .onAppear {
            if server.isEmpty { server = AppState.defaultServer }
            if let stored = UserDefaults.standard.string(forKey: "moon.server"), !stored.isEmpty {
                server = stored
            }
            if username.isEmpty {
                username = UserDefaults.standard.string(forKey: "moon.username") ?? ""
            }
            if let bootError = app.bootError, !bootError.isEmpty {
                errorMessage = bootError
            }
        }
    }

    private var background: some View {
        ZStack {
            Theme.background
            RadialGradient(
                colors: [Theme.accent.opacity(0.22), .clear],
                center: .topTrailing,
                startRadius: 10,
                endRadius: 380
            )
            RadialGradient(
                colors: [Color(red: 0.25, green: 0.35, blue: 0.75).opacity(0.20), .clear],
                center: .bottomLeading,
                startRadius: 10,
                endRadius: 420
            )
        }
        .ignoresSafeArea()
    }

    private var header: some View {
        VStack(spacing: 14) {
            ZStack {
                Circle()
                    .fill(Theme.accent.opacity(0.14))
                    .frame(width: 92, height: 92)
                    .overlay(Circle().stroke(Theme.accent.opacity(0.35), lineWidth: 1))
                Image(systemName: "moon.stars.fill")
                    .font(.system(size: 40, weight: .medium))
                    .foregroundColor(Theme.accent)
            }

            Text("MoonPlayer")
                .font(.system(size: 28, weight: .bold))
                .foregroundColor(.white)

            Text("登录你的自建影库")
                .font(.system(size: 14))
                .foregroundColor(Theme.textSecondary)
        }
        .padding(.bottom, 36)
    }

    private var form: some View {
        VStack(spacing: 14) {
            fieldShell(symbol: "server.rack") {
                TextField("服务器地址", text: $server)
                    .keyboardType(.URL)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .textContentType(.URL)
                    .focused($focused, equals: .server)
                    .submitLabel(.next)
                    .onSubmit { focused = .username }
                    .foregroundColor(.white)
            }

            fieldShell(symbol: "person") {
                TextField("用户名", text: $username)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .textContentType(.username)
                    .focused($focused, equals: .username)
                    .submitLabel(.next)
                    .onSubmit { focused = .password }
                    .foregroundColor(.white)
            }

            fieldShell(symbol: "lock") {
                SecureField("密码", text: $password)
                    .textContentType(.password)
                    .focused($focused, equals: .password)
                    .submitLabel(.go)
                    .onSubmit { submit() }
                    .foregroundColor(.white)
            }

            if let errorMessage {
                HStack(alignment: .top, spacing: 7) {
                    Image(systemName: "exclamationmark.circle.fill")
                        .font(.system(size: 12))
                        .padding(.top, 1)
                    Text(errorMessage)
                        .font(.system(size: 12.5))
                        .multilineTextAlignment(.leading)
                }
                .foregroundColor(Theme.accent)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 4)
            }

            Button(action: submit) {
                ZStack {
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .fill(canSubmit ? Theme.accent : Theme.surfaceHigh)
                    if isLoading {
                        ProgressView().tint(.white)
                    } else {
                        Text("登录")
                            .font(.system(size: 16, weight: .semibold))
                            .foregroundColor(canSubmit ? .white : Theme.textTertiary)
                    }
                }
                .frame(height: 50)
            }
            .buttonStyle(.plain)
            .disabled(!canSubmit || isLoading)
            .padding(.top, 6)
        }
        .padding(20)
        .background(Theme.surface.opacity(0.88))
        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .stroke(Theme.stroke, lineWidth: 0.6)
        )
    }

    private var footer: some View {
        VStack(spacing: 6) {
            Text("内容来自第三方采集源，本站不存储任何视频")
                .font(.system(size: 11))
                .foregroundColor(Theme.textTertiary)
            Text("MoonPlayer iOS · 1.0.0")
                .font(.system(size: 10.5))
                .foregroundColor(Theme.textTertiary.opacity(0.8))
        }
        .padding(.top, 26)
    }

    private var canSubmit: Bool {
        !server.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && !username.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && !password.isEmpty
    }

    private func fieldShell<Content: View>(
        symbol: String,
        @ViewBuilder content: () -> Content
    ) -> some View {
        HStack(spacing: 11) {
            Image(systemName: symbol)
                .font(.system(size: 14, weight: .medium))
                .foregroundColor(Theme.textTertiary)
                .frame(width: 18)
            content()
                .font(.system(size: 15))
        }
        .padding(.horizontal, 14)
        .frame(height: 48)
        .background(Theme.background.opacity(0.72))
        .clipShape(RoundedRectangle(cornerRadius: 11, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 11, style: .continuous)
                .stroke(Theme.stroke, lineWidth: 0.6)
        )
    }

    @MainActor
    private func submit() {
        guard canSubmit, !isLoading else { return }
        focused = nil
        isLoading = true
        errorMessage = nil
        Task {
            do {
                try await app.login(server: server, username: username, password: password)
            } catch {
                errorMessage = error.localizedDescription
            }
            isLoading = false
        }
    }
}
