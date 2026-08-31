import AppKit
import QuartzCore

enum CaptureMode {
    case area
    case window
    case longArea
    case recordArea
}

/// 选区确认后的去向（工具栏按钮可覆盖默认设置）
enum CaptureFinishAction: Equatable {
    case useSettings
    case editor
    case clipboard
    case save
    case pin
    case ocr

    static func from(after action: AfterCaptureAction) -> CaptureFinishAction {
        switch action {
        case .editor: return .editor
        case .clipboard: return .clipboard
        case .save: return .save
        case .pin: return .pin
        }
    }
}

/// 无边框截图层也必须能成为 key window，否则标注「文字」输入框收不到键盘事件。
private final class KeyableBorderlessWindow: NSWindow {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { true }
}

final class CaptureOverlayController {
    var onCancel: (() -> Void)?
    var onAreaSelected: ((CGImage, CGFloat, CaptureFinishAction) -> Void)?
    var onLongAreaSelected: ((CGDirectDisplayID, CGRect, CGRect, CGFloat) -> Void)? // displayID, displayBounds, selectionRect, selectionScale
    var onWindowSelected: ((CGWindowID) -> Void)?
    var onRecordAreaConfirmed: ((CGRect) -> Void)?

    private let window: NSWindow
    private let overlayView: CaptureOverlayView

    init(frame: CapturedFrame, mode: CaptureMode, windows: [WindowCapturer.WindowInfo] = []) {
        let screenFrame = frame.bounds
        window = KeyableBorderlessWindow(
            contentRect: screenFrame,
            styleMask: .borderless,
            backing: .buffered,
            defer: false
        )
        window.isOpaque = true
        window.backgroundColor = .black
        window.level = .screenSaver
        window.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .transient]
        window.ignoresMouseEvents = false
        window.acceptsMouseMovedEvents = true
        window.hasShadow = false
        window.sharingType = .none
        window.setFrame(screenFrame, display: true)

        let root = NSView(frame: NSRect(origin: .zero, size: screenFrame.size))
        root.wantsLayer = true
        root.layer?.contents = frame.image
        root.layer?.contentsGravity = .resize
        root.autoresizingMask = [.width, .height]

        let overlay = CaptureOverlayView(
            frame: root.bounds,
            captured: frame,
            mode: mode,
            windows: windows
        )
        overlay.autoresizingMask = [.width, .height]
        overlayView = overlay
        root.addSubview(overlay)
        window.contentView = root
        window.alphaValue = 0

        overlay.onCancel = { [weak self] in self?.onCancel?() }
        overlay.onAreaSelected = { [weak self] image, scale, action in
            self?.onAreaSelected?(image, scale, action)
        }
        overlay.onLongAreaSelected = { [weak self] displayID, displayBounds, selectionRect, scale in
            self?.onLongAreaSelected?(displayID, displayBounds, selectionRect, scale)
        }
        overlay.onWindowSelected = { [weak self] id in
            self?.onWindowSelected?(id)
        }
        overlay.onRecordAreaConfirmed = { [weak self] rect in
            self?.onRecordAreaConfirmed?(rect)
        }
    }

    func show() {
        window.makeKeyAndOrderFront(nil)
        window.makeFirstResponder(overlayView)
        NSApp.activate(ignoringOtherApps: true)
        NSAnimationContext.runAnimationGroup { ctx in
            ctx.duration = 0.12
            window.animator().alphaValue = 1
        }
    }

    func close() {
        window.orderOut(nil)
    }
}

/// 透明交互层：只画蒙版/选区/放大镜，背景截图在父视图 layer.contents
final class CaptureOverlayView: NSView {
    var onCancel: (() -> Void)?
    var onAreaSelected: ((CGImage, CGFloat, CaptureFinishAction) -> Void)?
    var onLongAreaSelected: ((CGDirectDisplayID, CGRect, CGRect, CGFloat) -> Void)?
    var onWindowSelected: ((CGWindowID) -> Void)?
    var onRecordAreaConfirmed: ((CGRect) -> Void)?

    private enum Handle: CaseIterable {
        case n, s, e, w, ne, nw, se, sw

        var cursor: NSCursor {
            switch self {
            case .n, .s: return .resizeUpDown
            case .e, .w: return .resizeLeftRight
            case .ne, .sw: return .crosshair
            case .nw, .se: return .crosshair
            }
        }
    }

    private enum DragSession {
        case create(start: CGPoint)
        case move(startRect: CGRect, anchor: CGPoint)
        case resize(handle: Handle, startRect: CGRect, anchor: CGPoint)
    }

    private let captured: CapturedFrame
    private let mode: CaptureMode
    private let windows: [WindowCapturer.WindowInfo]

    private var isAreaLike: Bool { mode == .area || mode == .longArea || mode == .recordArea }

    private var dragSession: DragSession?
    private var frozenSelection: CGRect?
    private var hoverWindow: WindowCapturer.WindowInfo?
    /// 双击吸附到系统窗口时，按窗口圆角裁切；手动画的矩形保持直角
    private var clipCropAsWindow = false
    private var mouseLocation: CGPoint = .zero
    private var tracking: NSTrackingArea?
    private var didComplete = false
    private var lastOverlayDraw = Date.distantPast
    private var actionBar: NSView?
    private var hoverHandle: Handle?

    /// 就地标注：在选区内直接画，不跳独立编辑器
    private var isAnnotating = false
    private var annotateDocument: AnnotationDocument?
    private var annotateCanvas: AnnotationCanvasView?
    private var annotateBar: NSView?

    /// 选区已冻结时：按下后未拖动 → 单击进编辑；拖动则移动选区
    private var pendingSelectionTap: (anchor: CGPoint, startRect: CGRect)?
    private var selectionTapMoved = false

    private let dim: CGFloat = 0.48
    /// 选区描边固定高对比色（不跟主题 accent，避免墨黑主题白底白字）
    private let accent = NSColor(calibratedRed: 0.32, green: 0.62, blue: 1.0, alpha: 1)
    private let handleHit: CGFloat = 10

    init(frame: NSRect, captured: CapturedFrame, mode: CaptureMode, windows: [WindowCapturer.WindowInfo]) {
        self.captured = captured
        self.mode = mode
        self.windows = windows
        super.init(frame: frame)
        wantsLayer = true
        layer?.backgroundColor = NSColor.clear.cgColor
    }

    required init?(coder: NSCoder) { fatalError() }

    override var acceptsFirstResponder: Bool { true }
    override var isOpaque: Bool { false }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        window?.makeFirstResponder(self)
        updateTracking()
        NSCursor.crosshair.set()
    }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        updateTracking()
    }

    private func updateTracking() {
        if let tracking { removeTrackingArea(tracking) }
        let options: NSTrackingArea.Options = [.activeAlways, .mouseMoved, .mouseEnteredAndExited, .inVisibleRect, .cursorUpdate]
        let area = NSTrackingArea(rect: bounds, options: options, owner: self, userInfo: nil)
        addTrackingArea(area)
        tracking = area
    }

    override func cursorUpdate(with event: NSEvent) {
        updateCursor(at: convert(event.locationInWindow, from: nil))
    }

    // MARK: - Drawing

    override func draw(_ dirtyRect: NSRect) {
        let selection = activeSelectionRect()
        let path = NSBezierPath(rect: bounds)
        if let selection {
            path.append(NSBezierPath(rect: selection))
            path.windingRule = .evenOdd
        }
        NSColor.black.withAlphaComponent(dim).setFill()
        path.fill()

        if let selection {
            accent.setStroke()
            let border = NSBezierPath(rect: selection)
            border.lineWidth = 2
            border.stroke()
            drawSizeLabel(for: selection)
            drawHandles(in: selection)
        }

        if mode == .window, let hover = hoverWindow {
            drawWindowHighlight(hover)
        } else if isAreaLike, frozenSelection == nil, dragSession == nil, let hover = hoverWindow {
            drawWindowHighlight(hover)
            drawHint("双击识别窗口")
        }

        if (mode == .area || mode == .longArea), AppSettings.shared.showMagnifier, frozenSelection == nil, dragSession == nil {
            drawMagnifier(at: mouseLocation)
        }
    }

    private func drawSizeLabel(for rect: CGRect) {
        let w = Int(rect.width.rounded())
        let h = Int(rect.height.rounded())
        let text = "\(w) × \(h)"
        let attrs: [NSAttributedString.Key: Any] = [
            .font: NSFont.monospacedDigitSystemFont(ofSize: 12, weight: .semibold),
            .foregroundColor: NSColor.white
        ]
        let size = (text as NSString).size(withAttributes: attrs)
        var labelRect = CGRect(x: rect.midX - size.width / 2 - 8, y: rect.minY - size.height - 18, width: size.width + 16, height: size.height + 8)
        if labelRect.minY < 8 { labelRect.origin.y = rect.maxY + 8 }
        NSColor.black.withAlphaComponent(0.72).setFill()
        NSBezierPath(roundedRect: labelRect, xRadius: 6, yRadius: 6).fill()
        accent.withAlphaComponent(0.9).setStroke()
        let border = NSBezierPath(roundedRect: labelRect, xRadius: 6, yRadius: 6)
        border.lineWidth = 1
        border.stroke()
        (text as NSString).draw(at: CGPoint(x: labelRect.minX + 8, y: labelRect.minY + 4), withAttributes: attrs)
    }

    private func drawHandles(in rect: CGRect) {
        NSColor.white.setFill()
        accent.setStroke()
        for handle in Handle.allCases {
            let p = handlePoint(handle, in: rect)
            let r = CGRect(x: p.x - 4, y: p.y - 4, width: 8, height: 8)
            let path = NSBezierPath(ovalIn: r)
            path.fill()
            path.lineWidth = 1.5
            path.stroke()
        }
    }

    private func handlePoint(_ handle: Handle, in rect: CGRect) -> CGPoint {
        switch handle {
        case .n:  return CGPoint(x: rect.midX, y: rect.maxY)
        case .s:  return CGPoint(x: rect.midX, y: rect.minY)
        case .e:  return CGPoint(x: rect.maxX, y: rect.midY)
        case .w:  return CGPoint(x: rect.minX, y: rect.midY)
        case .ne: return CGPoint(x: rect.maxX, y: rect.maxY)
        case .nw: return CGPoint(x: rect.minX, y: rect.maxY)
        case .se: return CGPoint(x: rect.maxX, y: rect.minY)
        case .sw: return CGPoint(x: rect.minX, y: rect.minY)
        }
    }

    private func drawWindowHighlight(_ hover: WindowCapturer.WindowInfo) {
        let local = convertFromScreenTopLeft(hover.bounds).intersection(bounds)
        guard local.width > 4, local.height > 4 else { return }
        let r = min(WindowCornerClipper.systemDefaultRadiusPoints(), min(local.width, local.height) / 4)
        accent.withAlphaComponent(0.18).setFill()
        NSBezierPath(roundedRect: local, xRadius: r, yRadius: r).fill()
        accent.setStroke()
        let p = NSBezierPath(roundedRect: local, xRadius: r, yRadius: r)
        p.lineWidth = 2
        p.stroke()
        let label = "\(hover.owner)\(hover.name.isEmpty ? "" : " — \(hover.name)")"
        drawBadge(label, near: local)
    }

    private func drawHint(_ text: String) {
        let attrs: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 12, weight: .medium),
            .foregroundColor: NSColor.white
        ]
        let size = (text as NSString).size(withAttributes: attrs)
        let rect = CGRect(
            x: bounds.midX - size.width / 2 - 10,
            y: 18,
            width: size.width + 20,
            height: size.height + 10
        )
        NSColor.black.withAlphaComponent(0.62).setFill()
        NSBezierPath(roundedRect: rect, xRadius: 8, yRadius: 8).fill()
        (text as NSString).draw(at: CGPoint(x: rect.minX + 10, y: rect.minY + 5), withAttributes: attrs)
    }

    private func drawBadge(_ text: String, near rect: CGRect) {
        let attrs: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 12, weight: .medium),
            .foregroundColor: NSColor.white
        ]
        let size = (text as NSString).size(withAttributes: attrs)
        let badge = CGRect(x: rect.minX, y: min(rect.maxY + 8, bounds.maxY - size.height - 16), width: size.width + 16, height: size.height + 8)
        NSColor.black.withAlphaComponent(0.7).setFill()
        NSBezierPath(roundedRect: badge, xRadius: 6, yRadius: 6).fill()
        (text as NSString).draw(at: CGPoint(x: badge.minX + 8, y: badge.minY + 4), withAttributes: attrs)
    }

    private func drawMagnifier(at point: CGPoint) {
        guard bounds.contains(point) else { return }
        let zoom: CGFloat = 10
        let size: CGFloat = 120
        let sample: CGFloat = size / zoom

        var origin = CGPoint(x: point.x + 24, y: point.y + 24)
        if origin.x + size > bounds.maxX { origin.x = point.x - size - 24 }
        if origin.y + size > bounds.maxY { origin.y = point.y - size - 24 }

        let magnifierRect = CGRect(origin: origin, size: CGSize(width: size, height: size))

        NSGraphicsContext.saveGraphicsState()
        NSBezierPath(ovalIn: magnifierRect).addClip()
        if let cropped = sampleImage(around: point, samplePoints: sample) {
            NSImage(cgImage: cropped, size: magnifierRect.size).draw(in: magnifierRect)
        }
        NSGraphicsContext.restoreGraphicsState()

        NSColor.white.setStroke()
        let ring = NSBezierPath(ovalIn: magnifierRect)
        ring.lineWidth = 2
        ring.stroke()

        if let color = colorAt(point) {
            let hex = color.hexString
            let attrs: [NSAttributedString.Key: Any] = [
                .font: NSFont.monospacedSystemFont(ofSize: 11, weight: .medium),
                .foregroundColor: contrastingTextColor(for: color)
            ]
            let labelSize = (hex as NSString).size(withAttributes: attrs)
            let labelRect = CGRect(x: magnifierRect.midX - labelSize.width / 2 - 6, y: magnifierRect.minY - 26, width: labelSize.width + 12, height: 20)
            color.setFill()
            NSBezierPath(roundedRect: labelRect, xRadius: 4, yRadius: 4).fill()
            (hex as NSString).draw(at: CGPoint(x: labelRect.minX + 6, y: labelRect.minY + 4), withAttributes: attrs)
        }
    }

    private func sampleImage(around point: CGPoint, samplePoints: CGFloat) -> CGImage? {
        let scale = captured.scale
        let px = point.x * scale
        let py = (bounds.height - point.y) * scale
        let half = (samplePoints * scale) / 2
        var crop = CGRect(x: px - half, y: py - half, width: half * 2, height: half * 2).integral
        crop = crop.intersection(CGRect(x: 0, y: 0, width: captured.image.width, height: captured.image.height))
        guard crop.width > 2, crop.height > 2 else { return nil }
        return captured.image.cropping(to: crop)
    }

    private func contrastingTextColor(for color: NSColor) -> NSColor {
        guard let rgb = color.usingColorSpace(.sRGB) else { return .white }
        let luma = 0.299 * rgb.redComponent + 0.587 * rgb.greenComponent + 0.114 * rgb.blueComponent
        return luma > 0.6 ? .black : .white
    }

    private func colorAt(_ point: CGPoint) -> NSColor? {
        let scale = captured.scale
        let x = Int((point.x * scale).rounded())
        let y = Int(((bounds.height - point.y) * scale).rounded())
        let cg = captured.image
        guard x >= 0, y >= 0, x < cg.width, y < cg.height,
              let data = cg.dataProvider?.data,
              let ptr = CFDataGetBytePtr(data) else { return nil }

        let bpp = max(cg.bitsPerPixel / 8, 1)
        let row = cg.bytesPerRow
        let idx = y * row + x * bpp
        guard idx + 2 < CFDataGetLength(data) else { return nil }

        let b = CGFloat(ptr[idx]) / 255
        let g = CGFloat(ptr[idx + 1]) / 255
        let r = CGFloat(ptr[idx + 2]) / 255
        return NSColor(calibratedRed: r, green: g, blue: b, alpha: 1)
    }

    // MARK: - Selection geometry

    private func activeSelectionRect() -> CGRect? {
        if let frozen = frozenSelection { return frozen }
        if case .create(let start) = dragSession, let current = optionalDragCurrent {
            return normalizedRect(start, current)
        }
        return nil
    }

    private var optionalDragCurrent: CGPoint? {
        if case .create = dragSession { return mouseLocation }
        return nil
    }

    private func normalizedRect(_ a: CGPoint, _ b: CGPoint) -> CGRect {
        CGRect(
            x: min(a.x, b.x),
            y: min(a.y, b.y),
            width: abs(b.x - a.x),
            height: abs(b.y - a.y)
        )
    }

    private func hitHandle(at point: CGPoint, in rect: CGRect) -> Handle? {
        for handle in Handle.allCases {
            let p = handlePoint(handle, in: rect)
            if hypot(point.x - p.x, point.y - p.y) <= handleHit { return handle }
        }
        return nil
    }

    private func resizedRect(handle: Handle, start: CGRect, to point: CGPoint) -> CGRect {
        var minX = start.minX, maxX = start.maxX
        var minY = start.minY, maxY = start.maxY
        switch handle {
        case .n:  maxY = point.y
        case .s:  minY = point.y
        case .e:  maxX = point.x
        case .w:  minX = point.x
        case .ne: maxX = point.x; maxY = point.y
        case .nw: minX = point.x; maxY = point.y
        case .se: maxX = point.x; minY = point.y
        case .sw: minX = point.x; minY = point.y
        }
        var rect = CGRect(x: min(minX, maxX), y: min(minY, maxY), width: abs(maxX - minX), height: abs(maxY - minY))
        rect = clampSelection(rect)
        if rect.width < 4 { rect.size.width = 4 }
        if rect.height < 4 { rect.size.height = 4 }
        return rect
    }

    private func clampSelection(_ rect: CGRect) -> CGRect {
        var r = rect
        r.origin.x = min(max(0, r.origin.x), bounds.width - 4)
        r.origin.y = min(max(0, r.origin.y), bounds.height - 4)
        r.size.width = min(r.width, bounds.width - r.origin.x)
        r.size.height = min(r.height, bounds.height - r.origin.y)
        return r
    }

    private func convertFromScreenTopLeft(_ quartzRect: CGRect) -> CGRect {
        let screenHeight = NSScreen.screens.map { $0.frame.maxY }.max() ?? 0
        let appKitRect = CGRect(
            x: quartzRect.origin.x,
            y: screenHeight - quartzRect.origin.y - quartzRect.height,
            width: quartzRect.width,
            height: quartzRect.height
        )
        guard let window else { return .zero }
        let localOrigin = window.convertPoint(fromScreen: appKitRect.origin)
        return CGRect(origin: localOrigin, size: appKitRect.size)
    }

    private func requestOverlayRedraw(force: Bool = false) {
        let now = Date()
        if !force, dragSession == nil, now.timeIntervalSince(lastOverlayDraw) < 0.033 { return }
        lastOverlayDraw = now
        needsDisplay = true
    }

    private func updateCursor(at point: CGPoint) {
        if let frozen = frozenSelection {
            if let handle = hitHandle(at: point, in: frozen) {
                hoverHandle = handle
                handle.cursor.set()
                return
            }
            if frozen.contains(point) {
                hoverHandle = nil
                NSCursor.openHand.set()
                return
            }
        }
        hoverHandle = nil
        NSCursor.crosshair.set()
    }

    // MARK: - Mouse

    override func mouseMoved(with event: NSEvent) {
        mouseLocation = convert(event.locationInWindow, from: nil)
        if mode == .window || isAreaLike { updateHoverWindow(at: mouseLocation) }
        updateCursor(at: mouseLocation)
        requestOverlayRedraw()
    }

    override func mouseDown(with event: NSEvent) {
        let point = convert(event.locationInWindow, from: nil)
        mouseLocation = point
        if mode == .window {
            if let hover = hoverWindow, !didComplete {
                didComplete = true
                onWindowSelected?(hover.id)
            }
            return
        }

        // 选区：双击复制完成；三击打开编辑器；无选区双击吸附窗口
        if isAreaLike, event.clickCount >= 2 {
            pendingSelectionTap = nil
            selectionTapMoved = false
            if let frozen = frozenSelection,
               frozen.width > 24, frozen.height > 24,
               frozen.insetBy(dx: -6, dy: -6).contains(point) {
                if mode == .recordArea { commitRecordArea() }
                else if mode == .longArea { commitLongSelection() }
                else if event.clickCount >= 3 {
                    commitSelection(.editor)
                } else {
                    commitSelection(.clipboard)
                }
                return
            }
            if snapSelectionToWindow(at: point) { return }
        }

        if isAnnotating { return }

        if let frozen = frozenSelection {
            if let handle = hitHandle(at: point, in: frozen) {
                pendingSelectionTap = nil
                hideActionBar()
                dragSession = .resize(handle: handle, startRect: frozen, anchor: point)
                clipCropAsWindow = false
                return
            }
            if frozen.contains(point) {
                // 按下预备：拖动则移动选区；单击不触发完成
                pendingSelectionTap = (anchor: point, startRect: frozen)
                selectionTapMoved = false
                hideActionBar()
                return
            }
        }

        pendingSelectionTap = nil
        hideActionBar()
        frozenSelection = nil
        clipCropAsWindow = false
        dragSession = .create(start: point)
        needsDisplay = true
    }

    override func mouseDragged(with event: NSEvent) {
        guard isAreaLike, !isAnnotating else { return }
        let point = convert(event.locationInWindow, from: nil)
        mouseLocation = point

        if let pending = pendingSelectionTap, dragSession == nil {
            let dx = point.x - pending.anchor.x
            let dy = point.y - pending.anchor.y
            if hypot(dx, dy) > 4 {
                selectionTapMoved = true
                dragSession = .move(startRect: pending.startRect, anchor: pending.anchor)
                clipCropAsWindow = false
                pendingSelectionTap = nil
                NSCursor.closedHand.set()
            } else {
                return
            }
        }

        switch dragSession {
        case .create:
            needsDisplay = true
        case .move(let startRect, let anchor):
            var next = startRect.offsetBy(dx: point.x - anchor.x, dy: point.y - anchor.y)
            next.origin.x = min(max(0, next.origin.x), bounds.width - next.width)
            next.origin.y = min(max(0, next.origin.y), bounds.height - next.height)
            frozenSelection = next
            needsDisplay = true
        case .resize(let handle, let startRect, _):
            frozenSelection = resizedRect(handle: handle, start: startRect, to: point)
            needsDisplay = true
        case .none:
            break
        }
    }

    override func mouseUp(with event: NSEvent) {
        guard isAreaLike, !didComplete, !isAnnotating else { return }
        let point = convert(event.locationInWindow, from: nil)
        mouseLocation = point

        // 选区上单击：仅恢复工具栏（双击复制 / 三击编辑）
        if pendingSelectionTap != nil {
            pendingSelectionTap = nil
            selectionTapMoved = false
            if let rect = frozenSelection, rect.width > 4, rect.height > 4 {
                showActionBar(near: rect)
            }
            updateCursor(at: point)
            return
        }

        switch dragSession {
        case .create(let start):
            let rect = normalizedRect(start, point)
            dragSession = nil
            guard rect.width > 4, rect.height > 4 else {
                // 无选区时单击：尝试吸附当前悬停窗口
                if mode == .area, hypot(point.x - start.x, point.y - start.y) < 4,
                   snapSelectionToWindow(at: point) {
                    return
                }
                frozenSelection = nil
                needsDisplay = true
                return
            }
            frozenSelection = clampSelection(rect)
            needsDisplay = true
            showActionBar(near: frozenSelection!)
        case .move, .resize:
            dragSession = nil
            if let rect = frozenSelection, rect.width > 4, rect.height > 4 {
                frozenSelection = clampSelection(rect)
                needsDisplay = true
                showActionBar(near: frozenSelection!)
            } else {
                frozenSelection = nil
                needsDisplay = true
            }
            updateCursor(at: point)
        case .none:
            break
        }
    }

    override func mouseEntered(with event: NSEvent) {
        updateCursor(at: convert(event.locationInWindow, from: nil))
    }

    // MARK: - Keyboard

    override func keyDown(with event: NSEvent) {
        if event.keyCode == 53 { // Esc
            if isAnnotating {
                exitInlineAnnotate(keepSelection: true)
                return
            }
            // 有选区时 Esc 直接退出截图（重选请用工具栏「重选」）
            hideActionBar()
            hideAnnotateBar()
            onCancel?()
            return
        }

        if isAnnotating {
            // 标注模式下仍支持导出快捷键（画布未处理时由这里兜底）
            let chars = event.charactersIgnoringModifiers ?? ""
            if event.modifierFlags.contains(.command) {
                switch chars {
                case "c": finishInlineAnnotate(.clipboard); return
                case "s": finishInlineAnnotate(.save); return
                case "p": finishInlineAnnotate(.pin); return
                case "z":
                    if event.modifierFlags.contains(.shift) {
                        annotateDocument?.redo()
                    } else {
                        annotateDocument?.undo()
                    }
                    annotateCanvas?.needsDisplay = true
                    return
                default: break
                }
            }
            if event.keyCode == 36 || event.keyCode == 76 {
                finishInlineAnnotate(.from(after: AppSettings.shared.afterCaptureAction))
                return
            }
            return
        }

        // 方向键微调选区
        if frozenSelection != nil, [123, 124, 125, 126].contains(event.keyCode) {
            nudgeSelection(keyCode: event.keyCode, large: event.modifierFlags.contains(.shift))
            return
        }

        if frozenSelection != nil, mode == .area {
            let chars = event.charactersIgnoringModifiers ?? ""
            if event.modifierFlags.contains(.command) {
                switch chars {
                case "c": commitSelection(.clipboard); return
                case "s": commitSelection(.save); return
                case "e":
                    if event.modifierFlags.contains(.shift) {
                        commitSelection(.editor)
                    } else {
                        enterInlineAnnotate()
                    }
                    return
                case "p": commitSelection(.pin); return
                case "t": commitSelection(.ocr); return
                default: break
                }
            }
        }

        // Return / keypad Enter / Space
        if event.keyCode == 36 || event.keyCode == 76 || event.keyCode == 49 {
            if mode == .recordArea {
                commitRecordArea()
            } else if mode == .longArea {
                commitLongSelection()
            } else if mode == .area, AppSettings.shared.afterCaptureAction == .editor {
                enterInlineAnnotate()
            } else {
                commitSelection(.useSettings)
            }
            return
        }

        // 无选区时 ⌘C 仍可复制取色
        if frozenSelection == nil,
           event.modifierFlags.contains(.command),
           event.charactersIgnoringModifiers == "c",
           let color = colorAt(mouseLocation) {
            NSPasteboard.general.clearContents()
            NSPasteboard.general.setString(color.hexString, forType: .string)
            ToastController.shared.show("已复制 \(color.hexString)")
            return
        }
        super.keyDown(with: event)
    }

    private func nudgeSelection(keyCode: UInt16, large: Bool) {
        guard var rect = frozenSelection else { return }
        let step: CGFloat = large ? 10 : 1
        switch keyCode {
        case 123: rect.origin.x -= step
        case 124: rect.origin.x += step
        case 125: rect.origin.y -= step
        case 126: rect.origin.y += step
        default: break
        }
        rect.origin.x = min(max(0, rect.origin.x), bounds.width - rect.width)
        rect.origin.y = min(max(0, rect.origin.y), bounds.height - rect.height)
        frozenSelection = rect
        needsDisplay = true
        if frozenSelection != nil {
            showActionBar(near: frozenSelection!)
        }
    }

    // MARK: - Commit

    private func commitRecordArea() {
        guard !didComplete, let rect = frozenSelection ?? activeSelectionRect(), rect.width > 4, rect.height > 4 else { return }
        hideActionBar()
        didComplete = true
        onRecordAreaConfirmed?(rect)
    }

    private func commitLongSelection() {
        guard !didComplete,
              let rect = frozenSelection ?? activeSelectionRect(),
              rect.width > 4,
              rect.height > 4
        else { return }
        hideActionBar()
        didComplete = true
        // 把“选择框”交给上层：上层负责自动滚动与拼接
        onLongAreaSelected?(captured.displayID, captured.bounds, rect, captured.scale)
    }

    private func commitSelection(_ action: CaptureFinishAction) {
        guard !didComplete, let rect = frozenSelection ?? activeSelectionRect(), rect.width > 4, rect.height > 4 else { return }
        hideActionBar()
        if let cropped = cropSelection(rect) {
            didComplete = true
            onAreaSelected?(cropped, captured.scale, action)
        }
    }

    // MARK: - Action bar

    private func showActionBar(near rect: CGRect) {
        hideActionBar()

        let bar = NSStackView()
        bar.orientation = .horizontal
        bar.spacing = 6
        bar.edgeInsets = NSEdgeInsets(top: 8, left: 10, bottom: 8, right: 10)
        bar.wantsLayer = true
        bar.layer?.backgroundColor = NSColor.black.withAlphaComponent(0.82).cgColor
        bar.layer?.cornerRadius = 12
        bar.layer?.borderWidth = 1
        bar.layer?.borderColor = NSColor.white.withAlphaComponent(0.16).cgColor
        if #available(macOS 10.15, *) {
            bar.layer?.cornerCurve = .continuous
        }

        if mode == .recordArea {
            let start = makeBarButton(title: "开始录屏", glyph: .record, primary: true) { [weak self] in
                self?.commitRecordArea()
            }
            start.toolTip = "录制当前选区（双击选区 / 回车）"
            bar.addArrangedSubview(start)

            addBarDivider(to: bar)

            let again = makeBarButton(title: "重选", glyph: nil, primary: false) { [weak self] in
                self?.barReselect()
            }
            again.toolTip = "清除选区重新框选"
            bar.addArrangedSubview(again)

            let cancel = makeBarButton(title: "取消", glyph: .close, primary: false) { [weak self] in
                self?.barCancel()
            }
            cancel.toolTip = "退出 (Esc)"
            bar.addArrangedSubview(cancel)
        } else if mode == .longArea {
            let start = makeBarButton(title: "开始长截图", glyph: .screen, primary: true) { [weak self] in
                self?.commitLongSelection()
            }
            start.toolTip = "自动滚动拼接（双击选区 / 回车）；尽量框网页内容"
            bar.addArrangedSubview(start)

            let cancel = makeBarButton(title: "取消", glyph: .close, primary: false) { [weak self] in
                self?.barCancel()
            }
            cancel.toolTip = "退出 (Esc)"
            bar.addArrangedSubview(cancel)

            addBarDivider(to: bar)

            let again = makeBarButton(title: "重选", glyph: nil, primary: false) { [weak self] in
                self?.barReselect()
            }
            again.toolTip = "清除选区重新框选"
            bar.addArrangedSubview(again)

        } else {
        let preferred = AppSettings.shared.afterCaptureAction

        let annotate = makeBarButton(title: "标注", glyph: .edit, primary: preferred == .editor) { [weak self] in
            self?.enterInlineAnnotate()
        }
        annotate.toolTip = "选区内快速标注（⌘E）"
        bar.addArrangedSubview(annotate)

        let editor = makeBarButton(title: "编辑器", glyph: .edit, primary: false) { [weak self] in
            self?.commitSelection(.editor)
        }
        editor.toolTip = "打开完整编辑窗口（⌘⇧E）"
        bar.addArrangedSubview(editor)

        addBarDivider(to: bar)

        let items: [(String, SnapGlyph, CaptureFinishAction, String)] = [
            ("复制", .copy, .clipboard, "复制到剪贴板（双击选区 / ⌘C）"),
            ("保存", .save, .save, "保存到文件 (⌘S)"),
            ("钉住", .pin, .pin, "钉在屏幕上 (⌘P)"),
            ("OCR", .ocr, .ocr, "识别文字并保存 TXT (⌘T)")
        ]

        for (title, glyph, action, tip) in items {
            let primary = (action == .clipboard && preferred == .clipboard)
                || (action == .save && preferred == .save)
                || (action == .pin && preferred == .pin)
            let button = makeBarButton(title: title, glyph: glyph, primary: primary) { [weak self] in
                self?.commitSelection(action)
            }
            button.toolTip = tip
            bar.addArrangedSubview(button)
        }

        addBarDivider(to: bar)

        let again = makeBarButton(title: "重选", glyph: nil, primary: false) { [weak self] in
            self?.barReselect()
        }
        again.toolTip = "清除选区重新框选"
        bar.addArrangedSubview(again)

        let cancel = makeBarButton(title: "取消", glyph: .close, primary: false) { [weak self] in
            self?.barCancel()
        }
        cancel.toolTip = "退出截图 (Esc)"
        bar.addArrangedSubview(cancel)
        }

        bar.translatesAutoresizingMaskIntoConstraints = false
        addSubview(bar)
        bar.layoutSubtreeIfNeeded()
        let size = bar.fittingSize
        let barSize = NSSize(width: ceil(size.width), height: max(44, ceil(size.height)))
        bar.setFrameSize(barSize)

        var origin = NSPoint(x: rect.midX - barSize.width / 2, y: rect.maxY + 12)
        if origin.y + barSize.height > bounds.maxY - 12 {
            origin.y = rect.minY - barSize.height - 12
        }
        origin.x = min(max(12, origin.x), bounds.maxX - barSize.width - 12)
        origin.y = min(max(12, origin.y), bounds.maxY - barSize.height - 12)
        bar.setFrameOrigin(origin)
        actionBar = bar
    }

    private func addBarDivider(to bar: NSStackView) {
        let divider = NSView(frame: NSRect(x: 0, y: 0, width: 1, height: 22))
        divider.wantsLayer = true
        divider.layer?.backgroundColor = NSColor.white.withAlphaComponent(0.18).cgColor
        divider.translatesAutoresizingMaskIntoConstraints = false
        divider.widthAnchor.constraint(equalToConstant: 1).isActive = true
        divider.heightAnchor.constraint(equalToConstant: 22).isActive = true
        bar.addArrangedSubview(divider)
    }

    private func hideActionBar() {
        actionBar?.removeFromSuperview()
        actionBar = nil
    }

    private func makeBarButton(title: String, glyph: SnapGlyph?, primary: Bool, compact: Bool = false, handler: @escaping () -> Void) -> NSButton {
        let b = ClosureButton(title: title, handler: handler)
        b.bezelStyle = .inline
        b.isBordered = false
        b.wantsLayer = true
        b.translatesAutoresizingMaskIntoConstraints = false
        b.layer?.cornerRadius = compact ? 6 : 8
        if #available(macOS 10.15, *) {
            b.layer?.cornerCurve = .continuous
        }
        b.layer?.backgroundColor = (primary ? NSColor.white : NSColor.white.withAlphaComponent(0.10)).cgColor
        b.contentTintColor = primary ? NSColor.black.withAlphaComponent(0.88) : .white
        b.font = .systemFont(ofSize: compact ? 11 : 12, weight: .semibold)
        let iconSize: CGFloat = compact ? 10 : 11
        if let glyph, let img = FlareBrand.menuSymbol(glyph, pointSize: iconSize) {
            b.image = img
            b.imagePosition = .imageLeading
            b.imageHugsTitle = true
        }
        let width: CGFloat
        let height: CGFloat
        if compact {
            width = title.count >= 3 ? 56 : (title.count >= 2 ? 48 : 40)
            height = 24
        } else {
            width = title.count >= 3 ? 72 : (title == "OCR" ? 58 : (title.count >= 2 ? 64 : 52))
            height = 28
        }
        NSLayoutConstraint.activate([
            b.widthAnchor.constraint(equalToConstant: width),
            b.heightAnchor.constraint(equalToConstant: height)
        ])
        return b
    }

    private func makeAnnotateToolButton(tool: AnnotationTool, selected: Bool, handler: @escaping () -> Void) -> NSButton {
        let isText = tool == .text
        let b = ClosureButton(title: isText ? "文字" : "", handler: handler)
        b.bezelStyle = .inline
        b.isBordered = false
        b.wantsLayer = true
        b.translatesAutoresizingMaskIntoConstraints = false
        b.layer?.cornerRadius = 6
        if #available(macOS 10.15, *) {
            b.layer?.cornerCurve = .continuous
        }
        b.layer?.backgroundColor = (selected ? NSColor.white : NSColor.white.withAlphaComponent(0.10)).cgColor
        b.contentTintColor = selected ? NSColor.black.withAlphaComponent(0.88) : .white
        if isText {
            b.font = .systemFont(ofSize: 10, weight: .semibold)
            b.image = nil
            b.imagePosition = .noImage
        } else {
            b.image = FlareBrand.menuSymbol(tool.glyph, pointSize: 12)
            b.imagePosition = .imageOnly
        }
        NSLayoutConstraint.activate([
            b.widthAnchor.constraint(equalToConstant: isText ? 36 : 28),
            b.heightAnchor.constraint(equalToConstant: 28)
        ])
        return b
    }

    private func barReselect() {
        exitInlineAnnotate(keepSelection: false)
        hideActionBar()
        frozenSelection = nil
        clipCropAsWindow = false
        dragSession = nil
        needsDisplay = true
        NSCursor.crosshair.set()
    }

    private func barCancel() {
        exitInlineAnnotate(keepSelection: false)
        hideActionBar()
        onCancel?()
    }

    // MARK: - Inline annotate

    private func enterInlineAnnotate() {
        guard !didComplete, !isAnnotating, mode == .area,
              let rect = frozenSelection, rect.width > 8, rect.height > 8,
              let cropped = cropSelection(rect)
        else { return }

        hideActionBar()
        isAnnotating = true
        dragSession = nil

        let base = ImageExporter.nsImage(from: cropped, scale: captured.scale)
        let doc = AnnotationDocument(image: base)
        doc.tool = .arrow
        annotateDocument = doc

        let canvas = AnnotationCanvasView(frame: rect)
        canvas.autoresizingMask = []
        canvas.document = doc
        canvas.wantsLayer = true
        canvas.layer?.cornerRadius = 2
        canvas.layer?.masksToBounds = true
        canvas.onEscape = { [weak self] in
            self?.exitInlineAnnotate(keepSelection: true)
        }
        addSubview(canvas)
        annotateCanvas = canvas
        window?.makeFirstResponder(canvas)

        showAnnotateBar(near: rect)
        needsDisplay = true
        ToastController.shared.show("选区内标注 · 单击选文字 · Esc 返回")
    }

    private func exitInlineAnnotate(keepSelection: Bool) {
        annotateCanvas?.removeFromSuperview()
        annotateCanvas = nil
        annotateDocument = nil
        hideAnnotateBar()
        isAnnotating = false
        if keepSelection, let rect = frozenSelection {
            showActionBar(near: rect)
            window?.makeFirstResponder(self)
        } else if !keepSelection {
            frozenSelection = nil
        }
        needsDisplay = true
        NSCursor.crosshair.set()
    }

    private func showAnnotateBar(near rect: CGRect) {
        hideAnnotateBar()

        let bar = NSStackView()
        bar.orientation = .horizontal
        bar.spacing = 4
        bar.edgeInsets = NSEdgeInsets(top: 6, left: 8, bottom: 6, right: 8)
        bar.wantsLayer = true
        bar.layer?.backgroundColor = NSColor.black.withAlphaComponent(0.86).cgColor
        bar.layer?.cornerRadius = 12
        bar.layer?.borderWidth = 1
        bar.layer?.borderColor = NSColor.white.withAlphaComponent(0.16).cgColor
        if #available(macOS 10.15, *) {
            bar.layer?.cornerCurve = .continuous
        }

        let tools: [(AnnotationTool, String)] = [
            (.select, "选择并调节箭头/形状"),
            (.arrow, "箭头"),
            (.pen, "画笔"),
            (.highlight, "高亮"),
            (.rect, "矩形"),
            (.ellipse, "椭圆"),
            (.line, "直线"),
            (.blur, "马赛克"),
            (.number, "序号"),
            (.step, "步骤编号"),
            (.text, "文字")
        ]
        for (tool, tip) in tools {
            let primary = tool == (annotateDocument?.tool ?? .arrow)
            let button = makeAnnotateToolButton(tool: tool, selected: primary) { [weak self] in
                self?.annotateDocument?.tool = tool
                if let r = self?.frozenSelection {
                    self?.showAnnotateBar(near: r)
                }
                self?.annotateCanvas?.needsDisplay = true
                self?.window?.makeFirstResponder(self?.annotateCanvas)
            }
            button.toolTip = tip
            bar.addArrangedSubview(button)
        }

        for color in AnnotationStyle.palette {
            let swatch = ClosureButton(title: "") { [weak self] in
                self?.annotateDocument?.setColor(color)
                self?.annotateCanvas?.needsDisplay = true
            }
            swatch.bezelStyle = .inline
            swatch.isBordered = false
            swatch.wantsLayer = true
            swatch.layer?.backgroundColor = color.cgColor
            swatch.layer?.cornerRadius = 6
            swatch.layer?.borderWidth = 1
            swatch.layer?.borderColor = NSColor.white.withAlphaComponent(0.35).cgColor
            swatch.toolTip = color.hexString
            swatch.translatesAutoresizingMaskIntoConstraints = false
            NSLayoutConstraint.activate([
                swatch.widthAnchor.constraint(equalToConstant: 12),
                swatch.heightAnchor.constraint(equalToConstant: 12)
            ])
            bar.addArrangedSubview(swatch)
        }

        let widthSlider = ClosureSlider(value: Double(annotateDocument?.style.lineWidth ?? 3), min: 1, max: 20) { [weak self] value in
            self?.annotateDocument?.setLineWidth(CGFloat(value))
            self?.annotateCanvas?.needsDisplay = true
        }
        widthSlider.toolTip = "画笔 / 箭头粗细"
        widthSlider.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            widthSlider.widthAnchor.constraint(equalToConstant: 56),
            widthSlider.heightAnchor.constraint(equalToConstant: 16)
        ])
        bar.addArrangedSubview(widthSlider)

        addBarDivider(to: bar)

        let undo = makeBarButton(title: "撤销", glyph: nil, primary: false, compact: true) { [weak self] in
            self?.annotateDocument?.undo()
            self?.annotateCanvas?.needsDisplay = true
        }
        undo.toolTip = "撤销 (⌘Z)"
        bar.addArrangedSubview(undo)

        let redo = makeBarButton(title: "重做", glyph: nil, primary: false, compact: true) { [weak self] in
            self?.annotateDocument?.redo()
            self?.annotateCanvas?.needsDisplay = true
        }
        redo.toolTip = "重做 (⌘⇧Z)"
        bar.addArrangedSubview(redo)

        addBarDivider(to: bar)

        let preferred = AppSettings.shared.afterCaptureAction
        let copy = makeBarButton(title: "复制", glyph: .copy, primary: preferred == .clipboard, compact: true) { [weak self] in
            self?.finishInlineAnnotate(.clipboard)
        }
        copy.toolTip = "复制标注结果 (⌘C)"
        bar.addArrangedSubview(copy)

        let save = makeBarButton(title: "保存", glyph: .save, primary: preferred == .save, compact: true) { [weak self] in
            self?.finishInlineAnnotate(.save)
        }
        save.toolTip = "保存到文件 (⌘S)"
        bar.addArrangedSubview(save)

        let pin = makeBarButton(title: "钉住", glyph: .pin, primary: preferred == .pin, compact: true) { [weak self] in
            self?.finishInlineAnnotate(.pin)
        }
        pin.toolTip = "钉在屏幕上 (⌘P)"
        bar.addArrangedSubview(pin)

        let editor = makeBarButton(title: "编辑器", glyph: .edit, primary: preferred == .editor, compact: true) { [weak self] in
            self?.finishInlineAnnotate(.editor)
        }
        editor.toolTip = "打开完整编辑窗口"
        bar.addArrangedSubview(editor)

        let done = makeBarButton(title: "完成", glyph: .success, primary: false, compact: true) { [weak self] in
            self?.finishInlineAnnotate(.from(after: AppSettings.shared.afterCaptureAction))
        }
        done.toolTip = "按设置默认动作完成（回车）"
        bar.addArrangedSubview(done)

        bar.translatesAutoresizingMaskIntoConstraints = false
        addSubview(bar)
        bar.layoutSubtreeIfNeeded()
        let size = bar.fittingSize
        let barSize = NSSize(width: ceil(size.width), height: max(36, ceil(size.height)))
        bar.setFrameSize(barSize)

        var origin = NSPoint(x: rect.midX - barSize.width / 2, y: rect.maxY + 12)
        if origin.y + barSize.height > bounds.maxY - 12 {
            origin.y = rect.minY - barSize.height - 12
        }
        origin.x = min(max(12, origin.x), bounds.maxX - barSize.width - 12)
        origin.y = min(max(12, origin.y), bounds.maxY - barSize.height - 12)
        bar.setFrameOrigin(origin)
        annotateBar = bar
    }

    private func hideAnnotateBar() {
        annotateBar?.removeFromSuperview()
        annotateBar = nil
    }

    private func finishInlineAnnotate(_ action: CaptureFinishAction) {
        guard !didComplete, let doc = annotateDocument else { return }
        let rendered = doc.renderedImage()
        guard let cg = rendered.cgImage(
            forProposedRect: nil,
            context: nil,
            hints: nil
        ) else { return }

        let scale: CGFloat = {
            let w = rendered.size.width
            guard w > 0 else { return captured.scale }
            return CGFloat(cg.width) / w
        }()

        hideAnnotateBar()
        annotateCanvas?.removeFromSuperview()
        annotateCanvas = nil
        annotateDocument = nil
        isAnnotating = false
        didComplete = true
        onAreaSelected?(cg, scale, action)
    }

    private func snapSelectionToWindow(at point: CGPoint) -> Bool {
        updateHoverWindow(at: point)
        guard let hover = hoverWindow else { return false }
        var local = convertFromScreenTopLeft(hover.bounds).intersection(bounds)
        local = clampSelection(local)
        guard local.width > 8, local.height > 8 else { return false }
        hideActionBar()
        dragSession = nil
        frozenSelection = local
        clipCropAsWindow = true
        needsDisplay = true
        showActionBar(near: local)
        updateCursor(at: point)
        return true
    }

    private func updateHoverWindow(at point: CGPoint) {
        guard let window else { return }
        let screenPoint = window.convertPoint(toScreen: point)
        let screenHeight = NSScreen.screens.map { $0.frame.maxY }.max() ?? 0
        let quartzPoint = CGPoint(x: screenPoint.x, y: screenHeight - screenPoint.y)
        hoverWindow = windows.first { $0.bounds.contains(quartzPoint) }
    }

    private func cropSelection(_ rect: CGRect) -> CGImage? {
        let scale = captured.scale
        var crop = CGRect(
            x: rect.origin.x * scale,
            y: (bounds.height - rect.origin.y - rect.height) * scale,
            width: rect.width * scale,
            height: rect.height * scale
        ).integral
        crop = crop.intersection(CGRect(x: 0, y: 0, width: captured.image.width, height: captured.image.height))
        guard crop.width > 1, crop.height > 1 else { return nil }
        guard let image = captured.image.cropping(to: crop) else { return nil }
        if clipCropAsWindow || mode == .window {
            return WindowCornerClipper.roundIfNeeded(image, scale: scale)
        }
        return image
    }
}

/// 轻量闭包按钮，避免为每个工具栏动作建 @objc 方法
private final class ClosureButton: NSButton {
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

private final class ClosureSlider: NSSlider {
    private let onChange: (Double) -> Void

    init(value: Double, min: Double, max: Double, onChange: @escaping (Double) -> Void) {
        self.onChange = onChange
        super.init(frame: .zero)
        minValue = min
        maxValue = max
        doubleValue = value
        target = self
        action = #selector(changed)
        controlSize = .small
        isContinuous = true
    }

    required init?(coder: NSCoder) { fatalError() }

    @objc private func changed() { onChange(doubleValue) }
}

extension NSColor {
    var hexString: String {
        guard let rgb = usingColorSpace(.sRGB) else { return "#000000" }
        let r = Int((rgb.redComponent * 255).rounded())
        let g = Int((rgb.greenComponent * 255).rounded())
        let b = Int((rgb.blueComponent * 255).rounded())
        return String(format: "#%02X%02X%02X", r, g, b)
    }
}
