import AppKit

/// 二次启动时通知已有进程前置界面
let flareReopenNotification = Notification.Name("app.flare.screenshot.reopen")

/// 单实例：已有同 Bundle ID 进程则激活它并退出，避免程序坞出现两个图标。
/// `--relaunch`：替换实例（先结束旧进程），用于权限生效后的重启。
func enforceSingleInstance() {
    let bundleID = Bundle.main.bundleIdentifier ?? "app.flare.screenshot"
    let myPID = ProcessInfo.processInfo.processIdentifier
    var others = NSRunningApplication.runningApplications(withBundleIdentifier: bundleID)
        .filter { $0.processIdentifier != myPID && !$0.isTerminated }

    let isRelaunch = CommandLine.arguments.contains("--relaunch")

    if isRelaunch {
        for app in others {
            app.terminate()
        }
        // 等待旧进程退出，最多 ~3 秒
        let deadline = Date().addingTimeInterval(3)
        while Date() < deadline {
            others = NSRunningApplication.runningApplications(withBundleIdentifier: bundleID)
                .filter { $0.processIdentifier != myPID && !$0.isTerminated }
            if others.isEmpty { break }
            for app in others where !app.isTerminated {
                app.forceTerminate()
            }
            Thread.sleep(forTimeInterval: 0.1)
        }
        return
    }

    guard let existing = others.first else { return }

    DistributedNotificationCenter.default().postNotificationName(
        flareReopenNotification,
        object: bundleID,
        userInfo: ["reason": "second-launch"],
        deliverImmediately: true
    )
    _ = existing.activate(options: [.activateAllWindows, .activateIgnoringOtherApps])
    usleep(150_000)
    exit(0)
}

let args = CommandLine.arguments
if args.contains("--diagnose") {
    let app = NSApplication.shared
    app.setActivationPolicy(.prohibited)
    let sem = DispatchSemaphore(value: 0)
    Task {
        let url = await Permissions.runDiagnoseToFile()
        print(try! String(contentsOf: url, encoding: .utf8))
        print("LOG=\(url.path)")
        sem.signal()
    }
    let deadline = Date().addingTimeInterval(8)
    while sem.wait(timeout: .now() + 0.05) != .success {
        RunLoop.current.run(mode: .default, before: Date().addingTimeInterval(0.05))
        if Date() > deadline { break }
    }
    exit(0)
}

if args.contains("--request-tcc") {
    let app = NSApplication.shared
    app.setActivationPolicy(.accessory)
    // 触发系统授权框，并把 App 写入「屏幕录制」列表
    let granted = CGRequestScreenCaptureAccess()
    print("CGRequestScreenCaptureAccess=\(granted)")
    print("preflight=\(CGPreflightScreenCaptureAccess())")
    // 稍等用户点允许
    RunLoop.current.run(until: Date().addingTimeInterval(1.5))
    print("preflight_after=\(CGPreflightScreenCaptureAccess())")
    exit(granted || CGPreflightScreenCaptureAccess() ? 0 : 1)
}

enforceSingleInstance()

let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.setActivationPolicy(.accessory)
app.run()
