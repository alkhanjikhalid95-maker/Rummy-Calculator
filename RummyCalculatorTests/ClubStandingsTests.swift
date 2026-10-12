import Foundation
import Testing
@testable import Rummy_Calculator

/// A finished game for the standings, newest first like history keeps them.
func standingsRecord(
    _ names: [String],
    _ scores: [Int],
    roundWinners: [String] = [],
    daysAgo: Int = 0
) -> GameRecord {
    let best = scores.min() ?? 0
    return GameRecord(
        id: UUID(),
        date: Date(timeIntervalSince1970: 1_790_000_000 - Double(daysAgo) * 86_400),
        duration: 1_800,
        playerNames: names,
        finalScores: scores,
        winnerName: names[scores.firstIndex(of: best) ?? 0],
        roundResults: roundWinners.enumerated().map { index, winner in
            GameRecord.RoundResult(roundNumber: index + 1, winnerName: winner, winType: WinType.normal.rawValue, scores: [0, 0, 0, 0])
        }
    )
}

@MainActor
@Suite("Club standings")
struct ClubStandingsTests {

    @Test("Places follow the final totals, lowest first, and level totals share a place")
    func placesShareTies() {
        let record = standingsRecord(["A", "B", "C", "D"], [300, 100, 100, 500])
        #expect(ClubStandings.places(in: record) == [3, 1, 1, 4])
    }

    @Test("Wins, places and points add up across games; a level finish at the top is a win for both")
    func countsAcrossGames() throws {
        let standings = ClubStandings(games: [
            standingsRecord(["Khalid", "Hamad", "Ali", "Saud"], [100, 100, 400, 900], roundWinners: ["Khalid", "Hamad", "Khalid"]),
            standingsRecord(["Khalid", "Hamad", "Ali", "Saud"], [700, 200, 300, 900], roundWinners: ["Hamad"]),
        ])
        #expect(standings.gameCount == 2)

        let khalid = try #require(standings.player(ClubStandings.key("Khalid")))
        #expect(khalid.games == 2)
        #expect(khalid.wins == 1)
        #expect(khalid.places == [1, 0, 1, 0])
        #expect(khalid.averagePlace == 2)
        #expect(khalid.pointsTotal == 800)
        #expect(khalid.bestScore == 100)
        #expect(khalid.roundWins == 2)

        let hamad = try #require(standings.player(ClubStandings.key("Hamad")))
        #expect(hamad.wins == 2)
        #expect(hamad.winRate == 1)
        #expect(hamad.roundWins == 2)

        let saud = try #require(standings.player(ClubStandings.key("Saud")))
        #expect(saud.places == [0, 0, 0, 2])
    }

    @Test("Names match whatever their case or spacing, under the latest spelling")
    func namesMatchLoosely() throws {
        let standings = ClubStandings(games: [
            standingsRecord(["Khalid", "Hamad", "Ali", "Saud"], [100, 200, 300, 400]),
            standingsRecord(["  khalid ", "HAMAD", "Ali", "Saud"], [100, 200, 300, 400], daysAgo: 3),
        ])
        #expect(standings.players.count == 4)
        let khalid = try #require(standings.player(ClubStandings.key("KHALID")))
        #expect(khalid.name == "Khalid")
        #expect(khalid.games == 2)
    }

    @Test("Blank seats are skipped and a name twice at one table counts once")
    func blankAndRepeatedNames() throws {
        let standings = ClubStandings(games: [
            standingsRecord(["Ali", "", "Ali", "Saud"], [100, 200, 300, 400]),
        ])
        #expect(standings.players.map(\.name).sorted() == ["Ali", "Saud"])
        let ali = try #require(standings.player(ClubStandings.key("Ali")))
        #expect(ali.games == 1)
        #expect(ali.wins == 1)
    }

    @Test("The leaderboard sorts by wins, by average place or by rounds won")
    func leaderboardSorts() {
        let standings = ClubStandings(games: [
            standingsRecord(["Khalid", "Hamad", "Ali", "Saud"], [100, 200, 300, 400], roundWinners: ["Saud", "Saud", "Saud"]),
            standingsRecord(["Khalid", "Hamad", "Ali", "Saud"], [100, 200, 300, 400]),
            standingsRecord(["Fahad", "Hamad", "Ali", "Saud"], [500, 100, 200, 300]),
        ])
        #expect(standings.leaderboard(by: .wins).map(\.name).prefix(2) == ["Khalid", "Hamad"])
        #expect(standings.leaderboard(by: .averagePlace).first?.name == "Khalid")
        #expect(standings.leaderboard(by: .averagePlace).last?.name == "Fahad")
        #expect(standings.leaderboard(by: .roundWins).first?.name == "Saud")
        #expect(standings.overallRank(of: ClubStandings.key("Khalid")) == 1)
    }

    @Test("Head-to-head counts only shared games: who finished ahead, places and wins")
    func headToHead() throws {
        let standings = ClubStandings(games: [
            standingsRecord(["Khalid", "Hamad", "Ali", "Saud"], [100, 200, 300, 400], roundWinners: ["Khalid", "Hamad"], daysAgo: 0),
            standingsRecord(["Khalid", "Hamad", "Ali", "Saud"], [500, 300, 100, 600], daysAgo: 1),
            standingsRecord(["Khalid", "Hamad", "Ali", "Saud"], [200, 200, 100, 600], daysAgo: 2),
            standingsRecord(["Khalid", "Fahad", "Ali", "Saud"], [900, 100, 200, 300], daysAgo: 3),
        ])
        let result = standings.headToHead(ClubStandings.key("Khalid"), ClubStandings.key("Hamad"))
        #expect(result.games == 3)
        #expect(result.first.ahead == 1)
        #expect(result.second.ahead == 1)
        #expect(result.level == 1)
        #expect(result.first.wins == 1)
        #expect(result.first.places == [1, 1, 1, 0])
        #expect(result.second.places == [0, 3, 0, 0])
        #expect(result.first.roundWins == 1)
        #expect(result.second.roundWins == 1)
        // Level on games ahead and on average place: Khalid's win decides it.
        #expect(result.first.averagePlace(over: 3) == result.second.averagePlace(over: 3))
        #expect(result.better == .first)
        #expect(result.meetings.map(\.first.score) == [100, 500, 200])
    }

    @Test("Two players who never shared a table have no verdict")
    func neverMet() {
        let standings = ClubStandings(games: [
            standingsRecord(["Khalid", "Hamad", "Ali", "Saud"], [100, 200, 300, 400]),
            standingsRecord(["Fahad", "Hamad", "Ali", "Saud"], [100, 200, 300, 400]),
        ])
        let result = standings.headToHead(ClubStandings.key("Khalid"), ClubStandings.key("Fahad"))
        #expect(result.games == 0)
        #expect(result.better == nil)
        #expect(standings.headToHead(ClubStandings.key("Ali"), ClubStandings.key("Ali")).games == 0)
    }

    @Test("A player's usual opponent is the one they have shared most tables with")
    func usualOpponent() {
        let standings = ClubStandings(games: [
            standingsRecord(["Fahad", "Hamad", "Ali", "Saud"], [100, 200, 300, 400]),
            standingsRecord(["Fahad", "Hamad", "Ali", "Nasser"], [100, 200, 300, 400]),
            standingsRecord(["Fahad", "Khalid", "Yousef", "Nasser"], [400, 100, 300, 200]),
            standingsRecord(["Fahad", "Khalid", "Yousef", "Nasser"], [400, 100, 300, 200]),
            standingsRecord(["Fahad", "Khalid", "Yousef", "Nasser"], [400, 100, 300, 200]),
        ])
        #expect(standings.usualOpponent(of: ClubStandings.key("Fahad"))?.name == "Nasser")
    }
}
