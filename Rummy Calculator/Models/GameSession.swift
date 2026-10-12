import Foundation

/// A game in progress, as saved between launches.
struct SavedSession: Codable {
    var game: Game
    var elapsedSeconds: Int
    var khabasIndex: Int?
    var localSeat: Int?
    /// The nearby player's ID in each seat, when seated from the lobby.
    var owners: [String?]?
}

/// Where the unfinished game is kept. Saving `nil` forgets it.
struct GameSessionStore {
    /// `nil` keeps nothing — for tests and previews.
    let defaults: UserDefaults?

    static let standard = GameSessionStore(defaults: .standard)
    static let ephemeral = GameSessionStore(defaults: nil)

    private static let key = "savedSession"

    func load() -> SavedSession? {
        guard let data = defaults?.data(forKey: Self.key) else { return nil }
        return try? JSONDecoder().decode(SavedSession.self, from: data)
    }

    func save(_ session: SavedSession?) {
        guard let defaults else { return }
        if let session, let data = try? JSONEncoder().encode(session) {
            defaults.set(data, forKey: Self.key)
        } else {
            defaults.removeObject(forKey: Self.key)
        }
    }
}
