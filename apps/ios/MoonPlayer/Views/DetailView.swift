import SwiftUI

struct DetailView: View {
    let sourceKey: String
    let videoID: String
    var previewTitle: String = ""
    var previewPoster: String?

    @EnvironmentObject private var app: AppState

    @State private var detail: VideoDetail?
    @State private var isLoading = true
    @State private var errorMessage: String?
    @State private var isFavorite = false
    @State private var showFullDescription = false
    @State private var playback: PlaybackContext?
    @State private var alertText = ""
    @State private var showAlert = false
    @State private var showSourcePicker = false
    @State private var activeSourceKey: String?
    @State private var activeVideoID: String?
    @State private var activeTitle: String?
    @State private var activePoster: String?

    private var currentSourceKey: String { activeSourceKey ?? sourceKey }
    private var currentVideoID: String { activeVideoID ?? videoID }
    private var currentTitle: String { activeTitle ?? previewTitle }
    private var currentPoster: String? { activePoster ?? previewPoster }

    private let episodeColumns = Array(
        repeating: GridItem(.flexible(), spacing: 8),
        count: 4
    )

    var body: some View {
        ScrollView {
            if let detail {
                content(detail)
            } else if isLoading {
                VStack(spacing: 14) {
                    ProgressView().tint(Theme.textSecondary)
                    Text("正在获取详情…")
                        .font(.system(size: 12.5))
                        .foregroundColor(Theme.textTertiary)
                }
                .frame(maxWidth: .infinity)
                .padding(.top, 120)
            } else {
                ErrorStateView(message: errorMessage ?? "获取详情失败") {
                    Task { await load() }
                }
                .padding(.top, 80)
            }
        }
        .background(Theme.background.ignoresSafeArea())
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                Button {
                    showSourcePicker = true
                } label: {
                    Image(systemName: "arrow.triangle.2.circlepath")
                }
                .accessibilityLabel("换源")
            }
        }
        .task { await load() }
        .refreshable { await load() }
        .fullScreenCover(item: $playback) { context in
            PlayerScreen(context: context)
                .environmentObject(app)
        }
        .sheet(isPresented: $showSourcePicker) {
            SourcePickerSheet(
                title: detail?.title ?? currentTitle,
                currentSourceKey: detail?.source ?? currentSourceKey
            ) { option in
                switchSource(option)
            }
        }
        .alert("提示", isPresented: $showAlert) {
            Button("好", role: .cancel) {}
        } message: {
            Text(alertText)
        }
    }

    // MARK: - 内容

    @ViewBuilder
    private func content(_ detail: VideoDetail) -> some View {
        VStack(alignment: .leading, spacing: 18) {
            header(detail)

            HStack(spacing: 12) {
                Button(action: playPrimary) {
                    HStack(spacing: 7) {
                        Image(systemName: "play.fill")
                            .font(.system(size: 13, weight: .bold))
                        Text(primaryButtonTitle(detail))
                            .font(.system(size: 15, weight: .semibold))
                            .lineLimit(1)
                    }
                    .foregroundColor(.white)
                    .frame(maxWidth: .infinity)
                    .frame(height: 46)
                    .background(Theme.accent)
                    .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                }
                .buttonStyle(.plain)
                .disabled(detail.episodeCount == 0)

                Button(action: toggleFavorite) {
                    Image(systemName: isFavorite ? "heart.fill" : "heart")
                        .font(.system(size: 18, weight: .medium))
                        .foregroundColor(isFavorite ? Theme.accent : .white.opacity(0.85))
                        .frame(width: 48, height: 46)
                        .background(Theme.surface)
                        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                        .overlay(
                            RoundedRectangle(cornerRadius: 12, style: .continuous)
                                .stroke(Theme.stroke, lineWidth: 0.6)
                        )
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 16)

            if detail.episodeCount == 0 {
                HStack(spacing: 8) {
                    Image(systemName: "exclamationmark.circle")
                    Text("该影片暂时没有可播放的 m3u8 选集，换一个源试试。")
                }
                .font(.system(size: 12.5))
                .foregroundColor(Theme.textSecondary)
                .padding(.horizontal, 16)
            }

            if let desc = detail.desc, !desc.isEmpty {
                descriptionSection(desc)
            }

            if detail.episodeCount > 0 {
                episodeSection(detail)
            }
        }
        .padding(.bottom, 30)
    }

    private func header(_ detail: VideoDetail) -> some View {
        let aspect = AppState.posterAspect(forSourceKey: detail.source ?? currentSourceKey)
        let posterWidth: CGFloat = aspect > 1.1 ? 150 : 108
        let posterHeight = posterWidth / aspect

        return ZStack(alignment: .bottom) {
            RemoteImage(url: app.imageURL(detail.poster ?? currentPoster))
                .frame(height: 210)
                .frame(maxWidth: .infinity)
                .clipped()
                .blur(radius: 26)
                .opacity(0.42)

            LinearGradient(
                colors: [.clear, Theme.background.opacity(0.55), Theme.background],
                startPoint: .top,
                endPoint: .bottom
            )
            .frame(height: 230)

            HStack(alignment: .bottom, spacing: 14) {
                RemoteImage(url: app.imageURL(detail.poster ?? currentPoster))
                    .frame(width: posterWidth, height: posterHeight)
                    .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                    .overlay(
                        RoundedRectangle(cornerRadius: 10, style: .continuous)
                            .stroke(Theme.stroke, lineWidth: 0.6)
                    )
                    .shadow(color: .black.opacity(0.45), radius: 12, y: 6)

                VStack(alignment: .leading, spacing: 7) {
                    Text(detail.title.isEmpty ? currentTitle : detail.title)
                        .font(.system(size: 19, weight: .bold))
                        .foregroundColor(.white)
                        .lineLimit(3)

                    let meta = metaText(detail)
                    if !meta.isEmpty {
                        Text(meta)
                            .font(.system(size: 11.5))
                            .foregroundColor(Theme.textSecondary)
                            .lineLimit(2)
                    }

                    if let remarks = detail.vod_remarks, !remarks.isEmpty {
                        Text(remarks)
                            .font(.system(size: 10.5, weight: .medium))
                            .foregroundColor(Theme.accent)
                            .lineLimit(1)
                    }

                    Text(detail.source_name ?? app.sourceName(for: currentSourceKey))
                        .font(.system(size: 10))
                        .foregroundColor(Theme.textTertiary)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 6)
        }
    }

    private func descriptionSection(_ desc: String) -> some View {
        VStack(alignment: .leading, spacing: 7) {
            Text("简介")
                .font(.system(size: 15, weight: .semibold))
                .foregroundColor(.white)

            Text(desc)
                .font(.system(size: 12.5))
                .lineSpacing(3)
                .foregroundColor(Theme.textSecondary)
                .lineLimit(showFullDescription ? nil : 4)

            if desc.count > 90 {
                Button(showFullDescription ? "收起" : "展开") {
                    withAnimation(.easeInOut(duration: 0.2)) {
                        showFullDescription.toggle()
                    }
                }
                .font(.system(size: 12, weight: .medium))
                .foregroundColor(Theme.accent)
            }
        }
        .padding(.horizontal, 16)
    }

    private func episodeSection(_ detail: VideoDetail) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("选集")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundColor(.white)
                Text("共 \(detail.episodeCount) 集")
                    .font(.system(size: 11))
                    .foregroundColor(Theme.textTertiary)
                Spacer()
                Button {
                    showSourcePicker = true
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: "arrow.triangle.2.circlepath")
                            .font(.system(size: 10, weight: .semibold))
                        Text("换源")
                            .font(.system(size: 11.5, weight: .medium))
                    }
                    .foregroundColor(Theme.accent)
                }
            }

            LazyVGrid(columns: episodeColumns, spacing: 8) {
                ForEach(Array((detail.episodes ?? []).indices), id: \.self) { index in
                    Button {
                        startPlayback(detail: detail, index: index, startTime: 0)
                    } label: {
                        Text(episodeTitle(detail, index))
                            .font(.system(size: 11.5, weight: .medium))
                            .foregroundColor(.white.opacity(0.9))
                            .lineLimit(1)
                            .frame(maxWidth: .infinity)
                            .frame(height: 34)
                            .background(
                                index == resumeIndex(detail)
                                    ? Theme.accentSoft
                                    : Theme.surface
                            )
                            .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                            .overlay(
                                RoundedRectangle(cornerRadius: 8, style: .continuous)
                                    .stroke(
                                        index == resumeIndex(detail)
                                            ? Theme.accent.opacity(0.65)
                                            : Theme.stroke,
                                        lineWidth: 0.6
                                    )
                            )
                    }
                    .buttonStyle(.plain)
                }
            }
        }
        .padding(.horizontal, 16)
    }

    // MARK: - 行为

    @MainActor
    private func load() async {
        if detail == nil { isLoading = true }
        errorMessage = nil
        do {
            let value = try await app.detail(
                sourceKey: currentSourceKey,
                videoID: currentVideoID,
                title: currentTitle
            )
            detail = value
            isLoading = false
            isFavorite = app.isFavorite(sourceKey: value.source ?? currentSourceKey, videoID: value.id)
        } catch APIError.unauthorized {
            app.logout()
        } catch {
            isLoading = false
            errorMessage = error.localizedDescription
        }
    }

    @MainActor
    private func switchSource(_ option: SourceOption) {
        activeSourceKey = option.sourceKey
        activeVideoID = option.result.id
        activeTitle = option.result.title
        activePoster = option.result.poster
        detail = nil
        isLoading = true
        errorMessage = nil
        Task { await load() }
    }

    private func playPrimary() {
        guard let detail, detail.episodeCount > 0 else { return }
        if let record = app.record(sourceKey: detail.source ?? currentSourceKey, videoID: detail.id) {
            let index = min(max(0, record.index - 1), detail.episodeCount - 1)
            startPlayback(detail: detail, index: index, startTime: record.playTime)
        } else {
            startPlayback(detail: detail, index: 0, startTime: 0)
        }
    }

    private func startPlayback(detail: VideoDetail, index: Int, startTime: Double) {
        guard let episodes = detail.episodes, !episodes.isEmpty else { return }
        let safeIndex = min(max(0, index), episodes.count - 1)
        let context = PlaybackContext(
            sourceKey: detail.source ?? currentSourceKey,
            sourceName: detail.source_name ?? app.sourceName(for: currentSourceKey),
            videoID: detail.id.isEmpty ? currentVideoID : detail.id,
            title: detail.title,
            cover: detail.poster ?? currentPoster ?? "",
            year: detail.year ?? "",
            episodes: episodes,
            episodeTitles: detail.episodes_titles ?? [],
            proxyMode: detail.proxyMode ?? false,
            startIndex: safeIndex,
            startTime: max(0, startTime)
        )
        playback = context
    }

    @MainActor
    private func toggleFavorite() {
        guard let detail else { return }
        Task {
            do {
                let nowFavorite = try await app.toggleFavorite(detail: detail, fallbackSourceKey: currentSourceKey)
                isFavorite = nowFavorite
                if nowFavorite { Haptics.success() } else { Haptics.light() }
            } catch {
                alertText = error.localizedDescription
                showAlert = true
            }
        }
    }

    // MARK: - 文案

    private func primaryButtonTitle(_ detail: VideoDetail) -> String {
        if let record = app.record(sourceKey: detail.source ?? currentSourceKey, videoID: detail.id) {
            return "继续观看 · 第\(record.index)集"
        }
        return "立即播放"
    }

    private func resumeIndex(_ detail: VideoDetail) -> Int? {
        guard let record = app.record(sourceKey: detail.source ?? currentSourceKey, videoID: detail.id) else {
            return nil
        }
        return min(max(0, record.index - 1), max(0, detail.episodeCount - 1))
    }

    private func episodeTitle(_ detail: VideoDetail, _ index: Int) -> String {
        if let titles = detail.episodes_titles, index < titles.count, !titles[index].isEmpty {
            return titles[index]
        }
        return "第\(index + 1)集"
    }

    private func metaText(_ detail: VideoDetail) -> String {
        var parts: [String] = []
        if let year = detail.year, !year.isEmpty, year != "unknown" {
            parts.append(year)
        }
        if let type = detail.type_name, !type.isEmpty {
            parts.append(type)
        }
        if detail.episodeCount > 0 {
            parts.append("\(detail.episodeCount) 集")
        }
        return parts.joined(separator: " · ")
    }
}
