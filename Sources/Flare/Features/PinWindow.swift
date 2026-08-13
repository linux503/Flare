import AppKit

final class PinWindowController {
    static let shared = PinWindowController()
    private var pins: [PinnedImageWindow] = []
    private init() {}

    func pin(image: NSImage) {
        let pin = PinnedImageWindow(image: image)
        pin.onClose = { [weak self, weak pin] in
            guard let self, let pin else { return }
            self.pins.removeAll { $0 === pin }
        }
        pins.append(pin)
        pin.show()
    }
}

final class PinnedImageWindow: NSObject {
    var onClose: (() -> Void)?

    private let window: NSWindow
    private let imageView: NSImageView
    private let toolbar: NSView

    init(image: NSImage) {
        let size = image.size
        let maxSide: CGFloat = 520
        let scale = min(1, maxSide / max(size.width, size.height))
        let frameSize = NSSize(width: max(size.width * scale, 160), height: max(size.height * scale, 120))

        window = NSWindow(
            contentRect: NSRect(origin: .zero, size: frameSize),
            styleMask: [.borderless, .resizable],
            backing: .buffered,
            defer: false
        )
        window.isOpaque = false
        window.backgroundColor = .clear
        window.hasShadow = true
        window.level = .floating
        window.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        window.isMovableByWindowBackground = true
        window.minSize = NSSize(width: 100, height: 80)

        let root = NSView(frame: NSRect(origin: .zero, size: frameSize))
        root.wantsLayer = true

        imageView = NSImageView(frame: NSRect(origin: .zero, size: frameSize))
        imageView.image = image
        imageView.imageScaling = .scaleProportionallyUpOrDown
        imageView.wantsLayer = true
        imageView.layer?.cornerRadius = 10
        imageView.layer?.masksToBounds = true
        imageView.layer?.borderWidth = 1.5
        imageView.layer?.borderColor = FlareBrand.accent.withAlphaComponent(0.55).cgColor
        root.addSubview(imageView)

        toolbar = NSView(frame: NSRect(x: 8, y: frameSize.height - 36, width: 96, height: 28))
        toolbar.wantsLayer = true
        // 固定深色底 + 白图标，避免霜白主题下 ink 变浅导致白字看不见
        toolbar.layer?.backgroundColor = NSColor.black.withAlphaComponent(0.72).cgColor
        toolbar.layer?.cornerRadius = 8
        root.addSubview(toolbar)

        window.contentView = root
        window.center()
        super.init()

        addToolButton(glyph: .close, x: 6, action: #selector(closePin))
        addToolButton(glyph: .copy, x: 34, action: #selector(copyPin))
        addToolButton(glyph: .save, x: 62, action: #selector(savePin))

        let rightClick = NSClickGestureRecognizer(target: self, action: #selector(showContextMenu(_:)))
        rightClick.buttonMask = 0x2
        imageView.addGestureRecognizer(rightClick)
    }

    @objc private func showContextMenu(_ gesture: NSClickGestureRecognizer) {
        guard gesture.state == .ended, let view = gesture.view else { return }
        let menu = NSMenu()
        menu.addItem(withTitle: "复制", action: #selector(copyPin), keyEquivalent: "").target = self
        menu.addItem(withTitle: "保存图片", action: #selector(savePin), keyEquivalent: "").target = self
        menu.addItem(withTitle: "OCR 并保存为 TXT…", action: #selector(ocrTXT), keyEquivalent: "").target = self
        menu.addItem(.separator())
        menu.addItem(withTitle: "关闭", action: #selector(closePin), keyEquivalent: "").target = self
        let loc = gesture.location(in: view)
        menu.popUp(positioning: nil, at: loc, in: view)
    }

    @objc private func ocrTXT() {
        guard let image = imageView.image else { return }
        Task {
            do {
                let url = try await TextFileService.createTXTFromOCR(image: image, askWhere: true)
                await MainActor.run {
                    ToastController.shared.show("已保存 \(url.lastPathComponent)")
                    TextFileService.reveal(url)
                }
            } catch {
                await MainActor.run {
                    if (error as? TextFileService.TextFileError) != .cancelled {
                        ToastController.shared.show("OCR 导出失败")
                    }
                }
            }
        }
    }

    private func addToolButton(glyph: SnapGlyph, x: CGFloat, action: Selector) {
        let button = NSButton(frame: NSRect(x: x, y: 4, width: 20, height: 20))
        button.bezelStyle = .inline
        button.isBordered = false
        button.image = FlareBrand.menuSymbol(glyph, pointSize: 12)
        button.imagePosition = .imageOnly
        button.contentTintColor = .white
        button.target = self
        button.action = action
        toolbar.addSubview(button)
    }

    func show() {
        window.makeKeyAndOrderFront(nil)
    }

    @objc private func closePin() {
        window.orderOut(nil)
        onClose?()
    }

    @objc private func copyPin() {
        if let image = imageView.image {
            ImageExporter.copyToClipboard(image)
            ToastController.shared.show("已复制")
        }
    }

    @objc private func savePin() {
        guard let image = imageView.image else { return }
        if let url = try? ImageExporter.save(image) {
            ToastController.shared.show("已保存：\(url.lastPathComponent)")
        }
    }
}
