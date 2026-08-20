import AppKit

final class AnnotationCanvasView: NSView {
    var document: AnnotationDocument! {
        didSet { needsDisplay = true }
    }

    var onRequestOCRToTXT: (() -> Void)?
    var onEscape: (() -> Void)?

    private var dragStart: CGPoint?
    private var dragCurrent: CGPoint?
    private var draftingShape: AnnotationItem.ShapeKind?
    private var textField: NSTextField?
    private var textFieldOrigin: CGPoint = .zero
    private var freehandPoints: [CGPoint] = []

    override var acceptsFirstResponder: Bool { true }
    override var isFlipped: Bool { false }

    override func draw(_ dirtyRect: NSRect) {
        guard let document else { return }
        let bounds = CGRect(origin: .zero, size: document.baseImage.size)
        document.baseImage.draw(in: bounds)
        AnnotationRenderer.draw(items: document.items, in: bounds, baseImage: document.baseImage)

        if let start = dragStart, let current = dragCurrent, let kind = draftingShape {
            AnnotationRenderer.draw(
                items: [.shape(id: UUID(), kind: kind, start: start, end: current, style: document.style)],
                in: bounds,
                baseImage: document.baseImage
            )
        }
    }

    override func mouseDown(with event: NSEvent) {
        let point = convert(event.locationInWindow, from: nil)
        guard let document else { return }

        // 正在输入文字时：点空白处提交，不要先抢走 firstResponder
        if textField != nil {
            commitTextField()
            return
        }

        switch document.tool {
        case .pen, .highlight:
            window?.makeFirstResponder(self)
            freehandPoints = [point]
            document.beginFreehand(at: point, highlight: document.tool == .highlight)
        case .arrow: beginShape(.arrow, at: point)
        case .line: beginShape(.line, at: point)
        case .rect: beginShape(.rect, at: point)
        case .ellipse: beginShape(.ellipse, at: point)
        case .blur:
            window?.makeFirstResponder(self)
            draftingShape = nil
            dragStart = point
            dragCurrent = point
        case .text:
            promptText(at: point)
        case .number, .step:
            window?.makeFirstResponder(self)
            document.add(.counter(id: UUID(), center: point, value: document.counterValue, style: document.style))
            needsDisplay = true
        case .select:
            window?.makeFirstResponder(self)
        }
    }

    override func mouseDragged(with event: NSEvent) {
        if textField != nil { return }
        let point = convert(event.locationInWindow, from: nil)
        guard let document else { return }

        switch document.tool {
        case .pen, .highlight:
            freehandPoints.append(point)
            document.updateLastFreehand(points: freehandPoints)
            needsDisplay = true
        case .arrow, .line, .rect, .ellipse, .blur:
            dragCurrent = point
            needsDisplay = true
        default:
            break
        }
    }

    override func mouseUp(with event: NSEvent) {
        if textField != nil { return }
        let point = convert(event.locationInWindow, from: nil)
        guard let document else { return }

        switch document.tool {
        case .arrow, .line, .rect, .ellipse:
            if let start = dragStart, let kind = draftingShape {
                let dist = hypot(point.x - start.x, point.y - start.y)
                if dist > 3 {
                    document.add(.shape(id: UUID(), kind: kind, start: start, end: point, style: document.style))
                }
            }
        case .blur:
            if let start = dragStart {
                let rect = CGRect(
                    x: min(start.x, point.x),
                    y: min(start.y, point.y),
                    width: abs(point.x - start.x),
                    height: abs(point.y - start.y)
                )
                if rect.width > 4, rect.height > 4 {
                    document.add(.blur(id: UUID(), rect: rect))
                }
            }
        default:
            break
        }

        dragStart = nil
        dragCurrent = nil
        draftingShape = nil
        freehandPoints = []
        needsDisplay = true
    }

    override func rightMouseDown(with event: NSEvent) {
        let menu = NSMenu(title: "Flare")
        menu.addItem(withTitle: "OCR 并保存为 TXT…", action: #selector(ocrToTXT), keyEquivalent: "").target = self
        menu.addItem(.separator())
        menu.addItem(withTitle: "复制图像", action: #selector(copyImage), keyEquivalent: "").target = self
        NSMenu.popUpContextMenu(menu, with: event, for: self)
    }

    @objc private func ocrToTXT() {
        onRequestOCRToTXT?()
    }

    @objc private func copyImage() {
        if let image = document?.renderedImage() {
            ImageExporter.copyToClipboard(image)
            ToastController.shared.show("已复制到剪贴板")
        }
    }

    override func keyDown(with event: NSEvent) {
        if textField != nil {
            // 交给输入框；Esc 仍可取消输入
            if event.keyCode == 53 {
                cancelTextField()
                return
            }
            return
        }
        if event.keyCode == 53 { // Esc
            onEscape?()
            return
        }
        if event.modifierFlags.contains(.command) {
            switch event.charactersIgnoringModifiers {
            case "z":
                if event.modifierFlags.contains(.shift) { document?.redo() } else { document?.undo() }
                needsDisplay = true
                return
            case "c":
                copyImage()
                return
            default: break
            }
        }
        if event.keyCode == 51 || event.keyCode == 117 {
            document?.undo()
            needsDisplay = true
            return
        }
        super.keyDown(with: event)
    }

    private func beginShape(_ kind: AnnotationItem.ShapeKind, at point: CGPoint) {
        window?.makeFirstResponder(self)
        draftingShape = kind
        dragStart = point
        dragCurrent = point
    }

    private func promptText(at point: CGPoint) {
        commitTextField()

        // 放到窗口 contentView，避免选区 masksToBounds 裁切输入框，也更易成为 first responder
        let host = window?.contentView ?? self
        let hostPoint = convert(point, to: host)

        let field = NSTextField(frame: .zero)
        field.placeholderString = "输入文字，回车确认"
        field.isBordered = true
        field.isBezeled = true
        field.bezelStyle = .roundedBezel
        field.isEditable = true
        field.isSelectable = true
        field.drawsBackground = true
        field.backgroundColor = NSColor(calibratedWhite: 0.08, alpha: 0.92)
        field.textColor = .white
        field.font = NSFont.systemFont(ofSize: max(document.style.fontSize, 16), weight: .semibold)
        field.focusRingType = .exterior
        field.stringValue = ""
        field.cell?.wraps = false
        field.cell?.isScrollable = true
        field.cell?.usesSingleLineMode = true
        field.target = self
        field.action = #selector(commitText(_:))
        field.delegate = textFieldBridge

        let width: CGFloat = 280
        let height: CGFloat = 32
        var frame = CGRect(x: hostPoint.x, y: hostPoint.y - height / 2, width: width, height: height)
        let hostBounds = host.bounds
        frame.origin.x = min(max(8, frame.origin.x), max(8, hostBounds.maxX - width - 8))
        frame.origin.y = min(max(8, frame.origin.y), max(8, hostBounds.maxY - height - 8))
        field.frame = frame

        host.addSubview(field)
        textField = field
        textFieldOrigin = point

        window?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        // 下一拍再抢焦点，避开 mouseDown 链路里的 responder 竞争
        DispatchQueue.main.async { [weak self, weak field] in
            guard let self, let field, field === self.textField else { return }
            self.window?.makeFirstResponder(field)
            field.currentEditor()?.selectedRange = NSRange(location: 0, length: 0)
        }
    }

    @objc private func commitText(_ sender: NSTextField) {
        let text = sender.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
        sender.removeFromSuperview()
        if textField === sender { textField = nil }
        guard !text.isEmpty, let document else {
            window?.makeFirstResponder(self)
            return
        }
        document.add(.text(id: UUID(), text: text, origin: textFieldOrigin, style: document.style))
        needsDisplay = true
        window?.makeFirstResponder(self)
    }

    private func commitTextField() {
        guard let field = textField else { return }
        commitText(field)
    }

    private func cancelTextField() {
        textField?.removeFromSuperview()
        textField = nil
        window?.makeFirstResponder(self)
    }

    private lazy var textFieldBridge = AnnotationTextFieldBridge { [weak self] field in
        self?.commitText(field)
    }
}

/// NSTextField 失焦时提交文字
private final class AnnotationTextFieldBridge: NSObject, NSTextFieldDelegate {
    private let onEnd: (NSTextField) -> Void

    init(onEnd: @escaping (NSTextField) -> Void) {
        self.onEnd = onEnd
    }

    func controlTextDidEndEditing(_ obj: Notification) {
        guard let field = obj.object as? NSTextField else { return }
        onEnd(field)
    }

    func control(_ control: NSControl, textView: NSTextView, doCommandBy commandSelector: Selector) -> Bool {
        if commandSelector == #selector(NSResponder.insertNewline(_:)) {
            if let field = control as? NSTextField {
                onEnd(field)
            }
            return true
        }
        if commandSelector == #selector(NSResponder.cancelOperation(_:)) {
            if let field = control as? NSTextField {
                field.stringValue = ""
                onEnd(field)
            }
            return true
        }
        return false
    }
}
