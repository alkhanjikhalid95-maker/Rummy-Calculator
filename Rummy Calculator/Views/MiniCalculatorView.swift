import SwiftUI

/// Adds up the cards a player is laying down, one tap per card.
struct MiniCalculatorView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var cards: [Tapped] = []
    @State private var floaters: [Tapped] = []

    /// One tapped card, identified so chips and "+n" floaters animate individually.
    struct Tapped: Identifiable, Equatable {
        let id = UUID()
        let label: String
        let value: Int
    }

    private var runningTotal: Int { cards.reduce(0) { $0 + $1.value } }

    private static let rows: [[String]] = [
        ["1", "2", "3", "4", "5"],
        ["6", "7", "8", "9", "10"],
        ["J", "Q", "K", "A"],
    ]

    /// Card values: face cards (A, K, Q, J) are worth 10
    static func cardValue(_ card: String) -> Int {
        switch card {
        case "A", "K", "Q", "J":
            return 10
        default:
            return Int(card) ?? 0
        }
    }

    var body: some View {
        VStack(spacing: 16) {
            SheetHeader(title: "حاسبة النزول", subtitle: "اضغط على كل ورقة تنزلها") {
                dismiss()
            }

            display
                .padding(.horizontal, 16)

            keypad
                .padding(.horizontal, 16)

            HStack(spacing: 12) {
                Button {
                    undo()
                } label: {
                    Label("تراجع", systemImage: "arrow.uturn.backward")
                }
                .buttonStyle(SoftButtonStyle())
                .disabled(cards.isEmpty)

                Button {
                    withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) {
                        cards.removeAll()
                    }
                } label: {
                    Label("صفّر", systemImage: "arrow.counterclockwise")
                }
                .buttonStyle(SoftButtonStyle(tint: .negative))
                .disabled(cards.isEmpty)
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 16)

            Spacer(minLength: 0)
        }
        .themedSheet()
        .sensoryFeedback(.impact(weight: .light), trigger: cards.count)
    }

    // MARK: - Display

    private var display: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 0) {
                    EyebrowLabel("المجموع", onAura: true)
                    ZStack(alignment: .topTrailing) {
                        Text("\(runningTotal)")
                            .font(.system(size: 72, weight: .light).monospacedDigit())
                            .foregroundStyle(.white)
                            .lineLimit(1)
                            .minimumScaleFactor(0.5)
                            .contentTransition(.numericText(value: Double(runningTotal)))

                        ForEach(floaters) { floater in
                            Text("+\(floater.value)")
                                .font(.system(size: 18, weight: .medium))
                                .foregroundStyle(.white)
                                .offset(x: 30, y: 4)
                                .transition(.asymmetric(
                                    insertion: .offset(y: 14).combined(with: .opacity),
                                    removal: .offset(y: -22).combined(with: .opacity)
                                ))
                        }
                    }
                }
                Spacer()
                GlassTag(text: cards.isEmpty ? "لا أوراق" : "\(cards.count) ورقة", systemImage: "rectangle.portrait.on.rectangle.portrait")
            }

            ScrollViewReader { proxy in
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 6) {
                        if cards.isEmpty {
                            Text("الأوراق تظهر هنا")
                                .font(.system(size: 13))
                                .foregroundStyle(Color.white.opacity(0.7))
                                .frame(height: 40)
                        }
                        ForEach(cards) { card in
                            chip(card.label)
                                .id(card.id)
                                .transition(.scale(scale: 0.4, anchor: .bottom).combined(with: .opacity))
                        }
                    }
                    .padding(.horizontal, 2)
                    .padding(.vertical, 4)
                }
                .onChange(of: cards.last?.id) { _, id in
                    guard let id else { return }
                    withAnimation { proxy.scrollTo(id, anchor: .trailing) }
                }
            }
            .frame(height: 48)
        }
        .padding(22)
        .background {
            AuraGradient()
                .clipShape(RoundedRectangle(cornerRadius: 36, style: .continuous))
        }
    }

    private func chip(_ label: String) -> some View {
        Text(label)
            .font(.system(size: 15, weight: .medium))
            .foregroundStyle(Color.ink)
            .frame(width: 30, height: 40)
            .background(Color.white, in: RoundedRectangle(cornerRadius: 7, style: .continuous))
            .shadow(color: .black.opacity(0.12), radius: 3, y: 2)
    }

    // MARK: - Keypad

    private var keypad: some View {
        VStack(spacing: 10) {
            ForEach(Self.rows, id: \.self) { row in
                HStack(spacing: 10) {
                    ForEach(row, id: \.self) { label in
                        Button {
                            add(label)
                        } label: {
                            CardKey(label: label, isFace: Int(label) == nil)
                        }
                        .buttonStyle(PressableStyle(scale: 0.88))
                        .accessibilityLabel(Text("\(label)، \(Self.cardValue(label))"))
                    }
                }
            }
        }
    }

    // MARK: - Actions

    private func add(_ label: String) {
        let card = Tapped(label: label, value: Self.cardValue(label))
        withAnimation(.spring(response: 0.35, dampingFraction: 0.7)) {
            cards.append(card)
        }
        guard !reduceMotion else { return }
        withAnimation(.easeOut(duration: 0.2)) { floaters.append(card) }
        Task {
            try? await Task.sleep(for: .milliseconds(420))
            withAnimation(.easeIn(duration: 0.3)) { floaters.removeAll { $0.id == card.id } }
        }
    }

    private func undo() {
        guard !cards.isEmpty else { return }
        withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) {
            _ = cards.removeLast()
        }
    }
}

/// A keypad key: a white card, or black for the court cards and the ace.
private struct CardKey: View {
    let label: String
    let isFace: Bool

    var body: some View {
        RoundedRectangle(cornerRadius: 18, style: .continuous)
            .fill(isFace ? Color.ink : Color.white)
            .overlay {
                Text(label)
                    .font(.system(size: 24, weight: .regular))
                    .foregroundStyle(isFace ? Color.white : Color.ink)
            }
            .frame(maxWidth: .infinity)
            .frame(height: 60)
            .shadow(color: .black.opacity(isFace ? 0.18 : 0.06), radius: 10, y: 4)
    }
}

#Preview {
    MiniCalculatorView()
}
