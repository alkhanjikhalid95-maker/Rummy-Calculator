import Foundation

/// The game as the home- and lock-screen widgets see it, passed through the
/// shared App Group.
///
/// Compiled into both the app and the widget extension.
struct WidgetGameState: Codable {
    let playerNames: [String]
    let scores: [Int]
    let currentRound: Int
    let isGameOver: Bool
    let leaderIndex: Int?
    let lastUpdated: Date
    var startDate: Date?
    var elapsedSeconds: Int?
    /// The seat this phone's owner plays, when they have said.
    var mySeat: Int?
    var advice: SeatAdvice?
    /// True when this phone is following a nearby scorekeeper.
    var isFollowing: Bool?

    static let storageKey = "widgetGameState"

    /// A board untouched for this long is treated as abandoned.
    static let staleAfter: TimeInterval = 12 * 60 * 60

    static var sharedDefaults: UserDefaults? {
        UserDefaults(suiteName: "group.KHALID.Rummy-Calculator")
    }

    /// Write to shared App Group UserDefaults
    func save() {
        guard let data = try? JSONEncoder().encode(self) else { return }
        Self.sharedDefaults?.set(data, forKey: Self.storageKey)
    }

    /// Read from shared App Group UserDefaults
    static func load() -> WidgetGameState? {
        guard let data = Self.sharedDefaults?.data(forKey: Self.storageKey) else { return nil }
        return try? JSONDecoder().decode(WidgetGameState.self, from: data)
    }

    /// Clear (when no game in progress)
    static func clear() {
        Self.sharedDefaults?.removeObject(forKey: Self.storageKey)
    }
}
