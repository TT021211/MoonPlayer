import AVFoundation
import SwiftUI
import UIKit

struct PlayerScreen: View {
    @EnvironmentObject private var app: AppState
    @Environment(\.dismiss) private var dismiss
    @Environment(\.scenePhase) private var scenePhase

    @StateObject private var model: PlayerModel

    @State private var showEpisodes = false
    @State private var showSpeed = false
    @State private var showSourcePicker = false
    @State private var switchError: String?

    @State private var dragMode: DragMode = .none
    @State private var dragStartTime: Double = 0
    @State private var dragSeekDelta: Double = 0
    @State private var dragSide: VerticalSide = .volume
    @State private var dragStartBrightness: Double = 1
    @State private var dragStartVolume: Double = 1
    @State private var dragLevel: Double = 0.5

    @State private var isLandscape = true
    @State private var flashText: String?
    @State private var pendingSingleTap: DispatchWorkItem?

    @State private var scrubbing = false
    @State private var scrubValue: Double = 0
    @AppStorage("player.fillMode") private var fillMode = 0
    @State private var isBoosting = false
    @State private var boostInteractionActive = false
    @State private var pressActive = false
    @State private var longPressWorkItem: DispatchWorkItem?
    @State private var lockedDuringPress = false
    @State private var suppressTapUntil = Date.distantPast

    private enum DragMode {
        case none
        case seek
        case vertical
    }

    private enum VerticalSide {
        case brightness
        case volume
    }

    init(context: PlaybackContext) {
        _model = StateObject(wrappedValue: PlayerModel(context: context))
    }

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            PlayerLayerView(player: model.player, fill: effectiveFill)
                .ignoresSafeArea()

            gestureLayer

            if model.isBuffering && model.errorMessage == nil {
                ProgressView()
                    .progressViewStyle(.circular)
                    .tint(.white)
                    .scaleEffect(1.4)
            }

            if model.controlsVisible || dragMode != .none {
                controlsOverlay
                    .transition(.opacity)
            }

            if let flashText {
                Text(flashText)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundColor(.white)
                    .padding(.horizontal, 18)
                    .padding(.vertical, 11)
                    .background(Color.black.opacity(0.55))
                    .clipShape(Capsule())
            }

            if isBoosting {
                VStack {
                    HStack(spacing: 6) {
                        Image(systemName: "forward.fill")
                            .font(.system(size: 11, weight: .bold))
                        Text("2x 倍速中 · 上滑锁定")
                            .font(.system(size: 12, weight: .semibold))
                    }
                    .foregroundColor(.white)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 8)
                    .background(.ultraThinMaterial, in: Capsule())
                    .padding(.top, 64)
                    Spacer()
                }
                .allowsHitTesting(false)
            }

            if dragMode == .seek {
                seekHUD
            }

            if dragMode == .vertical {
                verticalHUD
            }

            if let errorMessage = model.errorMessage {
                errorOverlay(errorMessage)
            }
        }
        .statusBarHidden(true)
        .persistentSystemOverlays(.hidden)
        .animation(.easeInOut(duration: 0.18), value: model.controlsVisible)
        .onAppear {
            OrientationManager.shared.lock(.landscape)
            isLandscape = true
            UIApplication.shared.isIdleTimerDisabled = true
            try? AVAudioSession.sharedInstance().setCategory(.playback, mode: .moviePlayback)
            try? AVAudioSession.sharedInstance().setActive(true)
            model.configure(app: app)
        }
        .onDisappear {
            pressActive = false
            boostInteractionActive = false
            cancelLongPressBoost()
            endLongPressBoost()
            model.stop()
            try? AVAudioSession.sharedInstance().setActive(false, options: [.notifyOthersOnDeactivation])
            UIApplication.shared.isIdleTimerDisabled = false
            OrientationManager.shared.lock(.portrait)
            Task {
                try? await Task.sleep(nanoseconds: 500_000_000)
                await app.refreshRecords()
            }
        }
        .onChange(of: scenePhase) { phase in
            if phase != .active {
                model.save(force: true)
                LocalHLSServer.shared.flushIndex()
            }
        }
        .sheet(isPresented: $showEpisodes) {
            episodeSheet
        }
        .sheet(isPresented: $showSourcePicker) {
            SourcePickerSheet(
                title: model.context.title,
                currentSourceKey: model.context.sourceKey
            ) { option in
                Task { await switchSource(option) }
            }
        }
        .confirmationDialog("播放速度", isPresented: $showSpeed, titleVisibility: .visible) {
            ForEach([0.5, 0.75, 1.0, 1.25, 1.5, 2.0], id: \.self) { rate in
                Button(rateLabel(rate)) {
                    model.setRate(Float(rate))
                }
            }
            Button("取消", role: .cancel) {}
        } message: {
            Text("长按画面 0.5 秒临时 2x，上滑锁定；单击控制栏，双击暂停")
        }
        .alert(
            "换源失败",
            isPresented: Binding(
                get: { switchError != nil },
                set: { if !$0 { switchError = nil } }
            )
        ) {
            Button("好", role: .cancel) { switchError = nil }
        } message: {
            Text(switchError ?? "")
        }
    }

    // MARK: - 手势

    private var gestureLayer: some View {
        GeometryReader { proxy in
            Color.clear
                .contentShape(Rectangle())
                .simultaneousGesture(
                    SpatialTapGesture(count: 2)
                        .onEnded { _ in
                            handleDoubleTap()
                        }
                )
                .simultaneousGesture(
                    SpatialTapGesture(count: 1)
                        .onEnded { _ in
                            handleSingleTap()
                        }
                )
                .simultaneousGesture(
                    DragGesture(minimumDistance: 18)
                        .onChanged { value in
                            handleDrag(value, size: proxy.size)
                        }
                        .onEnded { value in
                            handleDragEnd(value, size: proxy.size)
                        }
                )
                .simultaneousGesture(
                    DragGesture(minimumDistance: 0)
                        .onChanged { value in
                            handlePress(value)
                        }
                        .onEnded { _ in
                            endPress()
                        }
                )
        }
        .ignoresSafeArea()
    }

    private func handleSingleTap() {
        if isBoosting {
            endLongPressBoost()
            return
        }
        guard Date() >= suppressTapUntil else { return }
        pendingSingleTap?.cancel()
        let work = DispatchWorkItem {
            model.toggleControls()
        }
        pendingSingleTap = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.26, execute: work)
    }

    private func handleDoubleTap() {
        if isBoosting {
            endLongPressBoost()
            return
        }
        guard Date() >= suppressTapUntil else { return }
        pendingSingleTap?.cancel()
        Haptics.light()
        model.playPause()
    }

    // MARK: - 长按 / 上滑锁定

    private func handlePress(_ value: DragGesture.Value) {
        if !pressActive {
            pressActive = true
            scheduleLongPressBoost()
        }

        let dx = abs(value.translation.width)
        let dy = value.translation.height

        if !isBoosting && (dx > 12 || abs(dy) > 12) {
            pressActive = false
            cancelLongPressBoost()
        }

        guard isBoosting else { return }

        if dy < -30, !lockedDuringPress {
            lockedDuringPress = true
            isBoosting = false
            model.lockBoost()
            suppressTapUntil = Date().addingTimeInterval(0.4)
            Haptics.medium()
            flash("已锁定 2x", duration: 1.2)
        } else if dx > 40 {
            endLongPressBoost()
        }
    }

    private func endPress() {
        pressActive = false
        cancelLongPressBoost()
        if isBoosting {
            endLongPressBoost()
        }
        if boostInteractionActive {
            suppressTapUntil = Date().addingTimeInterval(0.4)
        }
        if flashText == "已锁定 2x" {
            flashText = nil
        }
        boostInteractionActive = false
        lockedDuringPress = false
    }

    private func scheduleLongPressBoost() {
        longPressWorkItem?.cancel()
        let work = DispatchWorkItem {
            guard pressActive, !isBoosting else { return }
            if model.boostLocked {
                boostInteractionActive = true
                model.unlockBoost()
                suppressTapUntil = Date().addingTimeInterval(0.4)
                Haptics.light()
                flash("已取消 2x")
                return
            }
            guard model.isPlaying else { return }
            beginLongPressBoost()
        }
        longPressWorkItem = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5, execute: work)
    }

    private func cancelLongPressBoost() {
        longPressWorkItem?.cancel()
        longPressWorkItem = nil
    }

    private func handleDrag(_ value: DragGesture.Value, size: CGSize) {
        guard !isBoosting, !boostInteractionActive else { return }
        if dragMode == .none {
            if abs(value.translation.width) > abs(value.translation.height) {
                dragMode = .seek
                dragStartTime = model.currentTime
                dragSeekDelta = 0
                model.showControls()
            } else {
                dragMode = .vertical
                dragSide = value.startLocation.x < size.width / 2 ? .brightness : .volume
                dragStartBrightness = Double(UIScreen.main.brightness)
                dragStartVolume = Double(model.player.volume)
                dragLevel = dragSide == .brightness ? dragStartBrightness : dragStartVolume
            }
        }

        switch dragMode {
        case .seek:
            let span = max(Double(size.width), 1)
            dragSeekDelta = (Double(value.translation.width) / span) * 240
        case .vertical:
            let span = max(Double(size.height), 1)
            let base = dragSide == .brightness ? dragStartBrightness : dragStartVolume
            let next = min(1, max(0, base - Double(value.translation.height) / span))
            dragLevel = next
            if dragSide == .brightness {
                UIScreen.main.brightness = CGFloat(next)
            } else {
                model.player.volume = Float(next)
            }
        case .none:
            break
        }
    }

    private func handleDragEnd(_ value: DragGesture.Value, size: CGSize) {
        if isBoosting {
            endLongPressBoost()
            return
        }
        if dragMode == .seek {
            model.seek(to: dragStartTime + dragSeekDelta)
        }
        dragMode = .none
        dragSeekDelta = 0
    }

    private func flash(_ text: String, duration: Double = 0.75) {
        flashText = text
        DispatchQueue.main.asyncAfter(deadline: .now() + duration) {
            if flashText == text { flashText = nil }
        }
    }

    private func beginLongPressBoost() {
        guard !isBoosting, !model.boostLocked, model.isPlaying else { return }
        boostInteractionActive = true
        isBoosting = true
        model.beginTemporaryBoost()
        Haptics.medium()
    }

    private func endLongPressBoost() {
        guard isBoosting else { return }
        isBoosting = false
        suppressTapUntil = Date().addingTimeInterval(0.4)
        model.endTemporaryBoost()
    }

    // MARK: - 控制层

    private var controlsOverlay: some View {
        VStack(spacing: 0) {
            topBar
            Spacer(minLength: 0)
            bottomBar
        }
        .background(
            ZStack {
                VStack(spacing: 0) {
                    LinearGradient(
                        colors: [.black.opacity(0.55), .clear],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                    .frame(height: 130)
                    Spacer(minLength: 0)
                }

                VStack(spacing: 0) {
                    Spacer(minLength: 0)
                    LinearGradient(
                        stops: [
                            .init(color: .clear, location: 0),
                            .init(color: .black.opacity(0.28), location: 0.35),
                            .init(color: .black.opacity(0.72), location: 1)
                        ],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                    .frame(height: 200)
                }
            }
            .ignoresSafeArea()
            .allowsHitTesting(false)
        )
    }

    private var topBar: some View {
        HStack(alignment: .center, spacing: 12) {
            Button {
                dismiss()
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundColor(.white)
                    .frame(width: 40, height: 40)
                    .background(Color.black.opacity(0.35))
                    .clipShape(Circle())
            }

            VStack(alignment: .leading, spacing: 2) {
                Text(model.context.title)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundColor(.white)
                    .lineLimit(1)
                Text("\(model.context.sourceName) · \(model.context.episodeTitle(at: model.currentIndex))")
                    .font(.system(size: 11))
                    .foregroundColor(.white.opacity(0.65))
                    .lineLimit(1)
            }

            Spacer(minLength: 0)

            Button {
                let nextFill = !effectiveFill
                fillMode = nextFill ? 1 : 2
                Haptics.light()
                flash(nextFill ? "铺满画面" : "适应画面")
            } label: {
                Image(systemName: effectiveFill ? "arrow.down.right.and.arrow.up.left" : "arrow.up.left.and.arrow.down.right")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundColor(.white.opacity(0.85))
                    .frame(width: 30, height: 30)
                    .background(Color.black.opacity(0.35))
                    .clipShape(Circle())
            }
            .accessibilityLabel(effectiveFill ? "切换为适应画面" : "切换为铺满画面")

            Text(model.useLocalCache ? "本地" : (model.preferProxy ? "缓存" : "直连"))
                .font(.system(size: 10, weight: .semibold))
                .foregroundColor(
                    model.useLocalCache
                        ? Color(red: 0.30, green: 0.80, blue: 0.55)
                        : (model.preferProxy ? Theme.accent : .white.opacity(0.6))
                )
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(Color.black.opacity(0.35))
                .clipShape(Capsule())

            Text("\(model.currentIndex + 1)/\(model.context.episodes.count)")
                .font(.system(size: 11, weight: .medium))
                .foregroundColor(.white.opacity(0.7))
                .padding(.horizontal, 10)
                .padding(.vertical, 5)
                .background(Color.black.opacity(0.35))
                .clipShape(Capsule())
        }
        .padding(.horizontal, 16)
        .padding(.top, 10)
    }

    private var bottomBar: some View {
        VStack(spacing: 6) {
            HStack(spacing: 10) {
                Text(formatTime(scrubbing ? scrubValue : model.currentTime))
                    .font(.system(size: 11, weight: .medium).monospacedDigit())
                    .foregroundColor(.white.opacity(0.8))
                    .frame(width: 52, alignment: .leading)

                PlayerProgressBar(
                    currentTime: model.currentTime,
                    duration: model.duration,
                    bufferedTime: model.bufferedTime,
                    scrubbing: $scrubbing,
                    scrubValue: $scrubValue,
                    onScrubStart: {
                        model.showControls()
                    },
                    onSeek: { target in
                        model.seek(to: target)
                    }
                )

                Text(formatTime(model.duration))
                    .font(.system(size: 11, weight: .medium).monospacedDigit())
                    .foregroundColor(.white.opacity(0.6))
                    .frame(width: 52, alignment: .trailing)
            }

            HStack(spacing: 22) {
                Button {
                    Haptics.selection()
                    model.previous()
                } label: {
                    Image(systemName: "backward.end.fill")
                        .font(.system(size: 21))
                        .foregroundColor(model.currentIndex > 0 ? .white : .white.opacity(0.3))
                }
                .disabled(model.currentIndex == 0)

                Button {
                    Haptics.light()
                    model.playPause()
                } label: {
                    Image(systemName: model.isPlaying ? "pause.fill" : "play.fill")
                        .font(.system(size: 30))
                        .foregroundColor(.white)
                        .frame(width: 46, height: 46)
                }

                Button {
                    Haptics.selection()
                    model.next()
                } label: {
                    Image(systemName: "forward.end.fill")
                        .font(.system(size: 21))
                        .foregroundColor(model.currentIndex + 1 < model.context.episodes.count ? .white : .white.opacity(0.3))
                }
                .disabled(model.currentIndex + 1 >= model.context.episodes.count)

                Spacer(minLength: 0)

                Button {
                    model.showControls()
                    showEpisodes = false
                    showSourcePicker = true
                } label: {
                    Image(systemName: "arrow.triangle.2.circlepath")
                        .font(.system(size: 17))
                        .foregroundColor(.white.opacity(0.9))
                }
                .accessibilityLabel("换源")

                Button {
                    model.showControls()
                    showEpisodes = true
                } label: {
                    Image(systemName: "rectangle.stack.fill")
                        .font(.system(size: 18))
                        .foregroundColor(.white.opacity(0.9))
                }

                Button {
                    model.showControls()
                    showSpeed = true
                } label: {
                    Text((model.boostLocked || isBoosting) ? "2x" : rateLabel(Double(model.playbackRate)))
                        .font(.system(size: 12.5, weight: .semibold))
                        .foregroundColor(.white.opacity(0.9))
                        .frame(minWidth: 28)
                }

                Button {
                    toggleOrientation()
                } label: {
                    Image(systemName: isLandscape ? "rectangle.portrait" : "rectangle")
                        .font(.system(size: 17))
                        .foregroundColor(.white.opacity(0.9))
                }
            }
            .padding(.top, 2)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background(
            ZStack {
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .fill(.ultraThinMaterial)
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .fill(Color.black.opacity(0.24))
            }
        )
        .overlay(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .stroke(Color.white.opacity(0.08), lineWidth: 0.6)
        )
        .padding(.horizontal, 12)
        .padding(.bottom, 14)
    }

    private var seekHUD: some View {
        VStack(spacing: 5) {
            Text(dragSeekDelta >= 0 ? "+\(Int(dragSeekDelta)) 秒" : "\(Int(dragSeekDelta)) 秒")
                .font(.system(size: 17, weight: .bold).monospacedDigit())
                .foregroundColor(.white)
            Text(formatTime(dragStartTime + dragSeekDelta))
                .font(.system(size: 12, weight: .medium).monospacedDigit())
                .foregroundColor(.white.opacity(0.75))
        }
        .padding(.horizontal, 22)
        .padding(.vertical, 14)
        .background(Color.black.opacity(0.55))
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
    }

    private var verticalHUD: some View {
        VStack(spacing: 7) {
            Image(systemName: dragSide == .brightness ? "sun.max.fill" : "speaker.wave.2.fill")
                .font(.system(size: 20))
                .foregroundColor(.white)
            ZStack(alignment: .bottom) {
                RoundedRectangle(cornerRadius: 3)
                    .fill(Color.white.opacity(0.22))
                RoundedRectangle(cornerRadius: 3)
                    .fill(Color.white)
                    .frame(height: max(4, 64 * dragLevel))
            }
            .frame(width: 7, height: 64)
            Text("\(Int(dragLevel * 100))%")
                .font(.system(size: 11, weight: .medium).monospacedDigit())
                .foregroundColor(.white.opacity(0.8))
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 14)
        .background(Color.black.opacity(0.55))
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
    }

    private func errorOverlay(_ message: String) -> some View {
        VStack(spacing: 14) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 30))
                .foregroundColor(Theme.accent)
            Text(message)
                .font(.system(size: 13))
                .foregroundColor(.white.opacity(0.86))
                .multilineTextAlignment(.center)
                .lineLimit(4)
            HStack(spacing: 10) {
                Button("重试") {
                    model.retry()
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 8)
                .background(Theme.surfaceHigh)
                .clipShape(Capsule())

                if model.preferProxy {
                    Button("改用直连") {
                        model.retryWithDirect()
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 8)
                    .background(Theme.surfaceHigh)
                    .clipShape(Capsule())
                } else {
                    Button("边看边缓存") {
                        model.retryWithProxy()
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 8)
                    .background(Theme.accent)
                    .clipShape(Capsule())
                }
            }
            .font(.system(size: 12.5, weight: .semibold))
            .foregroundColor(.white)

            Button("关闭") { dismiss() }
                .font(.system(size: 12))
                .foregroundColor(.white.opacity(0.6))
                .padding(.top, 2)
        }
        .padding(22)
        .frame(maxWidth: 340)
        .background(.ultraThinMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
        .padding(.horizontal, 30)
    }

    private var episodeSheet: some View {
        NavigationStack {
            List {
                ForEach(Array(model.context.episodes.indices), id: \.self) { index in
                    Button {
                        Haptics.selection()
                        model.load(index: index, startTime: 0, autoplay: true)
                        showEpisodes = false
                    } label: {
                        HStack {
                            Text(model.context.episodeTitle(at: index))
                                .font(.system(size: 14))
                                .foregroundColor(.white.opacity(0.92))
                                .lineLimit(1)
                            Spacer()
                            if index == model.currentIndex {
                                Image(systemName: "checkmark")
                                    .font(.system(size: 12, weight: .bold))
                                    .foregroundColor(Theme.accent)
                            }
                        }
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .listRowBackground(Theme.surface)
                }
            }
            .listStyle(.plain)
            .scrollContentBackground(.hidden)
            .background(Theme.background.ignoresSafeArea())
            .navigationTitle("选集")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("关闭") { showEpisodes = false }
                }
            }
        }
        .presentationDetents([.medium, .large])
    }

    // MARK: - 换源

    @MainActor
    private func switchSource(_ option: SourceOption) async {
        do {
            let detail = try await app.detail(
                sourceKey: option.sourceKey,
                videoID: option.result.id,
                title: option.result.title
            )
            guard let episodes = detail.episodes, !episodes.isEmpty else {
                switchError = "该片源没有可用选集"
                return
            }

            let index = min(model.currentIndex, episodes.count - 1)
            let resume = model.currentTime
            let context = PlaybackContext(
                sourceKey: detail.source ?? option.sourceKey,
                sourceName: detail.source_name ?? option.sourceName,
                videoID: detail.id.isEmpty ? option.result.id : detail.id,
                title: detail.title,
                cover: detail.poster ?? option.result.poster ?? "",
                year: detail.year ?? "",
                episodes: episodes,
                episodeTitles: detail.episodes_titles ?? [],
                proxyMode: detail.proxyMode ?? false,
                startIndex: index,
                startTime: resume
            )
            model.switchTo(context: context, startTime: resume)
            flash("已切换到 \(option.sourceName)")
        } catch {
            switchError = error.localizedDescription
        }
    }

    // MARK: - 工具

    /// 自动铺满：画面比例与屏幕接近时裁切铺满；差距过大（如竖屏中的横屏视频）保持完整画面。
    private var effectiveFill: Bool {
        switch fillMode {
        case 1: return true
        case 2: return false
        default: break
        }

        let screen = UIScreen.main.bounds.size
        guard screen.width > 0, screen.height > 0 else { return isLandscape }
        let screenAspect = Double(max(screen.width, screen.height) / min(screen.width, screen.height))
        guard model.videoAspect > 0 else { return isLandscape }
        if isLandscape {
            return model.videoAspect >= screenAspect * 0.8
        }
        return model.videoAspect <= (1 / screenAspect) * 1.25
    }

    private func toggleOrientation() {
        isLandscape.toggle()
        OrientationManager.shared.lock(isLandscape ? .landscape : .portrait)
    }

    private func rateLabel(_ rate: Double) -> String {
        if abs(rate - 1.0) < 0.001 { return "1x" }
        if abs(rate - 0.5) < 0.001 { return "0.5x" }
        if abs(rate - 0.75) < 0.001 { return "0.75x" }
        if abs(rate - 1.25) < 0.001 { return "1.25x" }
        if abs(rate - 1.5) < 0.001 { return "1.5x" }
        if abs(rate - 2.0) < 0.001 { return "2x" }
        return String(format: "%.2gx", rate)
    }

    private func formatTime(_ seconds: Double) -> String {
        guard seconds.isFinite, seconds > 0 else { return "00:00" }
        let total = Int(seconds)
        let h = total / 3600
        let m = (total % 3600) / 60
        let s = total % 60
        if h > 0 {
            return String(format: "%d:%02d:%02d", h, m, s)
        }
        return String(format: "%02d:%02d", m, s)
    }
}

// MARK: - 缓冲进度条

struct PlayerProgressBar: View {
    let currentTime: Double
    let duration: Double
    let bufferedTime: Double
    @Binding var scrubbing: Bool
    @Binding var scrubValue: Double
    var onScrubStart: (() -> Void)?
    let onSeek: (Double) -> Void

    var body: some View {
        GeometryReader { proxy in
            let width = max(proxy.size.width, 1)
            let total = max(duration, 1)
            let playedValue = min(max(scrubbing ? scrubValue : currentTime, 0), total)
            let played = playedValue / total
            let buffered = min(max(bufferedTime, 0), total) / total
            let thumbSize: CGFloat = scrubbing ? 14 : 11

            ZStack(alignment: .leading) {
                Capsule()
                    .fill(Color.white.opacity(0.18))
                    .frame(height: 4)

                Capsule()
                    .fill(Color.white.opacity(0.38))
                    .frame(width: width * buffered, height: 4)

                Capsule()
                    .fill(Theme.accent)
                    .frame(width: width * played, height: 4)

                Circle()
                    .fill(Color.white)
                    .frame(width: thumbSize, height: thumbSize)
                    .shadow(color: .black.opacity(0.35), radius: 3, y: 1)
                    .offset(x: width * played - thumbSize / 2)
            }
            .frame(width: width, height: 28)
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { value in
                        if !scrubbing {
                            scrubbing = true
                            scrubValue = playedValue
                            onScrubStart?()
                        }
                        let x = min(max(value.location.x, 0), width)
                        scrubValue = total * x / width
                    }
                    .onEnded { value in
                        let x = min(max(value.location.x, 0), width)
                        let target = total * x / width
                        onSeek(target)
                        scrubbing = false
                    }
            )
        }
        .frame(height: 28)
    }
}
