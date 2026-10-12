import Foundation
import Testing
@testable import Rummy_Calculator

/// The planner behind the predictions sheet and the lock-screen advice.
///
/// Swings per win: عادي 260, كلر 520, زاته 1040, زاته + جوكر 2080.
@MainActor
@Suite("Prediction engine")
struct PredictionEngineTests {

    private func swing(_ plan: [WinType]) -> Int {
        plan.reduce(0) { $0 + $1.swing }
    }

    @Test("A small gap needs one plain win, not every round left")
    func smallGapNeedsOneWin() throws {
        let result = try #require(PredictionEngine.plan(gap: 100, remainingRounds: 3))
        #expect(result.plan == [.normal])
        #expect(!result.isTie)
    }

    @Test("Matching the gap only draws level, so the plan goes one win further")
    func equalSwingIsNotALead() throws {
        // 260 closes a 260 gap exactly — a tie — so leading takes two wins.
        let result = try #require(PredictionEngine.plan(gap: 260, remainingRounds: 3))
        #expect(result.plan == [.normal, .normal])
        #expect(!result.isTie)
    }

    @Test("When three plain wins only tie, one is upgraded to take the lead")
    func upgradesInsteadOfSettlingForATie() throws {
        let result = try #require(PredictionEngine.plan(gap: 780, remainingRounds: 3))
        #expect(!result.isTie)
        #expect(result.plan.count == 3)
        #expect(swing(result.plan) > 780)
        #expect(result.plan.filter { $0 == .normal }.count == 2, "upgrade as little as possible")
    }

    @Test("A gap the best possible round matches exactly is reported as a tie")
    func exactMaximumIsATie() throws {
        let result = try #require(PredictionEngine.plan(gap: 2080, remainingRounds: 1))
        #expect(result.isTie)
        #expect(result.plan == [.zataJoker])
    }

    @Test("A gap beyond the best possible rounds has no plan")
    func beyondReach() {
        #expect(PredictionEngine.plan(gap: 2081, remainingRounds: 1) == nil)
        #expect(PredictionEngine.plan(gap: 100, remainingRounds: 0) == nil)
    }

    @Test("زاته + جوكر is only reached for when nothing else will do")
    func zataJokerIsALastResort() throws {
        // Three rounds of زاته swing 3120; a 3000 gap needs no زاته + جوكر.
        let result = try #require(PredictionEngine.plan(gap: 3000, remainingRounds: 3))
        #expect(!result.plan.contains(.zataJoker))
        #expect(swing(result.plan) > 3000)
    }

    @Test("A seat level with the leader is told one win takes it outright")
    func levelWithTheLeader() throws {
        let predictions = PredictionEngine.predictions(
            names: ["A", "B", "C", "D"],
            totals: [100, 100, 300, 400],
            remainingRounds: 3
        )
        let level = try #require(predictions.first { $0.playerIndex == 1 })
        #expect(level.gap == 0)
        #expect(level.roundPlan == [.normal])
        #expect(!level.resultIsTie)
    }

    // MARK: Advice

    @Test("Before round 7 the advice is standing only")
    func noPlanBeforeRoundSeven() throws {
        let advice = try #require(PredictionEngine.advice(
            forSeat: 2, totals: [0, 200, 400, 600], currentRound: 6, maxRounds: 9, isGameOver: false
        ))
        #expect(advice.kind == .behind)
        #expect(advice.rank == 3)
        #expect(advice.gap == 400)
        #expect(advice.needs.isEmpty)
    }

    @Test("From round 7 a trailing seat is told which wins take the lead")
    func planFromRoundSeven() throws {
        let advice = try #require(PredictionEngine.advice(
            forSeat: 3, totals: [-120, 300, 500, 600], currentRound: 7, maxRounds: 9, isGameOver: false
        ))
        #expect(advice.kind == .overtake)
        #expect(advice.rank == 4)
        #expect(advice.roundsLeft == 3)
        #expect(advice.gap == 720)
        // 720 behind: two plain wins swing 520, three swing 780.
        #expect(advice.needs == [SeatAdvice.Need(label: WinType.normal.rawValue, count: 3)])
        #expect(advice.needsSummary == "عادي ×3")
    }

    @Test("The leader is told their margin over the runner-up")
    func leaderAdvice() throws {
        let advice = try #require(PredictionEngine.advice(
            forSeat: 0, totals: [-120, 300, 500, 600], currentRound: 8, maxRounds: 9, isGameOver: false
        ))
        #expect(advice.kind == .leading)
        #expect(advice.rank == 1)
        #expect(advice.gap == 420)
    }

    @Test("A hopeless gap is called out rather than given an impossible plan")
    func outOfReachAdvice() throws {
        let advice = try #require(PredictionEngine.advice(
            forSeat: 1, totals: [0, 5000, 200, 200], currentRound: 9, maxRounds: 9, isGameOver: false
        ))
        #expect(advice.kind == .outOfReach)
        #expect(!advice.hasPlan)
    }

    @Test("After the last round the advice is the final placing")
    func finishedAdvice() throws {
        let advice = try #require(PredictionEngine.advice(
            forSeat: 2, totals: [0, 200, 400, 600], currentRound: 9, maxRounds: 9, isGameOver: true
        ))
        #expect(advice.kind == .finished)
        #expect(advice.rank == 3)
        #expect(advice.roundsLeft == 0)
    }

    @Test("Advice needs list the strongest win type first")
    func needsAreStrongestFirst() {
        let needs = PredictionEngine.needs(for: [.normal, .color, .zata, .normal])
        #expect(needs.map(\.label) == [WinType.zata.rawValue, WinType.color.rawValue, WinType.normal.rawValue])
        #expect(needs.last?.count == 2)
    }
}

// MARK: - Nearby

@MainActor
@Suite("Nearby sharing")
struct NearbySharingTests {

    private func snapshot(
        names: [String],
        owners: [String?] = ["a1b2c3d4", nil, "0badf00d", nil],
        lobby: [LobbyPlayer]? = nil
    ) -> TableSnapshot {
        let lobby = lobby ?? [LobbyPlayer(id: "a1b2c3d4", name: "خالد"), LobbyPlayer(id: "feedface", name: "نايف")]
        return TableSnapshot(
            hostID: UUID(),
            gameID: UUID(),
            names: names,
            totals: [-120, 300, 1_440, 600],
            round: 7,
            maxRounds: 9,
            isOver: false,
            dealer: 2,
            startedAt: Date(timeIntervalSince1970: 1_760_000_000),
            elapsed: 1954,
            lastWinner: 0,
            lastWinType: WinType.color.rawValue,
            owners: owners,
            lobby: lobby
        )
    }

    @Test("A board survives the trip over Bluetooth")
    func snapshotRoundTrip() throws {
        let original = snapshot(names: ["خالد", "حمد", "علي", "سعود"])
        let data = try #require(original.encoded())
        #expect(data.count <= NearbyService.maxValueLength)
        let decoded = try #require(TableSnapshot.decode(data))
        #expect(decoded == original)
        #expect(decoded.leaderIndex == 0)
    }

    @Test("Long names are trimmed so the board still fits one attribute")
    func longNamesAreTrimmed() throws {
        let long = String(repeating: "عبدالرحمن", count: 6)
        let data = try #require(snapshot(names: [long, long, long, long]).encoded())
        #expect(data.count <= NearbyService.maxValueLength)
        let decoded = try #require(TableSnapshot.decode(data))
        #expect(decoded.names.allSatisfy { $0.count < long.count && long.hasPrefix($0) })
    }

    @Test("Four long Arabic seat names and four long lobby names still fit, owners intact")
    func fullLobbyOfLongNamesFits() throws {
        let long = String(repeating: "عبدالرحمن", count: 3)
        let ids = ["a1b2c3d4", "0badf00d", "feedface", "c0ffee00"]
        let original = snapshot(
            names: [long, long, long, long],
            owners: ids.map { Optional($0) },
            lobby: ids.map { LobbyPlayer(id: $0, name: long) }
        )
        let data = try #require(original.encoded())
        #expect(data.count <= NearbyService.maxValueLength)

        let decoded = try #require(TableSnapshot.decode(data))
        #expect(decoded.owners == original.owners, "seat owners must never be trimmed")
        #expect(decoded.lobby.map(\.id) == ids, "every connected player is still listed")
        #expect(decoded.names.allSatisfy { !$0.isEmpty && long.hasPrefix($0) })
        #expect(decoded.linkedSeats == [0, 1, 2, 3])
    }

    @Test("A lobby snapshot carries no game, and the seats so far")
    func lobbyRoundTrip() throws {
        var lobby = snapshot(names: ["خالد", "", "علي", ""], owners: ["a1b2c3d4", nil, nil, nil])
        lobby.gameID = nil
        lobby.totals = [0, 0, 0, 0]
        let data = try #require(lobby.encoded())
        let decoded = try #require(TableSnapshot.decode(data))
        #expect(decoded.isLobby)
        #expect(decoded.leaderIndex == nil, "nobody leads before the game")
        #expect(decoded.names == ["خالد", "", "علي", ""])
        #expect(decoded == lobby)
    }

    @Test("A guest finds its seat from the owners list")
    func guestFindsItsSeat() {
        let board = snapshot(names: ["خالد", "حمد", "علي", "سعود"])
        #expect(board.seat(ofPlayer: "0badf00d") == 2)
        #expect(board.seat(ofPlayer: "feedface") == nil)
        #expect(board.knows(playerID: "feedface"), "in the lobby, waiting for a seat")
        #expect(!board.knows(playerID: "deadbeef"))
        #expect(board.linkedSeats == [0], "seat 2's owner is not connected")
    }

    @Test("A version-1 board from an older host still decodes, with no owners")
    func versionOneDecodes() throws {
        let v1 = #"{"v":1,"h":"3F2504E0-4F89-11D3-9A0C-0305E82C3301","g":"6BA7B810-9DAD-11D1-80B4-00C04FD430C8","n":["A","B","C","D"],"t":[-60,300,200,200],"r":2,"m":9,"o":false,"d":1,"e":42,"w":0,"wt":"عادي","l":[2]}"#
        let decoded = try #require(TableSnapshot.decode(Data(v1.utf8)))
        #expect(decoded.version == 1)
        #expect(!decoded.isLobby)
        #expect(decoded.owners == [nil, nil, nil, nil])
        #expect(decoded.lobby.isEmpty)
        #expect(decoded.totals == [-60, 300, 200, 200])
    }

    @Test("A snapshot with a mismatched owners list is rejected")
    func malformedOwnersAreRejected() throws {
        let bad = snapshot(names: ["A", "B", "C", "D"], owners: ["a1b2c3d4"])
        let data = try #require(bad.encoded())
        #expect(TableSnapshot.decode(data) == nil)
    }

    @Test("A profile is trimmed to 24 characters and survives the trip")
    func profileRoundTrip() throws {
        let long = String(repeating: "س", count: 40)
        let player = LobbyPlayer(id: "a1b2c3d4", name: "  \(long)  ")
        #expect(player.name.count == LobbyPlayer.maxNameLength)
        let data = try #require(player.encoded())
        let decoded = try #require(LobbyPlayer.decode(data))
        #expect(decoded == player)
        #expect(LobbyPlayer.decode(Data(#"{"i":"","n":"x"}"#.utf8)) == nil, "a profile needs an ID")
    }

    @Test("Each install's player ID is 8 hex characters and stays the same")
    func playerIDIsStable() {
        let id = PlayerIdentity.playerID
        #expect(id.count == 8)
        #expect(id.allSatisfy { $0.isHexDigit })
        #expect(PlayerIdentity.playerID == id)
        #expect(PlayerIdentity.makePlayerID().count == 8)
    }

    @Test("A board from a newer version of the app is ignored")
    func futureVersionIsRejected() throws {
        var future = snapshot(names: ["A", "B", "C", "D"])
        future.version = TableSnapshot.currentVersion + 1
        let data = try #require(future.encoded())
        #expect(TableSnapshot.decode(data) == nil)
    }

    @Test("The scorekeeper's board carries totals, round and the last winner")
    func viewModelSnapshot() throws {
        let viewModel = GameViewModel(sessionStore: .ephemeral)
        viewModel.playerNames = ["Khalid", "Hamad", "Ali", "Saud"]
        viewModel.startGame()
        viewModel.stopTimer()
        viewModel.selectWinner(playerIndex: 2, winType: .color)

        let board = try #require(viewModel.tableSnapshot)
        #expect(board.names == ["Khalid", "Hamad", "Ali", "Saud"])
        #expect(board.totals == viewModel.totals)
        #expect(board.round == 2)
        #expect(board.lastWinner == 2)
        #expect(board.lastWinType == WinType.color.rawValue)
        #expect(board.hostID == NearbyHost.hostID)
    }

    @Test("A player is recognised at the table by their saved name")
    func identityByName() {
        let saved = PlayerIdentity.preferredName
        defer { PlayerIdentity.preferredName = saved }

        PlayerIdentity.preferredName = "  ali "
        #expect(PlayerIdentity.seat(in: ["Khalid", "Hamad", "Ali", "Saud"]) == 2)
        PlayerIdentity.preferredName = "Nobody"
        #expect(PlayerIdentity.seat(in: ["Khalid", "Hamad", "Ali", "Saud"]) == nil)
    }

    @Test("This phone's seat is picked up when a game starts, and drives its advice")
    func localSeatFromIdentity() {
        let saved = PlayerIdentity.preferredName
        defer { PlayerIdentity.preferredName = saved }
        PlayerIdentity.preferredName = "Saud"

        let viewModel = GameViewModel(sessionStore: .ephemeral)
        viewModel.playerNames = ["Khalid", "Hamad", "Ali", "Saud"]
        viewModel.startGame()
        viewModel.stopTimer()
        #expect(viewModel.localSeatIndex == 3)

        for _ in 0..<6 { viewModel.selectWinner(playerIndex: 0, winType: .normal) }
        #expect(viewModel.localSeatAdvice?.kind == .overtake)
    }
}

// MARK: - Seat resolution

@MainActor
@Suite("Finding my seat")
struct SeatResolverTests {

    private func board(names: [String], owners: [String?]) -> TableSnapshot {
        TableSnapshot(
            hostID: UUID(), gameID: UUID(), names: names, totals: [0, 0, 0, 0],
            round: 1, maxRounds: 9, isOver: false, dealer: nil, startedAt: nil, elapsed: 0,
            lastWinner: nil, lastWinType: nil, owners: owners, lobby: []
        )
    }

    private let names = ["Khalid", "Hamad", "Ali", "Saud"]
    private func byName(_ wanted: String) -> ([String]) -> Int? {
        { $0.firstIndex(of: wanted) }
    }

    @Test("The host's assignment wins over a seat the player tapped")
    func hostAssignmentWins() {
        var resolver = SeatResolver(seat: 0, fromHost: false)
        resolver.update(with: board(names: names, owners: [nil, nil, "me", nil]), previousNames: names, playerID: "me", name: byName("Khalid"))
        #expect(resolver.seat == 2)
        #expect(resolver.fromHost)
    }

    @Test("Losing the host's seat falls back to the name, if typed")
    func unseatedFallsBackToName() {
        var resolver = SeatResolver(seat: 2, fromHost: true)
        resolver.update(with: board(names: names, owners: [nil, nil, nil, nil]), previousNames: names, playerID: "me", name: byName("Saud"))
        #expect(resolver.seat == 3)
        #expect(!resolver.fromHost)
    }

    @Test("A tapped seat stays while the names do not change")
    func manualSeatIsKept() {
        var resolver = SeatResolver(seat: 1, fromHost: false)
        resolver.update(with: board(names: names, owners: [nil, nil, nil, nil]), previousNames: names, playerID: "me", name: byName("Nobody"))
        #expect(resolver.seat == 1)
    }

    @Test("A reseated table is matched by name")
    func renamedTableMatchesByName() {
        var resolver = SeatResolver(seat: 1, fromHost: false)
        let reseated = ["Saud", "Ali", "Hamad", "Khalid"]
        resolver.update(with: board(names: reseated, owners: [nil, nil, nil, nil]), previousNames: names, playerID: "me", name: byName("Khalid"))
        #expect(resolver.seat == 3)
    }

    @Test("The first board is matched by name when there is no assignment")
    func firstBoardMatchesByName() {
        var resolver = SeatResolver(seat: nil, fromHost: false)
        resolver.update(with: board(names: names, owners: [nil, nil, nil, nil]), previousNames: nil, playerID: "me", name: byName("Ali"))
        #expect(resolver.seat == 2)
    }
}

// MARK: - Lobby rules

@MainActor
@Suite("Table lobby")
struct TableLobbyTests {

    private let khalid = LobbyPlayer(id: "aaaaaaa1", name: "Khalid")
    private let hamad = LobbyPlayer(id: "aaaaaaa2", name: "Hamad")
    private let otherKhalid = LobbyPlayer(id: "aaaaaaa3", name: "khalid")

    @Test("Seating a player takes them out of the available list")
    func assignRemovesFromAvailable() {
        var lobby = TableLobby()
        lobby.join(khalid)
        lobby.join(hamad)
        #expect(lobby.available.map(\.id) == [khalid.id, hamad.id])

        #expect(lobby.assign(playerID: khalid.id, toSeat: 2) == "Khalid")
        #expect(lobby.owners == [nil, nil, khalid.id, nil])
        #expect(lobby.available.map(\.id) == [hamad.id])
        #expect(lobby.seat(of: khalid.id) == 2)
    }

    @Test("Seating a player elsewhere moves them, and frees whoever held that seat")
    func reassignMoves() {
        var lobby = TableLobby()
        lobby.join(khalid)
        lobby.join(hamad)
        lobby.assign(playerID: khalid.id, toSeat: 0)
        lobby.assign(playerID: khalid.id, toSeat: 3)
        #expect(lobby.owners == [nil, nil, nil, khalid.id])

        lobby.assign(playerID: hamad.id, toSeat: 3)
        #expect(lobby.owners == [nil, nil, nil, hamad.id])
        #expect(lobby.available.map(\.id) == [khalid.id])
    }

    @Test("Clearing the seat or typing another name frees the player")
    func editingTheSeatUnassigns() {
        var lobby = TableLobby()
        lobby.join(khalid)
        lobby.assign(playerID: khalid.id, toSeat: 1)

        lobby.seatNameChanged(seat: 1, to: " Khalid ")
        #expect(lobby.seat(of: khalid.id) == 1, "the same name, give or take spaces, keeps the seat")

        lobby.seatNameChanged(seat: 1, to: "Khali")
        #expect(lobby.seat(of: khalid.id) == nil)
        #expect(lobby.available.map(\.id) == [khalid.id])

        lobby.assign(playerID: khalid.id, toSeat: 1)
        lobby.seatNameChanged(seat: 1, to: "")
        #expect(lobby.seat(of: khalid.id) == nil)
    }

    @Test("A disconnect drops the player from the available list but keeps their seat")
    func disconnectKeepsTheSeat() {
        var lobby = TableLobby()
        lobby.join(khalid)
        lobby.join(hamad)
        lobby.assign(playerID: khalid.id, toSeat: 0)

        lobby.leave(playerID: khalid.id)
        lobby.leave(playerID: hamad.id)
        #expect(lobby.available.isEmpty)
        #expect(lobby.owners[0] == khalid.id)
        #expect(lobby.linkedSeats.isEmpty, "no link while their phone is away")
        #expect(lobby.displayName(for: khalid.id) == "Khalid")

        lobby.join(khalid)
        #expect(lobby.linkedSeats == [0], "reconnecting relinks the seat")
        #expect(lobby.available.isEmpty, "still seated, so not available")
    }

    @Test("A duplicate name gets a suffix; the first to join keeps it as is")
    func duplicateNamesAreDisambiguated() {
        var lobby = TableLobby()
        lobby.join(khalid)
        lobby.join(otherKhalid)
        #expect(lobby.available.map(\.name) == ["Khalid", "khalid 2"])
        #expect(lobby.assign(playerID: otherKhalid.id, toSeat: 0) == "khalid 2")

        // The suffix holds after the first Khalid leaves, so seat names never shift.
        lobby.leave(playerID: khalid.id)
        #expect(lobby.displayName(for: otherKhalid.id) == "khalid 2")
    }

    @Test("A suffixed long name still fits the 24-character limit")
    func longDuplicateNameFits() {
        var lobby = TableLobby()
        let long = String(repeating: "ع", count: 24)
        lobby.join(LobbyPlayer(id: "1", name: long))
        lobby.join(LobbyPlayer(id: "2", name: long))
        let second = lobby.displayName(for: "2")
        #expect(second.count <= LobbyPlayer.maxNameLength)
        #expect(second.hasSuffix(" 2"))
    }

    @Test("Seat owners saved with a game come back without their phones")
    func restoreKeepsOwners() {
        var lobby = TableLobby()
        lobby.restore(owners: [nil, "aaaaaaa2", nil, nil], names: ["P1", "Hamad", "P3", "P4"])
        #expect(lobby.owners == [nil, "aaaaaaa2", nil, nil])
        #expect(lobby.available.isEmpty)
        #expect(lobby.displayName(for: "aaaaaaa2") == "Hamad")

        lobby.join(hamad)
        #expect(lobby.linkedSeats == [1])
    }
}

// MARK: - Lobby, end to end

@MainActor
@Suite("Lobby on the start page")
struct LobbyFlowTests {

    private let nayef = LobbyPlayer(id: "bbbbbbb1", name: "نايف")
    private let fahad = LobbyPlayer(id: "bbbbbbb2", name: "فهد")

    /// Stands in for a phone introducing itself over Bluetooth.
    private func join(_ player: LobbyPlayer, to viewModel: GameViewModel) {
        viewModel.nearbyHost.onPlayerJoined?(player)
    }

    /// Starting a game saves its names as presets; take ours back out so the
    /// test host's saved names are left as they were.
    private func forgetPresets(_ viewModel: GameViewModel) {
        for name in [nayef.name, fahad.name] {
            viewModel.presetNames.removeName(name)
        }
    }

    @Test("Seating a nearby player writes their name and links the seat")
    func seatingANearbyPlayer() {
        let viewModel = GameViewModel(sessionStore: .ephemeral)
        join(nayef, to: viewModel)
        join(fahad, to: viewModel)
        #expect(viewModel.availablePlayers.map(\.id) == [nayef.id, fahad.id])

        viewModel.seatPlayer(nayef.id, inSeat: 1)
        #expect(viewModel.playerNames[1] == "نايف")
        #expect(viewModel.availablePlayers.map(\.id) == [fahad.id])
        #expect(viewModel.linkedSeats == [1])

        let lobby = try! #require(viewModel.tableSnapshot)
        #expect(lobby.isLobby)
        #expect(lobby.seat(ofPlayer: nayef.id) == 1)
        #expect(lobby.totals == [0, 0, 0, 0])
        #expect(Set(lobby.lobby.map(\.id)) == [nayef.id, fahad.id])
    }

    @Test("Typing over a seated player frees them; typed names work as before")
    func typingOverASeat() {
        let viewModel = GameViewModel(sessionStore: .ephemeral)
        join(nayef, to: viewModel)
        viewModel.seatPlayer(nayef.id, inSeat: 0)

        viewModel.setSeatName(0, "Saad")
        #expect(viewModel.playerNames[0] == "Saad")
        #expect(viewModel.availablePlayers.map(\.id) == [nayef.id])
        #expect(viewModel.tableSnapshot?.owners == [nil, nil, nil, nil])
    }

    @Test("Moving a player to another seat clears the seat they left")
    func movingAPlayerClearsTheOldSeat() {
        let viewModel = GameViewModel(sessionStore: .ephemeral)
        join(nayef, to: viewModel)
        viewModel.seatPlayer(nayef.id, inSeat: 0)
        viewModel.seatPlayer(nayef.id, inSeat: 3)
        #expect(viewModel.playerNames == ["", "", "", "نايف"])
    }

    @Test("Starting the game sends every seated player their seat, and a rematch keeps it")
    func startCarriesOwners() throws {
        let viewModel = GameViewModel(sessionStore: .ephemeral)
        join(nayef, to: viewModel)
        join(fahad, to: viewModel)
        viewModel.seatPlayer(nayef.id, inSeat: 0)
        viewModel.seatPlayer(fahad.id, inSeat: 2)
        viewModel.setSeatName(1, "Ali")
        viewModel.startGame()
        viewModel.stopTimer()
        defer { forgetPresets(viewModel) }

        let board = try #require(viewModel.tableSnapshot)
        #expect(!board.isLobby)
        #expect(board.names == ["نايف", "Ali", "فهد", "P4"])
        #expect(board.seat(ofPlayer: nayef.id) == 0)
        #expect(board.seat(ofPlayer: fahad.id) == 2)

        viewModel.restartGame()
        viewModel.stopTimer()
        let rematch = try #require(viewModel.tableSnapshot)
        #expect(rematch.gameID != board.gameID)
        #expect(rematch.owners == board.owners)

        for _ in 0..<9 { viewModel.selectWinner(playerIndex: 1, winType: .normal) }
        viewModel.historyManager.deleteGame(at: IndexSet(integer: 0))
        viewModel.newGame()
        let backInLobby = try #require(viewModel.tableSnapshot)
        #expect(backInLobby.isLobby)
        #expect(backInLobby.owners == board.owners)
    }

    @Test("A player who leaves before the start keeps their name in the seat")
    func leavingBeforeTheStart() {
        let viewModel = GameViewModel(sessionStore: .ephemeral)
        join(nayef, to: viewModel)
        viewModel.seatPlayer(nayef.id, inSeat: 2)

        viewModel.nearbyHost.onPlayerLeft?(nayef.id)
        #expect(viewModel.playerNames[2] == "نايف")
        #expect(viewModel.linkedSeats.isEmpty)
        #expect(viewModel.tableSnapshot?.seat(ofPlayer: nayef.id) == 2)

        join(nayef, to: viewModel)
        #expect(viewModel.linkedSeats == [2])
    }

    @Test("Seat owners survive the app being closed mid-game")
    func ownersArePersisted() {
        let suite = "rummy-tests-lobbyOwners"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        let store = GameSessionStore(defaults: defaults)

        let first = GameViewModel(sessionStore: store)
        join(nayef, to: first)
        first.seatPlayer(nayef.id, inSeat: 1)
        first.startGame()
        first.stopTimer()
        defer { forgetPresets(first) }
        first.selectWinner(playerIndex: 0, winType: .normal)

        let relaunched = GameViewModel(sessionStore: store)
        relaunched.resumeGame()
        relaunched.stopTimer()
        #expect(relaunched.tableSnapshot?.seat(ofPlayer: nayef.id) == 1)
        #expect(relaunched.availablePlayers.isEmpty, "not connected until their phone returns")
    }
}

// MARK: - Saved sessions

@MainActor
@Suite("Saved sessions")
struct SavedSessionTests {

    /// A private defaults suite per test, emptied afterwards. Named after the
    /// test rather than a fresh UUID so repeated runs reuse the same files.
    private func store(_ name: String = #function) -> (GameSessionStore, UserDefaults, String) {
        let suite = "rummy-tests-\(name.filter(\.isLetter))"
        let defaults = UserDefaults(suiteName: suite)!
        return (GameSessionStore(defaults: defaults), defaults, suite)
    }

    @Test("An unfinished game comes back as a paused board after a relaunch")
    func unfinishedGameIsRestored() throws {
        let (store, defaults, suite) = store()
        defer { defaults.removePersistentDomain(forName: suite) }

        let first = GameViewModel(sessionStore: store)
        first.playerNames = ["Khalid", "Hamad", "Ali", "Saud"]
        first.startGame()
        first.stopTimer()
        first.selectWinner(playerIndex: 1, winType: .zata)
        first.selectWinner(playerIndex: 3, winType: .normal)
        let totals = first.totals

        let relaunched = GameViewModel(sessionStore: store)
        #expect(!relaunched.isGameStarted)
        #expect(relaunched.hasPausedGame)
        #expect(relaunched.playerNames == ["Khalid", "Hamad", "Ali", "Saud"])

        relaunched.resumeGame()
        relaunched.stopTimer()
        #expect(relaunched.totals == totals)
        #expect(relaunched.currentRoundNumber == 3)
    }

    @Test("A finished game is not offered for resuming")
    func finishedGameIsNotRestored() {
        let (store, defaults, suite) = store()
        defer { defaults.removePersistentDomain(forName: suite) }

        let first = GameViewModel(sessionStore: store)
        first.playerNames = ["Khalid", "Hamad", "Ali", "Saud"]
        first.startGame()
        for _ in 0..<9 { first.selectWinner(playerIndex: 0, winType: .normal) }
        #expect(first.isGameOver)
        first.historyManager.deleteGame(at: IndexSet(integer: 0))

        #expect(store.load() == nil)
        #expect(!GameViewModel(sessionStore: store).hasPausedGame)
    }

    @Test("Resetting forgets the saved game")
    func resetForgets() {
        let (store, defaults, suite) = store()
        defer { defaults.removePersistentDomain(forName: suite) }

        let viewModel = GameViewModel(sessionStore: store)
        viewModel.playerNames = ["Khalid", "Hamad", "Ali", "Saud"]
        viewModel.startGame()
        viewModel.selectWinner(playerIndex: 0, winType: .normal)
        #expect(store.load() != nil)

        viewModel.resetGame()
        #expect(store.load() == nil)
    }
}
