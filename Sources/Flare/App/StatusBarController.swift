import AppKit

final class StatusBarController: NSObject {
    static weak var shared: StatusBarController?

    private let item: NSStatusItem
    private let onCaptureArea: () -> Void
    private let onCaptureWindow: () -> Void
    private let onCaptureScreen: () -> Void
    private let onCaptureDelay: () -> Void
    private let onHistory: () -> Void
    private let onSettings: () -> Void
    private let onHome: () -> Void
    private let onDocuments: () -> Void
    private let onQuit: () -> Void

    init(
        onCaptureArea: @escaping () -> Void,
        onCaptureWindow: @escaping () -> Void,
        onCaptureScreen: @escaping () -> Void,
        onCaptureDelay: @escaping () -> Void,
        onHistory: @escaping () -> Void,
        onSettings: @escaping () -> Void,
        onHome: @escaping () -> Void,
        onDocuments: @escaping () -> Void = { HomeWindowController.shared.showDocuments() },
        onQuit: @escaping () -> Void
    ) {
        self.onCaptureArea = onCaptureArea
        self.onCaptureWindow = onCaptureWindow
        self.onCaptureScreen = onCaptureScreen
        self.onCaptureDelay = onCaptureDelay
        self.onHistory = onHistory
        self.onSettings = onSettings
        self.onHome = onHome
        self.onDocuments = onDocuments
        self.onQuit = onQuit

        item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        super.init()

        if let button = item.button {
            button.image = FlareBrand.statusBarSymbol()
            button.toolTip = "\(FlareBrand.name) — 单击截图 · 右键菜单"
            button.target = self
            button.action = #selector(statusButtonClicked(_:))
            button.sendAction(on: [.leftMouseUp, .rightMouseUp])
        }

        // 不常驻挂 menu，保证左键可直接截图
        item.menu = nil
        StatusBarController.shared = self
    }

    func reloadMenu() {
        // 菜单按需弹出，无需预挂
    }

    @objc private func statusButtonClicked(_ sender: Any?) {
        guard let event = NSApp.currentEvent else {
            onCaptureArea()
            return
        }
        if event.type == .rightMouseUp || event.modifierFlags.contains(.control) {
            popMenu()
        } else {
            onCaptureArea()
        }
    }

    private func popMenu() {
        guard let button = item.button else { return }
        let menu = buildMenu()
        let loc = NSPoint(x: 0, y: button.bounds.height + 2)
        menu.popUp(positioning: nil, at: loc, in: button)
    }

    private func buildMenu() -> NSMenu {
        let menu = NSMenu()
        menu.autoenablesItems = false

        let header = NSMenuItem(title: "\(FlareBrand.name)  ·  \(FlareBrand.tagline)", action: nil, keyEquivalent: "")
        header.isEnabled = false
        menu.addItem(header)
        menu.addItem(.separator())

        menu.addItem(makeHot("区域截图", .area, .area, #selector(captureArea)))
        menu.addItem(makeHot("窗口截图", .window, .window, #selector(captureWindow)))
        menu.addItem(makeHot("全屏截图", .screen, .screen, #selector(captureScreen)))
        menu.addItem(makeHot("延时 3 秒", .delay, .delay, #selector(captureDelay)))
        let recordTitle = ScreenRecorder.shared.isRecording ? "停止录屏" : "屏幕录制"
        menu.addItem(makeHot(recordTitle, .record, .record, #selector(toggleRecord)))
        menu.addItem(.separator())

        menu.addItem(make("打开主面板", .home, "o", [.command], #selector(showHome)))
        menu.addItem(makeHot("历史记录", .history, .history, #selector(showHistory)))

        let recent = Array(HistoryStore.shared.items.prefix(3))
        if !recent.isEmpty {
            menu.addItem(.separator())
            let recentHeader = NSMenuItem(title: "最近截图", action: nil, keyEquivalent: "")
            recentHeader.isEnabled = false
            menu.addItem(recentHeader)
            for (idx, entry) in recent.enumerated() {
                let mi = NSMenuItem(title: "  \(entry.fileName)", action: #selector(openRecent(_:)), keyEquivalent: "")
                mi.tag = idx
                mi.target = self
                if let thumb = HistoryStore.shared.thumbnail(for: entry) {
                    let icon = thumb.copy() as? NSImage ?? thumb
                    icon.size = NSSize(width: 18, height: 18)
                    mi.image = icon
                }
                menu.addItem(mi)
            }
        }

        menu.addItem(.separator())
        let docsHeader = NSMenuItem(title: "新建文档", action: nil, keyEquivalent: "")
        docsHeader.isEnabled = false
        menu.addItem(docsHeader)
        menu.addItem(make("文本 TXT…", .txt, "n", [.command, .shift], #selector(createTXT)))
        menu.addItem(make("Word 文档…", .word, "", [], #selector(createWord)))
        menu.addItem(make("PPT 演示文稿…", .powerpoint, "", [], #selector(createPPT)))
        menu.addItem(make("表格 Excel…", .spreadsheet, "", [], #selector(createSpreadsheet)))
        menu.addItem(make("打开新建面板", .documents, "d", [.command, .shift], #selector(showDocuments)))
        menu.addItem(.separator())
        menu.addItem(make("偏好设置…", .settings, ",", [.command], #selector(showSettings)))
        menu.addItem(make("退出 \(FlareBrand.name)", .quit, "q", [.command], #selector(quit)))

        return menu
    }

    private func makeHot(
        _ title: String,
        _ glyph: SnapGlyph,
        _ actionKey: HotKeyAction,
        _ action: Selector
    ) -> NSMenuItem {
        let sc = AppSettings.shared.shortcut(for: actionKey)
        let item = NSMenuItem(
            title: "\(title)    \(sc.displayString)",
            action: action,
            keyEquivalent: sc.menuKeyEquivalent
        )
        item.keyEquivalentModifierMask = sc.menuKeyEquivalent.isEmpty ? [] : sc.nsModifierFlags
        item.target = self
        item.image = FlareBrand.menuSymbol(glyph)
        item.isEnabled = true
        return item
    }

    private func make(
        _ title: String,
        _ glyph: SnapGlyph,
        _ key: String,
        _ modifiers: NSEvent.ModifierFlags,
        _ action: Selector
    ) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: action, keyEquivalent: key)
        item.keyEquivalentModifierMask = key.isEmpty ? [] : modifiers
        item.target = self
        item.image = FlareBrand.menuSymbol(glyph)
        item.isEnabled = true
        return item
    }

    @objc private func captureArea() { onCaptureArea() }
    @objc private func captureWindow() { onCaptureWindow() }
    @objc private func captureScreen() { onCaptureScreen() }
    @objc private func captureDelay() { onCaptureDelay() }
    @objc private func toggleRecord() { ScreenRecorder.shared.toggle() }
    @objc private func showHistory() { onHistory() }
    @objc private func showSettings() { onSettings() }
    @objc private func showHome() { onHome() }
    @objc private func showDocuments() { onDocuments() }
    @objc private func quit() { onQuit() }

    @objc private func createTXT() {
        DocumentService.createAndReveal(.txt, askWhere: true)
    }
    @objc private func createWord() {
        DocumentService.createAndReveal(.word, askWhere: true)
    }
    @objc private func createPPT() {
        DocumentService.createAndReveal(.powerpoint, askWhere: true)
    }
    @objc private func createSpreadsheet() {
        DocumentService.createAndReveal(.spreadsheet, askWhere: true)
    }

    @objc private func openRecent(_ sender: NSMenuItem) {
        let items = Array(HistoryStore.shared.items.prefix(3))
        guard items.indices.contains(sender.tag),
              let image = HistoryStore.shared.image(for: items[sender.tag]) else { return }
        EditorWindowController.shared.present(image: image)
    }
}
