import Foundation
import Carbon
import AppKit

final class AppSettings {
    static let shared = AppSettings()

    private let defaults = UserDefaults.standard

    var saveDirectory: URL {
        get {
            if let path = defaults.string(forKey: "saveDirectory"), !path.isEmpty {
                return URL(fileURLWithPath: path)
            }
            return FileManager.default.urls(for: .picturesDirectory, in: .userDomainMask)[0]
                .appendingPathComponent("Flare", isDirectory: true)
        }
        set {
            defaults.set(newValue.path, forKey: "saveDirectory")
            notify()
        }
    }

    /// 新建文档（TXT / Word / PPT / Excel）默认目录，与截图保存目录分开
    var documentDirectory: URL {
        get {
            if let path = defaults.string(forKey: "documentDirectory"), !path.isEmpty {
                return URL(fileURLWithPath: path)
            }
            return FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
                .appendingPathComponent("Flare", isDirectory: true)
        }
        set {
            defaults.set(newValue.path, forKey: "documentDirectory")
            notify()
        }
    }

    var imageFormat: ImageFormat {
        get { ImageFormat(rawValue: defaults.string(forKey: "imageFormat") ?? "png") ?? .png }
        set { defaults.set(newValue.rawValue, forKey: "imageFormat"); notify() }
    }

    var copyToClipboard: Bool {
        get { defaults.object(forKey: "copyToClipboard") as? Bool ?? true }
        set { defaults.set(newValue, forKey: "copyToClipboard"); notify() }
    }

    var openEditorAfterCapture: Bool {
        get { defaults.object(forKey: "openEditorAfterCapture") as? Bool ?? true }
        set { defaults.set(newValue, forKey: "openEditorAfterCapture"); notify() }
    }

    var playSound: Bool {
        get { defaults.object(forKey: "playSound") as? Bool ?? true }
        set { defaults.set(newValue, forKey: "playSound"); notify() }
    }

    var showMagnifier: Bool {
        get { defaults.object(forKey: "showMagnifier") as? Bool ?? true }
        set { defaults.set(newValue, forKey: "showMagnifier"); notify() }
    }

    var showInDock: Bool {
        get { defaults.object(forKey: "showInDock") as? Bool ?? true }
        set { defaults.set(newValue, forKey: "showInDock"); notify() }
    }

    var afterCaptureAction: AfterCaptureAction {
        get { AfterCaptureAction(rawValue: defaults.string(forKey: "afterCaptureAction") ?? "editor") ?? .editor }
        set { defaults.set(newValue.rawValue, forKey: "afterCaptureAction"); notify() }
    }

    var appTheme: AppThemeKind {
        get { AppThemeKind.migrated(from: defaults.string(forKey: "appTheme")) }
        set { defaults.set(newValue.rawValue, forKey: "appTheme"); notify() }
    }

    /// 主窗口透明度：1 = 不透明，越低越通透（约 0.72…1.0）
    /// 静默写入，避免拖动滑块时反复重注册热键 / 重建菜单
    var windowOpacity: Double {
        get {
            let v = defaults.object(forKey: "windowOpacity") as? Double ?? 0.94
            return min(1, max(0.72, v))
        }
        set {
            defaults.set(min(1, max(0.72, newValue)), forKey: "windowOpacity")
        }
    }

    // MARK: - Recording

    var recordDirectory: URL {
        get {
            if let path = defaults.string(forKey: "recordDirectory"), !path.isEmpty {
                return URL(fileURLWithPath: path)
            }
            return FileManager.default.urls(for: .moviesDirectory, in: .userDomainMask)[0]
                .appendingPathComponent("Flare", isDirectory: true)
        }
        set {
            defaults.set(newValue.path, forKey: "recordDirectory")
            notify()
        }
    }

    var recordShowCursor: Bool {
        get { defaults.object(forKey: "recordShowCursor") as? Bool ?? true }
        set { defaults.set(newValue, forKey: "recordShowCursor"); notify() }
    }

    var recordExcludeFlare: Bool {
        get { defaults.object(forKey: "recordExcludeFlare") as? Bool ?? true }
        set { defaults.set(newValue, forKey: "recordExcludeFlare"); notify() }
    }

    var recordHideFlareWindows: Bool {
        get { defaults.object(forKey: "recordHideFlareWindows") as? Bool ?? true }
        set { defaults.set(newValue, forKey: "recordHideFlareWindows"); notify() }
    }

    /// 开始录屏前倒计时秒数；0 = 立即开始
    var recordCountdownSeconds: Int {
        get {
            let v = defaults.object(forKey: "recordCountdownSeconds") as? Int ?? 3
            return min(10, max(0, v))
        }
        set { defaults.set(min(10, max(0, newValue)), forKey: "recordCountdownSeconds"); notify() }
    }

    var recordFPS: Int {
        get {
            let v = defaults.object(forKey: "recordFPS") as? Int ?? 30
            return [15, 24, 30, 60].contains(v) ? v : 30
        }
        set { defaults.set(newValue, forKey: "recordFPS"); notify() }
    }

    /// 默认录屏范围：全屏 / 区域
    var recordMode: RecordCaptureMode {
        get {
            let raw = defaults.string(forKey: "recordMode") ?? RecordCaptureMode.fullScreen.rawValue
            return RecordCaptureMode(rawValue: raw) ?? .fullScreen
        }
        set { defaults.set(newValue.rawValue, forKey: "recordMode"); notify() }
    }

    /// 清晰度预设
    var recordQuality: RecordQualityPreset {
        get {
            let raw = defaults.integer(forKey: "recordQuality")
            return RecordQualityPreset(rawValue: raw) ?? .high
        }
        set { defaults.set(newValue.rawValue, forKey: "recordQuality"); notify() }
    }

    /// 录屏声音：默认关闭。可选系统声音、麦克风，或两者。
    var recordAudioSource: RecordAudioSource {
        get {
            if let raw = defaults.string(forKey: "recordAudioSource"),
               let value = RecordAudioSource(rawValue: raw) {
                return value
            }
            return .off
        }
        set { defaults.set(newValue.rawValue, forKey: "recordAudioSource"); notify() }
    }

    // MARK: - Hotkeys

    func shortcut(for action: HotKeyAction) -> HotKeyShortcut {
        let def = action.defaultShortcut
        let codeKey = "\(action.rawValue)KeyCode"
        let modKey = "\(action.rawValue)Modifiers"
        guard defaults.object(forKey: codeKey) != nil || defaults.object(forKey: modKey) != nil else {
            return def
        }
        let code = UInt32(defaults.object(forKey: codeKey) as? Int ?? Int(def.keyCode))
        let mods = UInt32(defaults.object(forKey: modKey) as? Int ?? Int(def.modifiers))
        let stored = HotKeyShortcut(keyCode: code, modifiers: mods)
        if isCorrupted(stored) { return def }
        return stored
    }

    func setShortcut(_ shortcut: HotKeyShortcut, for action: HotKeyAction, notifyObservers: Bool = true) {
        guard !isCorrupted(shortcut) else { return }
        defaults.set(Int(shortcut.keyCode), forKey: "\(action.rawValue)KeyCode")
        defaults.set(Int(shortcut.modifiers), forKey: "\(action.rawValue)Modifiers")
        if notifyObservers { notify() }
    }

    func resetHotkeys() {
        for action in HotKeyAction.allCases {
            let def = action.defaultShortcut
            defaults.set(Int(def.keyCode), forKey: "\(action.rawValue)KeyCode")
            defaults.set(Int(def.modifiers), forKey: "\(action.rawValue)Modifiers")
        }
        notify()
    }

    /// 与旧字段兼容（若用户升级前已有设置）
    func migrateLegacyHotkeysIfNeeded() {
        let migratedKey = "hotkeysMigratedV2"
        guard defaults.bool(forKey: migratedKey) == false else { return }
        defaults.set(true, forKey: migratedKey)

        func absorb(_ legacyCode: String, _ legacyMod: String, _ action: HotKeyAction, _ fallbackMod: UInt32) {
            guard defaults.object(forKey: legacyCode) != nil else { return }
            let code = UInt32(defaults.integer(forKey: legacyCode))
            let mods = UInt32(defaults.object(forKey: legacyMod) as? Int ?? Int(fallbackMod))
            defaults.set(Int(code), forKey: "\(action.rawValue)KeyCode")
            defaults.set(Int(mods), forKey: "\(action.rawValue)Modifiers")
        }

        absorb("areaKeyCode", "areaModifiers", .area, HotKeyDefaults.cmdShift)
        absorb("windowKeyCode", "windowModifiers", .window, HotKeyDefaults.cmdShift)
        absorb("screenKeyCode", "screenModifiers", .screen, HotKeyDefaults.cmdShift)
        absorb("historyKeyCode", "historyModifiers", .history, HotKeyDefaults.cmdOption)
    }

    /// 修复曾把无效/半录制快捷键写成 ⌘A（keyCode=0, mods=cmd）导致热键失效
    func sanitizeHotkeysIfNeeded() {
        let key = "hotkeysSanitizedV3"
        var changed = false
        for action in HotKeyAction.allCases {
            let codeKey = "\(action.rawValue)KeyCode"
            let modKey = "\(action.rawValue)Modifiers"
            guard defaults.object(forKey: codeKey) != nil || defaults.object(forKey: modKey) != nil else { continue }
            let code = UInt32(defaults.object(forKey: codeKey) as? Int ?? 0)
            let mods = UInt32(defaults.object(forKey: modKey) as? Int ?? 0)
            let stored = HotKeyShortcut(keyCode: code, modifiers: mods)
            if isCorrupted(stored) {
                let def = action.defaultShortcut
                defaults.set(Int(def.keyCode), forKey: codeKey)
                defaults.set(Int(def.modifiers), forKey: modKey)
                changed = true
            }
        }
        if changed || defaults.bool(forKey: key) == false {
            defaults.set(true, forKey: key)
            if changed { notify() }
        }
    }

    /// 无修饰键，或「仅 ⌘ + A(keyCode 0)」——录制取消/写入失败时的常见坏值
    private func isCorrupted(_ shortcut: HotKeyShortcut) -> Bool {
        if shortcut.modifiers == 0 { return true }
        if shortcut.keyCode == 0 && shortcut.modifiers == UInt32(cmdKey) { return true }
        return false
    }

    /// 将旧的 ⌘⇧3/4/5（与系统截图冲突）迁移到 ⌘⌥3/4/5/6
    func migrateSystemConflictHotkeysIfNeeded() {
        let key = "hotkeysMigratedV5CmdOption"
        guard defaults.bool(forKey: key) == false else { return }
        defaults.set(true, forKey: key)

        let systemConflictMods = HotKeyDefaults.cmdShift
        let conflictKeys: Set<UInt32> = [
            HotKeyDefaults.delayKey,
            HotKeyDefaults.screenKey,
            HotKeyDefaults.areaKey,
            HotKeyDefaults.windowKey
        ]

        var changed = false
        for action in HotKeyAction.allCases {
            let codeKey = "\(action.rawValue)KeyCode"
            let modKey = "\(action.rawValue)Modifiers"
            if defaults.object(forKey: codeKey) == nil && defaults.object(forKey: modKey) == nil {
                let def = action.defaultShortcut
                defaults.set(Int(def.keyCode), forKey: codeKey)
                defaults.set(Int(def.modifiers), forKey: modKey)
                changed = true
                continue
            }
            let code = UInt32(defaults.object(forKey: codeKey) as? Int ?? 0)
            let mods = UInt32(defaults.object(forKey: modKey) as? Int ?? 0)
            if mods == systemConflictMods && conflictKeys.contains(code) {
                let def = action.defaultShortcut
                defaults.set(Int(def.keyCode), forKey: codeKey)
                defaults.set(Int(def.modifiers), forKey: modKey)
                changed = true
            }
        }
        // history 若仍是旧 cmdShift，也迁到默认
        let historyMods = UInt32(defaults.object(forKey: "historyModifiers") as? Int ?? 0)
        if historyMods == systemConflictMods {
            let def = HotKeyAction.history.defaultShortcut
            defaults.set(Int(def.keyCode), forKey: "historyKeyCode")
            defaults.set(Int(def.modifiers), forKey: "historyModifiers")
            changed = true
        }
        if changed { notify() }
    }

    func load() {
        migrateLegacyHotkeysIfNeeded()
        sanitizeHotkeysIfNeeded()
        migrateSystemConflictHotkeysIfNeeded()
        for action in HotKeyAction.allCases {
            let codeKey = "\(action.rawValue)KeyCode"
            let modKey = "\(action.rawValue)Modifiers"
            if defaults.object(forKey: codeKey) == nil || defaults.object(forKey: modKey) == nil {
                let def = action.defaultShortcut
                defaults.set(Int(def.keyCode), forKey: codeKey)
                defaults.set(Int(def.modifiers), forKey: modKey)
            }
        }
        try? FileManager.default.createDirectory(at: saveDirectory, withIntermediateDirectories: true)
        try? FileManager.default.createDirectory(at: documentDirectory, withIntermediateDirectories: true)
        try? FileManager.default.createDirectory(at: recordDirectory, withIntermediateDirectories: true)
    }

    private func notify() {
        NotificationCenter.default.post(name: .flareSettingsChanged, object: nil)
    }
}

enum ImageFormat: String, CaseIterable, Identifiable {
    case png, jpeg, tiff
    var id: String { rawValue }
    var displayName: String {
        switch self {
        case .png: return "PNG"
        case .jpeg: return "JPEG"
        case .tiff: return "TIFF"
        }
    }
    var fileExtension: String { rawValue }
}

enum AfterCaptureAction: String, CaseIterable, Identifiable {
    case editor, clipboard, save, pin
    var id: String { rawValue }
    var displayName: String {
        switch self {
        case .editor: return "打开编辑器"
        case .clipboard: return "复制到剪贴板"
        case .save: return "保存到文件"
        case .pin: return "钉在屏幕上"
        }
    }
}

enum RecordAudioSource: String, CaseIterable, Identifiable {
    case off
    case system
    case microphone
    case both

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .off: return "关闭"
        case .system: return "系统声音"
        case .microphone: return "麦克风"
        case .both: return "系统 + 麦克风"
        }
    }

    var capturesSystem: Bool { self == .system || self == .both }
    var capturesMicrophone: Bool { self == .microphone || self == .both }

    var toastHint: String {
        switch self {
        case .off: return ""
        case .system: return " · 系统声音"
        case .microphone: return " · 麦克风"
        case .both: return " · 系统+麦克风"
        }
    }
}

enum RecordCaptureMode: String, CaseIterable, Identifiable {
    case fullScreen
    case area

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .fullScreen: return "全屏"
        case .area: return "区域"
        }
    }
}

enum RecordQualityPreset: Int, CaseIterable, Identifiable {
    case performance = 0
    case standard = 1
    case high = 2
    case ultra = 3

    var id: Int { rawValue }

    var displayName: String {
        switch self {
        case .performance: return "流畅 720p"
        case .standard: return "标准 1080p"
        case .high: return "高清 原分辨率"
        case .ultra: return "超清 高码率"
        }
    }

    /// 相对原生分辨率的缩放（区域录屏时作用于选区尺寸）
    var resolutionScale: CGFloat {
        switch self {
        case .performance: return 0.5
        case .standard: return 0.75
        case .high: return 1.0
        case .ultra: return 1.0
        }
    }

    var bitrateMultiplier: Double {
        switch self {
        case .performance: return 0.55
        case .standard: return 0.85
        case .high: return 1.0
        case .ultra: return 1.65
        }
    }
}

extension HotKeyShortcut {
    var nsModifierFlags: NSEvent.ModifierFlags {
        var flags: NSEvent.ModifierFlags = []
        if modifiers & UInt32(controlKey) != 0 { flags.insert(.control) }
        if modifiers & UInt32(optionKey) != 0 { flags.insert(.option) }
        if modifiers & UInt32(shiftKey) != 0 { flags.insert(.shift) }
        if modifiers & UInt32(cmdKey) != 0 { flags.insert(.command) }
        return flags
    }

    /// 用于 NSMenuItem.keyEquivalent（单字符，小写）
    var menuKeyEquivalent: String {
        let name = HotKeyShortcut.keyName(keyCode: keyCode)
        if name.count == 1 { return name.lowercased() }
        // 功能键等菜单支持有限，留空（仍由全局热键触发）
        switch keyCode {
        case UInt32(kVK_Space): return " "
        default: return ""
        }
    }
}
