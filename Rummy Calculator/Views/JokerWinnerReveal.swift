import AVFoundation
import SwiftUI
import UIKit

/// The Joker announces the winner: he lowers his binoculars, throws them off
/// the card and raises a blank sign — a clip made with Kling from the card art
/// (see `Tools/JokerReveal`). The winner's name is live text set onto the sign
/// once it is still, so any name works.
///
/// Plays on the app's aura so it hands over to the celebration without a
/// change of light. Under Reduce Motion, or if the clip cannot play, it opens
/// on the finished frame with the name already up.
struct JokerWinnerReveal: View {
    let winnerName: String
    /// Where playback begins — 0 in the app. At or past `nameTime` it opens
    /// on the finished frame.
    let startTime: TimeInterval
    /// False holds the opening frame, for previews and tests.
    let playing: Bool
    let onContinue: () -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.scenePhase) private var scenePhase
    @State private var clip = RevealClip()
    @State private var nameShown = false
    /// The clip is over: its last frame is held as a still.
    @State private var finished = false
    /// Continue is showing.
    @State private var controlsShown = false
    @State private var burst = 0
    @State private var announced = false

    /// The binoculars leave his hands.
    static let throwTime: TimeInterval = 0.95
    /// The sign has stopped moving; the name goes up.
    static let nameTime: TimeInterval = 3.25

    /// The sign's cream panel inside its red border, as fractions of the clip
    /// frame. Measured on the clip's last frame; the sign holds this position
    /// from `nameTime` to the end.
    static let signPanel = CGRect(x: 0.2870, y: 0.0732, width: 0.4611, height: 0.1249)

    /// Width ÷ height of the clip — the card's own proportions.
    static let aspectRatio: CGFloat = 1080 / 1570

    private var displayName: String {
        let trimmed = winnerName.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? "الفائز" : trimmed
    }

    private var announcement: String {
        "\(displayName)، الفائز باللعبة. لعب رائع."
    }

    /// Whether to skip straight to the finished frame.
    private var opensFinished: Bool {
        reduceMotion || startTime >= Self.nameTime
    }

    init(winnerName: String, startTime: TimeInterval = 0, playing: Bool = true, onContinue: @escaping () -> Void) {
        self.winnerName = winnerName
        self.startTime = startTime
        self.playing = playing
        self.onContinue = onContinue
    }

    /// The card's frame on the full screen, safe areas included.
    static func cardFrame(in size: CGSize) -> CGRect {
        let width = min(size.width * 0.86, size.height * 0.6 * aspectRatio)
        let height = width / aspectRatio
        return CGRect(x: (size.width - width) / 2, y: size.height * 0.47 - height / 2, width: width, height: height)
    }

    var body: some View {
        GeometryReader { geometry in
            let card = Self.cardFrame(in: geometry.size)

            ZStack {
                AuraGradient(animated: !reduceMotion)

                cardView(size: card.size)
                    .position(x: card.midX, y: card.midY)

                VStack(spacing: 0) {
                    Text("انتهت اللعبة")
                        .font(.system(size: 17, weight: .medium))
                        .foregroundStyle(.white)
                        .padding(.top, geometry.safeAreaInsets.top + 12)
                    Spacer()
                    Button("متابعة", action: onContinue)
                        .buttonStyle(InkButtonStyle())
                        .frame(maxWidth: 420)
                        .padding(.horizontal, 32)
                        .padding(.bottom, geometry.safeAreaInsets.bottom + 12)
                        .opacity(controlsShown ? 1 : 0)
                        .offset(y: controlsShown ? 0 : 16)
                        .allowsHitTesting(controlsShown)
                        .accessibilityHidden(!controlsShown)
                }

                // The winner, for VoiceOver — the sign itself is part of the picture.
                Color.clear
                    .accessibilityElement()
                    .accessibilityLabel(Text(announcement))
                    .accessibilityAddTraits(.isHeader)
                    .accessibilityHidden(!nameShown)
            }
        }
        // The card centres on the whole screen, the same on every iPhone;
        // only the caption and button keep clear of the notch and home bar.
        .ignoresSafeArea()
        .statusBarHidden()
        .sensoryFeedback(.success, trigger: nameShown) { _, shown in shown && !opensFinished }
        .onAppear(perform: begin)
        .onDisappear { clip.stop() }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active { clip.resume() } else { clip.pause() }
        }
        .onChange(of: reduceMotion) { _, reduced in
            if reduced { finish(animated: false) }
        }
    }

    // MARK: - Card

    private func cardView(size: CGSize) -> some View {
        let shape = RoundedRectangle(cornerRadius: size.width * 0.05, style: .continuous)
        return ZStack {
            // Underneath the clip: its first frame while it loads, its last
            // once it has played — never an empty card.
            Image(finished ? "JokerRevealEnd" : "JokerRevealStart")
                .resizable()
                .scaledToFill()

            if clip.isPlaying || clip.hasStarted, !finished {
                RevealPlayerView(player: clip.player)
            }

            signText(size: size)
            SignConfetti(trigger: burst, panel: panelFrame(in: size))
        }
        .frame(width: size.width, height: size.height)
        .clipShape(shape)
        .background(shape.fill(.white).shadow(color: .black.opacity(0.22), radius: 24, y: 14))
        .accessibilityHidden(true)
    }

    private func panelFrame(in size: CGSize) -> CGRect {
        CGRect(
            x: Self.signPanel.minX * size.width,
            y: Self.signPanel.minY * size.height,
            width: Self.signPanel.width * size.width,
            height: Self.signPanel.height * size.height
        )
    }

    /// "الفائز" and the name, set on the sign's panel.
    private func signText(size: CGSize) -> some View {
        let panel = panelFrame(in: size)
        return VStack(spacing: panel.height * 0.02) {
            Text("الفائز")
                .font(.system(size: panel.height * 0.2, weight: .semibold))
                .foregroundStyle(Color(red: 0.78, green: 0.13, blue: 0.15))
            Text(displayName)
                .font(.system(size: panel.height * 0.5, weight: .heavy, design: .serif))
                .foregroundStyle(Color.ink)
                .lineLimit(1)
                .minimumScaleFactor(0.3)
        }
        .padding(.horizontal, panel.width * 0.07)
        .frame(width: panel.width, height: panel.height)
        .scaleEffect(nameShown ? 1 : 0.55)
        .opacity(nameShown ? 1 : 0)
        .position(x: panel.midX, y: panel.midY)
    }

    // MARK: - Playback

    private func begin() {
        guard !opensFinished else {
            finish(animated: false)
            return
        }
        guard playing else { return }
        clip.onThrow = {
            UIImpactFeedbackGenerator(style: .medium).impactOccurred()
        }
        clip.onName = { showName() }
        clip.onEnd = { finish(animated: true) }
        // A clip that cannot play must never hold up the winner.
        clip.onFailure = { finish(animated: false) }
        clip.play(from: startTime, throwTime: Self.throwTime, nameTime: Self.nameTime)
    }

    private func showName() {
        guard !nameShown else { return }
        if reduceMotion {
            nameShown = true
        } else {
            withAnimation(.spring(response: 0.42, dampingFraction: 0.58)) { nameShown = true }
            burst += 1
        }
        announce()
    }

    private func finish(animated: Bool) {
        if !nameShown {
            nameShown = true
            announce()
        }
        // Swap the playing clip for its identical last frame with no
        // animation — a cross-fade would ghost the first frame through it.
        finished = true
        clip.stop()
        if animated {
            withAnimation(.easeOut(duration: 0.35)) { controlsShown = true }
        } else {
            controlsShown = true
        }
    }

    private func announce() {
        guard !announced else { return }
        announced = true
        UIAccessibility.post(notification: .announcement, argument: announcement)
    }
}

// MARK: - Clip

/// The bundled Joker clip and its cue points.
@Observable
final class RevealClip {
    /// Made when playback starts — SwiftUI may build the view, and with it
    /// this object, more often than it shows it.
    private(set) var player: AVPlayer?
    private(set) var isPlaying = false
    private(set) var hasStarted = false

    @ObservationIgnored var onThrow: () -> Void = {}
    @ObservationIgnored var onName: () -> Void = {}
    @ObservationIgnored var onEnd: () -> Void = {}
    @ObservationIgnored var onFailure: () -> Void = {}

    @ObservationIgnored private var boundaryObserver: Any?
    @ObservationIgnored private var endObserver: NSObjectProtocol?
    @ObservationIgnored private var failObserver: NSObjectProtocol?
    @ObservationIgnored private var watchdog: Task<Void, Never>?
    @ObservationIgnored private var ended = false

    func play(from start: TimeInterval, throwTime: TimeInterval, nameTime: TimeInterval) {
        guard let url = Bundle.main.url(forResource: "JokerReveal", withExtension: "mp4") else {
            onFailure()
            return
        }
        let item = AVPlayerItem(url: url)
        let player = AVPlayer(playerItem: item)
        player.isMuted = true
        player.actionAtItemEnd = .pause
        player.preventsDisplaySleepDuringVideoPlayback = false
        self.player = player
        stopObserving()
        ended = false

        let cues = [throwTime, nameTime]
            .filter { $0 > start }
            .map { NSValue(time: CMTime(seconds: $0, preferredTimescale: 600)) }
        if !cues.isEmpty {
            boundaryObserver = player.addBoundaryTimeObserver(forTimes: cues, queue: .main) { [weak self] in
                MainActor.assumeIsolated {
                    guard let self else { return }
                    let now = player.currentTime().seconds
                    if now >= nameTime - 0.05 { self.onName() } else { self.onThrow() }
                }
            }
        }
        if start >= throwTime { onThrow() }
        endObserver = NotificationCenter.default.addObserver(forName: AVPlayerItem.didPlayToEndTimeNotification, object: item, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.reachEnd() }
        }
        failObserver = NotificationCenter.default.addObserver(forName: AVPlayerItem.failedToPlayToEndTimeNotification, object: item, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.fail() }
        }

        player.seek(to: CMTime(seconds: start, preferredTimescale: 600), toleranceBefore: .zero, toleranceAfter: .zero)
        player.play()
        isPlaying = true
        hasStarted = true

        // If the clip stalls — decoding trouble, a missing frame — finish anyway.
        let deadline = nameTime - start + 2.5
        watchdog = Task { [weak self] in
            try? await Task.sleep(for: .seconds(deadline))
            guard let self, !Task.isCancelled, !self.ended else { return }
            if item.status == .failed || player.currentTime().seconds < nameTime {
                self.fail()
            }
        }
    }

    func pause() {
        guard isPlaying else { return }
        player?.pause()
    }

    func resume() {
        guard isPlaying, !ended else { return }
        player?.play()
    }

    func stop() {
        player?.pause()
        isPlaying = false
        stopObserving()
    }

    private func reachEnd() {
        guard !ended else { return }
        ended = true
        // A clip shorter than expected still puts the name up.
        onName()
        onEnd()
        stop()
    }

    private func fail() {
        guard !ended else { return }
        ended = true
        stop()
        onFailure()
    }

    private func stopObserving() {
        if let boundaryObserver { player?.removeTimeObserver(boundaryObserver) }
        boundaryObserver = nil
        if let endObserver { NotificationCenter.default.removeObserver(endObserver) }
        endObserver = nil
        if let failObserver { NotificationCenter.default.removeObserver(failObserver) }
        failObserver = nil
        watchdog?.cancel()
        watchdog = nil
    }
}

/// An `AVPlayerLayer` filling its frame, with no controls.
private struct RevealPlayerView: UIViewRepresentable {
    let player: AVPlayer?

    func makeUIView(context: Context) -> PlayerLayerView {
        let view = PlayerLayerView()
        view.playerLayer.videoGravity = .resizeAspectFill
        view.playerLayer.player = player
        view.isUserInteractionEnabled = false
        return view
    }

    func updateUIView(_ view: PlayerLayerView, context: Context) {
        view.playerLayer.player = player
    }

    final class PlayerLayerView: UIView {
        override static var layerClass: AnyClass { AVPlayerLayer.self }
        var playerLayer: AVPlayerLayer { layer as! AVPlayerLayer }
    }
}

// MARK: - Confetti

/// A small burst off the sign as the name lands, in the card's own red,
/// yellow, black and white. Invisible at rest, so it does not matter which
/// keyframe the animator settles on.
private struct SignConfetti: View {
    let trigger: Int
    let panel: CGRect

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private nonisolated struct Piece {
        let angle: Double
        let speed: Double
        let spin: Double
        let size: Double
        let colour: Color
    }

    private nonisolated static let pieces: [Piece] = {
        var seed: UInt64 = 0x2545F4914F6CDD1D
        func next() -> Double {
            seed ^= seed << 13; seed ^= seed >> 7; seed ^= seed << 17
            return Double(seed % 10_000) / 10_000
        }
        let colours: [Color] = [
            Color(red: 0.84, green: 0.13, blue: 0.13),
            Color(red: 0.98, green: 0.86, blue: 0.08),
            .white,
            .ink,
        ]
        return (0..<30).map { _ in
            Piece(
                angle: -.pi * (0.05 + 0.9 * next()),
                speed: 140 + 200 * next(),
                spin: (next() - 0.5) * 1000,
                size: 4 + 4 * next(),
                colour: colours[Int(next() * 4) % 4]
            )
        }
    }()

    var body: some View {
        Color.clear
            .keyframeAnimator(initialValue: 0.0, trigger: reduceMotion ? 0 : trigger) { content, age in
                content.overlay {
                    Canvas { context, _ in
                        guard age > 0, age < 1 else { return }
                        let seconds = age * 1.1
                        for piece in Self.pieces {
                            let x = panel.midX + cos(piece.angle) * piece.speed * seconds
                            let y = panel.midY + sin(piece.angle) * piece.speed * seconds + 0.5 * 520 * seconds * seconds
                            var bit = context
                            bit.opacity = 1 - max(0, (age - 0.65) / 0.35)
                            bit.translateBy(x: x, y: y)
                            bit.rotate(by: .degrees(piece.spin * seconds))
                            let rect = CGRect(x: -piece.size / 2, y: -piece.size * 0.8, width: piece.size, height: piece.size * 1.6)
                            bit.fill(Path(roundedRect: rect, cornerRadius: 1), with: .color(piece.colour))
                        }
                    }
                }
            } keyframes: { _ in
                LinearKeyframe(0.001, duration: 0.001)
                LinearKeyframe(1, duration: 1.1)
            }
            .allowsHitTesting(false)
    }
}

#Preview("Reveal") {
    JokerWinnerReveal(winnerName: "Khalid") {}
}

#Preview("Finished") {
    JokerWinnerReveal(winnerName: "خالد", startTime: JokerWinnerReveal.nameTime) {}
}
