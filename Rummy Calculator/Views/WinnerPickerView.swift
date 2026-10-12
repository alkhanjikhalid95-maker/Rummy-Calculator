import SwiftUI

struct WinnerPickerView: View {
    @Bindable var viewModel: GameViewModel
    /// Starts on the win-type step when the player tapped a seat on the board.
    @State private var selectedPlayerIndex: Int?
    @State private var selectedWinType: WinType?
    @State private var popTriggers = [0, 0, 0, 0]
    /// The seat popping before the win-type step slides in.
    @State private var pendingSeat: Int?
    /// +1 going forward, -1 going back — picks the slide direction.
    @State private var direction = 1

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    init(viewModel: GameViewModel) {
        self.viewModel = viewModel
        _selectedPlayerIndex = State(initialValue: viewModel.winnerPickerSeat)
    }

    private var stepTransition: AnyTransition {
        guard !reduceMotion else { return .opacity }
        return .asymmetric(
            insertion: .move(edge: direction > 0 ? .trailing : .leading).combined(with: .opacity),
            removal: .move(edge: direction > 0 ? .leading : .trailing).combined(with: .opacity)
        )
    }

    var body: some View {
        VStack(spacing: 0) {
            SheetHeader(
                title: title,
                subtitle: "اللفة \(viewModel.currentRoundNumber) من 9",
                onClose: { viewModel.showWinnerPicker = false }
            )

            ZStack {
                if let idx = selectedPlayerIndex, let wt = selectedWinType {
                    deckQuestionStep(playerIndex: idx, winType: wt)
                        .transition(stepTransition)
                } else if let idx = selectedPlayerIndex {
                    winTypeSelectionStep(playerIndex: idx)
                        .transition(stepTransition)
                } else {
                    playerSelectionStep
                        .transition(stepTransition)
                }
            }
            .frame(maxHeight: .infinity, alignment: .top)
        }
        .themedSheet()
        .sensoryFeedback(.selection, trigger: selectedPlayerIndex)
        .sensoryFeedback(.selection, trigger: selectedWinType)
    }

    private var title: LocalizedStringKey {
        if selectedWinType != nil { return "هل فاز من السحبة؟" }
        if selectedPlayerIndex != nil { return "نوع الفوز" }
        return "من فاز؟"
    }

    private func go(_ step: Int, _ change: () -> Void) {
        direction = step
        withAnimation(reduceMotion ? nil : .spring(response: 0.42, dampingFraction: 0.86), change)
    }

    // MARK: - Step 1: Player Selection

    private var playerSelectionStep: some View {
        PokerTable(style: .aura) { index in
            let name = viewModel.players.indices.contains(index) ? viewModel.players[index].name : ""
            Button {
                choose(seat: index)
            } label: {
                SeatBubble(
                    name: name,
                    seat: index,
                    size: 58,
                    style: .aura,
                    isRaised: pendingSeat == index,
                    popTrigger: popTriggers[index],
                    badge: viewModel.leaderIndex == index && viewModel.lastCompletedRoundIndex != nil ? .crown : nil
                )
                .seatTag(edge: TableLayout.tagEdge(for: index)) {
                    SeatTag(
                        name: name,
                        detail: viewModel.totalScore(playerIndex: index).formatted(),
                        style: .aura,
                        isHighlighted: pendingSeat == index
                    )
                }
            }
            .buttonStyle(PressableStyle(scale: 0.9))
            .disabled(pendingSeat != nil)
            .accessibilityLabel(Text(name))
        } center: {
            VStack(spacing: 6) {
                Image(systemName: "hand.tap")
                    .font(.system(size: 22, weight: .light))
                Text("اضغط على الفائز")
                    .font(.system(size: 14))
            }
            .foregroundStyle(Color.white.opacity(0.9))
        }
        .padding(.horizontal, 70)
        .padding(.vertical, 50)
        .background {
            AuraGradient()
                .clipShape(RoundedRectangle(cornerRadius: 40, style: .continuous))
        }
        .padding(.horizontal, 16)
        .padding(.top, 8)
        .padding(.bottom, 20)
    }

    /// Lets the bubble-up play before moving on.
    private func choose(seat: Int) {
        popTriggers[seat] += 1
        pendingSeat = seat
        Task {
            try? await Task.sleep(for: .milliseconds(reduceMotion ? 0 : 260))
            go(1) { selectedPlayerIndex = seat }
            pendingSeat = nil
        }
    }

    // MARK: - Step 2: Win Type Selection

    private func winTypeSelectionStep(playerIndex idx: Int) -> some View {
        VStack(spacing: 18) {
            winnerBadge(playerIndex: idx, subtitle: "فاز في هذه اللفة")

            LazyVGrid(columns: [GridItem(.flexible(), spacing: 12), GridItem(.flexible(), spacing: 12)], spacing: 12) {
                ForEach(Array(mergedWinTypes.enumerated()), id: \.element.representative.id) { offset, merged in
                    Button {
                        if viewModel.deckWinEnabled {
                            // Advance to step 3 — ask about deck usage
                            go(1) { selectedWinType = merged.representative }
                        } else {
                            viewModel.selectWinner(playerIndex: idx, winType: merged.representative)
                        }
                    } label: {
                        winTypeCard(merged, tier: offset)
                    }
                    .buttonStyle(PressableStyle(scale: 0.95))
                }
            }
            .padding(.horizontal, 16)

            backButton { go(-1) { selectedPlayerIndex = nil } }
        }
        .padding(.top, 8)
    }

    private func winTypeCard(_ merged: MergedWinType, tier: Int) -> some View {
        let wt = merged.representative
        return VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 4) {
                ForEach(0..<4, id: \.self) { dot in
                    Circle()
                        .fill(dot <= tier ? Color.ink : Color.rule)
                        .frame(width: 6, height: 6)
                }
            }

            Text(merged.label)
                .font(.system(size: 19, weight: .regular))
                .foregroundStyle(Color.ink)
                .lineLimit(2)
                .minimumScaleFactor(0.8)

            HStack(spacing: 10) {
                Text("\(wt.winnerScore)")
                    .foregroundStyle(Color.positive)
                Text("+\(wt.loserScore)")
                    .foregroundStyle(Color.inkSecondary)
            }
            .font(.system(size: 13, weight: .medium).monospacedDigit())
        }
        .frame(maxWidth: .infinity, minHeight: 118, alignment: .leading)
        .padding(.horizontal, 18)
        .card(radius: 28)
        .accessibilityElement(children: .combine)
    }

    // MARK: - Step 3: Deck Question (only when deckWinEnabled)

    private func deckQuestionStep(playerIndex idx: Int, winType wt: WinType) -> some View {
        VStack(spacing: 18) {
            winnerBadge(playerIndex: idx, subtitle: wt.tierLabel)

            VStack(spacing: 12) {
                // Yes — winner drew from the deck (no penalty)
                Button {
                    viewModel.selectWinner(playerIndex: idx, winType: wt, usedDeck: true)
                } label: {
                    Label("نعم — من السحبة", systemImage: "rectangle.stack")
                }
                .buttonStyle(InkButtonStyle())

                // No — winner used the discard pile (penalty applies)
                Button {
                    viewModel.selectWinner(playerIndex: idx, winType: wt, usedDeck: false)
                } label: {
                    Label("لا — من النزول (+100)", systemImage: "arrow.turn.down.left")
                }
                .buttonStyle(SoftButtonStyle(height: 56))
            }
            .padding(.horizontal, 20)

            backButton { go(-1) { selectedWinType = nil } }
        }
        .padding(.top, 8)
    }

    // MARK: - Pieces

    private func winnerBadge(playerIndex idx: Int, subtitle: String) -> some View {
        HStack(spacing: 14) {
            SeatBubble(name: viewModel.players[idx].name, seat: idx, size: 52, style: .paper, isRaised: true)
            VStack(alignment: .leading, spacing: 2) {
                Text(viewModel.players[idx].name)
                    .font(.system(size: 22, weight: .regular))
                    .foregroundStyle(Color.ink)
                Text(subtitle)
                    .font(.system(size: 14))
                    .foregroundStyle(Color.inkSecondary)
            }
            Spacer()
        }
        .padding(.horizontal, 26)
    }

    private func backButton(_ action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Label("رجوع", systemImage: "chevron.backward")
                .font(.system(size: 15))
                .foregroundStyle(Color.inkSecondary)
        }
        .padding(.top, 4)
    }

    // MARK: - Merged Win Types

    private struct MergedWinType {
        let label: String
        let representative: WinType
    }

    private var mergedWinTypes: [MergedWinType] {
        [
            MergedWinType(label: "عادي", representative: .normal),
            MergedWinType(label: "كلر / جوكر", representative: .color),
            MergedWinType(label: "كلر+جوكر / زاته", representative: .zata),
            MergedWinType(label: "زاته + جوكر", representative: .zataJoker),
        ]
    }
}

#Preview {
    let vm = GameViewModel(sessionStore: .ephemeral)
    vm.playerNames = ["Khalid", "Hamad", "Ali", "Saud"]
    vm.startGame()
    vm.showWinnerPicker = true
    return WinnerPickerView(viewModel: vm)
}
