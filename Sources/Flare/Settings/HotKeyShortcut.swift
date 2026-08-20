import AppKit
import Carbon
import SwiftUI

struct HotKeyShortcut: Equatable, Hashable {
    var keyCode: UInt32
    var modifiers: UInt32 // Carbon modifiers

    static let empty = HotKeyShortcut(keyCode: 0, modifiers: 0)

    var isValid: Bool {
        // keyCode 0 是 ⌘A 的 A（kVK_ANSI_A），不能当无效
        modifiers != 0
    }

    var displayString: String {
        guard isValid else { return "未设置" }
        return HotKeyShortcut.symbolString(modifiers: modifiers) + HotKeyShortcut.keyName(keyCode: keyCode)
    }

    static func symbolString(modifiers: UInt32) -> String {
        var s = ""
        if modifiers & UInt32(controlKey) != 0 { s += "⌃" }
        if modifiers & UInt32(optionKey) != 0 { s += "⌥" }
        if modifiers & UInt32(shiftKey) != 0 { s += "⇧" }
        if modifiers & UInt32(cmdKey) != 0 { s += "⌘" }
        return s
    }

    static func from(event: NSEvent) -> HotKeyShortcut? {
        // 忽略单纯修饰键
        let pureModifiers: Set<UInt16> = [54, 55, 56, 57, 58, 59, 60, 61, 62, 63]
        if pureModifiers.contains(event.keyCode) { return nil }

        var carbon: UInt32 = 0
        let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
        if flags.contains(.control) { carbon |= UInt32(controlKey) }
        if flags.contains(.option) { carbon |= UInt32(optionKey) }
        if flags.contains(.shift) { carbon |= UInt32(shiftKey) }
        if flags.contains(.command) { carbon |= UInt32(cmdKey) }

        // 全局热键至少要有一个修饰键，避免误触
        guard carbon != 0 else { return nil }
        return HotKeyShortcut(keyCode: UInt32(event.keyCode), modifiers: carbon)
    }

    static func keyName(keyCode: UInt32) -> String {
        let map: [UInt32: String] = [
            UInt32(kVK_ANSI_A): "A", UInt32(kVK_ANSI_B): "B", UInt32(kVK_ANSI_C): "C",
            UInt32(kVK_ANSI_D): "D", UInt32(kVK_ANSI_E): "E", UInt32(kVK_ANSI_F): "F",
            UInt32(kVK_ANSI_G): "G", UInt32(kVK_ANSI_H): "H", UInt32(kVK_ANSI_I): "I",
            UInt32(kVK_ANSI_J): "J", UInt32(kVK_ANSI_K): "K", UInt32(kVK_ANSI_L): "L",
            UInt32(kVK_ANSI_M): "M", UInt32(kVK_ANSI_N): "N", UInt32(kVK_ANSI_O): "O",
            UInt32(kVK_ANSI_P): "P", UInt32(kVK_ANSI_Q): "Q", UInt32(kVK_ANSI_R): "R",
            UInt32(kVK_ANSI_S): "S", UInt32(kVK_ANSI_T): "T", UInt32(kVK_ANSI_U): "U",
            UInt32(kVK_ANSI_V): "V", UInt32(kVK_ANSI_W): "W", UInt32(kVK_ANSI_X): "X",
            UInt32(kVK_ANSI_Y): "Y", UInt32(kVK_ANSI_Z): "Z",
            UInt32(kVK_ANSI_0): "0", UInt32(kVK_ANSI_1): "1", UInt32(kVK_ANSI_2): "2",
            UInt32(kVK_ANSI_3): "3", UInt32(kVK_ANSI_4): "4", UInt32(kVK_ANSI_5): "5",
            UInt32(kVK_ANSI_6): "6", UInt32(kVK_ANSI_7): "7", UInt32(kVK_ANSI_8): "8",
            UInt32(kVK_ANSI_9): "9",
            UInt32(kVK_Space): "Space",
            UInt32(kVK_Return): "↩",
            UInt32(kVK_Tab): "⇥",
            UInt32(kVK_Escape): "Esc",
            UInt32(kVK_Delete): "⌫",
            UInt32(kVK_ForwardDelete): "⌦",
            UInt32(kVK_LeftArrow): "←",
            UInt32(kVK_RightArrow): "→",
            UInt32(kVK_UpArrow): "↑",
            UInt32(kVK_DownArrow): "↓",
            UInt32(kVK_F1): "F1", UInt32(kVK_F2): "F2", UInt32(kVK_F3): "F3",
            UInt32(kVK_F4): "F4", UInt32(kVK_F5): "F5", UInt32(kVK_F6): "F6",
            UInt32(kVK_F7): "F7", UInt32(kVK_F8): "F8", UInt32(kVK_F9): "F9",
            UInt32(kVK_F10): "F10", UInt32(kVK_F11): "F11", UInt32(kVK_F12): "F12",
            UInt32(kVK_ANSI_Minus): "-",
            UInt32(kVK_ANSI_Equal): "=",
            UInt32(kVK_ANSI_LeftBracket): "[",
            UInt32(kVK_ANSI_RightBracket): "]",
            UInt32(kVK_ANSI_Semicolon): ";",
            UInt32(kVK_ANSI_Quote): "'",
            UInt32(kVK_ANSI_Comma): ",",
            UInt32(kVK_ANSI_Period): ".",
            UInt32(kVK_ANSI_Slash): "/",
            UInt32(kVK_ANSI_Backslash): "\\",
            UInt32(kVK_ANSI_Grave): "`"
        ]
        return map[keyCode] ?? "Key\(keyCode)"
    }
}

enum HotKeyAction: String, CaseIterable, Identifiable {
    case area, window, screen, delay, longShot, record, history

    var id: String { rawValue }

    var title: String {
        switch self {
        case .area: return "区域截图"
        case .window: return "窗口截图"
        case .screen: return "全屏截图"
        case .delay: return "延时截图"
        case .longShot: return "长截图"
        case .record: return "屏幕录制"
        case .history: return "历史记录"
        }
    }

    var defaultShortcut: HotKeyShortcut {
        // 默认用 ⌘⌥，避开系统截图 ⌘⇧3/4/5（否则 RegisterEventHotKey 会静默失败）
        switch self {
        case .area:
            return HotKeyShortcut(keyCode: HotKeyDefaults.areaKey, modifiers: HotKeyDefaults.cmdOption)
        case .window:
            return HotKeyShortcut(keyCode: HotKeyDefaults.windowKey, modifiers: HotKeyDefaults.cmdOption)
        case .screen:
            return HotKeyShortcut(keyCode: HotKeyDefaults.screenKey, modifiers: HotKeyDefaults.cmdOption)
        case .delay:
            return HotKeyShortcut(keyCode: HotKeyDefaults.delayKey, modifiers: HotKeyDefaults.cmdOption)
        case .longShot:
            return HotKeyShortcut(keyCode: HotKeyDefaults.longShotKey, modifiers: HotKeyDefaults.cmdOption)
        case .record:
            return HotKeyShortcut(keyCode: HotKeyDefaults.recordKey, modifiers: HotKeyDefaults.cmdOption)
        case .history:
            return HotKeyShortcut(keyCode: HotKeyDefaults.historyKey, modifiers: HotKeyDefaults.cmdOption)
        }
    }
}
