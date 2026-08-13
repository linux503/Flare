import AppKit
import CoreGraphics
import ScreenCaptureKit

enum PermissionState: Equatable {
    /// 从未授权 / 已拒绝 / 已撤销
    case denied
    /// 本进程内刚勾选成功：ScreenCaptureKit 要等重启才生效
    case needsRelaunch
    /// 启动时已有权限，可直接截屏
    case granted
    case unknown
}

/// 屏幕录制权限（kTCCServiceScreenCapture）
///
/// 硬规则：用户在本进程生命周期内刚打开开关时，ScreenCaptureKit **不会**立刻可用，
/// 必须完全退出再启动。用 `hasObservedFalse` 区分「启动时已有权限」和「中途刚授权」。
enum Permissions {
    private static let relaunchFlagKey = "flareDidAutoRelaunchForTCC"
    private static let applicationsPath = "/Applications/Flare Pro.app"

    /// 本进程内一旦截屏成功
    private static var sessionCaptureOK = false
    /// 是否在本进程中观察到过 preflight == false
    private static var hasObservedFalse = !CGPreflightScreenCaptureAccess()
    private static var lastUIPresentedAt: Date?
    private static var relaunchScheduled = false
    private static var pollTimer: Timer?

    // MARK: - Public status

    static var hasScreenRecordingPermission: Bool {
        CGPreflightScreenCaptureAccess()
    }

    /// 仅当真正可截时为 true（中途刚授权不算）
    static var isReadyForCapture: Bool {
        if sessionCaptureOK { return true }
        refreshObserved()
        return hasScreenRecordingPermission && !hasObservedFalse
    }

    /// 是否允许开始截图流程
    static func canAttemptCapture() -> Bool {
        isReadyForCapture
    }

    static func currentState() -> PermissionState {
        refreshObserved()
        if sessionCaptureOK { return .granted }
        if hasScreenRecordingPermission {
            return hasObservedFalse ? .needsRelaunch : .granted
        }
        return .denied
    }

    /// 异步严格状态（设置页 / 诊断）；必要时用 SCK 复核
    static func strictState() async -> PermissionState {
        let state = currentState()
        if state == .granted {
            // 启动时已授权：偶尔用探测确认（失败不降级为 denied，避免误报）
            return .granted
        }
        if state == .needsRelaunch { return .needsRelaunch }

        // denied：再探一次，兼容「系统已勾但 preflight 滞后」
        if await probeScreenCaptureKit() {
            sessionCaptureOK = true
            hasObservedFalse = false
            clearRelaunchFlag()
            return .granted
        }
        return hasScreenRecordingPermission ? .needsRelaunch : .denied
    }

    static func markCaptureSucceeded() {
        sessionCaptureOK = true
        hasObservedFalse = false
        clearRelaunchFlag()
    }

    @discardableResult
    static func requestScreenRecordingPermission() -> Bool {
        let granted = CGRequestScreenCaptureAccess()
        refreshObserved()
        return granted
    }

    // MARK: - Ensure / UI

    static func ensureScreenCaptureReady(presentUI: Bool = true) {
        Task { @MainActor in
            refreshObserved()
            let state = currentState()
            writeDiagnoseLog(state: state)

            NotificationCenter.default.post(
                name: .flarePermissionChanged,
                object: nil,
                userInfo: [
                    "granted": state == .granted,
                    "state": stateLabel(state),
                    "announce": false
                ]
            )

            switch state {
            case .granted:
                return
            case .needsRelaunch:
                guard presentUI else { return }
                // 权限已开但本进程不可用：自动重启（不依赖易坏的 sticky 永久标记）
                scheduleRelaunch(message: "权限已打开，正在重启以生效…", force: false)
            case .denied, .unknown:
                // 弹系统授权框（若曾拒绝则无框，只返回 false）
                if !hasScreenRecordingPermission {
                    _ = requestScreenRecordingPermission()
                    try? await Task.sleep(nanoseconds: 400_000_000)
                    refreshObserved()
                    let after = currentState()
                    if after == .needsRelaunch {
                        scheduleRelaunch(message: "权限已打开，正在重启以生效…", force: false)
                        return
                    }
                    if after == .granted { return }
                }
                guard presentUI else { return }
                if let last = lastUIPresentedAt, Date().timeIntervalSince(last) < 2 {
                    return
                }
                lastUIPresentedAt = Date()
                openScreenRecordingSettings()
                PermissionWindowController.shared.show(
                    preflightGranted: hasScreenRecordingPermission,
                    captureWorks: false
                )
            }
        }
    }

    static func handleCaptureFailure() {
        Task { @MainActor in
            if sessionCaptureOK {
                ToastController.shared.show("截图失败，请重试")
                return
            }
            refreshObserved()
            // 失败后重新读 TCC
            if !hasScreenRecordingPermission {
                hasObservedFalse = true
            }
            let state = await strictState()
            switch state {
            case .granted:
                sessionCaptureOK = true
                ToastController.shared.show("截图失败，请重试")
            case .needsRelaunch:
                scheduleRelaunch(message: "权限已打开，正在重启以生效…", force: true)
            case .denied, .unknown:
                ensureScreenCaptureReady(presentUI: true)
            }
        }
    }

    static func promptScreenCaptureIfNeeded() {
        ensureScreenCaptureReady(presentUI: true)
    }

    static func hasScreenCaptureAccess() async -> Bool {
        await strictState() == .granted
    }

    // MARK: - Settings deep link

    static func openScreenRecordingSettings() {
        let candidates = [
            "x-apple.systempreferences:com.apple.preference.security?Privacy_ScreenCapture",
            "x-apple.systempreferences:com.apple.settings.PrivacySecurity.extension?Privacy_ScreenCapture",
            "x-apple.systempreferences:com.apple.Settings.PrivacySecurity.extension?Privacy_ScreenCapture"
        ]
        for s in candidates {
            if let url = URL(string: s), NSWorkspace.shared.open(url) { return }
        }
    }

    // MARK: - Relaunch（必须用 NSWorkspace，且带 --relaunch）

    /// 始终优先重启到 /Applications，避免 dist/Downloads 与已授权副本 TCC 身份不一致
    static func preferredAppURL() -> URL {
        let apps = URL(fileURLWithPath: applicationsPath)
        if FileManager.default.fileExists(atPath: apps.path) {
            return apps
        }
        return Bundle.main.bundleURL
    }

    static func runningFromApplications() -> Bool {
        let current = (Bundle.main.bundlePath as NSString).standardizingPath
        let apps = (applicationsPath as NSString).standardizingPath
        return current == apps
    }

    /// 若已安装到 /Applications 却从别处启动：切到 Applications 再开（权限只认那一份）
    @discardableResult
    static func relocateToApplicationsIfNeeded() -> Bool {
        let apps = URL(fileURLWithPath: applicationsPath)
        guard FileManager.default.fileExists(atPath: apps.path) else { return false }
        guard !runningFromApplications() else { return false }

        ToastController.shared.show("正在切换到「应用程序」中的 \(FlareBrand.name)…")
        relaunchApp(at: apps, reason: "relocate")
        return true
    }

    static func relaunchApp() {
        relaunchApp(at: preferredAppURL(), reason: "manual")
    }

    private static func relaunchApp(at appURL: URL, reason: String) {
        appendLog("relaunch reason=\(reason) url=\(appURL.path) current=\(Bundle.main.bundlePath)")
        clearRelaunchFlag()

        let configuration = NSWorkspace.OpenConfiguration()
        configuration.createsNewApplicationInstance = true
        configuration.arguments = ["--relaunch"]
        configuration.activates = true

        NSWorkspace.shared.openApplication(at: appURL, configuration: configuration) { _, error in
            DispatchQueue.main.async {
                if let error {
                    appendLog("relaunch failed: \(error.localizedDescription)")
                    // 回退：修正后的 open 语法（路径，不要 -a）
                    fallbackRelaunch(appURL: appURL)
                    return
                }
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
                    NSApp.terminate(nil)
                }
            }
        }
    }

    private static func fallbackRelaunch(appURL: URL) {
        let pid = ProcessInfo.processInfo.processIdentifier
        let escaped = appURL.path.replacingOccurrences(of: "'", with: "'\\''")
        // 注意：对 .app 路径必须用 open -n 'path'，不能用 -a（-a 只认应用名）
        let script = """
        #!/bin/zsh
        while kill -0 \(pid) 2>/dev/null; do sleep 0.05; done
        sleep 0.35
        /usr/bin/open -n '\(escaped)' --args --relaunch
        """
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("flare-relaunch-\(pid).sh")
        do {
            try script.write(to: url, atomically: true, encoding: .utf8)
            try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: url.path)
            let process = Process()
            process.executableURL = URL(fileURLWithPath: "/bin/zsh")
            process.arguments = [url.path]
            try process.run()
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
                NSApp.terminate(nil)
            }
        } catch {
            appendLog("fallback relaunch failed: \(error)")
            ToastController.shared.show("自动重启失败，请完全退出后从「应用程序」打开")
            openScreenRecordingSettings()
        }
    }

    private static func scheduleRelaunch(message: String, force: Bool) {
        if relaunchScheduled {
            ToastController.shared.show("请完全退出后重新打开 \(FlareBrand.name)")
            return
        }
        // 旧 sticky 标记曾导致永远无法自动重启；仅在非 force 时作软提示
        if !force, UserDefaults.standard.bool(forKey: relaunchFlagKey) {
            ToastController.shared.show("权限已勾选，请点「重启 \(FlareBrand.name)」生效")
            lastUIPresentedAt = Date()
            PermissionWindowController.shared.show(
                preflightGranted: true,
                captureWorks: false
            )
            return
        }
        relaunchScheduled = true
        UserDefaults.standard.set(true, forKey: relaunchFlagKey)
        ToastController.shared.show(message)
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) {
            relaunchApp()
        }
    }

    static func clearRelaunchFlag() {
        UserDefaults.standard.set(false, forKey: relaunchFlagKey)
        relaunchScheduled = false
    }

    // MARK: - Polling（权限 sheet 打开时）

    static func startPolling() {
        stopPolling()
        let timer = Timer(timeInterval: 1.0, repeats: true) { _ in
            Task { @MainActor in
                let before = currentState()
                refreshObserved()
                let after = currentState()
                if before != after {
                    NotificationCenter.default.post(
                        name: .flarePermissionChanged,
                        object: nil,
                        userInfo: [
                            "granted": after == .granted,
                            "state": stateLabel(after),
                            "announce": false
                        ]
                    )
                }
                if after == .needsRelaunch {
                    stopPolling()
                    scheduleRelaunch(message: "权限已打开，正在重启以生效…", force: true)
                } else if after == .granted {
                    stopPolling()
                    PermissionWindowController.shared.close()
                    ToastController.shared.show("屏幕录制已就绪")
                }
            }
        }
        RunLoop.main.add(timer, forMode: .common)
        pollTimer = timer
    }

    static func stopPolling() {
        pollTimer?.invalidate()
        pollTimer = nil
    }

    // MARK: - Probe / diagnose

    static func probeScreenCaptureKit() async -> Bool {
        do {
            let content = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: true)
            guard let display = content.displays.first else { return false }
            let filter = SCContentFilter(display: display, excludingWindows: [])
            let config = SCStreamConfiguration()
            config.width = 64
            config.height = 64
            config.showsCursor = false
            _ = try await SCScreenshotManager.captureImage(contentFilter: filter, configuration: config)
            return true
        } catch {
            appendLog("probe failed: \(error)")
            return false
        }
    }

    static var logURL: URL {
        let dir = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Flare", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir.appendingPathComponent("permission.log")
    }

    static func runDiagnoseToFile() async -> URL {
        var lines: [String] = []
        lines.append("Flare Permission Diagnose")
        lines.append("time: \(Date())")
        lines.append("bundle: \(Bundle.main.bundlePath)")
        lines.append("executable: \(Bundle.main.executablePath ?? "?")")
        lines.append("fromApplications: \(runningFromApplications())")
        lines.append("preflight: \(hasScreenRecordingPermission)")
        lines.append("hasObservedFalse: \(hasObservedFalse)")
        lines.append("sessionOK: \(sessionCaptureOK)")
        lines.append("state: \(stateLabel(currentState()))")
        lines.append("cdhash: \(codesignCDHash() ?? "?")")

        do {
            let content = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: true)
            lines.append("displays: \(content.displays.count)")
            if let d = content.displays.first {
                let filter = SCContentFilter(display: d, excludingWindows: [])
                let config = SCStreamConfiguration()
                config.width = min(d.width, 800)
                config.height = min(d.height, 500)
                config.showsCursor = false
                let img = try await SCScreenshotManager.captureImage(contentFilter: filter, configuration: config)
                lines.append("capture: OK \(img.width)x\(img.height)")
                sessionCaptureOK = true
                hasObservedFalse = false
            }
        } catch {
            lines.append("capture: FAIL \(error)")
        }

        let text = lines.joined(separator: "\n") + "\n"
        try? text.write(to: logURL, atomically: true, encoding: .utf8)
        return logURL
    }

    // MARK: - Private

    private static func refreshObserved() {
        let pre = hasScreenRecordingPermission
        if !pre { hasObservedFalse = true }
    }

    private static func writeDiagnoseLog(state: PermissionState) {
        let text = """
        time: \(Date())
        bundle: \(Bundle.main.bundlePath)
        fromApplications: \(runningFromApplications())
        preflight: \(hasScreenRecordingPermission)
        hasObservedFalse: \(hasObservedFalse)
        sessionOK: \(sessionCaptureOK)
        state: \(stateLabel(state))

        """
        try? text.write(to: logURL, atomically: true, encoding: .utf8)
    }

    private static func appendLog(_ line: String) {
        let url = logURL
        let old = (try? String(contentsOf: url, encoding: .utf8)) ?? ""
        let stamp = ISO8601DateFormatter().string(from: Date())
        try? (old + "[\(stamp)] \(line)\n").write(to: url, atomically: true, encoding: .utf8)
    }

    private static func stateLabel(_ state: PermissionState) -> String {
        switch state {
        case .granted: return "granted"
        case .needsRelaunch: return "needsRelaunch"
        case .denied: return "denied"
        case .unknown: return "unknown"
        }
    }

    private static func codesignCDHash() -> String? {
        let task = Process()
        task.executableURL = URL(fileURLWithPath: "/usr/bin/codesign")
        task.arguments = ["-dv", "--verbose=2", Bundle.main.bundlePath]
        let err = Pipe()
        task.standardError = err
        task.standardOutput = Pipe()
        do {
            try task.run()
            task.waitUntilExit()
            let data = err.fileHandleForReading.readDataToEndOfFile()
            let s = String(data: data, encoding: .utf8) ?? ""
            for line in s.split(separator: "\n") {
                if line.hasPrefix("CDHash=") {
                    return String(line.dropFirst("CDHash=".count))
                }
            }
        } catch {}
        return nil
    }
}

extension Notification.Name {
    static let flarePermissionChanged = Notification.Name("flarePermissionChanged")
}
