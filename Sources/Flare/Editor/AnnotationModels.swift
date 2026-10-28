import AppKit
import Combine
import CoreImage

enum AnnotationTool: String, CaseIterable, Identifiable {
    case select
    case pen
    case highlight
    case arrow
    case line
    case rect
    case ellipse
    case text
    case blur
    case number
    case step

    var id: String { rawValue }

    var title: String {
        switch self {
        case .select: return L("选择")
        case .pen: return L("画笔")
        case .highlight: return L("高亮")
        case .arrow: return L("箭头")
        case .line: return L("划线")
        case .rect: return L("矩形")
        case .ellipse: return L("椭圆")
        case .text: return L("文字")
        case .blur: return L("打码")
        case .number: return L("序号")
        case .step: return L("步骤")
        }
    }

    var glyph: SnapGlyph {
        switch self {
        case .select: return .toolSelect
        case .pen: return .toolPen
        case .highlight: return .toolHighlight
        case .arrow: return .toolArrow
        case .line: return .toolLine
        case .rect: return .toolRect
        case .ellipse: return .toolEllipse
        case .text: return .toolText
        case .blur: return .toolBlur
        case .number: return .toolNumber
        case .step: return .toolStep
        }
    }
}

struct AnnotationStyle: Equatable {
    var color: NSColor = NSColor(calibratedRed: 1, green: 0.23, blue: 0.19, alpha: 1)
    var lineWidth: CGFloat = 3
    var fontSize: CGFloat = 18

    static let palette: [NSColor] = [
        NSColor(calibratedRed: 1, green: 0.23, blue: 0.19, alpha: 1),
        NSColor(calibratedRed: 1, green: 0.58, blue: 0, alpha: 1),
        NSColor(calibratedRed: 1, green: 0.80, blue: 0, alpha: 1),
        NSColor(calibratedRed: 0.20, green: 0.78, blue: 0.35, alpha: 1),
        NSColor(calibratedRed: 0.10, green: 0.68, blue: 0.97, alpha: 1),
        NSColor(calibratedWhite: 0.92, alpha: 1),
        NSColor(calibratedWhite: 0.45, alpha: 1),
        NSColor.black
    ]
}

enum AnnotationHit {
    case body
    case start
    case end
}

enum RedactKind: String, CaseIterable, Identifiable {
    case mosaic
    case frost
    case black
    case bar

    var id: String { rawValue }

    var title: String {
        switch self {
        case .mosaic: return L("马赛克")
        case .frost: return L("模糊")
        case .black: return L("涂黑")
        case .bar: return L("黑条")
        }
    }
}

enum AnnotationItem: Identifiable {
    case freehand(id: UUID, points: [CGPoint], style: AnnotationStyle, highlight: Bool)
    case shape(id: UUID, kind: ShapeKind, start: CGPoint, end: CGPoint, style: AnnotationStyle)
    case text(id: UUID, text: String, origin: CGPoint, style: AnnotationStyle)
    case blur(id: UUID, rect: CGRect, kind: RedactKind)
    case counter(id: UUID, center: CGPoint, value: Int, style: AnnotationStyle)

    enum ShapeKind { case arrow, line, rect, ellipse }

    var id: UUID {
        switch self {
        case .freehand(let id, _, _, _),
             .shape(let id, _, _, _, _),
             .text(let id, _, _, _),
             .blur(let id, _, _),
             .counter(let id, _, _, _):
            return id
        }
    }

    func applying(_ style: AnnotationStyle) -> AnnotationItem {
        switch self {
        case .freehand(let id, let points, _, let highlight):
            return .freehand(id: id, points: points, style: style, highlight: highlight)
        case .shape(let id, let kind, let start, let end, _):
            return .shape(id: id, kind: kind, start: start, end: end, style: style)
        case .text(let id, let text, let origin, _):
            return .text(id: id, text: text, origin: origin, style: style)
        case .counter(let id, let center, let value, _):
            return .counter(id: id, center: center, value: value, style: style)
        case .blur:
            return self
        }
    }

    func translated(by delta: CGPoint) -> AnnotationItem {
        func moved(_ pt: CGPoint) -> CGPoint { CGPoint(x: pt.x + delta.x, y: pt.y + delta.y) }
        switch self {
        case .freehand(let id, let points, let style, let highlight):
            return .freehand(id: id, points: points.map(moved), style: style, highlight: highlight)
        case .shape(let id, let kind, let start, let end, let style):
            return .shape(id: id, kind: kind, start: moved(start), end: moved(end), style: style)
        case .text(let id, let text, let origin, let style):
            return .text(id: id, text: text, origin: moved(origin), style: style)
        case .blur(let id, let rect, let kind):
            return .blur(id: id, rect: rect.offsetBy(dx: delta.x, dy: delta.y), kind: kind)
        case .counter(let id, let center, let value, let style):
            return .counter(id: id, center: moved(center), value: value, style: style)
        }
    }

    func hitTest(_ point: CGPoint, threshold: CGFloat = 10) -> AnnotationHit? {
        switch self {
        case .freehand(_, let points, let style, let highlight):
            guard points.count > 1 else { return nil }
            let t = max(threshold, (highlight ? style.lineWidth * 4 : style.lineWidth) / 2 + 4)
            for i in 1..<points.count {
                if AnnotationItem.distance(point, points[i - 1], points[i]) <= t { return .body }
            }
            return nil
        case .shape(_, let kind, let start, let end, let style):
            if hypot(point.x - start.x, point.y - start.y) <= 12 { return .start }
            if hypot(point.x - end.x, point.y - end.y) <= 12 { return .end }
            let t = max(threshold, style.lineWidth / 2 + 4)
            switch kind {
            case .arrow, .line:
                return AnnotationItem.distance(point, start, end) <= t ? .body : nil
            case .rect, .ellipse:
                let rect = CGRect(
                    x: min(start.x, end.x), y: min(start.y, end.y),
                    width: abs(end.x - start.x), height: abs(end.y - start.y)
                ).insetBy(dx: -t, dy: -t)
                return rect.contains(point) ? .body : nil
            }
        case .text(_, let text, let origin, let style):
            let attrs: [NSAttributedString.Key: Any] = [
                .font: NSFont.systemFont(ofSize: style.fontSize, weight: .semibold)
            ]
            let size = (text as NSString).size(withAttributes: attrs)
            return CGRect(origin: origin, size: size).insetBy(dx: -6, dy: -6).contains(point) ? .body : nil
        case .blur(_, let rect, _):
            return rect.insetBy(dx: -4, dy: -4).contains(point) ? .body : nil
        case .counter(_, let center, _, _):
            return hypot(point.x - center.x, point.y - center.y) <= 18 ? .body : nil
        }
    }

    private static func distance(_ p: CGPoint, _ a: CGPoint, _ b: CGPoint) -> CGFloat {
        let dx = b.x - a.x, dy = b.y - a.y
        let len2 = dx * dx + dy * dy
        if len2 < 1 { return hypot(p.x - a.x, p.y - a.y) }
        var t = ((p.x - a.x) * dx + (p.y - a.y) * dy) / len2
        t = min(1, max(0, t))
        return hypot(p.x - (a.x + t * dx), p.y - (a.y + t * dy))
    }
}

final class AnnotationDocument: ObservableObject {
    let baseImage: NSImage
    @Published var items: [AnnotationItem] = []
    @Published var tool: AnnotationTool = .line
    @Published var style = AnnotationStyle()
    @Published var redactKind: RedactKind
    @Published var selectedID: UUID?
    @Published private(set) var counterValue = 1

    private var undoStack: [[AnnotationItem]] = []
    private var redoStack: [[AnnotationItem]] = []

    init(image: NSImage) {
        self.baseImage = image
        self.redactKind = AppSettings.shared.redactKind
    }

    func pushUndo() {
        undoStack.append(items)
        redoStack.removeAll()
    }

    func undo() {
        guard let previous = undoStack.popLast() else { return }
        redoStack.append(items)
        items = previous
    }

    func redo() {
        guard let next = redoStack.popLast() else { return }
        undoStack.append(items)
        items = next
    }

    func clear() {
        pushUndo()
        items.removeAll()
        counterValue = 1
    }

    func add(_ item: AnnotationItem) {
        pushUndo()
        items.append(item)
        selectedID = item.id
        if case .counter = item {
            counterValue += 1
        }
    }

    func setColor(_ color: NSColor) {
        style.color = color
        applyStyleToSelected()
    }

    func setLineWidth(_ width: CGFloat) {
        style.lineWidth = max(1, min(20, width))
        applyStyleToSelected()
    }

    func setFontSize(_ size: CGFloat) {
        style.fontSize = max(10, min(48, size))
        applyStyleToSelected()
    }

    func setRedactKind(_ kind: RedactKind) {
        redactKind = kind
        AppSettings.shared.redactKind = kind
        guard let id = selectedID, let idx = items.firstIndex(where: { $0.id == id }) else { return }
        if case .blur(let bid, let rect, _) = items[idx] {
            items[idx] = .blur(id: bid, rect: rect, kind: kind)
        }
    }

    func applyStyleToSelected() {
        guard let id = selectedID, let idx = items.firstIndex(where: { $0.id == id }) else { return }
        items[idx] = items[idx].applying(style)
    }

    func replace(_ item: AnnotationItem) {
        guard let idx = items.firstIndex(where: { $0.id == item.id }) else { return }
        items[idx] = item
    }

    func deleteSelected() {
        guard let id = selectedID else { return }
        pushUndo()
        items.removeAll { $0.id == id }
        selectedID = nil
    }

    func item(at point: CGPoint) -> (AnnotationItem, AnnotationHit)? {
        for item in items.reversed() {
            if let hit = item.hitTest(point) {
                return (item, hit)
            }
        }
        return nil
    }

    func updateLastFreehand(points: [CGPoint]) {
        guard let last = items.last, case .freehand(let id, _, let style, let highlight) = last else { return }
        items[items.count - 1] = .freehand(id: id, points: points, style: style, highlight: highlight)
    }

    func beginFreehand(at point: CGPoint, highlight: Bool) {
        pushUndo()
        items.append(.freehand(id: UUID(), points: [point], style: style, highlight: highlight))
    }

    func renderedImage() -> NSImage {
        let size = baseImage.size
        let nativeScale: CGFloat = {
            if let cg = baseImage.cgImage(forProposedRect: nil, context: nil, hints: nil) {
                return max(CGFloat(cg.width) / max(size.width, 1), 1)
            }
            if let rep = baseImage.representations.max(by: { $0.pixelsWide < $1.pixelsWide }),
               rep.pixelsWide > 0 {
                return max(CGFloat(rep.pixelsWide) / max(size.width, 1), 1)
            }
            return NSScreen.main?.backingScaleFactor ?? 2
        }()
        let pixelW = max(Int((size.width * nativeScale).rounded()), 1)
        let pixelH = max(Int((size.height * nativeScale).rounded()), 1)
        guard let rep = NSBitmapImageRep(
            bitmapDataPlanes: nil,
            pixelsWide: pixelW,
            pixelsHigh: pixelH,
            bitsPerSample: 8,
            samplesPerPixel: 4,
            hasAlpha: true,
            isPlanar: false,
            colorSpaceName: .deviceRGB,
            bytesPerRow: 0,
            bitsPerPixel: 0
        ) else {
            let image = NSImage(size: size)
            image.lockFocus()
            baseImage.draw(in: CGRect(origin: .zero, size: size))
            AnnotationRenderer.draw(items: items, in: CGRect(origin: .zero, size: size), baseImage: baseImage)
            image.unlockFocus()
            return image
        }
        rep.size = size
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
        baseImage.draw(in: CGRect(origin: .zero, size: size))
        AnnotationRenderer.draw(items: items, in: CGRect(origin: .zero, size: size), baseImage: baseImage)
        NSGraphicsContext.restoreGraphicsState()
        let image = NSImage(size: size)
        image.addRepresentation(rep)
        return image
    }
}

enum AnnotationRenderer {
    static func draw(items: [AnnotationItem], in bounds: CGRect, baseImage: NSImage) {
        for item in items {
            switch item {
            case .freehand(_, let points, let style, let highlight):
                guard points.count > 1 else { continue }
                let path = NSBezierPath()
                path.move(to: points[0])
                for p in points.dropFirst() { path.line(to: p) }
                path.lineJoinStyle = .round
                path.lineCapStyle = .round
                path.lineWidth = highlight ? style.lineWidth * 4 : style.lineWidth
                let color = highlight ? style.color.withAlphaComponent(0.35) : style.color
                color.setStroke()
                path.stroke()

            case .shape(_, let kind, let start, let end, let style):
                style.color.setStroke()
                style.color.withAlphaComponent(0.15).setFill()
                switch kind {
                case .line:
                    let p = NSBezierPath()
                    p.move(to: start)
                    p.line(to: end)
                    p.lineWidth = style.lineWidth
                    p.stroke()
                case .arrow:
                    drawArrow(from: start, to: end, style: style)
                case .rect:
                    let rect = CGRect(x: min(start.x, end.x), y: min(start.y, end.y),
                                      width: abs(end.x - start.x), height: abs(end.y - start.y))
                    let p = NSBezierPath(roundedRect: rect, xRadius: 2, yRadius: 2)
                    p.lineWidth = style.lineWidth
                    p.fill()
                    p.stroke()
                case .ellipse:
                    let rect = CGRect(x: min(start.x, end.x), y: min(start.y, end.y),
                                      width: abs(end.x - start.x), height: abs(end.y - start.y))
                    let p = NSBezierPath(ovalIn: rect)
                    p.lineWidth = style.lineWidth
                    p.fill()
                    p.stroke()
                }

            case .text(_, let text, let origin, let style):
                let attrs: [NSAttributedString.Key: Any] = [
                    .font: NSFont.systemFont(ofSize: style.fontSize, weight: .semibold),
                    .foregroundColor: style.color
                ]
                (text as NSString).draw(at: origin, withAttributes: attrs)

            case .blur(_, let rect, let kind):
                drawRedact(baseImage: baseImage, rect: rect, kind: kind)

            case .counter(_, let center, let value, let style):
                let r: CGFloat = 14
                let circle = CGRect(x: center.x - r, y: center.y - r, width: r * 2, height: r * 2)
                style.color.setFill()
                NSBezierPath(ovalIn: circle).fill()
                let attrs: [NSAttributedString.Key: Any] = [
                    .font: NSFont.boldSystemFont(ofSize: 14),
                    .foregroundColor: NSColor.white
                ]
                let s = "\(value)" as NSString
                let size = s.size(withAttributes: attrs)
                s.draw(at: CGPoint(x: center.x - size.width / 2, y: center.y - size.height / 2), withAttributes: attrs)
            }
        }
    }

    private static func drawArrow(from start: CGPoint, to end: CGPoint, style: AnnotationStyle) {
        let path = NSBezierPath()
        path.move(to: start)
        path.line(to: end)
        path.lineWidth = style.lineWidth
        path.lineCapStyle = .round
        style.color.setStroke()
        path.stroke()

        let angle = atan2(end.y - start.y, end.x - start.x)
        let head: CGFloat = 12 + style.lineWidth
        let a1 = angle + .pi * 0.8
        let a2 = angle - .pi * 0.8
        let headPath = NSBezierPath()
        headPath.move(to: end)
        headPath.line(to: CGPoint(x: end.x + cos(a1) * head, y: end.y + sin(a1) * head))
        headPath.line(to: CGPoint(x: end.x + cos(a2) * head, y: end.y + sin(a2) * head))
        headPath.close()
        style.color.setFill()
        headPath.fill()
    }

    static func drawSelection(for item: AnnotationItem) {
        NSColor.white.setStroke()
        NSColor.systemBlue.setFill()
        switch item {
        case .shape(_, let kind, let start, let end, _):
            switch kind {
            case .arrow, .line:
                handle(at: start)
                handle(at: end)
            case .rect, .ellipse:
                let rect = CGRect(
                    x: min(start.x, end.x), y: min(start.y, end.y),
                    width: abs(end.x - start.x), height: abs(end.y - start.y)
                )
                let outline = NSBezierPath(rect: rect)
                outline.lineWidth = 1
                outline.setLineDash([4, 3], count: 2, phase: 0)
                NSColor.systemBlue.withAlphaComponent(0.9).setStroke()
                outline.stroke()
                handle(at: start)
                handle(at: end)
            }
        case .freehand(_, let points, _, _):
            if let first = points.first { handle(at: first) }
            if let last = points.last, points.count > 1 { handle(at: last) }
        case .text(_, let text, let origin, let style):
            let attrs: [NSAttributedString.Key: Any] = [
                .font: NSFont.systemFont(ofSize: style.fontSize, weight: .semibold)
            ]
            let size = (text as NSString).size(withAttributes: attrs)
            let outline = NSBezierPath(rect: CGRect(origin: origin, size: size).insetBy(dx: -3, dy: -2))
            outline.lineWidth = 1
            NSColor.systemBlue.withAlphaComponent(0.9).setStroke()
            outline.stroke()
        case .blur(_, let rect, _):
            let outline = NSBezierPath(rect: rect)
            outline.lineWidth = 1
            outline.setLineDash([4, 3], count: 2, phase: 0)
            NSColor.systemBlue.setStroke()
            outline.stroke()
        case .counter(_, let center, _, _):
            handle(at: center)
        }
    }

    private static func handle(at point: CGPoint) {
        let r = CGRect(x: point.x - 5, y: point.y - 5, width: 10, height: 10)
        NSColor.white.setFill()
        NSBezierPath(ovalIn: r).fill()
        NSColor.systemBlue.setStroke()
        let ring = NSBezierPath(ovalIn: r.insetBy(dx: 0.5, dy: 0.5))
        ring.lineWidth = 1.5
        ring.stroke()
    }

    private static let ciContext = CIContext(options: [.useSoftwareRenderer: false])

    private static func drawRedact(baseImage: NSImage, rect: CGRect, kind: RedactKind) {
        guard rect.width > 1, rect.height > 1 else { return }
        let path = NSBezierPath(roundedRect: rect, xRadius: 3, yRadius: 3)
        NSGraphicsContext.saveGraphicsState()
        path.addClip()
        switch kind {
        case .mosaic:
            drawPixelate(baseImage: baseImage, rect: rect)
        case .frost:
            drawFrost(baseImage: baseImage, rect: rect)
        case .black:
            NSColor.black.withAlphaComponent(0.92).setFill()
            path.fill()
        case .bar:
            NSColor.black.setFill()
            let bar = rect.insetBy(dx: 0, dy: max(0, (rect.height - max(14, rect.height * 0.38)) / 2))
            NSBezierPath(roundedRect: bar, xRadius: min(6, bar.height / 2), yRadius: min(6, bar.height / 2)).fill()
        }
        NSGraphicsContext.restoreGraphicsState()
    }

    private static func drawPixelate(baseImage: NSImage, rect: CGRect) {
        let shortest = min(rect.width, rect.height)
        let block = max(16, min(28, (shortest / 5).rounded(.down)))
        var y = rect.minY
        while y < rect.maxY {
            var x = rect.minX
            while x < rect.maxX {
                let sample = CGRect(x: x, y: y, width: min(block, rect.maxX - x), height: min(block, rect.maxY - y))
                let color = averageColor(of: baseImage, in: sample) ?? .gray
                color.setFill()
                NSBezierPath(rect: sample).fill()
                x += block
            }
            y += block
        }
        NSColor.black.withAlphaComponent(0.12).setFill()
        NSBezierPath(rect: rect).fill()
    }

    private static func drawFrost(baseImage: NSImage, rect: CGRect) {
        guard let cg = baseImage.cgImage(forProposedRect: nil, context: nil, hints: nil) else {
            NSColor.white.withAlphaComponent(0.35).setFill()
            NSBezierPath(rect: rect).fill()
            return
        }
        let scaleX = CGFloat(cg.width) / max(baseImage.size.width, 1)
        let scaleY = CGFloat(cg.height) / max(baseImage.size.height, 1)
        var crop = CGRect(
            x: rect.minX * scaleX,
            y: (baseImage.size.height - rect.maxY) * scaleY,
            width: rect.width * scaleX,
            height: rect.height * scaleY
        ).integral
        crop = crop.intersection(CGRect(x: 0, y: 0, width: cg.width, height: cg.height))
        guard crop.width > 2, crop.height > 2, let piece = cg.cropping(to: crop) else { return }
        let input = CIImage(cgImage: piece)
        let radius = max(10, min(crop.width, crop.height) * 0.16)
        let blurred = input.clampedToExtent()
            .applyingGaussianBlur(sigma: radius)
            .cropped(to: input.extent)
        guard let out = ciContext.createCGImage(blurred, from: blurred.extent) else { return }
        let image = NSImage(cgImage: out, size: rect.size)
        image.draw(in: rect, from: CGRect(origin: .zero, size: image.size), operation: .copy, fraction: 1)
        NSColor.white.withAlphaComponent(0.08).setFill()
        NSBezierPath(rect: rect).fill()
    }

    private static func averageColor(of image: NSImage, in rect: CGRect) -> NSColor? {
        guard let cg = image.cgImage(forProposedRect: nil, context: nil, hints: nil) else { return nil }
        let scaleX = CGFloat(cg.width) / image.size.width
        let scaleY = CGFloat(cg.height) / image.size.height
        let crop = CGRect(
            x: rect.origin.x * scaleX,
            y: (image.size.height - rect.origin.y - rect.height) * scaleY,
            width: rect.width * scaleX,
            height: rect.height * scaleY
        ).integral
        guard let piece = cg.cropping(to: crop) else { return nil }
        let rep = NSBitmapImageRep(cgImage: piece)
        rep.size = NSSize(width: 1, height: 1)
        return rep.colorAt(x: 0, y: 0)
    }
}
