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
            button.toolTip = "\(FlareBrand.name) — 单击打开菜单"
            button.target = self
            button.action = #selector(statusButtonClicked(_:))
            button.sendAction(on: [.leftMouseUp, .rightMouseUp])
        }

        item.menu = nil
        StatusBarController.shared = self
    }

    func reloadMenu() {
        refreshStatusBarIcon()
    }

    func refreshStatusBarIcon() {
        guard let button = item.button else { return }
        let recording = ScreenRecorder.shared.isRecording || ScreenRecorder.shared.isCountingDown
        if recording {
            button.image = FlareBrand.statusBarRecordingSymbol()
            let clock = String(format: "%02d:%02d", ScreenRecorder.shared.elapsedSeconds / 60, ScreenRecorder.shared.elapsedSeconds % 60)
            let t = ScreenRecorder.shared.isPaused
                ? "录屏已暂停 \(clock)"
                : (ScreenRecorder.shared.isCountingDown ? "录屏倒计时" : "正在录屏 \(clock)")
            button.toolTip = "\(FlareBrand.name) — \(t) · 单击打开菜单"
        } else {
            button.image = FlareBrand.statusBarSymbol()
            button.toolTip = "\(FlareBrand.name) — 单击打开菜单"
        }
    }

    func refreshRecordingAppearance() {
        refreshStatusBarIcon()
    }

    @objc private func statusButtonClicked(_ sender: Any?) {
        popMenu()
    }

    private func popMenu() {
        guard let button = item.button else { return }
        let menu = buildMenu()
        let loc = NSPoint(x: 0, y: button.bounds.height + 2)
        menu.popUp(positioning: nil, at: loc, in: button)
    }

    /// 精简菜单：常用截图 / 录屏 + 主面板 / 设置 / 退出
    private func buildMenu() -> NSMenu {
        let menu = NSMenu()
        menu.autoenablesItems = false
        menu.minimumWidth = 220

        menu.addItem(FlareMenu.brandHeader(subtitle: FlareMenu.recordingSubtitle()))
        menu.addItem(FlareMenu.separator())

        let rec = ScreenRecorder.shared
        if rec.isRecording {
            menu.addItem(item(
                rec.isPaused ? "继续录屏" : "暂停录屏",
                rec.isPaused ? .play : .pause,
                "", [],
                #selector(togglePauseRecord)
            ))
            menu.addItem(hot("停止并保存", .record, #selector(stopRecord), glyph: .stop))
            menu.addItem(item("丢弃录屏", .trash, "", [], #selector(discardRecord)))
        } else if rec.isCountingDown {
            menu.addItem(item("取消倒计时", .close, "", [], #selector(stopRecord)))
        } else {
            menu.addItem(hot("区域截图", .area, #selector(captureArea)))
            menu.addItem(hot("窗口截图", .window, #selector(captureWindow)))
            menu.addItem(hot("全屏截图", .screen, #selector(captureScreen)))
            menu.addItem(FlareMenu.separator())
            menu.addItem(hot("开始录屏", .record, #selector(startRecordFull), glyph: .record))
        }

        menu.addItem(FlareMenu.separator())
        menu.addItem(item("打开主面板", .home, "", [], #selector(showHome)))
        menu.addItem(item("偏好设置…", .settings, ",", [.command], #selector(showSettings)))
        menu.addItem(item("退出 \(FlareBrand.name)", .quit, "q", [.command], #selector(quit)))

        return menu
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
    @objc private func startRecordFull() { ScreenRecorder.shared.startFullScreen() }
    @objc private func stopRecord() { ScreenRecorder.shared.stop() }
    @objc private func discardRecord() { ScreenRecorder.shared.cancelAndDiscard() }
    @objc private func togglePauseRecord() { ScreenRecorder.shared.togglePause() }
    @objc private func showSettings() { onSettings() }
    @objc private func showHome() { onHome() }
    @objc private func quit() { onQuit() }
}
