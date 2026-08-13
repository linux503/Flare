import AppKit

final class AnnotationCanvasView: NSView {
    var document: AnnotationDocument! {
        didSet { needsDisplay = true }
    }

    var onRequestOCRToTXT: (() -> Void)?

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
        window?.makeFirstResponder(self)
        let point = convert(event.locationInWindow, from: nil)
        guard let document else { return }

        switch document.tool {
        case .pen, .highlight:
            freehandPoints = [point]
            document.beginFreehand(at: point, highlight: document.tool == .highlight)
        case .arrow: beginShape(.arrow, at: point)
        case .line: beginShape(.line, at: point)
        case .rect: beginShape(.rect, at: point)
        case .ellipse: beginShape(.ellipse, at: point)
        case .blur:
            draftingShape = nil
            dragStart = point
            dragCurrent = point
        case .text:
            promptText(at: point)
        case .number, .step:
            document.add(.counter(id: UUID(), center: point, value: document.counterValue, style: document.style))
            needsDisplay = true
        case .select:
            break
        }
    }

    override func mouseDragged(with event: NSEvent) {
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
        draftingShape = kind
        dragStart = point
        dragCurrent = point
    }

    private func promptText(at point: CGPoint) {
        textField?.removeFromSuperview()
        let field = NSTextField(frame: CGRect(x: point.x, y: point.y - 16, width: 240, height: 28))
        field.placeholderString = "输入文字，回车确认"
        field.isBordered = true
        field.backgroundColor = NSColor.black.withAlphaComponent(0.55)
        field.textColor = .white
        field.font = NSFont.systemFont(ofSize: document.style.fontSize, weight: .semibold)
        field.focusRingType = .none
        field.target = self
        field.action = #selector(commitText(_:))
        addSubview(field)
        window?.makeFirstResponder(field)
        textField = field
        textFieldOrigin = point
    }

    @objc private func commitText(_ sender: NSTextField) {
        let text = sender.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
        sender.removeFromSuperview()
        textField = nil
        guard !text.isEmpty, let document else { return }
        document.add(.text(id: UUID(), text: text, origin: textFieldOrigin, style: document.style))
        needsDisplay = true
        window?.makeFirstResponder(self)
    }
}
