import AppKit
import SwiftUI

/// 界面主题：仅黑 / 白两套，保证对比与原生观感
enum AppThemeKind: String, CaseIterable, Identifiable {
    case ink
    case frost

    var id: String { rawValue }

    var title: String {
        switch self {
        case .ink: return "墨黑"
        case .frost: return "霜白"
        }
    }

    var subtitle: String {
        switch self {
        case .ink: return "深色界面 · 夜间舒适"
        case .frost: return "浅色界面 · 日间清晰"
        }
    }

    var palette: FlarePalette {
        switch self {
        case .ink:
            return FlarePalette(
                isDark: true,
                windowNS: NSColor(calibratedRed: 0.07, green: 0.07, blue: 0.08, alpha: 1),
                canvasTop: Color(red: 0.12, green: 0.12, blue: 0.13),
                canvasBottom: Color(red: 0.05, green: 0.05, blue: 0.055),
                glow: Color.white.opacity(0.05),
                sidebar: Color(red: 0.09, green: 0.09, blue: 0.10),
                textPrimary: Color.white.opacity(0.96),
                textSecondary: Color.white.opacity(0.62),
                textMuted: Color.white.opacity(0.42),
                accent: Color(red: 0.94, green: 0.94, blue: 0.95),
                accentNS: NSColor(calibratedWhite: 0.94, alpha: 1),
                fill: Color.white.opacity(0.07),
                fillStrong: Color.white.opacity(0.13),
                stroke: Color.white.opacity(0.12),
                strokeStrong: Color.white.opacity(0.24),
                inverseFill: Color.white.opacity(0.94),
                inverseText: Color.black.opacity(0.88),
                warning: Color(red: 1.0, green: 0.62, blue: 0.28),
                success: Color(red: 0.45, green: 0.86, blue: 0.58)
            )
        case .frost:
            // 提高次级/弱文字对比，避免「看不清」
            return FlarePalette(
                isDark: false,
                windowNS: NSColor(calibratedRed: 0.96, green: 0.965, blue: 0.97, alpha: 1),
                canvasTop: Color(red: 0.985, green: 0.987, blue: 0.99),
                canvasBottom: Color(red: 0.93, green: 0.935, blue: 0.945),
                glow: Color.black.opacity(0.04),
                sidebar: Color(red: 0.94, green: 0.945, blue: 0.955),
                textPrimary: Color(red: 0.08, green: 0.09, blue: 0.11),
                textSecondary: Color(red: 0.22, green: 0.24, blue: 0.28),
                textMuted: Color(red: 0.36, green: 0.38, blue: 0.42),
                accent: Color(red: 0.12, green: 0.13, blue: 0.16),
                accentNS: NSColor(calibratedRed: 0.12, green: 0.13, blue: 0.16, alpha: 1),
                fill: Color.black.opacity(0.045),
                fillStrong: Color.black.opacity(0.08),
                stroke: Color.black.opacity(0.10),
                strokeStrong: Color.black.opacity(0.18),
                inverseFill: Color(red: 0.12, green: 0.13, blue: 0.16),
                inverseText: Color.white.opacity(0.96),
                warning: Color(red: 0.82, green: 0.38, blue: 0.08),
                success: Color(red: 0.10, green: 0.52, blue: 0.32)
            )
        }
    }

    var swatches: [Color] {
        let p = palette
        return [p.canvasBottom, p.canvasTop, p.accent, p.fillStrong]
    }

    /// 旧主题兼容
    static func migrated(from raw: String?) -> AppThemeKind {
        switch raw {
        case "frost": return .frost
        case "pine", "reef", "ink", .none: return .ink
        default: return AppThemeKind(rawValue: raw ?? "") ?? .ink
        }
    }
}

struct FlarePalette {
    let isDark: Bool
    let windowNS: NSColor
    let canvasTop: Color
    let canvasBottom: Color
    let glow: Color
    let sidebar: Color
    let textPrimary: Color
    let textSecondary: Color
    let textMuted: Color
    let accent: Color
    let accentNS: NSColor
    let fill: Color
    let fillStrong: Color
    let stroke: Color
    let strokeStrong: Color
    let inverseFill: Color
    let inverseText: Color
    let warning: Color
    let success: Color

    var preferredColorScheme: ColorScheme { isDark ? .dark : .light }
    var nsAppearance: NSAppearance? {
        NSAppearance(named: isDark ? .darkAqua : .aqua)
    }
}

private struct FlareThemeKey: EnvironmentKey {
    static let defaultValue = AppThemeKind.ink.palette
}

extension EnvironmentValues {
    var flareTheme: FlarePalette {
        get { self[FlareThemeKey.self] }
        set { self[FlareThemeKey.self] = newValue }
    }
}

final class ThemeController: ObservableObject {
    static let shared = ThemeController()

    @Published var kind: AppThemeKind {
        didSet {
            guard oldValue != kind else { return }
            AppSettings.shared.appTheme = kind
            NotificationCenter.default.post(name: .flareThemeChanged, object: kind)
        }
    }

    @Published var windowOpacity: Double {
        didSet {
            let clamped = min(1, max(0.72, windowOpacity))
            if clamped != windowOpacity {
                windowOpacity = clamped
                return
            }
            AppSettings.shared.windowOpacity = clamped
            NotificationCenter.default.post(name: .flareThemeChanged, object: kind)
        }
    }

    var palette: FlarePalette { kind.palette }

    private init() {
        kind = AppSettings.shared.appTheme
        windowOpacity = AppSettings.shared.windowOpacity
    }

    func set(_ kind: AppThemeKind) {
        withAnimation(.easeInOut(duration: 0.24)) {
            self.kind = kind
        }
    }

    func setOpacity(_ value: Double) {
        withAnimation(.easeOut(duration: 0.15)) {
            windowOpacity = value
        }
    }
}

/// 原生毛玻璃背景
struct VisualEffectView: NSViewRepresentable {
    var material: NSVisualEffectView.Material
    var blendingMode: NSVisualEffectView.BlendingMode = .behindWindow
    var state: NSVisualEffectView.State = .active

    func makeNSView(context: Context) -> NSVisualEffectView {
        let view = NSVisualEffectView()
        view.material = material
        view.blendingMode = blendingMode
        view.state = state
        view.isEmphasized = true
        return view
    }

    func updateNSView(_ nsView: NSVisualEffectView, context: Context) {
        nsView.material = material
        nsView.blendingMode = blendingMode
        nsView.state = state
    }
}

struct ThemeCanvas: View {
    let palette: FlarePalette
    var opacity: Double = 1

    var body: some View {
        ZStack {
            if opacity < 0.98 {
                VisualEffectView(
                    material: palette.isDark ? .hudWindow : .sheet,
                    blendingMode: .behindWindow
                )
            }
            LinearGradient(
                colors: [
                    palette.canvasTop.opacity(opacity < 0.98 ? 0.82 : 1),
                    palette.canvasBottom.opacity(opacity < 0.98 ? 0.78 : 1)
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            if opacity >= 0.98 {
                RadialGradient(
                    colors: [palette.glow, .clear],
                    center: .topTrailing,
                    startRadius: 40,
                    endRadius: 420
                )
            }
        }
        .ignoresSafeArea()
    }
}

extension Notification.Name {
    static let flareThemeChanged = Notification.Name("flareThemeChanged")
}
