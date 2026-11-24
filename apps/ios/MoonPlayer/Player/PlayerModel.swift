import AVFoundation
import Foundation

final class PlayerModel: ObservableObject {
    let player = AVPlayer()
    @Published private(set) var context: PlaybackContext

    @Published var currentIndex: Int
    @Published var isPlaying = false
    @Published var controlsVisible = true
    @Published var currentTime: Double = 0
    @Published var duration: Double = 0
    @Published var bufferedTime: Double = 0
    @Published var isBuffering = true
    @Published var errorMessage: String?
    @Published var playbackRate: Float = 1.0
    @Published var preferProxy = false
    @Published var useLocalCache = false
    @Published var boostLocked = false
    @Published private(set) var videoAspect: Double = 0

    private weak var app: AppState?
    private var timeObserver: Any?
    private var endObserver: NSObjectProtocol?
    private var statusObservation: NSKeyValueObservation?
    private var timeControlObservation: NSKeyValueObservation?
    private var presentationObservation: NSKeyValueObservation?
    private var hideWorkItem: DispatchWorkItem?
    private var lastSaved: Double = -100
    private var didStop = false
    private var didFallback = false
    private var preloadedEpisodeIndex: Int?
    private var temporaryBoost = false
    private var boostRate: Float = 2.0

    init(context: PlaybackContext) {
        self.context = context
        self.currentIndex = min(max(0, context.startIndex), max(0, context.episodes.count - 1))
        player.automaticallyWaitsToMinimizeStalling = true
        player.actionAtItemEnd = .pause
    }

    // MARK: - 生命周期

    func configure(app: AppState) {
        guard self.app == nil else { return }
        self.app = app
        preferProxy = app.forceProxy
        useLocalCache = app.localCacheEnabled
        didFallback = false
        LocalHLSServer.shared.startIfNeeded()
        installObservers()
        load(index: currentIndex, startTime: context.startTime, autoplay: true)
    }

    /// 播放页内换源：保留集数索引和当前进度。
    func switchTo(context newContext: PlaybackContext, startTime: Double) {
        guard !newContext.episodes.isEmpty else { return }
        save(force: true)

        context = newContext
        currentIndex = min(max(0, newContext.startIndex), newContext.episodes.count - 1)
        didFallback = false
        preloadedEpisodeIndex = nil
        if let app {
            useLocalCache = app.localCacheEnabled
            preferProxy = app.forceProxy
        }
        load(index: currentIndex, startTime: startTime, autoplay: true)
    }

    func stop() {
        guard !didStop else { return }
        didStop = true
        player.pause()
        save(force: true)
        hideWorkItem?.cancel()

        if let timeObserver {
            player.removeTimeObserver(timeObserver)
            self.timeObserver = nil
        }
        if let endObserver {
            NotificationCenter.default.removeObserver(endObserver)
            self.endObserver = nil
        }
        statusObservation?.invalidate()
        statusObservation = nil
        timeControlObservation?.invalidate()
        timeControlObservation = nil
        presentationObservation?.invalidate()
        presentationObservation = nil
        player.replaceCurrentItem(with: nil)
    }

    private func installObservers() {
        let interval = CMTime(seconds: 0.5, preferredTimescale: 600)
        timeObserver = player.addPeriodicTimeObserver(forInterval: interval, queue: .main) { [weak self] time in
            self?.tick(time)
        }

        endObserver = NotificationCenter.default.addObserver(
            forName: AVPlayerItem.didPlayToEndTimeNotification,
            object: nil,
            queue: .main
        ) { [weak self] notification in
            guard let self else { return }
            guard let item = notification.object as? AVPlayerItem, item === self.player.currentItem else { return }
            self.handleEnd()
        }

        timeControlObservation = player.observe(\.timeControlStatus, options: [.initial, .new]) { [weak self] player, _ in
            let status = player.timeControlStatus
            DispatchQueue.main.async {
                self?.applyTimeControl(status)
            }
        }
    }

    // MARK: - 播放

    func load(index: Int, startTime: Double, autoplay: Bool) {
        guard index >= 0, index < context.episodes.count else { return }
        guard let app else { return }

        if index != currentIndex {
            didFallback = false
            preloadedEpisodeIndex = nil
        }

        currentIndex = index
        errorMessage = nil
        isBuffering = true
        duration = 0
        bufferedTime = 0
        videoAspect = 0
        temporaryBoost = false
        currentTime = max(0, startTime)
        lastSaved = -100

        let url = app.playURL(
            episode: context.episodes[index],
            sourceKey: context.sourceKey,
            proxyMode: context.proxyMode,
            forceProxy: preferProxy
        )
        guard let url else {
            isBuffering = false
            errorMessage = "无法生成播放地址"
            return
        }

        var playbackURL = url
        if useLocalCache {
            if let local = LocalHLSServer.shared.makePlaylistURL(for: url) {
                playbackURL = local
            } else {
                useLocalCache = false
            }
        }

        let item = AVPlayerItem(url: playbackURL)
        // 预缓冲 20 秒，给服务端/本地缓存留出提前拉片的时间
        item.preferredForwardBufferDuration = 20

        statusObservation?.invalidate()
        statusObservation = item.observe(\.status, options: [.initial, .new]) { [weak self] item, _ in
            DispatchQueue.main.async {
                self?.handleStatus(item)
            }
        }

        presentationObservation?.invalidate()
        presentationObservation = nil

        player.replaceCurrentItem(with: item)
        presentationObservation = item.observe(\.presentationSize, options: [.initial, .new]) { [weak self] item, _ in
            let size = item.presentationSize
            guard size.width > 0, size.height > 0 else { return }
            DispatchQueue.main.async {
                guard let self, self.player.currentItem === item else { return }
                self.videoAspect = Double(size.width / size.height)
            }
        }
        if startTime > 1 {
            player.seek(
                to: CMTime(seconds: startTime, preferredTimescale: 600),
                toleranceBefore: .zero,
                toleranceAfter: .zero
            )
        }
        if autoplay {
            player.playImmediately(atRate: effectiveRate)
        }
    }

    func playPause() {
        if isPlaying {
            player.pause()
            controlsVisible = true
            hideWorkItem?.cancel()
        } else {
            player.playImmediately(atRate: effectiveRate)
            scheduleHide()
        }
    }

    /// 长按画面临时加速，松开恢复用户选择的倍速。
    func beginTemporaryBoost() {
        guard isPlaying, !temporaryBoost, !boostLocked else { return }
        temporaryBoost = true
        boostRate = 2.0
        player.rate = boostRate
    }

    func endTemporaryBoost() {
        guard temporaryBoost else { return }
        temporaryBoost = false
        if isPlaying, !boostLocked {
            player.rate = max(0.5, playbackRate)
        }
    }

    /// 长按后上滑锁定 2x，松手也保持。
    func lockBoost() {
        guard temporaryBoost else { return }
        temporaryBoost = false
        boostLocked = true
        boostRate = 2.0
        player.rate = boostRate
    }

    func unlockBoost() {
        guard boostLocked else { return }
        boostLocked = false
        if isPlaying {
            player.rate = max(0.5, playbackRate)
        }
    }

    private var effectiveRate: Float {
        if boostLocked || temporaryBoost {
            return max(2.0, boostRate)
        }
        return max(0.5, playbackRate)
    }

    func seek(to seconds: Double) {
        guard seconds.isFinite else { return }
        let upper = duration > 0 ? duration : max(seconds, 0)
        let target = min(max(0, seconds), upper)
        player.seek(
            to: CMTime(seconds: target, preferredTimescale: 600),
            toleranceBefore: .zero,
            toleranceAfter: .zero
        )
        currentTime = target
        scheduleHide()
    }

    func seek(by delta: Double) {
        seek(to: currentTime + delta)
    }

    func setRate(_ rate: Float) {
        boostLocked = false
        playbackRate = rate
        if isPlaying, !temporaryBoost {
            player.rate = rate
        }
    }

    func next() {
        guard currentIndex + 1 < context.episodes.count else { return }
        didFallback = false
        load(index: currentIndex + 1, startTime: 0, autoplay: true)
    }

    func previous() {
        guard currentIndex > 0 else { return }
        didFallback = false
        load(index: currentIndex - 1, startTime: 0, autoplay: true)
    }

    func retry() {
        if let app {
            preferProxy = app.forceProxy
            useLocalCache = app.localCacheEnabled
        }
        didFallback = false
        errorMessage = nil
        load(index: currentIndex, startTime: currentTime, autoplay: true)
    }

    func retryWithProxy() {
        preferProxy = true
        didFallback = true
        errorMessage = nil
        load(index: currentIndex, startTime: currentTime, autoplay: true)
    }

    func retryWithDirect() {
        preferProxy = false
        didFallback = true
        errorMessage = nil
        load(index: currentIndex, startTime: currentTime, autoplay: true)
    }

    func toggleControls() {
        controlsVisible.toggle()
        if controlsVisible {
            scheduleHide()
        } else {
            hideWorkItem?.cancel()
        }
    }

    func showControls() {
        controlsVisible = true
        scheduleHide()
    }

    // MARK: - 保存进度

    func save(force: Bool) {
        guard let app else { return }
        if !force && currentTime < 1 { return }
        let time = currentTime
        let total = duration
        let index = currentIndex
        lastSaved = time
        Task {
            await app.saveProgress(
                context: context,
                episodeIndex: index,
                playTime: time,
                duration: total
            )
        }
    }

    // MARK: - 内部

    private func tick(_ time: CMTime) {
        let seconds = time.seconds
        if seconds.isFinite {
            currentTime = max(0, seconds)
        }
        if let item = player.currentItem {
            let total = item.duration.seconds
            if total.isFinite, total > 0 {
                duration = total
            }

            var bufferedEnd = 0.0
            for value in item.loadedTimeRanges {
                let range = value.timeRangeValue
                let end = range.start.seconds + range.duration.seconds
                if end.isFinite {
                    bufferedEnd = max(bufferedEnd, end)
                }
            }
            bufferedTime = max(0, bufferedEnd)
        }
        if currentTime - lastSaved >= 5 {
            save(force: false)
        }
        if currentTime >= 5 {
            preloadNextEpisodeIfNeeded()
        }
    }

    /// 当前集播到 5 秒后，后台把下一集的播放列表和前几片预取到本地。
    private func preloadNextEpisodeIfNeeded() {
        guard useLocalCache, let app else { return }
        let next = currentIndex + 1
        guard next < context.episodes.count, preloadedEpisodeIndex != next else { return }
        preloadedEpisodeIndex = next

        guard let url = app.playURL(
            episode: context.episodes[next],
            sourceKey: context.sourceKey,
            proxyMode: context.proxyMode,
            forceProxy: preferProxy
        ) else {
            return
        }
        LocalHLSServer.shared.preload(for: url)
    }

    private func handleStatus(_ item: AVPlayerItem) {
        guard item === player.currentItem else { return }
        switch item.status {
        case .readyToPlay:
            isBuffering = false
            let total = item.duration.seconds
            if total.isFinite, total > 0 {
                duration = total
            }
            if isPlaying {
                player.rate = effectiveRate
            }
        case .failed:
            if useLocalCache {
                // 本地代理失败（服务端未更新、上游拒连等）：先退回普通播放
                useLocalCache = false
                let resume = currentTime
                load(index: currentIndex, startTime: resume, autoplay: true)
                return
            }
            if !didFallback {
                // 代理缓存和直连各试一次（例如服务端未更新、跨域/防盗链、缓存不可用）
                didFallback = true
                preferProxy.toggle()
                let resume = currentTime
                load(index: currentIndex, startTime: resume, autoplay: true)
            } else {
                isBuffering = false
                errorMessage = friendlyError(item.error)
            }
        default:
            break
        }
    }

    private func friendlyError(_ error: Error?) -> String {
        if let error = error as NSError? {
            if error.domain == NSURLErrorDomain {
                switch error.code {
                case NSURLErrorNotConnectedToInternet:
                    return "网络未连接，请检查网络后重试"
                case NSURLErrorTimedOut:
                    return "连接片源超时，换一集或换一个源试试"
                case NSURLErrorCannotConnectToHost, NSURLErrorCannotFindHost, NSURLErrorNetworkConnectionLost:
                    return "片源服务器连接失败，换一集或换一个源试试"
                default:
                    break
                }
            }
            if error.domain == AVFoundationErrorDomain {
                return "片源无法解码或地址已过期，换一集或换一个源试试"
            }
        }
        return "无法播放该视频，换一集或换一个源试试"
    }

    private func applyTimeControl(_ status: AVPlayer.TimeControlStatus) {
        switch status {
        case .playing:
            isPlaying = true
            isBuffering = false
            scheduleHide()
        case .waitingToPlayAtSpecifiedRate:
            isBuffering = true
        case .paused:
            isPlaying = false
            hideWorkItem?.cancel()
        @unknown default:
            break
        }
    }

    private func handleEnd() {
        if currentIndex + 1 < context.episodes.count {
            load(index: currentIndex + 1, startTime: 0, autoplay: true)
        } else {
            isPlaying = false
            controlsVisible = true
        }
    }

    private func scheduleHide() {
        hideWorkItem?.cancel()
        guard isPlaying else { return }
        let item = DispatchWorkItem { [weak self] in
            guard let self, self.isPlaying else { return }
            self.controlsVisible = false
        }
        hideWorkItem = item
        DispatchQueue.main.asyncAfter(deadline: .now() + 4, execute: item)
    }
}
