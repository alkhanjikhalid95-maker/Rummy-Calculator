import SwiftUI

// MARK: - Palette

/// Soft and quiet: off-white canvas, near-black ink, and a mauve-to-sage aura
/// for the hero surfaces.
extension Color {
    nonisolated static let canvas       = Color(red: 0.949, green: 0.949, blue: 0.957)
    nonisolated static let ink          = Color(red: 0.067, green: 0.067, blue: 0.075)
    nonisolated static let inkSecondary = Color(red: 0.443, green: 0.443, blue: 0.478)
    nonisolated static let inkTertiary  = Color(red: 0.690, green: 0.690, blue: 0.710)
    nonisolated static let rule         = Color.black.opacity(0.07)

    nonisolated static let mauveLight = Color(red: 0.890, green: 0.808, blue: 0.859)
    nonisolated static let mauve      = Color(red: 0.792, green: 0.651, blue: 0.745)
    nonisolated static let mauveDeep  = Color(red: 0.663, green: 0.514, blue: 0.616)
    nonisolated static let taupe      = Color(red: 0.737, green: 0.706, blue: 0.651)
    nonisolated static let sage       = Color(red: 0.580, green: 0.663, blue: 0.525)
    nonisolated static let sageDeep   = Color(red: 0.412, green: 0.522, blue: 0.369)

    /// The one warm accent — current round, predictions.
    nonisolated static let ember    = Color(red: 0.929, green: 0.471, blue: 0.231)
    nonisolated static let positive = Color(red: 0.231, green: 0.549, blue: 0.361)
    nonisolated static let negative = Color(red: 0.827, green: 0.278, blue: 0.329)
}

// MARK: - Backgrounds

/// The plain canvas behind lists and sheets.
struct AppBackground: View {
    var body: some View {
        Color.canvas.ignoresSafeArea()
    }
}

/// Mauve melting into sage, drifting slowly. Still under Reduce Motion.
struct AuraGradient: View {
    var animated = true
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        TimelineView(.animation(minimumInterval: 1 / 20, paused: reduceMotion || !animated)) { timeline in
            let t = Float(timeline.date.timeIntervalSinceReferenceDate)
            let drift: Float = (reduceMotion || !animated) ? 0 : 1
            MeshGradient(
                width: 3,
                height: 3,
                points: [
                    [0, 0], [0.5, 0], [1, 0],
                    [0, 0.5],
                    [0.5 + drift * 0.12 * sin(t * 0.35), 0.48 + drift * 0.1 * cos(t * 0.27)],
                    [1, 0.5],
                    [0, 1], [0.5, 1], [1, 1],
                ],
                colors: [
                    .taupe, .mauveLight, Color(red: 0.62, green: 0.64, blue: 0.53),
                    .mauve, .mauve, .sage,
                    .mauveLight, .mauveDeep, .sageDeep,
                ]
            )
        }
    }
}

// MARK: - Glass

extension View {
    /// Frosted glass in `shape`: Liquid Glass on iOS 26, material before it,
    /// with a faint fill and a bright rim so it reads on any backdrop.
    @ViewBuilder
    func glass<S: Shape>(in shape: S, interactive: Bool = false) -> some View {
        let rimmed = self
            .background(Color.white.opacity(0.12), in: shape)
            .overlay(shape.stroke(Color.white.opacity(0.45), lineWidth: 0.75))
        if #available(iOS 26.0, *) {
            rimmed.glassEffect(interactive ? .regular.interactive() : .regular, in: shape)
        } else {
            rimmed.background(.ultraThinMaterial, in: shape)
        }
    }

    /// White card with a soft, wide shadow.
    func card(radius: CGFloat = 30, highlighted: Bool = false) -> some View {
        self
            .background(Color.white, in: RoundedRectangle(cornerRadius: radius, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: radius, style: .continuous)
                    .stroke(highlighted ? Color.ink : Color.clear, lineWidth: 1.5)
            )
            .shadow(color: .black.opacity(0.06), radius: 18, y: 8)
    }

    /// Light rounded sheet chrome shared by every modal.
    func themedSheet() -> some View {
        self
            .presentationBackground(Color.canvas)
            .presentationCornerRadius(36)
            .presentationDragIndicator(.visible)
    }
}

// MARK: - Buttons

/// Solid black pill — the one primary action on a screen.
struct InkButtonStyle: ButtonStyle {
    var height: CGFloat = 56

    func makeBody(configuration: Configuration) -> some View {
        Pill(configuration: configuration, height: height)
    }

    private struct Pill: View {
        let configuration: Configuration
        let height: CGFloat
        @Environment(\.isEnabled) private var isEnabled

        var body: some View {
            configuration.label
                .font(.system(size: 17, weight: .medium))
                .foregroundStyle(.white)
                .frame(maxWidth: .infinity)
                .frame(height: height)
                .background(isEnabled ? Color.ink : Color.inkTertiary, in: Capsule())
                .shadow(color: .black.opacity(configuration.isPressed || !isEnabled ? 0.06 : 0.2), radius: 14, y: 6)
                .scaleEffect(configuration.isPressed ? 0.97 : 1)
                .animation(.spring(response: 0.25, dampingFraction: 0.7), value: configuration.isPressed)
                .animation(.easeInOut(duration: 0.2), value: isEnabled)
        }
    }
}

/// White pill with a soft shadow — secondary actions.
struct SoftButtonStyle: ButtonStyle {
    var height: CGFloat = 52
    var tint: Color = .ink

    func makeBody(configuration: Configuration) -> some View {
        Pill(configuration: configuration, height: height, tint: tint)
    }

    private struct Pill: View {
        let configuration: Configuration
        let height: CGFloat
        let tint: Color
        @Environment(\.isEnabled) private var isEnabled

        var body: some View {
            configuration.label
                .font(.system(size: 15, weight: .medium))
                .foregroundStyle(isEnabled ? tint : Color.inkTertiary)
                .frame(maxWidth: .infinity)
                .frame(height: height)
                .background(Color.white, in: Capsule())
                .shadow(color: .black.opacity(configuration.isPressed ? 0.03 : 0.07), radius: 12, y: 5)
                .scaleEffect(configuration.isPressed ? 0.97 : 1)
                .animation(.spring(response: 0.25, dampingFraction: 0.7), value: configuration.isPressed)
                .animation(.easeInOut(duration: 0.2), value: isEnabled)
        }
    }
}

/// Shrinks slightly under the finger — for tiles and cards that are buttons.
struct PressableStyle: ButtonStyle {
    var scale: CGFloat = 0.94

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? scale : 1)
            .animation(.spring(response: 0.22, dampingFraction: 0.65), value: configuration.isPressed)
    }
}

// MARK: - Small pieces

/// Round icon button. `onAura` puts it in glass over the gradient; otherwise
/// it is a white disc with a soft shadow, like the canvas buttons.
struct IconPill: View {
    let systemName: String
    let label: LocalizedStringKey
    var isActive = false
    var onAura = false
    var size: CGFloat = 46
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            GlassCircle(systemName: systemName, isActive: isActive, onAura: onAura, size: size)
        }
        .buttonStyle(PressableStyle(scale: 0.9))
        .accessibilityLabel(Text(label))
    }
}

/// The look of `IconPill`, for buttons that need their own badges or effects.
struct GlassCircle: View {
    let systemName: String
    var isActive = false
    var onAura = false
    var size: CGFloat = 46

    var body: some View {
        let icon = Image(systemName: systemName)
            .font(.system(size: size * 0.36, weight: .regular))
            .frame(width: size, height: size)

        if isActive {
            icon
                .foregroundStyle(.white)
                .background(Color.ink, in: Circle())
                .shadow(color: .black.opacity(0.2), radius: 10, y: 4)
        } else if onAura {
            icon
                .foregroundStyle(.white)
                .glass(in: Circle(), interactive: true)
        } else {
            icon
                .foregroundStyle(Color.ink)
                .background(Color.white, in: Circle())
                .shadow(color: .black.opacity(0.07), radius: 12, y: 5)
        }
    }
}

/// Title row at the top of every sheet, with a close button.
struct SheetHeader: View {
    let title: LocalizedStringKey
    var subtitle: String?
    var onClose: (() -> Void)?

    var body: some View {
        HStack(alignment: .top) {
            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.system(size: 26, weight: .medium))
                    .foregroundStyle(Color.ink)
                if let subtitle {
                    Text(subtitle)
                        .font(.system(size: 14))
                        .foregroundStyle(Color.inkSecondary)
                        .contentTransition(.opacity)
                }
            }
            Spacer()
            if let onClose {
                IconPill(systemName: "xmark", label: "إغلاق", size: 40, action: onClose)
            }
        }
        .padding(.horizontal, 22)
        .padding(.top, 24)
        .padding(.bottom, 8)
    }
}

/// Small section label in grey. No letter-spacing: it pulls Arabic
/// letters apart.
struct EyebrowLabel: View {
    let text: LocalizedStringKey
    var onAura = false

    init(_ text: LocalizedStringKey, onAura: Bool = false) {
        self.text = text
        self.onAura = onAura
    }

    var body: some View {
        Text(text)
            .font(.system(size: 14, weight: .regular))
            .foregroundStyle(onAura ? Color.white.opacity(0.85) : Color.inkSecondary)
    }
}

/// Black capsule tag, like a category chip.
struct InkChip: View {
    let text: String
    var systemImage: String?

    var body: some View {
        HStack(spacing: 5) {
            if let systemImage {
                Image(systemName: systemImage)
                    .font(.system(size: 11, weight: .semibold))
            }
            Text(text)
                .font(.system(size: 13, weight: .medium))
                .lineLimit(1)
        }
        .foregroundStyle(.white)
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .background(Color.ink, in: Capsule())
    }
}

/// Glass capsule with a label, for values shown over the aura.
struct GlassTag: View {
    let text: String
    var systemImage: String?
    var font: Font = .system(size: 15, weight: .regular)

    var body: some View {
        HStack(spacing: 6) {
            if let systemImage {
                Image(systemName: systemImage)
                    .font(.system(size: 12, weight: .medium))
            }
            Text(text)
                .font(font)
                .lineLimit(1)
                .contentTransition(.interpolate)
        }
        .foregroundStyle(.white)
        .padding(.horizontal, 16)
        .padding(.vertical, 9)
        .glass(in: Capsule())
    }
}

// MARK: - Formatting

/// Elapsed seconds as `mm:ss`, or `h:mm:ss` past the hour.
func formatDuration(_ seconds: Int) -> String {
    let h = seconds / 3600
    let m = (seconds % 3600) / 60
    let s = seconds % 60
    if h > 0 {
        return String(format: "%d:%02d:%02d", h, m, s)
    }
    return String(format: "%02d:%02d", m, s)
}
