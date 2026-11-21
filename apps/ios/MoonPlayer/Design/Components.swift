import SwiftUI
import UIKit

// MARK: - 远程图片

struct RemoteImage: View {
    let url: URL?
    var contentMode: ContentMode = .fill

    @StateObject private var loader = RemoteImageLoader()

    var body: some View {
        ZStack {
            if let image = loader.image {
                Image(uiImage: image)
                    .resizable()
                    .aspectRatio(contentMode: contentMode)
            } else {
                placeholder(symbol: "photo")
                    .overlay {
                        if loader.isLoading {
                            ProgressView()
                                .progressViewStyle(.circular)
                                .tint(.white.opacity(0.45))
                                .scaleEffect(0.8)
                        }
                    }
            }
        }
        .onAppear { loader.load(url) }
        .onChange(of: url) { value in loader.load(value) }
    }

    private func placeholder(symbol: String) -> some View {
        ZStack {
            LinearGradient(
                colors: [Theme.surfaceHigh, Theme.surface],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            Image(systemName: symbol)
                .font(.system(size: 22, weight: .light))
                .foregroundColor(.white.opacity(0.22))
        }
    }
}

final class RemoteImageLoader: ObservableObject {
    @Published private(set) var image: UIImage?
    @Published private(set) var isLoading = false

    private var current: URL?
    private var task: Task<Void, Never>?

    func load(_ url: URL?) {
        if current == url { return }
        current = url
        task?.cancel()
        image = nil

        guard let url else {
            isLoading = false
            return
        }
        if let hit = ImageCache.shared.cached(url) {
            image = hit
            isLoading = false
            return
        }

        isLoading = true
        task = Task { [weak self] in
            let fetched = await ImageCache.shared.load(url)
            guard !Task.isCancelled else { return }
            DispatchQueue.main.async {
                self?.image = fetched
                self?.isLoading = false
            }
        }
    }
}

// MARK: - 海报卡

struct PosterCard: View {
    let title: String
    let poster: String?
    var badge: String?
    var year: String?
    var sourceName: String?
    /// 宽 / 高：竖版 2/3，横版 16/9、3/2
    var aspect: CGFloat = 2.0 / 3.0

    @EnvironmentObject private var app: AppState

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            ZStack(alignment: .topTrailing) {
                Color.clear
                    .aspectRatio(aspect, contentMode: .fit)
                    .overlay(
                        RemoteImage(url: app.imageURL(poster))
                    )
                    .clipShape(RoundedRectangle(cornerRadius: Theme.posterRadius, style: .continuous))
                    .overlay(
                        RoundedRectangle(cornerRadius: Theme.posterRadius, style: .continuous)
                            .stroke(Theme.stroke, lineWidth: 0.5)
                    )

                if let badge, !badge.isEmpty {
                    Text(badge)
                        .font(.system(size: 9, weight: .semibold))
                        .foregroundColor(.white)
                        .lineLimit(1)
                        .padding(.horizontal, 5)
                        .padding(.vertical, 2.5)
                        .background(Color.black.opacity(0.62))
                        .clipShape(RoundedRectangle(cornerRadius: 4, style: .continuous))
                        .padding(5)
                }
            }

            Text(title)
                .font(.system(size: 12.5, weight: .medium))
                .foregroundColor(.white.opacity(0.92))
                .lineLimit(2)
                .multilineTextAlignment(.leading)
                .frame(maxWidth: .infinity, alignment: .leading)

            if let sourceName, !sourceName.isEmpty {
                Text(sourceName)
                    .font(.system(size: 10))
                    .foregroundColor(Theme.textTertiary)
                    .lineLimit(1)
            } else if let year, !year.isEmpty, year != "unknown" {
                Text(year)
                    .font(.system(size: 10))
                    .foregroundColor(Theme.textTertiary)
            }
        }
    }
}

// MARK: - 分类胶囊

struct ChipButton: View {
    let title: String
    var selected: Bool = false
    var action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(title)
                .font(.system(size: 13, weight: selected ? .semibold : .regular))
                .foregroundColor(selected ? .white : Color.white.opacity(0.78))
                .lineLimit(1)
                .padding(.horizontal, 13)
                .padding(.vertical, 7)
                .background(selected ? Theme.accent : Theme.surfaceHigh)
                .clipShape(Capsule())
        }
        .buttonStyle(.plain)
    }
}

// MARK: - 区块标题

struct SectionHeader: View {
    let title: String
    var trailing: String?
    var destination: AnyView?
    var action: (() -> Void)?

    var body: some View {
        HStack(alignment: .firstTextBaseline) {
            Text(title)
                .font(.system(size: 19, weight: .bold))
                .foregroundColor(.white)
            Spacer()
            if let trailing {
                if let destination {
                    NavigationLink(destination: destination) {
                        Text(trailing)
                            .font(.system(size: 12.5, weight: .medium))
                            .foregroundColor(Theme.textSecondary)
                    }
                } else if let action {
                    Button(action: action) {
                        Text(trailing)
                            .font(.system(size: 12.5, weight: .medium))
                            .foregroundColor(Theme.textSecondary)
                    }
                } else {
                    Text(trailing)
                        .font(.system(size: 12.5))
                        .foregroundColor(Theme.textTertiary)
                }
            }
        }
    }
}

// MARK: - 状态视图

struct EmptyStateView: View {
    let symbol: String
    let title: String
    var subtitle: String?

    var body: some View {
        VStack(spacing: 10) {
            Image(systemName: symbol)
                .font(.system(size: 34, weight: .light))
                .foregroundColor(.white.opacity(0.25))
            Text(title)
                .font(.system(size: 15, weight: .semibold))
                .foregroundColor(.white.opacity(0.72))
            if let subtitle {
                Text(subtitle)
                    .font(.system(size: 12.5))
                    .foregroundColor(Theme.textTertiary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 32)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 42)
    }
}

struct ErrorStateView: View {
    let message: String
    var retry: (() -> Void)?

    var body: some View {
        VStack(spacing: 12) {
            Image(systemName: "exclamationmark.triangle")
                .font(.system(size: 30, weight: .light))
                .foregroundColor(Theme.accent.opacity(0.85))
            Text(message)
                .font(.system(size: 13))
                .foregroundColor(Theme.textSecondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 28)
            if let retry {
                Button("重试", action: retry)
                    .font(.system(size: 13, weight: .semibold))
                    .padding(.horizontal, 18)
                    .padding(.vertical, 8)
                    .background(Theme.surfaceHigh)
                    .clipShape(Capsule())
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 36)
    }
}

// MARK: - 轻提示

struct ToastView: View {
    let text: String

    var body: some View {
        Text(text)
            .font(.system(size: 13, weight: .medium))
            .foregroundColor(.white)
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
            .background(.ultraThinMaterial)
            .clipShape(Capsule())
            .shadow(color: .black.opacity(0.25), radius: 10, y: 4)
    }
}

// MARK: - 渐变遮罩

struct BottomFade: View {
    var height: CGFloat = 90

    var body: some View {
        LinearGradient(
            colors: [.clear, Color.black.opacity(0.9)],
            startPoint: .top,
            endPoint: .bottom
        )
        .frame(height: height)
        .allowsHitTesting(false)
    }
}
