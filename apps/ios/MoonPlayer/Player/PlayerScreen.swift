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

            PlayerLayerView(player: model.player)
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
            model.configure(app: app)
        }
        .onDisappear {
            model.stop()
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
            }
        }
        .sheet(isPresented: $showEpisodes) {
            episodeSheet
        }
        .confirmationDialog("播放速度", isPresented: $showSpeed, titleVisibility: .visible) {
            ForEach([0.5, 0.75, 1.0, 1.25, 1.5, 2.0], id: \.self) { rate in
                Button(rateLabel(rate)) {
                    model.setRate(Float(rate))
                }
            }
            Button("取消", role: .cancel) {}
        }
    }

    // MARK: - 手势

    private var gestureLayer: some View {
        GeometryReader { proxy in
            Color.clear
                .contentShape(Rectangle())
                .simultaneousGesture(
                    SpatialTapGesture(count: 2)
                        .onEnded { value in
                            handleDoubleTap(at: value.location, size: proxy.size)
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
        }
        .ignoresSafeArea()
    }

    private func handleSingleTap() {
        pendingSingleTap?.cancel()
        let work = DispatchWorkItem {
            model.toggleControls()
        }
        pendingSingleTap = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.26, execute: work)
    }

    private func handleDoubleTap(at location: CGPoint, size: CGSize) {
        pendingSingleTap?.cancel()
        if location.x < size.width * 0.36 {
            model.seek(by: -10)
            flash("快退 10 秒")
        } else if location.x > size.width * 0.64 {
            model.seek(by: 10)
            flash("快进 10 秒")
        } else {
            model.playPause()
        }
    }

    private func handleDrag(_ value: DragGesture.Value, size: CGSize) {
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
        if dragMode == .seek {
            model.seek(to: dragStartTime + dragSeekDelta)
        }
        dragMode = .none
        dragSeekDelta = 0
    }

    private func flash(_ text: String) {
        flashText = text
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.75) {
            if flashText == text { flashText = nil }
        }
    }

    // MARK: - 控制层

    private var controlsOverlay: some View {
        VStack(spacing: 0) {
            topBar
            Spacer(minLength: 0)
            bottomBar
        }
        .background(
            LinearGradient(
                colors: [.black.opacity(0.62), .clear, .clear, .black.opacity(0.78)],
                startPoint: .top,
                endPoint: .bottom
            )
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
                Text(model.context.episodeTitle(at: model.currentIndex))
                    .font(.system(size: 11))
                    .foregroundColor(.white.opacity(0.65))
                    .lineLimit(1)
            }

            Spacer(minLength: 0)

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

                Slider(
                    value: Binding(
                        get: {
                            let value = scrubbing ? scrubValue : model.currentTime
                            return min(max(value, 0), maxDuration)
                        },
                        set: { scrubValue = $0 }
                    ),
                    in: 0...maxDuration,
                    onEditingChanged: { editing in
                        if editing {
                            scrubbing = true
                            scrubValue = model.currentTime
                            model.showControls()
                        } else {
                            model.seek(to: scrubValue)
                            scrubbing = false
                        }
                    }
                )
                .tint(Theme.accent)

                Text(formatTime(model.duration))
                    .font(.system(size: 11, weight: .medium).monospacedDigit())
                    .foregroundColor(.white.opacity(0.6))
                    .frame(width: 52, alignment: .trailing)
            }

            HStack(spacing: 26) {
                Button {
                    model.previous()
                } label: {
                    Image(systemName: "backward.end.fill")
                        .font(.system(size: 21))
                        .foregroundColor(model.currentIndex > 0 ? .white : .white.opacity(0.3))
                }
                .disabled(model.currentIndex == 0)

                Button {
                    model.playPause()
                } label: {
                    Image(systemName: model.isPlaying ? "pause.fill" : "play.fill")
                        .font(.system(size: 30))
                        .foregroundColor(.white)
                        .frame(width: 46, height: 46)
                }

                Button {
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
                    Text(rateLabel(Double(model.playbackRate)))
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
        .padding(.horizontal, 20)
        .padding(.bottom, 18)
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

                if !model.context.proxyMode {
                    Button("走服务端代理") {
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

    // MARK: - 工具

    private var maxDuration: Double {
        max(model.duration, 1)
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
