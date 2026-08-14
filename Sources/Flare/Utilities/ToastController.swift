import AppKit
import QuartzCore

final class ToastController {
    static let shared = ToastController()

    private var window: NSPanel?
    private var label: NSTextField?
    private var hideWork: DispatchWorkItem?

    private init() {}

    func show(_ text: String, on screen: NSScreen? = nil) {
        hideWork?.cancel()

        let attrs: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 13, weight: .semibold),
            .foregroundColor: NSColor.white
        ]
        let size = (text as NSString).size(withAttributes: attrs)
        let padX: CGFloat = 18
        let padY: CGFloat = 12
        let rect = NSRect(x: 0, y: 0, width: size.width + padX * 2, height: size.height + padY * 2)

        let panel: NSPanel
        if let existing = window {
            panel = existing
            panel.setContentSize(rect.size)
            label?.stringValue = text
            label?.frame = NSRect(x: padX, y: padY - 1, width: size.width, height: size.height)
            if let view = panel.contentView {
                view.frame = NSRect(origin: .zero, size: rect.size)
            }
        } else {
            panel = NSPanel(
                contentRect: rect,
                styleMask: [.borderless, .nonactivatingPanel],
                backing: .buffered,
                defer: false
            )
            panel.isOpaque = false
            panel.backgroundColor = .clear
            panel.level = .statusBar
            panel.hasShadow = true
            panel.sharingType = .none
            panel.ignoresMouseEvents = true
            panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .transient]

            let view = NSView(frame: rect)
            view.wantsLayer = true
        view.layer?.backgroundColor = NSColor.black.withAlphaComponent(0.78).cgColor
        view.layer?.cornerRadius = 12
        view.layer?.borderWidth = 1
        view.layer?.borderColor = NSColor.white.withAlphaComponent(0.18).cgColor

            let field = NSTextField(labelWithString: text)
            field.font = attrs[.font] as? NSFont
            field.textColor = .white
            field.frame = NSRect(x: padX, y: padY - 1, width: size.width, height: size.height)
            view.addSubview(field)
            panel.contentView = view
            label = field
            window = panel
        }

        let targetScreen = screen
            ?? NSScreen.screens.first { NSMouseInRect(NSEvent.mouseLocation, $0.frame, false) }
            ?? NSScreen.main
        if let frame = targetScreen?.visibleFrame {
            let origin = NSPoint(x: frame.midX - rect.width / 2, y: frame.minY + 56)
            panel.setFrame(NSRect(origin: origin, size: rect.size), display: true)
        }

        panel.alphaValue = 0
        panel.orderFront(nil)
        NSAnimationContext.runAnimationGroup { ctx in
            ctx.duration = 0.18
            ctx.timingFunction = CAMediaTimingFunction(name: .easeOut)
            panel.animator().alphaValue = 1
        }

        let work = DispatchWorkItem { [weak self] in
            guard let self, let panel = self.window else { return }
            NSAnimationContext.runAnimationGroup({ ctx in
                ctx.duration = 0.22
                ctx.timingFunction = CAMediaTimingFunction(name: .easeIn)
                panel.animator().alphaValue = 0
            }, completionHandler: {
                panel.orderOut(nil)
            })
        }
        hideWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.7, execute: work)
    }
}
