import AppKit
import Carbon
import os.log

extension Notification.Name {
    static let flareSettingsChanged = Notification.Name("flareSettingsChanged")
}

final class HotKeyManager {
    static let shared = HotKeyManager()

    private let log = Logger(subsystem: "app.flare.screenshot", category: "HotKey")
    private var hotKeyRefs: [UInt32: EventHotKeyRef] = [:]
    private var handlerRef: EventHandlerRef?
    private var localMonitor: Any?
    private var globalMonitor: Any?
    /// Carbon 注册失败时的本地/全局键监听兜底
    private var monitorBindings: [(HotKeyShortcut, ActionID)] = []

    private enum ActionID: UInt32 {
        case area = 1
        case window = 2
        case screen = 3
        case history = 4
        case delay = 5
        case record = 6
    }

    private init() {
        installHandler()
    }

    func registerDefaults() {
        unregisterAll()
        stopMonitors()
        monitorBindings.removeAll()

        let settings = AppSettings.shared
        let pairs: [(ActionID, HotKeyAction)] = [
            (.area, .area),
            (.window, .window),
            (.screen, .screen),
            (.delay, .delay),
            (.record, .record),
            (.history, .history)
        ]

        var usedFallbackMonitor = false
        for (id, action) in pairs {
            let shortcut = settings.shortcut(for: action)
            if register(id: id, shortcut: shortcut) {
                continue
            }

            // 系统占用 ⌘⇧3/4/5 时，自动切到 ⌘⌥ 同键位
            let alt = HotKeyShortcut(keyCode: shortcut.keyCode, modifiers: HotKeyDefaults.cmdOption)
            if alt != shortcut, register(id: id, shortcut: alt) {
                settings.setShortcut(alt, for: action, notifyObservers: false)
                log.info("hotkey \(action.rawValue) fell back to \(alt.displayString, privacy: .public)")
                continue
            }

            monitorBindings.append((shortcut, id))
            usedFallbackMonitor = true
            log.error("RegisterEventHotKey failed for \(action.rawValue) \(shortcut.displayString, privacy: .public)")
        }

        if usedFallbackMonitor {
            startMonitors()
            DispatchQueue.main.async {
                ToastController.shared.show("部分快捷键改用备用监听")
            }
        }
    }

    func unregisterAll() {
        for (_, ref) in hotKeyRefs {
            UnregisterEventHotKey(ref)
        }
        hotKeyRefs.removeAll()
    }

    @discardableResult
    private func register(id: ActionID, shortcut: HotKeyShortcut) -> Bool {
        guard shortcut.isValid else { return false }
        var ref: EventHotKeyRef?
        let hotKeyID = EventHotKeyID(signature: OSType(0x534E4150), id: id.rawValue) // SNAP
        let status = RegisterEventHotKey(
            shortcut.keyCode,
            shortcut.modifiers,
            hotKeyID,
            GetEventDispatcherTarget(),
            0,
            &ref
        )
        if status == noErr, let ref {
            hotKeyRefs[id.rawValue] = ref
            return true
        }
        log.error("RegisterEventHotKey status=\(status) id=\(id.rawValue)")
        return false
    }

    private func installHandler() {
        var eventType = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
        let status = InstallEventHandler(
            GetEventDispatcherTarget(),
            { _, event, _ -> OSStatus in
                guard let event else { return OSStatus(eventNotHandledErr) }
                var hkID = EventHotKeyID()
                GetEventParameter(
                    event,
                    EventParamName(kEventParamDirectObject),
                    EventParamType(typeEventHotKeyID),
                    nil,
                    MemoryLayout<EventHotKeyID>.size,
                    nil,
                    &hkID
                )
                let actionID = hkID.id
                DispatchQueue.main.async {
                    HotKeyManager.shared.handle(id: actionID)
                }
                return noErr
            },
            1,
            &eventType,
            nil,
            &handlerRef
        )
        if status != noErr {
            log.error("InstallEventHandler failed: \(status)")
        }
    }

    private func startMonitors() {
        stopMonitors()
        let handler: (NSEvent) -> Void = { [weak self] event in
            self?.matchMonitor(event)
        }
        localMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
            handler(event)
            return event
        }
        globalMonitor = NSEvent.addGlobalMonitorForEvents(matching: .keyDown, handler: handler)
    }

    private func stopMonitors() {
        if let localMonitor {
            NSEvent.removeMonitor(localMonitor)
            self.localMonitor = nil
        }
        if let globalMonitor {
            NSEvent.removeMonitor(globalMonitor)
            self.globalMonitor = nil
        }
    }

    private func matchMonitor(_ event: NSEvent) {
        guard let shortcut = HotKeyShortcut.from(event: event) else { return }
        for (bound, id) in monitorBindings where bound == shortcut {
            DispatchQueue.main.async {
                HotKeyManager.shared.handle(id: id.rawValue)
            }
            return
        }
    }

    fileprivate func handle(id: UInt32) {
        switch ActionID(rawValue: id) {
        case .area:
            CaptureCoordinator.shared.startAreaCapture()
        case .window:
            CaptureCoordinator.shared.startWindowCapture()
        case .screen:
            CaptureCoordinator.shared.startFullScreenCapture()
        case .history:
            HistoryWindowController.shared.show()
        case .delay:
            CaptureCoordinator.shared.startDelayedCapture(seconds: 3)
        case .record:
            ScreenRecorder.shared.toggle()
        case .none:
            break
        }
    }
}

enum HotKeyDefaults {
    /// 避免与系统截图 ⌘⇧3/4/5 冲突：默认用 ⌘⌥
    static let cmdShift: UInt32 = UInt32(cmdKey | shiftKey)
    static let cmdOption: UInt32 = UInt32(cmdKey | optionKey)

    static let areaKey: UInt32 = UInt32(kVK_ANSI_5)
    static let windowKey: UInt32 = UInt32(kVK_ANSI_6)
    static let screenKey: UInt32 = UInt32(kVK_ANSI_4)
    static let delayKey: UInt32 = UInt32(kVK_ANSI_3)
    static let recordKey: UInt32 = UInt32(kVK_ANSI_R)
    static let historyKey: UInt32 = UInt32(kVK_ANSI_H)
}
