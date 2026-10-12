import SwiftUI

struct HistoryView: View {
    @Bindable var viewModel: GameViewModel
    @Environment(\.dismiss) private var dismiss
    @State private var showClearConfirmation = false

    var body: some View {
        NavigationStack {
            ZStack {
                AppBackground()

                if viewModel.historyManager.games.isEmpty {
                    VStack(spacing: 14) {
                        FloatingCards(width: 46)
                            .frame(height: 90)
                        Text("لا توجد ألعاب بعد")
                            .font(.system(size: 19))
                            .foregroundStyle(Color.ink)
                        Text("تُحفظ كل لعبة تلقائياً عند انتهائها")
                            .font(.system(size: 14))
                            .foregroundStyle(Color.inkSecondary)
                    }
                } else {
                    List {
                        ForEach(viewModel.historyManager.games) { record in
                            NavigationLink {
                                GameDetailView(record: record)
                            } label: {
                                gameRow(record)
                            }
                            .listRowBackground(Color.white)
                            .listRowSeparatorTint(Color.rule)
                        }
                        .onDelete { indexSet in
                            withAnimation {
                                viewModel.historyManager.deleteGame(at: indexSet)
                            }
                        }
                    }
                    .listStyle(.insetGrouped)
                    .scrollContentBackground(.hidden)
                }
            }
            .navigationTitle("سجل الألعاب")
            .navigationBarTitleDisplayMode(.inline)
            .confirmationDialog("حذف كل السجل؟", isPresented: $showClearConfirmation, titleVisibility: .visible) {
                Button("حذف الكل", role: .destructive) {
                    withAnimation {
                        viewModel.historyManager.clearAll()
                    }
                }
                Button("إلغاء", role: .cancel) {}
            } message: {
                Text("لا يمكن التراجع عن هذا.")
            }
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button {
                        dismiss()
                    } label: {
                        Image(systemName: "xmark")
                    }
                    .accessibilityLabel(Text("إغلاق"))
                }

                if !viewModel.historyManager.games.isEmpty {
                    ToolbarItem(placement: .topBarTrailing) {
                        Button("حذف الكل", role: .destructive) {
                            showClearConfirmation = true
                        }
                        .foregroundStyle(Color.negative)
                    }
                }
            }
        }
        .tint(Color.ink)
        .themedSheet()
    }

    private func gameRow(_ record: GameRecord) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Image(systemName: "crown")
                    .font(.system(size: 13))
                Text(record.winnerName)
                    .font(.system(size: 17))
                Spacer()
                Text(record.date, style: .date)
                    .font(.system(size: 12))
                    .foregroundStyle(Color.inkSecondary)
            }
            .foregroundStyle(Color.ink)

            HStack(spacing: 12) {
                ForEach(Array(record.playerNames.enumerated()), id: \.offset) { idx, name in
                    HStack(spacing: 4) {
                        Text(name)
                            .lineLimit(1)
                        if idx < record.finalScores.count {
                            Text(record.finalScores[idx].formatted())
                                .monospacedDigit()
                                .foregroundStyle(name == record.winnerName ? Color.positive : Color.inkSecondary)
                        }
                    }
                    .font(.system(size: 12))
                    .foregroundStyle(Color.inkSecondary)
                }
            }

            Label(formatDuration(record.duration), systemImage: "timer")
                .font(.system(size: 12))
                .foregroundStyle(Color.inkTertiary)
        }
        .padding(.vertical, 6)
    }
}

// MARK: - Game Detail View

struct GameDetailView: View {
    let record: GameRecord

    var body: some View {
        ZStack {
            AppBackground()

            ScrollView {
                VStack(spacing: 14) {
                    // Winner hero
                    VStack(alignment: .leading, spacing: 4) {
                        EyebrowLabel("الفائز", onAura: true)
                        Text(record.winnerName)
                            .font(.system(size: 40, weight: .light))
                            .foregroundStyle(.white)
                        HStack(spacing: 8) {
                            GlassTag(text: record.date.formatted(date: .abbreviated, time: .omitted), systemImage: "calendar")
                            GlassTag(text: formatDuration(record.duration), systemImage: "clock")
                        }
                        .padding(.top, 8)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(22)
                    .background {
                        AuraGradient(animated: false)
                            .clipShape(RoundedRectangle(cornerRadius: 32, style: .continuous))
                    }

                    // Final scores
                    VStack(alignment: .leading, spacing: 14) {
                        EyebrowLabel("النتائج النهائية")

                        HStack(spacing: 0) {
                            ForEach(Array(record.playerNames.enumerated()), id: \.offset) { idx, name in
                                let isWinner = name == record.winnerName
                                VStack(spacing: 6) {
                                    SeatBubble(name: name, seat: idx, size: 40, style: .paper, isRaised: isWinner)
                                    Text(name)
                                        .font(.system(size: 13))
                                        .foregroundStyle(Color.ink)
                                        .lineLimit(1)
                                    if idx < record.finalScores.count {
                                        Text(record.finalScores[idx].formatted())
                                            .font(.system(size: 17).monospacedDigit())
                                            .foregroundStyle(isWinner ? Color.positive : Color.inkSecondary)
                                    }
                                }
                                .frame(maxWidth: .infinity)
                            }
                        }
                    }
                    .padding(18)
                    .card(radius: 28)

                    // Round-by-round breakdown
                    VStack(alignment: .leading, spacing: 8) {
                        EyebrowLabel("تفاصيل اللفات")

                        HStack(spacing: 0) {
                            Text("#")
                                .frame(width: 24)
                            ForEach(Array(record.playerNames.enumerated()), id: \.offset) { _, name in
                                Text(name)
                                    .lineLimit(1)
                                    .frame(maxWidth: .infinity)
                            }
                        }
                        .font(.system(size: 12))
                        .foregroundStyle(Color.inkSecondary)

                        ForEach(record.roundResults, id: \.roundNumber) { round in
                            HStack(spacing: 0) {
                                Text("\(round.roundNumber)")
                                    .font(.system(size: 12))
                                    .frame(width: 24)
                                    .foregroundStyle(Color.inkTertiary)

                                ForEach(Array(round.scores.enumerated()), id: \.offset) { idx, _ in
                                    VStack(spacing: 1) {
                                        Text(cumulativeScore(through: round.roundNumber, playerIndex: idx).formatted())
                                            .font(.system(size: 14).monospacedDigit())
                                            .foregroundStyle(Color.ink)
                                        if record.playerNames.indices.contains(idx) && record.playerNames[idx] == round.winnerName {
                                            Text(round.winType)
                                                .font(.system(size: 9, weight: .medium))
                                                .foregroundStyle(Color.ember)
                                        }
                                    }
                                    .frame(maxWidth: .infinity)
                                }
                            }
                            .padding(.vertical, 6)
                            .background(
                                round.roundNumber % 2 == 0 ? Color.canvas : Color.clear,
                                in: RoundedRectangle(cornerRadius: 10, style: .continuous)
                            )
                        }
                    }
                    .padding(18)
                    .card(radius: 28)
                }
                .padding(.horizontal, 16)
                .padding(.bottom, 20)
            }
        }
        .navigationTitle("تفاصيل اللعبة")
        .navigationBarTitleDisplayMode(.inline)
    }

    private func cumulativeScore(through roundNumber: Int, playerIndex: Int) -> Int {
        record.roundResults
            .filter { $0.roundNumber <= roundNumber }
            .reduce(0) { total, round in
                total + (playerIndex < round.scores.count ? round.scores[playerIndex] : 0)
            }
    }
}
