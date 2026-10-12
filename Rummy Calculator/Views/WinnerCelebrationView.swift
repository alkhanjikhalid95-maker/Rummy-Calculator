import SwiftUI

// MARK: - Winner Celebration

/// Full-screen finish overlay. It opens on the Joker reveal — the camera
/// dives into the card's binocular lens and the winner's name appears in the
/// glass — and its Continue moves on to a first-place medal over falling
/// confetti, with the winner's name, total and elapsed time.
///
/// Every moving part is switched off under Reduce Motion, which leaves the
/// same composition drawn statically rather than a different screen.
struct WinnerCelebrationView: View {
    let winnerName: String
    let winnerScore: Int?
    let elapsed: String
    let onDismiss: () -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var revealed = false
    /// True while the Joker reveal is on screen.
    @State private var showingReveal: Bool
    private let startsWithReveal: Bool

    private var animated: Bool { !reduceMotion }

    init(
        winnerName: String,
        winnerScore: Int?,
        elapsed: String,
        startsWithReveal: Bool = true,
        onDismiss: @escaping () -> Void
    ) {
        self.winnerName = winnerName
        self.winnerScore = winnerScore
        self.elapsed = elapsed
        self.startsWithReveal = startsWithReveal
        self.onDismiss = onDismiss
        _showingReveal = State(initialValue: startsWithReveal)
    }

    var body: some View {
        ZStack {
            if showingReveal {
                JokerWinnerReveal(winnerName: winnerName) {
                    withAnimation(.easeInOut(duration: 0.5)) { showingReveal = false }
                }
                .transition(.scale(scale: 1.06).combined(with: .opacity))
            } else {
                celebration
                    .transition(.scale(scale: 0.96).combined(with: .opacity))
            }
        }
    }

    /// The medal page, shown once the reveal is done.
    private var celebration: some View {
        ZStack {
            // Tapping anywhere off the card dismisses.
            AuraGradient(animated: animated)
                .ignoresSafeArea()
                .contentShape(Rectangle())
                .onTapGesture(perform: onDismiss)

            if animated {
                ConfettiLayer()
                    .ignoresSafeArea()
                    .allowsHitTesting(false)
            }

            // The entrance only nudges scale and offset — never opacity. A
            // celebration that depends on `onAppear` landing to become visible
            // shows an empty screen when it does not.
            VStack(spacing: 30) {
                FirstPlaceMedal(animated: animated)
                    .frame(width: 220, height: 220)
                    .scaleEffect(revealed ? 1 : 0.82)

                winnerCard
                    .offset(y: revealed ? 0 : 18)
            }
            .padding(.horizontal, 28)

            // Close button, pinned to the safe area rather than a fixed offset.
            VStack {
                HStack {
                    Spacer()
                    IconPill(systemName: "xmark", label: "إغلاق", onAura: true, action: onDismiss)
                }
                Spacer()
            }
            .padding(.horizontal, 20)
            .padding(.top, 12)
        }
        // The reveal already buzzed for the win; only a medal page that
        // opens straight away needs its own.
        .sensoryFeedback(trigger: revealed) { _, isRevealed in
            isRevealed && !startsWithReveal ? .success : nil
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel(Text("المركز الأول"))
        .accessibilityValue(Text(winnerName))
        .onAppear {
            guard animated else {
                revealed = true
                return
            }
            withAnimation(.spring(response: 0.55, dampingFraction: 0.62)) {
                revealed = true
            }
        }
    }

    // MARK: Winner card

    private var winnerCard: some View {
        VStack(spacing: 10) {
            Text("المركز الأول")
                .font(.system(size: 14))
                .foregroundStyle(Color.inkSecondary)

            Text(winnerName)
                .font(.system(size: 36, weight: .regular))
                .foregroundStyle(Color.ink)
                .lineLimit(2)
                .minimumScaleFactor(0.5)
                .multilineTextAlignment(.center)

            HStack(spacing: 10) {
                if let winnerScore {
                    InkChip(text: winnerScore.formatted(), systemImage: "sum")
                }
                InkChip(text: elapsed, systemImage: "clock")
            }
            .padding(.top, 4)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 26)
        .padding(.horizontal, 20)
        .card(radius: 36)
    }
}

// MARK: - First Place Medal

/// A black disc stamped with a "1", circled by a slowly turning dial ring
/// and a breathing glass halo.
private struct FirstPlaceMedal: View {
    let animated: Bool

    @State private var sweep: Double = 0
    @State private var halo: CGFloat = 0.94

    var body: some View {
        ZStack {
            // Breathing glass halo
            Circle()
                .fill(Color.white.opacity(0.12))
                .frame(width: 210, height: 210)
                .glass(in: Circle())
                .scaleEffect(halo)

            // Dial ticks
            Circle()
                .stroke(Color.white.opacity(0.55), style: StrokeStyle(lineWidth: 8, dash: [1, 6]))
                .frame(width: 176, height: 176)

            // Turning arc with a knob, like a dial's pointer
            Circle()
                .trim(from: 0, to: 0.3)
                .stroke(Color.white, style: StrokeStyle(lineWidth: 2, lineCap: .round))
                .frame(width: 176, height: 176)
                .overlay(alignment: .trailing) {
                    Circle()
                        .fill(Color.white)
                        .frame(width: 12, height: 12)
                        .overlay(Circle().fill(Color.ink).frame(width: 5, height: 5))
                        .offset(x: 6)
                }
                .rotationEffect(.degrees(sweep))

            Circle()
                .fill(Color.ink)
                .frame(width: 136, height: 136)
                .shadow(color: .black.opacity(0.3), radius: 18, y: 10)

            VStack(spacing: -4) {
                Text("1")
                    .font(.system(size: 76, weight: .ultraLight))
                Image(systemName: "crown")
                    .font(.system(size: 14, weight: .light))
            }
            .foregroundStyle(.white)
            .offset(y: 2)
        }
        .onAppear {
            guard animated else { return }
            withAnimation(.linear(duration: 7).repeatForever(autoreverses: false)) {
                sweep = 360
            }
            withAnimation(.easeInOut(duration: 1.8).repeatForever(autoreverses: true)) {
                halo = 1.04
            }
        }
    }
}

// MARK: - Confetti

/// Falling confetti drawn in a single `Canvas`, driven off the timeline clock
/// so there is one animation regardless of how many pieces are on screen.
private struct ConfettiLayer: View {
    private struct Piece {
        let column: CGFloat      // 0…1 across the width
        let sway: CGFloat        // horizontal drift, in points
        let width: CGFloat
        let height: CGFloat
        let color: Color
        let spins: Double        // turns per fall
        let fallDuration: Double
        let delay: Double
        let rounded: Bool
    }

    private static let palette: [Color] = [
        .white,
        .white,
        Color(red: 0.890, green: 0.808, blue: 0.859),
        Color(red: 0.580, green: 0.663, blue: 0.525),
        Color(red: 0.929, green: 0.471, blue: 0.231),
        Color(red: 0.067, green: 0.067, blue: 0.075),
    ]

    /// Seeded so the pattern is identical every time the screen is shown —
    /// a celebration that reshuffles on each redraw looks like a glitch.
    private static let pieces: [Piece] = {
        var seed: UInt64 = 0x9E3779B97F4A7C15
        func next() -> Double {
            seed ^= seed << 13
            seed ^= seed >> 7
            seed ^= seed << 17
            return Double(seed % 10_000) / 10_000
        }
        return (0..<56).map { _ in
            Piece(
                column: CGFloat(next()),
                sway: CGFloat(14 + next() * 40),
                width: CGFloat(5 + next() * 5),
                height: CGFloat(9 + next() * 8),
                color: palette[Int(next() * Double(palette.count)) % palette.count],
                spins: 1.2 + next() * 2.4,
                fallDuration: 3.4 + next() * 3.2,
                delay: next() * 3.0,
                rounded: next() > 0.55
            )
        }
    }()

    var body: some View {
        TimelineView(.animation) { timeline in
            Canvas { context, size in
                let now = timeline.date.timeIntervalSinceReferenceDate

                for piece in Self.pieces {
                    let elapsed = now - piece.delay
                    guard elapsed > 0 else { continue }

                    // 0…1 through one fall, looping forever.
                    let progress = (elapsed / piece.fallDuration)
                        .truncatingRemainder(dividingBy: 1)

                    let y = -40 + CGFloat(progress) * (size.height + 80)
                    let x = piece.column * size.width
                        + sin(progress * .pi * 2.4) * piece.sway

                    // Fade the last fifth so pieces do not pop out of existence.
                    let opacity = progress > 0.8 ? (1 - progress) / 0.2 : 1

                    context.drawLayer { layer in
                        layer.translateBy(x: x, y: y)
                        layer.rotate(by: .degrees(progress * piece.spins * 360))
                        layer.opacity = opacity

                        let rect = CGRect(
                            x: -piece.width / 2,
                            y: -piece.height / 2,
                            width: piece.width,
                            height: piece.height
                        )
                        let path = piece.rounded
                            ? Path(ellipseIn: rect)
                            : Path(roundedRect: rect, cornerRadius: 1.5)
                        layer.fill(path, with: .color(piece.color))
                    }
                }
            }
        }
    }
}

// MARK: - Previews

#Preview("Celebration") {
    WinnerCelebrationView(
        winnerName: "Khalid",
        winnerScore: -240,
        elapsed: "42:17",
        onDismiss: {}
    )
}

#Preview("Tie") {
    WinnerCelebrationView(
        winnerName: "Khalid • Hamad",
        winnerScore: 180,
        elapsed: "1:05:32",
        onDismiss: {}
    )
}
