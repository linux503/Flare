import AppKit

/// 录屏中的浮动停止条
final class RecordingHUDController {
    static let shared = RecordingHUDController()

    private var window: NSWindow?
    private weak var timeLabel: NSTextField?
    private var keyMonitor: Any?

    private init() {}

    func show() {
        hide()

        let size = NSSize(width: 220, height: 52)
        let screen = NSScreen.main?.visibleFrame ?? .zero
        let origin = NSPoint(x: screen.midX - size.width / 2, y: screen.maxY - size.height - 28)

        let window = NSWindow(
            contentRect: NSRect(origin: origin, size: size),
            styleMask: [.borderless],
            backing: .buffered,
            defer: false
        )
        window.isOpaque = false
        window.backgroundColor = .clear
        window.level = .floating
        window.hasShadow = true
        window.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]
        window.isMovableByWindowBackground = true
        window.ignoresMouseEvents = false

        let root = NSView(frame: NSRect(origin: .zero, size: size))
        root.wantsLayer = true
        root.layer?.backgroundColor = NSColor.black.withAlphaComponent(0.82).cgColor
        root.layer?.cornerRadius = 14
        root.layer?.borderWidth = 1
        root.layer?.borderColor = NSColor.white.withAlphaComponent(0.18).cgColor
        if #available(macOS 10.15, *) {
            root.layer?.cornerCurve = .continuous
        }

        let dot = NSView(frame: NSRect(x: 16, y: 20, width: 12, height: 12))
        dot.wantsLayer = true
        dot.layer?.backgroundColor = NSColor.systemRed.cgColor
        dot.layer?.cornerRadius = 6
        root.addSubview(dot)

        let time = NSTextField(labelWithString: "00:00")
        time.font = .monospacedDigitSystemFont(ofSize: 15, weight: .semibold)
        time.textColor = .white
        time.frame = NSRect(x: 36, y: 14, width: 72, height: 24)
        root.addSubview(time)
        timeLabel = time

        let stop = NSButton(frame: NSRect(x: 118, y: 10, width: 86, height: 32))
        stop.title = "停止"
        stop.bezelStyle = .rounded
        stop.isBordered = false
        stop.wantsLayer = true
        stop.layer?.backgroundColor = NSColor.white.cgColor
        stop.layer?.cornerRadius = 8
        stop.contentTintColor = .black
        stop.font = .systemFont(ofSize: 13, weight: .semibold)
        stop.target = self
        stop.action = #selector(stopTapped)
        root.addSubview(stop)

        window.contentView = root
        window.orderFrontRegardless()
        self.window = window

        keyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            if event.keyCode == 53 { // Esc
                self?.stopTapped()
                return nil
            }
            return event
        }
    }

    func update(seconds: Int) {
        let m = seconds / 60
        let s = seconds % 60
        timeLabel?.stringValue = String(format: "%02d:%02d", m, s)
    }

    func hide() {
        if let keyMonitor {
            NSEvent.removeMonitor(keyMonitor)
            self.keyMonitor = nil
        }
        window?.orderOut(nil)
        window = nil
        timeLabel = nil
    }

    @objc private func stopTapped() {
        ScreenRecorder.shared.stop()
    }
}
