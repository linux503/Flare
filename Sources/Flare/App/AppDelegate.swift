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
            // 已安装到 /Applications 却从 dist/Downloads 启动 → 切过去，否则 TCC 对不上
            if Permissions.relocateToApplicationsIfNeeded() {
                return
            }

            let defaults = UserDefaults.standard
            let first = defaults.bool(forKey: "snapHasLaunched") == false
            if first {
                defaults.set(true, forKey: "snapHasLaunched")
                HomeWindowController.shared.show()
            }

            DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) {
                Task {
                    Permissions.clearRelaunchFlag()
                    let state = await Permissions.strictState()
                    await MainActor.run {
                        let stateName: String = {
                            switch state {
                            case .granted: return "granted"
                            case .needsRelaunch: return "needsRelaunch"
                            case .denied: return "denied"
                            case .unknown: return "unknown"
                            }
                        }()
                        NotificationCenter.default.post(
                            name: .flarePermissionChanged,
                            object: nil,
                            userInfo: [
                                "granted": state == .granted,
                                "state": stateName,
                                "announce": false
                            ]
                        )
                        switch state {
                        case .granted:
                            if !first {
                                ToastController.shared.show("\(FlareBrand.name) 已就绪 · 单击菜单栏截图")
                            }
                        case .needsRelaunch:
                            Permissions.ensureScreenCaptureReady(presentUI: true)
                        case .denied, .unknown:
                            HomeWindowController.shared.show()
                            Permissions.ensureScreenCaptureReady(presentUI: true)
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
