import AppKit
import SwiftUI

/// 全应用统一图标目录：同一套 SF Symbol、字重与渲染方式
enum SnapGlyph: String, CaseIterable {
    case brand
    case area
    case window
    case screen
    case delay
    case record
    case history
    case settings
    case documents
    case home
    case txt
    case word
    case powerpoint
    case spreadsheet
    case folder
    case permission
    case success
    case warning
    case tip
    case trash
    case copy
    case edit
    case save
    case pin
    case ocr
    case close
    case plus
    case power
    case quit
    case refresh
    case relaunch
    case undo
    case redo
    case stroke
    // 标注工具
    case toolSelect
    case toolPen
    case toolHighlight
    case toolArrow
    case toolLine
    case toolRect
    case toolEllipse
    case toolText
    case toolBlur
    case toolNumber
    case toolStep

    /// 轮廓为主的精致单色风格（状态类可用 filled）
    var systemName: String {
        switch self {
        case .brand: return "camera.aperture"
        case .area: return "viewfinder"
        case .window: return "macwindow"
        case .screen: return "display"
        case .delay: return "timer"
        case .record: return "record.circle"
        case .history: return "clock.arrow.circlepath"
        case .settings: return "gearshape"
        case .documents: return "doc.badge.plus"
        case .home: return "square.grid.2x2"
        case .txt: return "doc.text"
        case .word: return "doc.richtext"
        case .powerpoint: return "play.rectangle"
        case .spreadsheet: return "tablecells"
        case .folder: return "folder"
        case .permission: return "lock.shield"
        case .success: return "checkmark.circle.fill"
        case .warning: return "exclamationmark.circle.fill"
        case .tip: return "lightbulb"
        case .trash: return "trash"
        case .copy: return "doc.on.clipboard"
        case .edit: return "pencil"
        case .save: return "square.and.arrow.down"
        case .pin: return "pin"
        case .ocr: return "text.viewfinder"
        case .close: return "xmark"
        case .plus: return "plus.circle"
        case .power, .quit: return "power"
        case .refresh: return "arrow.clockwise"
        case .relaunch: return "arrow.triangle.2.circlepath"
        case .undo: return "arrow.uturn.backward"
        case .redo: return "arrow.uturn.forward"
        case .stroke: return "pencil.tip"
        case .toolSelect: return "arrow.up.left.and.arrow.down.right"
        case .toolPen: return "pencil.tip"
        case .toolHighlight: return "highlighter"
        case .toolArrow: return "arrow.up.right"
        case .toolLine: return "line.diagonal"
        case .toolRect: return "rectangle"
        case .toolEllipse: return "oval"
        case .toolText: return "textformat"
        case .toolBlur: return "checkerboard.rectangle"
        case .toolNumber: return "number.circle"
        case .toolStep: return "list.number"
        }
    }

    static func forCapture(_ action: HotKeyAction) -> SnapGlyph {
        switch action {
        case .area: return .area
        case .window: return .window
        case .screen: return .screen
        case .delay: return .delay
        case .record: return .record
        case .history: return .history
        }
    }
}

enum SnapIconSize {
    case caption   // 11
    case menu      // 13
    case body      // 15
    case title     // 18
    case hero      // 22
    case display   // 28

    var points: CGFloat {
        switch self {
        case .caption: return 11
        case .menu: return 13
        case .body: return 15
        case .title: return 18
        case .hero: return 22
        case .display: return 28
        }
    }
}

/// SwiftUI 统一图标
struct SnapIcon: View {
    let glyph: SnapGlyph
    var size: SnapIconSize = .body
    var weight: Font.Weight = .semibold
    var opacity: Double = 0.92
    var tint: Color? = nil
    @Environment(\.flareTheme) private var theme

    init(
        _ glyph: SnapGlyph,
        size: SnapIconSize = .body,
        weight: Font.Weight = .semibold,
        opacity: Double = 0.92,
        tint: Color? = nil
    ) {
        self.glyph = glyph
        self.size = size
        self.weight = weight
        self.opacity = opacity
        self.tint = tint
    }

    var body: some View {
        Image(systemName: glyph.systemName)
            .font(.system(size: size.points, weight: weight, design: .default))
            .symbolRenderingMode(.monochrome)
            .foregroundStyle(tint ?? theme.textPrimary.opacity(opacity))
    }
}

/// 玻璃底图标槽：卡片 / 主按钮统一容器
struct SnapIconWell: View {
    let glyph: SnapGlyph
    var side: CGFloat = 48
    var iconSize: SnapIconSize = .title
    var cornerRadius: CGFloat = 12
    @Environment(\.flareTheme) private var theme

    init(_ glyph: SnapGlyph, side: CGFloat = 48, iconSize: SnapIconSize = .title, cornerRadius: CGFloat = 12) {
        self.glyph = glyph
        self.side = side
        self.iconSize = iconSize
        self.cornerRadius = cornerRadius
    }

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                .fill(theme.fillStrong)
            RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                .strokeBorder(theme.stroke, lineWidth: 1)
            SnapIcon(glyph, size: iconSize, opacity: 0.95)
        }
        .frame(width: side, height: side)
    }
}

extension FlareBrand {
    /// AppKit / 菜单栏统一模板图标
    static func menuSymbol(_ glyph: SnapGlyph, pointSize: CGFloat = 13) -> NSImage? {
        menuSymbol(glyph.systemName, pointSize: pointSize)
    }

    static func menuSymbol(_ name: String, pointSize: CGFloat = 13) -> NSImage? {
        let base = NSImage.SymbolConfiguration(pointSize: pointSize, weight: .semibold)
        let mono = base.applying(.preferringMonochrome())
        guard let image = NSImage(systemSymbolName: name, accessibilityDescription: nil) else { return nil }
        image.isTemplate = true
        return image.withSymbolConfiguration(mono) ?? image.withSymbolConfiguration(base)
    }

    /// 菜单栏图标：透明底品牌剪影（template，深浅菜单栏都清晰）
    static func statusBarSymbol() -> NSImage? {
        let names = ["StatusBarIcon", "FlareIcon"]
        for name in names {
            if let url = Bundle.main.url(forResource: name, withExtension: "png"),
               let source = NSImage(contentsOf: url) {
                return prepareStatusBarImage(source)
            }
            if let source = NSImage(named: name) {
                return prepareStatusBarImage(source)
            }
        }
        return menuSymbol(.brand, pointSize: 14)
    }

    private static func prepareStatusBarImage(_ source: NSImage) -> NSImage {
        let image = (source.copy() as? NSImage) ?? source
        image.size = NSSize(width: 18, height: 18)
        image.isTemplate = true
        return image
    }
}
