import SwiftUI
import WidgetKit

// MARK: - Palette

/// The app's palette for the widget extension: ink on white, white on the
/// mauve-to-sage aura.
enum WidgetPalette {
    static let ink          = Color(red: 0.067, green: 0.067, blue: 0.075)
    static let inkSecondary = Color(red: 0.443, green: 0.443, blue: 0.478)
    static let mauveLight   = Color(red: 0.890, green: 0.808, blue: 0.859)
    static let mauve        = Color(red: 0.792, green: 0.651, blue: 0.745)
    static let mauveDeep    = Color(red: 0.663, green: 0.514, blue: 0.616)
    static let sage         = Color(red: 0.580, green: 0.663, blue: 0.525)
    static let sageDeep     = Color(red: 0.412, green: 0.522, blue: 0.369)
    static let ember        = Color(red: 0.929, green: 0.471, blue: 0.231)
    static let positive     = Color(red: 0.231, green: 0.549, blue: 0.361)
    static let positiveOnDark = Color(red: 0.55, green: 0.85, blue: 0.62)
    static let negative     = Color(red: 0.827, green: 0.278, blue: 0.329)

    /// Behind the home-screen widgets.
    static let aura = LinearGradient(
        colors: [mauveLight, mauve, sage],
        startPoint: .topLeading,
        endPoint: .bottomTrailing
    )
}

/// Whether text sits on a light surface (ink) or a dark/coloured one (white).
enum WidgetTone {
    case light, dark

    var primary: Color { self == .light ? WidgetPalette.ink : .white }
    var secondary: Color { self == .light ? WidgetPalette.inkSecondary : .white.opacity(0.75) }
    var faint: Color { self == .light ? WidgetPalette.ink.opacity(0.12) : .white.opacity(0.25) }
    var leader: Color { self == .light ? WidgetPalette.positive : WidgetPalette.positiveOnDark }
}

// MARK: - Shared pieces

/// Round label, e.g. "اللفة 7 / 9" or "انتهت اللعبة".
func roundTitle(_ round: Int, isGameOver: Bool, maxRounds: Int = 9) -> String {
    isGameOver ? "انتهت اللعبة" : "اللفة \(round) / \(maxRounds)"
}

/// Nine dots, filled for rounds played, a ring for the current one.
struct RoundPips: View {
    let round: Int
    let isGameOver: Bool
    var maxRounds = 9
    var tone: WidgetTone = .light

    var body: some View {
        HStack(spacing: 4) {
            ForEach(1...maxRounds, id: \.self) { index in
                let played = isGameOver || index < round
                let current = !isGameOver && index == round
                if current {
                    Circle()
                        .stroke(WidgetPalette.ember, lineWidth: 1.5)
                        .frame(width: 7, height: 7)
                } else {
                    Circle()
                        .fill(played ? tone.primary : tone.faint)
                        .frame(width: 5, height: 5)
                }
            }
        }
        .accessibilityHidden(true)
    }
}

/// Game clock: live while playing, fixed once finished.
struct GameClock: View {
    let startDate: Date?
    let elapsedSeconds: Int
    let isGameOver: Bool
    var tone: WidgetTone = .light

    var body: some View {
        HStack(spacing: 3) {
            Image(systemName: "clock")
                .font(.system(size: 10))
            if let startDate, !isGameOver {
                Text(startDate, style: .timer)
                    .monospacedDigit()
                    .multilineTextAlignment(.trailing)
                    .frame(maxWidth: 56, alignment: .trailing)
            } else {
                Text(clockString(elapsedSeconds))
                    .monospacedDigit()
            }
        }
        .font(.system(size: 13))
        .foregroundStyle(tone.secondary)
    }
}

func clockString(_ seconds: Int) -> String {
    let h = seconds / 3600
    let m = (seconds % 3600) / 60
    let s = seconds % 60
    return h > 0 ? String(format: "%d:%02d:%02d", h, m, s) : String(format: "%02d:%02d", m, s)
}

/// One seat: monogram disc, name and total; black when it is this phone's.
struct SeatColumn: View {
    let name: String
    let score: Int
    let seat: Int
    let isLeader: Bool
    let isMine: Bool
    var compact = false
    var tone: WidgetTone = .light
    /// Off in the lobby, before anyone has a score.
    var showScore = true

    var body: some View {
        VStack(spacing: compact ? 2 : 4) {
            ZStack(alignment: .topTrailing) {
                Circle()
                    .fill(isMine ? tone.primary : tone.faint)
                    .frame(width: compact ? 22 : 28, height: compact ? 22 : 28)
                    .overlay(
                        Text(name.first.map { String($0).uppercased() } ?? "?")
                            .font(.system(size: compact ? 11 : 13, weight: .medium))
                            .foregroundStyle(isMine ? (tone == .light ? Color.white : WidgetPalette.ink) : tone.primary)
                    )
                if isLeader {
                    Image(systemName: "crown.fill")
                        .font(.system(size: compact ? 7 : 8))
                        .foregroundStyle(tone.primary)
                        .offset(x: 5, y: -5)
                }
            }
            Text(name)
                .font(.system(size: compact ? 11 : 12, weight: isMine ? .semibold : .regular))
                .foregroundStyle(tone.primary)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
            Text(showScore ? score.formatted() : "—")
                .font(.system(size: compact ? 13 : 16, weight: .medium).monospacedDigit())
                .foregroundStyle(isLeader ? tone.leader : (showScore ? tone.primary : tone.secondary))
                .lineLimit(1)
                .minimumScaleFactor(0.7)
                .contentTransition(.numericText(value: Double(score)))
        }
        .frame(maxWidth: .infinity)
    }
}

/// The four seats in board order.
struct SeatsRow: View {
    let names: [String]
    let scores: [Int]
    let leaderIndex: Int?
    let mySeat: Int?
    var compact = false
    var tone: WidgetTone = .light
    var showScores = true

    var body: some View {
        HStack(spacing: 2) {
            ForEach(names.indices, id: \.self) { index in
                if index < scores.count {
                    SeatColumn(
                        name: names[index],
                        score: scores[index],
                        seat: index,
                        isLeader: leaderIndex == index,
                        isMine: mySeat == index,
                        compact: compact,
                        tone: tone,
                        showScore: showScores
                    )
                }
            }
        }
    }
}

/// The advice line: headline, then the wins needed as chips.
struct AdviceRow: View {
    let advice: SeatAdvice
    var compact = false
    var tone: WidgetTone = .light

    private var icon: String {
        switch advice.kind {
        case .leading: return "crown"
        case .overtake: return "scope"
        case .tie: return "equal.circle"
        case .outOfReach: return "hand.raised"
        case .behind: return "chart.bar"
        case .finished: return advice.rank == 1 ? "trophy" : "flag.checkered"
        }
    }

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: icon)
                .font(.system(size: compact ? 10 : 12))
                .foregroundStyle(tone.primary)
            Text(advice.headline)
                .font(.system(size: compact ? 12 : 13, weight: .medium))
                .foregroundStyle(tone.primary)
                .lineLimit(1)
            if advice.hasPlan {
                ForEach(advice.needs, id: \.self) { need in
                    Text(need.count > 1 ? "\(need.label) ×\(need.count)" : need.label)
                        .font(.system(size: compact ? 11 : 12, weight: .medium))
                        .foregroundStyle(tone == .light ? Color.white : WidgetPalette.ink)
                        .lineLimit(1)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 3)
                        .background(tone.primary, in: Capsule())
                }
            } else {
                Text(advice.detail)
                    .font(.system(size: compact ? 11 : 12))
                    .foregroundStyle(tone.secondary)
                    .lineLimit(1)
            }
            Spacer(minLength: 0)
        }
        .environment(\.layoutDirection, .rightToLeft)
        .minimumScaleFactor(0.75)
    }
}
