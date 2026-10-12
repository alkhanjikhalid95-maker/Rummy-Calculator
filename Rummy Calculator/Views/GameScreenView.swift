import SwiftUI

/// The game in progress: the leader and a chart of everyone's totals over the
/// aura, then the table — tap the player who won the round.
struct GameScreenView: View {
    @Bindable var viewModel: GameViewModel
    @State private var showWinnerPopup = false
    @State private var showNearby = false
    @State private var popTriggers = [0, 0, 0, 0]
    /// Keeps the celebration from re-opening every time the board reappears
    /// after the player has dismissed it. Reset when the board is playable again.
    @State private var celebrationShownForThisGame = false

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var boardAnimation: Animation? {
        reduceMotion ? nil : .spring(response: 0.5, dampingFraction: 0.82)
    }

    var body: some View {
        ZStack(alignment: .bottom) {
            AuraGradient()
                .ignoresSafeArea()

            ScrollView {
                VStack(spacing: 18) {
                    topBar
                    hero
                    tableCard
                    shortcuts
                }
                .padding(.horizontal, 16)
                .padding(.bottom, 120)
            }
            .scrollIndicators(.hidden)

            dock
                .padding(.bottom, 8)

            if showWinnerPopup {
                winnerOverlay
            }
        }
        .animation(boardAnimation, value: viewModel.rounds)
        .animation(boardAnimation, value: viewModel.isGameOver)
        .animation(boardAnimation, value: viewModel.predictionsActive)
        .sensoryFeedback(.success, trigger: viewModel.scoreEvent)
        .sheet(isPresented: $viewModel.showWinnerPicker) {
            WinnerPickerView(viewModel: viewModel)
                .presentationDetents([.height(620), .large])
        }
        .sheet(isPresented: $viewModel.showScoreSheet) {
            ScoreSheetView(viewModel: viewModel)
                .presentationDetents([.large])
        }
        .sheet(isPresented: $viewModel.showCalculator) {
            MiniCalculatorView()
                .presentationDetents([.height(640), .large])
        }
        .sheet(isPresented: $viewModel.showPredictions) {
            PredictionView(viewModel: viewModel)
                .presentationDetents([.large])
        }
        .sheet(isPresented: $showNearby) {
            NearbyHostSheet(viewModel: viewModel)
                .presentationDetents([.large])
        }
        .onAppear {
            // `onChange` alone misses a board that is already finished when it
            // appears — resuming a completed game, for one.
            if viewModel.isGameOver && !celebrationShownForThisGame {
                showWinnerPopup = true
                celebrationShownForThisGame = true
            }
        }
        .onChange(of: viewModel.isGameOver) { _, isOver in
            if isOver {
                withAnimation(.easeOut(duration: 0.3)) { showWinnerPopup = true }
                celebrationShownForThisGame = true
            } else {
                celebrationShownForThisGame = false
            }
        }
    }

    // MARK: - Top bar

    private var topBar: some View {
        HStack {
            IconPill(systemName: "chevron.left", label: "إيقاف مؤقت", onAura: true) {
                viewModel.pauseGame()
            }
            Spacer()
            Text(viewModel.isGameOver ? "انتهت اللعبة" : "اللفة \(viewModel.currentRoundNumber) من 9")
                .font(.system(size: 18, weight: .regular))
                .foregroundStyle(.white)
                .contentTransition(.numericText())
            Spacer()
            nearbyButton
        }
        .padding(.top, 4)
    }

    private var nearbyButton: some View {
        let host = viewModel.nearbyHost
        let live = host.status == .live
        return Button {
            showNearby = true
        } label: {
            GlassCircle(systemName: "dot.radiowaves.left.and.right", isActive: live, onAura: true)
                .symbolEffect(.variableColor.iterative, isActive: live && !reduceMotion)
                .overlay(alignment: .topTrailing) {
                    if host.followerCount > 0 {
                        Text("\(host.followerCount)")
                            .font(.system(size: 10, weight: .semibold))
                            .foregroundStyle(.white)
                            .frame(width: 18, height: 18)
                            .background(Color.ember, in: Circle())
                            .offset(x: 2, y: -2)
                            .transition(.scale)
                    }
                }
        }
        .buttonStyle(PressableStyle(scale: 0.9))
        .accessibilityLabel(Text("اللاعبون القريبون"))
        .accessibilityValue(Text(live ? "المشاركة تعمل" : "المشاركة متوقفة"))
        .animation(.spring(response: 0.3, dampingFraction: 0.6), value: host.followerCount)
    }

    // MARK: - Hero

    private var hero: some View {
        let leader = viewModel.lastCompletedRoundIndex == nil ? nil : viewModel.leaderIndex
        let leaderTotal = leader.map { viewModel.totalScore(playerIndex: $0) }

        return VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 2) {
                    EyebrowLabel(viewModel.isGameOver ? "الفائز" : (leader == nil ? "لم تبدأ اللفات بعد" : "المتصدر"), onAura: true)
                    Text(leaderTotal.map { $0.formatted() } ?? "0")
                        .font(.system(size: 64, weight: .light).monospacedDigit())
                        .foregroundStyle(.white)
                        .contentTransition(.numericText(value: Double(leaderTotal ?? 0)))
                        .lineLimit(1)
                        .minimumScaleFactor(0.6)
                }
                Spacer()
                VStack(alignment: .trailing, spacing: 10) {
                    GlassTag(text: viewModel.timerString, systemImage: "clock", font: .system(size: 15).monospacedDigit())
                    if viewModel.canShowPredictions {
                        Button {
                            if viewModel.predictionsActive {
                                viewModel.predictionsActive = false
                            } else {
                                viewModel.predictionsActive = true
                                viewModel.showPredictions = true
                            }
                        } label: {
                            GlassCircle(
                                systemName: viewModel.predictionsActive ? "lightbulb.fill" : "lightbulb",
                                isActive: viewModel.predictionsActive,
                                onAura: true,
                                size: 42
                            )
                            .symbolEffect(.bounce, value: viewModel.predictionsActive)
                        }
                        .buttonStyle(PressableStyle(scale: 0.9))
                        .accessibilityLabel(Text("التوقعات"))
                        .transition(.scale.combined(with: .opacity))
                    }
                }
            }

            ScoreChart(
                series: viewModel.scoreSeries,
                names: viewModel.players.map(\.name),
                leader: leader,
                maxRounds: viewModel.game?.maxRounds ?? 9,
                showsStandings: true
            )
            .frame(height: 164)
        }
        .padding(.horizontal, 6)
    }

    // MARK: - Table

    private var tableCard: some View {
        let lastRound = viewModel.lastRoundScores
        let currentRound = viewModel.game?.currentRoundIndex
        let dealer = viewModel.isGameOver ? nil : viewModel.lastCompletedRoundIndex.flatMap { viewModel.resolvedKhabasIndex(throughRound: $0) }

        return VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .center) {
                Text(viewModel.isGameOver ? "النتيجة النهائية" : "من فاز في اللفة \(viewModel.currentRoundNumber)؟")
                    .font(.system(size: 18, weight: .regular))
                    .foregroundStyle(Color.ink)
                    .contentTransition(.numericText())
                Spacer()
                if let dealer, viewModel.players.indices.contains(dealer) {
                    InkChip(text: "خباص · \(viewModel.players[dealer].name)")
                        .id(dealer)
                        .transition(.push(from: .bottom))
                }
            }
            .padding(.horizontal, 22)
            .padding(.top, 22)

            GameTableView(
                seats: viewModel.players.indices.map { index in
                    TableSeat(
                        name: viewModel.players[index].name,
                        total: viewModel.totalScore(playerIndex: index),
                        lastRound: lastRound?[index],
                        hint: currentRound.flatMap { viewModel.predictionLabel(roundIndex: $0, playerIndex: index) }
                    )
                },
                leader: viewModel.lastCompletedRoundIndex == nil ? nil : viewModel.leaderIndex,
                dealer: dealer,
                mySeat: viewModel.localSeatIndex,
                linked: viewModel.linkedSeats,
                rounds: viewModel.roundCards,
                round: viewModel.currentRoundNumber,
                maxRounds: viewModel.game?.maxRounds ?? 9,
                isOver: viewModel.isGameOver,
                roundTrigger: viewModel.scoreEvent,
                popTriggers: popTriggers,
                onSeatTap: { seat in
                    guard !viewModel.isGameOver else {
                        viewModel.showScoreSheet = true
                        return
                    }
                    popTriggers[seat] += 1
                    // Let the bubble-up play before the sheet covers it.
                    Task {
                        try? await Task.sleep(for: .milliseconds(reduceMotion ? 0 : 240))
                        viewModel.tapColumn(playerIndex: seat)
                    }
                }
            )
        }
        .card(radius: 36)
    }

    // MARK: - Shortcuts

    private var shortcuts: some View {
        HStack(spacing: 12) {
            shortcut(
                icon: "lightbulb",
                title: "التوقعات",
                subtitle: viewModel.canShowPredictions ? "ما يحتاجه كل لاعب" : "تفتح في اللفة 7",
                enabled: viewModel.canShowPredictions
            ) {
                viewModel.predictionsActive = true
                viewModel.showPredictions = true
            }

            shortcut(
                icon: "dot.radiowaves.left.and.right",
                title: "القريبون",
                subtitle: nearbySubtitle,
                enabled: true
            ) {
                showNearby = true
            }
        }
    }

    private var nearbySubtitle: String {
        let host = viewModel.nearbyHost
        guard host.status == .live else { return "مشاركة النتائج" }
        return host.followerCount == 0 ? "بانتظار اللاعبين" : "يتابعك \(host.followerCount)"
    }

    private func shortcut(icon: String, title: String, subtitle: String, enabled: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 10) {
                Image(systemName: icon)
                    .font(.system(size: 17))
                    .foregroundStyle(enabled ? Color.ink : Color.inkTertiary)
                    .frame(width: 38, height: 38)
                    .background(Color.canvas, in: Circle())
                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(.system(size: 16, weight: .medium))
                        .foregroundStyle(enabled ? Color.ink : Color.inkTertiary)
                    Text(subtitle)
                        .font(.system(size: 12))
                        .foregroundStyle(Color.inkSecondary)
                        .lineLimit(1)
                        .contentTransition(.opacity)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(18)
            .card(radius: 28)
        }
        .buttonStyle(PressableStyle(scale: 0.96))
        .disabled(!enabled)
    }

    // MARK: - Dock

    /// Glass dock: score grid, the primary action, calculator.
    private var dock: some View {
        HStack(spacing: 14) {
            IconPill(systemName: "list.number", label: "جدول النتائج", onAura: true, size: 52) {
                viewModel.showScoreSheet = true
            }

            Button {
                if viewModel.isGameOver {
                    showWinnerPopup = false
                    withAnimation(boardAnimation) { viewModel.restartGame() }
                } else {
                    viewModel.openWinnerPicker()
                }
            } label: {
                Image(systemName: viewModel.isGameOver ? "arrow.counterclockwise" : "plus")
                    .font(.system(size: 24, weight: .light))
                    .foregroundStyle(.white)
                    .frame(width: 66, height: 66)
                    .background(Color.ink, in: Circle())
                    .shadow(color: .black.opacity(0.25), radius: 12, y: 6)
                    .contentTransition(.symbolEffect(.replace))
            }
            .buttonStyle(PressableStyle(scale: 0.9))
            .accessibilityLabel(Text(viewModel.isGameOver ? "إعادة اللعب" : "تسجيل الفائز"))

            if viewModel.isGameOver {
                IconPill(systemName: "person.2", label: "لاعبون جدد", onAura: true, size: 52) {
                    showWinnerPopup = false
                    viewModel.newGame()
                }
                .transition(.scale.combined(with: .opacity))
            } else {
                IconPill(systemName: "plus.forwardslash.minus", label: "حاسبة النزول", onAura: true, size: 52) {
                    viewModel.showCalculator = true
                }
                .transition(.scale.combined(with: .opacity))
            }
        }
        .padding(8)
        .glass(in: Capsule())
    }

    // MARK: - Winner Overlay

    private var winnerOverlay: some View {
        WinnerCelebrationView(
            winnerName: viewModel.gameWinnerName ?? "",
            winnerScore: viewModel.gameWinnerScore,
            elapsed: viewModel.timerString,
            onDismiss: { showWinnerPopup = false }
        )
        .transition(.opacity)
    }
}

#Preview {
    let vm = GameViewModel(sessionStore: .ephemeral)
    vm.playerNames = ["Khalid", "Hamad", "Ali", "Saud"]
    vm.startGame()
    vm.selectWinner(playerIndex: 1, winType: .color)
    vm.selectWinner(playerIndex: 3, winType: .normal)
    return GameScreenView(viewModel: vm)
}
