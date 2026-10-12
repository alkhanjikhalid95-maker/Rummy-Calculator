import SwiftUI

/// Looks for scorekeepers nearby and lets the player pick one to follow.
struct NearbyJoinView: View {
    var guest: NearbyGuest
    @Environment(\.dismiss) private var dismiss
    @State private var name = PlayerIdentity.preferredName ?? ""
    /// The first time only: this phone's name, which the host sees.
    @State private var needsName = (PlayerIdentity.preferredName ?? "").trimmingCharacters(in: .whitespaces).isEmpty
    @FocusState private var nameFocused: Bool

    /// Waits this long for a second table before joining a lone one.
    private static let settle: Duration = .milliseconds(1500)

    var body: some View {
        VStack(spacing: 0) {
            SheetHeader(title: "تابع لعبة قريبة", subtitle: "النتائج تصل جوالك وشاشة القفل عبر البلوتوث") {
                dismiss()
            }

            ScrollView {
                VStack(spacing: 18) {
                    if needsName {
                        nameStep
                            .transition(.move(edge: .leading).combined(with: .opacity))
                    } else {
                        RadarPulse(isActive: guest.radio == .ready || guest.radio == .unknown)
                            .frame(height: 190)
                            .padding(.top, 8)

                        content
                    }
                }
                .padding(.horizontal, 16)
                .padding(.bottom, 24)
            }
        }
        .themedSheet()
        .animation(.spring(response: 0.45, dampingFraction: 0.86), value: needsName)
        .onAppear {
            if needsName {
                nameFocused = true
            } else {
                guest.startBrowsing()
            }
        }
        // One table in range: join it once no second one turns up.
        .task(id: guest.tables.map(\.id)) {
            guard guest.tables.count == 1, guest.phase == .browsing else { return }
            try? await Task.sleep(for: Self.settle)
            guard !Task.isCancelled, guest.tables.count == 1, guest.phase == .browsing else { return }
            guest.follow(guest.tables[0])
        }
        .onDisappear {
            if guest.phase == .browsing {
                guest.stopBrowsing()
            }
        }
        .onChange(of: guest.phase) { _, phase in
            if phase == .following { dismiss() }
        }
    }

    // MARK: - Name

    private var nameStep: some View {
        VStack(alignment: .leading, spacing: 16) {
            VStack(alignment: .leading, spacing: 4) {
                Text("ما اسمك؟")
                    .font(.system(size: 22))
                    .foregroundStyle(Color.ink)
                Text("يراه المضيف ليجلسك في مقعدك. يُحفظ على هذا الجوال فقط — بلا حساب ولا إنترنت.")
                    .font(.system(size: 13))
                    .foregroundStyle(Color.inkSecondary)
            }

            TextField("اسمك", text: $name)
                .font(.system(size: 22))
                .multilineTextAlignment(.center)
                .textContentType(.givenName)
                .submitLabel(.continue)
                .focused($nameFocused)
                .onSubmit(saveName)
                .padding(.vertical, 14)
                .background(Color.canvas, in: Capsule())

            Button("متابعة", action: saveName)
                .buttonStyle(InkButtonStyle())
                .disabled(name.trimmingCharacters(in: .whitespaces).isEmpty)
        }
        .padding(22)
        .card(radius: 32)
        .padding(.top, 8)
    }

    private func saveName() {
        let trimmed = String(name.trimmingCharacters(in: .whitespaces).prefix(LobbyPlayer.maxNameLength))
        guard !trimmed.isEmpty else { return }
        PlayerIdentity.preferredName = trimmed
        needsName = false
        guest.startBrowsing()
    }

    // MARK: - Tables

    @ViewBuilder
    private var content: some View {
        switch guest.radio {
        case .unauthorized:
            notice(
                icon: "lock.shield",
                title: "البلوتوث غير مسموح",
                message: "اسمح للتطبيق باستخدام البلوتوث من الإعدادات لمتابعة الألعاب القريبة."
            ) {
                Button("فتح الإعدادات") {
                    if let url = URL(string: UIApplication.openSettingsURLString) {
                        UIApplication.shared.open(url)
                    }
                }
                .buttonStyle(InkButtonStyle(height: 48))
            }
        case .poweredOff:
            notice(icon: "antenna.radiowaves.left.and.right.slash", title: "البلوتوث مغلق", message: "شغّل البلوتوث من مركز التحكم ثم حاول مجدداً.") { EmptyView() }
        case .unsupported:
            notice(icon: "exclamationmark.triangle", title: "غير مدعوم", message: "هذا الجهاز لا يدعم البلوتوث منخفض الطاقة.") { EmptyView() }
        case .ready, .unknown:
            if guest.tables.isEmpty {
                VStack(spacing: 8) {
                    Text("نبحث عن طاولات قريبة…")
                        .font(.system(size: 18))
                        .foregroundStyle(Color.ink)
                    Text("اطلب من حامل النتائج تشغيل «مشاركة اللعبة» من شاشة اللعبة.")
                        .font(.system(size: 14))
                        .foregroundStyle(Color.inkSecondary)
                        .multilineTextAlignment(.center)
                }
                .padding(.top, 4)
            } else {
                VStack(alignment: .leading, spacing: 10) {
                    EyebrowLabel(guest.tables.count == 1 ? "تنضم تلقائياً…" : "طاولات قريبة")
                        .padding(.leading, 6)
                    ForEach(guest.tables) { table in
                        tableRow(table)
                            .transition(.scale(scale: 0.9).combined(with: .opacity))
                    }
                }
                .animation(.spring(response: 0.4, dampingFraction: 0.8), value: guest.tables)
            }
        }
    }

    private func tableRow(_ table: NearbyGuest.Table) -> some View {
        let snapshot = table.snapshot
        return Button {
            guest.follow(table)
        } label: {
            HStack(spacing: 12) {
                HStack(spacing: -10) {
                    ForEach(snapshot.names.indices.filter { !snapshot.names[$0].isEmpty }, id: \.self) { index in
                        SeatBubble(name: snapshot.names[index], seat: index, size: 32, style: .paper)
                    }
                }
                VStack(alignment: .leading, spacing: 3) {
                    Text(snapshot.names.filter { !$0.isEmpty }.joined(separator: "، "))
                        .font(.system(size: 15))
                        .foregroundStyle(Color.ink)
                        .lineLimit(1)
                    Text(snapshot.isLobby ? "يجهّز الطاولة" : (snapshot.isOver ? "انتهت اللعبة" : "اللفة \(snapshot.round) من \(snapshot.maxRounds)"))
                        .font(.system(size: 12))
                        .foregroundStyle(Color.inkSecondary)
                }
                Spacer(minLength: 0)
                InkChip(text: "تابع")
            }
            .padding(14)
            .card(radius: 26)
        }
        .buttonStyle(PressableStyle(scale: 0.97))
    }

    private func notice<Action: View>(icon: String, title: String, message: String, @ViewBuilder action: () -> Action) -> some View {
        VStack(spacing: 10) {
            Image(systemName: icon)
                .font(.system(size: 26, weight: .light))
                .foregroundStyle(Color.ink)
            Text(title)
                .font(.system(size: 18))
                .foregroundStyle(Color.ink)
            Text(message)
                .font(.system(size: 14))
                .foregroundStyle(Color.inkSecondary)
                .multilineTextAlignment(.center)
            action()
        }
        .padding(22)
        .frame(maxWidth: .infinity)
        .card(radius: 28)
    }
}

/// Rings rippling out from a glass disc while searching.
struct RadarPulse: View {
    var isActive: Bool
    var onAura = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        let line = onAura ? Color.white : Color.ink
        TimelineView(.animation(paused: !isActive || reduceMotion)) { timeline in
            let t = timeline.date.timeIntervalSinceReferenceDate
            ZStack {
                ForEach(0..<3, id: \.self) { ring in
                    let phase = (t / 2.6 + Double(ring) / 3).truncatingRemainder(dividingBy: 1)
                    Circle()
                        .stroke(line.opacity(isActive ? 0.35 * (1 - phase) : 0.08), lineWidth: 1)
                        .scaleEffect(isActive && !reduceMotion ? 0.3 + phase * 0.9 : 0.4 + Double(ring) * 0.25)
                }
                Image(systemName: "dot.radiowaves.left.and.right")
                    .font(.system(size: 26, weight: .light))
                    .foregroundStyle(.white)
                    .symbolEffect(.variableColor.iterative, isActive: isActive && !reduceMotion)
                    .frame(width: 84, height: 84)
                    .background(Color.ink, in: Circle())
                    .shadow(color: .black.opacity(0.2), radius: 14, y: 6)
            }
        }
        .accessibilityHidden(true)
    }
}
