import SwiftUI

/// One seat as the game table shows it.
struct TableSeat {
    var name: String
    var total: Int
    /// What the seat scored in the round just played — floats up from it.
    var lastRound: Int?
    /// Prediction for the current round, when predictions are on.
    var hint: String?
}

/// One of the nine rounds, for the progress dots.
struct RoundCard: Identifiable {
    enum State: Equatable {
        /// Played: who won and how, when known.
        case played(winner: Int?, label: String?)
        case current
        case upcoming
    }

    let id: Int
    let state: State
}

/// The live game as a table seen from above: four players where they sit,
/// their totals beside them, and the round in the middle.
struct GameTableView: View {
    let seats: [TableSeat]
    var leader: Int?
    var dealer: Int?
    var mySeat: Int?
    var linked: Set<Int> = []
    let rounds: [RoundCard]
    let round: Int
    let maxRounds: Int
    let isOver: Bool
    /// Before the game: names only, no totals.
    var isLobby = false
    /// Changes once per recorded round, to float the per-seat deltas.
    var roundTrigger = 0
    var popTriggers = [0, 0, 0, 0]
    var onSeatTap: ((Int) -> Void)?

    var body: some View {
        PokerTable(seatCount: seats.count, style: .paper, aspectRatio: 1.7) { index in
            seatView(index)
        } center: {
            centerpiece
        }
        .padding(.horizontal, 44)
        .padding(.top, 70)
        .padding(.bottom, 74)
    }

    // MARK: Seats

    @ViewBuilder
    private func seatView(_ index: Int) -> some View {
        let seat = seats[index]
        let isLeader = leader == index
        let bubble = SeatBubble(
            name: seat.name,
            seat: index,
            size: 52,
            style: .paper,
            popTrigger: popTriggers.indices.contains(index) ? popTriggers[index] : 0,
            badge: isLeader ? .crown : (mySeat == index ? .you : (linked.contains(index) ? .linked : nil))
        )
        .overlay(alignment: .bottomLeading) {
            if dealer == index && !isOver {
                DealerChip()
                    .offset(x: -8, y: 6)
                    .transition(.scale.combined(with: .opacity))
            }
        }
        .overlay {
            if let delta = seat.lastRound {
                RoundDelta(value: delta, trigger: roundTrigger)
            }
        }
        .seatTag(edge: index == 0 ? .top : .bottom, spacing: 6) {
            VStack(spacing: 2) {
                if index == 0, let hint = seat.hint {
                    hintChip(hint)
                }
                SeatTag(
                    name: seat.name,
                    placeholder: "مقعد فارغ",
                    detail: isLobby ? nil : seat.total.formatted(),
                    style: .paper,
                    isHighlighted: mySeat == index,
                    detailColor: isLeader ? .positive : nil
                )
                if index != 0, let hint = seat.hint {
                    hintChip(hint)
                }
            }
        }

        if let onSeatTap {
            Button { onSeatTap(index) } label: { bubble }
                .buttonStyle(PressableStyle(scale: 0.9))
                .accessibilityLabel(Text("\(seat.name)، \(seat.total)"))
                .accessibilityHint(Text(isOver ? "" : "تسجيل الفائز في هذه اللفة"))
        } else {
            bubble
                .accessibilityElement(children: .combine)
        }
    }

    private func hintChip(_ text: String) -> some View {
        Text(text)
            .font(.system(size: 11, weight: .medium))
            .foregroundStyle(.white)
            .lineLimit(1)
            .padding(.horizontal, 8)
            .padding(.vertical, 2)
            .background(Color.ember, in: Capsule())
            .transition(.scale.combined(with: .opacity))
    }

    // MARK: Centre

    private var centerpiece: some View {
        VStack(spacing: 6) {
            if isLobby {
                Image(systemName: "hourglass")
                    .font(.system(size: 22, weight: .light))
                    .foregroundStyle(Color.ink)
                    .symbolEffect(.pulse)
                Text("بانتظار البدء")
                    .font(.system(size: 13))
                    .foregroundStyle(Color.inkSecondary)
            } else if isOver {
                Image(systemName: "flag.checkered")
                    .font(.system(size: 22, weight: .light))
                    .foregroundStyle(Color.ink)
                Text("انتهت اللعبة")
                    .font(.system(size: 13))
                    .foregroundStyle(Color.inkSecondary)
            } else {
                Text("اللفة")
                    .font(.system(size: 12))
                    .foregroundStyle(Color.inkSecondary)
                Text("\(round)")
                    .font(.system(size: 40, weight: .light).monospacedDigit())
                    .foregroundStyle(Color.ink)
                    .contentTransition(.numericText(value: Double(round)))
            }
            RoundDots(rounds: rounds)
        }
        .accessibilityElement(children: .combine)
    }
}

// MARK: - Round dots

/// Nine dots: filled for rounds played, a ring for the current one.
struct RoundDots: View {
    let rounds: [RoundCard]
    var onAura = false

    var body: some View {
        HStack(spacing: 5) {
            ForEach(rounds) { card in
                let base = onAura ? Color.white : Color.ink
                switch card.state {
                case .played:
                    Circle().fill(base).frame(width: 6, height: 6)
                case .current:
                    Circle()
                        .stroke(Color.ember, lineWidth: 1.5)
                        .frame(width: 9, height: 9)
                        .transition(.scale)
                case .upcoming:
                    Circle().fill(base.opacity(0.18)).frame(width: 6, height: 6)
                }
            }
        }
        .frame(height: 10)
        .animation(.spring(response: 0.4, dampingFraction: 0.7), value: rounds.map(\.state))
        .accessibilityHidden(true)
    }
}

// MARK: - Small pieces

/// The dealer button, marking the خباص.
private struct DealerChip: View {
    var body: some View {
        Text("خ")
            .font(.system(size: 11, weight: .semibold))
            .foregroundStyle(.white)
            .frame(width: 22, height: 22)
            .background(Circle().fill(Color.negative))
            .overlay(Circle().stroke(Color.white, lineWidth: 1.5))
            .accessibilityLabel(Text("خباص"))
    }
}

/// "+200" / "-60" rising off a seat after a round is recorded. Invisible at
/// rest, so it does not matter which keyframe the animator settles on.
private struct RoundDelta: View {
    let value: Int
    let trigger: Int

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private struct Float {
        var rise: CGFloat = 0
        var opacity: Double = 0
        var scale: CGFloat = 0.6
    }

    var body: some View {
        Text(value > 0 ? "+\(value)" : "\(value)")
            .font(.system(size: 14, weight: .semibold).monospacedDigit())
            .foregroundStyle(value <= 0 ? Color.positive : Color.negative)
            .padding(.horizontal, 9)
            .padding(.vertical, 4)
            .background(Color.white, in: Capsule())
            .shadow(color: .black.opacity(0.12), radius: 8, y: 3)
            .fixedSize()
            .keyframeAnimator(initialValue: Float(), trigger: reduceMotion ? 0 : trigger) { content, state in
                content
                    .scaleEffect(state.scale)
                    .offset(y: -34 - state.rise)
                    .opacity(state.opacity)
            } keyframes: { _ in
                KeyframeTrack(\.opacity) {
                    LinearKeyframe(1, duration: 0.15)
                    LinearKeyframe(1, duration: 1.1)
                    LinearKeyframe(0, duration: 0.35)
                }
                KeyframeTrack(\.rise) {
                    CubicKeyframe(24, duration: 1.6)
                }
                KeyframeTrack(\.scale) {
                    SpringKeyframe(1.1, duration: 0.25, spring: .bouncy)
                    SpringKeyframe(1, duration: 0.3)
                }
            }
            .allowsHitTesting(false)
            .accessibilityHidden(true)
    }
}
