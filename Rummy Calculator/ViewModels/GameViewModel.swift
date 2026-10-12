import ActivityKit
import Foundation
import OSLog
import SwiftUI
import WidgetKit

private let logger = Logger(subsystem: "KHALID.Rummy-Calculator", category: "LiveActivity")

@Observable
final class GameViewModel {

    // MARK: - Game State

    var game: Game?
    var playerNames: [String] = ["", "", "", ""]
    let historyManager = GameHistoryManager()
    let presetNames = PresetNamesManager()
    let nearbyHost = NearbyHost()
    /// Phones at the table and the seats they hold.
    private(set) var lobby = TableLobby()
    private let sessionStore: GameSessionStore
    @ObservationIgnored private var publishTask: Task<Void, Never>?

    /// The seat played by this phone's owner, when they have said — it
    /// personalises the Live Activity and widgets.
    private(set) var localSeatIndex: Int?

    init(sessionStore: GameSessionStore = .standard) {
        self.sessionStore = sessionStore
        nearbyHost.onPlayerJoined = { [weak self] player in self?.playerJoined(player) }
        nearbyHost.onPlayerLeft = { [weak self] playerID in
            self?.lobby.leave(playerID: playerID)
            self?.publishToNearby()
        }
        nearbyHost.onAllPlayersLeft = { [weak self] in self?.lobby.disconnectAll() }
        restoreSavedSession()
    }

    // MARK: - UI State

    var showWinnerPicker = false
    /// The seat the winner picker opens on, when the player tapped one.
    var winnerPickerSeat: Int?
    var showScoreSheet = false
    /// Counts recorded rounds — drives the table's per-round animation and haptic.
    private(set) var scoreEvent = 0
    var selectedRoundIndex: Int?
    var showManualEntry = false
    var manualEntryPlayerIndex: Int?
    var manualEntryRoundIndex: Int?
    var manualEntryText = ""
    var showCalculator = false
    var showPredictions = false
    var predictionsActive = false

    // MARK: - Rules

    /// When true, the winner doesn't cause a +100 penalty to the next player
    var noPenaltyForDroppedCard: Bool {
        get { UserDefaults.standard.bool(forKey: "noPenaltyForDroppedCard") }
        set { UserDefaults.standard.set(newValue, forKey: "noPenaltyForDroppedCard") }
    }

    /// When true, WinnerPickerView adds a per-round step asking whether the winner used the deck.
    /// The answer overrides the global noPenaltyForDroppedCard for that round only.
    var deckWinEnabled: Bool {
        get { UserDefaults.standard.bool(forKey: "deckWinEnabled") }
        set { UserDefaults.standard.set(newValue, forKey: "deckWinEnabled") }
    }

    // MARK: - خباص (Dealer) Tracking

    /// The seat index of the current خباص (dealer). Persists across tied rounds.
    private(set) var currentKhabasIndex: Int?

    // MARK: - Timer

    var gameStartDate: Date?
    var elapsedSeconds: Int = 0
    private var timerTask: Task<Void, Never>?

    var timerString: String {
        let h = elapsedSeconds / 3600
        let m = (elapsedSeconds % 3600) / 60
        let s = elapsedSeconds % 60
        if h > 0 {
            return String(format: "%d:%02d:%02d", h, m, s)
        }
        return String(format: "%02d:%02d", m, s)
    }

    // MARK: - Live Activity

    private var currentActivity: Activity<GameActivityAttributes>?

    // MARK: - Round Deletion

    var roundToDelete: Int?
    var showDeleteConfirmation = false

    // MARK: - Computed

    var isGameStarted: Bool { game != nil }

    var isGameOver: Bool { game?.isGameOver ?? false }

    var currentRoundNumber: Int {
        guard let game else { return 1 }
        return (game.currentRoundIndex ?? game.maxRounds - 1) + 1
    }

    var canShowPredictions: Bool {
        currentRoundNumber >= 7 && !isGameOver
    }

    var players: [Player] { game?.players ?? [] }

    var rounds: [Round] { game?.rounds ?? [] }

    /// Seat index (or indices) holding the lowest total once the game is over.
    /// More than one when the game ends level — the celebration shows them all.
    var gameWinnerIndices: [Int] {
        guard isGameOver, !players.isEmpty else { return [] }
        let totals = players.indices.map { totalScore(playerIndex: $0) }
        guard let best = totals.min() else { return [] }
        return totals.indices.filter { totals[$0] == best }
    }

    /// The name of the overall game winner (lowest cumulative score).
    /// Tied winners are joined so a level finish never silently picks one seat.
    var gameWinnerName: String? {
        let indices = gameWinnerIndices
        guard !indices.isEmpty else { return nil }
        return indices.map { players[$0].name }.joined(separator: " • ")
    }

    /// The winning total, shown alongside the name on the celebration screen.
    var gameWinnerScore: Int? {
        guard let seat = gameWinnerIndices.first else { return nil }
        return totalScore(playerIndex: seat)
    }

    /// The index of the last completed round (for coloring first/last place).
    var lastCompletedRoundIndex: Int? {
        guard let game else { return nil }
        // Find the last round that is completed
        for i in stride(from: game.rounds.count - 1, through: 0, by: -1) {
            if game.rounds[i].isCompleted { return i }
        }
        return nil
    }

    /// Player index with the lowest cumulative score through a given round (first place / best).
    func firstPlaceIndex(throughRound roundIndex: Int) -> Int? {
        guard !players.isEmpty else { return nil }
        var bestIdx = 0
        var bestScore = cumulativeScore(throughRound: roundIndex, playerIndex: 0)
        for i in 1..<players.count {
            let s = cumulativeScore(throughRound: roundIndex, playerIndex: i)
            if s < bestScore {
                bestScore = s
                bestIdx = i
            }
        }
        return bestIdx
    }

    /// Player index with the highest cumulative score through a given round (last place / worst).
    func lastPlaceIndex(throughRound roundIndex: Int) -> Int? {
        guard !players.isEmpty else { return nil }
        var worstIdx = 0
        var worstScore = cumulativeScore(throughRound: roundIndex, playerIndex: 0)
        for i in 1..<players.count {
            let s = cumulativeScore(throughRound: roundIndex, playerIndex: i)
            if s > worstScore {
                worstScore = s
                worstIdx = i
            }
        }
        return worstIdx
    }

    /// Name of the current خباص (dealer / last-place player).
    /// If tied for last, the current dealer stays unless a clear 4th place emerges.
    var lastPlaceName: String? {
        guard let roundIdx = lastCompletedRoundIndex else { return nil }
        guard let idx = resolvedKhabasIndex(throughRound: roundIdx) else { return nil }
        return players[idx].name
    }

    /// Determines the خباص index with tie-breaking logic:
    /// - If one player is clearly in last place, they become the خباص.
    /// - If tied for last, the current خباص stays (dealer doesn't change on ties).
    /// - Anti-clockwise: when a new clear last place emerges, that player becomes خباص.
    func resolvedKhabasIndex(throughRound roundIndex: Int) -> Int? {
        guard !players.isEmpty else { return nil }

        // Find highest (worst) score
        var worstScore = Int.min
        for i in 0..<players.count {
            let s = cumulativeScore(throughRound: roundIndex, playerIndex: i)
            if s > worstScore { worstScore = s }
        }

        // Find all players tied at worst score
        var tiedIndices: [Int] = []
        for i in 0..<players.count {
            if cumulativeScore(throughRound: roundIndex, playerIndex: i) == worstScore {
                tiedIndices.append(i)
            }
        }

        if tiedIndices.count == 1 {
            // Clear last place — this player is the خباص
            return tiedIndices[0]
        } else {
            // Tied for last: if current خباص is among the tied players, they stay
            if let current = currentKhabasIndex, tiedIndices.contains(current) {
                return current
            }
            // Otherwise pick the first tied player (fallback)
            return tiedIndices.first
        }
    }

    // MARK: - Cumulative Score

    func cumulativeScore(throughRound roundIndex: Int, playerIndex: Int) -> Int {
        guard let game else { return 0 }
        let playerId = game.players[playerIndex].id
        var total = 0
        for i in 0...roundIndex {
            if let score = game.rounds[i].scores.first(where: { $0.playerId == playerId }) {
                total += score.effectiveScore
            }
        }
        return total
    }

    // MARK: - Start Game

    func startGame() {
        // Clear any paused game when starting a new one
        pausedGame = nil

        // Auto-save manually entered names to presets
        let nonEmpty = playerNames.filter { !$0.isEmpty }
        presetNames.addNames(nonEmpty)

        let players = playerNames.enumerated().map { index, name in
            Player(name: name.isEmpty ? "P\(index + 1)" : name, seatIndex: index)
        }
        game = Game(players: players)
        currentKhabasIndex = nil
        localSeatIndex = PlayerIdentity.seat(in: players.map(\.name))
        startTimer()
        startLiveActivity()
        if nearbyHost.isEnabled {
            nearbyHost.start()
        }
        gameDidChange()
    }

    // MARK: - Timer

    func startTimer() {
        gameStartDate = Date()
        elapsedSeconds = 0
        runTimer()
    }

    /// Ticks the on-board clock. The lock screen counts from `gameStartDate`
    /// on its own, so the Live Activity is not refreshed every tick.
    private func runTimer() {
        timerTask?.cancel()
        timerTask = Task { @MainActor [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(1))
                guard !Task.isCancelled else { break }
                if let start = self?.gameStartDate {
                    self?.elapsedSeconds = Int(Date().timeIntervalSince(start))
                }
            }
        }
    }

    func stopTimer() {
        timerTask?.cancel()
        timerTask = nil
    }

    // MARK: - Change Fan-out

    /// Pushes the board everywhere it is shown outside this screen, and saves
    /// it. Every mutation of `game` ends here.
    private func gameDidChange() {
        updateWidgetState()
        updateLiveActivity()
        publishToNearby()
        persistSession()
    }

    // MARK: - Local Seat

    /// Marks which player owns this phone, and remembers the name so the same
    /// player is recognised in the next game.
    func setLocalSeat(_ seat: Int?) {
        localSeatIndex = seat
        if let seat, players.indices.contains(seat) {
            PlayerIdentity.preferredName = players[seat].name
        }
        updateWidgetState()
        updateLiveActivity()
        persistSession()
    }

    /// Standing and advice for this phone's own seat.
    var localSeatAdvice: SeatAdvice? {
        guard let game, let seat = localSeatIndex else { return nil }
        return PredictionEngine.advice(
            forSeat: seat,
            totals: totals,
            currentRound: currentRoundNumber,
            maxRounds: game.maxRounds,
            isGameOver: game.isGameOver
        )
    }

    var totals: [Int] {
        players.indices.map { totalScore(playerIndex: $0) }
    }

    /// Seat with the lowest total — the first on a tie.
    var leaderIndex: Int? {
        let totals = totals
        guard let best = totals.min() else { return nil }
        return totals.firstIndex(of: best)
    }

    // MARK: - Widget Integration

    private func updateWidgetState() {
        guard let game else {
            clearWidgetState()
            return
        }

        var state = WidgetGameState(
            playerNames: game.players.map(\.name),
            scores: totals,
            currentRound: currentRoundNumber,
            isGameOver: game.isGameOver,
            leaderIndex: leaderIndex,
            lastUpdated: Date()
        )
        state.startDate = game.isGameOver ? nil : gameStartDate
        state.elapsedSeconds = elapsedSeconds
        state.mySeat = localSeatIndex
        state.advice = localSeatAdvice
        state.save()
        WidgetCenter.shared.reloadAllTimelines()
    }

    private func clearWidgetState() {
        WidgetGameState.clear()
        WidgetCenter.shared.reloadAllTimelines()
    }

    // MARK: - Nearby Sharing

    /// Turns sharing with nearby phones on or off — the lobby on the start
    /// page as well as games.
    func setNearbySharing(_ enabled: Bool) {
        nearbyHost.isEnabled = enabled
        if enabled {
            nearbyHost.start()
            publishToNearby()
        } else {
            nearbyHost.stop()
        }
    }

    /// The table-setup page is showing: open the lobby when sharing is on.
    func openLobby() {
        guard nearbyHost.isEnabled else { return }
        nearbyHost.start()
        publishToNearby()
    }

    private func publishToNearby() {
        publishTask?.cancel()
        publishTask = nil
        guard nearbyHost.status != .off, let snapshot = tableSnapshot else { return }
        nearbyHost.publish(snapshot)
    }

    /// Coalesces bursts — a name typed letter by letter — into one update.
    private func schedulePublish() {
        publishTask?.cancel()
        publishTask = Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(300))
            guard !Task.isCancelled else { return }
            self?.publishToNearby()
        }
    }

    /// The table as nearby phones receive it: the lobby before a game, then
    /// the board.
    var tableSnapshot: TableSnapshot? {
        guard let game else {
            return TableSnapshot(
                hostID: NearbyHost.hostID,
                gameID: nil,
                names: playerNames.map { $0.trimmingCharacters(in: .whitespaces) },
                totals: Array(repeating: 0, count: playerNames.count),
                round: 1,
                maxRounds: 9,
                isOver: false,
                dealer: nil,
                startedAt: nil,
                elapsed: 0,
                lastWinner: nil,
                lastWinType: nil,
                owners: lobby.owners,
                lobby: lobby.connected
            )
        }
        let lastRound = lastCompletedRoundIndex.map { game.rounds[$0] }
        return TableSnapshot(
            hostID: NearbyHost.hostID,
            gameID: game.id,
            names: game.players.map(\.name),
            totals: totals,
            round: currentRoundNumber,
            maxRounds: game.maxRounds,
            isOver: game.isGameOver,
            dealer: lastCompletedRoundIndex.flatMap { resolvedKhabasIndex(throughRound: $0) },
            startedAt: game.isGameOver ? nil : gameStartDate,
            elapsed: elapsedSeconds,
            lastWinner: lastRound?.winnerId.flatMap { id in game.players.firstIndex { $0.id == id } },
            lastWinType: lastRound?.winType?.rawValue,
            owners: lobby.owners,
            lobby: lobby.connected
        )
    }

    // MARK: - Lobby

    /// Nearby players connected and not yet seated.
    var availablePlayers: [LobbyPlayer] { lobby.available }

    /// Seats held by a phone that is connected right now.
    var linkedSeats: Set<Int> { lobby.linkedSeats }

    /// Whether the start page should offer nearby players: sharing is on and
    /// Bluetooth is working.
    var isLobbyOpen: Bool { nearbyHost.isEnabled && nearbyHost.status == .live }

    private func playerJoined(_ player: LobbyPlayer) {
        lobby.join(player)
        // A seated player who renamed themselves carries the new name into
        // the seat — but never mid-game, where names are the board's.
        if game == nil, let seat = lobby.seat(of: player.id) {
            playerNames[seat] = lobby.displayName(for: player.id)
        }
        publishToNearby()
    }

    /// Seats a nearby player, writing their name into the seat.
    func seatPlayer(_ playerID: String, inSeat seat: Int) {
        let previousSeat = lobby.seat(of: playerID)
        guard playerNames.indices.contains(seat), let name = lobby.assign(playerID: playerID, toSeat: seat) else { return }
        // Moving a player clears the seat they left.
        if let previousSeat, previousSeat != seat {
            playerNames[previousSeat] = ""
        }
        playerNames[seat] = name
        publishToNearby()
    }

    /// A seat's name typed by hand. Typing over a nearby player — or clearing
    /// the seat — frees them for another seat.
    func setSeatName(_ seat: Int, _ name: String) {
        guard playerNames.indices.contains(seat) else { return }
        playerNames[seat] = name
        lobby.seatNameChanged(seat: seat, to: name)
        schedulePublish()
    }

    // MARK: - Live Activity Management

    private func startLiveActivity() {
        // End any stale activities first
        for activity in Activity<GameActivityAttributes>.activities {
            Task { await activity.end(nil, dismissalPolicy: .immediate) }
        }
        currentActivity = nil

        guard game != nil else { return }
        // Requesting while the user has Live Activities switched off throws
        // every time; check first so the log stays meaningful.
        guard ActivityAuthorizationInfo().areActivitiesEnabled else { return }

        let content = ActivityContent(state: buildActivityContentState(), staleDate: nil)
        do {
            currentActivity = try Activity.request(
                attributes: GameActivityAttributes(isFollowing: false),
                content: content,
                pushType: nil
            )
        } catch {
            logger.error("Failed to start Live Activity: \(error)")
        }
    }

    private func updateLiveActivity() {
        guard let activity = currentActivity, game != nil else { return }
        let content = ActivityContent(state: buildActivityContentState(), staleDate: nil)
        Task {
            await activity.update(content)
        }
    }

    private func endLiveActivity(showFinalState: Bool = false) {
        guard let activity = currentActivity else { return }

        let finalContent: ActivityContent<GameActivityAttributes.ContentState>?
        if showFinalState {
            finalContent = ActivityContent(state: buildActivityContentState(), staleDate: nil)
        } else {
            finalContent = nil
        }

        Task {
            await activity.end(
                finalContent,
                dismissalPolicy: showFinalState ? .after(.now + 300) : .immediate
            )
        }
        currentActivity = nil
    }

    private func buildActivityContentState() -> GameActivityAttributes.ContentState {
        GameActivityAttributes.ContentState(
            playerNames: players.map(\.name),
            scores: totals,
            currentRound: currentRoundNumber,
            isGameOver: isGameOver,
            leaderIndex: leaderIndex,
            elapsedSeconds: elapsedSeconds,
            startDate: isGameOver ? nil : gameStartDate,
            mySeat: localSeatIndex,
            advice: localSeatAdvice
        )
    }

    // MARK: - Scoring Engine

    /// - Parameter usedDeck: Only relevant when `deckWinEnabled` is true.
    ///   When true the winner drew from the deck, so the +100 penalty is suppressed for this round
    ///   regardless of the global `noPenaltyForDroppedCard` setting.
    func selectWinner(playerIndex: Int, winType: WinType, usedDeck: Bool = false) {
        guard var game else { return }
        guard let roundIndex = game.currentRoundIndex else { return }

        let winner = game.players[playerIndex]
        let penaltyPlayerIndex = (playerIndex + 1) % game.players.count
        let penaltyPlayerId = game.players[penaltyPlayerIndex].id

        var scores: [PlayerScore] = []

        for player in game.players {
            let isWinner = player.id == winner.id
            let baseScore = isWinner ? winType.winnerScore : winType.loserScore
            // Penalty is suppressed if the global no-penalty rule is on, OR if the winner used the deck this round
            let penaltyDisabled = noPenaltyForDroppedCard || usedDeck
            let hasPenalty = !penaltyDisabled && !isWinner && player.id == penaltyPlayerId
            let totalAutoScore = hasPenalty ? baseScore + 100 : baseScore

            scores.append(PlayerScore(
                playerId: player.id,
                autoScore: totalAutoScore,
                hasPenalty: hasPenalty,
                isWinner: isWinner
            ))
        }

        game.rounds[roundIndex].winnerId = winner.id
        game.rounds[roundIndex].winType = winType
        game.rounds[roundIndex].scores = scores
        self.game = game
        scoreEvent += 1

        // Update خباص tracking after scoring
        if let lastRound = lastCompletedRoundIndex {
            if let resolved = resolvedKhabasIndex(throughRound: lastRound) {
                currentKhabasIndex = resolved
            }
        }

        showWinnerPicker = false
        selectedRoundIndex = nil

        // Auto-save to history when game completes
        if self.game?.isGameOver == true {
            stopTimer()
            saveGameToHistory()
        }
        gameDidChange()
        if self.game?.isGameOver == true {
            endLiveActivity(showFinalState: true)
        }
    }

    // MARK: - Delete Round

    func confirmDeleteRound(_ roundIndex: Int) {
        roundToDelete = roundIndex
        showDeleteConfirmation = true
    }

    func deleteRound() {
        guard var game, let roundIndex = roundToDelete else {
            showDeleteConfirmation = false
            return
        }
        let stoppedClockAtFinish = game.isGameOver
        game.rounds[roundIndex].winnerId = nil
        game.rounds[roundIndex].winType = nil
        game.rounds[roundIndex].scores = []
        // Also clear any rounds after this one (they depend on cumulative)
        for i in (roundIndex + 1)..<game.rounds.count {
            if game.rounds[i].isCompleted {
                game.rounds[i].winnerId = nil
                game.rounds[i].winType = nil
                game.rounds[i].scores = []
            }
        }
        self.game = game

        // Recalculate خباص after deletion
        if let lastRound = lastCompletedRoundIndex {
            currentKhabasIndex = resolvedKhabasIndex(throughRound: lastRound)
        } else {
            currentKhabasIndex = nil
        }

        if stoppedClockAtFinish {
            // The board is playable again, so the clock picks up where it stopped.
            gameStartDate = Date().addingTimeInterval(-Double(elapsedSeconds))
            runTimer()
            startLiveActivity()
        }
        gameDidChange()
        showDeleteConfirmation = false
        roundToDelete = nil
    }

    // MARK: - Manual Override

    func openManualEntry(roundIndex: Int, playerIndex: Int) {
        guard let game, game.rounds[roundIndex].isCompleted else { return }
        manualEntryRoundIndex = roundIndex
        manualEntryPlayerIndex = playerIndex

        let playerId = game.players[playerIndex].id
        if let score = game.rounds[roundIndex].scores.first(where: { $0.playerId == playerId }) {
            manualEntryText = "\(score.effectiveScore)"
        }
        showManualEntry = true
    }

    func applyManualScore() {
        guard var game,
              let roundIndex = manualEntryRoundIndex,
              let playerIndex = manualEntryPlayerIndex,
              let value = Int(manualEntryText) else {
            showManualEntry = false
            return
        }

        let playerId = game.players[playerIndex].id
        if let scoreIndex = game.rounds[roundIndex].scores.firstIndex(where: { $0.playerId == playerId }) {
            game.rounds[roundIndex].scores[scoreIndex].manualScore = value
        }

        self.game = game
        gameDidChange()
        showManualEntry = false
        manualEntryRoundIndex = nil
        manualEntryPlayerIndex = nil
        manualEntryText = ""
    }

    func clearManualScore() {
        guard var game,
              let roundIndex = manualEntryRoundIndex,
              let playerIndex = manualEntryPlayerIndex else {
            showManualEntry = false
            return
        }

        let playerId = game.players[playerIndex].id
        if let scoreIndex = game.rounds[roundIndex].scores.firstIndex(where: { $0.playerId == playerId }) {
            game.rounds[roundIndex].scores[scoreIndex].manualScore = nil
        }

        self.game = game
        gameDidChange()
        showManualEntry = false
        manualEntryRoundIndex = nil
        manualEntryPlayerIndex = nil
        manualEntryText = ""
    }

    // MARK: - Tap Column

    /// Opens the winner picker with `playerIndex` already chosen.
    func tapColumn(playerIndex: Int) {
        openWinnerPicker(preselecting: playerIndex)
    }

    func openWinnerPicker(preselecting seat: Int? = nil) {
        guard let game, !game.isGameOver else { return }
        guard game.currentRoundIndex != nil else { return }
        selectedRoundIndex = game.currentRoundIndex
        winnerPickerSeat = seat
        showWinnerPicker = true
    }

    // MARK: - Table

    /// What each seat scored in the most recent round.
    var lastRoundScores: [Int]? {
        guard let roundIndex = lastCompletedRoundIndex else { return nil }
        return players.indices.map { score(roundIndex: roundIndex, playerIndex: $0)?.effectiveScore ?? 0 }
    }

    /// Each seat's running total: zero before round 1, then after every
    /// round played — the score chart's lines.
    var scoreSeries: [[Int]] {
        let played = (lastCompletedRoundIndex ?? -1) + 1
        return players.indices.map { seat in
            [0] + (0..<played).map { cumulativeScore(throughRound: $0, playerIndex: seat) }
        }
    }

    /// The nine rounds as cards for the table.
    var roundCards: [RoundCard] {
        guard let game else { return [] }
        return game.rounds.indices.map { index in
            let round = game.rounds[index]
            if round.isCompleted {
                let winner = round.winnerId.flatMap { id in game.players.firstIndex { $0.id == id } }
                return RoundCard(id: index, state: .played(winner: winner, label: round.winType?.rawValue))
            }
            return RoundCard(id: index, state: index == game.currentRoundIndex ? .current : .upcoming)
        }
    }

    // MARK: - Helpers

    func score(roundIndex: Int, playerIndex: Int) -> PlayerScore? {
        guard let game else { return nil }
        let playerId = game.players[playerIndex].id
        return game.rounds[roundIndex].scores.first { $0.playerId == playerId }
    }

    func totalScore(playerIndex: Int) -> Int {
        guard let game else { return 0 }
        return game.totalScore(for: game.players[playerIndex].id)
    }

    // MARK: - Prediction Engine

    func computePredictions() -> [PlayerPrediction] {
        guard let game, let currentIdx = game.currentRoundIndex else { return [] }
        return PredictionEngine.predictions(
            names: game.players.map(\.name),
            totals: totals,
            remainingRounds: game.maxRounds - currentIdx
        )
    }

    func predictionLabel(roundIndex: Int, playerIndex: Int) -> String? {
        guard predictionsActive else { return nil }
        guard let game else { return nil }
        guard let currentIdx = game.currentRoundIndex, roundIndex >= currentIdx else { return nil }

        let predictions = computePredictions()
        if let pred = predictions.first(where: { $0.playerIndex == playerIndex }),
           let plan = pred.roundPlan {
            // roundIndex relative to current round gives the plan index
            let planIndex = roundIndex - currentIdx
            if planIndex >= 0 && planIndex < plan.count {
                return plan[planIndex].rawValue
            }
        }
        return nil
    }

    // MARK: - Save to History

    private func saveGameToHistory() {
        guard let game, game.isGameOver else { return }

        let names = game.players.map { $0.name }
        let scores = game.players.map { player in
            game.totalScore(for: player.id)
        }

        let winnerIdx = scores.enumerated().min(by: { $0.element < $1.element })?.offset ?? 0

        let roundResults = game.rounds.compactMap { round -> GameRecord.RoundResult? in
            guard round.isCompleted,
                  let winnerId = round.winnerId,
                  let winType = round.winType,
                  let winner = game.players.first(where: { $0.id == winnerId }) else {
                return nil
            }
            let roundScores = game.players.map { player in
                round.scores.first(where: { $0.playerId == player.id })?.effectiveScore ?? 0
            }
            return GameRecord.RoundResult(
                roundNumber: round.roundNumber,
                winnerName: winner.name,
                winType: winType.rawValue,
                scores: roundScores
            )
        }

        let record = GameRecord(
            id: UUID(),
            date: gameStartDate ?? Date(),
            duration: elapsedSeconds,
            playerNames: names,
            finalScores: scores,
            winnerName: names[winnerIdx],
            roundResults: roundResults
        )

        historyManager.save(record)
    }

    // MARK: - Pause / Resume

    /// Whether there is a paused game that can be resumed.
    var hasPausedGame: Bool { pausedGame != nil }

    /// Stored game state for resume.
    private(set) var pausedGame: Game?
    private(set) var pausedElapsed: Int = 0
    private var pausedKhabasIndex: Int?
    private var pausedLocalSeat: Int?

    /// Go back to start page without losing the current game.
    func pauseGame() {
        guard let game else { return }
        pausedGame = game
        pausedElapsed = elapsedSeconds
        pausedKhabasIndex = currentKhabasIndex
        pausedLocalSeat = localSeatIndex
        self.game = nil
        predictionsActive = false
        stopTimer()
        endLiveActivity()
        clearWidgetState()
        persistSession()
        publishToNearby()
    }

    /// Resume a previously paused game.
    func resumeGame() {
        guard let paused = pausedGame else { return }
        game = paused
        pausedGame = nil
        currentKhabasIndex = pausedKhabasIndex
        pausedKhabasIndex = nil
        localSeatIndex = pausedLocalSeat ?? PlayerIdentity.seat(in: paused.players.map(\.name))
        pausedLocalSeat = nil
        // Restore timer from where it left off
        gameStartDate = Date().addingTimeInterval(-Double(pausedElapsed))
        elapsedSeconds = pausedElapsed
        pausedElapsed = 0
        if !paused.isGameOver {
            runTimer()
            startLiveActivity()
        }
        if nearbyHost.isEnabled {
            nearbyHost.start()
        }
        gameDidChange()
    }

    // MARK: - Persistence

    /// Saves the board so it survives the app being closed — call when the
    /// app leaves the foreground too, to keep the clock current.
    func persistSession() {
        if let game, !game.isGameOver {
            sessionStore.save(SavedSession(
                game: game,
                elapsedSeconds: elapsedSeconds,
                khabasIndex: currentKhabasIndex,
                localSeat: localSeatIndex,
                owners: lobby.owners
            ))
        } else if game == nil, let pausedGame {
            sessionStore.save(SavedSession(
                game: pausedGame,
                elapsedSeconds: pausedElapsed,
                khabasIndex: pausedKhabasIndex,
                localSeat: pausedLocalSeat,
                owners: lobby.owners
            ))
        } else {
            // Finished games live in history; nothing to resume.
            sessionStore.save(nil)
        }
    }

    /// A game left unfinished last time comes back as a paused board.
    private func restoreSavedSession() {
        guard let saved = sessionStore.load(), !saved.game.isGameOver else { return }
        pausedGame = saved.game
        pausedElapsed = saved.elapsedSeconds
        pausedKhabasIndex = saved.khabasIndex
        pausedLocalSeat = saved.localSeat
        playerNames = saved.game.players.map(\.name)
        if let owners = saved.owners {
            lobby.restore(owners: owners, names: playerNames)
        }
    }

    // MARK: - Reset

    func resetGame() {
        game = nil
        pausedGame = nil
        playerNames = ["", "", "", ""]
        predictionsActive = false
        currentKhabasIndex = nil
        localSeatIndex = nil
        for seat in playerNames.indices {
            lobby.release(seat: seat)
        }
        stopTimer()
        endLiveActivity()
        clearWidgetState()
        sessionStore.save(nil)
        publishToNearby()
    }

    /// Rematch: same seats, fresh board, clock from zero.
    func restartGame() {
        guard let game else { return }
        self.playerNames = game.players.map(\.name)
        self.game = nil
        predictionsActive = false
        endLiveActivity()
        startGame()
    }

    /// Back to the table with the same names filled in, to reseat or rename
    /// before the next game. The finished board is already in history.
    func newGame() {
        guard let game else { return }
        playerNames = game.players.map(\.name)
        self.game = nil
        pausedGame = nil
        predictionsActive = false
        currentKhabasIndex = nil
        stopTimer()
        endLiveActivity()
        clearWidgetState()
        sessionStore.save(nil)
        // Seats and their owners carry over; nearby phones go back to the lobby.
        publishToNearby()
    }
}
