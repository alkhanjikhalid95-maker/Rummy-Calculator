import ActivityKit
import SwiftUI
import WidgetKit

struct RummyScoreWidgetLiveActivity: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: GameActivityAttributes.self) { context in
            // LOCK SCREEN / NOTIFICATION BANNER
            LockScreenActivityView(state: context.state, isFollowing: context.attributes.isFollowing)
                .activityBackgroundTint(Color.white.opacity(0.92))
                .activitySystemActionForegroundColor(WidgetPalette.ink)
        } dynamicIsland: { context in
            let state = context.state
            return DynamicIsland {
                DynamicIslandExpandedRegion(.leading) {
                    VStack(alignment: .leading, spacing: 4) {
                        Label {
                            Text(state.isLobby == true ? "بانتظار البدء" : (state.isGameOver ? "انتهت" : "اللفة \(state.currentRound)"))
                        } icon: {
                            Image(systemName: "suit.spade.fill")
                        }
                        .font(.system(size: 14, weight: .medium))
                        .foregroundStyle(.white)
                        RoundPips(round: state.currentRound, isGameOver: state.isGameOver, tone: .dark)
                    }
                    .padding(.leading, 4)
                }
                DynamicIslandExpandedRegion(.trailing) {
                    GameClock(startDate: state.startDate, elapsedSeconds: state.elapsedSeconds, isGameOver: state.isGameOver, tone: .dark)
                        .padding(.trailing, 4)
                }
                DynamicIslandExpandedRegion(.bottom) {
                    VStack(spacing: 8) {
                        SeatsRow(
                            names: state.playerNames,
                            scores: state.scores,
                            leaderIndex: state.leaderIndex,
                            mySeat: state.mySeat,
                            compact: true,
                            tone: .dark,
                            showScores: state.isLobby != true
                        )
                        if let advice = state.advice {
                            AdviceRow(advice: advice, compact: true, tone: .dark)
                        }
                    }
                }
            } compactLeading: {
                HStack(spacing: 3) {
                    Image(systemName: "suit.spade.fill")
                    Text("\(state.currentRound)")
                        .monospacedDigit()
                }
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(.white)
            } compactTrailing: {
                CompactTrailingView(state: state)
            } minimal: {
                Image(systemName: "suit.spade.fill")
                    .font(.system(size: 12))
                    .foregroundStyle(.white)
            }
            .keylineTint(WidgetPalette.mauve)
        }
    }
}

// MARK: - Lock Screen

private struct LockScreenActivityView: View {
    let state: GameActivityAttributes.ContentState
    let isFollowing: Bool

    var body: some View {
        VStack(spacing: 10) {
            HStack(spacing: 8) {
                Image(systemName: "suit.spade.fill")
                    .font(.system(size: 13))
                    .foregroundStyle(WidgetPalette.ink)
                if state.isLobby == true {
                    Text("بانتظار بدء اللعبة")
                        .font(.system(size: 15, weight: .medium))
                        .foregroundStyle(WidgetPalette.ink)
                } else {
                    Text(roundTitle(state.currentRound, isGameOver: state.isGameOver))
                        .font(.system(size: 15, weight: .medium))
                        .foregroundStyle(WidgetPalette.ink)
                    RoundPips(round: state.currentRound, isGameOver: state.isGameOver)
                }
                Spacer(minLength: 4)
                if isFollowing && !state.isConnected {
                    Label("غير متصل", systemImage: "antenna.radiowaves.left.and.right.slash")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(WidgetPalette.negative)
                        .labelStyle(.titleAndIcon)
                } else if state.isLobby != true {
                    GameClock(startDate: state.startDate, elapsedSeconds: state.elapsedSeconds, isGameOver: state.isGameOver)
                }
            }

            SeatsRow(
                names: state.playerNames,
                scores: state.scores,
                leaderIndex: state.leaderIndex,
                mySeat: state.mySeat,
                showScores: state.isLobby != true
            )

            if state.isLobby == true {
                Text(state.mySeat.map { "مقعدك: \(state.playerNames.indices.contains($0) ? state.playerNames[$0] : "")" } ?? "بانتظار المضيف ليختار مقعدك")
                    .font(.system(size: 13))
                    .foregroundStyle(WidgetPalette.inkSecondary)
            }

            if let advice = state.advice {
                AdviceRow(advice: advice)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                    .background(WidgetPalette.mauveLight.opacity(0.55), in: Capsule())
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 14)
    }
}

/// The player's own total when they have a seat, the leader's otherwise.
private struct CompactTrailingView: View {
    let state: GameActivityAttributes.ContentState

    var body: some View {
        if let seat = state.mySeat, seat < state.scores.count {
            Text(state.scores[seat].formatted())
                .font(.system(size: 13, weight: .medium).monospacedDigit())
                .foregroundStyle(state.leaderIndex == seat ? WidgetPalette.positiveOnDark : .white)
        } else if let leader = state.leaderIndex, leader < state.scores.count {
            HStack(spacing: 2) {
                Image(systemName: "crown.fill")
                    .font(.system(size: 9))
                    .foregroundStyle(.white)
                Text(state.scores[leader].formatted())
                    .font(.system(size: 13, weight: .medium).monospacedDigit())
                    .foregroundStyle(.white)
            }
        }
    }
}

// MARK: - Preview

#Preview("Live Activity", as: .content, using: GameActivityAttributes(isFollowing: true)) {
    RummyScoreWidgetLiveActivity()
} contentStates: {
    GameActivityAttributes.ContentState(
        playerNames: ["خالد", "حمد", "علي", "سعود"],
        scores: [-60, 520, 300, 200],
        currentRound: 7,
        isGameOver: false,
        leaderIndex: 0,
        elapsedSeconds: 1954,
        startDate: Date().addingTimeInterval(-1954),
        mySeat: 1,
        advice: SeatAdvice(
            kind: .overtake,
            rank: 4,
            gap: 580,
            roundsLeft: 3,
            needs: [.init(label: "كلر", count: 1), .init(label: "عادي", count: 1)]
        )
    )
    GameActivityAttributes.ContentState(
        playerNames: ["خالد", "حمد", "علي", "سعود"],
        scores: [-60, 200, 300, 200],
        currentRound: 3,
        isGameOver: false,
        leaderIndex: 0,
        elapsedSeconds: 754,
        startDate: Date().addingTimeInterval(-754)
    )
}
