import SwiftUI

/// A player's view of a game kept on someone else's phone: their own total
/// over the aura, the table with live totals, and — from round 7 — what they
/// need to take the lead.
struct FollowingGameView: View {
    var guest: NearbyGuest
    @State private var popTriggers = [0, 0, 0, 0]
    @State private var confirmLeave = false

    var body: some View {
        ZStack {
            AuraGradient()
                .ignoresSafeArea()

            ScrollView {
                VStack(spacing: 18) {
                    topBar
                    if let snapshot = guest.snapshot, snapshot.isLobby {
                        lobbyHero(snapshot)
                        lobbyStatus(snapshot)
                        tableCard(snapshot)
                    } else if let snapshot = guest.snapshot {
                        hero(snapshot)
                        tableCard(snapshot)
                        adviceSection(snapshot)
                    } else {
                        VStack(spacing: 18) {
                            RadarPulse(isActive: true, onAura: true)
                                .frame(height: 200)
                            Text("جارٍ الاتصال بحامل النتائج…")
                                .font(.system(size: 16))
                                .foregroundStyle(.white)
                        }
                        .padding(.top, 120)
                    }
                }
                .padding(.horizontal, 16)
                .padding(.bottom, 30)
            }
            .scrollIndicators(.hidden)
        }
        .animation(.spring(response: 0.45, dampingFraction: 0.85), value: guest.snapshot)
        .sensoryFeedback(.success, trigger: guest.snapshot?.round)
        .confirmationDialog("التوقف عن متابعة هذه اللعبة؟", isPresented: $confirmLeave, titleVisibility: .visible) {
            Button("مغادرة", role: .destructive) { guest.leave() }
            Button("إلغاء", role: .cancel) {}
        }
    }

    // MARK: - Pieces

    private var topBar: some View {
        HStack {
            IconPill(systemName: "xmark", label: "مغادرة", onAura: true) { confirmLeave = true }
            Spacer()
            Text(guest.snapshot?.isLobby == true ? "طاولة قريبة" : "تتابع لعبة قريبة")
                .font(.system(size: 18))
                .foregroundStyle(.white)
            Spacer()
            GlassCircle(
                systemName: guest.isConnected ? "dot.radiowaves.left.and.right" : "antenna.radiowaves.left.and.right.slash",
                onAura: true
            )
            .symbolEffect(.variableColor.iterative, isActive: guest.isConnected)
            .accessibilityLabel(Text(guest.isConnected ? "متصل" : "غير متصل"))
        }
        .padding(.top, 4)
    }

    // MARK: - Lobby

    private func lobbyHero(_ snapshot: TableSnapshot) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            EyebrowLabel("مرحباً", onAura: true)
            Text(PlayerIdentity.preferredName ?? "")
                .font(.system(size: 52, weight: .light))
                .foregroundStyle(.white)
                .lineLimit(1)
                .minimumScaleFactor(0.5)
            GlassTag(
                text: guest.isConnected ? "متصل بالمضيف" : "نعيد الاتصال…",
                systemImage: guest.isConnected ? "checkmark" : "arrow.triangle.2.circlepath"
            )
            .padding(.top, 6)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 6)
    }

    /// Where this phone stands in the lobby: being introduced, waiting for a
    /// seat, or seated and waiting for the start.
    private func lobbyStatus(_ snapshot: TableSnapshot) -> some View {
        let seat = guest.mySeat.flatMap { snapshot.names.indices.contains($0) ? $0 : nil }

        return HStack(alignment: .center, spacing: 14) {
            Group {
                if let seat {
                    SeatBubble(name: snapshot.names[seat], seat: seat, size: 48, style: .paper, isRaised: true)
                } else {
                    WaitingDots()
                        .frame(width: 48, height: 48)
                        .background(Color.canvas, in: Circle())
                }
            }
            VStack(alignment: .leading, spacing: 3) {
                Text(lobbyHeadline(seat: seat, snapshot: snapshot))
                    .font(.system(size: 18))
                    .foregroundStyle(Color.ink)
                    .contentTransition(.opacity)
                Text(seat == nil ? "سيظهر اسمك في مقعدك عندما يختاره" : "تبدأ المتابعة تلقائياً عند بدء اللعبة")
                    .font(.system(size: 13))
                    .foregroundStyle(Color.inkSecondary)
            }
            Spacer(minLength: 0)
        }
        .padding(20)
        .card(radius: 30)
        .sensoryFeedback(.success, trigger: seat)
        .animation(.spring(response: 0.45, dampingFraction: 0.8), value: seat)
    }

    private func lobbyHeadline(seat: Int?, snapshot: TableSnapshot) -> String {
        if let seat {
            return "مقعدك: \(snapshot.names[seat]) · اللاعب \(seat + 1)"
        }
        if !guest.isKnownToHost {
            return "نعرّف المضيف بك…"
        }
        return "بانتظار المضيف ليختار مقعدك"
    }

    // MARK: - Game

    private func hero(_ snapshot: TableSnapshot) -> some View {
        let mine = guest.mySeat.flatMap { snapshot.totals.indices.contains($0) ? snapshot.totals[$0] : nil }

        return VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 2) {
                    EyebrowLabel(mine == nil ? "اختر مقعدك في الطاولة" : "نتيجتك", onAura: true)
                    Text((mine ?? 0).formatted())
                        .font(.system(size: 64, weight: .light).monospacedDigit())
                        .foregroundStyle(.white)
                        .contentTransition(.numericText(value: Double(mine ?? 0)))
                        .opacity(mine == nil ? 0.4 : 1)
                }
                Spacer()
                VStack(alignment: .trailing, spacing: 10) {
                    if let start = snapshot.startedAt, !snapshot.isOver {
                        HStack(spacing: 6) {
                            Image(systemName: "clock")
                                .font(.system(size: 12))
                            Text(start, style: .timer)
                                .monospacedDigit()
                        }
                        .font(.system(size: 15))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 16)
                        .padding(.vertical, 9)
                        .glass(in: Capsule())
                    } else {
                        GlassTag(text: formatDuration(snapshot.elapsed), systemImage: "clock")
                    }
                    GlassTag(
                        text: guest.isConnected ? "متصل" : "نعيد الاتصال…",
                        systemImage: guest.isConnected ? "checkmark" : "arrow.triangle.2.circlepath"
                    )
                }
            }

            HStack(spacing: 10) {
                GlassTag(text: snapshot.isOver ? "انتهت اللعبة" : "اللفة \(snapshot.round) من \(snapshot.maxRounds)")
                if let advice = guest.advice {
                    GlassTag(text: "المركز \(advice.rank)", systemImage: advice.rank == 1 ? "crown" : nil)
                }
            }
        }
        .padding(.horizontal, 6)
    }

    private func tableCard(_ snapshot: TableSnapshot) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text(snapshot.isLobby ? "الطاولة" : (guest.mySeat == nil ? "اضغط على مقعدك" : "الطاولة"))
                    .font(.system(size: 18))
                    .foregroundStyle(Color.ink)
                Spacer()
                if let winner = snapshot.lastWinner, snapshot.names.indices.contains(winner), let type = snapshot.lastWinType {
                    InkChip(text: "آخر لفة: \(snapshot.names[winner]) · \(type)")
                }
            }
            .padding(.horizontal, 22)
            .padding(.top, 22)

            GameTableView(
                seats: snapshot.names.indices.map { index in
                    TableSeat(name: snapshot.names[index], total: snapshot.totals[index])
                },
                leader: snapshot.round > 1 || snapshot.isOver ? snapshot.leaderIndex : nil,
                dealer: snapshot.dealer,
                mySeat: guest.mySeat,
                linked: snapshot.linkedSeats.subtracting(guest.mySeat.map { [$0] } ?? []),
                rounds: roundCards(snapshot),
                round: snapshot.round,
                maxRounds: snapshot.maxRounds,
                isOver: snapshot.isOver,
                isLobby: snapshot.isLobby,
                popTriggers: popTriggers,
                // In the lobby the host seats players; tapping is the fallback
                // for games whose names were typed by hand.
                onSeatTap: snapshot.isLobby || guest.seatFromHost ? nil : { index in
                    popTriggers[index] += 1
                    guest.chooseSeat(guest.mySeat == index ? nil : index)
                }
            )
        }
        .card(radius: 36)
    }

    /// Played rounds filled in — only the latest carries its winner, since the
    /// board shared over Bluetooth holds totals rather than every round.
    private func roundCards(_ snapshot: TableSnapshot) -> [RoundCard] {
        let played = snapshot.isOver ? snapshot.maxRounds : snapshot.round - 1
        return (0..<snapshot.maxRounds).map { index in
            if index < played {
                let isLatest = index == played - 1
                return RoundCard(id: index, state: .played(
                    winner: isLatest ? snapshot.lastWinner : nil,
                    label: isLatest ? snapshot.lastWinType : nil
                ))
            }
            return RoundCard(id: index, state: index == played ? .current : .upcoming)
        }
    }

    @ViewBuilder
    private func adviceSection(_ snapshot: TableSnapshot) -> some View {
        if guest.mySeat == nil {
            VStack(alignment: .leading, spacing: 8) {
                Text("أي لاعب أنت؟")
                    .font(.system(size: 18))
                    .foregroundStyle(Color.ink)
                Text("اضغط على مقعدك في الطاولة لتظهر نتيجتك على شاشة القفل، وما تحتاجه لتتصدر من اللفة السابعة.")
                    .font(.system(size: 14))
                    .foregroundStyle(Color.inkSecondary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(22)
            .card(radius: 32)
        } else if let advice = guest.advice {
            AdviceCard(advice: advice, firstAdviceRound: PredictionEngine.firstAdviceRound)
        }
    }
}

// MARK: - Waiting dots

/// Three dots breathing in turn — someone else's move. Still and fully drawn
/// under Reduce Motion.
private struct WaitingDots: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        TimelineView(.animation(minimumInterval: 1 / 30, paused: reduceMotion)) { timeline in
            let t = reduceMotion ? 0 : timeline.date.timeIntervalSinceReferenceDate
            HStack(spacing: 4) {
                ForEach(0..<3, id: \.self) { dot in
                    let wave = (sin(t * 4 - Double(dot) * 0.8) + 1) / 2
                    Circle()
                        .fill(Color.ink)
                        .frame(width: 6, height: 6)
                        .scaleEffect(reduceMotion ? 1 : 0.7 + wave * 0.5)
                }
            }
        }
        .accessibilityHidden(true)
    }
}

// MARK: - Advice card

/// The player's standing and, from round 7, the wins they need — in full.
struct AdviceCard: View {
    let advice: SeatAdvice
    let firstAdviceRound: Int

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .top, spacing: 12) {
                Image(systemName: icon)
                    .font(.system(size: 16))
                    .foregroundStyle(.white)
                    .frame(width: 40, height: 40)
                    .background(Color.ink, in: Circle())
                VStack(alignment: .leading, spacing: 3) {
                    Text(advice.headline)
                        .font(.system(size: 19))
                        .foregroundStyle(Color.ink)
                    Text(subtitle)
                        .font(.system(size: 13))
                        .foregroundStyle(Color.inkSecondary)
                }
                Spacer(minLength: 0)
                Text("#\(advice.rank)")
                    .font(.system(size: 28, weight: .light).monospacedDigit())
                    .foregroundStyle(Color.ink)
                    .contentTransition(.numericText(value: Double(advice.rank)))
            }

            if advice.hasPlan {
                FlowLayout(spacing: 8) {
                    ForEach(advice.needs, id: \.self) { need in
                        InkChip(text: need.count > 1 ? "\(need.label) ×\(need.count)" : need.label)
                            .transition(.scale.combined(with: .opacity))
                    }
                }
                Text(planExplanation)
                    .font(.system(size: 12))
                    .foregroundStyle(Color.inkSecondary)
            }
        }
        .padding(20)
        .frame(maxWidth: .infinity, alignment: .leading)
        .card(radius: 30)
        .animation(.spring(response: 0.4, dampingFraction: 0.8), value: advice)
    }

    private var icon: String {
        switch advice.kind {
        case .leading: return "crown"
        case .overtake: return "scope"
        case .tie: return "equal"
        case .outOfReach: return "hand.raised"
        case .behind: return "chart.bar"
        case .finished: return advice.rank == 1 ? "trophy" : "flag.checkered"
        }
    }

    private var subtitle: String {
        switch advice.kind {
        case .behind:
            return "\(advice.detail) · الخطة من اللفة \(firstAdviceRound)"
        case .overtake, .tie:
            let standing = advice.gap == 0 ? "متعادل مع المتصدر" : "خلف المتصدر بـ \(advice.gap)"
            return "\(standing) · باقي \(advice.roundsLeft) لفات"
        default:
            return advice.detail
        }
    }

    private var planExplanation: String {
        let wins = advice.totalWins
        let rounds = advice.roundsLeft
        let lead = advice.kind == .tie ? "للتعادل" : "لتتصدر"
        return "اربح \(wins) من \(rounds) لفات متبقية بهذه الأنواع \(lead) — بافتراض أن المتصدر لا يربح لفة. جزاء +100 غير محسوب."
    }
}
