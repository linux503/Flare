import AppKit
import AVFoundation
import CoreGraphics
import ScreenCaptureKit

enum PermissionState: Equatable {
    case denied
    case needsRelaunch
    case granted
    case unknown
}

/// 屏幕录制权限。
/// - 未授权时绝不调用 ScreenCaptureKit / CGRequest：两者都会弹出系统授权框。
/// - TCC 绑定的是代码签名身份，不是 Bundle ID；ad-hoc 每次构建都会丢权限。
enum Permissions {
    private static let applicationsPath = "/Applications/Flare Pro.app"
    private static let everSucceededKey = "flareCaptureEverSucceeded"
    private static let authorizedIdentityKey = "flareAuthorizedSigningIdentity"
    private static let reauthToastShownKey = "flareReauthToastShown"

    /// 本进程已确认可截屏
    private static var sessionVerified = false
    private static var permissionUIShown = false
    private static var pollTimer: Timer?
    /// 本进程曾见过 preflight=false（用于判断「刚打开开关」，好自动重启）
    private static var sawDeniedPreflight = false
    private static var didAutoRelaunchForGrant = false
    private static var didRequestTCCThisSession = false
    private static var probeFinished = false
    private static var probeSucceeded = false
    private static var cachedCodesignDump: String?
    private static var cachedIdentityToken: String?

    // MARK: - Public status

    static var hasScreenRecordingPermission: Bool {
        CGPreflightScreenCaptureAccess()
    }

    /// 未授权时不要去调 ScreenCaptureKit（会弹系统框）。
    static func canAttemptCapture() -> Bool {
        sessionVerified || hasScreenRecordingPermission
    }

    @discardableResult
    static func prepareForCapture() -> Bool {
        if sessionVerified { return true }
        if hasScreenRecordingPermission { return true }
        sawDeniedPreflight = true
        promptScreenCaptureFromUser()
        return false
    }

    static func currentState() -> PermissionState {
        if sessionVerified { return .granted }
        if !hasScreenRecordingPermission {
            sawDeniedPreflight = true
            return .denied
        }
        if probeFinished {
            return probeSucceeded ? .granted : .needsRelaunch
        }
        return .unknown
    }

    static func strictState() async -> PermissionState {
        if sessionVerified { return .granted }
        if !hasScreenRecordingPermission {
            sawDeniedPreflight = true
            return .denied
        }
        if await verifyAccessSilently() { return .granted }
        return .needsRelaunch
    }

    static func markCaptureSucceeded() {
        markVerified()
    }

    /// 仅在用户明确点「打开系统设置 / 请求授权」时调用。
    @discardableResult
    static func requestScreenRecordingPermission() -> Bool {
        didRequestTCCThisSession = true
        return CGRequestScreenCaptureAccess()
    }

    // MARK: - Verify

    /// 真正静默：没 preflight 就直接 false，不会触发系统授权框。
    @discardableResult
    static func verifyAccessSilently() async -> Bool {
        if sessionVerified { return true }
        guard hasScreenRecordingPermission else {
            sawDeniedPreflight = true
            return false
        }
        if probeFinished { return probeSucceeded }
        probeFinished = true
        probeSucceeded = await probeScreenCaptureKit()
        if probeSucceeded { markVerified() }
        return probeSucceeded
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

            if hasScreenRecordingPermission {
                ToastController.shared.show("权限已打开，请完全退出后重新打开")
                return
            }

            sawDeniedPreflight = true
            notifyPermissionIssue()
        }
    }

    /// 签名身份变了，或曾经成功过但当前 preflight 为否。
    static func needsReauthorizationAfterUpdate() -> Bool {
        guard !sessionVerified else { return false }
        if savedIdentityMismatch() { return true }
        return UserDefaults.standard.bool(forKey: everSucceededKey) && !hasScreenRecordingPermission
    }

    static func showReauthorizationHintIfNeeded() {
        guard needsReauthorizationAfterUpdate() else { return }
        guard !UserDefaults.standard.bool(forKey: reauthToastShownKey) else { return }
        UserDefaults.standard.set(true, forKey: reauthToastShownKey)
        ToastController.shared.show("请在系统设置删除旧的 Flare Pro，再重新勾选并重启")
    }

    static func permissionIssueSummary() -> String {
        if savedIdentityMismatch() {
            return "系统里的授权还绑着旧签名。请删除所有 Flare Pro 条目后，重新勾选当前应用。"
        }
        if UserDefaults.standard.bool(forKey: everSucceededKey), !hasScreenRecordingPermission {
            return "之前曾授权成功，但当前进程未生效。请删除系统设置里的旧条目后重新勾选。"
        }
        return "请在系统设置 → 屏幕与系统音频录制 中打开 Flare Pro。"
    }

    static func diagnosticDetails() -> String {
        var lines: [String] = []
        lines.append("路径：\(Bundle.main.bundlePath)")
        if let token = signingIdentityToken() {
            lines.append("签名：\(token)")
        }
        lines.append("preflight：\(hasScreenRecordingPermission ? "是" : "否")")
        return lines.joined(separator: "\n")
    }

    static func isAdHocSigned() -> Bool {
        signingIdentityToken()?.hasPrefix("adhoc:") == true
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

    /// 从系统设置回到前台：只看 preflight；刚授权则重启，绝不反复弹系统框。
    static func refreshAfterForeground() {
        Task { @MainActor in
            await checkGrantProgress(allowAutoRelaunch: true)
        }
    }

    // MARK: - Settings

    static func openScreenRecordingSettings() {
        if !hasScreenRecordingPermission, !didRequestTCCThisSession {
            _ = requestScreenRecordingPermission()
        }
        let candidates = [
            "x-apple.systempreferences:com.apple.preference.security?Privacy_ScreenCapture",
            "x-apple.systempreferences:com.apple.settings.PrivacySecurity.extension?Privacy_ScreenCapture",
            "x-apple.systempreferences:com.apple.Settings.PrivacySecurity.extension?Privacy_ScreenCapture"
        ]
        for s in candidates {
            if let url = URL(string: s), NSWorkspace.shared.open(url) { return }
        }
    }

    static func openMicrophoneSettings() {
        let candidates = [
            "x-apple.systempreferences:com.apple.preference.security?Privacy_Microphone",
            "x-apple.systempreferences:com.apple.settings.PrivacySecurity.extension?Privacy_Microphone"
        ]
        for s in candidates {
            if let url = URL(string: s), NSWorkspace.shared.open(url) { return }
        }
    }

    static func hasMicrophoneAccess() -> Bool {
        AVCaptureDevice.authorizationStatus(for: .audio) == .authorized
    }

    static func requestMicrophoneAccess() async -> Bool {
        let status = AVCaptureDevice.authorizationStatus(for: .audio)
        switch status {
        case .authorized:
            return true
        case .notDetermined:
            return await withCheckedContinuation { cont in
                AVCaptureDevice.requestAccess(for: .audio) { cont.resume(returning: $0) }
            }
        default:
            return false
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

    // MARK: - Polling（权限 sheet 打开时：只轮询 preflight，不调 ScreenCaptureKit）

    static func startPolling() {
        stopPolling()
        if !hasScreenRecordingPermission { sawDeniedPreflight = true }
        let timer = Timer(timeInterval: 1.2, repeats: true) { _ in
            Task { @MainActor in
                await checkGrantProgress(allowAutoRelaunch: true)
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
        lines.append("identity: \(signingIdentityToken() ?? "?")")
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

    @MainActor
    private static func checkGrantProgress(allowAutoRelaunch: Bool) async {
        if sessionVerified {
            stopPolling()
            PermissionWindowController.shared.close()
            postPermissionChanged()
            return
        }

        if !hasScreenRecordingPermission {
            sawDeniedPreflight = true
            postPermissionChanged()
            return
        }

        // 刚从「未授权」变为「系统已记录」：同一进程里 SCK 仍不可用，直接重启。
        if allowAutoRelaunch, sawDeniedPreflight {
            postPermissionChanged()
            autoRelaunchIfJustGranted()
            return
        }

        if await verifyAccessSilently() {
            stopPolling()
            PermissionWindowController.shared.close()
            ToastController.shared.show("屏幕录制已就绪")
            postPermissionChanged()
        } else {
            postPermissionChanged()
        }
    }

    private static func autoRelaunchIfJustGranted() {
        guard !didAutoRelaunchForGrant else { return }
        didAutoRelaunchForGrant = true
        stopPolling()
        ToastController.shared.show("权限已打开，正在重启以生效…")
        relaunchApp()
    }

    private static func markVerified() {
        sessionVerified = true
        probeFinished = true
        probeSucceeded = true
        UserDefaults.standard.set(true, forKey: everSucceededKey)
        UserDefaults.standard.set(false, forKey: reauthToastShownKey)
        if let token = signingIdentityToken() {
            UserDefaults.standard.set(token, forKey: authorizedIdentityKey)
        }
        postPermissionChanged()
        writeDiagnoseLog(state: .granted)
    }

    private static func savedIdentityMismatch() -> Bool {
        guard let current = signingIdentityToken(),
              let saved = UserDefaults.standard.string(forKey: authorizedIdentityKey),
              !saved.isEmpty else { return false }
        return current != saved
    }

    private static func notifyPermissionIssue() {
        if savedIdentityMismatch() || UserDefaults.standard.bool(forKey: everSucceededKey) {
            ToastController.shared.show("权限需对当前应用重新授权：系统设置里 − 删除所有 Flare Pro，再勾选并 ⌘Q 重启")
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
        let pid = ProcessInfo.processInfo.processIdentifier
        let path = appURL.path
        appendLog("relaunch pid=\(pid) url=\(path) current=\(Bundle.main.bundlePath)")

        // 不能对正在运行的自己调 NSWorkspace.openApplication：系统往往只是激活当前实例，
        // 随后 terminate 就把唯一进程杀掉，看起来像「重启了但没回来」。
        // 先拉起一个脱离会话的助手，等本进程退出后再 open。
        let quoted = "'" + path.replacingOccurrences(of: "'", with: "'\\''") + "'"
        let script = """
        while /bin/kill -0 \(pid) >/dev/null 2>&1; do /bin/sleep 0.1; done
        /bin/sleep 0.35
        exec /usr/bin/open -n -a \(quoted) --args --relaunch
        """

        let task = Process()
        task.executableURL = URL(fileURLWithPath: "/bin/zsh")
        task.arguments = ["-c", "/usr/bin/nohup /bin/zsh -c \(shellQuote(script)) >/dev/null 2>&1 &"]
        task.standardInput = FileHandle.nullDevice
        task.standardOutput = FileHandle.nullDevice
        task.standardError = FileHandle.nullDevice

        do {
            try task.run()
            task.waitUntilExit()
            appendLog("relaunch helper spawned status=\(task.terminationStatus)")
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.12) {
                NSApp.terminate(nil)
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) {
                    exit(0)
                }
            }
        } catch {
            appendLog("relaunch spawn failed: \(error.localizedDescription)")
            ToastController.shared.show("请手动完全退出后，从「应用程序」重新打开")
        }
    }

    private static func shellQuote(_ value: String) -> String {
        "'" + value.replacingOccurrences(of: "'", with: "'\\''") + "'"
    }

    private static func writeDiagnoseLog(state: PermissionState) {
        let text = """
        time: \(Date())
        bundle: \(Bundle.main.bundlePath)
        fromApplications: \(runningFromApplications())
        preflight: \(hasScreenRecordingPermission)
        sessionVerified: \(sessionVerified)
        identity: \(signingIdentityToken() ?? "?")
        state: \(stateLabel(state))

        """
        try? text.write(to: logURL, atomically: true, encoding: .utf8)
    }

    private static func appendLog(_ line: String) {
        let url = logURL
        let old = (try? String(contentsOf: url, encoding: .utf8)) ?? ""
        let stamp = ISO8601DateFormatter().string(from: Date())
        try? (old + "[\(stamp)] \(line)\n").write(to: logURL, atomically: true, encoding: .utf8)
    }

    private static func stateLabel(_ state: PermissionState) -> String {
        switch state {
        case .granted: return "granted"
        case .needsRelaunch: return "needsRelaunch"
        case .denied: return "denied"
        case .unknown: return "unknown"
        }
    }

    private static func signingIdentityToken() -> String? {
        if let cached = cachedIdentityToken { return cached }
        guard let dump = codesignDump() else { return nil }
        if let team = codesignField(dump, "TeamIdentifier"), team != "not set" {
            cachedIdentityToken = "team:\(team)"
            return cachedIdentityToken
        }
        if let auth = codesignField(dump, "Authority") {
            cachedIdentityToken = "authority:\(auth)"
            return cachedIdentityToken
        }
        if dump.contains("Signature=adhoc") || dump.contains("flags=0x2(adhoc)") {
            if let hash = codesignField(dump, "CDHash") {
                cachedIdentityToken = "adhoc:\(hash)"
                return cachedIdentityToken
            }
            cachedIdentityToken = "adhoc"
            return cachedIdentityToken
        }
        return nil
    }

    private static func codesignDump() -> String? {
        if let cached = cachedCodesignDump { return cached }
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
            cachedCodesignDump = s
            return s
        } catch {
            return nil
        }
    }

    private static func codesignField(_ dump: String, _ key: String) -> String? {
        let prefix = "\(key)="
        for line in dump.split(separator: "\n") {
            if line.hasPrefix(prefix) {
                return String(line.dropFirst(prefix.count))
            }
        }
        return nil
    }
}

extension Notification.Name {
    static let flarePermissionChanged = Notification.Name("flarePermissionChanged")
}
