import SwiftUI
import AppKit

// MARK: - Native AppKit Visual Effect Wrapper (Vibrancy & Liquid Glass)

/// Bridges `NSVisualEffectView` to SwiftUI for authentic macOS HUD/Popover translucency.
public struct VisualEffectGlassView: NSViewRepresentable {
    public var material: NSVisualEffectView.Material
    public var blendingMode: NSVisualEffectView.BlendingMode
    public var state: NSVisualEffectView.State
    public var isEmphasized: Bool

    public init(
        material: NSVisualEffectView.Material = .popover,
        blendingMode: NSVisualEffectView.BlendingMode = .behindWindow,
        state: NSVisualEffectView.State = .active,
        isEmphasized: Bool = false
    ) {
        self.material = material
        self.blendingMode = blendingMode
        self.state = state
        self.isEmphasized = isEmphasized
    }

    public func makeNSView(context: Context) -> NSVisualEffectView {
        let view = NSVisualEffectView()
        view.material = material
        view.blendingMode = blendingMode
        view.state = state
        view.isEmphasized = isEmphasized
        return view
    }

    public func updateNSView(_ nsView: NSVisualEffectView, context: Context) {
        nsView.material = material
        nsView.blendingMode = blendingMode
        nsView.state = state
        nsView.isEmphasized = isEmphasized
    }
}

// MARK: - Liquid Glass Refraction Border & Surface Modifiers

/// Applies a translucent frosted-glass surface, luminous 1px refraction border,
/// and multi-layered ambient shadows matching macOS Sonoma/Sequoia/Tahoe aesthetics.
public struct LiquidGlassCardModifier: ViewModifier {
    @Environment(\.colorScheme) private var colorScheme
    public var cornerRadius: CGFloat
    public var padding: CGFloat
    public var isInteractive: Bool
    @State private var isHovered: Bool = false

    public init(cornerRadius: CGFloat = 12, padding: CGFloat = 12, isInteractive: Bool = true) {
        self.cornerRadius = cornerRadius
        self.padding = padding
        self.isInteractive = isInteractive
    }

    private var primaryBorderColor: Color {
        colorScheme == .dark
            ? Color.white.opacity(isHovered && isInteractive ? 0.26 : 0.15)
            : Color.black.opacity(isHovered && isInteractive ? 0.14 : 0.08)
    }

    private var surfaceTint: Color {
        if colorScheme == .dark {
            return Color.white.opacity(isHovered && isInteractive ? 0.075 : 0.045)
        } else {
            return Color.white.opacity(isHovered && isInteractive ? 0.68 : 0.52)
        }
    }

    public func body(content: Content) -> some View {
        // Performance: per-card blur materials + 2 large shadows were re-rendered for every
        // row (75+ deadlines, 300 files). Cards now use a flat translucent fill over the
        // window's single vibrancy layer, with one cheap shadow and no hover scale animation.
        content
            .padding(padding)
            .background(
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .fill(surfaceTint)
            )
            .overlay(
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .strokeBorder(primaryBorderColor, lineWidth: 1)
            )
            .shadow(
                color: Color.black.opacity(colorScheme == .dark ? 0.18 : 0.05),
                radius: 2,
                x: 0,
                y: 1
            )
            .onHover { hovering in
                guard isInteractive else { return }
                isHovered = hovering
            }
    }
}

/// Container surface modifier for the outer popover or settings sheet window.
public struct LiquidGlassWindowModifier: ViewModifier {
    @Environment(\.colorScheme) private var colorScheme
    public var cornerRadius: CGFloat

    public init(cornerRadius: CGFloat = 16) {
        self.cornerRadius = cornerRadius
    }

    private var outerBorderColor: Color {
        colorScheme == .dark ? Color.white.opacity(0.15) : Color.black.opacity(0.08)
    }

    public func body(content: Content) -> some View {
        content
            .background(
                ZStack {
                    VisualEffectGlassView(
                        material: .popover,
                        blendingMode: .behindWindow,
                        state: .active
                    )
                    RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                        .fill(.ultraThinMaterial.opacity(0.65))
                }
            )
            .overlay(
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .strokeBorder(outerBorderColor, lineWidth: 1)
            )
            .shadow(color: Color.black.opacity(0.28), radius: 16, x: 0, y: 8)
    }
}

public extension View {
    /// Styles any view as a luminous liquid-glass card with 1px refraction border and ambient depth.
    func liquidGlassCard(
        cornerRadius: CGFloat = 12,
        padding: CGFloat = 12,
        isInteractive: Bool = true
    ) -> some View {
        modifier(
            LiquidGlassCardModifier(
                cornerRadius: cornerRadius,
                padding: padding,
                isInteractive: isInteractive
            )
        )
    }

    /// Styles a top-level popover or sheet container with behind-window vibrancy and 1px border.
    func liquidGlassContainer(cornerRadius: CGFloat = 16) -> some View {
        modifier(LiquidGlassWindowModifier(cornerRadius: cornerRadius))
    }
}

// MARK: - Glow Status Badge

public enum SyncVisualState: Equatable, Sendable {
    case synced
    case checkingBrightspace
    case downloading(fileName: String)
    case uploadingToNotebook
    case authRequired
    case error(message: String)

    public var label: String {
        switch self {
        case .synced:
            return "All Courses Synced"
        case .checkingBrightspace:
            return "Checking Brightspace..."
        case .downloading(let fileName):
            return "Downloading \(fileName)..."
        case .uploadingToNotebook:
            return "Uploading to Notebook..."
        case .authRequired:
            return "Session Login Required"
        case .error(let message):
            return message
        }
    }

    public var tintColor: Color {
        switch self {
        case .synced:
            return Color(nsColor: .systemGreen)
        case .checkingBrightspace, .downloading:
            return Color(nsColor: .systemCyan)
        case .uploadingToNotebook:
            return Color(nsColor: .systemPurple)
        case .authRequired:
            return Color(nsColor: .systemOrange)
        case .error:
            return Color(nsColor: .systemRed)
        }
    }

    public var isBusy: Bool {
        switch self {
        case .checkingBrightspace, .downloading, .uploadingToNotebook:
            return true
        case .synced, .authRequired, .error:
            return false
        }
    }
}

/// Luminous status pill with a live pulsing indicator dot and glass border.
public struct GlowStatusBadge: View {
    public let state: SyncVisualState
    @Environment(\.colorScheme) private var colorScheme
    @State private var pulse: Bool = false

    public init(state: SyncVisualState) {
        self.state = state
    }

    public var body: some View {
        HStack(spacing: 7) {
            ZStack {
                Circle()
                    .fill(state.tintColor.opacity(0.35))
                    .frame(width: 14, height: 14)
                    .scaleEffect(state.isBusy && pulse ? 1.35 : 0.85)
                    .opacity(state.isBusy && pulse ? 0.0 : 0.7)

                Circle()
                    .fill(state.tintColor)
                    .frame(width: 7, height: 7)
                    .shadow(color: state.tintColor.opacity(0.85), radius: 5, x: 0, y: 0)
            }

            Text(state.label)
                .font(.system(size: 11.5, weight: .semibold, design: .default))
                .foregroundStyle(.primary)
                .lineLimit(1)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 5)
        .background(
            Capsule(style: .continuous)
                .fill(.thinMaterial)
                .overlay(
                    Capsule(style: .continuous)
                        .fill(state.tintColor.opacity(colorScheme == .dark ? 0.12 : 0.08))
                )
        )
        .overlay(
            Capsule(style: .continuous)
                .strokeBorder(
                    colorScheme == .dark ? Color.white.opacity(0.15) : Color.black.opacity(0.08),
                    lineWidth: 1
                )
        )
        .onAppear {
            withAnimation(.easeInOut(duration: 1.2).repeatForever(autoreverses: true)) {
                pulse = true
            }
        }
    }
}

// MARK: - Glass Capsule Button Style

public struct GlassActionButtonStyle: ButtonStyle {
    @Environment(\.colorScheme) private var colorScheme
    public var prominent: Bool

    public init(prominent: Bool = false) {
        self.prominent = prominent
    }

    public func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 12, weight: .medium, design: .default))
            .foregroundStyle(prominent ? Color.white : Color.primary)
            .padding(.horizontal, 11)
            .padding(.vertical, 6)
            .background(
                Group {
                    if prominent {
                        RoundedRectangle(cornerRadius: 8, style: .continuous)
                            .fill(
                                LinearGradient(
                                    colors: [
                                        Color.accentColor.opacity(configuration.isPressed ? 0.80 : 0.95),
                                        Color.accentColor.opacity(configuration.isPressed ? 0.65 : 0.78)
                                    ],
                                    startPoint: .top,
                                    endPoint: .bottom
                                )
                            )
                    } else {
                        RoundedRectangle(cornerRadius: 8, style: .continuous)
                            .fill(.ultraThinMaterial)
                            .overlay(
                                RoundedRectangle(cornerRadius: 8, style: .continuous)
                                    .fill(
                                        colorScheme == .dark
                                            ? Color.white.opacity(configuration.isPressed ? 0.12 : 0.06)
                                            : Color.black.opacity(configuration.isPressed ? 0.08 : 0.03)
                                    )
                            )
                    }
                }
            )
            .overlay(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .strokeBorder(
                        colorScheme == .dark ? Color.white.opacity(0.15) : Color.black.opacity(0.08),
                        lineWidth: 1
                    )
            )
            .scaleEffect(configuration.isPressed ? 0.97 : 1.0)
            .animation(.easeOut(duration: 0.12), value: configuration.isPressed)
    }
}

// MARK: - Course Code Tag Pill

public struct CourseTagBadge: View {
    public let courseCode: String
    public let accent: Color

    public init(courseCode: String, accent: Color = .cyan) {
        self.courseCode = courseCode
        self.accent = accent
    }

    public var body: some View {
        Text(courseCode)
            .font(.system(size: 10.5, weight: .bold, design: .monospaced))
            .foregroundStyle(accent)
            .padding(.horizontal, 7)
            .padding(.vertical, 2.5)
            .background(
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .fill(accent.opacity(0.14))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .strokeBorder(accent.opacity(0.28), lineWidth: 1)
            )
    }
}
