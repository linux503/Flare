import AppKit
import SwiftUI

/// 全应用统一图标目录：同一套 SF Symbol、字重与渲染方式
enum SnapGlyph: String, CaseIterable, Hashable {
    case brand
    case area
    case window
    case screen
    case delay
    case longShot
    case record
    case pause
    case play
    case stop
    case mic
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
    case translate
    case close
    case plus
    case power
    case quit
    case refresh
    case relaunch
    case undo
    case redo
    case stroke
    case link
    case update
    case about
    case mail
    case more
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
    case watermark

    /// 优先用系统符号；macOS 14–15 没有新符号时自动回退，避免空白图标
    var systemName: String { symbolCandidates[0] }

    var symbolCandidates: [String] {
        switch self {
        case .brand: return ["camera.aperture", "camera.viewfinder", "camera"]
        case .area: return ["viewfinder", "plus.viewfinder", "camera.viewfinder"]
        case .window: return ["macwindow", "rectangle.on.rectangle", "square.on.square"]
        case .screen: return ["display", "desktopcomputer"]
        case .delay: return ["timer"]
        case .longShot: return ["arrow.up.and.down.square", "arrow.up.arrow.down", "rectangle.split.1x2"]
        case .record: return ["record.circle", "circle.fill"]
        case .pause: return ["pause.circle", "pause"]
        case .play: return ["play.circle", "play.fill"]
        case .stop: return ["stop.circle", "stop.fill"]
        case .mic: return ["mic"]
        case .history: return ["clock.arrow.circlepath", "clock"]
        case .settings: return ["gearshape", "gear"]
        case .documents: return ["doc.badge.plus", "doc"]
        case .home: return ["square.grid.2x2", "square.grid.2x2.fill"]
        case .txt: return ["doc.text"]
        case .word: return ["doc.richtext", "doc.text"]
        case .powerpoint: return ["play.rectangle", "play.rectangle.fill"]
        case .spreadsheet: return ["tablecells"]
        case .folder: return ["folder"]
        case .permission: return ["lock.shield", "lock.fill"]
        case .success: return ["checkmark.circle.fill", "checkmark.circle"]
        case .warning: return ["exclamationmark.circle.fill", "exclamationmark.circle"]
        case .tip: return ["lightbulb"]
        case .trash: return ["trash"]
        case .copy: return ["doc.on.clipboard", "doc.on.doc"]
        case .edit: return ["pencil"]
        case .save: return ["square.and.arrow.down"]
        case .pin: return ["pin"]
        case .ocr: return ["text.viewfinder", "doc.text.magnifyingglass", "text.magnifyingglass", "doc.text"]
        case .translate: return ["translate", "character.bubble", "globe", "text.bubble"]
        case .close: return ["xmark"]
        case .plus: return ["plus.circle"]
        case .power, .quit: return ["power"]
        case .refresh: return ["arrow.clockwise"]
        case .relaunch: return ["arrow.triangle.2.circlepath", "arrow.2.circlepath", "arrow.clockwise"]
        case .undo: return ["arrow.uturn.backward"]
        case .redo: return ["arrow.uturn.forward"]
        case .stroke: return ["pencil.tip", "pencil"]
        case .link: return ["link"]
        case .update: return ["arrow.down.circle"]
        case .about: return ["info.circle"]
        case .mail: return ["envelope", "envelope.fill", "tray"]
        case .more: return ["ellipsis.circle", "ellipsis"]
        case .toolSelect: return ["arrow.up.left.and.arrow.down.right", "arrow.up.left.and.down.right.magnifyingglass", "cursorarrow"]
        case .toolPen: return ["pencil.tip", "pencil"]
        case .toolHighlight: return ["highlighter", "pencil.tip"]
        case .toolArrow: return ["arrow.up.right"]
        case .toolLine: return ["line.diagonal", "minus"]
        case .toolRect: return ["rectangle"]
        case .toolEllipse: return ["oval"]
        case .toolText: return ["textformat"]
        case .toolBlur: return ["checkerboard.rectangle", "square.grid.3x3", "square.grid.2x2"]
        case .toolNumber: return ["number.circle", "number"]
        case .toolStep: return ["list.number", "list.bullet"]
        case .watermark: return ["seal", "checkmark.seal", "signature", "sparkles"]
        }
    }

    private static var resolvedCache: [SnapGlyph: String] = [:]

    func resolvedSystemName() -> String {
        if let cached = Self.resolvedCache[self] { return cached }
        let name = symbolCandidates.first {
            NSImage(systemSymbolName: $0, accessibilityDescription: nil) != nil
        } ?? "circle"
        Self.resolvedCache[self] = name
        return name
    }

    /// iOS 设置 App 那种彩色图标底
    var iosTint: Color {
        switch self {
        case .area, .brand: return Color(red: 0.35, green: 0.34, blue: 0.84)
        case .window: return Color(red: 0.35, green: 0.78, blue: 0.98)
        case .screen: return Color(red: 0.35, green: 0.78, blue: 0.98)
        case .delay: return Color(red: 1, green: 0.584, blue: 0)
        case .longShot: return Color(red: 0.69, green: 0.32, blue: 0.87)
        case .record, .stop: return Color(red: 1, green: 0.231, blue: 0.188)
        case .play: return Color(red: 0.204, green: 0.78, blue: 0.349)
        case .pause: return Color(red: 1, green: 0.584, blue: 0)
        case .mic: return Color(red: 1, green: 0.231, blue: 0.188)
        case .history: return Color(red: 1, green: 0.584, blue: 0)
        case .settings: return Color(red: 0.557, green: 0.557, blue: 0.576)
        case .documents, .txt: return Color(red: 0.557, green: 0.557, blue: 0.576)
        case .word: return Color(red: 0.18, green: 0.46, blue: 0.85)
        case .powerpoint: return Color(red: 0.87, green: 0.37, blue: 0.23)
        case .spreadsheet: return Color(red: 0.20, green: 0.63, blue: 0.38)
        case .folder: return Color(red: 0.039, green: 0.518, blue: 1)
        case .permission: return Color(red: 0.204, green: 0.78, blue: 0.349)
        case .success: return Color(red: 0.204, green: 0.78, blue: 0.349)
        case .warning: return Color(red: 1, green: 0.584, blue: 0)
        case .tip: return Color(red: 1, green: 0.80, blue: 0)
        case .trash: return Color(red: 1, green: 0.231, blue: 0.188)
        case .copy: return Color(red: 0.557, green: 0.557, blue: 0.576)
        case .edit: return Color(red: 1, green: 0.80, blue: 0)
        case .save: return Color(red: 0.039, green: 0.518, blue: 1)
        case .pin: return Color(red: 1, green: 0.231, blue: 0.188)
        case .ocr: return Color(red: 0.35, green: 0.34, blue: 0.84)
        case .translate: return Color(red: 0.039, green: 0.518, blue: 1)
        case .close: return Color(red: 0.557, green: 0.557, blue: 0.576)
        case .plus: return Color(red: 0.204, green: 0.78, blue: 0.349)
        case .power, .quit: return Color(red: 0.557, green: 0.557, blue: 0.576)
        case .refresh, .relaunch, .update: return Color(red: 0.039, green: 0.518, blue: 1)
        case .undo, .redo: return Color(red: 0.557, green: 0.557, blue: 0.576)
        case .stroke: return Color(red: 1, green: 0.80, blue: 0)
        case .link: return Color(red: 0.557, green: 0.557, blue: 0.576)
        case .about: return Color(red: 0.039, green: 0.518, blue: 1)
        case .mail, .more: return Color(red: 0.039, green: 0.518, blue: 1)
        case .home: return Color(red: 0.35, green: 0.34, blue: 0.84)
        case .watermark: return Color(red: 0.86, green: 0.72, blue: 0.46)
        case .toolSelect, .toolPen, .toolHighlight, .toolArrow, .toolLine, .toolRect, .toolEllipse, .toolText, .toolBlur, .toolNumber, .toolStep:
            return Color(red: 0.039, green: 0.518, blue: 1)
        }
    }

    static func forCapture(_ action: HotKeyAction) -> SnapGlyph {
        switch action {
        case .area: return .area
        case .window: return .window
        case .screen: return .screen
        case .delay: return .delay
        case .longShot: return .longShot
        case .translate: return .translate
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
        Image(systemName: glyph.resolvedSystemName())
            .font(.system(size: size.points, weight: weight, design: .default))
            .symbolRenderingMode(.monochrome)
            .foregroundStyle(tint ?? theme.textPrimary.opacity(opacity))
    }
}

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
        menuSymbol(glyph.resolvedSystemName(), pointSize: pointSize)
    }

    static func menuSymbol(_ name: String, pointSize: CGFloat = 13) -> NSImage? {
        let base = NSImage.SymbolConfiguration(pointSize: pointSize, weight: .semibold)
        let mono = base.applying(.preferringMonochrome())
        guard let image = NSImage(systemSymbolName: name, accessibilityDescription: nil) else { return nil }
        image.isTemplate = true
        return image.withSymbolConfiguration(mono) ?? image.withSymbolConfiguration(base)
    }

    /// 菜单栏可用高度（随系统菜单栏厚度自适应，略留边距）
    static var statusBarIconSide: CGFloat {
        max(20, NSStatusBar.system.thickness - 1)
    }

    /// 菜单栏图标：跟随当前 Logo 预设（默认墨黑闪光）
    static func statusBarSymbol() -> NSImage? {
        if let mark = appMarkImage() {
            return prepareStatusBarImage(mark, asTemplate: false)
        }
        if let spark = LogoCatalog.presetImage(.spark) {
            return prepareStatusBarImage(spark, asTemplate: false)
        }
        return menuSymbol(.brand, pointSize: statusBarIconSide - 4)
    }

    /// 录屏中：红色录制点（非 template，保证菜单栏可见）
    static func statusBarRecordingSymbol() -> NSImage? {
        let side = statusBarIconSide
        let size = NSSize(width: side, height: side)
        let image = NSImage(size: size)
        image.lockFocus()
        NSColor.clear.setFill()
        NSBezierPath(rect: NSRect(origin: .zero, size: size)).fill()
        NSColor.systemRed.setFill()
        let inset = side * 0.22
        NSBezierPath(ovalIn: NSRect(x: inset, y: inset, width: size.width - inset * 2, height: size.height - inset * 2)).fill()
        image.unlockFocus()
        image.isTemplate = false
        return image
    }

    private static func prepareStatusBarImage(_ source: NSImage, asTemplate: Bool) -> NSImage {
        let side = statusBarIconSide
        let dest = NSRect(x: 0, y: 0, width: side, height: side)
        let image = NSImage(size: dest.size)
        image.lockFocus()
        if let ctx = NSGraphicsContext.current {
            ctx.imageInterpolation = .high
        }
        NSColor.clear.setFill()
        NSBezierPath(rect: dest).fill()

        let srcSize = source.size.width > 0 && source.size.height > 0
            ? source.size
            : NSSize(width: side, height: side)
        let pad: CGFloat = 0.5
        let maxSide = side - pad * 2
        let scale = min(maxSide / srcSize.width, maxSide / srcSize.height)
        let drawSize = NSSize(width: srcSize.width * scale, height: srcSize.height * scale)
        let draw = NSRect(
            x: (side - drawSize.width) / 2,
            y: (side - drawSize.height) / 2,
            width: drawSize.width,
            height: drawSize.height
        )
        // 与 Logo 生成器一致的 squircle 裁切，菜单栏小尺寸更清晰
        let corner = draw.width * 0.24
        let clip = NSBezierPath(roundedRect: draw, xRadius: corner, yRadius: corner)
        clip.addClip()
        source.draw(in: draw, from: NSRect(origin: .zero, size: srcSize), operation: .sourceOver, fraction: 1)
        image.unlockFocus()
        image.isTemplate = asTemplate
        return image
    }
}
