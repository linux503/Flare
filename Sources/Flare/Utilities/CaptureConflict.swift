import AppKit
import Carbon
import CoreGraphics

/// 窗口截成黑屏、快捷键被抢：常见是 DRM 保护窗口，或其他截图/录屏软件占用采集通道。
enum CaptureConflict {
    private static var didWarnRunningAppsThisSession = false

    struct RivalApp: Equatable {
        let name: String
        let bundleID: String
    }

    /// 会抢屏幕采集或叠一层截图 HUD 的常见软件
    private static let rivalHints: [(needles: [String], name: String)] = [
        (["cleanshot"], "CleanShot X"),
        (["snipaste"], "Snipaste"),
        (["ishot"], "iShot"),
        (["xnip"], "Xnip"),
        (["shottr"], "Shottr"),
        (["pixpin"], "PixPin"),
        (["snagit"], "Snagit"),
        (["monosnap"], "Monosnap"),
        (["lightshot"], "Lightshot"),
        (["kap."], "Kap"),
        (["obsproject", "obs-studio", "com.obs"], "OBS"),
        (["loom"], "Loom"),
        (["screenflow"], "ScreenFlow"),
        (["jumploop"], "Jumploop"),
        (["better365"], "iShot"),
        (["apowersoft"], "Apowersoft"),
        (["bandicam"], "Bandicam")
    ]

    static func runningRivalApps() -> [RivalApp] {
        let own = (Bundle.main.bundleIdentifier ?? "").lowercased()
        var seen = Set<String>()
        var result: [RivalApp] = []
        for app in NSWorkspace.shared.runningApplications {
            guard let bid = app.bundleIdentifier?.lowercased(), bid != own else { continue }
            guard let name = matchRival(bundleID: bid, localized: app.localizedName) else { continue }
            if seen.insert(name).inserted {
                result.append(RivalApp(name: name, bundleID: app.bundleIdentifier ?? bid))
            }
        }
        return result
    }

    private static func matchRival(bundleID: String, localized: String?) -> String? {
        let hay = bundleID + " " + (localized ?? "").lowercased()
        for hint in rivalHints {
            if hint.needles.contains(where: { hay.contains($0) }) {
                return hint.name
            }
        }
        return nil
    }

    static func rivalNamesText() -> String? {
        let names = runningRivalApps().map(\.name)
        guard !names.isEmpty else { return nil }
        return names.joined(separator: "、")
    }

    /// 截图开始前：有同类软件就提醒一次（本进程只弹一次，避免刷屏）
    static func warnBeforeCaptureIfNeeded() {
        guard !didWarnRunningAppsThisSession else { return }
        guard let names = rivalNamesText() else { return }
        didWarnRunningAppsThisSession = true
        ToastController.shared.show(
            "检测到 \(names) 正在运行，窗口可能截成黑屏。请先退出这些截图/录屏软件后再试",
            duration: 4.2
        )
    }

    static func isSystemScreenshotShortcut(_ shortcut: HotKeyShortcut) -> Bool {
        let cmdShift = UInt32(cmdKey | shiftKey)
        guard shortcut.modifiers == cmdShift else { return false }
        // 系统截图：⌘⇧3 全屏 / ⌘⇧4 区域 / ⌘⇧5 工具
        return shortcut.keyCode == UInt32(kVK_ANSI_3)
            || shortcut.keyCode == UInt32(kVK_ANSI_4)
            || shortcut.keyCode == UInt32(kVK_ANSI_5)
    }

    static func hotkeyConflictMessage(shortcut: HotKeyShortcut) -> String {
        if isSystemScreenshotShortcut(shortcut) {
            return "\(shortcut.displayString) 是系统截图快捷键（⌘⇧3/4/5）。请改键，或关掉系统设置里的截图快捷键"
        }
        if let names = rivalNamesText() {
            return "快捷键 \(shortcut.displayString) 注册失败，可能被 \(names) 占用。请改键或退出该软件"
        }
        return "快捷键 \(shortcut.displayString) 已被系统或其他软件占用，请到设置里改成别的组合"
    }

    static func windowSharingIsBlocked(_ id: CGWindowID) -> Bool {
        guard let list = CGWindowListCopyWindowInfo([.optionIncludingWindow], id) as? [[String: Any]],
              let info = list.first
        else { return false }
        let sharing = info[kCGWindowSharingState as String] as? Int ?? 1
        return sharing == 0
    }

    static func isMostlyBlack(_ image: CGImage) -> Bool {
        let tw = 24
        let th = 24
        var buf = [UInt8](repeating: 0, count: tw * th * 4)
        guard let ctx = CGContext(
            data: &buf,
            width: tw,
            height: th,
            bitsPerComponent: 8,
            bytesPerRow: tw * 4,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else { return false }
        ctx.interpolationQuality = .low
        ctx.draw(image, in: CGRect(x: 0, y: 0, width: tw, height: th))
        var dark = 0
        let n = tw * th
        for i in 0..<n {
            let o = i * 4
            if Int(buf[o]) + Int(buf[o + 1]) + Int(buf[o + 2]) < 48 {
                dark += 1
            }
        }
        return Double(dark) / Double(n) > 0.90
    }

    static func explainBlackWindow(id: CGWindowID) -> String {
        if windowSharingIsBlocked(id) {
            return "该窗口禁止被截屏（银行/密码/DRM 视频常见），系统会填成黑屏"
        }
        if let names = rivalNamesText() {
            return "窗口是黑的：\(names) 可能占用了屏幕采集。请退出后重试，或改用区域截图"
        }
        return "窗口是黑的：系统保护内容（浏览器全屏视频/DRM）无法采集。可改用区域截图试试"
    }
}
