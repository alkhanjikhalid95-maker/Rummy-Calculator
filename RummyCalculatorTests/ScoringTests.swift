import Foundation
import Testing
@testable import Rummy_Calculator

/// Exercises the scoring engine, خباص tracking and the prediction planner.
///
/// The two rule toggles live in `UserDefaults.standard`, so each test sets the
/// pair it depends on rather than inheriting whatever the last run left behind.
@MainActor
@Suite("Scoring")
struct ScoringTests {

    private static let seats = ["Khalid", "Hamad", "Ali", "Saud"]

    private func startedGame(
        noPenalty: Bool = false,
        deckWin: Bool = false
    ) -> GameViewModel {
        let viewModel = GameViewModel(sessionStore: .ephemeral)
        viewModel.noPenaltyForDroppedCard = noPenalty
        viewModel.deckWinEnabled = deckWin
        viewModel.playerNames = Self.seats
        viewModel.startGame()
        viewModel.stopTimer()
        return viewModel
    }

    private func totals(_ viewModel: GameViewModel) -> [Int] {
        viewModel.players.indices.map { viewModel.totalScore(playerIndex: $0) }
    }

    // MARK: Win types

    @Test("Every win type keeps the same credit-to-charge ratio")
    func winTypeTable() {
        for type in WinType.allCases {
            #expect(type.winnerScore < 0, "\(type.rawValue) should credit the winner")
            #expect(type.loserScore > 0, "\(type.rawValue) should charge the losers")
            // A loser always pays 10/3 of what the winner is credited.
            #expect(type.loserScore * 3 == -type.winnerScore * 10, "\(type.rawValue) is off the curve")
        }
        #expect(WinType.normal.winnerScore == -60)
        #expect(WinType.normal.loserScore == 200)
        #expect(WinType.zataJoker.winnerScore == -480)
        #expect(WinType.zataJoker.loserScore == 1600)
    }

    // MARK: Round scoring

    @Test("A normal win credits the winner and puts +100 on the next seat")
    func normalWinAppliesPenaltyToNextSeat() {
        let viewModel = startedGame()
        viewModel.selectWinner(playerIndex: 0, winType: .normal)

        #expect(totals(viewModel) == [-60, 300, 200, 200])

        let penalised = try! #require(viewModel.score(roundIndex: 0, playerIndex: 1))
        #expect(penalised.hasPenalty)
        let winner = try! #require(viewModel.score(roundIndex: 0, playerIndex: 0))
        #expect(winner.isWinner)
        #expect(!winner.hasPenalty)
    }

    @Test("The penalty wraps from the last seat back to the first")
    func penaltyWrapsAround() {
        let viewModel = startedGame()
        viewModel.selectWinner(playerIndex: 3, winType: .normal)
        #expect(totals(viewModel) == [300, 200, 200, -60])
    }

    @Test("The no-penalty rule suppresses the +100 for every round")
    func noPenaltyRule() {
        let viewModel = startedGame(noPenalty: true)
        viewModel.selectWinner(playerIndex: 0, winType: .normal)
        #expect(totals(viewModel) == [-60, 200, 200, 200])
    }

    @Test("Winning from the deck suppresses the +100 for that round only")
    func deckWinSuppressesPenaltyForOneRound() {
        let viewModel = startedGame(deckWin: true)
        viewModel.selectWinner(playerIndex: 0, winType: .normal, usedDeck: true)
        viewModel.selectWinner(playerIndex: 0, winType: .normal, usedDeck: false)

        // Round 1 charged seat 1 a flat 200; round 2 added the +100.
        #expect(viewModel.score(roundIndex: 0, playerIndex: 1)?.hasPenalty == false)
        #expect(viewModel.score(roundIndex: 1, playerIndex: 1)?.hasPenalty == true)
        #expect(totals(viewModel) == [-120, 500, 400, 400])
    }

    @Test("Cumulative scores add up round by round")
    func cumulativeScores() {
        let viewModel = startedGame(noPenalty: true)
        viewModel.selectWinner(playerIndex: 0, winType: .normal)   // 0: -60
        viewModel.selectWinner(playerIndex: 0, winType: .color)    // 0: -120

        #expect(viewModel.cumulativeScore(throughRound: 0, playerIndex: 0) == -60)
        #expect(viewModel.cumulativeScore(throughRound: 1, playerIndex: 0) == -180)
        #expect(viewModel.cumulativeScore(throughRound: 1, playerIndex: 2) == 600)
    }

    // MARK: Standings

    @Test("First and last place track the lowest and highest totals")
    func standings() {
        let viewModel = startedGame()
        viewModel.selectWinner(playerIndex: 0, winType: .normal)

        #expect(viewModel.firstPlaceIndex(throughRound: 0) == 0)
        #expect(viewModel.lastPlaceIndex(throughRound: 0) == 1)
        #expect(viewModel.lastCompletedRoundIndex == 0)
        #expect(viewModel.lastPlaceName == "Hamad")
    }

    @Test("The خباص keeps the deal while the tie for last persists")
    func khabasStaysOnATie() {
        let viewModel = startedGame(noPenalty: true)

        // Seat 0 wins twice: seats 1, 2 and 3 are level on 400.
        viewModel.selectWinner(playerIndex: 0, winType: .normal)
        viewModel.selectWinner(playerIndex: 0, winType: .normal)
        let firstDealer = try! #require(viewModel.resolvedKhabasIndex(throughRound: 1))
        #expect([1, 2, 3].contains(firstDealer))

        // Still level after a third identical round — the dealer must not move.
        viewModel.selectWinner(playerIndex: 0, winType: .normal)
        #expect(viewModel.resolvedKhabasIndex(throughRound: 2) == firstDealer)
    }

    @Test("A clear last place takes over the deal")
    func khabasMovesOnAClearLast() {
        let viewModel = startedGame(noPenalty: true)
        viewModel.selectWinner(playerIndex: 0, winType: .normal)
        viewModel.selectWinner(playerIndex: 1, winType: .normal)
        viewModel.selectWinner(playerIndex: 2, winType: .normal)
        // Seat 3 is the only one who never won: 200 × 3 = 600, worst on its own.
        #expect(viewModel.resolvedKhabasIndex(throughRound: 2) == 3)
        #expect(viewModel.lastPlaceName == "Saud")
    }

    // MARK: Editing

    @Test("Deleting a round also clears every round after it")
    func deletingARoundClearsTheRest() {
        let viewModel = startedGame()
        for _ in 0..<3 { viewModel.selectWinner(playerIndex: 0, winType: .normal) }
        #expect(viewModel.game?.currentRoundIndex == 3)

        viewModel.confirmDeleteRound(0)
        viewModel.deleteRound()

        #expect(viewModel.game?.currentRoundIndex == 0)
        #expect(viewModel.rounds.allSatisfy { !$0.isCompleted })
        #expect(totals(viewModel) == [0, 0, 0, 0])
        #expect(viewModel.lastCompletedRoundIndex == nil)
    }

    @Test("A manual score overrides the automatic one and can be reset")
    func manualOverride() {
        let viewModel = startedGame()
        viewModel.selectWinner(playerIndex: 0, winType: .normal)

        viewModel.openManualEntry(roundIndex: 0, playerIndex: 2)
        #expect(viewModel.manualEntryText == "200")
        viewModel.manualEntryText = "75"
        viewModel.applyManualScore()
        #expect(viewModel.totalScore(playerIndex: 2) == 75)

        viewModel.openManualEntry(roundIndex: 0, playerIndex: 2)
        viewModel.clearManualScore()
        #expect(viewModel.totalScore(playerIndex: 2) == 200)
    }

    @Test("Manual entry on an unplayed round is ignored")
    func manualEntryNeedsACompletedRound() {
        let viewModel = startedGame()
        viewModel.openManualEntry(roundIndex: 4, playerIndex: 0)
        #expect(!viewModel.showManualEntry)
        #expect(viewModel.manualEntryRoundIndex == nil)
    }

    // MARK: Finishing

    @Test("The game ends after nine rounds and names the lowest total")
    func gameEnds() {
        let viewModel = startedGame()
        for round in 0..<9 {
            #expect(!viewModel.isGameOver, "ended early at round \(round)")
            viewModel.selectWinner(playerIndex: 0, winType: .normal)
        }
        #expect(viewModel.isGameOver)
        #expect(viewModel.gameWinnerIndices == [0])
        #expect(viewModel.gameWinnerName == "Khalid")
        #expect(viewModel.gameWinnerScore == -540)
        #expect(!viewModel.canShowPredictions)
    }

    @Test("A level finish reports every tied seat rather than picking one")
    func levelFinishReportsBothSeats() {
        let viewModel = startedGame()
        for _ in 0..<9 { viewModel.selectWinner(playerIndex: 0, winType: .normal) }

        // Seat 0 is on -540 and seat 1 on 2700; drag seat 1 down to match.
        viewModel.openManualEntry(roundIndex: 0, playerIndex: 1)
        viewModel.manualEntryText = "-2940"
        viewModel.applyManualScore()

        #expect(viewModel.totalScore(playerIndex: 1) == -540)
        #expect(viewModel.gameWinnerIndices == [0, 1])
        #expect(viewModel.gameWinnerName == "Khalid • Hamad")
        #expect(viewModel.gameWinnerScore == -540)
    }

    @Test("Winner helpers stay empty while the game is still running")
    func noWinnerMidGame() {
        let viewModel = startedGame()
        viewModel.selectWinner(playerIndex: 0, winType: .normal)
        #expect(viewModel.gameWinnerIndices.isEmpty)
        #expect(viewModel.gameWinnerName == nil)
        #expect(viewModel.gameWinnerScore == nil)
    }

    // MARK: Predictions

    @Test("Predictions only open in the closing rounds")
    func predictionsUnlockLate() {
        let viewModel = startedGame()
        for _ in 0..<5 { viewModel.selectWinner(playerIndex: 0, winType: .normal) }
        #expect(!viewModel.canShowPredictions)   // round 6
        viewModel.selectWinner(playerIndex: 0, winType: .normal)
        #expect(viewModel.canShowPredictions)    // round 7
    }

    @Test("Every plan fits in the rounds left and takes the lead, or at least draws level")
    func predictionPlansAreSufficient() {
        let viewModel = startedGame()
        for _ in 0..<6 { viewModel.selectWinner(playerIndex: 0, winType: .normal) }

        let remaining = 9 - (viewModel.currentRoundNumber - 1)
        let predictions = viewModel.computePredictions()
        #expect(predictions.count == 3, "one row per non-leading seat")

        for prediction in predictions where prediction.canCatchUp {
            let plan = try! #require(prediction.roundPlan)
            #expect(!plan.isEmpty && plan.count <= remaining)
            let swing = plan.reduce(0) { $0 + $1.swing }
            if prediction.resultIsTie {
                #expect(swing == prediction.gap, "\(prediction.playerName)'s tie plan is off")
            } else {
                #expect(swing > prediction.gap, "\(prediction.playerName)'s plan does not take the lead")
            }
        }
    }

    @Test("An unreachable leader is reported as unreachable")
    func hopelessGapIsReported() {
        let viewModel = startedGame()
        for _ in 0..<8 { viewModel.selectWinner(playerIndex: 0, winType: .zataJoker) }

        // Seat 1 has taken eight 1600s plus penalties against a -3840 leader;
        // one round left cannot swing 2080 per round.
        let predictions = viewModel.computePredictions()
        let trailing = try! #require(predictions.first { $0.playerIndex == 1 })
        #expect(!trailing.canCatchUp)
        #expect(trailing.roundPlan == nil)
    }

    @Test("Prediction labels only appear for the current round onward")
    func predictionLabelsAreForwardLooking() {
        let viewModel = startedGame()
        for _ in 0..<6 { viewModel.selectWinner(playerIndex: 0, winType: .normal) }
        viewModel.predictionsActive = true

        #expect(viewModel.predictionLabel(roundIndex: 0, playerIndex: 1) == nil)
        #expect(viewModel.predictionLabel(roundIndex: 6, playerIndex: 1) != nil)

        viewModel.predictionsActive = false
        #expect(viewModel.predictionLabel(roundIndex: 6, playerIndex: 1) == nil)
    }

    // MARK: Session lifecycle

    @Test("Pausing parks the board and resuming brings it back intact")
    func pauseAndResume() {
        let viewModel = startedGame()
        viewModel.selectWinner(playerIndex: 0, winType: .normal)
        let before = totals(viewModel)
        let dealer = viewModel.resolvedKhabasIndex(throughRound: 0)

        viewModel.pauseGame()
        #expect(!viewModel.isGameStarted)
        #expect(viewModel.hasPausedGame)

        viewModel.resumeGame()
        viewModel.stopTimer()
        #expect(viewModel.isGameStarted)
        #expect(!viewModel.hasPausedGame)
        #expect(totals(viewModel) == before)
        #expect(viewModel.resolvedKhabasIndex(throughRound: 0) == dealer)
    }

    @Test("Restarting keeps the seats and drops the paused board")
    func restartKeepsNames() {
        let viewModel = startedGame()
        viewModel.selectWinner(playerIndex: 0, winType: .normal)
        viewModel.pauseGame()
        viewModel.resumeGame()
        viewModel.restartGame()
        viewModel.stopTimer()

        #expect(viewModel.players.map(\.name) == Self.seats)
        #expect(totals(viewModel) == [0, 0, 0, 0])
        #expect(!viewModel.hasPausedGame)
    }

    @Test("A new game goes back to the table with the same names and no board")
    func newGameReturnsToTheTable() {
        let viewModel = startedGame()
        for _ in 0..<9 { viewModel.selectWinner(playerIndex: 0, winType: .normal) }
        viewModel.newGame()

        #expect(!viewModel.isGameStarted)
        #expect(!viewModel.hasPausedGame)
        #expect(viewModel.playerNames == Self.seats)
    }

    @Test("Deleting a round of a finished game restarts the clock")
    func deletingFromAFinishedBoardResumesTheClock() {
        let viewModel = startedGame()
        for _ in 0..<9 { viewModel.selectWinner(playerIndex: 0, winType: .normal) }
        #expect(viewModel.isGameOver)

        viewModel.confirmDeleteRound(8)
        viewModel.deleteRound()
        defer { viewModel.stopTimer() }

        #expect(!viewModel.isGameOver)
        #expect(viewModel.game?.currentRoundIndex == 8)
    }

    @Test("Empty seats fall back to P1…P4")
    func emptySeatsGetPlaceholders() {
        let viewModel = GameViewModel(sessionStore: .ephemeral)
        viewModel.playerNames = ["", "Hamad", "", ""]
        viewModel.startGame()
        viewModel.stopTimer()
        #expect(viewModel.players.map(\.name) == ["P1", "Hamad", "P3", "P4"])
    }
}

// MARK: - Preset names

@MainActor
@Suite("Preset names")
struct PresetNamesTests {

    @Test("Placeholder seat names are never saved as presets")
    func placeholdersAreBlocked() {
        let manager = PresetNamesManager()
        let before = manager.customNames
        manager.addNames(["P1", "p4", "  "])
        #expect(manager.customNames == before)
        for name in ["P1", "p4"] {
            manager.removeName(name)
        }
    }

    @Test("The built-in list carries no surnames")
    func builtInsAreGivenNamesOnly() {
        for name in PresetNamesManager.builtIn {
            #expect(!name.contains(" "), "\(name) looks like a full name")
        }
    }

    @Test("Custom names come before the built-ins and are de-duplicated")
    func customNamesLeadTheList() {
        let manager = PresetNamesManager()
        let unique = "TestSeat-\(UUID().uuidString.prefix(6))"
        manager.addNames([unique, unique])
        defer { manager.removeName(unique) }

        #expect(manager.all.first == unique)
        #expect(manager.all.filter { $0 == unique }.count == 1)
        #expect(manager.all.contains("Khalid"))
    }
}
