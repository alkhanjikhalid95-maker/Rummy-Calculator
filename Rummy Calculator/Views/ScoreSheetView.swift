import SwiftUI

/// The round-by-round score grid: cumulative totals per round, tap a score to
/// override it, swipe a round to delete it, tap a column to record a winner.
struct ScoreSheetView: View {
    @Bindable var viewModel: GameViewModel
    @Environment(\.dismiss) private var dismiss
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var boardAnimation: Animation? {
        reduceMotion ? nil : .spring(response: 0.45, dampingFraction: 0.8)
    }

    var body: some View {
        VStack(spacing: 0) {
            SheetHeader(
                title: "جدول النتائج",
                subtitle: viewModel.isGameOver ? "انتهت اللعبة" : "اللفة \(viewModel.currentRoundNumber) من 9 · اسحب اللفة لحذفها",
                onClose: { dismiss() }
            )

            ScrollView {
                VStack(spacing: 0) {
                    columnHeaders
                    Color.rule.frame(height: 1)

                    ForEach(0..<(viewModel.game?.maxRounds ?? 9), id: \.self) { roundIndex in
                        roundRow(roundIndex: roundIndex)

                        if (roundIndex + 1) % 3 == 0 && roundIndex < 8 {
                            Color.ink.opacity(0.12).frame(height: 1)
                        } else {
                            Color.rule.frame(height: 0.5)
                        }
                    }
                }
                .background(Color.white)
                .clipShape(RoundedRectangle(cornerRadius: 28, style: .continuous))
                .shadow(color: .black.opacity(0.06), radius: 18, y: 8)
                .padding(.horizontal, 16)
                .padding(.bottom, 24)
                .animation(boardAnimation, value: viewModel.rounds)
                .animation(boardAnimation, value: viewModel.predictionsActive)
            }
            .scrollBounceBehavior(.basedOnSize)
        }
        .themedSheet()
        .sheet(isPresented: $viewModel.showManualEntry) {
            ManualEntryView(viewModel: viewModel)
                .presentationDetents([.height(330)])
        }
        .alert("حذف اللفة؟", isPresented: $viewModel.showDeleteConfirmation) {
            Button("حذف", role: .destructive) {
                withAnimation(boardAnimation) {
                    viewModel.deleteRound()
                }
            }
            Button("إلغاء", role: .cancel) {
                viewModel.roundToDelete = nil
            }
        } message: {
            if let r = viewModel.roundToDelete {
                Text("سيتم حذف اللفة \(r + 1) وكل اللفات التي بعدها.")
            }
        }
    }

    // MARK: - Headers

    private var columnHeaders: some View {
        let leader = viewModel.lastCompletedRoundIndex == nil ? nil : viewModel.leaderIndex

        return HStack(spacing: 0) {
            ForEach(Array(viewModel.players.enumerated()), id: \.element.id) { playerIndex, player in
                Button {
                    recordWinner(playerIndex)
                } label: {
                    VStack(spacing: 2) {
                        Text("P\(playerIndex + 1)")
                            .font(.system(size: 10, weight: .medium))
                            .kerning(1.5)
                            .foregroundStyle(Color.inkTertiary)
                        HStack(spacing: 3) {
                            if leader == playerIndex {
                                Image(systemName: "crown.fill")
                                    .font(.system(size: 9))
                                    .foregroundStyle(Color.ink)
                                    .transition(.scale.combined(with: .opacity))
                            }
                            Text(player.name)
                                .font(.system(size: 14, weight: viewModel.localSeatIndex == playerIndex ? .semibold : .regular))
                                .foregroundStyle(Color.ink)
                                .lineLimit(1)
                                .minimumScaleFactor(0.6)
                        }
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 10)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityHint(Text("تسجيل الفائز في هذه اللفة"))

                if playerIndex < viewModel.players.count - 1 {
                    Color.rule.frame(width: 1)
                }
            }
        }
        .background(Color.canvas.opacity(0.6))
        .animation(boardAnimation, value: leader)
    }

    /// The picker is presented from the board, so close this sheet first.
    private func recordWinner(_ playerIndex: Int) {
        guard !viewModel.isGameOver else { return }
        dismiss()
        Task {
            try? await Task.sleep(for: .milliseconds(350))
            viewModel.tapColumn(playerIndex: playerIndex)
        }
    }

    // MARK: - Rows

    private func roundRow(roundIndex: Int) -> some View {
        let rounds = viewModel.rounds
        let round: Round? = roundIndex < rounds.count ? rounds[roundIndex] : nil
        let isCurrentRound = viewModel.game?.currentRoundIndex == roundIndex
        let isCompleted = round?.isCompleted ?? false

        return rowContent(roundIndex: roundIndex, isCurrentRound: isCurrentRound, isCompleted: isCompleted)
            .swipeToDelete(enabled: isCompleted) {
                viewModel.confirmDeleteRound(roundIndex)
            }
    }

    private func rowContent(roundIndex: Int, isCurrentRound: Bool, isCompleted: Bool) -> some View {
        ZStack(alignment: .leading) {
            if isCurrentRound {
                Color.ember.opacity(0.07)
                    .transition(.opacity)
            }

            HStack(spacing: 0) {
                ForEach(Array(viewModel.players.enumerated()), id: \.element.id) { playerIndex, _ in
                    Group {
                        if isCompleted {
                            Button {
                                viewModel.openManualEntry(roundIndex: roundIndex, playerIndex: playerIndex)
                            } label: {
                                cumulativeScoreCell(roundIndex: roundIndex, playerIndex: playerIndex)
                            }
                            .buttonStyle(.plain)
                            .transition(.scale(scale: 0.6).combined(with: .opacity))
                        } else if isCurrentRound {
                            Button {
                                recordWinner(playerIndex)
                            } label: {
                                currentRoundCell(playerIndex: playerIndex)
                            }
                            .buttonStyle(.plain)
                        } else {
                            futureRoundCell(roundIndex: roundIndex, playerIndex: playerIndex)
                        }
                    }

                    if playerIndex < viewModel.players.count - 1 {
                        Color.rule.frame(width: 1)
                    }
                }
            }

            Group {
                if isCurrentRound {
                    Circle()
                        .stroke(Color.ember, lineWidth: 1.5)
                        .frame(width: 7, height: 7)
                } else {
                    Text("\(roundIndex + 1)")
                        .font(.system(size: 9, weight: .medium))
                        .foregroundStyle(Color.inkTertiary)
                }
            }
            .padding(.leading, 5)
        }
        .frame(minHeight: 44)
    }

    // MARK: - Cells

    private func cumulativeScoreCell(roundIndex: Int, playerIndex: Int) -> some View {
        let cumulative = viewModel.cumulativeScore(throughRound: roundIndex, playerIndex: playerIndex)
        let playerScore = viewModel.score(roundIndex: roundIndex, playerIndex: playerIndex)

        let isLatestRound = roundIndex == viewModel.lastCompletedRoundIndex
        let isFirst = isLatestRound && viewModel.firstPlaceIndex(throughRound: roundIndex) == playerIndex
        let isLast  = isLatestRound && viewModel.lastPlaceIndex(throughRound: roundIndex) == playerIndex

        let scoreColor: Color = isFirst ? .positive : isLast ? .negative : .ink

        return VStack(spacing: 2) {
            Text("\(cumulative)")
                .font(.system(size: 17, weight: isLatestRound ? .medium : .regular).monospacedDigit())
                .foregroundStyle(scoreColor)
                .contentTransition(.numericText(value: Double(cumulative)))

            HStack(spacing: 4) {
                if let ps = playerScore {
                    if ps.isWinner {
                        Image(systemName: "crown.fill")
                            .font(.system(size: 9))
                            .foregroundStyle(Color.ink)
                    }
                    if ps.hasPenalty {
                        Text("+100")
                            .font(.system(size: 9, weight: .semibold))
                            .foregroundStyle(Color.negative)
                    }
                    if ps.manualScore != nil {
                        Image(systemName: "pencil")
                            .font(.system(size: 9))
                            .foregroundStyle(Color.inkSecondary)
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, minHeight: 44)
        .contentShape(Rectangle())
    }

    private func currentRoundCell(playerIndex: Int) -> some View {
        Group {
            if let label = viewModel.predictionLabel(roundIndex: viewModel.game?.currentRoundIndex ?? 0, playerIndex: playerIndex) {
                predictionChip(label)
            } else {
                Image(systemName: "plus")
                    .font(.system(size: 12, weight: .light))
                    .foregroundStyle(Color.inkTertiary)
            }
        }
        .frame(maxWidth: .infinity, minHeight: 44)
        .contentShape(Rectangle())
    }

    private func futureRoundCell(roundIndex: Int, playerIndex: Int) -> some View {
        Group {
            if let label = viewModel.predictionLabel(roundIndex: roundIndex, playerIndex: playerIndex) {
                predictionChip(label)
            } else {
                Color.clear
            }
        }
        .frame(maxWidth: .infinity, minHeight: 44)
    }

    private func predictionChip(_ label: String) -> some View {
        Text(label)
            .font(.system(size: 12, weight: .medium))
            .foregroundStyle(.white)
            .lineLimit(1)
            .minimumScaleFactor(0.7)
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .background(Color.ember, in: Capsule())
            .padding(.horizontal, 2)
            .transition(.scale(scale: 0.5).combined(with: .opacity))
    }
}

// MARK: - Swipe To Delete Modifier

struct SwipeToDeleteModifier: ViewModifier {
    let enabled: Bool
    let onDelete: () -> Void

    @State private var offset: CGFloat = 0

    func body(content: Content) -> some View {
        if enabled {
            ZStack(alignment: .trailing) {
                HStack {
                    Spacer()
                    Button {
                        onDelete()
                        withAnimation(.easeOut(duration: 0.2)) { offset = 0 }
                    } label: {
                        Image(systemName: "trash.fill")
                            .foregroundStyle(.white)
                            .frame(width: 70, height: 44)
                            .background(Color.negative)
                    }
                    .accessibilityLabel(Text("حذف اللفة"))
                }
                .opacity(offset < 0 ? 1 : 0)

                content
                    .offset(x: offset)
                    .highPriorityGesture(
                        DragGesture(minimumDistance: 30, coordinateSpace: .local)
                            .onChanged { value in
                                let t = value.translation.width
                                if t < 0 { offset = max(t, -80) }
                                else if offset < 0 { offset = min(0, offset + t) }
                            }
                            .onEnded { value in
                                withAnimation(.spring(response: 0.3, dampingFraction: 0.75)) {
                                    offset = value.translation.width < -40 ? -70 : 0
                                }
                            }
                    )
            }
            .clipped()
            .accessibilityAction(named: Text("حذف اللفة"), onDelete)
        } else {
            content
        }
    }
}

extension View {
    func swipeToDelete(enabled: Bool, onDelete: @escaping () -> Void) -> some View {
        modifier(SwipeToDeleteModifier(enabled: enabled, onDelete: onDelete))
    }
}

#Preview {
    let vm = GameViewModel(sessionStore: .ephemeral)
    vm.playerNames = ["Khalid", "Hamad", "Ali", "Saud"]
    vm.startGame()
    vm.selectWinner(playerIndex: 0, winType: .normal)
    return ScoreSheetView(viewModel: vm)
}
