import SwiftUI

/// Club standings across every saved game: a podium and leaderboard of wins
/// and places, and a head-to-head for any two players.
struct StandingsView: View {
    enum Tab: Hashable {
        case leaderboard, headToHead
    }

    private let standings: ClubStandings

    @Environment(\.dismiss) private var dismiss
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    @State private var tab: Tab
    @State private var sort: ClubStandings.Sort = .wins
    @State private var firstKey: String?
    @State private var secondKey: String?
    /// Drives the entrance. Only heights, scale and offset move — never
    /// opacity — so the page is fully drawn even if it never runs.
    @State private var appeared = false

    /// `first` and `second` open the head-to-head on that pair.
    init(games: [GameRecord], tab: Tab = .leaderboard, first: String? = nil, second: String? = nil) {
        standings = ClubStandings(games: games)
        _tab = State(initialValue: tab)
        _firstKey = State(initialValue: first.map(ClubStandings.key))
        _secondKey = State(initialValue: second.map(ClubStandings.key))
    }

    private var spring: Animation? {
        reduceMotion ? nil : .spring(response: 0.5, dampingFraction: 0.84)
    }

    var body: some View {
        VStack(spacing: 0) {
            SheetHeader(title: "الترتيب العام", subtitle: subtitle) { dismiss() }

            if standings.players.isEmpty {
                emptyState
            } else {
                TabSwitch(selection: $tab)
                    .padding(.horizontal, 16)
                    .padding(.bottom, 6)

                ScrollView {
                    ZStack(alignment: .top) {
                        switch tab {
                        case .leaderboard:
                            leaderboard
                                .transition(.move(edge: .leading))
                        case .headToHead:
                            headToHead
                                .transition(.move(edge: .trailing))
                        }
                    }
                    .padding(.horizontal, 16)
                    .padding(.top, 10)
                    .padding(.bottom, 28)
                }
                .scrollIndicators(.hidden)
            }
        }
        .themedSheet()
        .animation(spring, value: tab)
        .animation(spring, value: sort)
        .sensoryFeedback(.selection, trigger: tab)
        .sensoryFeedback(.selection, trigger: sort)
        .sensoryFeedback(.selection, trigger: [firstKey, secondKey])
        .onAppear {
            guard !appeared else { return }
            if reduceMotion {
                appeared = true
            } else {
                withAnimation(.spring(response: 0.7, dampingFraction: 0.8).delay(0.1)) { appeared = true }
            }
        }
    }

    private var subtitle: String {
        "\(standings.gameCount) لعبة · \(standings.players.count) لاعب"
    }

    private var emptyState: some View {
        VStack(spacing: 14) {
            FloatingCards(width: 46)
                .frame(height: 90)
            Text("لا توجد نتائج بعد")
                .font(.system(size: 19))
                .foregroundStyle(Color.ink)
            Text("يظهر الترتيب بعد أول لعبة مكتملة")
                .font(.system(size: 14))
                .foregroundStyle(Color.inkSecondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(.bottom, 60)
    }

    // MARK: - Leaderboard

    private var leaderboard: some View {
        let board = standings.leaderboard(by: sort)
        return VStack(spacing: 14) {
            Podium(top: Array(board.prefix(3)), sort: sort, raised: appeared)

            SortPicker(selection: $sort)

            VStack(spacing: 0) {
                PlacesLegend()
                    .padding(.bottom, 4)
                ForEach(Array(board.enumerated()), id: \.element.id) { index, player in
                    LeaderboardRow(rank: index + 1, player: player, sort: sort, showsRule: index > 0, raised: appeared) {
                        compare(player)
                    }
                    .offset(y: appeared ? 0 : 18)
                    .animation(
                        reduceMotion ? nil : .spring(response: 0.55, dampingFraction: 0.82).delay(0.05 * Double(min(index, 8))),
                        value: appeared
                    )
                }
            }
            .padding(.horizontal, 18)
            .padding(.vertical, 14)
            .card(radius: 28)

            Text("اضغط على لاعب لمقارنته بغيره")
                .font(.system(size: 12))
                .foregroundStyle(Color.inkTertiary)
        }
    }

    /// Opens the head-to-head with `player` against their usual opponent.
    private func compare(_ player: ClubStandings.Player) {
        firstKey = player.key
        secondKey = standings.usualOpponent(of: player.key)?.key
        tab = .headToHead
    }

    // MARK: - Head-to-head

    /// The chosen pair, falling back to the leader and their usual opponent.
    private var pair: (first: ClubStandings.Player, second: ClubStandings.Player)? {
        guard let first = firstKey.flatMap({ standings.player($0) }) ?? standings.players.first else { return nil }
        let chosen = secondKey.flatMap { $0 == first.key ? nil : standings.player($0) }
        guard let second = chosen ?? standings.usualOpponent(of: first.key) else { return nil }
        return (first, second)
    }

    @ViewBuilder
    private var headToHead: some View {
        if let pair {
            let result = standings.headToHead(pair.first.key, pair.second.key)
            VStack(spacing: 14) {
                matchup(pair.first, pair.second, result)

                if result.games == 0 {
                    neverMet(pair.first, pair.second)
                } else {
                    comparison(pair.first, pair.second, result)
                    PlacesComparison(first: pair.first.name, second: pair.second.name, result: result, raised: appeared)
                    meetings(result)
                }
            }
        } else {
            Text("تحتاج المقارنة لاعبَين على الأقل")
                .font(.system(size: 15))
                .foregroundStyle(Color.inkSecondary)
                .padding(.top, 40)
        }
    }

    private func matchup(_ first: ClubStandings.Player, _ second: ClubStandings.Player, _ result: HeadToHead) -> some View {
        VStack(spacing: 16) {
            HStack {
                EyebrowLabel("مرات التقدّم على الآخر")
                Spacer()
                Text("\(result.games) لعبة معاً")
                    .font(.system(size: 12))
                    .foregroundStyle(Color.inkSecondary)
                    .contentTransition(.numericText(value: Double(result.games)))
            }

            HStack(alignment: .top, spacing: 0) {
                PlayerPicker(
                    player: first,
                    tint: .ink,
                    options: standings.players.filter { $0.key != second.key }
                ) { firstKey = $0 }

                VStack(spacing: 10) {
                    HStack(alignment: .firstTextBaseline, spacing: 8) {
                        Text("\(result.first.ahead)")
                            .foregroundStyle(Color.ink)
                            .contentTransition(.numericText(value: Double(result.first.ahead)))
                        Text(":")
                            .foregroundStyle(Color.inkTertiary)
                        Text("\(result.second.ahead)")
                            .foregroundStyle(Color.sageDeep)
                            .contentTransition(.numericText(value: Double(result.second.ahead)))
                    }
                    .font(.system(size: 44, weight: .light).monospacedDigit())

                    Button {
                        firstKey = second.key
                        secondKey = first.key
                    } label: {
                        Image(systemName: "arrow.left.arrow.right")
                            .font(.system(size: 13, weight: .medium))
                            .foregroundStyle(Color.ink)
                            .frame(width: 34, height: 34)
                            .background(Color.canvas, in: Circle())
                    }
                    .buttonStyle(PressableStyle(scale: 0.88))
                    .accessibilityLabel(Text("تبديل اللاعبَين"))
                }
                .padding(.top, 6)
                .fixedSize()

                PlayerPicker(
                    player: second,
                    tint: .sageDeep,
                    options: standings.players.filter { $0.key != first.key }
                ) { secondKey = $0 }
            }

            SplitBar(first: result.first.ahead, level: result.level, second: result.second.ahead)
                .frame(height: 8)

            verdict(first, second, result)
        }
        .padding(20)
        .card(radius: 32)
        .accessibilityElement(children: .contain)
    }

    @ViewBuilder
    private func verdict(_ first: ClubStandings.Player, _ second: ClubStandings.Player, _ result: HeadToHead) -> some View {
        switch result.better {
        case .first:
            VerdictChip(text: "\(first.name) أفضل ترتيباً", tint: .ink)
                .id(first.key)
                .transition(.scale(scale: 0.6))
        case .second:
            VerdictChip(text: "\(second.name) أفضل ترتيباً", tint: .sageDeep)
                .id(second.key)
                .transition(.scale(scale: 0.6))
        case nil:
            Text(result.games == 0 ? "لم يلتقيا بعد" : "متعادلان")
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(Color.ink)
                .padding(.horizontal, 14)
                .padding(.vertical, 7)
                .background(Color.canvas, in: Capsule())
        }
    }

    private func neverMet(_ first: ClubStandings.Player, _ second: ClubStandings.Player) -> some View {
        VStack(spacing: 8) {
            Image(systemName: "person.2.slash")
                .font(.system(size: 24, weight: .light))
                .foregroundStyle(Color.ink)
            Text("لم يلتقِ \(first.name) مع \(second.name) على طاولة واحدة بعد")
                .font(.system(size: 15))
                .foregroundStyle(Color.ink)
                .multilineTextAlignment(.center)
            Text("اختر لاعباً آخر من الأعلى")
                .font(.system(size: 13))
                .foregroundStyle(Color.inkSecondary)
        }
        .padding(22)
        .frame(maxWidth: .infinity)
        .card(radius: 28)
    }

    private func comparison(_ first: ClubStandings.Player, _ second: ClubStandings.Player, _ result: HeadToHead) -> some View {
        let games = result.games
        let avgFirst = result.first.averagePlace(over: games)
        let avgSecond = result.second.averagePlace(over: games)
        let rankFirst = standings.overallRank(of: first.key) ?? 0
        let rankSecond = standings.overallRank(of: second.key) ?? 0

        return VStack(spacing: 4) {
            HStack {
                EyebrowLabel("في الألعاب المشتركة")
                Spacer()
            }
            .padding(.bottom, 6)

            StatRow(label: "الانتصارات", first: "\(result.first.wins)", second: "\(result.second.wins)",
                    better: edge(Double(result.first.wins), Double(result.second.wins), higherIsBetter: true))
            StatRow(label: "متوسط المركز", first: decimal(avgFirst), second: decimal(avgSecond),
                    better: edge(avgFirst, avgSecond, higherIsBetter: false))
            StatRow(label: "الفوز باللفات", first: "\(result.first.roundWins)", second: "\(result.second.roundWins)",
                    better: edge(Double(result.first.roundWins), Double(result.second.roundWins), higherIsBetter: true))
            StatRow(label: "مجموع النقاط", first: result.first.pointsTotal.formatted(), second: result.second.pointsTotal.formatted(),
                    better: edge(Double(result.first.pointsTotal), Double(result.second.pointsTotal), higherIsBetter: false))
            StatRow(label: "أفضل نتيجة", first: (result.first.bestScore ?? 0).formatted(), second: (result.second.bestScore ?? 0).formatted(),
                    better: edge(Double(result.first.bestScore ?? 0), Double(result.second.bestScore ?? 0), higherIsBetter: false))

            Rectangle()
                .fill(Color.rule)
                .frame(height: 1)
                .padding(.vertical, 6)

            StatRow(label: "الترتيب العام", first: "\(rankFirst)", second: "\(rankSecond)",
                    better: edge(Double(rankFirst), Double(rankSecond), higherIsBetter: false))
        }
        .padding(18)
        .card(radius: 28)
    }

    private func meetings(_ result: HeadToHead) -> some View {
        VStack(spacing: 0) {
            HStack {
                EyebrowLabel("آخر المواجهات")
                Spacer()
            }
            .padding(.bottom, 8)

            ForEach(Array(result.meetings.prefix(6).enumerated()), id: \.element.id) { index, meeting in
                if index > 0 {
                    Rectangle().fill(Color.rule).frame(height: 1)
                }
                HStack {
                    MeetingResult(result: meeting.first, isAhead: meeting.first.score < meeting.second.score, tint: .ink)
                    Spacer()
                    Text(meeting.date.formatted(date: .abbreviated, time: .omitted))
                        .font(.system(size: 12))
                        .foregroundStyle(Color.inkSecondary)
                    Spacer()
                    MeetingResult(result: meeting.second, isAhead: meeting.second.score < meeting.first.score, tint: .sageDeep)
                }
                .padding(.vertical, 10)
            }
        }
        .padding(18)
        .card(radius: 28)
    }

    private func edge(_ first: Double, _ second: Double, higherIsBetter: Bool) -> HeadToHead.Edge? {
        guard first != second else { return nil }
        return (first > second) == higherIsBetter ? .first : .second
    }

    private func decimal(_ value: Double) -> String {
        value.formatted(.number.precision(.fractionLength(1)))
    }
}

// MARK: - Tabs

private struct TabSwitch: View {
    @Binding var selection: StandingsView.Tab
    @Namespace private var pill

    var body: some View {
        HStack(spacing: 4) {
            item(.leaderboard, title: "الصدارة", icon: "trophy")
            item(.headToHead, title: "المواجهة", icon: "person.2")
        }
        .padding(4)
        .background(Color.white, in: Capsule())
        .shadow(color: .black.opacity(0.06), radius: 12, y: 5)
    }

    private func item(_ tab: StandingsView.Tab, title: LocalizedStringKey, icon: String) -> some View {
        let isSelected = selection == tab
        return Button {
            selection = tab
        } label: {
            Label(title, systemImage: icon)
                .font(.system(size: 15, weight: .medium))
                .foregroundStyle(isSelected ? Color.white : Color.ink)
                .frame(maxWidth: .infinity)
                .frame(height: 42)
                .background {
                    if isSelected {
                        Capsule()
                            .fill(Color.ink)
                            .matchedGeometryEffect(id: "selection", in: pill)
                    }
                }
                .contentShape(Capsule())
        }
        .buttonStyle(PressableStyle(scale: 0.97))
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }
}

private struct SortPicker: View {
    @Binding var selection: ClubStandings.Sort

    var body: some View {
        HStack(spacing: 8) {
            ForEach(ClubStandings.Sort.allCases) { sort in
                let isSelected = selection == sort
                Button {
                    selection = sort
                } label: {
                    Text(sort.title)
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(isSelected ? Color.white : Color.ink)
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)
                        .frame(maxWidth: .infinity)
                        .frame(height: 36)
                        .background(isSelected ? Color.ink : Color.white, in: Capsule())
                        .shadow(color: .black.opacity(isSelected ? 0.18 : 0.06), radius: 10, y: 4)
                }
                .buttonStyle(PressableStyle(scale: 0.95))
                .accessibilityAddTraits(isSelected ? .isSelected : [])
            }
        }
    }
}

extension ClubStandings.Sort {
    var title: LocalizedStringKey {
        switch self {
        case .wins: "الانتصارات"
        case .averagePlace: "متوسط المركز"
        case .roundWins: "الفوز باللفات"
        }
    }

    /// The figure a player is ranked on, and what it counts.
    func value(for player: ClubStandings.Player) -> (number: String, unit: String) {
        switch self {
        case .wins:
            ("\(player.wins)", "فوز")
        case .averagePlace:
            (player.averagePlace.formatted(.number.precision(.fractionLength(1))), "متوسط المركز")
        case .roundWins:
            ("\(player.roundWins)", "لفة")
        }
    }
}

// MARK: - Podium

/// The top three on the aura, standing on blocks that rise into place.
private struct Podium: View {
    let top: [ClubStandings.Player]
    let sort: ClubStandings.Sort
    let raised: Bool

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private static let heights: [CGFloat] = [96, 72, 54]

    /// Second, first, third — the winner in the middle.
    private var order: [Int] {
        [1, 0, 2].filter { top.indices.contains($0) }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            GlassTag(text: "المتصدرون", systemImage: "trophy", font: .system(size: 13, weight: .medium))

            HStack(alignment: .bottom, spacing: 10) {
                ForEach(order, id: \.self) { index in
                    column(index)
                }
            }
        }
        .padding(18)
        .background {
            AuraGradient()
                .clipShape(RoundedRectangle(cornerRadius: 32, style: .continuous))
        }
        .shadow(color: Color.mauveDeep.opacity(0.2), radius: 20, y: 10)
    }

    private func column(_ index: Int) -> some View {
        let player = top[index]
        let place = index + 1
        let value = sort.value(for: player)
        return VStack(spacing: 8) {
            SeatBubble(
                name: player.name,
                seat: index,
                size: place == 1 ? 56 : 46,
                style: .aura,
                isRaised: place == 1,
                badge: place == 1 ? .crown : nil
            )

            Text(player.name)
                .font(.system(size: 13, weight: place == 1 ? .semibold : .regular))
                .foregroundStyle(Color.ink)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
                .padding(.horizontal, 10)
                .padding(.vertical, 5)
                .frosted(in: Capsule())

            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(Color.clear)
                .frosted(in: RoundedRectangle(cornerRadius: 18, style: .continuous))
                .overlay(alignment: .top) {
                    VStack(spacing: 0) {
                        Text("\(place)")
                            .font(.system(size: 26, weight: .light))
                        Text("\(value.number) \(value.unit)")
                            .font(.system(size: 11).monospacedDigit())
                            .lineLimit(1)
                            .minimumScaleFactor(0.7)
                            .contentTransition(.numericText())
                            .opacity(0.7)
                    }
                    .foregroundStyle(Color.ink)
                    .padding(.top, 8)
                    .padding(.horizontal, 4)
                }
                .frame(height: raised ? Self.heights[index] : 46)
                .animation(
                    reduceMotion ? nil : .spring(response: 0.6, dampingFraction: 0.7).delay([0.15, 0.05, 0.25][index]),
                    value: raised
                )
        }
        .frame(maxWidth: .infinity)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text("المركز \(place)، \(player.name)، \(value.number) \(value.unit)"))
    }
}

// MARK: - Leaderboard rows

private extension Color {
    /// First to fourth place, darkest first.
    static let places: [Color] = [.ink, .mauveDeep, .sage, .inkTertiary.opacity(0.6)]
}

private let placeNames = ["الأول", "الثاني", "الثالث", "الرابع"]

private struct PlacesLegend: View {
    var body: some View {
        HStack(spacing: 12) {
            Text("المراكز")
                .foregroundStyle(Color.inkSecondary)
            Spacer(minLength: 0)
            ForEach(0..<4, id: \.self) { place in
                HStack(spacing: 4) {
                    Circle()
                        .fill(Color.places[place])
                        .frame(width: 7, height: 7)
                    Text(placeNames[place])
                        .foregroundStyle(Color.inkSecondary)
                }
            }
        }
        .font(.system(size: 11))
        .accessibilityHidden(true)
    }
}

private struct LeaderboardRow: View {
    let rank: Int
    let player: ClubStandings.Player
    let sort: ClubStandings.Sort
    let showsRule: Bool
    let raised: Bool
    let action: () -> Void

    var body: some View {
        let value = sort.value(for: player)
        Button(action: action) {
            VStack(spacing: 10) {
                HStack(spacing: 12) {
                    Text("\(rank)")
                        .font(.system(size: 15, weight: .medium).monospacedDigit())
                        .foregroundStyle(rank == 1 ? Color.ink : Color.inkSecondary)
                        .frame(width: 20)

                    SeatBubble(name: player.name, seat: 0, size: 40, style: .paper, isRaised: rank == 1)

                    VStack(alignment: .leading, spacing: 3) {
                        Text(player.name)
                            .font(.system(size: 17))
                            .foregroundStyle(Color.ink)
                            .lineLimit(1)
                        Text("\(player.games) لعبة · نسبة الفوز \(player.winRate.formatted(.percent.precision(.fractionLength(0))))")
                            .font(.system(size: 12))
                            .foregroundStyle(Color.inkSecondary)
                            .lineLimit(1)
                    }

                    Spacer(minLength: 8)

                    VStack(alignment: .trailing, spacing: 0) {
                        Text(value.number)
                            .font(.system(size: 24, weight: .light).monospacedDigit())
                            .foregroundStyle(Color.ink)
                            .contentTransition(.numericText())
                        Text(value.unit)
                            .font(.system(size: 11))
                            .foregroundStyle(Color.inkSecondary)
                    }
                }

                PlacesBar(places: player.places, raised: raised)
                    .frame(height: 6)
                    .padding(.leading, 84)
            }
            .padding(.vertical, 12)
            .overlay(alignment: .top) {
                if showsRule {
                    Rectangle().fill(Color.rule).frame(height: 1)
                }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(PressableStyle(scale: 0.98))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text("المركز \(rank)، \(player.name)، \(player.wins) فوز من \(player.games) لعبة"))
        .accessibilityHint(Text("مقارنته بلاعب آخر"))
    }
}

/// How often a player finished in each place, as one segmented bar.
private struct PlacesBar: View {
    let places: [Int]
    let raised: Bool

    var body: some View {
        let total = max(1, places.reduce(0, +))
        GeometryReader { geo in
            let gaps = CGFloat(places.filter { $0 > 0 }.count - 1) * 2
            HStack(spacing: 2) {
                ForEach(places.indices, id: \.self) { place in
                    if places[place] > 0 {
                        Capsule()
                            .fill(Color.places[place])
                            .frame(width: max(0, geo.size.width - gaps) * CGFloat(places[place]) / CGFloat(total))
                    }
                }
            }
            .scaleEffect(x: raised ? 1 : 0.05, anchor: .leading)
        }
        .accessibilityHidden(true)
    }
}

// MARK: - Head-to-head pieces

/// A player's disc and name; tap to pick someone else.
private struct PlayerPicker: View {
    let player: ClubStandings.Player
    let tint: Color
    let options: [ClubStandings.Player]
    let onSelect: (String) -> Void

    var body: some View {
        Menu {
            ForEach(options) { option in
                Button(option.name) { onSelect(option.key) }
            }
        } label: {
            VStack(spacing: 6) {
                PlayerDisc(name: player.name, tint: tint, size: 58)
                Text(player.name)
                    .font(.system(size: 16, weight: .medium))
                    .foregroundStyle(Color.ink)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
                HStack(spacing: 3) {
                    Text("تغيير")
                    Image(systemName: "chevron.down")
                        .font(.system(size: 9, weight: .semibold))
                }
                .font(.system(size: 11))
                .foregroundStyle(Color.inkSecondary)
                .padding(.horizontal, 10)
                .padding(.vertical, 4)
                .background(Color.canvas, in: Capsule())
            }
            .frame(maxWidth: .infinity)
        }
        .accessibilityLabel(Text(player.name))
        .accessibilityHint(Text("اختيار لاعب آخر"))
    }
}

/// A solid disc with the player's initial. Pops when the player changes.
private struct PlayerDisc: View {
    let name: String
    let tint: Color
    let size: CGFloat

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        Text(name.trimmingCharacters(in: .whitespaces).first.map { String($0).uppercased() } ?? "")
            .font(.system(size: size * 0.4))
            .foregroundStyle(.white)
            .frame(width: size, height: size)
            .background(tint, in: Circle())
            .shadow(color: tint.opacity(0.3), radius: 10, y: 5)
            .keyframeAnimator(initialValue: CGFloat(1), trigger: reduceMotion ? "" : name) { content, scale in
                content.scaleEffect(scale)
            } keyframes: { _ in
                SpringKeyframe(1.18, duration: 0.15, spring: .snappy)
                SpringKeyframe(1, duration: 0.35, spring: .bouncy)
            }
    }
}

/// Games finished ahead by each player, with level games between.
private struct SplitBar: View {
    let first: Int
    let level: Int
    let second: Int

    var body: some View {
        GeometryReader { geo in
            let total = first + level + second
            let parts = [(first, Color.ink), (level, Color.inkTertiary.opacity(0.4)), (second, Color.sageDeep)]
                .filter { $0.0 > 0 }
            let usable = max(0, geo.size.width - CGFloat(max(0, parts.count - 1)) * 3)
            HStack(spacing: 3) {
                if total == 0 {
                    Capsule().fill(Color.canvas)
                } else {
                    ForEach(parts.indices, id: \.self) { index in
                        Capsule()
                            .fill(parts[index].1)
                            .frame(width: usable * CGFloat(parts[index].0) / CGFloat(total))
                    }
                }
            }
        }
        .accessibilityHidden(true)
    }
}

private struct VerdictChip: View {
    let text: String
    let tint: Color

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: "crown.fill")
                .font(.system(size: 11, weight: .semibold))
            Text(text)
                .font(.system(size: 14, weight: .medium))
                .lineLimit(1)
        }
        .foregroundStyle(.white)
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
        .background(tint, in: Capsule())
        .shadow(color: tint.opacity(0.3), radius: 10, y: 4)
    }
}

/// One measure for both players; the better figure sits in its player's pill.
private struct StatRow: View {
    let label: LocalizedStringKey
    let first: String
    let second: String
    let better: HeadToHead.Edge?

    var body: some View {
        HStack {
            pill(first, isBetter: better == .first, tint: .ink)
            Spacer(minLength: 6)
            Text(label)
                .font(.system(size: 13))
                .foregroundStyle(Color.inkSecondary)
                .lineLimit(1)
            Spacer(minLength: 6)
            pill(second, isBetter: better == .second, tint: .sageDeep)
        }
        .padding(.vertical, 3)
        .accessibilityElement(children: .combine)
    }

    private func pill(_ text: String, isBetter: Bool, tint: Color) -> some View {
        Text(text)
            .font(.system(size: 15, weight: isBetter ? .semibold : .regular).monospacedDigit())
            .foregroundStyle(isBetter ? Color.white : Color.ink)
            .lineLimit(1)
            .minimumScaleFactor(0.7)
            .contentTransition(.numericText())
            .frame(minWidth: 64)
            .padding(.vertical, 6)
            .padding(.horizontal, 6)
            .background(isBetter ? tint : Color.canvas, in: Capsule())
    }
}

/// Where each of the two finished, place by place, as paired bars.
private struct PlacesComparison: View {
    let first: String
    let second: String
    let result: HeadToHead
    let raised: Bool

    var body: some View {
        let peak = max(1, (result.first.places + result.second.places).max() ?? 1)
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 12) {
                EyebrowLabel("أين حلّ كلٌّ منهما")
                Spacer(minLength: 0)
                key(first, .ink)
                key(second, .sageDeep)
            }

            HStack(alignment: .bottom, spacing: 0) {
                ForEach(0..<4, id: \.self) { place in
                    VStack(spacing: 6) {
                        HStack(alignment: .bottom, spacing: 5) {
                            bar(result.first.places[place], peak: peak, tint: .ink)
                            bar(result.second.places[place], peak: peak, tint: .sageDeep)
                        }
                        .frame(height: 96, alignment: .bottom)
                        Text(placeNames[place])
                            .font(.system(size: 12))
                            .foregroundStyle(Color.inkSecondary)
                    }
                    .frame(maxWidth: .infinity)
                }
            }
        }
        .padding(18)
        .card(radius: 28)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text(summary))
    }

    private func key(_ name: String, _ tint: Color) -> some View {
        HStack(spacing: 4) {
            Circle().fill(tint).frame(width: 7, height: 7)
            Text(name)
                .font(.system(size: 11))
                .foregroundStyle(Color.inkSecondary)
                .lineLimit(1)
        }
    }

    private func bar(_ count: Int, peak: Int, tint: Color) -> some View {
        VStack(spacing: 3) {
            Text("\(count)")
                .font(.system(size: 11, weight: .medium).monospacedDigit())
                .foregroundStyle(count == 0 ? Color.inkTertiary : Color.ink)
                .contentTransition(.numericText(value: Double(count)))
            RoundedRectangle(cornerRadius: 5, style: .continuous)
                .fill(count == 0 ? Color.canvas : tint)
                .frame(width: 16, height: raised ? max(4, 72 * CGFloat(count) / CGFloat(peak)) : 4)
        }
    }

    private var summary: String {
        (0..<4).map { place in
            "\(placeNames[place]): \(first) \(result.first.places[place])، \(second) \(result.second.places[place])"
        }
        .joined(separator: ". ")
    }
}

/// One player's place and total in a game the two shared.
private struct MeetingResult: View {
    let result: HeadToHead.Meeting.Result
    let isAhead: Bool
    let tint: Color

    var body: some View {
        HStack(spacing: 8) {
            Text("\(result.place)")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(isAhead ? Color.white : Color.ink)
                .frame(width: 24, height: 24)
                .background(isAhead ? tint : Color.canvas, in: Circle())
            Text(result.score.formatted())
                .font(.system(size: 15).monospacedDigit())
                .foregroundStyle(isAhead ? Color.ink : Color.inkSecondary)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text("المركز \(result.place)، \(result.score)"))
    }
}

#Preview("Leaderboard") {
    StandingsView(games: [])
}
