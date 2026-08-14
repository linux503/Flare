import AppKit

/// 录屏浮动控制条：计时 / 暂停 / 停止
final class RecordingHUDController {
    static let shared = RecordingHUDController()

    private var window: NSWindow?
    private weak var timeLabel: NSTextField?
    private weak var statusLabel: NSTextField?
    private weak var pauseButton: NSButton?
    private weak var pulseDot: NSView?
    private var keyMonitor: Any?
    private var pulseTimer: Timer?

    private init() {}

    func show() {
        hide()

        let size = NSSize(width: 300, height: 56)
        let screen = NSScreen.main?.visibleFrame ?? .zero
        let origin = NSPoint(x: screen.midX - size.width / 2, y: screen.maxY - size.height - 24)

        let window = NSWindow(
            contentRect: NSRect(origin: origin, size: size),
            styleMask: [.borderless],
            backing: .buffered,
            defer: false
        )
        window.isOpaque = false
        window.backgroundColor = .clear
        window.level = .statusBar
        window.hasShadow = true
        window.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]
        window.isMovableByWindowBackground = true

        let root = NSView(frame: NSRect(origin: .zero, size: size))
        root.wantsLayer = true
        root.layer?.backgroundColor = NSColor.black.withAlphaComponent(0.86).cgColor
        root.layer?.cornerRadius = 16
        root.layer?.borderWidth = 1
        root.layer?.borderColor = NSColor.white.withAlphaComponent(0.16).cgColor
        if #available(macOS 10.15, *) {
            root.layer?.cornerCurve = .continuous
        }

        let dot = NSView(frame: NSRect(x: 16, y: 22, width: 12, height: 12))
        dot.wantsLayer = true
        dot.layer?.backgroundColor = NSColor.systemRed.cgColor
        dot.layer?.cornerRadius = 6
        root.addSubview(dot)
        pulseDot = dot

        let time = NSTextField(labelWithString: "00:00")
        time.font = .monospacedDigitSystemFont(ofSize: 16, weight: .semibold)
        time.textColor = .white
        time.frame = NSRect(x: 36, y: 16, width: 64, height: 24)
        root.addSubview(time)
        timeLabel = time

        let status = NSTextField(labelWithString: "录制中")
        status.font = .systemFont(ofSize: 10, weight: .medium)
        status.textColor = NSColor.white.withAlphaComponent(0.55)
        status.frame = NSRect(x: 100, y: 18, width: 44, height: 20)
        root.addSubview(status)
        statusLabel = status

        let pause = makeChip(title: "暂停", x: 148) { [weak self] in
            ScreenRecorder.shared.togglePause()
            self?.syncPauseTitle()
        }
        root.addSubview(pause)
        pauseButton = pause

        let stop = makeChip(title: "停止", x: 210, emphasis: true) {
            ScreenRecorder.shared.stop()
        }
        root.addSubview(stop)

        window.contentView = root
        window.orderFrontRegardless()
        self.window = window

        keyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
            if event.keyCode == 53 { // Esc
                ScreenRecorder.shared.stop()
                return nil
            }
            if event.modifierFlags.contains(.command),
               event.charactersIgnoringModifiers?.lowercased() == "p" {
                ScreenRecorder.shared.togglePause()
                RecordingHUDController.shared.syncPauseTitle()
                return nil
            }
            return event
        }

        pulseTimer = Timer.scheduledTimer(withTimeInterval: 0.8, repeats: true) { [weak self] _ in
            guard let dot = self?.pulseDot?.layer else { return }
            if ScreenRecorder.shared.isPaused {
                dot.opacity = 0.35
                return
            }
            CATransaction.begin()
            CATransaction.setAnimationDuration(0.35)
            dot.opacity = dot.opacity < 0.6 ? 1 : 0.35
            CATransaction.commit()
        }
        if let pulseTimer {
            RunLoop.main.add(pulseTimer, forMode: .common)
        }
    }

    func update(seconds: Int) {
        timeLabel?.stringValue = String(format: "%02d:%02d", seconds / 60, seconds % 60)
    }

    func updatePaused(_ paused: Bool) {
        statusLabel?.stringValue = paused ? "已暂停" : "录制中"
        statusLabel?.textColor = paused
            ? NSColor.systemYellow.withAlphaComponent(0.9)
            : NSColor.white.withAlphaComponent(0.55)
        syncPauseTitle()
        pulseDot?.layer?.backgroundColor = (paused ? NSColor.systemYellow : NSColor.systemRed).cgColor
    }

    func hide() {
        pulseTimer?.invalidate()
        pulseTimer = nil
        if let keyMonitor {
            NSEvent.removeMonitor(keyMonitor)
            self.keyMonitor = nil
        }
        window?.orderOut(nil)
        window = nil
        timeLabel = nil
        statusLabel = nil
        pauseButton = nil
        pulseDot = nil
    }

    private func syncPauseTitle() {
        pauseButton?.title = ScreenRecorder.shared.isPaused ? "继续" : "暂停"
    }

    private func makeChip(title: String, x: CGFloat, emphasis: Bool = false, action: @escaping () -> Void) -> NSButton {
        let b = ClosureHUDButton(title: title, handler: action)
        b.frame = NSRect(x: x, y: 12, width: 52, height: 32)
        b.bezelStyle = .inline
        b.isBordered = false
        b.wantsLayer = true
        b.layer?.cornerRadius = 8
        if #available(macOS 10.15, *) {
            b.layer?.cornerCurve = .continuous
        }
        b.layer?.backgroundColor = (emphasis ? NSColor.white : NSColor.white.withAlphaComponent(0.12)).cgColor
        b.contentTintColor = emphasis ? NSColor.black.withAlphaComponent(0.88) : .white
        b.font = .systemFont(ofSize: 12, weight: .semibold)
        return b
    }
}

private final class ClosureHUDButton: NSButton {
    private let handler: () -> Void
    init(title: String, handler: @escaping () -> Void) {
        self.handler = handler
        super.init(frame: .zero)
        self.title = title
        self.target = self
        self.action = #selector(tap)
    }
    required init?(coder: NSCoder) { fatalError() }
    @objc private func tap() { handler() }
}
