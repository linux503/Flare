import AppKit

/// 主菜单 / 状态栏菜单的统一视觉与构建工具
enum FlareMenu {
    // MARK: - Section / Header

    static func section(_ title: String) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: nil, keyEquivalent: "")
        item.isEnabled = false
        item.attributedTitle = NSAttributedString(
            string: title.uppercased(),
            attributes: [
                .font: NSFont.systemFont(ofSize: 10.5, weight: .semibold),
                .foregroundColor: NSColor.tertiaryLabelColor,
                .kern: 0.8
            ]
        )
        return item
    }

    /// 状态栏菜单顶部品牌条
    static func brandHeader(subtitle: String? = nil) -> NSMenuItem {
        let item = NSMenuItem()
        item.isEnabled = false
        item.view = BrandHeaderView(subtitle: subtitle ?? FlareBrand.tagline)
        return item
    }

    // MARK: - Items

    static func item(
        _ title: String,
        glyph: SnapGlyph? = nil,
        symbol: String? = nil,
        key: String = "",
        modifiers: NSEvent.ModifierFlags = [.command],
        target: AnyObject?,
        action: Selector?,
        enabled: Bool = true
    ) -> NSMenuItem {
        let mi = NSMenuItem(title: title, action: action, keyEquivalent: key)
        mi.keyEquivalentModifierMask = key.isEmpty ? [] : modifiers
        mi.target = target
        mi.isEnabled = enabled
        if let glyph {
            mi.image = FlareBrand.menuSymbol(glyph)
        } else if let symbol {
            mi.image = FlareBrand.menuSymbol(symbol)
        }
        return mi
    }

    /// 绑定全局热键：右侧用系统 keyEquivalent 展示，标题不再塞快捷键文字
    static func hotItem(
        _ title: String,
        actionKey: HotKeyAction,
        glyph: SnapGlyph? = nil,
        target: AnyObject?,
        action: Selector
    ) -> NSMenuItem {
        let sc = AppSettings.shared.shortcut(for: actionKey)
        let key = sc.menuKeyEquivalent
        let mi = NSMenuItem(title: title, action: action, keyEquivalent: key)
        mi.keyEquivalentModifierMask = key.isEmpty ? [] : sc.nsModifierFlags
        mi.target = target
        mi.isEnabled = true
        mi.image = FlareBrand.menuSymbol(glyph ?? SnapGlyph.forCapture(actionKey))
        // 多键名无法映射到 keyEquivalent 时，用 tip 提示
        if key.isEmpty, sc.isValid {
            mi.toolTip = sc.displayString
        }
        return mi
    }

    static func separator() -> NSMenuItem { .separator() }

    // MARK: - Thumbnails

    static func recentThumbnail(_ source: NSImage) -> NSImage {
        let side: CGFloat = 20
        let out = NSImage(size: NSSize(width: side, height: side))
        out.lockFocus()
        let path = NSBezierPath(roundedRect: NSRect(x: 0, y: 0, width: side, height: side), xRadius: 4, yRadius: 4)
        path.addClip()
        let src = source.size
        let scale = max(side / max(src.width, 1), side / max(src.height, 1))
        let draw = NSRect(
            x: (side - src.width * scale) / 2,
            y: (side - src.height * scale) / 2,
            width: src.width * scale,
            height: src.height * scale
        )
        source.draw(in: draw, from: .zero, operation: .copy, fraction: 1)
        out.unlockFocus()
        return out
    }

    static func recordingSubtitle() -> String {
        let rec = ScreenRecorder.shared
        if rec.isCountingDown { return "倒计时中…" }
        if rec.isPaused { return "已暂停 · \(formatDuration(rec.elapsedSeconds))" }
        if rec.isRecording { return "录制中 · \(formatDuration(rec.elapsedSeconds))" }
        return FlareBrand.tagline
    }

    private static func formatDuration(_ seconds: Int) -> String {
        let m = seconds / 60
        let s = seconds % 60
        return String(format: "%d:%02d", m, s)
    }
}

// MARK: - Brand header view

private final class BrandHeaderView: NSView {
    private let iconView = NSImageView()
    private let titleLabel = NSTextField(labelWithString: "")
    private let subtitleLabel = NSTextField(labelWithString: "")

    init(subtitle: String) {
        super.init(frame: NSRect(x: 0, y: 0, width: 248, height: 54))
        wantsLayer = true

        iconView.imageScaling = .scaleProportionallyUpOrDown
        iconView.wantsLayer = true
        iconView.layer?.cornerRadius = 7
        iconView.layer?.masksToBounds = true
        if let mark = FlareBrand.appMarkImage() {
            iconView.image = mark
        } else {
            iconView.image = FlareBrand.menuSymbol(.brand, pointSize: 16)
            iconView.contentTintColor = .labelColor
        }

        titleLabel.stringValue = FlareBrand.name
        titleLabel.font = .systemFont(ofSize: 13, weight: .semibold)
        titleLabel.textColor = .labelColor
        titleLabel.lineBreakMode = .byTruncatingTail

        subtitleLabel.stringValue = subtitle
        subtitleLabel.font = .systemFont(ofSize: 11, weight: .regular)
        subtitleLabel.textColor = .secondaryLabelColor
        subtitleLabel.lineBreakMode = .byTruncatingTail

        addSubview(iconView)
        addSubview(titleLabel)
        addSubview(subtitleLabel)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError() }

    override func layout() {
        super.layout()
        let pad: CGFloat = 14
        let icon: CGFloat = 28
        iconView.frame = NSRect(x: pad, y: (bounds.height - icon) / 2, width: icon, height: icon)
        let textX = iconView.frame.maxX + 10
        let textW = bounds.width - textX - pad
        titleLabel.frame = NSRect(x: textX, y: 26, width: textW, height: 17)
        subtitleLabel.frame = NSRect(x: textX, y: 10, width: textW, height: 15)
    }
}
