import SwiftUI

// MARK: - Table

/// Which surface a table sits on: the gradient aura, or a white card.
enum TableStyle {
    case aura, paper
}

/// A stadium-shaped table outline with the four seats on its edge: P1 top,
/// P2 right, P3 bottom, P4 left — where the players actually sit.
///
/// `seat` is positioned by its own centre, so a bubble lands exactly on the
/// edge; labels hang off it with `seatTag(edge:_:)` without moving it.
struct PokerTable<Seat: View, Center: View>: View {
    var seatCount = 4
    var style: TableStyle = .aura
    /// Width ÷ height; below 1 is a tall table, above 1 a wide one.
    var aspectRatio: CGFloat = TableLayout.aspectRatio
    @ViewBuilder let seat: (Int) -> Seat
    @ViewBuilder let center: () -> Center

    var body: some View {
        GeometryReader { geo in
            let size = geo.size
            ZStack {
                TableTrack(style: style)
                center()
                    .frame(width: size.width * 0.62, height: size.height * 0.62)
                ForEach(0..<seatCount, id: \.self) { index in
                    seat(index)
                        .position(TableLayout.seatPoint(index, in: size))
                }
            }
        }
        .aspectRatio(aspectRatio, contentMode: .fit)
    }
}

extension PokerTable where Center == EmptyView {
    init(
        seatCount: Int = 4,
        style: TableStyle = .aura,
        aspectRatio: CGFloat = TableLayout.aspectRatio,
        @ViewBuilder seat: @escaping (Int) -> Seat
    ) {
        self.seatCount = seatCount
        self.style = style
        self.aspectRatio = aspectRatio
        self.seat = seat
        self.center = { EmptyView() }
    }
}

/// Geometry shared by every table, independent of what sits in the seats.
enum TableLayout {
    /// A long stadium standing upright.
    static let aspectRatio: CGFloat = 0.62

    /// Centre of each side of the table.
    static func seatPoint(_ index: Int, in size: CGSize) -> CGPoint {
        switch index {
        case 0: return CGPoint(x: size.width / 2, y: 0)
        case 1: return CGPoint(x: size.width, y: size.height / 2)
        case 2: return CGPoint(x: size.width / 2, y: size.height)
        default: return CGPoint(x: 0, y: size.height / 2)
        }
    }

    /// Which way a seat's name tag hangs so it stays over the table.
    static func tagEdge(for index: Int) -> VerticalEdge {
        index == 2 ? .top : .bottom
    }
}

/// The table drawn as fine lines: an outline, a ring of ticks like a dial, and
/// a faint inner track.
private struct TableTrack: View {
    let style: TableStyle

    var body: some View {
        let line = style == .aura ? Color.white : Color.ink
        ZStack {
            Capsule()
                .fill(style == .aura ? Color.white.opacity(0.12) : Color.canvas)

            Capsule()
                .strokeBorder(line.opacity(style == .aura ? 0.6 : 0.1), lineWidth: 1)

            Capsule()
                .inset(by: 14)
                .stroke(line.opacity(style == .aura ? 0.45 : 0.16), style: StrokeStyle(lineWidth: 7, dash: [1, 7]))

            Capsule()
                .inset(by: 30)
                .stroke(line.opacity(style == .aura ? 0.22 : 0.06), lineWidth: 1)
        }
    }
}

// MARK: - Seat bubble

/// A player's seat: a disc with their initial. Glass on the aura, white on a
/// card, black when it is the active seat.
///
/// Bump `popTrigger` to play the "bubble up" — an overshooting scale with a
/// ripple — and set `isRaised` to keep it lifted while that seat is active.
struct SeatBubble: View {
    let name: String
    let seat: Int
    var size: CGFloat = 58
    var style: TableStyle = .aura
    var isRaised = false
    var popTrigger = 0
    var badge: Badge?

    enum Badge {
        case crown, you, linked
    }

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private struct PopState {
        var scale: CGFloat = 1
        var ripple: CGFloat = 0
    }

    private var monogram: String {
        let trimmed = name.trimmingCharacters(in: .whitespaces)
        guard let first = trimmed.first else { return "" }
        return String(first).uppercased()
    }

    private var foreground: Color {
        if isRaised { return .white }
        return style == .aura ? .white : .ink
    }

    var body: some View {
        let rippleColor = style == .aura ? Color.white : Color.ink
        ZStack {
            disc
                .overlay {
                    if monogram.isEmpty {
                        Image(systemName: "plus")
                            .font(.system(size: size * 0.32, weight: .light))
                            .foregroundStyle(foreground.opacity(0.8))
                    } else {
                        Text(monogram)
                            .font(.system(size: size * 0.4, weight: .regular))
                            .foregroundStyle(foreground)
                            .contentTransition(.interpolate)
                    }
                }

            if let badge {
                badgeView(badge)
                    .offset(x: size * 0.38, y: -size * 0.36)
                    .transition(.scale.combined(with: .opacity))
            }
        }
        .frame(width: size, height: size)
        .scaleEffect(isRaised ? 1.12 : 1)
        // A constant trigger under Reduce Motion means the pop never plays.
        .keyframeAnimator(initialValue: PopState(), trigger: reduceMotion ? 0 : popTrigger) { content, state in
            content
                .scaleEffect(state.scale)
                .overlay {
                    // Ripple ring: invisible at rest, so it does not matter
                    // whether the animator settles on its first or last value.
                    Circle()
                        .stroke(rippleColor, lineWidth: 1.5)
                        .scaleEffect(1 + state.ripple * 0.9)
                        .opacity(state.ripple > 0 ? Double(1 - state.ripple) * 0.8 : 0)
                }
        } keyframes: { _ in
            KeyframeTrack(\.scale) {
                SpringKeyframe(1.24, duration: 0.16, spring: .snappy)
                SpringKeyframe(0.95, duration: 0.14, spring: .snappy)
                SpringKeyframe(1, duration: 0.3, spring: .bouncy)
            }
            KeyframeTrack(\.ripple) {
                LinearKeyframe(0.01, duration: 0.01)
                CubicKeyframe(1, duration: 0.55)
            }
        }
        .animation(.spring(response: 0.35, dampingFraction: 0.65), value: isRaised)
    }

    @ViewBuilder
    private var disc: some View {
        if isRaised {
            Circle()
                .fill(Color.ink)
                .frame(width: size, height: size)
                .shadow(color: .black.opacity(0.25), radius: 12, y: 6)
        } else if style == .aura {
            Circle()
                .fill(Color.white.opacity(0.14))
                .frame(width: size, height: size)
                .glass(in: Circle())
        } else {
            Circle()
                .fill(Color.white)
                .frame(width: size, height: size)
                .shadow(color: .black.opacity(0.09), radius: 10, y: 4)
        }
    }

    @ViewBuilder
    private func badgeView(_ badge: Badge) -> some View {
        switch badge {
        case .crown:
            Image(systemName: "crown.fill")
                .font(.system(size: size * 0.17, weight: .semibold))
                .foregroundStyle(.white)
                .frame(width: size * 0.36, height: size * 0.36)
                .background(Color.ink, in: Circle())
                .overlay(Circle().stroke(Color.white, lineWidth: 1.5))
        case .you:
            Text("أنت")
                .font(.system(size: size * 0.17, weight: .semibold))
                .foregroundStyle(.white)
                .padding(.horizontal, 6)
                .padding(.vertical, 2)
                .background(Color.ember, in: Capsule())
                .overlay(Capsule().stroke(Color.white, lineWidth: 1.5))
        case .linked:
            Image(systemName: "dot.radiowaves.left.and.right")
                .font(.system(size: size * 0.15, weight: .bold))
                .foregroundStyle(.white)
                .frame(width: size * 0.34, height: size * 0.34)
                .background(Color.sageDeep, in: Circle())
                .overlay(Circle().stroke(Color.white, lineWidth: 1.5))
        }
    }
}

// MARK: - Seat tag

/// Name (and optional value) hanging under or over a seat bubble.
struct SeatTag: View {
    let name: String
    var placeholder: String = "اسم اللاعب"
    var detail: String?
    var style: TableStyle = .aura
    var isHighlighted = false
    var detailColor: Color?

    var body: some View {
        let text = style == .aura ? Color.white : Color.ink
        VStack(spacing: 3) {
            Text(name.isEmpty ? placeholder : name)
                .font(.system(size: 14, weight: isHighlighted ? .semibold : .regular))
                .foregroundStyle(name.isEmpty ? text.opacity(0.8) : text)
                .lineLimit(1)
                .frame(maxWidth: 100)

            if let detail {
                Text(detail)
                    .font(.system(size: 15, weight: .medium).monospacedDigit())
                    .foregroundStyle(detailColor ?? text.opacity(0.75))
                    .lineLimit(1)
                    .contentTransition(.numericText())
            }
        }
        .fixedSize()
    }
}

extension View {
    /// Hangs `tag` above or below this view without changing its layout size,
    /// so a seat bubble stays centred on the table's edge.
    func seatTag<Tag: View>(edge: VerticalEdge, spacing: CGFloat = 8, @ViewBuilder _ tag: () -> Tag) -> some View {
        overlay(alignment: edge == .bottom ? .bottom : .top) {
            tag()
                .alignmentGuide(edge == .bottom ? .bottom : .top) { d in
                    edge == .bottom ? d[.top] - spacing : d[.bottom] + spacing
                }
        }
    }
}

// MARK: - Cards

/// A small face-up playing card.
struct MiniCard: View {
    let rank: String
    let suit: String
    let isRed: Bool
    var width: CGFloat = 40

    var body: some View {
        let ink = isRed ? Color(red: 0.86, green: 0.27, blue: 0.24) : Color.ink
        RoundedRectangle(cornerRadius: width * 0.16, style: .continuous)
            .fill(Color.white)
            .frame(width: width, height: width * 1.4)
            .overlay(alignment: .topLeading) {
                VStack(spacing: -2) {
                    Text(rank).font(.system(size: width * 0.28, weight: .semibold))
                    Text(suit).font(.system(size: width * 0.22))
                }
                .foregroundStyle(ink)
                .padding(width * 0.09)
            }
            .overlay {
                Text(suit)
                    .font(.system(size: width * 0.5))
                    .foregroundStyle(ink)
                    .offset(y: width * 0.12)
            }
            .overlay(
                RoundedRectangle(cornerRadius: width * 0.16, style: .continuous)
                    .stroke(Color.black.opacity(0.06), lineWidth: 0.5)
            )
            .shadow(color: .black.opacity(0.12), radius: 6, y: 3)
    }
}

/// Three cards fanned out and gently floating — the app's illustration.
struct FloatingCards: View {
    var width: CGFloat = 54
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private static let cards: [(rank: String, suit: String, isRed: Bool)] = [
        ("A", "♠", false), ("K", "♥", true), ("Q", "♦", true),
    ]

    var body: some View {
        TimelineView(.animation(minimumInterval: 1 / 30, paused: reduceMotion)) { timeline in
            let t = reduceMotion ? 0 : timeline.date.timeIntervalSinceReferenceDate
            ZStack {
                ForEach(Array(Self.cards.enumerated()), id: \.offset) { index, card in
                    let phase = t * 0.9 + Double(index) * 1.4
                    MiniCard(rank: card.rank, suit: card.suit, isRed: card.isRed, width: width)
                        .rotationEffect(.degrees(Double(index - 1) * 16 + sin(phase) * 3), anchor: .bottom)
                        .offset(x: CGFloat(index - 1) * width * 0.36, y: CGFloat(sin(phase)) * 4)
                }
            }
        }
        .accessibilityHidden(true)
    }
}
