import SwiftUI
import UIKit

/// The Joker card's reveal: the camera dives into the nearer binocular lens
/// and the winner's name resolves inside the glass, 4.6 seconds in all.
///
/// Adapted from the JokerWinnerAnimation kit: the same timing and optics,
/// with Arabic copy for the end of a game. Give each showing a fresh identity
/// so it replays; uses the `JokerCard` image set.
struct JokerWinnerReveal: View {
    let winnerName: String
    let imageName: String
    /// Where playback begins — 0 in the app; previews and tests can open on
    /// the finished frame.
    let startTime: TimeInterval
    let onContinue: () -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.scenePhase) private var scenePhase
    @ScaledMetric(relativeTo: .largeTitle) private var nameSize: CGFloat = 68
    @State private var startedAt: Date?
    @State private var accumulated: TimeInterval = 0
    @State private var finished = false
    @State private var announced = false

    private let duration: TimeInterval = 4.6
    private var displayName: String {
        let trimmed = winnerName.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? "الفائز" : trimmed
    }

    private var announcement: String {
        "\(displayName)، الفائز باللعبة. لعب رائع."
    }

    init(winnerName: String, imageName: String = "JokerCard", startTime: TimeInterval = 0, onContinue: @escaping () -> Void) {
        self.winnerName = winnerName
        self.imageName = imageName
        self.startTime = startTime
        self.onContinue = onContinue
    }

    var body: some View {
        GeometryReader { geometry in
            TimelineView(.animation(minimumInterval: 1.0 / 60, paused: finished || scenePhase != .active)) { timeline in
                let elapsed = min(duration, accumulated + (startedAt.map { max(0, timeline.date.timeIntervalSince($0)) } ?? 0))
                let time = reduceMotion ? duration : elapsed
                let reveal = JokerOptics.smooth((time - 3.3) / 0.8)
                ZStack {
                    Canvas(opaque: true) { context, size in
                        JokerOptics.draw(context: context, size: size, time: time, image: Image(imageName))
                    }
                    .accessibilityHidden(true)

                    // Arabic is never letter-spaced: tracking pulls the letters apart.
                    VStack {
                        Text("انتهت اللعبة")
                            .font(.system(size: 14, weight: .medium))
                            .padding(.top, max(48, geometry.size.height * 0.135))
                        Spacer()
                        Text("لمسة سحر… وفوز مستحق")
                            .font(.system(size: 14))
                            .padding(.bottom, max(90, geometry.size.height * 0.18))
                    }
                    .foregroundStyle(Color(hex: 0x737B70))
                    .opacity(1 - JokerOptics.smooth((time - 0.5) / 0.55))
                    .accessibilityHidden(true)

                    winnerContent(reveal: reveal, availableHeight: geometry.size.height)
                        .padding(.horizontal, 28)
                        .frame(maxWidth: 620)
                        .opacity(reveal)
                        .blur(radius: (1 - reveal) * 6)
                        .offset(y: (1 - reveal) * 17)
                        .accessibilityHidden(reveal < 1)

                    VStack {
                        Spacer()
                        Button(action: onContinue) {
                            Text("متابعة")
                                .font(.system(size: 16, weight: .medium))
                                .frame(maxWidth: .infinity, minHeight: 52)
                                .foregroundStyle(Color(hex: 0xEFDFB9))
                                .background(Color(hex: 0xB7A06D).opacity(0.09), in: RoundedRectangle(cornerRadius: 14))
                                .overlay(RoundedRectangle(cornerRadius: 14).stroke(Color(hex: 0xC2A970).opacity(0.3), lineWidth: 1))
                        }
                        .buttonStyle(.plain)
                        .padding(.horizontal, 36)
                        .padding(.bottom, max(30, geometry.safeAreaInsets.bottom + 22))
                        .frame(maxWidth: 560)
                    }
                    .opacity(JokerOptics.smooth((time - 4.1) / 0.4))
                    .allowsHitTesting(time >= 4.5)
                    .accessibilityHidden(time < 4.5)
                }
                .onChange(of: time >= 4.1) { _, ready in
                    guard ready, !announced else { return }
                    announced = true
                    UINotificationFeedbackGenerator().notificationOccurred(.success)
                    UIAccessibility.post(notification: .announcement, argument: announcement)
                }
                .onChange(of: elapsed >= duration) { _, complete in
                    if complete { accumulated = duration; startedAt = nil; finished = true }
                }
            }
        }
        .background(.white)
        .ignoresSafeArea()
        .statusBarHidden()
        .onAppear { reset() }
        .onDisappear { pause() }
        .onChange(of: winnerName) { _, _ in reset() }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active, !finished { startedAt = Date() }
            else { pause() }
        }
        .onChange(of: reduceMotion) { _, reduced in
            if reduced { accumulated = duration; startedAt = nil; finished = true; announceReducedMotion() }
        }
    }

    private func winnerContent(reveal: Double, availableHeight: CGFloat) -> some View {
        VStack(spacing: availableHeight < 500 ? 10 : 24) {
            Text("الجوكر قال كلمته")
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(Color(hex: 0xC8BC99))
            Text("♦")
                .font(.system(size: 28, weight: .regular, design: .serif))
                .foregroundStyle(Color(hex: 0xE0C78B))
                .accessibilityHidden(true)
            Text(displayName)
                .font(.system(size: min(nameSize, availableHeight < 500 ? 48 : nameSize), weight: .regular, design: .serif))
                .multilineTextAlignment(.center)
                .lineLimit(3)
                .minimumScaleFactor(0.25)
                .foregroundStyle(LinearGradient(colors: [Color(hex: 0xFFF5D7), Color(hex: 0xD3B571)], startPoint: .top, endPoint: .bottom))
                .frame(maxWidth: .infinity, minHeight: availableHeight < 500 ? 50 : 82)
            Rectangle().fill(Color(hex: 0xCDBD88).opacity(0.3)).frame(width: 46, height: 1)
                .accessibilityHidden(true)
            Text("الفائز باللعبة")
                .font(.system(size: 14, weight: .medium))
                .foregroundStyle(Color(hex: 0xE0D1AB))
            if availableHeight >= 500 {
                Text("لعب رائع")
                    .font(.system(size: 15)).foregroundStyle(Color(hex: 0xA9B9AA))
            }
        }
        .padding(.bottom, availableHeight < 500 ? 44 : 0)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(announcement)
        .accessibilityAddTraits(.isHeader)
    }

    private func reset() {
        let skip = reduceMotion || startTime >= duration
        accumulated = skip ? duration : max(0, startTime)
        finished = skip
        announced = false
        startedAt = skip || scenePhase != .active ? nil : Date()
        if skip { announceReducedMotion() }
    }

    private func pause() {
        if let startedAt { accumulated = min(duration, accumulated + max(0, Date().timeIntervalSince(startedAt))) }
        startedAt = nil
    }

    private func announceReducedMotion() {
        guard !announced else { return }
        announced = true
        UIAccessibility.post(notification: .announcement, argument: announcement)
    }
}

/// Camera path and lens drawing, in the coordinates of the 300 × 436 card art.
private nonisolated enum JokerOptics {
    static func clamp(_ x: Double) -> Double { max(0, min(1, x)) }
    static func smooth(_ value: Double) -> Double { let x = clamp(value); return x * x * (3 - 2 * x) }
    static func ease(_ value: Double) -> Double {
        let x = clamp(value)
        return x < 0.5 ? 4 * x * x * x : 1 - pow(-2 * x + 2, 3) / 2
    }

    static func draw(context: GraphicsContext, size: CGSize, time: Double, image: Image) {
        let width = size.width, height = size.height
        context.fill(Path(CGRect(origin: .zero, size: size)), with: .color(.white))
        let progress = ease((time - 0.65) / 2.7)
        let pan = smooth((time - 0.65) / 1.6)
        let cardWidth = min(width * 292 / 390, height * 0.58 * 300 / 436)
        let baseScale = cardWidth / 300
        // Cover every corner, including on iPad and in landscape.
        let finalScale = max(82, hypot(width, height) * 0.65 / (7.55 * baseScale))
        let zoom = CGFloat(exp(log(Double(finalScale)) * progress))
        let startX = (width - cardWidth) / 2 + 103 * baseScale
        let startY = (height - 436 * baseScale) / 2 + 201 * baseScale
        let cameraX = startX + (width / 2 - startX) * pan
        let cameraY = startY + (height * 0.48 - startY) * pan
        var world = context
        world.translateBy(x: cameraX, y: cameraY)
        world.scaleBy(x: baseScale * zoom, y: baseScale * zoom)
        world.translateBy(x: -103, y: -201)
        // Transform a fixed-size Canvas, rather than allocate an enormous scaled bitmap.
        world.draw(image, in: CGRect(x: 0, y: 0, width: 300, height: 436))
        drawGlass(context: world, progress: progress)

        let reveal = smooth((time - 3.3) / 0.8)
        guard reveal > 0 else { return }
        var finish = context
        finish.opacity = reveal
        finish.fill(Path(CGRect(origin: .zero, size: size)), with: .radialGradient(
            Gradient(colors: [.clear, Color(hex: 0x020B09).opacity(0.6)]),
            center: CGPoint(x: width * 0.5, y: height * 0.48), startRadius: 35, endRadius: height * 0.65))
        var rings = finish
        rings.translateBy(x: width / 2, y: height * 0.46)
        rings.rotate(by: .radians(-0.25))
        rings.stroke(ellipse(x: 0, y: 0, rx: width * 0.664, ry: height * 0.423), with: .color(Color(hex: 0xD9C384).opacity(0.12)), lineWidth: 1)
        rings.stroke(ellipse(x: 0, y: 0, rx: width * 0.633, ry: height * 0.405), with: .color(Color(hex: 0xE4CF92).opacity(0.12)), lineWidth: 0.5)
        for i in 0..<16 {
            let angle = Double(i) * 2.39996
            let radius = Double(100 + (i % 4) * 35) * min(width / 390, height / 844)
            let x = width / 2 + cos(angle) * radius
            let y = height * 0.47 + sin(angle) * radius * 1.45 - (time - 3.3) * 8
            let dotRadius = i % 3 == 0 ? 1.4 : 0.8
            finish.fill(ellipse(x: x, y: y, rx: dotRadius, ry: dotRadius), with: .color(Color(hex: 0xE4D4A0).opacity(0.2 + 0.35 * pow(sin(Double(i) * 1.71), 2))))
        }
    }

    private static func drawGlass(context: GraphicsContext, progress: Double) {
        var lens = context
        // Measured in the original 300 x 436 image: the nearer, lower binocular lens.
        lens.translateBy(x: 103, y: 201)
        lens.rotate(by: .radians(0.48))
        lens.fill(ellipse(x: 0, y: 0, rx: 9.25, ry: 12), with: .linearGradient(
            Gradient(stops: [.init(color: Color(hex: 0xEFEED2), location: 0), .init(color: Color(hex: 0x1D2523), location: 0.2), .init(color: Color(hex: 0x070C0B), location: 0.5), .init(color: Color(hex: 0xA58F52), location: 0.82), .init(color: Color(hex: 0x151C19), location: 1)]),
            startPoint: CGPoint(x: -10, y: -12), endPoint: CGPoint(x: 10, y: 12)))
        lens.clip(to: ellipse(x: 0, y: 0, rx: 7.55, ry: 10.2))
        lens.fill(Path(CGRect(x: -10, y: -13, width: 20, height: 26)), with: .radialGradient(
            Gradient(stops: [.init(color: Color(hex: 0x526459), location: 0), .init(color: Color(hex: 0x213832), location: 0.21), .init(color: Color(hex: 0x10251F), location: 0.52), .init(color: Color(hex: 0x071512), location: 0.83), .init(color: Color(hex: 0x050E0D), location: 1)]),
            center: CGPoint(x: -3.8, y: -5.6), startRadius: 0.2, endRadius: 18))
        var reflection = lens
        reflection.rotate(by: .radians(-0.32))
        reflection.fill(Path(CGRect(x: -15, y: -15, width: 30, height: 30)), with: .linearGradient(
            Gradient(stops: [.init(color: .clear, location: 0), .init(color: Color(hex: 0xFFF9DF).opacity(0.4 - progress * 0.23), location: 0.35), .init(color: Color(hex: 0xF4EBBF).opacity(0.04), location: 0.47), .init(color: .clear, location: 0.6)]),
            startPoint: CGPoint(x: -8, y: -10), endPoint: CGPoint(x: 5, y: 6)))
        lens.stroke(ellipse(x: 0.7, y: 1, rx: 6.1, ry: 8.6), with: .color(Color(hex: 0xD3C180).opacity(0.16)), lineWidth: 0.16)
        var glint = Path()
        glint.addArc(center: .zero, radius: 1, startAngle: .radians(3.55), endAngle: .radians(4.8), clockwise: false, transform: CGAffineTransform(scaleX: 6.65, y: 9.3))
        lens.stroke(glint, with: .color(Color(hex: 0xFFF8D0).opacity(0.53)), lineWidth: 0.3)
    }

    private static func ellipse(x: Double, y: Double, rx: Double, ry: Double) -> Path {
        Path(ellipseIn: CGRect(x: x - rx, y: y - ry, width: 2 * rx, height: 2 * ry))
    }
}

private extension Color {
    nonisolated init(hex: UInt32) {
        self.init(.sRGB, red: Double((hex >> 16) & 255) / 255, green: Double((hex >> 8) & 255) / 255, blue: Double(hex & 255) / 255, opacity: 1)
    }
}

#Preview("Reveal") {
    JokerWinnerReveal(winnerName: "Khalid") {}
}

#Preview("Final frame") {
    JokerWinnerReveal(winnerName: "خالد", startTime: 4.6) {}
}
