import Foundation

/// Where one seat stands and, from round 7, the wins it needs to take the
/// lead — worked out on the phone and handed to the lock screen ready to draw.
///
/// Compiled into both the app and the widget extension.
struct SeatAdvice: Codable, Hashable {
    enum Kind: String, Codable, Hashable {
        /// Outright first; `gap` is the margin over the runner-up.
        case leading
        /// The wins in `needs` take the outright lead.
        case overtake
        /// The best the remaining rounds allow is drawing level.
        case tie
        /// No combination of wins left closes the gap.
        case outOfReach
        /// Too early for a plan — rank and gap only.
        case behind
        /// The game is over; `rank` is final.
        case finished
    }

    /// One line of a plan: win `count` rounds as `label`.
    struct Need: Codable, Hashable {
        var label: String
        var count: Int
    }

    var kind: Kind
    /// 1-based standing, sharing a place on equal totals.
    var rank: Int
    /// Points behind the leader, or the lead over the runner-up when leading.
    var gap: Int
    var roundsLeft: Int
    /// Strongest win type first.
    var needs: [Need] = []

    var totalWins: Int { needs.reduce(0) { $0 + $1.count } }

    var headline: String {
        switch kind {
        case .leading: return "أنت المتصدر"
        case .overtake: return "لتتصدر تحتاج"
        case .tie: return "أقصى الممكن: تعادل"
        case .outOfReach: return "الصدارة بعيدة"
        case .behind: return "المركز \(rank)"
        case .finished: return rank == 1 ? "فزت باللعبة" : "انتهت · المركز \(rank)"
        }
    }

    var detail: String {
        switch kind {
        case .leading:
            return "بفارق \(gap)"
        case .overtake, .tie:
            return needsSummary
        case .outOfReach, .behind:
            return gap == 0 ? "متعادل مع المتصدر" : "خلف المتصدر بـ \(gap)"
        case .finished:
            return rank == 1 ? "بفارق \(gap)" : "خلف الفائز بـ \(gap)"
        }
    }

    /// The plan on one line, e.g. "كلر، عادي ×2".
    var needsSummary: String {
        needs
            .map { $0.count > 1 ? "\($0.label) ×\($0.count)" : $0.label }
            .joined(separator: "، ")
    }

    /// Whether this advice carries a plan of wins to show.
    var hasPlan: Bool { kind == .overtake || kind == .tie }
}
