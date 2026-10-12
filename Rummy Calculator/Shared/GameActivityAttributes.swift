import ActivityKit
import Foundation

/// Live Activity for a game in progress — on the phone keeping score, or on a
/// nearby player's phone following it over Bluetooth.
///
/// Compiled into both the app and the widget extension.
struct GameActivityAttributes: ActivityAttributes {
    /// True on a phone following someone else's board.
    let isFollowing: Bool

    /// Everything that changes. Names live here rather than in the static
    /// attributes so a follower's activity can carry on into a rematch with
    /// different seats — a new activity can only be started in the foreground.
    struct ContentState: Codable, Hashable {
        var playerNames: [String]
        var scores: [Int]
        var currentRound: Int
        var isGameOver: Bool
        var leaderIndex: Int?
        /// Fixed duration, shown once the game is over.
        var elapsedSeconds: Int
        /// Drives a live timer on the lock screen without further updates.
        var startDate: Date?
        /// The seat this phone's owner plays, when they have said.
        var mySeat: Int?
        var advice: SeatAdvice?
        /// False while a follower has lost the scorekeeper's phone.
        var isConnected = true
        /// True while the host is still seating players — no scores yet.
        var isLobby: Bool?
    }
}
