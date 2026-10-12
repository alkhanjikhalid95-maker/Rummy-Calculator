import Foundation
import SwiftUI

// MARK: - Win Type

enum WinType: String, CaseIterable, Identifiable, Codable {
    case normal = "عادي"
    case color = "كلر"
    case joker = "جوكر"
    case colorJoker = "كلر + جوكر"
    case zata = "زاته"
    case zataJoker = "زاته + جوكر"

    var id: String { rawValue }

    var winnerScore: Int {
        switch self {
        case .normal: return -60
        case .color: return -120
        case .joker: return -120
        case .colorJoker: return -240
        case .zata: return -240
        case .zataJoker: return -480
        }
    }

    var loserScore: Int {
        switch self {
        case .normal: return 200
        case .color: return 400
        case .joker: return 400
        case .colorJoker: return 800
        case .zata: return 800
        case .zataJoker: return 1600
        }
    }

    /// The 4 distinct scoring tiers for predictions (one representative per tier).
    /// Players can infer that جوكر = كلر and كلر + جوكر = زاته.
    static let predictionTiers: [WinType] = [.normal, .color, .zata, .zataJoker]

    /// How far one win of this type moves the winner against any one loser.
    var swing: Int { loserScore - winnerScore }

    /// Label covering every win type that scores the same as this one.
    var tierLabel: String {
        switch self {
        case .normal: return "عادي"
        case .color, .joker: return "كلر / جوكر"
        case .colorJoker, .zata: return "زاته / كلر+جوكر"
        case .zataJoker: return "زاته + جوكر"
        }
    }
}

// MARK: - Player

struct Player: Identifiable, Equatable, Codable {
    let id: UUID
    var name: String
    let seatIndex: Int

    init(name: String = "", seatIndex: Int) {
        self.id = UUID()
        self.name = name
        self.seatIndex = seatIndex
    }
}

// MARK: - Player Score

struct PlayerScore: Identifiable, Equatable, Codable {
    let id: UUID
    let playerId: UUID
    var autoScore: Int
    var manualScore: Int?
    var hasPenalty: Bool
    var isWinner: Bool

    var effectiveScore: Int {
        manualScore ?? autoScore
    }

    init(playerId: UUID, autoScore: Int, hasPenalty: Bool = false, isWinner: Bool = false) {
        self.id = UUID()
        self.playerId = playerId
        self.autoScore = autoScore
        self.hasPenalty = hasPenalty
        self.isWinner = isWinner
    }
}

// MARK: - Round

struct Round: Identifiable, Equatable, Codable {
    let id: UUID
    let roundNumber: Int
    var winnerId: UUID?
    var winType: WinType?
    var scores: [PlayerScore]

    init(roundNumber: Int, scores: [PlayerScore] = []) {
        self.id = UUID()
        self.roundNumber = roundNumber
        self.scores = scores
    }

    var isCompleted: Bool {
        winnerId != nil
    }
}

// MARK: - Game

struct Game: Equatable, Codable {
    /// Identifies this board to nearby phones, so a rematch reads as a new game.
    var id = UUID()
    var players: [Player]
    var rounds: [Round]
    var maxRounds: Int { 9 }

    init(players: [Player]) {
        self.players = players
        self.rounds = (1...9).map { Round(roundNumber: $0) }
    }

    var currentRoundIndex: Int? {
        rounds.firstIndex { !$0.isCompleted }
    }

    var isGameOver: Bool {
        rounds.allSatisfy { $0.isCompleted }
    }

    func totalScore(for playerId: UUID) -> Int {
        rounds.reduce(0) { total, round in
            let score = round.scores.first { $0.playerId == playerId }
            return total + (score?.effectiveScore ?? 0)
        }
    }
}

// MARK: - Game Record (for history)

struct GameRecord: Codable, Identifiable {
    let id: UUID
    let date: Date
    let duration: Int // seconds
    let playerNames: [String]
    let finalScores: [Int]
    let winnerName: String
    /// Per-round info: (winnerName, winType rawValue)
    let roundResults: [RoundResult]

    struct RoundResult: Codable {
        let roundNumber: Int
        let winnerName: String
        let winType: String
        let scores: [Int] // one per player, in same order as playerNames
    }
}

// MARK: - Game History Manager

@Observable
final class GameHistoryManager {
    private static let storageKey = "gameHistory"
    private static let maxGames = 100

    var games: [GameRecord] = []

    init() {
        load()
    }

    func save(_ record: GameRecord) {
        games.insert(record, at: 0)
        if games.count > Self.maxGames {
            games = Array(games.prefix(Self.maxGames))
        }
        persist()
    }

    func deleteGame(at indexSet: IndexSet) {
        games.remove(atOffsets: indexSet)
        persist()
    }

    func clearAll() {
        games.removeAll()
        persist()
    }

    private func load() {
        guard let data = UserDefaults.standard.data(forKey: Self.storageKey) else { return }
        if let decoded = try? JSONDecoder().decode([GameRecord].self, from: data) {
            games = decoded
        }
    }

    private func persist() {
        if let data = try? JSONEncoder().encode(games) {
            UserDefaults.standard.set(data, forKey: Self.storageKey)
        }
    }
}

// MARK: - Preset Names

@Observable
final class PresetNamesManager {
    private static let storageKey = "customPlayerNames"

    /// Seed names offered in the picker before the player saves any of their own.
    /// Deliberately common given names only — no surnames, so a public build
    /// never ships a real, identifiable person's name.
    static let builtIn: [String] = [
        "Khalid",
        "Hamad",
        "Ali",
        "Saud",
        "Nasser",
        "Yousef",
        "Mohammed",
        "Jassim",
        "Abdullah",
        "Fahad",
        "Rashid",
    ]

    var customNames: [String] = []

    /// All names: custom first (most recent on top), then built-in
    var all: [String] {
        let combined = customNames + Self.builtIn
        // Deduplicate while preserving order
        var seen = Set<String>()
        return combined.filter { name in
            let lowered = name.lowercased()
            if seen.contains(lowered) { return false }
            seen.insert(lowered)
            return true
        }
    }

    init() {
        load()
    }

    /// Names that should never be saved (placeholder defaults)
    private static let blockedNames: Set<String> = ["p1", "p2", "p3", "p4"]

    /// Add names that aren't already in the list
    func addNames(_ names: [String]) {
        let existingLowered = Set(all.map { $0.lowercased() })
        var added = false
        for name in names {
            let trimmed = name.trimmingCharacters(in: .whitespaces)
            guard !trimmed.isEmpty,
                  !existingLowered.contains(trimmed.lowercased()),
                  !Self.blockedNames.contains(trimmed.lowercased()) else { continue }
            customNames.insert(trimmed, at: 0)
            added = true
        }
        if added { persist() }
    }

    func removeName(_ name: String) {
        customNames.removeAll { $0.lowercased() == name.lowercased() }
        persist()
    }

    /// Rename a custom name (for fixing typos / capitalization)
    func renameName(from oldName: String, to newName: String) {
        let trimmed = newName.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty,
              !Self.blockedNames.contains(trimmed.lowercased()) else { return }
        if let index = customNames.firstIndex(where: { $0.lowercased() == oldName.lowercased() }) {
            customNames[index] = trimmed
            persist()
        }
    }

    private func load() {
        if let data = UserDefaults.standard.data(forKey: Self.storageKey),
           let decoded = try? JSONDecoder().decode([String].self, from: data) {
            // Filter out any previously saved blocked names
            customNames = decoded.filter { !Self.blockedNames.contains($0.lowercased()) }
            // Re-persist if any were removed
            if customNames.count != decoded.count { persist() }
        }
    }

    private func persist() {
        if let data = try? JSONEncoder().encode(customNames) {
            UserDefaults.standard.set(data, forKey: Self.storageKey)
        }
    }
}
