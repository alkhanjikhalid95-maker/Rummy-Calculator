import SwiftUI

/// Every player's running total across the rounds, as fine white lines over
/// the aura. Lower totals sit higher — up is winning. The leader's line is
/// drawn bold and dropped to the axis at the latest round.
struct ScoreChart: View {
    /// Per seat: the running total before round 1 (zero) and after each
    /// round played.
    let series: [[Int]]
    let names: [String]
    let leader: Int?
    var maxRounds = 9

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var played: Int { max(0, (series.first?.count ?? 1) - 1) }

    var body: some View {
        VStack(spacing: 8) {
            GeometryReader { geo in
                let size = geo.size
                let scale = Scale(series: series, maxRounds: maxRounds, size: size)

                ZStack(alignment: .topLeading) {
                    // Guides
                    ForEach(0..<4, id: \.self) { row in
                        Path { path in
                            let y = size.height * CGFloat(row) / 3
                            path.move(to: CGPoint(x: 0, y: y))
                            path.addLine(to: CGPoint(x: size.width, y: y))
                        }
                        .stroke(Color.white.opacity(0.18), style: StrokeStyle(lineWidth: 0.75, dash: [3, 5]))
                    }

                    // Other seats first, so the leader's line sits on top.
                    ForEach(drawOrder, id: \.self) { seat in
                        line(for: seat, scale: scale)
                    }

                    if let leader, played > 0, series.indices.contains(leader) {
                        let end = scale.point(round: played, total: series[leader][played])
                        Path { path in
                            path.move(to: end)
                            path.addLine(to: CGPoint(x: end.x, y: size.height))
                        }
                        .stroke(Color.white.opacity(0.5), lineWidth: 0.75)

                        Circle()
                            .fill(Color.white)
                            .frame(width: 7, height: 7)
                            .position(x: end.x, y: size.height)
                    }

                    // End points, with each player's initial.
                    ForEach(series.indices, id: \.self) { seat in
                        let end = scale.point(round: played, total: series[seat].last ?? 0)
                        let isLeader = seat == leader
                        ZStack {
                            Circle()
                                .fill(Color.white.opacity(isLeader ? 0.35 : 0.15))
                                .frame(width: isLeader ? 22 : 14, height: isLeader ? 22 : 14)
                            Circle()
                                .fill(Color.white)
                                .frame(width: isLeader ? 9 : 6, height: isLeader ? 9 : 6)
                        }
                        .position(end)

                        Text(initial(seat))
                            .font(.system(size: 11, weight: isLeader ? .semibold : .regular))
                            .foregroundStyle(Color.white.opacity(isLeader ? 1 : 0.75))
                            .position(x: min(end.x + 16, size.width - 6), y: end.y)
                    }
                }
                .animation(reduceMotion ? nil : .spring(response: 0.6, dampingFraction: 0.85), value: series)
            }

            // Round axis
            HStack(spacing: 0) {
                ForEach(0...maxRounds, id: \.self) { round in
                    Text(round == 0 ? "" : "\(round)")
                        .font(.system(size: 11, weight: round == played ? .semibold : .regular))
                        .foregroundStyle(Color.white.opacity(round == played ? 1 : 0.6))
                        .frame(maxWidth: .infinity)
                }
            }
        }
        .environment(\.layoutDirection, .leftToRight)
        .accessibilityElement()
        .accessibilityLabel(Text("مخطط النتائج"))
        .accessibilityValue(Text(accessibilitySummary))
    }

    private var drawOrder: [Int] {
        series.indices.filter { $0 != leader } + (leader.map { [$0] } ?? [])
    }

    private func initial(_ seat: Int) -> String {
        guard names.indices.contains(seat), let first = names[seat].first else { return "" }
        return String(first).uppercased()
    }

    private func line(for seat: Int, scale: Scale) -> some View {
        let isLeader = seat == leader
        let points = series[seat].enumerated().map { scale.point(round: $0.offset, total: $0.element) }
        return ChartLine(points: points)
            .stroke(
                Color.white.opacity(isLeader ? 1 : 0.45),
                style: StrokeStyle(lineWidth: isLeader ? 2 : 1.2, lineCap: .round, lineJoin: .round)
            )
            .keyframeAnimator(initialValue: CGFloat(1), trigger: reduceMotion ? 0 : played) { content, progress in
                content.mask(alignment: .leading) {
                    Rectangle().scaleEffect(x: progress, anchor: .leading)
                }
            } keyframes: { _ in
                MoveKeyframe(0.75)
                CubicKeyframe(1, duration: 0.8)
            }
    }

    private var accessibilitySummary: String {
        series.indices.map { seat in
            let name = names.indices.contains(seat) ? names[seat] : "P\(seat + 1)"
            return "\(name) \(series[seat].last ?? 0)"
        }
        .joined(separator: "، ")
    }

    /// Maps rounds and totals into the chart's box, best total at the top.
    private struct Scale {
        let maxRounds: Int
        let size: CGSize
        let low: Double
        let high: Double

        init(series: [[Int]], maxRounds: Int, size: CGSize) {
            self.maxRounds = maxRounds
            self.size = size
            let all = series.flatMap { $0 }
            let low = Double(all.min() ?? 0)
            let high = Double(all.max() ?? 0)
            let pad = max(60, (high - low) * 0.12)
            self.low = low - pad
            self.high = high + pad
        }

        func point(round: Int, total: Int) -> CGPoint {
            let x = size.width * CGFloat(round) / CGFloat(maxRounds)
            let fraction = (Double(total) - low) / max(1, high - low)
            return CGPoint(x: x, y: size.height * CGFloat(fraction))
        }
    }
}

/// A smooth line through points, eased between them.
private struct ChartLine: Shape {
    let points: [CGPoint]

    func path(in rect: CGRect) -> Path {
        var path = Path()
        guard let first = points.first else { return path }
        path.move(to: first)
        for (previous, point) in zip(points, points.dropFirst()) {
            let midX = (previous.x + point.x) / 2
            path.addCurve(
                to: point,
                control1: CGPoint(x: midX, y: previous.y),
                control2: CGPoint(x: midX, y: point.y)
            )
        }
        return path
    }
}
