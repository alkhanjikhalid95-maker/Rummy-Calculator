import SwiftUI

struct StartPageView: View {
    @Bindable var viewModel: GameViewModel
    @State private var showHistory = false
    @State private var showNameEditor = false
    @State private var showRules = false
    @State private var showJoin = false

    /// The seat whose name is being typed, if any.
    @State private var editingSeat: Int?
    /// The name a seat had when editing began — suggestions only filter once
    /// the player starts typing something different.
    @State private var nameAtEditStart = ""
    /// Bumped per seat to play its bubble-up.
    @State private var popTriggers = [0, 0, 0, 0]
    /// Bumped to focus the field and select its text.
    @State private var focusToken = 0
    /// Drives the entrance. It only nudges scale and offset — never opacity —
    /// so the page is fully drawn even if the animation never runs.
    @State private var appeared = false

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var isEditing: Bool { editingSeat != nil }

    private var seatedCount: Int {
        viewModel.playerNames.filter { !$0.trimmingCharacters(in: .whitespaces).isEmpty }.count
    }

    var body: some View {
        ZStack {
            AppBackground()
                .onTapGesture(perform: finishEditing)

            VStack(spacing: 16) {
                if !isEditing {
                    header
                        .transition(.move(edge: .top).combined(with: .opacity))

                    if viewModel.isLobbyOpen {
                        NearbyPlayersRow(players: viewModel.availablePlayers, onSeat: seatNearby)
                            .transition(.move(edge: .top).combined(with: .opacity))
                    }

                    if let paused = viewModel.pausedGame {
                        resumeCard(paused)
                            .transition(.move(edge: .top).combined(with: .opacity))
                    }
                }

                tableCard
                    .layoutPriority(1)

                if let seat = editingSeat {
                    seatEditor(seat: seat)
                        .transition(.move(edge: .bottom).combined(with: .opacity))
                }
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 8)
        }
        .sensoryFeedback(.selection, trigger: editingSeat)
        .animation(.spring(response: 0.45, dampingFraction: 0.85), value: viewModel.isLobbyOpen)
        .onAppear {
            // With sharing on, nearby phones can join while names are set.
            viewModel.openLobby()
            guard !appeared else { return }
            if reduceMotion {
                appeared = true
            } else {
                withAnimation(.spring(response: 0.7, dampingFraction: 0.82)) { appeared = true }
            }
        }
        .sheet(isPresented: $showHistory) {
            HistoryView(viewModel: viewModel)
        }
        .sheet(isPresented: $showNameEditor) {
            NameEditorView(presetNames: viewModel.presetNames)
        }
        .sheet(isPresented: $showRules) {
            RulesView(viewModel: viewModel)
        }
        .sheet(isPresented: $showJoin) {
            NearbyJoinView(guest: .shared)
        }
    }

    // MARK: - Header

    private var header: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack(alignment: .center) {
                Text("حاسبة الهاند")
                    .font(.system(size: 34, weight: .medium))
                    .foregroundStyle(Color.ink)
                Spacer()
                IconPill(systemName: "gearshape", label: "الإعدادات") {
                    showRules = true
                }
            }

            HStack(alignment: .center) {
                Text(Date.now, format: .dateTime.day().month(.wide).year())
                    .font(.system(size: 22, weight: .regular))
                    .foregroundStyle(Color.ink)
                Spacer()
                IconPill(systemName: "clock.arrow.circlepath", label: "سجل الألعاب", size: 42) {
                    showHistory = true
                }
            }
        }
        .padding(.horizontal, 8)
        .padding(.top, 8)
        .offset(y: appeared ? 0 : -10)
    }

    private func resumeCard(_ paused: Game) -> some View {
        Button {
            viewModel.resumeGame()
        } label: {
            HStack(spacing: 0) {
                VStack(alignment: .leading, spacing: 6) {
                    Text("لعبة غير منتهية")
                        .font(.system(size: 15))
                        .foregroundStyle(Color.ink)
                    Text("اللفة \((paused.currentRoundIndex ?? paused.maxRounds - 1) + 1)")
                        .font(.system(size: 32, weight: .light))
                        .foregroundStyle(Color.ink)
                    Text("\(formatDuration(viewModel.pausedElapsed)) · \(paused.players.map(\.name).joined(separator: "، "))")
                        .font(.system(size: 12))
                        .foregroundStyle(Color.inkSecondary)
                        .lineLimit(1)
                }
                .padding(.leading, 22)

                Spacer(minLength: 8)

                ZStack(alignment: .bottomTrailing) {
                    FloatingCards(width: 44)
                        .frame(width: 120, height: 96)
                    Image(systemName: "play.fill")
                        .font(.system(size: 18))
                        .foregroundStyle(.white)
                        .frame(width: 54, height: 54)
                        .background(Color.ink, in: Circle())
                        .shadow(color: .black.opacity(0.25), radius: 10, y: 5)
                        .offset(x: 4, y: 6)
                }
                .padding(.trailing, 22)
            }
            .frame(height: 124)
            .card(radius: 36)
        }
        .buttonStyle(PressableStyle(scale: 0.97))
        .accessibilityLabel(Text("استئناف اللعبة"))
    }

    // MARK: - Table card

    private var tableCard: some View {
        VStack(spacing: 0) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 2) {
                    EyebrowLabel("اللاعبون", onAura: true)
                    HStack(alignment: .firstTextBaseline, spacing: 4) {
                        Text("\(seatedCount)")
                            .font(.system(size: 48, weight: .light).monospacedDigit())
                            .contentTransition(.numericText(value: Double(seatedCount)))
                        Text("/ 4")
                            .font(.system(size: 20, weight: .light))
                            .opacity(0.7)
                    }
                    .foregroundStyle(.white)
                }
                Spacer()
                IconPill(systemName: "person.2", label: "الأسماء المحفوظة", onAura: true, size: 44) {
                    finishEditing()
                    showNameEditor = true
                }
            }
            .padding(.horizontal, 24)
            .padding(.top, 22)

            table
                .padding(.horizontal, 56)
                .padding(.top, 30)
                .padding(.bottom, 40)
                .frame(maxHeight: .infinity)

            if !isEditing {
                dock
                    .padding(.bottom, 20)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
        .background {
            AuraGradient()
                .clipShape(RoundedRectangle(cornerRadius: 40, style: .continuous))
                .contentShape(Rectangle())
                .onTapGesture(perform: finishEditing)
        }
        .shadow(color: Color.mauveDeep.opacity(0.25), radius: 24, y: 12)
        .scaleEffect(appeared ? 1 : 0.96)
    }

    private var table: some View {
        PokerTable(style: .aura) { index in
            seatView(index)
        } center: {
            VStack(spacing: 6) {
                Image(systemName: "hand.tap")
                    .font(.system(size: 20, weight: .light))
                Text(seatedCount == 4 ? "الطاولة جاهزة" : "اضغط على اللاعب لكتابة اسمه")
                    .font(.system(size: 13))
                    .multilineTextAlignment(.center)
                    .contentTransition(.opacity)
            }
            .foregroundStyle(Color.white.opacity(0.85))
            .opacity(isEditing ? 0 : 1)
            .allowsHitTesting(false)
        }
    }

    private func seatView(_ index: Int) -> some View {
        let name = viewModel.playerNames[index]
        let isActive = editingSeat == index

        return Button {
            beginEditing(seat: index)
        } label: {
            SeatBubble(
                name: name,
                seat: index,
                size: 60,
                style: .aura,
                isRaised: isActive,
                popTrigger: popTriggers[index],
                badge: viewModel.linkedSeats.contains(index) ? .linked : nil
            )
            .seatTag(edge: TableLayout.tagEdge(for: index)) {
                SeatTag(name: name, style: .aura, isHighlighted: isActive)
            }
        }
        .buttonStyle(PressableStyle(scale: 0.9))
        .zIndex(isActive ? 1 : 0)
        .scaleEffect(appeared ? 1 : 0.6)
        .animation(
            reduceMotion ? nil : .spring(response: 0.5, dampingFraction: 0.6).delay(0.15 + Double(index) * 0.08),
            value: appeared
        )
        .accessibilityLabel(Text(name.isEmpty ? "اللاعب \(index + 1)، بدون اسم" : "اللاعب \(index + 1)، \(name)"))
        .accessibilityHint(Text("تعديل الاسم"))
    }

    /// Glass dock: follow a nearby game, start, saved names.
    private var dock: some View {
        HStack(spacing: 14) {
            IconPill(systemName: "dot.radiowaves.left.and.right", label: "تابع لعبة على جوال قريب", onAura: true, size: 52) {
                showJoin = true
            }

            Button {
                viewModel.startGame()
            } label: {
                Image(systemName: "play.fill")
                    .font(.system(size: 22))
                    .foregroundStyle(.white)
                    .frame(width: 66, height: 66)
                    .background(Color.ink, in: Circle())
                    .shadow(color: .black.opacity(0.25), radius: 12, y: 6)
            }
            .buttonStyle(PressableStyle(scale: 0.9))
            .accessibilityLabel(Text(viewModel.hasPausedGame ? "لعبة جديدة" : "ابدأ اللعبة"))
            .sensoryFeedback(.impact(weight: .medium), trigger: viewModel.isGameStarted)

            IconPill(systemName: "list.bullet", label: "الأسماء المحفوظة", onAura: true, size: 52) {
                showNameEditor = true
            }
        }
        .padding(8)
        .glass(in: Capsule())
    }

    // MARK: - Editing

    private func beginEditing(seat: Int) {
        popTriggers[seat] += 1
        nameAtEditStart = viewModel.playerNames[seat]
        withAnimation(.spring(response: 0.42, dampingFraction: 0.84)) {
            editingSeat = seat
        }
        focusToken += 1
    }

    /// Moves to the next seat, or closes the editor after the last one.
    private func advance(from seat: Int) {
        if seat < 3 {
            beginEditing(seat: seat + 1)
        } else {
            finishEditing()
        }
    }

    private func finishEditing() {
        guard isEditing else { return }
        for index in viewModel.playerNames.indices {
            let trimmed = viewModel.playerNames[index].trimmingCharacters(in: .whitespaces)
            if trimmed != viewModel.playerNames[index] {
                viewModel.setSeatName(index, trimmed)
            }
        }
        withAnimation(.spring(response: 0.42, dampingFraction: 0.86)) {
            editingSeat = nil
        }
        UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
    }

    /// Seats a nearby player: into the seat being edited, else the first
    /// empty one.
    private func seatNearby(_ player: LobbyPlayer) {
        let target = editingSeat ?? viewModel.playerNames.firstIndex {
            $0.trimmingCharacters(in: .whitespaces).isEmpty
        }
        guard let seat = target else { return }
        viewModel.seatPlayer(player.id, inSeat: seat)
        popTriggers[seat] += 1
        if editingSeat != nil {
            advance(from: seat)
        }
    }

    /// Nearby players not yet seated, narrowed by what has been typed.
    private func nearbySuggestions(for seat: Int) -> [LobbyPlayer] {
        let typed = viewModel.playerNames[seat].trimmingCharacters(in: .whitespaces)
        let query = typed == nameAtEditStart ? "" : typed.lowercased()
        return viewModel.availablePlayers.filter { query.isEmpty || $0.name.lowercased().contains(query) }
    }

    /// Saved names not already seated elsewhere, narrowed by what has been typed.
    private func suggestions(for seat: Int) -> [String] {
        let taken = Set(
            viewModel.playerNames.enumerated()
                .filter { $0.offset != seat }
                .map { $0.element.lowercased() }
        )
        let typed = viewModel.playerNames[seat].trimmingCharacters(in: .whitespaces)
        let query = typed == nameAtEditStart ? "" : typed.lowercased()
        return viewModel.presetNames.all.filter { name in
            !taken.contains(name.lowercased())
                && (query.isEmpty || name.lowercased().contains(query))
                && name.lowercased() != typed.lowercased()
        }
    }

    private func seatEditor(seat: Int) -> some View {
        VStack(spacing: 14) {
            HStack(spacing: 12) {
                SeatBubble(name: viewModel.playerNames[seat], seat: seat, size: 40, style: .paper, isRaised: true)
                VStack(alignment: .leading, spacing: 2) {
                    Text("اللاعب \(seat + 1)")
                        .font(.system(size: 17, weight: .medium))
                        .foregroundStyle(Color.ink)
                    Text("اكتب الاسم أو اختر من المحفوظة")
                        .font(.system(size: 12))
                        .foregroundStyle(Color.inkSecondary)
                }
                Spacer()
                Button("تم", action: finishEditing)
                    .font(.system(size: 15, weight: .medium))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 18)
                    .padding(.vertical, 9)
                    .background(Color.ink, in: Capsule())
                    .buttonStyle(PressableStyle())
            }

            SelectAllTextField(
                text: Binding(
                    get: { viewModel.playerNames[seat] },
                    set: { viewModel.setSeatName(seat, $0) }
                ),
                placeholder: "اسم اللاعب",
                focusToken: focusToken,
                returnKey: seat < 3 ? .next : .done,
                onSubmit: { advance(from: seat) }
            )
            .frame(height: 54)
            .padding(.horizontal, 10)
            .background(Color.canvas, in: Capsule())

            let nearby = nearbySuggestions(for: seat)
            let names = suggestions(for: seat)
            if !nearby.isEmpty || !names.isEmpty {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        // Phones at the table first: seating one links the seat to it.
                        ForEach(nearby) { player in
                            Button {
                                seatNearby(player)
                            } label: {
                                HStack(spacing: 6) {
                                    Image(systemName: "dot.radiowaves.left.and.right")
                                        .font(.system(size: 11))
                                    Text(player.name)
                                        .font(.system(size: 14))
                                }
                                .foregroundStyle(.white)
                                .padding(.horizontal, 14)
                                .padding(.vertical, 9)
                                .background(Color.ink, in: Capsule())
                            }
                            .buttonStyle(PressableStyle())
                            .transition(.scale.combined(with: .opacity))
                            .accessibilityLabel(Text("\(player.name)، لاعب قريب"))
                        }
                        ForEach(names, id: \.self) { name in
                            Button {
                                viewModel.setSeatName(seat, name)
                                popTriggers[seat] += 1
                                advance(from: seat)
                            } label: {
                                Text(name)
                                    .font(.system(size: 14))
                                    .foregroundStyle(Color.ink)
                                    .padding(.horizontal, 16)
                                    .padding(.vertical, 9)
                                    .background(Color.canvas, in: Capsule())
                            }
                            .buttonStyle(PressableStyle())
                        }
                    }
                    .padding(.horizontal, 2)
                }
                .scrollClipDisabled()
            }
        }
        .padding(18)
        .card(radius: 32)
    }
}

// MARK: - Nearby players

/// Phones that joined this table and are waiting for a seat. Each pops in
/// with the bubble-up; tap one to seat it.
struct NearbyPlayersRow: View {
    let players: [LobbyPlayer]
    let onSeat: (LobbyPlayer) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 6) {
                Image(systemName: "dot.radiowaves.left.and.right")
                    .font(.system(size: 12))
                    .symbolEffect(.variableColor.iterative, isActive: players.isEmpty)
                Text(players.isEmpty ? "بانتظار اللاعبين القريبين" : "لاعبون قريبون · اضغط لإجلاسهم")
                    .font(.system(size: 13))
                    .contentTransition(.opacity)
            }
            .foregroundStyle(Color.inkSecondary)
            .padding(.horizontal, 20)

            if players.isEmpty {
                Text("على جوال كل لاعب: «تابع لعبة على جوال قريب»")
                    .font(.system(size: 12))
                    .foregroundStyle(Color.inkTertiary)
                    .padding(.horizontal, 20)
            } else {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 14) {
                        ForEach(players) { player in
                            NearbyPlayerBubble(player: player) { onSeat(player) }
                                .transition(.scale(scale: 0.3).combined(with: .opacity))
                        }
                    }
                    .padding(.horizontal, 20)
                    .padding(.vertical, 6)
                }
                .scrollClipDisabled()
            }
        }
        .padding(.vertical, 12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .card(radius: 28)
        .animation(.spring(response: 0.45, dampingFraction: 0.7), value: players)
    }
}

/// One waiting player. Plays the bubble-up as it arrives.
private struct NearbyPlayerBubble: View {
    let player: LobbyPlayer
    let action: () -> Void
    @State private var pop = 0

    var body: some View {
        Button(action: action) {
            VStack(spacing: 6) {
                SeatBubble(name: player.name, seat: 0, size: 46, style: .paper, popTrigger: pop, badge: .linked)
                Text(player.name)
                    .font(.system(size: 12))
                    .foregroundStyle(Color.ink)
                    .lineLimit(1)
                    .frame(maxWidth: 72)
            }
        }
        .buttonStyle(PressableStyle(scale: 0.9))
        .accessibilityLabel(Text(player.name))
        .accessibilityHint(Text("إجلاسه في أول مقعد فارغ"))
        .onAppear { pop += 1 }
    }
}

// MARK: - Rules View

struct RulesView: View {
    @Bindable var viewModel: GameViewModel
    @Environment(\.dismiss) private var dismiss
    @State private var myName = PlayerIdentity.preferredName ?? ""

    var body: some View {
        NavigationStack {
            List {
                Section {
                    Toggle(isOn: $viewModel.noPenaltyForDroppedCard) {
                        VStack(alignment: .leading, spacing: 4) {
                            Text("هند من السحبة")
                            Text("الفوز بدون استخدام ورقة النزول لا يترتب عليه جزاء +100")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }

                    Toggle(isOn: $viewModel.deckWinEnabled) {
                        VStack(alignment: .leading, spacing: 4) {
                            Text("وضع السحبة")
                            Text("عند اختيار الفائز، يُسأل عن استخدام السحبة لكل لفة على حدة")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                } header: {
                    Text("قواعد اللعبة")
                }

                Section {
                    Toggle(isOn: Binding(
                        get: { viewModel.nearbyHost.isEnabled },
                        set: { viewModel.setNearbySharing($0) }
                    )) {
                        VStack(alignment: .leading, spacing: 4) {
                            Text("مشاركة اللعبة عبر البلوتوث")
                            Text("يتابع اللاعبون القريبون النتائج على شاشة القفل في جوالاتهم")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }

                    HStack {
                        Text("اسمي")
                        TextField("اسمك في اللعبة", text: $myName)
                            .multilineTextAlignment(.trailing)
                            .submitLabel(.done)
                            .onSubmit(saveMyName)
                    }
                } header: {
                    Text("اللاعبون القريبون")
                } footer: {
                    Text("عند وجود اسمك على الطاولة يتعرف عليك التطبيق تلقائياً، ويعرض لك من اللفة السابعة نوع الفوز الذي تحتاجه لتتصدر.")
                }
            }
            .tint(Color.ink)
            .scrollContentBackground(.hidden)
            .background(Color.canvas)
            .navigationTitle("الإعدادات")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("تم") {
                        saveMyName()
                        dismiss()
                    }
                    .fontWeight(.medium)
                }
            }
        }
        .themedSheet()
    }

    private func saveMyName() {
        let trimmed = myName.trimmingCharacters(in: .whitespaces)
        guard trimmed != (PlayerIdentity.preferredName ?? "") else { return }
        PlayerIdentity.preferredName = trimmed.isEmpty ? nil : trimmed
        // A host this phone follows should see the new name.
        NearbyGuest.shared.refreshProfile()
    }
}

#Preview {
    StartPageView(viewModel: GameViewModel(sessionStore: .ephemeral))
}
