import CoreBluetooth
import Foundation

// MARK: - Bluetooth service

/// The GATT service the scorekeeper's phone publishes for players at the table.
///
/// - `revision` notifies a counter each time the board changes, so followers
///   wake (even when locked) and fetch the new board.
/// - `snapshot` is read on demand; it can exceed one notification packet, and
///   a read is reassembled by Core Bluetooth up to the 512-byte attribute limit.
/// - `profile` is written by a follower to introduce itself — player ID and
///   name — so the host can seat it.
enum NearbyService {
    static let service = CBUUID(string: "DC0C6F67-0532-4686-BC39-E9065A6471F4")
    static let revision = CBUUID(string: "DB95881D-4533-42F7-9539-FB5681F3C1E4")
    static let snapshot = CBUUID(string: "FEB354DA-5F4D-48A6-9D0E-D8D3D35222D6")
    static let profile = CBUUID(string: "9EB17F9A-87CB-4334-A515-61DDA915E3A3")

    /// The largest value an attribute may hold.
    static let maxValueLength = 512
}

// MARK: - Players

/// A phone at the table: its install's player ID and the name its owner chose.
struct LobbyPlayer: Codable, Hashable, Identifiable {
    var id: String
    var name: String

    /// Names travel at most this long.
    static let maxNameLength = 24

    private enum CodingKeys: String, CodingKey {
        case id = "i", name = "n"
    }

    init(id: String, name: String) {
        self.id = id
        self.name = String(name.trimmingCharacters(in: .whitespacesAndNewlines).prefix(Self.maxNameLength))
    }

    /// The profile a follower writes to the host.
    func encoded() -> Data? {
        try? JSONEncoder().encode(self)
    }

    static func decode(_ data: Data) -> LobbyPlayer? {
        guard let player = try? JSONDecoder().decode(LobbyPlayer.self, from: data),
              !player.id.isEmpty
        else { return nil }
        // Re-trim: the wire is not trusted to have done it.
        return LobbyPlayer(id: String(player.id.prefix(16)), name: player.name)
    }
}

// MARK: - Snapshot

/// Everything a follower needs to mirror the table — the lobby before a game,
/// then the board — and to find its own seat.
///
/// Totals rather than round-by-round scores, which keeps it small enough for
/// a single attribute.
struct TableSnapshot: Codable, Equatable {
    /// 1: board only. 2: adds the lobby, seat owners and connected players.
    static let currentVersion = 2

    var version = TableSnapshot.currentVersion
    /// Stable per scorekeeping phone, so a follower can find it again.
    var hostID: UUID
    /// Changes on every new game, including a rematch. `nil` in the lobby.
    var gameID: UUID?
    /// Seat names so far in the lobby; the players' names in a game.
    var names: [String]
    var totals: [Int]
    var round: Int
    var maxRounds: Int
    var isOver: Bool
    /// The خباص's seat.
    var dealer: Int?
    var startedAt: Date?
    var elapsed: Int
    var lastWinner: Int?
    var lastWinType: String?
    /// The player ID seated in each seat, or `nil` for a name typed by hand.
    var owners: [String?]
    /// Phones connected to the host right now.
    var lobby: [LobbyPlayer]

    private enum CodingKeys: String, CodingKey {
        case version = "v", hostID = "h", gameID = "g", names = "n", totals = "t"
        case round = "r", maxRounds = "m", isOver = "o", dealer = "d"
        case startedAt = "s", elapsed = "e", lastWinner = "w", lastWinType = "wt"
        case owners = "ow", lobby = "lo"
    }

    init(
        hostID: UUID,
        gameID: UUID?,
        names: [String],
        totals: [Int],
        round: Int,
        maxRounds: Int,
        isOver: Bool,
        dealer: Int?,
        startedAt: Date?,
        elapsed: Int,
        lastWinner: Int?,
        lastWinType: String?,
        owners: [String?],
        lobby: [LobbyPlayer]
    ) {
        self.hostID = hostID
        self.gameID = gameID
        self.names = names
        self.totals = totals
        self.round = round
        self.maxRounds = maxRounds
        self.isOver = isOver
        self.dealer = dealer
        self.startedAt = startedAt
        self.elapsed = elapsed
        self.lastWinner = lastWinner
        self.lastWinType = lastWinType
        self.owners = owners
        self.lobby = lobby
    }

    /// Reads version 2, and version 1 — a board with no lobby, owners or
    /// player IDs — so a follower still works against an older host.
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        version = try c.decode(Int.self, forKey: .version)
        hostID = try c.decode(UUID.self, forKey: .hostID)
        gameID = try c.decodeIfPresent(UUID.self, forKey: .gameID)
        names = try c.decode([String].self, forKey: .names)
        totals = try c.decode([Int].self, forKey: .totals)
        round = try c.decode(Int.self, forKey: .round)
        maxRounds = try c.decode(Int.self, forKey: .maxRounds)
        isOver = try c.decode(Bool.self, forKey: .isOver)
        dealer = try c.decodeIfPresent(Int.self, forKey: .dealer)
        startedAt = try c.decodeIfPresent(Date.self, forKey: .startedAt)
        elapsed = try c.decode(Int.self, forKey: .elapsed)
        lastWinner = try c.decodeIfPresent(Int.self, forKey: .lastWinner)
        lastWinType = try c.decodeIfPresent(String.self, forKey: .lastWinType)
        owners = try c.decodeIfPresent([String?].self, forKey: .owners) ?? Array(repeating: nil, count: names.count)
        lobby = try c.decodeIfPresent([LobbyPlayer].self, forKey: .lobby) ?? []
    }

    /// No game yet: the host is still seating players.
    var isLobby: Bool { gameID == nil }

    var leaderIndex: Int? {
        guard !isLobby, let best = totals.min() else { return nil }
        return totals.firstIndex(of: best)
    }

    /// The seat the host gave `playerID`, if any.
    func seat(ofPlayer playerID: String) -> Int? {
        owners.firstIndex { $0 == playerID }
    }

    /// Whether the host has seen `playerID` — connected or seated.
    func knows(playerID: String) -> Bool {
        seat(ofPlayer: playerID) != nil || lobby.contains { $0.id == playerID }
    }

    /// Seats whose owner's phone is connected right now.
    var linkedSeats: Set<Int> {
        let connected = Set(lobby.map(\.id))
        return Set(owners.indices.filter { owners[$0].map(connected.contains) ?? false })
    }

    /// Compact JSON that fits in a single attribute. Long names are trimmed
    /// step by step; as a last resort the lobby keeps IDs without names, and
    /// then only as many players as fit.
    func encoded() -> Data? {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .secondsSince1970

        func fits(_ snapshot: TableSnapshot) -> Data? {
            guard let data = try? encoder.encode(snapshot), data.count <= NearbyService.maxValueLength else { return nil }
            return data
        }

        var copy = self
        for limit in [24, 14, 8, 4] {
            copy.names = names.map { String($0.prefix(limit)) }
            copy.lobby = lobby.map { LobbyPlayer(id: $0.id, name: String($0.name.prefix(limit))) }
            if let data = fits(copy) { return data }
        }
        copy.lobby = lobby.map { LobbyPlayer(id: $0.id, name: "") }
        while true {
            if let data = fits(copy) { return data }
            guard !copy.lobby.isEmpty else { return nil }
            copy.lobby.removeLast()
        }
    }

    static func decode(_ data: Data) -> TableSnapshot? {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .secondsSince1970
        guard let snapshot = try? decoder.decode(TableSnapshot.self, from: data),
              snapshot.version <= currentVersion,
              snapshot.names.count == snapshot.totals.count,
              snapshot.owners.count == snapshot.names.count
        else { return nil }
        return snapshot
    }
}

// MARK: - Who am I

/// This install's identity at the table: a short random player ID that never
/// changes, and the name its owner goes by. No account, no server — both live
/// in this phone's settings.
enum PlayerIdentity {
    private static let nameKey = "myPlayerName"
    private static let idKey = "myPlayerID"

    static var preferredName: String? {
        get { UserDefaults.standard.string(forKey: nameKey) }
        set { UserDefaults.standard.set(newValue, forKey: nameKey) }
    }

    /// 8 hex characters, made on first use.
    static var playerID: String {
        if let stored = UserDefaults.standard.string(forKey: idKey), !stored.isEmpty {
            return stored
        }
        let id = makePlayerID()
        UserDefaults.standard.set(id, forKey: idKey)
        return id
    }

    static func makePlayerID() -> String {
        String(format: "%08x", UInt32.random(in: .min ... .max))
    }

    /// The seat whose name matches this phone's owner, if any.
    static func seat(in names: [String]) -> Int? {
        guard let mine = preferredName?.trimmingCharacters(in: .whitespaces).lowercased(),
              !mine.isEmpty else { return nil }
        return names.firstIndex { $0.trimmingCharacters(in: .whitespaces).lowercased() == mine }
    }
}

// MARK: - Finding my seat

/// How a follower settles which seat is its own when a new snapshot arrives.
///
/// The host's assignment wins. Without one, a seat the player tapped stays,
/// and a reseated table is matched by name.
struct SeatResolver {
    var seat: Int?
    /// True when `seat` came from the host's assignment.
    var fromHost: Bool

    mutating func update(with snapshot: TableSnapshot, previousNames: [String]?, playerID: String, name: (([String]) -> Int?)) {
        if let assigned = snapshot.seat(ofPlayer: playerID) {
            seat = assigned
            fromHost = true
            return
        }
        if fromHost {
            // The host took the seat back; fall back to the name, if typed.
            fromHost = false
            seat = name(snapshot.names)
            return
        }
        if let seat, !snapshot.names.indices.contains(seat) {
            self.seat = nil
        }
        if let previousNames, previousNames != snapshot.names {
            seat = name(snapshot.names)
        } else if seat == nil, previousNames == nil {
            seat = name(snapshot.names)
        }
    }
}
