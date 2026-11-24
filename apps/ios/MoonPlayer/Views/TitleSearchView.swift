import Foundation
import SwiftUI

// MARK: - 片源选择模型

final class SourcePickerModel: ObservableObject {
    let title: String

    @Published private(set) var options: [SourceOption] = []
    @Published private(set) var isLoading = true
    @Published private(set) var errorMessage: String?

    private weak var app: AppState?
    private var probeTask: Task<Void, Never>?
    private var didLoad = false

    init(title: String) {
        self.title = title
    }

    @MainActor
    func configure(app: AppState) {
        self.app = app
        if didLoad {
            if options.contains(where: { $0.state == .pending }) {
                startProbes()
            }
            return
        }
        didLoad = true
        Task { await self.search() }
    }

    @MainActor
    func cancel() {
        probeTask?.cancel()
        for index in options.indices where options[index].state == .probing {
            options[index].state = .pending
        }
    }

    @MainActor
    func search() async {
        guard let app else { return }
        probeTask?.cancel()
        isLoading = true
        errorMessage = nil
        options = []

        do {
            let results = try await app.globalSearch(title)
            var seen = Set<String>()
            let deduped = results.filter { item in
                let key = "\(item.source ?? "")+\(item.id)"
                guard !seen.contains(key) else { return false }
                seen.insert(key)
                return true
            }
            options = makeOptions(from: deduped, app: app)
            isLoading = false
            startProbes()
        } catch APIError.unauthorized {
            app.logout()
        } catch {
            isLoading = false
            errorMessage = error.localizedDescription
        }
    }

    @MainActor
    var recommendedOption: SourceOption? {
        let ready = options.filter { $0.state == .ready && $0.episodeCount > 0 }
        guard !ready.isEmpty else { return nil }
        return ready.max { recommendationScore($0) < recommendationScore($1) }
    }

    // MARK: 分组

    private func makeOptions(from results: [SearchResult], app: AppState) -> [SourceOption] {
        var groups: [String: [SearchResult]] = [:]
        var order: [String] = []

        for result in results {
            guard let sourceKey = result.source, !sourceKey.isEmpty else { continue }
            if groups[sourceKey] == nil { order.append(sourceKey) }
            groups[sourceKey, default: []].append(result)
        }

        return order.compactMap { sourceKey -> SourceOption? in
            let items = groups[sourceKey] ?? []
            guard let best = bestMatch(in: items) else { return nil }
            let initialQuality = qualityFromLabels(
                [best.vod_remarks ?? ""] + (best.episodes_titles ?? []),
                sourceKey: sourceKey
            )
            return SourceOption(
                sourceKey: sourceKey,
                sourceName: best.source_name ?? app.sourceName(for: sourceKey),
                result: best,
                matchCount: items.count,
                quality: initialQuality,
                latencyMs: nil,
                episodeCount: best.episodeCount,
                state: .pending,
                firstEpisode: nil
            )
        }
    }

    private func bestMatch(in items: [SearchResult]) -> SearchResult? {
        guard let first = items.first else { return nil }
        let target = normalized(title)
        if let exact = items.first(where: { normalized($0.title) == target }) {
            return exact
        }
        if let contains = items.first(where: {
            let value = normalized($0.title)
            return !target.isEmpty && (value.contains(target) || target.contains(value))
        }) {
            return contains
        }
        return first
    }

    private func normalized(_ text: String) -> String {
        text.lowercased()
            .components(separatedBy: CharacterSet.alphanumerics.inverted)
            .joined()
    }

    // MARK: 测速 / 清晰度

    @MainActor
    private func startProbes() {
        let targets = options
        guard !targets.isEmpty else { return }

        probeTask?.cancel()
        probeTask = Task {
            await withTaskGroup(of: Void.self) { group in
                var iterator = targets.makeIterator()
                let maxConcurrent = 6

                for _ in 0..<min(maxConcurrent, targets.count) {
                    guard let option = iterator.next() else { break }
                    group.addTask { await self.probe(option) }
                }

                while (await group.next()) != nil {
                    if let option = iterator.next() {
                        group.addTask { await self.probe(option) }
                    }
                }
            }

            guard !Task.isCancelled else { return }
            await probeM3U8Qualities()
        }
    }

    @MainActor
    private func probe(_ option: SourceOption) async {
        guard
            let index = options.firstIndex(where: { $0.id == option.id }),
            options[index].state == .pending
        else {
            return
        }

        options[index].state = .probing
        let started = Date()

        do {
            guard let app else { return }
            let detail = try await app.detail(
                sourceKey: option.sourceKey,
                videoID: option.result.id,
                title: option.result.title
            )
            guard !Task.isCancelled else { return }

            let latency = Int(Date().timeIntervalSince(started) * 1000)
            guard let current = options.firstIndex(where: { $0.id == option.id }) else { return }
            options[current].latencyMs = latency
            options[current].episodeCount = detail.episodeCount
            options[current].quality = qualityFromDetail(detail, sourceKey: option.sourceKey)
            options[current].firstEpisode = detail.episodes?.first
            options[current].state = .ready
        } catch {
            guard !Task.isCancelled else { return }
            let latency = Int(Date().timeIntervalSince(started) * 1000)
            guard let current = options.firstIndex(where: { $0.id == option.id }) else { return }
            options[current].latencyMs = latency
            options[current].state = .failed
            options[current].errorText = error.localizedDescription
        }
    }

    @MainActor
    private func probeM3U8Qualities() async {
        let targets = options
            .filter { $0.state == .ready && $0.quality == nil }
            .prefix(8)
            .map { $0 }

        guard !targets.isEmpty else { return }

        await withTaskGroup(of: (String, String?).self) { group in
            var iterator = targets.makeIterator()
            let maxConcurrent = 3

            for _ in 0..<min(maxConcurrent, targets.count) {
                guard let option = iterator.next() else { break }
                group.addTask {
                    let quality = await self.qualityFromPlaylist(option)
                    return (option.id, quality)
                }
            }

            while let (id, quality) = await group.next() {
                if let quality, let index = options.firstIndex(where: { $0.id == id }) {
                    options[index].quality = quality
                }
                if let option = iterator.next() {
                    group.addTask {
                        let value = await self.qualityFromPlaylist(option)
                        return (option.id, value)
                    }
                }
            }
        }
    }

    private func qualityFromPlaylist(_ option: SourceOption) async -> String? {
        guard !Task.isCancelled else { return nil }
        guard let episode = option.firstEpisode,
              episode.contains(".m3u8") || episode.contains(".m3u") else {
            return nil
        }

        var raw: URL
        if episode.hasPrefix("/"), let base = APIClient.shared.baseURL,
           let resolved = URL(string: base.absoluteString.trimmingCharacters(in: CharacterSet(charactersIn: "/")) + episode) {
            raw = resolved
        } else if let direct = URL(string: episode) {
            raw = direct
        } else {
            return nil
        }

        var request = URLRequest(url: raw)
        request.timeoutInterval = 5
        request.setValue("Mozilla/5.0 (iPhone; CPU iPhone OS 18_0 like Mac OS X)", forHTTPHeaderField: "User-Agent")

        guard let (data, _) = try? await URLSession.shared.data(for: request),
              let text = String(data: data, encoding: .utf8) else {
            return nil
        }

        let pattern = #"RESOLUTION=(\d+)x(\d+)"#
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return nil }
        let ns = text as NSString
        let matches = regex.matches(in: text, range: NSRange(location: 0, length: ns.length))
        var heights: [Int] = []
        for match in matches where match.numberOfRanges >= 3 {
            if let height = Int(ns.substring(with: match.range(at: 2))) {
                heights.append(height)
            }
        }
        guard let maxHeight = heights.max() else { return nil }
        if maxHeight >= 2000 { return "4K" }
        if maxHeight >= 1000 { return "1080P" }
        if maxHeight >= 700 { return "720P" }
        if maxHeight >= 460 { return "480P" }
        return "\(maxHeight)P"
    }

    private func qualityFromDetail(_ detail: VideoDetail, sourceKey: String) -> String? {
        var labels: [String] = []
        if let remarks = detail.vod_remarks { labels.append(remarks) }
        if let titles = detail.episodes_titles { labels.append(contentsOf: titles) }
        return qualityFromLabels(labels, sourceKey: sourceKey)
    }

    private func qualityFromLabels(_ labels: [String], sourceKey: String) -> String? {
        let text = labels.joined(separator: " ").uppercased()
        if text.contains("2160") || text.contains("4K") { return "4K" }
        if text.contains("1080") { return "1080P" }
        if text.contains("720") { return "720P" }
        if text.contains("480") { return "480P" }
        if text.contains("360") { return "360P" }
        if text.contains("蓝光") || text.contains("BLURAY") { return "蓝光" }
        if text.contains("高清") || text.contains("HD") { return "HD" }

        let key = sourceKey.lowercased()
        if key.contains("aqdlt") { return "480P" }
        if key.contains("hohoj") { return "720P" }
        return nil
    }

    private func recommendationScore(_ option: SourceOption) -> Int {
        let qualityRank: Int
        switch (option.quality ?? "").uppercased() {
        case let value where value.contains("4K") || value.contains("2160"): qualityRank = 4
        case let value where value.contains("1080") || value.contains("蓝光"): qualityRank = 3
        case let value where value.contains("720") || value.contains("HD"): qualityRank = 2
        case let value where value.contains("480"): qualityRank = 1
        default: qualityRank = 0
        }
        let latencyPenalty = min(option.latencyMs ?? 5000, 5000)
        return qualityRank * 100_000 - latencyPenalty
    }
}

// MARK: - 片源选择界面

struct SourcePickerView: View {
    let title: String
    var currentSourceKey: String?
    var showsHeader = true
    let onSelect: (SourceOption) -> Void

    @EnvironmentObject private var app: AppState
    @StateObject private var model: SourcePickerModel

    init(
        title: String,
        currentSourceKey: String? = nil,
        showsHeader: Bool = true,
        onSelect: @escaping (SourceOption) -> Void
    ) {
        self.title = title
        self.currentSourceKey = currentSourceKey
        self.showsHeader = showsHeader
        self.onSelect = onSelect
        _model = StateObject(wrappedValue: SourcePickerModel(title: title))
    }

    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 14) {
                if model.isLoading && model.options.isEmpty {
                    loadingView
                } else if let errorMessage = model.errorMessage, model.options.isEmpty {
                    ErrorStateView(message: errorMessage) {
                        Task { await model.search() }
                    }
                    .padding(.top, 50)
                } else if model.options.isEmpty {
                    EmptyStateView(
                        symbol: "magnifyingglass",
                        title: "没有找到「\(title)」的片源",
                        subtitle: "可以换个关键词，或到频道里按分类找"
                    )
                    .padding(.top, 50)
                } else {
                    if showsHeader {
                        header
                    }

                    if let option = model.recommendedOption {
                        Button {
                            onSelect(option)
                        } label: {
                            HStack(spacing: 8) {
                                Image(systemName: "play.fill")
                                    .font(.system(size: 12, weight: .bold))
                                Text("播放推荐 · \(option.sourceName)")
                                    .font(.system(size: 14, weight: .semibold))
                                    .lineLimit(1)
                                Spacer(minLength: 0)
                                if let quality = option.quality {
                                    Text(quality)
                                        .font(.system(size: 10, weight: .semibold))
                                        .foregroundColor(.white.opacity(0.82))
                                }
                            }
                            .foregroundColor(.white)
                            .padding(.horizontal, 16)
                            .frame(height: 46)
                            .background(Theme.accent)
                            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                        }
                        .buttonStyle(.plain)
                    }

                    ForEach(model.options) { option in
                        Button {
                            onSelect(option)
                        } label: {
                            SourceOptionCard(
                                option: option,
                                recommended: option.id == model.recommendedOption?.id,
                                isCurrent: option.sourceKey == currentSourceKey
                            )
                        }
                        .buttonStyle(.plain)
                    }

                    footer
                }
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 28)
        }
        .background(Theme.background.ignoresSafeArea())
        .refreshable {
            await model.search()
        }
        .task {
            model.configure(app: app)
        }
        .onDisappear {
            model.cancel()
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(title)
                .font(.system(size: 21, weight: .bold))
                .foregroundColor(.white)
                .lineLimit(2)

            HStack(spacing: 6) {
                Text("找到 \(model.options.count) 个片源")
                Text("·")
                Text("按源分组，点击选择线路")
            }
            .font(.system(size: 11.5))
            .foregroundColor(Theme.textTertiary)
        }
        .padding(.top, 4)
        .padding(.bottom, 2)
    }

    private var footer: some View {
        Text("延时为详情接口实测，越短越适合当前网络；清晰度取自片源标注或播放列表，未标注会显示「清晰度未标」。")
            .font(.system(size: 10.5))
            .foregroundColor(Theme.textTertiary.opacity(0.85))
            .padding(.top, 6)
            .padding(.horizontal, 2)
    }

    private var loadingView: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 9) {
                ProgressView().tint(Theme.textSecondary)
                Text("正在搜索所有片源…")
                    .font(.system(size: 13))
                    .foregroundColor(Theme.textTertiary)
            }
            .padding(.top, 8)

            ForEach(0..<5, id: \.self) { _ in
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(Theme.surface)
                    .frame(height: 92)
                    .overlay(
                        HStack {
                            Circle().fill(Theme.surfaceHigh).frame(width: 42, height: 42)
                            VStack(alignment: .leading, spacing: 7) {
                                RoundedRectangle(cornerRadius: 4).fill(Theme.surfaceHigh).frame(width: 110, height: 12)
                                RoundedRectangle(cornerRadius: 4).fill(Theme.surfaceHigh).frame(width: 180, height: 9)
                                RoundedRectangle(cornerRadius: 4).fill(Theme.surfaceHigh).frame(width: 150, height: 9)
                            }
                            .padding(.leading, 4)
                            Spacer()
                        }
                        .padding(14)
                    )
            }
        }
    }
}

// MARK: - 换源 Sheet

struct SourcePickerSheet: View {
    let title: String
    var currentSourceKey: String?
    let onSelect: (SourceOption) -> Void

    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            SourcePickerView(
                title: title,
                currentSourceKey: currentSourceKey
            ) { option in
                dismiss()
                onSelect(option)
            }
            .navigationTitle("换源")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("关闭") { dismiss() }
                }
            }
        }
        .presentationDetents([.medium, .large])
    }
}

// MARK: - 页面入口

struct TitleSearchView: View {
    let title: String

    @State private var selected: SourceOption?

    var body: some View {
        SourcePickerView(title: title) { option in
            selected = option
        }
        .navigationTitle("选择片源")
        .navigationBarTitleDisplayMode(.inline)
        .navigationDestination(
            isPresented: Binding(
                get: { selected != nil },
                set: { if !$0 { selected = nil } }
            )
        ) {
            if let selected {
                DetailView(
                    sourceKey: selected.sourceKey,
                    videoID: selected.result.id,
                    previewTitle: selected.result.title,
                    previewPoster: selected.result.poster
                )
            }
        }
    }
}

// MARK: - 卡片

struct SourceOptionCard: View {
    let option: SourceOption
    let recommended: Bool
    var isCurrent: Bool = false

    private var symbol: String { AppState.channelSymbol(for: option.sourceKey) }
    private var accent: Color { AppState.channelColor(for: option.sourceKey) }

    var body: some View {
        HStack(spacing: 12) {
            ZStack {
                RoundedRectangle(cornerRadius: 11, style: .continuous)
                    .fill(accent.opacity(0.16))
                    .frame(width: 44, height: 44)
                Image(systemName: symbol)
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundColor(accent)
            }

            VStack(alignment: .leading, spacing: 5) {
                HStack(spacing: 6) {
                    Text(option.sourceName)
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundColor(.white.opacity(0.94))
                        .lineLimit(1)

                    if isCurrent {
                        Text("当前")
                            .font(.system(size: 9, weight: .bold))
                            .foregroundColor(Color(red: 0.55, green: 0.75, blue: 1.0))
                            .padding(.horizontal, 5)
                            .padding(.vertical, 2)
                            .background(Color(red: 0.55, green: 0.75, blue: 1.0).opacity(0.16))
                            .clipShape(Capsule())
                    }

                    if recommended {
                        Text("推荐")
                            .font(.system(size: 9, weight: .bold))
                            .foregroundColor(.white)
                            .padding(.horizontal, 5)
                            .padding(.vertical, 2)
                            .background(Theme.accent)
                            .clipShape(Capsule())
                    }

                    if option.matchCount > 1 {
                        Text("\(option.matchCount) 个版本")
                            .font(.system(size: 9, weight: .medium))
                            .foregroundColor(Theme.textTertiary)
                    }
                }

                Text(option.result.title)
                    .font(.system(size: 11.5))
                    .foregroundColor(Theme.textSecondary)
                    .lineLimit(1)

                HStack(spacing: 5) {
                    badge(option.quality ?? "清晰度未标", color: qualityColor, icon: "sparkles")
                    badge(latencyText, color: latencyColor, icon: "wifi")
                    badge("\(option.episodeCount) 集", color: Theme.textTertiary, icon: "rectangle.stack")
                }
            }

            Spacer(minLength: 0)

            trailing
        }
        .padding(14)
        .background(Theme.surface)
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .stroke(
                    isCurrent
                        ? Color(red: 0.55, green: 0.75, blue: 1.0).opacity(0.55)
                        : (recommended ? Theme.accent.opacity(0.45) : Theme.stroke),
                    lineWidth: 0.7
                )
        )
    }

    @ViewBuilder
    private var trailing: some View {
        switch option.state {
        case .probing:
            ProgressView()
                .progressViewStyle(.circular)
                .tint(Theme.textTertiary)
                .scaleEffect(0.7)
        case .failed:
            Image(systemName: "exclamationmark.circle")
                .font(.system(size: 15, weight: .medium))
                .foregroundColor(Theme.accent.opacity(0.85))
        default:
            Image(systemName: "chevron.right")
                .font(.system(size: 11, weight: .semibold))
                .foregroundColor(Theme.textTertiary)
        }
    }

    private var latencyText: String {
        switch option.state {
        case .pending:
            return "待测速"
        case .probing:
            return "测速中"
        case .failed:
            return "不可用"
        case .ready:
            guard let ms = option.latencyMs else { return "—" }
            if ms < 1000 { return "\(ms)ms" }
            return String(format: "%.1fs", Double(ms) / 1000)
        }
    }

    private var latencyColor: Color {
        switch option.state {
        case .failed:
            return Theme.accent
        case .pending, .probing:
            return Theme.textTertiary
        case .ready:
            let ms = option.latencyMs ?? 9999
            if ms < 500 { return Color(red: 0.30, green: 0.80, blue: 0.55) }
            if ms < 1500 { return Color(red: 0.95, green: 0.76, blue: 0.28) }
            return Color(red: 0.98, green: 0.55, blue: 0.25)
        }
    }

    private var qualityColor: Color {
        let value = (option.quality ?? "").uppercased()
        if value.contains("4K") || value.contains("2160") {
            return Color(red: 0.72, green: 0.55, blue: 1.0)
        }
        if value.contains("1080") || value.contains("蓝光") {
            return Color(red: 0.35, green: 0.65, blue: 1.0)
        }
        if value.contains("720") || value.contains("HD") {
            return Color(red: 0.30, green: 0.80, blue: 0.55)
        }
        if value.contains("480") || value.contains("360") {
            return Color(red: 0.95, green: 0.66, blue: 0.25)
        }
        return Theme.textTertiary
    }

    private func badge(_ text: String, color: Color, icon: String) -> some View {
        HStack(spacing: 3) {
            Image(systemName: icon)
                .font(.system(size: 8, weight: .semibold))
            Text(text)
                .font(.system(size: 9.5, weight: .medium))
        }
        .foregroundColor(color)
        .padding(.horizontal, 6)
        .padding(.vertical, 3)
        .background(color.opacity(0.12))
        .clipShape(Capsule())
    }
}

// MARK: - 数据模型

enum SourceProbeState: Equatable {
    case pending
    case probing
    case ready
    case failed
}

struct SourceOption: Identifiable {
    let sourceKey: String
    let sourceName: String
    let result: SearchResult
    let matchCount: Int
    var quality: String?
    var latencyMs: Int?
    var episodeCount: Int
    var state: SourceProbeState
    var errorText: String?
    var firstEpisode: String?

    var id: String { sourceKey }
}
