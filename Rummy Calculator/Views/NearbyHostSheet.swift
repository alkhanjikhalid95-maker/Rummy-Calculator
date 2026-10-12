import SwiftUI

/// The scorekeeper's controls for sharing the board with phones at the table,
/// and for saying which player this phone belongs to.
struct NearbyHostSheet: View {
    @Bindable var viewModel: GameViewModel
    @Environment(\.dismiss) private var dismiss
    @State private var popTriggers = [0, 0, 0, 0]

    private var host: NearbyHost { viewModel.nearbyHost }

    var body: some View {
        VStack(spacing: 0) {
            SheetHeader(title: "اللاعبون القريبون", subtitle: "شارك النتائج مع جوالات الطاولة عبر البلوتوث") {
                dismiss()
            }

            ScrollView {
                VStack(spacing: 14) {
                    shareCard
                    mySeatCard
                    explainer
                }
                .padding(.horizontal, 16)
                .padding(.bottom, 24)
            }
        }
        .themedSheet()
    }

    // MARK: - Sharing

    private var shareCard: some View {
        VStack(alignment: .leading, spacing: 16) {
            Toggle(isOn: Binding(
                get: { host.isEnabled },
                set: { viewModel.setNearbySharing($0) }
            )) {
                HStack(spacing: 12) {
                    Image(systemName: "dot.radiowaves.left.and.right")
                        .font(.system(size: 17))
                        .foregroundStyle(host.status == .live ? .white : Color.ink)
                        .symbolEffect(.variableColor.iterative, isActive: host.status == .live)
                        .frame(width: 42, height: 42)
                        .background(host.status == .live ? Color.ink : Color.canvas, in: Circle())
                        .animation(.easeInOut, value: host.status)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("مشاركة اللعبة")
                            .font(.system(size: 17))
                            .foregroundStyle(Color.ink)
                        Text(statusText)
                            .font(.system(size: 12))
                            .foregroundStyle(statusColor)
                            .contentTransition(.opacity)
                    }
                }
            }
            .tint(Color.ink)

            if host.status == .unauthorized {
                Button("السماح بالبلوتوث من الإعدادات") {
                    if let url = URL(string: UIApplication.openSettingsURLString) {
                        UIApplication.shared.open(url)
                    }
                }
                .buttonStyle(SoftButtonStyle(height: 44))
            }

            if host.status == .live {
                HStack(spacing: 8) {
                    ForEach(viewModel.players.indices, id: \.self) { index in
                        let linked = viewModel.linkedSeats.contains(index)
                        VStack(spacing: 6) {
                            SeatBubble(name: viewModel.players[index].name, seat: index, size: 38, style: .paper, badge: linked ? .linked : nil)
                            Text(viewModel.players[index].name)
                                .font(.system(size: 11))
                                .foregroundStyle(linked ? Color.ink : Color.inkTertiary)
                                .lineLimit(1)
                        }
                        .frame(maxWidth: .infinity)
                    }
                }
                .animation(.spring(response: 0.4, dampingFraction: 0.7), value: viewModel.linkedSeats)
                .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
        .padding(18)
        .card(radius: 28)
        .animation(.spring(response: 0.4, dampingFraction: 0.85), value: host.status)
    }

    private var statusText: String {
        switch host.status {
        case .off: return "متوقفة"
        case .starting: return "جارٍ التشغيل…"
        case .live:
            return host.followerCount == 0
                ? "بانتظار اللاعبين — يختارون «تابع لعبة على جوال قريب»"
                : "يتابعك \(host.followerCount) \(host.followerCount == 1 ? "جوال" : "جوالات")"
        case .poweredOff: return "البلوتوث مغلق"
        case .unauthorized: return "البلوتوث غير مسموح للتطبيق"
        case .unsupported: return "هذا الجهاز لا يدعم البلوتوث"
        }
    }

    private var statusColor: Color {
        switch host.status {
        case .live: return .positive
        case .poweredOff, .unauthorized, .unsupported: return .negative
        default: return .inkSecondary
        }
    }

    // MARK: - This phone's seat

    private var mySeatCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            VStack(alignment: .leading, spacing: 2) {
                Text("أي لاعب أنت؟")
                    .font(.system(size: 17))
                    .foregroundStyle(Color.ink)
                Text("لتظهر نتيجتك وما تحتاجه لتتصدر على شاشة قفل هذا الجوال")
                    .font(.system(size: 12))
                    .foregroundStyle(Color.inkSecondary)
            }

            HStack(spacing: 8) {
                ForEach(viewModel.players.indices, id: \.self) { index in
                    let isMine = viewModel.localSeatIndex == index
                    Button {
                        popTriggers[index] += 1
                        viewModel.setLocalSeat(isMine ? nil : index)
                    } label: {
                        VStack(spacing: 6) {
                            SeatBubble(
                                name: viewModel.players[index].name,
                                seat: index,
                                size: 48,
                                style: .paper,
                                isRaised: isMine,
                                popTrigger: popTriggers[index]
                            )
                            Text(viewModel.players[index].name)
                                .font(.system(size: 12, weight: isMine ? .medium : .regular))
                                .foregroundStyle(isMine ? Color.ink : Color.inkSecondary)
                                .lineLimit(1)
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 6)
                    }
                    .buttonStyle(PressableStyle())
                }
            }
            .sensoryFeedback(.selection, trigger: viewModel.localSeatIndex)

            if let advice = viewModel.localSeatAdvice {
                AdviceCard(advice: advice, firstAdviceRound: PredictionEngine.firstAdviceRound)
                    .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
        .padding(18)
        .card(radius: 28)
        .animation(.spring(response: 0.4, dampingFraction: 0.85), value: viewModel.localSeatIndex)
    }

    private var explainer: some View {
        VStack(alignment: .leading, spacing: 10) {
            Label("يعمل بدون إنترنت، عبر البلوتوث فقط", systemImage: "wifi.slash")
            Label("تتحدث شاشة القفل لدى كل لاعب بعد كل لفة", systemImage: "lock.iphone")
            Label("من اللفة السابعة: نوع الفوز المطلوب للتصدر", systemImage: "scope")
        }
        .font(.system(size: 13))
        .foregroundStyle(Color.inkSecondary)
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 8)
        .padding(.top, 4)
    }
}
