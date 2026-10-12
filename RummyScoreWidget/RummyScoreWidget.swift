//
//  RummyScoreWidget.swift
//  RummyScoreWidget
//
//  Created by khalid alkhanji on 28/03/2026.
//

import WidgetKit
import SwiftUI

// MARK: - Timeline Entry

struct RummyScoreEntry: TimelineEntry {
    let date: Date
    let state: WidgetGameState?
}

// MARK: - Timeline Provider

struct RummyScoreProvider: TimelineProvider {
    static let sample = WidgetGameState(
        playerNames: ["خالد", "حمد", "علي", "سعود"],
        scores: [-60, 520, 300, 200],
        currentRound: 7,
        isGameOver: false,
        leaderIndex: 0,
        lastUpdated: Date(),
        startDate: Date().addingTimeInterval(-1954),
        elapsedSeconds: 1954,
        mySeat: 1,
        advice: SeatAdvice(
            kind: .overtake,
            rank: 4,
            gap: 580,
            roundsLeft: 3,
            needs: [.init(label: "كلر", count: 1), .init(label: "عادي", count: 1)]
        )
    )

    func placeholder(in context: Context) -> RummyScoreEntry {
        RummyScoreEntry(date: Date(), state: Self.sample)
    }

    func getSnapshot(in context: Context, completion: @escaping (RummyScoreEntry) -> Void) {
        // The gallery shows a game in progress rather than an empty card.
        let state = WidgetGameState.load() ?? (context.isPreview ? Self.sample : nil)
        completion(RummyScoreEntry(date: Date(), state: state))
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<RummyScoreEntry>) -> Void) {
        let now = Date()
        guard let state = WidgetGameState.load() else {
            completion(Timeline(entries: [RummyScoreEntry(date: now, state: nil)], policy: .never))
            return
        }
        // The app reloads on every change; past the stale mark an untouched
        // board is treated as abandoned rather than shown forever.
        let staleAt = state.lastUpdated.addingTimeInterval(WidgetGameState.staleAfter)
        var entries = [RummyScoreEntry(date: now, state: staleAt > now ? state : nil)]
        if staleAt > now {
            entries.append(RummyScoreEntry(date: staleAt, state: nil))
        }
        completion(Timeline(entries: entries, policy: .never))
    }
}

// MARK: - Widget View

struct RummyScoreWidgetView: View {
    @Environment(\.widgetFamily) var family
    let entry: RummyScoreEntry

    var body: some View {
        switch family {
        case .systemSmall:
            if let state = entry.state { smallView(state) } else { noGameHome }
        case .systemMedium:
            if let state = entry.state { mediumView(state) } else { noGameHome }
        case .accessoryCircular:
            circularView(entry.state)
        case .accessoryInline:
            inlineView(entry.state)
        default:
            if let state = entry.state { rectangularView(state) } else { noGameRectangular }
        }
    }

    // MARK: Home screen

    private func header(_ state: WidgetGameState) -> some View {
        HStack(spacing: 6) {
            Image(systemName: "suit.spade.fill")
                .font(.system(size: 12))
            Text(roundTitle(state.currentRound, isGameOver: state.isGameOver))
                .font(.system(size: 14, weight: .medium))
            Spacer(minLength: 4)
            GameClock(startDate: state.startDate, elapsedSeconds: state.elapsedSeconds ?? 0, isGameOver: state.isGameOver, tone: .dark)
        }
    }

    private func mediumView(_ state: WidgetGameState) -> some View {
        VStack(spacing: 8) {
            header(state)
                .foregroundStyle(.white)
            SeatsRow(
                names: state.playerNames,
                scores: state.scores,
                leaderIndex: state.leaderIndex,
                mySeat: state.mySeat,
                tone: .dark
            )
            if let advice = state.advice {
                AdviceRow(advice: advice, compact: true, tone: .dark)
            } else {
                RoundPips(round: state.currentRound, isGameOver: state.isGameOver, tone: .dark)
            }
        }
    }

    /// The player's own seat when they have one, the leader otherwise.
    private func smallView(_ state: WidgetGameState) -> some View {
        let focus = state.mySeat ?? state.leaderIndex ?? 0
        let name = state.playerNames.indices.contains(focus) ? state.playerNames[focus] : ""
        let score = state.scores.indices.contains(focus) ? state.scores[focus] : 0

        return VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 4) {
                Image(systemName: "suit.spade.fill")
                Text(state.isGameOver ? "انتهت" : "اللفة \(state.currentRound)")
            }
            .font(.system(size: 13, weight: .medium))
            .foregroundStyle(.white.opacity(0.85))

            Spacer(minLength: 0)

            HStack(spacing: 4) {
                if state.leaderIndex == focus {
                    Image(systemName: "crown.fill")
                        .font(.system(size: 11))
                }
                Text(name)
                    .font(.system(size: 15))
                    .lineLimit(1)
            }
            .foregroundStyle(.white)
            Text(score.formatted())
                .font(.system(size: 40, weight: .light).monospacedDigit())
                .foregroundStyle(.white)
                .minimumScaleFactor(0.6)
                .lineLimit(1)
                .contentTransition(.numericText(value: Double(score)))

            if let advice = state.advice {
                Text(advice.hasPlan ? advice.needsSummary : advice.detail)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(.white.opacity(0.9))
                    .lineLimit(2)
                    .minimumScaleFactor(0.8)
            } else {
                RoundPips(round: state.currentRound, isGameOver: state.isGameOver, tone: .dark)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
    }

    private var noGameHome: some View {
        VStack(spacing: 8) {
            Image(systemName: "suit.spade.fill")
                .font(.system(size: 22, weight: .light))
            Text("حاسبة الهاند")
                .font(.system(size: 15, weight: .medium))
            Text("لا توجد لعبة حالية")
                .font(.system(size: 12))
                .opacity(0.75)
        }
        .foregroundStyle(.white)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: Lock screen

    private func rectangularView(_ state: WidgetGameState) -> some View {
        VStack(alignment: .leading, spacing: 1) {
            HStack(spacing: 4) {
                Image(systemName: "suit.spade.fill")
                    .font(.system(size: 10))
                Text(state.isGameOver ? "انتهت" : "اللفة \(state.currentRound)")
                if let advice = state.advice {
                    Text("· #\(advice.rank)")
                }
            }
            .font(.system(size: 14, weight: .semibold))
            .widgetAccentable()

            if let seat = state.mySeat, let advice = state.advice, seat < state.scores.count {
                Text("أنا \(state.scores[seat].formatted()) · \(advice.headline)")
                    .font(.system(size: 13, weight: .medium))
                    .lineLimit(1)
                Text(advice.hasPlan ? advice.needsSummary : advice.detail)
                    .font(.system(size: 13, weight: .bold))
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
            } else {
                HStack(spacing: 6) {
                    ForEach(state.playerNames.indices, id: \.self) { i in
                        if i < state.scores.count {
                            VStack(spacing: 0) {
                                HStack(spacing: 1) {
                                    if state.leaderIndex == i {
                                        Image(systemName: "crown.fill").font(.system(size: 7))
                                    }
                                    Text(String(state.playerNames[i].prefix(4)))
                                        .font(.system(size: 13, weight: state.leaderIndex == i ? .bold : .regular))
                                        .lineLimit(1)
                                }
                                Text(state.scores[i].formatted())
                                    .font(.system(size: 14, weight: .semibold, design: .monospaced))
                                    .lineLimit(1)
                                    .minimumScaleFactor(0.7)
                            }
                            .frame(maxWidth: .infinity)
                        }
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var noGameRectangular: some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack(spacing: 4) {
                Image(systemName: "suit.spade.fill")
                    .font(.system(size: 10))
                Text("حاسبة الهاند")
                    .font(.system(size: 15, weight: .semibold))
            }
            .widgetAccentable()

            Text("لا توجد لعبة حالية")
                .font(.system(size: 14))
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    /// Round progress ring; the centre shows this player's place when known.
    private func circularView(_ state: WidgetGameState?) -> some View {
        Group {
            if let state {
                Gauge(value: Double(state.isGameOver ? 9 : state.currentRound - 1), in: 0...9) {
                    Image(systemName: "suit.spade.fill")
                } currentValueLabel: {
                    if let advice = state.advice {
                        Text("#\(advice.rank)")
                    } else {
                        Text("\(state.currentRound)")
                    }
                }
                .gaugeStyle(.accessoryCircular)
                .widgetAccentable()
            } else {
                ZStack {
                    AccessoryWidgetBackground()
                    Image(systemName: "suit.spade.fill")
                        .font(.system(size: 20))
                }
            }
        }
    }

    private func inlineView(_ state: WidgetGameState?) -> some View {
        Group {
            if let state {
                if let advice = state.advice {
                    Text("♠ \(state.currentRound) · #\(advice.rank) · \(advice.hasPlan ? advice.needsSummary : advice.detail)")
                } else if let leader = state.leaderIndex, leader < state.playerNames.count {
                    Text("♠ اللفة \(state.currentRound) · 👑 \(state.playerNames[leader])")
                } else {
                    Text("♠ اللفة \(state.currentRound)")
                }
            } else {
                Text("♠ لا توجد لعبة حالية")
            }
        }
    }
}

// MARK: - Widget Definition

struct RummyScoreWidget: Widget {
    let kind: String = "RummyScoreWidget"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: RummyScoreProvider()) { entry in
            RummyScoreWidgetView(entry: entry)
                .containerBackground(for: .widget) {
                    WidgetBackground()
                }
        }
        .configurationDisplayName("نتائج الهاند")
        .description("نتائج اللعبة الحالية، وما تحتاجه لتتصدر من اللفة السابعة")
        .supportedFamilies([.systemSmall, .systemMedium, .accessoryRectangular, .accessoryCircular, .accessoryInline])
    }
}

/// Felt-and-night on the home screen; the system's own material on the lock
/// screen, where widgets are tinted.
private struct WidgetBackground: View {
    @Environment(\.widgetFamily) private var family

    var body: some View {
        switch family {
        case .systemSmall, .systemMedium:
            WidgetPalette.aura
        default:
            Color.clear
        }
    }
}

// MARK: - Preview

#Preview(as: .systemMedium) {
    RummyScoreWidget()
} timeline: {
    RummyScoreEntry(date: Date(), state: RummyScoreProvider.sample)
    RummyScoreEntry(date: Date(), state: nil)
}

#Preview(as: .accessoryRectangular) {
    RummyScoreWidget()
} timeline: {
    RummyScoreEntry(date: Date(), state: RummyScoreProvider.sample)
}
