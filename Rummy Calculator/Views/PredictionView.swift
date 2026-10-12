import SwiftUI

struct PredictionView: View {
    @Bindable var viewModel: GameViewModel
    @Environment(\.dismiss) private var dismiss
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var appeared = false

    private var roundsLeft: Int {
        (viewModel.game?.maxRounds ?? 9) - (viewModel.currentRoundNumber - 1)
    }

    var body: some View {
        let predictions = viewModel.computePredictions()

        VStack(spacing: 0) {
            SheetHeader(
                title: "التوقعات",
                subtitle: "اللفة \(viewModel.currentRoundNumber) من \(viewModel.game?.maxRounds ?? 9) · باقي \(roundsLeft) لفات",
                onClose: { dismiss() }
            )

            ScrollView {
                VStack(spacing: 12) {
                    if let leaderIdx = viewModel.leaderIndex {
                        leaderCard(leaderIdx)
                    }

                    if predictions.isEmpty {
                        Text("لا توجد بيانات كافية بعد")
                            .foregroundStyle(Color.inkSecondary)
                            .padding()
                    } else {
                        ForEach(Array(predictions.enumerated()), id: \.element.id) { offset, pred in
                            predictionCard(pred)
                                .offset(y: appeared ? 0 : 24)
                                .animation(
                                    reduceMotion ? nil : .spring(response: 0.5, dampingFraction: 0.8).delay(Double(offset) * 0.08),
                                    value: appeared
                                )
                        }
                    }

                    Text("الخطة تفترض أن المتصدر لا يربح أي لفة متبقية، ولا تحسب جزاء +100.")
                        .font(.system(size: 12))
                        .foregroundStyle(Color.inkSecondary)
                        .multilineTextAlignment(.center)
                        .padding(.top, 4)
                }
                .padding(.horizontal, 16)
                .padding(.bottom, 24)
            }
        }
        .themedSheet()
        .onAppear { appeared = true }
    }

    private func leaderCard(_ leaderIdx: Int) -> some View {
        HStack(alignment: .center) {
            VStack(alignment: .leading, spacing: 2) {
                EyebrowLabel("المتصدر", onAura: true)
                Text(viewModel.totalScore(playerIndex: leaderIdx).formatted())
                    .font(.system(size: 48, weight: .light).monospacedDigit())
                    .foregroundStyle(.white)
            }
            Spacer()
            GlassTag(text: viewModel.players[leaderIdx].name, systemImage: "crown")
        }
        .padding(22)
        .background {
            AuraGradient()
                .clipShape(RoundedRectangle(cornerRadius: 32, style: .continuous))
        }
    }

    private func predictionCard(_ pred: PlayerPrediction) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 12) {
                SeatBubble(name: pred.playerName, seat: pred.playerIndex, size: 42, style: .paper)
                VStack(alignment: .leading, spacing: 2) {
                    Text(pred.playerName)
                        .font(.system(size: 17))
                        .foregroundStyle(Color.ink)
                    Text("\(pred.currentTotal.formatted()) · خلف بـ \(pred.gap.formatted())")
                        .font(.system(size: 13).monospacedDigit())
                        .foregroundStyle(Color.inkSecondary)
                }
                Spacer()
                statusBadge(pred)
            }

            if pred.canCatchUp {
                FlowLayout(spacing: 6) {
                    ForEach(pred.combinationSummary, id: \.winType) { item in
                        InkChip(text: "\(item.winType.rawValue) ×\(item.count)")
                    }
                }
                Text("يحتاج الفوز في \(pred.roundPlan?.count ?? 0) من \(roundsLeft) لفات")
                    .font(.system(size: 12))
                    .foregroundStyle(Color.inkSecondary)
            }
        }
        .padding(18)
        .card(radius: 28)
    }

    @ViewBuilder
    private func statusBadge(_ pred: PlayerPrediction) -> some View {
        let (text, color): (String, Color) = {
            if !pred.canCatchUp { return ("صعب اللحاق", .negative) }
            if pred.resultIsTie { return ("تعادل فقط", .ember) }
            return ("يمكنه التصدر", .positive)
        }()
        Text(text)
            .font(.system(size: 12, weight: .medium))
            .foregroundStyle(color)
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            .background(color.opacity(0.1), in: Capsule())
    }
}

// MARK: - Flow Layout

struct FlowLayout: Layout {
    var spacing: CGFloat = 6

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let maxWidth = proposal.width ?? .infinity
        var x: CGFloat = 0
        var y: CGFloat = 0
        var rowHeight: CGFloat = 0

        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if x + size.width > maxWidth && x > 0 {
                x = 0
                y += rowHeight + spacing
                rowHeight = 0
            }
            x += size.width + spacing
            rowHeight = max(rowHeight, size.height)
        }

        return CGSize(width: maxWidth, height: y + rowHeight)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var x: CGFloat = bounds.minX
        var y: CGFloat = bounds.minY
        var rowHeight: CGFloat = 0

        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if x + size.width > bounds.maxX && x > bounds.minX {
                x = bounds.minX
                y += rowHeight + spacing
                rowHeight = 0
            }
            subview.place(at: CGPoint(x: x, y: y), proposal: .unspecified)
            x += size.width + spacing
            rowHeight = max(rowHeight, size.height)
        }
    }
}

#Preview {
    let vm = GameViewModel(sessionStore: .ephemeral)
    vm.playerNames = ["Khalid", "Hamad", "Ali", "Saud"]
    vm.startGame()
    // Simulate 7 rounds
    for i in 0..<7 {
        vm.selectWinner(playerIndex: i % 4, winType: .normal)
    }
    vm.predictionsActive = true
    return PredictionView(viewModel: vm)
}
