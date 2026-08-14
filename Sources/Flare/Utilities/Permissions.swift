import AppKit
import CoreGraphics
import ScreenCaptureKit

enum PermissionState: Equatable {
    case denied
    case needsRelaunch
    case granted
    case unknown
}

/// 屏幕录制权限：以 **实际能否截屏** 为准，不依赖易误判的 preflight 连环弹窗。
enum Permissions {
    private static let applicationsPath = "/Applications/Flare Pro.app"
    private static let everSucceededKey = "flareCaptureEverSucceeded"
    private static let authorizedCDHashKey = "flareAuthorizedCDHash"
    private static let reauthToastShownKey = "flareReauthToastShown"

    /// 本进程已确认可截屏（探测或截屏成功）
    private static var sessionVerified = false
    /// 本进程是否已展示过权限说明 sheet（仅用户主动点击时弹出）
    private static var permissionUIShown = false
    private static var pollTimer: Timer?

    // MARK: - Public status

    static var hasScreenRecordingPermission: Bool {
        CGPreflightScreenCaptureAccess()
    }

    /// 不再用 preflight 拦截截图流程——直接尝试，失败再提示。
    static func canAttemptCapture() -> Bool { true }

    static func currentState() -> PermissionState {
        if sessionVerified { return .granted }
        if hasScreenRecordingPermission { return .needsRelaunch }
        return .denied
    }

    static func strictState() async -> PermissionState {
        if sessionVerified { return .granted }
        if await verifyAccessSilently() { return .granted }
        return hasScreenRecordingPermission ? .needsRelaunch : .denied
    }

    static func markCaptureSucceeded() {
        markVerified()
    }

    @discardableResult
    static func requestScreenRecordingPermission() -> Bool {
        CGRequestScreenCaptureAccess()
    }

    // MARK: - Verify

    /// 静默探测 ScreenCaptureKit；成功则标记已就绪。
    @discardableResult
    static func verifyAccessSilently() async -> Bool {
        if sessionVerified { return true }
        if await probeScreenCaptureKit() {
            markVerified()
            return true
        }
        return false
    }

    static func isPermissionError(_ error: Error) -> Bool {
        let ns = error as NSError
        if ns.domain == "com.apple.ScreenCaptureKit.SCStreamErrorDomain", ns.code == -3801 {
            return true
        }
        let text = ns.localizedDescription.lowercased()
        return text.contains("declined tcc") || text.contains("permission") && text.contains("capture")
    }

    // MARK: - Ensure / UI

    static func ensureScreenCaptureReady(presentUI: Bool = true, force: Bool = false) {
        Task { @MainActor in
            if await verifyAccessSilently() {
                permissionUIShown = false
                PermissionWindowController.shared.close()
                ToastController.shared.show("屏幕录制已就绪")
                postPermissionChanged()
                return
            }

            guard presentUI else { return }
            presentPermissionGuidance(force: force)
        }
    }

    static func handleCaptureFailure(error: Error? = nil) {
        Task { @MainActor in
            if sessionVerified {
                ToastController.shared.show("操作失败，请重试")
                return
            }

            if let error, !isPermissionError(error) {
                ToastController.shared.show("操作失败，请重试")
                return
            }

            if await verifyAccessSilently() {
                ToastController.shared.show("请再试一次")
                return
            }

            // 截图/录屏失败：只 Toast，不自动弹 sheet（避免「已授权仍连环弹窗」）
            notifyPermissionIssue()
        }
    }

    /// 应用更新或重装后 CDHash 变化，TCC 仍指向旧二进制
    static func needsReauthorizationAfterUpdate() -> Bool {
        guard !sessionVerified else { return false }
        if savedCDHashMismatch() { return true }
        return UserDefaults.standard.bool(forKey: everSucceededKey) && !hasScreenRecordingPermission
    }

    static func showReauthorizationHintIfNeeded() {
        guard needsReauthorizationAfterUpdate() else { return }
        guard !UserDefaults.standard.bool(forKey: reauthToastShownKey) else { return }
        UserDefaults.standard.set(true, forKey: reauthToastShownKey)
        ToastController.shared.show("Flare 已更新：请在系统设置删除旧的 Flare Pro，再重新勾选并重启")
    }

    static func permissionIssueSummary() -> String {
        if savedCDHashMismatch() {
            return "系统里的授权可能绑定了旧版本。请删除所有 Flare Pro 条目后，重新勾选当前应用。"
        }
        if UserDefaults.standard.bool(forKey: everSucceededKey), !hasScreenRecordingPermission {
            return "之前曾授权成功，但当前版本未生效。请删除系统设置里的旧条目后重新勾选。"
        }
        return "请在系统设置 → 屏幕与系统音频录制 中打开 Flare Pro。"
    }

    static func diagnosticDetails() -> String {
        var lines: [String] = []
        lines.append("路径：\(Bundle.main.bundlePath)")
        if let hash = codesignCDHash() {
            lines.append("签名：\(hash.prefix(12))…")
        }
        lines.append("preflight：\(hasScreenRecordingPermission ? "是" : "否")")
        return lines.joined(separator: "\n")
    }

    static func promptScreenCaptureFromUser() {
        Task { @MainActor in
            if await verifyAccessSilently() {
                PermissionWindowController.shared.close()
                ToastController.shared.show("屏幕录制已就绪")
                return
            }
            permissionUIShown = true
            PermissionWindowController.shared.show(
                preflightGranted: hasScreenRecordingPermission,
                captureWorks: false
            )
        }
    }

    static func resetSessionPromptFlags() {
        permissionUIShown = false
        UserDefaults.standard.set(false, forKey: reauthToastShownKey)
    }

    static func hasScreenCaptureAccess() async -> Bool {
        await verifyAccessSilently()
    }

    // MARK: - Settings

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

    // MARK: - App location

    static func preferredAppURL() -> URL {
        let apps = URL(fileURLWithPath: applicationsPath)
        if FileManager.default.fileExists(atPath: apps.path) { return apps }
        return Bundle.main.bundleURL
    }

    static func runningFromApplications() -> Bool {
        let current = (Bundle.main.bundlePath as NSString).standardizingPath
        let apps = (applicationsPath as NSString).standardizingPath
        return current == apps
    }

    @discardableResult
    static func relocateToApplicationsIfNeeded() -> Bool {
        let apps = URL(fileURLWithPath: applicationsPath)
        guard FileManager.default.fileExists(atPath: apps.path) else { return false }
        guard !runningFromApplications() else { return false }

        ToastController.shared.show("正在切换到「应用程序」中的 \(FlareBrand.name)…")
        relaunchApp(at: apps)
        return true
    }

    static func relaunchApp() {
        relaunchApp(at: preferredAppURL())
    }

    static func clearRelaunchFlag() {}

    // MARK: - Polling（权限 sheet 打开时：用户去系统设置改开关）

    static func startPolling() {
        stopPolling()
        let timer = Timer(timeInterval: 1.2, repeats: true) { _ in
            Task { @MainActor in
                if await verifyAccessSilently() {
                    stopPolling()
                    PermissionWindowController.shared.close()
                    ToastController.shared.show("屏幕录制已就绪")
                    postPermissionChanged()
                } else {
                    postPermissionChanged()
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
        lines.append("sessionVerified: \(sessionVerified)")
        lines.append("state: \(stateLabel(currentState()))")
        lines.append("cdhash: \(codesignCDHash() ?? "?")")
        lines.append("everSucceeded: \(UserDefaults.standard.bool(forKey: everSucceededKey))")

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
                markVerified()
            }
        } catch {
            lines.append("capture: FAIL \(error)")
        }

        let text = lines.joined(separator: "\n") + "\n"
        try? text.write(to: logURL, atomically: true, encoding: .utf8)
        return logURL
    }

    // MARK: - Private

    private static func markVerified() {
        sessionVerified = true
        UserDefaults.standard.set(true, forKey: everSucceededKey)
        UserDefaults.standard.set(false, forKey: reauthToastShownKey)
        if let hash = codesignCDHash() {
            UserDefaults.standard.set(hash, forKey: authorizedCDHashKey)
        }
        postPermissionChanged()
        writeDiagnoseLog(state: .granted)
    }

    private static func savedCDHashMismatch() -> Bool {
        guard let current = codesignCDHash(),
              let saved = UserDefaults.standard.string(forKey: authorizedCDHashKey),
              !saved.isEmpty else { return false }
        return current != saved
    }

    private static func notifyPermissionIssue() {
        if savedCDHashMismatch() || UserDefaults.standard.bool(forKey: everSucceededKey) {
            ToastController.shared.show("权限需对当前版本重新授权：系统设置里 − 删除所有 Flare Pro，再勾选并 ⌘Q 重启")
        } else {
            ToastController.shared.show("需要屏幕录制权限（点主界面「需授权」查看步骤）")
        }
    }

    private static func presentPermissionGuidance(force: Bool) {
        if !force { return }
        permissionUIShown = true
        writeDiagnoseLog(state: currentState())
        PermissionWindowController.shared.show(
            preflightGranted: hasScreenRecordingPermission,
            captureWorks: sessionVerified
        )
    }

    private static func postPermissionChanged() {
        let state = currentState()
        NotificationCenter.default.post(
            name: .flarePermissionChanged,
            object: nil,
            userInfo: [
                "granted": state == .granted,
                "state": stateLabel(state),
                "announce": false
            ]
        )
    }

    private static func relaunchApp(at appURL: URL) {
        appendLog("relaunch url=\(appURL.path) current=\(Bundle.main.bundlePath)")
        let configuration = NSWorkspace.OpenConfiguration()
        configuration.createsNewApplicationInstance = true
        configuration.arguments = ["--relaunch"]
        configuration.activates = true

        NSWorkspace.shared.openApplication(at: appURL, configuration: configuration) { _, error in
            DispatchQueue.main.async {
                if let error {
                    appendLog("relaunch failed: \(error.localizedDescription)")
                    ToastController.shared.show("请手动完全退出后，从「应用程序」重新打开")
                    openScreenRecordingSettings()
                    return
                }
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
                    NSApp.terminate(nil)
                }
            }
        }
    }

    private static func writeDiagnoseLog(state: PermissionState) {
        let text = """
        time: \(Date())
        bundle: \(Bundle.main.bundlePath)
        fromApplications: \(runningFromApplications())
        preflight: \(hasScreenRecordingPermission)
        sessionVerified: \(sessionVerified)
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
        task.arguments = ["-dv", "--verbose=2", Bundle.main.bundleURL.path]
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
