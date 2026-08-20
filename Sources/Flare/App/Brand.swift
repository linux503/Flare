import AppKit
import SwiftUI

enum FlareBrand {
    /// 对外品牌名
    static let name = "Flare Pro"
    static let tagline = "一拍即得"
    static let version = "1.3.1"

    /// 官网 / 下载 / 更新源（GitHub Pages）
    static let websiteURL = "https://linux503.github.io/Flare/"
    static let downloadURL = "https://linux503.github.io/Flare/#download"
    static let githubURL = "https://github.com/linux503/Flare"
    static let updateFeedURL = "https://linux503.github.io/Flare/version.json"
    static let supportEmail = "https://github.com/linux503/Flare/issues"

    /// 兼容旧引用：跟随当前主题强调色
    static var accent: NSColor { ThemeController.shared.palette.accentNS }
    static var accentDeep: NSColor { accent.blended(withFraction: 0.25, of: .black) ?? accent }
    static var ink: NSColor { ThemeController.shared.palette.windowNS }
    static var inkSoft: NSColor { ink.blended(withFraction: 0.08, of: .white) ?? ink }

    static var glassFill: NSColor {
        let p = ThemeController.shared.palette
        return p.isDark
            ? NSColor(calibratedWhite: 1, alpha: 0.08)
            : NSColor(calibratedWhite: 0, alpha: 0.06)
    }
    static var glassStroke: NSColor {
        let p = ThemeController.shared.palette
        return p.isDark
            ? NSColor(calibratedWhite: 1, alpha: 0.14)
            : NSColor(calibratedWhite: 0, alpha: 0.12)
    }
    static var glassHighlight: NSColor {
        let p = ThemeController.shared.palette
        return p.isDark
            ? NSColor(calibratedWhite: 1, alpha: 0.2)
            : NSColor(calibratedWhite: 0, alpha: 0.08)
    }

    static var accentColor: Color { ThemeController.shared.palette.accent }
    static var accentDeepColor: Color { accentColor.opacity(0.75) }
    static var inkColor: Color { Color(nsColor: ink) }
    static var glassFillColor: Color { ThemeController.shared.palette.fill }
    static var glassStrokeColor: Color { ThemeController.shared.palette.stroke }
    static var glassHighlightColor: Color { ThemeController.shared.palette.strokeStrong }

    /// 兼容旧调用；新 UI 请用 ThemeCanvas + environment
    static var shellBackground: some View {
        ThemeCanvas(
            palette: ThemeController.shared.palette,
            opacity: ThemeController.shared.windowOpacity
        )
    }

    /// 当前选用的 Logo（设置里可换预设或自选图片）
    static func appMarkImage() -> NSImage? {
        LogoCatalog.currentImage()
    }
}

/// 应用内品牌标：与 Dock 同款完整 Logo（含深色底，保证墨黑主题也清晰）
struct FlareBrandMark: View {
    var size: CGFloat = 36
    var cornerRadius: CGFloat = 9
    @Environment(\.flareTheme) private var theme
    @State private var stamp = 0

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                .fill(Color(red: 0.12, green: 0.12, blue: 0.13))
            Group {
                if let image = FlareBrand.appMarkImage() {
                    Image(nsImage: image)
                        .resizable()
                        .interpolation(.high)
                        .aspectRatio(contentMode: .fit)
                } else {
                    SnapIcon(.brand, size: .title, opacity: 1, tint: .white)
                }
            }
        }
        .frame(width: size, height: size)
        .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                .strokeBorder(theme.strokeStrong, lineWidth: 1)
        )
        .id(stamp)
        .onReceive(NotificationCenter.default.publisher(for: .flareSettingsChanged)) { _ in
            stamp += 1
        }
        .accessibilityLabel(FlareBrand.name)
    }
}
