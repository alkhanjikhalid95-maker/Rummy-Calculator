import Foundation

/// Standings across every finished game in history: who wins most, where
/// each player usually finishes, and how any two compare at the same table.
///
/// Players are matched by name, ignoring case, accents and stray spaces, so
/// "khalid " and "Khalid" are one player. Places follow the final totals —
/// lowest first — and players level on a total share the place, so a game
/// that ends level at the top is a win for each of them.
nonisolated struct ClubStandings {

    struct Player: Identifiable, Equatable {
        /// The name as most recently written.
        let name: String
        let key: String
        var games = 0
        var wins = 0
        var roundWins = 0
        /// How often they finished first, second, third and fourth.
        var places = [0, 0, 0, 0]
        var placeTotal = 0
        var pointsTotal = 0
        /// Lowest final total — the best game.
        var bestScore: Int?

        var id: String { key }

        var winRate: Double { games == 0 ? 0 : Double(wins) / Double(games) }
        var averagePlace: Double { games == 0 ? 0 : Double(placeTotal) / Double(games) }
        var averageScore: Double { games == 0 ? 0 : Double(pointsTotal) / Double(games) }
    }

    enum Sort: CaseIterable, Identifiable {
        /// Most games won.
        case wins
        /// Best average finishing place.
        case averagePlace
        /// Most rounds won.
        case roundWins

        var id: Self { self }
    }

    /// Everyone who has played, best record first.
    let players: [Player]
    let gameCount: Int
    private let games: [GameRecord]

    init(games: [GameRecord]) {
        self.games = games
        gameCount = games.count

        var byKey: [String: Player] = [:]
        // History is newest first, so the first spelling met is the latest.
        for record in games {
            let places = Self.places(in: record)
            // Two seats under one name count once.
            var seen = Set<String>()
            for (seat, name) in record.playerNames.enumerated() {
                let key = Self.key(name)
                guard !key.isEmpty, let place = places[seat], seen.insert(key).inserted else { continue }
                var player = byKey[key] ?? Player(name: Self.display(name), key: key)
                let score = record.finalScores[seat]
                player.games += 1
                player.placeTotal += place
                player.places[min(place, 4) - 1] += 1
                if place == 1 { player.wins += 1 }
                player.pointsTotal += score
                player.bestScore = min(player.bestScore ?? score, score)
                player.roundWins += record.roundResults.filter { Self.key($0.winnerName) == key }.count
                byKey[key] = player
            }
        }
        players = Self.sorted(Array(byKey.values), by: .wins)
    }

    func leaderboard(by sort: Sort) -> [Player] {
        Self.sorted(players, by: sort)
    }

    func player(_ key: String) -> Player? {
        players.first { $0.key == key }
    }

    /// Place on the leaderboard by wins, counting from 1.
    func overallRank(of key: String) -> Int? {
        players.firstIndex { $0.key == key }.map { $0 + 1 }
    }

    /// The player shared the most tables with `key`, best record first on a tie.
    func usualOpponent(of key: String) -> Player? {
        // `max(by:)` keeps the first of equals, and `players` is best first.
        players
            .filter { $0.key != key }
            .max { meetings(key, $0.key) < meetings(key, $1.key) }
    }

    /// How two players fared in the games they both played.
    func headToHead(_ first: String, _ second: String) -> HeadToHead {
        var result = HeadToHead()
        for record in games {
            let keys = record.playerNames.map(Self.key)
            guard first != second,
                  let a = keys.firstIndex(of: first),
                  let b = keys.firstIndex(of: second)
            else { continue }
            let places = Self.places(in: record)
            guard let placeA = places[a], let placeB = places[b] else { continue }
            let scoreA = record.finalScores[a]
            let scoreB = record.finalScores[b]

            result.first.add(place: placeA, score: scoreA, roundWins: record.roundResults.filter { Self.key($0.winnerName) == first }.count)
            result.second.add(place: placeB, score: scoreB, roundWins: record.roundResults.filter { Self.key($0.winnerName) == second }.count)
            if scoreA < scoreB {
                result.first.ahead += 1
            } else if scoreB < scoreA {
                result.second.ahead += 1
            } else {
                result.level += 1
            }
            result.meetings.append(.init(
                id: record.id,
                date: record.date,
                first: .init(place: placeA, score: scoreA),
                second: .init(place: placeB, score: scoreB)
            ))
        }
        return result
    }

    // MARK: - Helpers

    /// Matches names written differently: case, accents and spacing aside.
    static func key(_ name: String) -> String {
        display(name).folding(options: [.caseInsensitive, .diacriticInsensitive, .widthInsensitive], locale: nil)
    }

    private static func display(_ name: String) -> String {
        name.split(whereSeparator: \.isWhitespace).joined(separator: " ")
    }

    /// Each seat's finishing place, lowest total first; level totals share a
    /// place. `nil` for a seat with no name or no final total.
    static func places(in record: GameRecord) -> [Int?] {
        let totals = record.finalScores
        return record.playerNames.indices.map { seat in
            guard totals.indices.contains(seat), !key(record.playerNames[seat]).isEmpty else { return nil }
            let rivals = record.playerNames.indices.filter { $0 != seat && totals.indices.contains($0) && !key(record.playerNames[$0]).isEmpty }
            return 1 + rivals.filter { totals[$0] < totals[seat] }.count
        }
    }

    private func meetings(_ a: String, _ b: String) -> Int {
        games.filter { record in
            let keys = record.playerNames.map(Self.key)
            return keys.contains(a) && keys.contains(b)
        }.count
    }

    private static func sorted(_ players: [Player], by sort: Sort) -> [Player] {
        players.sorted { a, b in
            switch sort {
            case .wins:
                if a.wins != b.wins { return a.wins > b.wins }
                if a.winRate != b.winRate { return a.winRate > b.winRate }
                if a.averagePlace != b.averagePlace { return a.averagePlace < b.averagePlace }
            case .averagePlace:
                if a.averagePlace != b.averagePlace { return a.averagePlace < b.averagePlace }
                if a.games != b.games { return a.games > b.games }
                if a.wins != b.wins { return a.wins > b.wins }
            case .roundWins:
                if a.roundWins != b.roundWins { return a.roundWins > b.roundWins }
                if a.wins != b.wins { return a.wins > b.wins }
                if a.averagePlace != b.averagePlace { return a.averagePlace < b.averagePlace }
            }
            if a.games != b.games { return a.games > b.games }
            return a.name.localizedStandardCompare(b.name) == .orderedAscending
        }
    }
}

/// Two players over the games they both played.
nonisolated struct HeadToHead: Equatable {

    struct Side: Equatable {
        /// Games finished with the lower total of the two.
        var ahead = 0
        var wins = 0
        var roundWins = 0
        var places = [0, 0, 0, 0]
        var placeTotal = 0
        var pointsTotal = 0
        var bestScore: Int?

        fileprivate mutating func add(place: Int, score: Int, roundWins: Int) {
            placeTotal += place
            places[min(place, 4) - 1] += 1
            if place == 1 { wins += 1 }
            pointsTotal += score
            bestScore = min(bestScore ?? score, score)
            self.roundWins += roundWins
        }

        func averagePlace(over games: Int) -> Double {
            games == 0 ? 0 : Double(placeTotal) / Double(games)
        }
    }

    struct Meeting: Identifiable, Equatable {
        struct Result: Equatable {
            let place: Int
            let score: Int
        }

        let id: UUID
        let date: Date
        let first: Result
        let second: Result
    }

    enum Edge: Equatable {
        case first, second
    }

    var first = Side()
    var second = Side()
    /// Games the two finished on the same total.
    var level = 0
    /// Newest first, as history keeps them.
    var meetings: [Meeting] = []

    var games: Int { meetings.count }

    /// Who has the better record against the other: more games finished
    /// ahead, then the better average place, then more wins. `nil` when
    /// level on all three, or when they have never met.
    var better: Edge? {
        guard games > 0 else { return nil }
        if first.ahead != second.ahead { return first.ahead > second.ahead ? .first : .second }
        let a = first.averagePlace(over: games)
        let b = second.averagePlace(over: games)
        if a != b { return a < b ? .first : .second }
        if first.wins != second.wins { return first.wins > second.wins ? .first : .second }
        return nil
    }
}
