import SwiftUI
import AppKit

// MARK: - Liquid Glass Theme Preset

public enum LiquidGlassPreset: String, CaseIterable, Identifiable, Sendable {
    case tahoeClear = "Tahoe Clear"
    case tahoeFrost = "Tahoe Frost"
    case prismaticTint = "Prism Tint"

    public var id: String { rawValue }

    public var icon: String {
        switch self {
        case .tahoeClear: return "drop.halffull"
        case .tahoeFrost: return "sparkles"
        case .prismaticTint: return "prism.fill"
        }
    }
}

// MARK: - Native AppKit Visual Effect & Transparent Window Bridge

/// Configures the hosting NSWindow so behind-window vibrancy & Liquid Glass refraction work natively.
public struct TransparentWindowConfigurator: NSViewRepresentable {
    public init() {}

    public func makeNSView(context: Context) -> NSView {
        let view = NSView()
        DispatchQueue.main.async {
            if let window = view.window {
                window.isOpaque = false
                window.backgroundColor = .clear
                window.titlebarAppearsTransparent = true
                window.hasShadow = true
            }
        }
        return view
    }

    public func updateNSView(_ nsView: NSView, context: Context) {
        DispatchQueue.main.async {
            if let window = nsView.window {
                if window.isOpaque {
                    window.isOpaque = false
                }
                if window.backgroundColor != .clear {
                    window.backgroundColor = .clear
                }
            }
        }
    }
}

/// Bridges `NSVisualEffectView` to SwiftUI for authentic macOS HUD/Sidebar/Behind-Window translucency.
public struct VisualEffectGlassView: NSViewRepresentable {
    public var material: NSVisualEffectView.Material
    public var blendingMode: NSVisualEffectView.BlendingMode
    public var state: NSVisualEffectView.State
    public var isEmphasized: Bool

    public init(
        material: NSVisualEffectView.Material = .underWindowBackground,
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

// MARK: - macOS 26 Tahoe Liquid Glass Card & Window Modifiers

/// Applies a curved optical Liquid Glass lens surface, top specular sheen, and diagonal
/// 1px refraction rim light matching macOS 26 Tahoe aesthetics with zero per-row blur overhead.
public struct LiquidGlassCardModifier: ViewModifier {
    @Environment(\.colorScheme) private var colorScheme
    @AppStorage("BrightspaceSync.GlassPreset") private var presetRaw: String = LiquidGlassPreset.tahoeClear.rawValue
    public var cornerRadius: CGFloat
    public var padding: CGFloat
    public var isInteractive: Bool
    public var tint: Color?
    @State private var isHovered: Bool = false

    public init(
        cornerRadius: CGFloat = 13,
        padding: CGFloat = 12,
        isInteractive: Bool = true,
        tint: Color? = nil
    ) {
        self.cornerRadius = cornerRadius
        self.padding = padding
        self.isInteractive = isInteractive
        self.tint = tint
    }

    private var preset: LiquidGlassPreset {
        LiquidGlassPreset(rawValue: presetRaw) ?? .tahoeClear
    }

    private var lensGradient: LinearGradient {
        let activeHover = isHovered && isInteractive
        let baseTint = tint ?? Color.cyan

        if colorScheme == .dark {
            let topAlpha: Double = {
                switch preset {
                case .tahoeClear: return activeHover ? 0.14 : 0.095
                case .tahoeFrost: return activeHover ? 0.17 : 0.12
                case .prismaticTint: return activeHover ? 0.16 : 0.11
                }
            }()
            let midAlpha: Double = {
                switch preset {
                case .tahoeClear: return activeHover ? 0.055 : 0.032
                case .tahoeFrost: return activeHover ? 0.08 : 0.052
                case .prismaticTint: return activeHover ? 0.07 : 0.045
                }
            }()
            let botAlpha: Double = activeHover ? 0.075 : 0.045

            return LinearGradient(
                stops: [
                    .init(color: Color.white.opacity(topAlpha), location: 0.0),
                    .init(color: (tint != nil ? baseTint.opacity(activeHover ? 0.10 : 0.06) : Color.white.opacity(midAlpha)), location: 0.42),
                    .init(color: (preset == .prismaticTint ? baseTint.opacity(0.08) : Color.white.opacity(botAlpha)), location: 1.0)
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        } else {
            let topAlpha: Double = {
                switch preset {
                case .tahoeClear: return activeHover ? 0.82 : 0.68
                case .tahoeFrost: return activeHover ? 0.90 : 0.78
                case .prismaticTint: return activeHover ? 0.85 : 0.72
                }
            }()
            let midAlpha: Double = {
                switch preset {
                case .tahoeClear: return activeHover ? 0.56 : 0.42
                case .tahoeFrost: return activeHover ? 0.72 : 0.58
                case .prismaticTint: return activeHover ? 0.64 : 0.50
                }
            }()
            return LinearGradient(
                stops: [
                    .init(color: Color.white.opacity(topAlpha), location: 0.0),
                    .init(color: Color.white.opacity(midAlpha), location: 0.55),
                    .init(color: (tint != nil ? baseTint.opacity(0.14) : Color.white.opacity(midAlpha + 0.08)), location: 1.0)
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        }
    }

    private var specularRimGradient: LinearGradient {
        let activeHover = isHovered && isInteractive
        let rimTint = tint ?? Color.cyan

        if colorScheme == .dark {
            return LinearGradient(
                stops: [
                    .init(color: Color.white.opacity(activeHover ? 0.46 : 0.28), location: 0.0),
                    .init(color: Color.white.opacity(activeHover ? 0.14 : 0.08), location: 0.48),
                    .init(color: rimTint.opacity(activeHover ? 0.34 : 0.18), location: 1.0)
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        } else {
            return LinearGradient(
                stops: [
                    .init(color: Color.white.opacity(activeHover ? 0.96 : 0.84), location: 0.0),
                    .init(color: Color.black.opacity(activeHover ? 0.10 : 0.06), location: 0.50),
                    .init(color: rimTint.opacity(activeHover ? 0.36 : 0.22), location: 1.0)
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        }
    }

    public func body(content: Content) -> some View {
        content
            .padding(padding)
            .background(
                ZStack {
                    RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                        .fill(lensGradient)

                    // Top optical specular highlight curve
                    VStack(spacing: 0) {
                        LinearGradient(
                            colors: [
                                Color.white.opacity(colorScheme == .dark ? 0.11 : 0.45),
                                Color.clear
                            ],
                            startPoint: .top,
                            endPoint: .bottom
                        )
                        .frame(height: min(22, cornerRadius * 1.4))
                        Spacer(minLength: 0)
                    }
                    .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
                }
            )
            .overlay(
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .strokeBorder(specularRimGradient, lineWidth: 1)
            )
            .shadow(
                color: Color.black.opacity(colorScheme == .dark ? 0.22 : 0.06),
                radius: 3,
                x: 0,
                y: 1.5
            )
            .onHover { hovering in
                guard isInteractive else { return }
                isHovered = hovering
            }
    }
}

/// Container surface modifier for the outer desktop workspace, popover, or sheet window.
public struct LiquidGlassWindowModifier: ViewModifier {
    @Environment(\.colorScheme) private var colorScheme
    @AppStorage("BrightspaceSync.GlassPreset") private var presetRaw: String = LiquidGlassPreset.tahoeClear.rawValue
    public var cornerRadius: CGFloat

    public init(cornerRadius: CGFloat = 16) {
        self.cornerRadius = cornerRadius
    }

    private var preset: LiquidGlassPreset {
        LiquidGlassPreset(rawValue: presetRaw) ?? .tahoeClear
    }

    private var windowMaterial: NSVisualEffectView.Material {
        switch preset {
        case .tahoeClear:
            return .underWindowBackground
        case .tahoeFrost:
            return .hudWindow
        case .prismaticTint:
            return .fullScreenUI
        }
    }

    private var ambientTintGradient: LinearGradient {
        if colorScheme == .dark {
            switch preset {
            case .tahoeClear:
                return LinearGradient(
                    colors: [
                        Color.white.opacity(0.04),
                        Color.cyan.opacity(0.025),
                        Color.indigo.opacity(0.035)
                    ],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
            case .tahoeFrost:
                return LinearGradient(
                    colors: [
                        Color.white.opacity(0.07),
                        Color.cyan.opacity(0.03),
                        Color.black.opacity(0.14)
                    ],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
            case .prismaticTint:
                return LinearGradient(
                    colors: [
                        Color.cyan.opacity(0.09),
                        Color.purple.opacity(0.05),
                        Color.indigo.opacity(0.08)
                    ],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
            }
        } else {
            switch preset {
            case .tahoeClear:
                return LinearGradient(
                    colors: [
                        Color.white.opacity(0.32),
                        Color.cyan.opacity(0.04),
                        Color.white.opacity(0.22)
                    ],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
            case .tahoeFrost:
                return LinearGradient(
                    colors: [
                        Color.white.opacity(0.55),
                        Color.white.opacity(0.42)
                    ],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
            case .prismaticTint:
                return LinearGradient(
                    colors: [
                        Color.cyan.opacity(0.11),
                        Color.white.opacity(0.38),
                        Color.indigo.opacity(0.08)
                    ],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
            }
        }
    }

    private var outerRimGradient: LinearGradient {
        LinearGradient(
            stops: [
                .init(color: Color.white.opacity(colorScheme == .dark ? 0.36 : 0.85), location: 0.0),
                .init(color: Color.white.opacity(colorScheme == .dark ? 0.10 : 0.30), location: 0.5),
                .init(color: Color.cyan.opacity(colorScheme == .dark ? 0.24 : 0.30), location: 1.0)
            ],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
    }

    public func body(content: Content) -> some View {
        content
            .background(
                ZStack {
                    TransparentWindowConfigurator()
                    VisualEffectGlassView(
                        material: windowMaterial,
                        blendingMode: .behindWindow,
                        state: .active
                    )
                    RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                        .fill(ambientTintGradient)
                }
            )
            .overlay(
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .strokeBorder(outerRimGradient, lineWidth: 1)
            )
    }
}

// MARK: - Liquid Glass Pill & Progress Bar Components

/// Styles any capsule or rounded pill with macOS 26 Tahoe Liquid Glass refraction and top specular sheen.
public struct LiquidGlassPillModifier: ViewModifier {
    @Environment(\.colorScheme) private var colorScheme
    public var tint: Color
    public var isSelected: Bool
    public var cornerRadius: CGFloat?

    public init(tint: Color = .cyan, isSelected: Bool = false, cornerRadius: CGFloat? = nil) {
        self.tint = tint
        self.isSelected = isSelected
        self.cornerRadius = cornerRadius
    }

    private var fillGradient: LinearGradient {
        if isSelected {
            return LinearGradient(
                stops: [
                    .init(color: Color.white.opacity(colorScheme == .dark ? 0.22 : 0.72), location: 0.0),
                    .init(color: tint.opacity(colorScheme == .dark ? 0.26 : 0.22), location: 0.45),
                    .init(color: tint.opacity(colorScheme == .dark ? 0.18 : 0.15), location: 1.0)
                ],
                startPoint: .top,
                endPoint: .bottom
            )
        } else {
            return LinearGradient(
                stops: [
                    .init(color: Color.white.opacity(colorScheme == .dark ? 0.11 : 0.65), location: 0.0),
                    .init(color: Color.white.opacity(colorScheme == .dark ? 0.04 : 0.38), location: 1.0)
                ],
                startPoint: .top,
                endPoint: .bottom
            )
        }
    }

    private var borderGradient: LinearGradient {
        if isSelected {
            return LinearGradient(
                stops: [
                    .init(color: Color.white.opacity(colorScheme == .dark ? 0.55 : 0.95), location: 0.0),
                    .init(color: tint.opacity(0.55), location: 0.5),
                    .init(color: tint.opacity(0.35), location: 1.0)
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        } else {
            return LinearGradient(
                stops: [
                    .init(color: Color.white.opacity(colorScheme == .dark ? 0.26 : 0.78), location: 0.0),
                    .init(color: Color.white.opacity(colorScheme == .dark ? 0.07 : 0.22), location: 1.0)
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        }
    }

    public func body(content: Content) -> some View {
        if let r = cornerRadius {
            content
                .background(
                    RoundedRectangle(cornerRadius: r, style: .continuous)
                        .fill(fillGradient)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: r, style: .continuous)
                        .strokeBorder(borderGradient, lineWidth: 1)
                )
        } else {
            content
                .background(
                    Capsule(style: .continuous)
                        .fill(fillGradient)
                )
                .overlay(
                    Capsule(style: .continuous)
                        .strokeBorder(borderGradient, lineWidth: 1)
                )
        }
    }
}

/// Recessed Liquid Glass tube progress bar with luminous liquid fill and top specular lens reflection.
public struct LiquidGlassProgressBar: View {
    @Environment(\.colorScheme) private var colorScheme
    public let percentage: Double
    public let tint: Color
    public var height: CGFloat

    public init(percentage: Double, tint: Color = .cyan, height: CGFloat = 7) {
        self.percentage = percentage
        self.tint = tint
        self.height = height
    }

    public var body: some View {
        GeometryReader { geo in
            let clamped = CGFloat(min(100.0, max(0.0, percentage)) / 100.0)
            let fillWidth = max(height, geo.size.width * clamped)

            ZStack(alignment: .leading) {
                // Recessed glass tube track
                Capsule(style: .continuous)
                    .fill(
                        LinearGradient(
                            colors: [
                                Color.black.opacity(colorScheme == .dark ? 0.28 : 0.08),
                                Color.white.opacity(colorScheme == .dark ? 0.05 : 0.35)
                            ],
                            startPoint: .top,
                            endPoint: .bottom
                        )
                    )
                    .overlay(
                        Capsule(style: .continuous)
                            .strokeBorder(
                                Color.white.opacity(colorScheme == .dark ? 0.14 : 0.55),
                                lineWidth: 0.8
                            )
                    )

                // Luminous liquid fill with top specular reflection
                if percentage > 0 {
                    ZStack(alignment: .top) {
                        Capsule(style: .continuous)
                            .fill(
                                LinearGradient(
                                    colors: [
                                        tint.opacity(0.82),
                                        tint
                                    ],
                                    startPoint: .leading,
                                    endPoint: .trailing
                                )
                            )

                        // Top-half curved glass specular highlight
                        Capsule(style: .continuous)
                            .fill(
                                LinearGradient(
                                    colors: [
                                        Color.white.opacity(0.45),
                                        Color.white.opacity(0.0)
                                    ],
                                    startPoint: .top,
                                    endPoint: .bottom
                                )
                            )
                            .frame(height: height * 0.55)
                            .padding(.horizontal, 1.5)
                    }
                    .frame(width: fillWidth, height: height)
                }
            }
        }
        .frame(height: height)
    }
}

public extension View {
    /// Styles any view as a luminous macOS 26 Tahoe Liquid Glass card with specular rim light.
    func liquidGlassCard(
        cornerRadius: CGFloat = 13,
        padding: CGFloat = 12,
        isInteractive: Bool = true,
        tint: Color? = nil
    ) -> some View {
        modifier(
            LiquidGlassCardModifier(
                cornerRadius: cornerRadius,
                padding: padding,
                isInteractive: isInteractive,
                tint: tint
            )
        )
    }

    /// Styles a top-level window, popover, or sheet container with behind-window Liquid Glass refraction.
    func liquidGlassContainer(cornerRadius: CGFloat = 16) -> some View {
        modifier(LiquidGlassWindowModifier(cornerRadius: cornerRadius))
    }

    /// Styles a capsule or rounded pill with Liquid Glass specular highlight and refraction border.
    func liquidGlassPill(
        tint: Color = .cyan,
        isSelected: Bool = false,
        cornerRadius: CGFloat? = nil
    ) -> some View {
        modifier(
            LiquidGlassPillModifier(
                tint: tint,
                isSelected: isSelected,
                cornerRadius: cornerRadius
            )
        )
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

/// Luminous status pill with a live pulsing indicator dot and Liquid Glass rim.
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
                .font(.system(size: 11.5, weight: .semibold, design: .rounded))
                .foregroundStyle(.primary)
                .lineLimit(1)
        }
        .padding(.horizontal, 11)
        .padding(.vertical, 5)
        .liquidGlassPill(tint: state.tintColor, isSelected: true)
        .onAppear {
            withAnimation(.easeInOut(duration: 1.2).repeatForever(autoreverses: true)) {
                pulse = true
            }
        }
    }
}

// MARK: - Liquid Glass Capsule Button Style

public struct GlassActionButtonStyle: ButtonStyle {
    @Environment(\.colorScheme) private var colorScheme
    public var prominent: Bool

    public init(prominent: Bool = false) {
        self.prominent = prominent
    }

    public func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 12, weight: .semibold, design: .rounded))
            .foregroundStyle(prominent ? Color.white : Color.primary)
            .padding(.horizontal, 11)
            .padding(.vertical, 6)
            .background(
                Group {
                    if prominent {
                        RoundedRectangle(cornerRadius: 9, style: .continuous)
                            .fill(
                                LinearGradient(
                                    stops: [
                                        .init(color: Color.cyan.opacity(configuration.isPressed ? 0.85 : 0.95), location: 0.0),
                                        .init(color: Color.accentColor.opacity(configuration.isPressed ? 0.75 : 0.88), location: 0.55),
                                        .init(color: Color.indigo.opacity(configuration.isPressed ? 0.70 : 0.82), location: 1.0)
                                    ],
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing
                                )
                            )
                            .overlay(
                                VStack(spacing: 0) {
                                    LinearGradient(
                                        colors: [Color.white.opacity(0.38), Color.clear],
                                        startPoint: .top,
                                        endPoint: .bottom
                                    )
                                    .frame(height: 11)
                                    Spacer(minLength: 0)
                                }
                                .clipShape(RoundedRectangle(cornerRadius: 9, style: .continuous))
                            )
                    } else {
                        RoundedRectangle(cornerRadius: 9, style: .continuous)
                            .fill(
                                LinearGradient(
                                    colors: [
                                        Color.white.opacity(colorScheme == .dark ? (configuration.isPressed ? 0.18 : 0.12) : (configuration.isPressed ? 0.85 : 0.72)),
                                        Color.white.opacity(colorScheme == .dark ? (configuration.isPressed ? 0.09 : 0.05) : (configuration.isPressed ? 0.55 : 0.44))
                                    ],
                                    startPoint: .top,
                                    endPoint: .bottom
                                )
                            )
                    }
                }
            )
            .overlay(
                RoundedRectangle(cornerRadius: 9, style: .continuous)
                    .strokeBorder(
                        LinearGradient(
                            colors: [
                                Color.white.opacity(colorScheme == .dark ? (prominent ? 0.55 : 0.34) : 0.90),
                                (prominent ? Color.cyan : Color.white).opacity(colorScheme == .dark ? 0.14 : 0.25)
                            ],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        ),
                        lineWidth: 1
                    )
            )
            .scaleEffect(configuration.isPressed ? 0.97 : 1.0)
    }
}

// MARK: - Course Code Liquid Glass Tag Pill

public struct CourseTagBadge: View {
    @Environment(\.colorScheme) private var colorScheme
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
            .padding(.horizontal, 7.5)
            .padding(.vertical, 2.5)
            .liquidGlassPill(tint: accent, isSelected: true, cornerRadius: 6.5)
    }
}
