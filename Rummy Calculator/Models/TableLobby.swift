import Foundation

/// The host's view of who is at the table: the phones connected over
/// Bluetooth, and which seat each one holds.
///
/// Pure rules, no Bluetooth — the view model feeds it joins and leaves and
/// asks it who can still be seated.
struct TableLobby: Equatable {
    /// Every player seen, in the order they first appeared. That order
    /// decides who keeps a shared name as is and who gets a suffix.
    private(set) var players: [LobbyPlayer] = []
    private(set) var connectedIDs: Set<String> = []
    /// The player ID holding each seat, or `nil` for an empty or hand-typed seat.
    private(set) var owners: [String?]

    init(seatCount: Int = 4) {
        owners = Array(repeating: nil, count: seatCount)
    }

    // MARK: Connections

    /// A phone introduced itself, for the first time or again after a
    /// disconnect — a seat it held is still its own.
    mutating func join(_ player: LobbyPlayer) {
        if let index = players.firstIndex(where: { $0.id == player.id }) {
            players[index].name = player.name
        } else {
            players.append(player)
        }
        connectedIDs.insert(player.id)
    }

    /// A phone went away. It leaves the available list, but a seat it held
    /// keeps its name until the host changes it.
    mutating func leave(playerID: String) {
        connectedIDs.remove(playerID)
    }

    /// Bluetooth went off: nobody is connected any more.
    mutating func disconnectAll() {
        connectedIDs.removeAll()
    }

    func isConnected(_ playerID: String) -> Bool {
        connectedIDs.contains(playerID)
    }

    // MARK: Seating

    /// Seats `playerID`, moving them out of any other seat and releasing
    /// whoever held this one. Returns the name to write into the seat.
    @discardableResult
    mutating func assign(playerID: String, toSeat seat: Int) -> String? {
        guard owners.indices.contains(seat), players.contains(where: { $0.id == playerID }) else { return nil }
        for index in owners.indices where owners[index] == playerID {
            owners[index] = nil
        }
        owners[seat] = playerID
        return displayName(for: playerID)
    }

    mutating func release(seat: Int) {
        guard owners.indices.contains(seat) else { return }
        owners[seat] = nil
    }

    /// The host edited a seat's name by hand. Clearing it, or typing anything
    /// other than the seated player's name, frees the player for another seat.
    mutating func seatNameChanged(seat: Int, to name: String) {
        guard owners.indices.contains(seat), let owner = owners[seat] else { return }
        if name.trimmingCharacters(in: .whitespacesAndNewlines) != displayName(for: owner) {
            owners[seat] = nil
        }
    }

    /// Puts back seat owners saved with an unfinished game, so a relaunch
    /// keeps everyone in their seats until their phones reconnect.
    mutating func restore(owners saved: [String?], names: [String]) {
        for (seat, owner) in saved.enumerated() where owners.indices.contains(seat) {
            guard let owner else { continue }
            if !players.contains(where: { $0.id == owner }) {
                players.append(LobbyPlayer(id: owner, name: names.indices.contains(seat) ? names[seat] : ""))
            }
            owners[seat] = owner
        }
    }

    func seat(of playerID: String) -> Int? {
        owners.firstIndex { $0 == playerID }
    }

    /// Seats held by a phone that is connected right now.
    var linkedSeats: Set<Int> {
        Set(owners.indices.filter { owners[$0].map(connectedIDs.contains) ?? false })
    }

    // MARK: Lists

    /// Connected and not yet seated, in the order they joined, under their
    /// display names.
    var available: [LobbyPlayer] {
        connected.filter { seat(of: $0.id) == nil }
    }

    /// Everyone connected, under their display names.
    var connected: [LobbyPlayer] {
        players
            .filter { connectedIDs.contains($0.id) }
            .map { LobbyPlayer(id: $0.id, name: displayName(for: $0.id)) }
    }

    /// A player's name, with " 2", " 3"… when someone who joined earlier
    /// already goes by it.
    func displayName(for playerID: String) -> String {
        guard let index = players.firstIndex(where: { $0.id == playerID }) else { return "" }
        let base = players[index].name.isEmpty ? "لاعب" : players[index].name
        let key = base.lowercased()
        let earlier = players[..<index].filter { ($0.name.isEmpty ? "لاعب" : $0.name).lowercased() == key }.count
        guard earlier > 0 else { return base }
        // Leave room for the suffix within the length a name may travel at.
        return "\(base.prefix(LobbyPlayer.maxNameLength - 3)) \(earlier + 1)"
    }
}
