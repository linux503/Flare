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
            button.imageScaling = .scaleNone
            button.toolTip = "\(FlareBrand.name) — 单击截图 · 右键菜单"
            button.target = self
            button.action = #selector(statusButtonClicked(_:))
            button.sendAction(on: [.leftMouseUp, .rightMouseUp])
        }

        item.menu = nil
        StatusBarController.shared = self
    }

    func reloadMenu() {
        refreshRecordingAppearance()
    }

    func refreshRecordingAppearance() {
        guard let button = item.button else { return }
        let recording = ScreenRecorder.shared.isRecording || ScreenRecorder.shared.isCountingDown
        if recording {
            button.image = FlareBrand.statusBarRecordingSymbol()
            let t = ScreenRecorder.shared.isPaused
                ? "录屏已暂停"
                : (ScreenRecorder.shared.isCountingDown ? "录屏倒计时" : "正在录屏")
            button.toolTip = "\(FlareBrand.name) — \(t) · 单击停止 · 右键菜单"
        } else {
            button.image = FlareBrand.statusBarSymbol()
            button.toolTip = "\(FlareBrand.name) — 单击截图 · 右键菜单"
        }
    }

    @objc private func statusButtonClicked(_ sender: Any?) {
        guard let event = NSApp.currentEvent else {
            onCaptureArea()
            return
        }
        if event.type == .rightMouseUp || event.modifierFlags.contains(.control) {
            popMenu()
        } else if ScreenRecorder.shared.isRecording || ScreenRecorder.shared.isCountingDown {
            ScreenRecorder.shared.stop()
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
        menu.minimumWidth = 248

        menu.addItem(FlareMenu.brandHeader(subtitle: FlareMenu.recordingSubtitle()))
        menu.addItem(FlareMenu.separator())

        menu.addItem(FlareMenu.section("截图"))
        menu.addItem(hot("区域截图", .area, #selector(captureArea)))
        menu.addItem(hot("窗口截图", .window, #selector(captureWindow)))
        menu.addItem(hot("全屏截图", .screen, #selector(captureScreen)))
        menu.addItem(hot("延时 3 秒", .delay, #selector(captureDelay)))
        menu.addItem(FlareMenu.separator())

        menu.addItem(FlareMenu.section("录制"))
        appendRecordingItems(to: menu)
        menu.addItem(FlareMenu.separator())

        menu.addItem(FlareMenu.section("面板"))
        menu.addItem(item("打开主面板", .home, "o", [.command], #selector(showHome)))
        menu.addItem(hot("历史记录", .history, #selector(showHistory)))
        menu.addItem(item("录制面板", .record, "r", [.command, .shift], #selector(showRecordPane)))
        appendRecent(to: menu)
        menu.addItem(FlareMenu.separator())

        let docs = NSMenuItem(title: "新建文档", action: nil, keyEquivalent: "")
        docs.image = FlareBrand.menuSymbol(.documents)
        docs.submenu = documentsSubmenu()
        menu.addItem(docs)
        menu.addItem(FlareMenu.separator())

        menu.addItem(item("偏好设置…", .settings, ",", [.command], #selector(showSettings)))
        menu.addItem(item("退出 \(FlareBrand.name)", .quit, "q", [.command], #selector(quit)))

        return menu
    }

    private func appendRecordingItems(to menu: NSMenu) {
        let rec = ScreenRecorder.shared
        if rec.isRecording {
            menu.addItem(item(
                rec.isPaused ? "继续录屏" : "暂停录屏",
                rec.isPaused ? .play : .pause,
                "p", [.command],
                #selector(togglePauseRecord)
            ))
            menu.addItem(hot("停止并保存", .record, #selector(stopRecord), glyph: .stop))
            menu.addItem(item("丢弃录屏", .trash, "", [], #selector(discardRecord)))
        } else if rec.isCountingDown {
            menu.addItem(item("取消倒计时", .close, "", [], #selector(stopRecord)))
        } else {
            menu.addItem(hot("全屏录屏", .screen, #selector(startRecordFull)))
            menu.addItem(hot("区域录屏", .area, #selector(startRecordArea)))
            menu.addItem(item("立即开始（全屏）", .play, "", [], #selector(startRecordNow)))
        }
        menu.addItem(item("打开录屏文件夹", .folder, "", [], #selector(openRecordFolder)))
    }

    private func appendRecent(to menu: NSMenu) {
        let recent = Array(HistoryStore.shared.items.prefix(4))
        guard !recent.isEmpty else { return }
        menu.addItem(FlareMenu.separator())
        menu.addItem(FlareMenu.section("最近"))
        for (idx, entry) in recent.enumerated() {
            let title = entry.fileName
            let mi = NSMenuItem(title: title, action: #selector(openRecent(_:)), keyEquivalent: "")
            mi.tag = idx
            mi.target = self
            mi.isEnabled = true
            if let thumb = HistoryStore.shared.thumbnail(for: entry) {
                mi.image = FlareMenu.recentThumbnail(thumb)
            } else {
                mi.image = FlareBrand.menuSymbol(.history)
            }
            menu.addItem(mi)
        }
    }

    private func documentsSubmenu() -> NSMenu {
        let m = NSMenu(title: "新建文档")
        m.autoenablesItems = false
        m.addItem(item("文本 TXT…", .txt, "n", [.command, .shift], #selector(createTXT)))
        m.addItem(item("Word 文档…", .word, "", [], #selector(createWord)))
        m.addItem(item("PPT 演示文稿…", .powerpoint, "", [], #selector(createPPT)))
        m.addItem(item("表格 Excel…", .spreadsheet, "", [], #selector(createSpreadsheet)))
        m.addItem(FlareMenu.separator())
        m.addItem(item("打开新建面板", .documents, "d", [.command, .shift], #selector(showDocuments)))
        return m
    }

    private func hot(
        _ title: String,
        _ actionKey: HotKeyAction,
        _ action: Selector,
        glyph: SnapGlyph? = nil
    ) -> NSMenuItem {
        FlareMenu.hotItem(title, actionKey: actionKey, glyph: glyph, target: self, action: action)
    }

    private func item(
        _ title: String,
        _ glyph: SnapGlyph,
        _ key: String,
        _ modifiers: NSEvent.ModifierFlags,
        _ action: Selector
    ) -> NSMenuItem {
        FlareMenu.item(title, glyph: glyph, key: key, modifiers: modifiers, target: self, action: action)
    }

    @objc private func captureArea() { onCaptureArea() }
    @objc private func captureWindow() { onCaptureWindow() }
    @objc private func captureScreen() { onCaptureScreen() }
    @objc private func captureDelay() { onCaptureDelay() }
    @objc private func startRecordFull() { ScreenRecorder.shared.startFullScreen() }
    @objc private func startRecordArea() { ScreenRecorder.shared.startArea() }
    @objc private func startRecordNow() { ScreenRecorder.shared.startFullScreen(countdown: false) }
    @objc private func stopRecord() { ScreenRecorder.shared.stop() }
    @objc private func discardRecord() { ScreenRecorder.shared.cancelAndDiscard() }
    @objc private func togglePauseRecord() { ScreenRecorder.shared.togglePause() }
    @objc private func showRecordPane() { HomeWindowController.shared.showRecord() }
    @objc private func openRecordFolder() { ScreenRecorder.shared.openRecordingsFolder() }
    @objc private func showHistory() { onHistory() }
    @objc private func showSettings() { onSettings() }
    @objc private func showHome() { onHome() }
    @objc private func showDocuments() { onDocuments() }
    @objc private func quit() { onQuit() }

    @objc private func createTXT() { DocumentService.createAndReveal(.txt, askWhere: true) }
    @objc private func createWord() { DocumentService.createAndReveal(.word, askWhere: true) }
    @objc private func createPPT() { DocumentService.createAndReveal(.powerpoint, askWhere: true) }
    @objc private func createSpreadsheet() { DocumentService.createAndReveal(.spreadsheet, askWhere: true) }

    @objc private func openRecent(_ sender: NSMenuItem) {
        let items = Array(HistoryStore.shared.items.prefix(4))
        guard items.indices.contains(sender.tag),
              let image = HistoryStore.shared.image(for: items[sender.tag]) else { return }
        EditorWindowController.shared.present(image: image)
    }
}
