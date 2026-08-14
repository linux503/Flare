import AppKit
import SwiftUI

final class AppDelegate: NSObject, NSApplicationDelegate {
    private var statusBar: StatusBarController?
    private var mainMenu: MainMenuController?

    func applicationDidFinishLaunching(_ notification: Notification) {
        AppSettings.shared.load()
        HistoryStore.shared.load()
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
            Task { await Permissions.verifyAccessSilently() }
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
                        }
                    }
                }
            }
        }
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        bringToFront()
        return true
    }

    func applicationWillTerminate(_ notification: Notification) {
        HotKeyManager.shared.unregisterAll()
    }

    private func bringToFront() {
        if AppSettings.shared.showInDock {
            NSApp.setActivationPolicy(.regular)
        }
        NSApp.activate(ignoringOtherApps: true)
        HomeWindowController.shared.show()
    }
}
