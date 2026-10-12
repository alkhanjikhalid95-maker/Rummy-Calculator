import Foundation

// MARK: - Prediction Result

struct PlayerPrediction: Identifiable {
    var id: Int { playerIndex }
    let playerIndex: Int
    let playerName: String
    let currentTotal: Int
    let leaderTotal: Int
    let gap: Int
    /// The wins needed, weakest first — one entry per round the player must
    /// win, so it can be shorter than the rounds left.
    let roundPlan: [WinType]?
    let resultIsTie: Bool
    let canCatchUp: Bool

    /// Summarised combination, e.g. [(عادي, 2), (كلر, 1)]
    var combinationSummary: [(winType: WinType, count: Int)] {
        guard let plan = roundPlan else { return [] }
        var counts: [WinType: Int] = [:]
        for wt in plan { counts[wt, default: 0] += 1 }
        // Return in tier order (عادي, كلر, زاته, زاته+جوكر)
        return WinType.predictionTiers.compactMap { wt in
            guard let c = counts[wt], c > 0 else { return nil }
            return (wt, c)
        }
    }
}

// MARK: - Engine

/// Works out what each trailing seat needs from the rounds that are left.
///
/// A round the player wins moves them `swing` points against the leader; a
/// round someone else wins leaves the gap where it is. So the question is
/// which wins add up to *more* than the gap — equal only draws level. The
/// +100 penalty is left out: it depends on seating and on how the hand is won,
/// so plans err on the side of asking for slightly too much.
enum PredictionEngine {

    /// The round from which plans are offered.
    static let firstAdviceRound = 7

    /// Fewest, plainest wins that take a player from `gap` points behind to
    /// the outright lead, or failing that to level. `nil` when neither is
    /// reachable in `remainingRounds`.
    static func plan(gap: Int, remainingRounds: Int) -> (plan: [WinType], isTie: Bool)? {
        if let lead = cheapestPlan(covering: gap + 1, rounds: remainingRounds) {
            return (lead, false)
        }
        if gap > 0, let level = cheapestPlan(covering: gap, rounds: remainingRounds) {
            return (level, true)
        }
        return nil
    }

    /// Wins whose swings add up to at least `target`, weakest first.
    ///
    /// Plain wins are tried first, as few as will do. When even winning every
    /// round plainly falls short, rounds are upgraded from the last backwards,
    /// spreading each tier across rounds before reaching for the next, and
    /// زاته + جوكر is held back as a last resort — it is rarely made.
    static func cheapestPlan(covering target: Int, rounds: Int) -> [WinType]? {
        let tiers = WinType.predictionTiers
        guard let weakest = tiers.first, let strongest = tiers.last else { return nil }
        guard target > 0 else { return [] }
        guard rounds > 0, strongest.swing * rounds >= target else { return nil }

        for wins in 1...rounds where weakest.swing * wins >= target {
            return Array(repeating: weakest, count: wins)
        }

        var plan = Array(repeating: weakest, count: rounds)
        var total = weakest.swing * rounds

        func upgrade(to tier: WinType) {
            for index in plan.indices.reversed() where total < target {
                guard tier.swing > plan[index].swing else { continue }
                total += tier.swing - plan[index].swing
                plan[index] = tier
            }
        }

        for tier in tiers.dropFirst() where tier != .zataJoker && total < target {
            upgrade(to: tier)
        }
        if total < target {
            upgrade(to: .zataJoker)
        }
        return total >= target ? plan : nil
    }

    /// One prediction per seat that is not outright first, nearest the lead first.
    static func predictions(names: [String], totals: [Int], remainingRounds: Int) -> [PlayerPrediction] {
        guard remainingRounds > 0, let leaderTotal = totals.min() else { return [] }

        let order = totals.indices.sorted { totals[$0] < totals[$1] }
        // The seat that heads the list is the reference leader; everyone else
        // — including anyone level with it — gets a plan.
        return order.dropFirst().map { seat in
            let gap = totals[seat] - leaderTotal
            let result = plan(gap: gap, remainingRounds: remainingRounds)
            return PlayerPrediction(
                playerIndex: seat,
                playerName: names.indices.contains(seat) ? names[seat] : "P\(seat + 1)",
                currentTotal: totals[seat],
                leaderTotal: leaderTotal,
                gap: gap,
                roundPlan: result?.plan,
                resultIsTie: result?.isTie ?? false,
                canCatchUp: result != nil
            )
        }
    }

    /// What `seat` should know about its position, for the lock screen.
    static func advice(
        forSeat seat: Int,
        totals: [Int],
        currentRound: Int,
        maxRounds: Int,
        isGameOver: Bool
    ) -> SeatAdvice? {
        guard totals.indices.contains(seat) else { return nil }
        let mine = totals[seat]
        let others = totals.enumerated().filter { $0.offset != seat }.map(\.element)
        let bestOther = others.min() ?? mine
        let rank = 1 + totals.filter { $0 < mine }.count
        let roundsLeft = isGameOver ? 0 : max(0, maxRounds - currentRound + 1)

        if mine < bestOther {
            return SeatAdvice(
                kind: isGameOver ? .finished : .leading,
                rank: 1,
                gap: bestOther - mine,
                roundsLeft: roundsLeft
            )
        }

        let gap = mine - bestOther
        if isGameOver {
            return SeatAdvice(kind: .finished, rank: rank, gap: gap, roundsLeft: 0)
        }
        guard currentRound >= firstAdviceRound else {
            return SeatAdvice(kind: .behind, rank: rank, gap: gap, roundsLeft: roundsLeft)
        }
        guard let result = plan(gap: gap, remainingRounds: roundsLeft) else {
            return SeatAdvice(kind: .outOfReach, rank: rank, gap: gap, roundsLeft: roundsLeft)
        }
        return SeatAdvice(
            kind: result.isTie ? .tie : .overtake,
            rank: rank,
            gap: gap,
            roundsLeft: roundsLeft,
            needs: needs(for: result.plan)
        )
    }

    /// A plan folded into counts per win type, strongest first.
    static func needs(for plan: [WinType]) -> [SeatAdvice.Need] {
        WinType.predictionTiers.reversed().compactMap { tier in
            let count = plan.filter { $0 == tier }.count
            return count > 0 ? SeatAdvice.Need(label: tier.rawValue, count: count) : nil
        }
    }
}
