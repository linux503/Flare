import AppKit
import Combine

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
        case .select: return "选择"
        case .pen: return "画笔"
        case .highlight: return "高亮"
        case .arrow: return "箭头"
        case .line: return "直线"
        case .rect: return "矩形"
        case .ellipse: return "椭圆"
        case .text: return "文字"
        case .blur: return "马赛克"
        case .number: return "序号"
        case .step: return "步骤"
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
}

enum AnnotationItem: Identifiable {
    case freehand(id: UUID, points: [CGPoint], style: AnnotationStyle, highlight: Bool)
    case shape(id: UUID, kind: ShapeKind, start: CGPoint, end: CGPoint, style: AnnotationStyle)
    case text(id: UUID, text: String, origin: CGPoint, style: AnnotationStyle)
    case blur(id: UUID, rect: CGRect)
    case counter(id: UUID, center: CGPoint, value: Int, style: AnnotationStyle)

    enum ShapeKind { case arrow, line, rect, ellipse }

    var id: UUID {
        switch self {
        case .freehand(let id, _, _, _),
             .shape(let id, _, _, _, _),
             .text(let id, _, _, _),
             .blur(let id, _),
             .counter(let id, _, _, _):
            return id
        }
    }
}

final class AnnotationDocument: ObservableObject {
    let baseImage: NSImage
    @Published var items: [AnnotationItem] = []
    @Published var tool: AnnotationTool = .arrow
    @Published var style = AnnotationStyle()
    @Published var selectedID: UUID?
    @Published private(set) var counterValue = 1

    private var undoStack: [[AnnotationItem]] = []
    private var redoStack: [[AnnotationItem]] = []

    init(image: NSImage) {
        self.baseImage = image
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
        if case .counter = item {
            counterValue += 1
        }
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
        let pixelW = max(Int(size.width * 2), 1)
        let pixelH = max(Int(size.height * 2), 1)
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

            case .blur(_, let rect):
                drawPixelate(baseImage: baseImage, rect: rect)

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

    private static func drawPixelate(baseImage: NSImage, rect: CGRect) {
        guard rect.width > 1, rect.height > 1 else { return }
        let block: CGFloat = 10
        NSGraphicsContext.saveGraphicsState()
        NSBezierPath(rect: rect).addClip()

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
        NSGraphicsContext.restoreGraphicsState()
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
