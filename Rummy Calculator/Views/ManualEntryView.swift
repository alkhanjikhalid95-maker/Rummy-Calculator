import SwiftUI

struct ManualEntryView: View {
    @Bindable var viewModel: GameViewModel
    @FocusState private var focused: Bool

    private var playerName: String {
        guard let idx = viewModel.manualEntryPlayerIndex, viewModel.players.indices.contains(idx) else { return "" }
        return viewModel.players[idx].name
    }

    private var subtitle: String {
        guard let round = viewModel.manualEntryRoundIndex else { return playerName }
        return "\(playerName) · اللفة \(round + 1)"
    }

    var body: some View {
        VStack(spacing: 18) {
            SheetHeader(title: "تعديل النتيجة", subtitle: subtitle) {
                viewModel.showManualEntry = false
            }

            TextField("النتيجة", text: $viewModel.manualEntryText)
                .keyboardType(.numbersAndPunctuation)
                .font(.system(size: 44, weight: .light).monospacedDigit())
                .foregroundStyle(Color.ink)
                .multilineTextAlignment(.center)
                .focused($focused)
                .submitLabel(.done)
                .onSubmit { viewModel.applyManualScore() }
                .padding(.vertical, 14)
                .card(radius: 28)
                .padding(.horizontal, 20)

            HStack(spacing: 12) {
                Button {
                    viewModel.clearManualScore()
                } label: {
                    Label("الحساب التلقائي", systemImage: "arrow.uturn.backward")
                }
                .buttonStyle(SoftButtonStyle(height: 54))

                Button {
                    viewModel.applyManualScore()
                } label: {
                    Text("حفظ")
                }
                .buttonStyle(InkButtonStyle(height: 54))
                .disabled(Int(viewModel.manualEntryText) == nil)
            }
            .padding(.horizontal, 20)

            Spacer(minLength: 0)
        }
        .themedSheet()
        .onAppear { focused = true }
    }
}

#Preview {
    let vm = GameViewModel(sessionStore: .ephemeral)
    vm.manualEntryText = "350"
    return ManualEntryView(viewModel: vm)
}
