import AppKit

/// Dock / 菜单栏顶部的应用主菜单
final class MainMenuController: NSObject {
    static weak var shared: MainMenuController?

    func install() {
        MainMenuController.shared = self
        reload()
    }

    func reload() {
        let main = NSMenu()

        let appMenuItem = NSMenuItem()
        let appMenu = NSMenu()
        appMenu.addItem(item(L("关于 %@", FlareBrand.name), #selector(showAbout), key: "", glyph: .about))
        appMenu.addItem(.separator())
        appMenu.addItem(item(L("检查更新…"), #selector(checkUpdate), key: "", glyph: .update))
        appMenu.addItem(item(L("偏好设置…"), #selector(showSettings), key: ",", glyph: .settings))
        appMenu.addItem(.separator())
        appMenu.addItem(item(L("隐藏 %@", FlareBrand.name), #selector(NSApplication.hide(_:)), key: "h", target: NSApp))
        appMenu.addItem(item(L("隐藏其他"), #selector(NSApplication.hideOtherApplications(_:)), key: "h", modifiers: [.command, .option], target: NSApp))
        appMenu.addItem(item(L("显示全部"), #selector(NSApplication.unhideAllApplications(_:)), key: "", target: NSApp))
        appMenu.addItem(.separator())
        appMenu.addItem(item(L("退出 %@", FlareBrand.name), #selector(NSApplication.terminate(_:)), key: "q", target: NSApp, glyph: .quit))
        appMenuItem.submenu = appMenu
        main.addItem(appMenuItem)

        let captureItem = NSMenuItem()
        captureItem.submenu = {
            let m = NSMenu(title: L("截图"))
            m.addItem(hotItem(L("区域截图"), .area, #selector(captureArea)))
            m.addItem(hotItem(L("窗口截图"), .window, #selector(captureWindow)))
            m.addItem(hotItem(L("全屏截图"), .screen, #selector(captureScreen)))
            m.addItem(hotItem(L("延时截图"), .delay, #selector(captureDelay)))
            m.addItem(hotItem(L("长截图"), .longShot, #selector(captureLong)))
            m.addItem(hotItem(L("翻译"), .translate, #selector(captureTranslate)))
            m.addItem(item(L("网页证据快照…"), #selector(showEvidence), key: "", glyph: .link))
            m.addItem(item(L("临邮"), #selector(showMailbox), key: "", glyph: .mail))
            m.addItem(.separator())
            m.addItem(item(L("打开主面板"), #selector(showHome), key: "o", glyph: .home))
            m.addItem(hotItem(L("历史记录"), .history, #selector(showHistory)))
            m.addItem(.separator())
            m.addItem(item(L("打开截图文件夹"), #selector(openSaveFolder), key: "", glyph: .folder))
            return m
        }()
        main.addItem(captureItem)

        let recordItem = NSMenuItem()
        recordItem.submenu = {
            let m = NSMenu(title: L("录制"))
            let rec = ScreenRecorder.shared
            if rec.isRecording {
                if rec.isPaused {
                    m.addItem(item(L("继续录屏"), #selector(togglePauseRecord), key: "p", glyph: .play))
                } else {
                    m.addItem(item(L("暂停录屏"), #selector(togglePauseRecord), key: "p", glyph: .pause))
                }
                m.addItem(hotItem(L("停止并保存"), .record, #selector(stopRecord), glyph: .stop))
                m.addItem(item(L("丢弃录屏"), #selector(discardRecord), key: "", glyph: .trash))
            } else if rec.isCountingDown {
                m.addItem(item(L("取消倒计时"), #selector(stopRecord), key: "", glyph: .close))
            } else {
                // 与设置中心「屏幕录制」快捷键一致
                m.addItem(hotItem(L("开始录屏（%@）", AppSettings.shared.recordMode.displayName), .record, #selector(startRecord), glyph: .record))
                m.addItem(item(L("立即开始"), #selector(startRecordNow), key: "", glyph: .play))
                m.addItem(.separator())
                m.addItem(item(L("全屏录屏"), #selector(startRecordFull), key: "", glyph: .screen))
                m.addItem(item(L("区域录屏"), #selector(startRecordArea), key: "", glyph: .area))
                m.addItem(item(L("窗口录屏"), #selector(startRecordWindow), key: "", glyph: .window))
            }
            m.addItem(.separator())
            m.addItem(item(L("打开录制面板"), #selector(showRecord), key: "r", modifiers: [.command, .shift], glyph: .record))
            m.addItem(item(L("打开录屏文件夹"), #selector(openRecordFolder), key: "", glyph: .folder))
            return m
        }()
        main.addItem(recordItem)

        let newItem = NSMenuItem()
        newItem.submenu = {
            let m = NSMenu(title: L("新建"))
            m.addItem(item(L("文本 TXT…"), #selector(createTXT), key: "n", modifiers: [.command, .shift], glyph: .txt))
            m.addItem(item(L("Word 文档…"), #selector(createWord), key: "", glyph: .word))
            m.addItem(item(L("PPT 演示文稿…"), #selector(createPPT), key: "", glyph: .powerpoint))
            m.addItem(item(L("表格 Excel…"), #selector(createSpreadsheet), key: "", glyph: .spreadsheet))
            m.addItem(.separator())
            m.addItem(item(L("打开新建面板"), #selector(showDocuments), key: "d", modifiers: [.command, .shift], glyph: .documents))
            m.addItem(item(L("打开文档文件夹"), #selector(openDocumentFolder), key: "", glyph: .folder))
            return m
        }()
        main.addItem(newItem)

        let toolsItem = NSMenuItem()
        toolsItem.submenu = {
            let m = NSMenu(title: L("工具"))
            m.addItem(hotItem(L("翻译"), .translate, #selector(captureTranslate)))
            m.addItem(item(L("临邮"), #selector(showMailbox), key: "", glyph: .mail))
            m.addItem(item(L("网页证据快照…"), #selector(showEvidence), key: "", glyph: .link))
            return m
        }()
        main.addItem(toolsItem)

        let windowItem = NSMenuItem()
        let windowMenu = NSMenu(title: L("窗口"))
        windowMenu.addItem(item(L("最小化"), #selector(NSWindow.performMiniaturize(_:)), key: "m"))
        windowMenu.addItem(item(L("缩放"), #selector(NSWindow.performZoom(_:)), key: ""))
        windowMenu.addItem(.separator())
        windowMenu.addItem(item(L("前置全部窗口"), #selector(NSApplication.arrangeInFront(_:)), key: "", target: NSApp))
        windowItem.submenu = windowMenu
        main.addItem(windowItem)

        let helpItem = NSMenuItem()
        let helpMenu = NSMenu(title: L("帮助"))
        helpMenu.addItem(item(L("屏幕录制权限…"), #selector(openPermission), key: "", glyph: .permission))
        helpMenu.addItem(item(L("检查更新…"), #selector(checkUpdate), key: "", glyph: .update))
        helpMenu.addItem(.separator())
        helpMenu.addItem(item(L("官方网站"), #selector(openWebsite), key: "", glyph: .link))
        helpMenu.addItem(item(L("GitHub 仓库"), #selector(openGitHub), key: "", glyph: .link))
        helpItem.submenu = helpMenu
        main.addItem(helpItem)

        NSApp.mainMenu = main
        main.items.first?.submenu?.title = FlareBrand.name
    }

    private func hotItem(
        _ title: String,
        _ action: HotKeyAction,
        _ selector: Selector,
        glyph: SnapGlyph? = nil
    ) -> NSMenuItem {
        FlareMenu.hotItem(title, actionKey: action, glyph: glyph, target: self, action: selector)
    }

    private func item(
        _ title: String,
        _ action: Selector,
        key: String,
        modifiers: NSEvent.ModifierFlags = [.command],
        target: AnyObject? = nil,
        glyph: SnapGlyph? = nil
    ) -> NSMenuItem {
        FlareMenu.item(
            title,
            glyph: glyph,
            key: key,
            modifiers: modifiers,
            target: target ?? self,
            action: action
        )
    }

    @objc private func showAbout() { HomeWindowController.shared.showAbout() }
    @objc private func showSettings() { HomeWindowController.shared.showSettings() }
    @objc private func showHome() { HomeWindowController.shared.show() }
    @objc private func showHistory() { HomeWindowController.shared.showHistory() }
    @objc private func showDocuments() { HomeWindowController.shared.showDocuments() }
    @objc private func captureArea() { CaptureCoordinator.shared.startAreaCapture() }
    @objc private func captureWindow() { CaptureCoordinator.shared.startWindowCapture() }
    @objc private func captureScreen() { CaptureCoordinator.shared.startFullScreenCapture() }
    @objc private func captureDelay() { CaptureCoordinator.shared.startDelayedCapture(seconds: 3) }
    @objc private func captureLong() { CaptureCoordinator.shared.startLongAreaCapture() }
    @objc private func captureTranslate() { CaptureCoordinator.shared.startTranslateCapture() }
    @objc private func showEvidence() { EvidenceWindowController.shared.show() }
    @objc private func startRecord() { ScreenRecorder.shared.start() }
    @objc private func startRecordFull() { ScreenRecorder.shared.startFullScreen() }
    @objc private func startRecordArea() { ScreenRecorder.shared.startArea() }
    @objc private func startRecordWindow() { ScreenRecorder.shared.startWindow() }
    @objc private func startRecordNow() { ScreenRecorder.shared.start(countdown: false) }
    @objc private func showMailbox() { HomeWindowController.shared.showMailbox() }
    @objc private func stopRecord() { ScreenRecorder.shared.stop() }
    @objc private func discardRecord() { ScreenRecorder.shared.cancelAndDiscard() }
    @objc private func togglePauseRecord() { ScreenRecorder.shared.togglePause() }
    @objc private func showRecord() { HomeWindowController.shared.showRecord() }
    @objc private func openRecordFolder() { ScreenRecorder.shared.openRecordingsFolder() }
    @objc private func openPermission() {
        Permissions.openScreenRecordingSettings()
    }
    @objc private func checkUpdate() {
        Task { await UpdateChecker.checkAndPrompt() }
    }
    @objc private func openWebsite() {
        if let url = URL(string: FlareBrand.websiteURL) { NSWorkspace.shared.open(url) }
    }
    @objc private func openGitHub() {
        if let url = URL(string: FlareBrand.githubURL) { NSWorkspace.shared.open(url) }
    }
    @objc private func openSaveFolder() {
        NSWorkspace.shared.open(AppSettings.shared.saveDirectory)
    }
    @objc private func openDocumentFolder() {
        try? FileManager.default.createDirectory(at: AppSettings.shared.documentDirectory, withIntermediateDirectories: true)
        NSWorkspace.shared.open(AppSettings.shared.documentDirectory)
    }
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
}
