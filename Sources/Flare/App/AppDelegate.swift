import AppKit
import SwiftUI

final class AppDelegate: NSObject, NSApplicationDelegate {
    private var statusBar: StatusBarController?
    private var mainMenu: MainMenuController?

    func applicationDidFinishLaunching(_ notification: Notification) {
        AppSettings.shared.load()
        HistoryStore.shared.load()
        migrateToMenuBarOnlyIfNeeded()
        NSApp.setActivationPolicy(AppSettings.shared.showInDock ? .regular : .accessory)

        DistributedNotificationCenter.default().addObserver(
            forName: flareReopenNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            self?.bringToFront()
        }

        NotificationCenter.default.addObserver(
            forName: NSApplication.didBecomeActiveNotification,
            object: nil,
            queue: .main
        ) { _ in
            Permissions.refreshAfterForeground()
        }

        mainMenu = MainMenuController()
        mainMenu?.install()

        statusBar = StatusBarController(
            onCaptureArea: { CaptureCoordinator.shared.startAreaCapture() },
            onCaptureWindow: { CaptureCoordinator.shared.startWindowCapture() },
            onCaptureScreen: { CaptureCoordinator.shared.startFullScreenCapture() },
            onCaptureDelay: { CaptureCoordinator.shared.startDelayedCapture(seconds: 3) },
            onHistory: { HomeWindowController.shared.showHistory() },
            onSettings: { HomeWindowController.shared.showSettings() },
            onHome: { HomeWindowController.shared.show() },
            onDocuments: { HomeWindowController.shared.showDocuments() },
            onQuit: { NSApp.terminate(nil) }
        )

        HotKeyManager.shared.registerDefaults()

        NotificationCenter.default.addObserver(
            forName: .flareSettingsChanged,
            object: nil,
            queue: .main
        ) { _ in
            HotKeyManager.shared.registerDefaults()
            StatusBarController.shared?.reloadMenu()
            MainMenuController.shared?.reload()
        }

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) {
            if CommandLine.arguments.contains("--relaunch") {
                Permissions.resetSessionPromptFlags()
            }

            if Permissions.relocateToApplicationsIfNeeded() {
                return
            }

            let defaults = UserDefaults.standard
            let first = defaults.bool(forKey: "snapHasLaunched") == false
            if first {
                defaults.set(true, forKey: "snapHasLaunched")
                HomeWindowController.shared.show()
            }

            // 静默探测权限，不弹窗；用户从系统设置返回时会再次探测
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) {
                Task {
                    let ok = await Permissions.verifyAccessSilently()
                    await MainActor.run {
                        let state = ok ? PermissionState.granted : Permissions.currentState()
                        NotificationCenter.default.post(
                            name: .flarePermissionChanged,
                            object: nil,
                            userInfo: [
                                "granted": ok,
                                "state": state == .granted ? "granted" : (state == .needsRelaunch ? "needsRelaunch" : "denied"),
                                "announce": false
                            ]
                        )
                        if ok, !first {
                            ToastController.shared.show("\(FlareBrand.name) 已就绪 · 单击菜单栏截图")
                        } else if !ok {
                            Permissions.showReauthorizationHintIfNeeded()
                            Permissions.startPolling()
                        }
                    }
                }
            }
        }
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        if CaptureCoordinator.shared.shouldSuppressHomeReveal {
            return false
        }
        bringToFront()
        return true
    }

    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        let rec = ScreenRecorder.shared
        guard rec.isRecording || rec.isCountingDown else { return .terminateNow }

        let alert = NSAlert()
        alert.messageText = "正在录屏"
        alert.informativeText = rec.isCountingDown ? "倒计时尚未结束，确定退出？" : "退出前请选择如何处理当前录屏。"
        if rec.isRecording {
            alert.addButton(withTitle: "保存并退出")
            alert.addButton(withTitle: "丢弃并退出")
            alert.addButton(withTitle: "取消")
        } else {
            alert.addButton(withTitle: "退出")
            alert.addButton(withTitle: "取消")
        }

        switch alert.runModal() {
        case .alertFirstButtonReturn:
            Task { @MainActor in
                await rec.stopInternal(discard: false)
                NSApp.reply(toApplicationShouldTerminate: true)
            }
            return .terminateLater
        case .alertSecondButtonReturn:
            if rec.isRecording {
                Task { @MainActor in
                    await rec.stopInternal(discard: true)
                    NSApp.reply(toApplicationShouldTerminate: true)
                }
                return .terminateLater
            }
            return .terminateCancel
        default:
            return .terminateCancel
        }
    }

    func applicationWillTerminate(_ notification: Notification) {
        HotKeyManager.shared.unregisterAll()
    }

    private func migrateToMenuBarOnlyIfNeeded() {
        let defaults = UserDefaults.standard
        guard defaults.object(forKey: "flareMenuBarOnly") == nil else { return }
        defaults.set(true, forKey: "flareMenuBarOnly")
        defaults.set(false, forKey: "showInDock")
    }

    private func bringToFront() {
        if AppSettings.shared.showInDock {
            NSApp.setActivationPolicy(.regular)
        }
        NSApp.activate(ignoringOtherApps: true)
        HomeWindowController.shared.show()
    }
}
