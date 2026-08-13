import AppKit
import QuartzCore

final class DelayOverlayController {
    static let shared = DelayOverlayController()

    private var window: NSWindow?
    private var timer: Timer?
    private var remaining = 0
    private var onFire: (() -> Void)?
    private var onCancel: (() -> Void)?
    private weak var label: NSTextField?
    private weak var ringLayer: CAShapeLayer?
    private var keyMonitor: Any?
    private var totalSeconds = 3

    private init() {}

    func start(seconds: Int, onFire: @escaping () -> Void, onCancel: @escaping () -> Void) {
        cleanup(keepCallbacks: false)
        self.onFire = onFire
        self.onCancel = onCancel
        totalSeconds = max(1, seconds)
        remaining = totalSeconds

        let mouseScreen = NSScreen.screens.first { NSMouseInRect(NSEvent.mouseLocation, $0.frame, false) }
        let screen = mouseScreen?.visibleFrame ?? NSScreen.main?.visibleFrame ?? .zero
        let size = NSSize(width: 180, height: 180)
        let origin = NSPoint(x: screen.midX - size.width / 2, y: screen.midY - size.height / 2)

        let window = NSWindow(
            contentRect: NSRect(origin: origin, size: size),
            styleMask: .borderless,
            backing: .buffered,
            defer: false
        )
        window.isOpaque = false
        window.backgroundColor = .clear
        window.level = .floating
        window.hasShadow = true
        window.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        window.isMovableByWindowBackground = true
        window.alphaValue = 0

        let container = KeyView(frame: NSRect(origin: .zero, size: size))
        container.wantsLayer = true
        container.layer?.backgroundColor = NSColor.black.withAlphaComponent(0.72).cgColor
        container.layer?.cornerRadius = 32
        container.layer?.borderWidth = 1
        container.layer?.borderColor = NSColor.white.withAlphaComponent(0.2).cgColor
        container.onEscape = { [weak self] in self?.cancel() }

        let ring = CAShapeLayer()
        let inset: CGFloat = 18
        let path = CGPath(ellipseIn: CGRect(x: inset, y: inset, width: size.width - inset * 2, height: size.height - inset * 2), transform: nil)
        ring.path = path
        ring.fillColor = NSColor.clear.cgColor
        ring.strokeColor = NSColor.white.withAlphaComponent(0.85).cgColor
        ring.lineWidth = 4
        ring.lineCap = .round
        ring.strokeEnd = 1
        ring.transform = CATransform3DMakeRotation(-.pi / 2, 0, 0, 1)
        ring.frame = container.bounds
        container.layer?.addSublayer(ring)
        ringLayer = ring

        let title = NSTextField(labelWithString: "\(remaining)")
        title.font = NSFont.monospacedDigitSystemFont(ofSize: 56, weight: .bold)
        title.textColor = NSColor.white
        title.alignment = .center
        title.frame = NSRect(x: 0, y: 56, width: size.width, height: 70)
        container.addSubview(title)
        label = title

        let hint = NSTextField(labelWithString: "Esc 取消")
        hint.font = NSFont.systemFont(ofSize: 12, weight: .medium)
        hint.textColor = NSColor.white.withAlphaComponent(0.55)
        hint.alignment = .center
        hint.frame = NSRect(x: 0, y: 32, width: size.width, height: 18)
        container.addSubview(hint)

        window.contentView = container
        window.makeKeyAndOrderFront(nil)
        window.makeFirstResponder(container)
        self.window = window

        NSAnimationContext.runAnimationGroup { ctx in
            ctx.duration = 0.18
            window.animator().alphaValue = 1
        }
        pulseLabel()

        keyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            if event.keyCode == 53 {
                self?.cancel()
                return nil
            }
            return event
        }

        timer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in
            self?.tick()
        }
        if let timer {
            RunLoop.main.add(timer, forMode: .common)
        }
        updateRing(animated: false)
    }

    private func tick() {
        remaining -= 1
        if remaining <= 0 {
            let fire = onFire
            cleanup(keepCallbacks: false)
            fire?()
            return
        }
        label?.stringValue = "\(remaining)"
        pulseLabel()
        updateRing(animated: true)
    }

    private func updateRing(animated: Bool) {
        let progress = CGFloat(remaining) / CGFloat(max(totalSeconds, 1))
        if animated {
            let anim = CABasicAnimation(keyPath: "strokeEnd")
            anim.fromValue = ringLayer?.presentation()?.strokeEnd ?? ringLayer?.strokeEnd
            anim.toValue = progress
            anim.duration = 0.35
            anim.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
            ringLayer?.strokeEnd = progress
            ringLayer?.add(anim, forKey: "stroke")
        } else {
            ringLayer?.strokeEnd = progress
        }
    }

    private func pulseLabel() {
        guard let label else { return }
        label.layer?.removeAllAnimations()
        let anim = CABasicAnimation(keyPath: "transform.scale")
        anim.fromValue = 1.12
        anim.toValue = 1.0
        anim.duration = 0.35
        anim.timingFunction = CAMediaTimingFunction(name: .easeOut)
        label.wantsLayer = true
        label.layer?.add(anim, forKey: "pulse")
    }

    func cancel() {
        let cancel = onCancel
        cleanup(keepCallbacks: false)
        cancel?()
    }

    private func cleanup(keepCallbacks: Bool) {
        timer?.invalidate()
        timer = nil
        if let keyMonitor {
            NSEvent.removeMonitor(keyMonitor)
            self.keyMonitor = nil
        }
        window?.orderOut(nil)
        window = nil
        label = nil
        ringLayer = nil
        if !keepCallbacks {
            onFire = nil
            onCancel = nil
        }
    }

    private final class KeyView: NSView {
        var onEscape: (() -> Void)?
        override var acceptsFirstResponder: Bool { true }
        override func keyDown(with event: NSEvent) {
            if event.keyCode == 53 {
                onEscape?()
            } else {
                super.keyDown(with: event)
            }
        }
    }
}
