import AppKit
import CoreImage

/// 截图右下角高级玻璃水印：磨砂底、香槟金描边、品牌标 + 字标。
enum ScreenshotWatermark {
    static let gold = NSColor(calibratedRed: 0.86, green: 0.72, blue: 0.46, alpha: 1)
    static let goldSoft = NSColor(calibratedRed: 0.86, green: 0.72, blue: 0.46, alpha: 0.55)

    private static let ciContext = CIContext(options: [.useSoftwareRenderer: false])

    static func applyIfNeeded(_ image: NSImage) -> NSImage {
        guard AppSettings.shared.watermarkEnabled else { return image }
        return stamped(image)
    }

    static func stamped(_ image: NSImage) -> NSImage {
        let size = image.size
        guard size.width >= 72, size.height >= 72 else { return image }

        let pixelW: Int
        let pixelH: Int
        if let cg = image.cgImage(forProposedRect: nil, context: nil, hints: nil) {
            pixelW = max(cg.width, 1)
            pixelH = max(cg.height, 1)
        } else {
            let scale = NSScreen.main?.backingScaleFactor ?? 2
            pixelW = max(Int((size.width * scale).rounded()), 1)
            pixelH = max(Int((size.height * scale).rounded()), 1)
        }
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
        ) else { return image }
        rep.size = size
        NSGraphicsContext.saveGraphicsState()
        guard let ctx = NSGraphicsContext(bitmapImageRep: rep) else {
            NSGraphicsContext.restoreGraphicsState()
            return image
        }
        NSGraphicsContext.current = ctx
        ctx.imageInterpolation = .high
        ctx.shouldAntialias = true
        let bounds = CGRect(origin: .zero, size: size)
        image.draw(in: bounds, from: bounds, operation: .copy, fraction: 1)
        drawChrome(in: bounds, source: image, sourceFrame: bounds)
        NSGraphicsContext.restoreGraphicsState()
        let out = NSImage(size: size)
        out.addRepresentation(rep)
        return out
    }

    /// 在当前图形上下文里画预览（选区 / 编辑器画布），坐标原点左下。
    static func drawPreview(in rect: CGRect, source: NSImage?) {
        guard AppSettings.shared.watermarkEnabled else { return }
        guard rect.width >= 72, rect.height >= 72 else { return }
        let covered = CGRect(origin: .zero, size: source?.size ?? rect.size)
        drawChrome(in: rect, source: source, sourceFrame: covered)
    }

    static func drawPreview(in rect: CGRect, sourceCG: CGImage, viewBounds: CGRect) {
        guard AppSettings.shared.watermarkEnabled else { return }
        guard rect.width >= 72, rect.height >= 72 else { return }
        let ns = NSImage(cgImage: sourceCG, size: viewBounds.size)
        drawChrome(in: rect, source: ns, sourceFrame: viewBounds)
    }

    // MARK: - Layout

    private static func badgeRect(in rect: CGRect) -> CGRect? {
        let minSide = min(rect.width, rect.height)
        guard minSide >= 72 else { return nil }
        let pad = max(8, minSide * 0.02)
        let height = min(40, max(26, minSide * 0.055))
        let width = min(rect.width - pad * 2, max(height * 3.05, 128))
        return CGRect(
            x: rect.maxX - pad - width,
            y: rect.minY + pad,
            width: width,
            height: height
        )
    }

    private static func drawChrome(in rect: CGRect, source: NSImage?, sourceFrame: CGRect? = nil) {
        guard let badge = badgeRect(in: rect) else { return }
        drawBadge(badge, source: source, sourceFrame: sourceFrame)
    }

    private static func drawBadge(_ badge: CGRect, source: NSImage?, sourceFrame: CGRect?) {
        let radius = badge.height * 0.38
        let path = NSBezierPath(roundedRect: badge, xRadius: radius, yRadius: radius)

        NSGraphicsContext.saveGraphicsState()
        let shadow = NSShadow()
        shadow.shadowColor = NSColor.black.withAlphaComponent(0.10)
        shadow.shadowBlurRadius = max(5, badge.height * 0.16)
        shadow.shadowOffset = NSSize(width: 0, height: -0.4)
        shadow.set()
        NSColor.black.withAlphaComponent(0.01).setFill()
        path.fill()
        NSGraphicsContext.restoreGraphicsState()

        NSGraphicsContext.saveGraphicsState()
        path.addClip()
        drawFrost(in: badge, source: source, sourceFrame: sourceFrame)
        NSColor.white.withAlphaComponent(0.10).setFill()
        path.fill()
        NSColor.black.withAlphaComponent(0.06).setFill()
        path.fill()
        let shine = NSGradient(colorsAndLocations:
            (NSColor.white.withAlphaComponent(0.22), 0),
            (NSColor.white.withAlphaComponent(0.04), 0.46),
            (NSColor.clear, 1)
        )
        let shineRect = CGRect(x: badge.minX, y: badge.midY, width: badge.width, height: badge.height * 0.55)
        shine?.draw(in: shineRect, angle: 270)
        gold.withAlphaComponent(0.10).setFill()
        path.fill()
        NSGraphicsContext.restoreGraphicsState()

        gold.withAlphaComponent(0.28).setStroke()
        path.lineWidth = max(0.55, badge.height * 0.014)
        path.stroke()

        let inset = badge.height * 0.16
        let logoSide = badge.height - inset * 2
        let logoRect = CGRect(
            x: badge.minX + inset * 1.05,
            y: badge.minY + inset,
            width: logoSide,
            height: logoSide
        )
        drawLogo(in: logoRect)

        let dividerX = logoRect.maxX + inset * 0.5
        gold.withAlphaComponent(0.22).setStroke()
        let divider = NSBezierPath()
        divider.move(to: CGPoint(x: dividerX, y: badge.minY + badge.height * 0.26))
        divider.line(to: CGPoint(x: dividerX, y: badge.maxY - badge.height * 0.26))
        divider.lineWidth = 0.5
        divider.stroke()

        let textX = dividerX + inset * 0.6
        let textWidth = max(8, badge.maxX - inset - textX)
        let wordSize = max(8, badge.height * 0.27)
        let wordFont = roundedFont(size: wordSize, weight: .semibold)
        let word = NSAttributedString(
            string: "FLARE PRO",
            attributes: [
                .font: wordFont,
                .foregroundColor: NSColor.white.withAlphaComponent(0.72),
                .kern: max(0.6, wordSize * 0.10)
            ]
        )
        let wordHeight = word.size().height
        let subSize = max(6.5, badge.height * 0.17)
        let subFont = roundedFont(size: subSize, weight: .medium)
        let sub = NSAttributedString(
            string: stampDate(),
            attributes: [
                .font: subFont,
                .foregroundColor: gold.withAlphaComponent(0.55),
                .kern: 0.45
            ]
        )
        let subHeight = sub.size().height
        let stack = wordHeight + 1.5 + subHeight
        let textY = badge.midY - stack / 2
        word.draw(in: CGRect(x: textX, y: textY + subHeight + 1.5, width: textWidth, height: wordHeight))
        sub.draw(in: CGRect(x: textX, y: textY, width: textWidth, height: subHeight))
    }

    private static func drawLogo(in rect: CGRect) {
        let aligned = rect.integral
        let radius = aligned.height * 0.28
        let clip = NSBezierPath(roundedRect: aligned, xRadius: radius, yRadius: radius)
        NSGraphicsContext.saveGraphicsState()
        clip.addClip()
        if let ctx = NSGraphicsContext.current {
            ctx.imageInterpolation = .high
            ctx.shouldAntialias = true
        }
        if let logo = FlareBrand.appMarkImage() {
            logo.draw(
                in: aligned,
                from: CGRect(origin: .zero, size: logo.size),
                operation: .sourceOver,
                fraction: 0.82,
                respectFlipped: true,
                hints: [.interpolation: NSImageInterpolation.high]
            )
        } else {
            NSColor(calibratedWhite: 0.1, alpha: 0.55).setFill()
            clip.fill()
            gold.withAlphaComponent(0.7).setFill()
            let inner = aligned.insetBy(dx: aligned.width * 0.22, dy: aligned.height * 0.22)
            NSBezierPath(ovalIn: inner).fill()
        }
        NSGraphicsContext.restoreGraphicsState()
        gold.withAlphaComponent(0.22).setStroke()
        clip.lineWidth = 0.45
        clip.stroke()
    }

    private static func drawFrost(in badge: CGRect, source: NSImage?, sourceFrame: CGRect?) {
        guard let source else {
            NSColor.black.withAlphaComponent(0.5).setFill()
            NSBezierPath(rect: badge).fill()
            return
        }

        let frame = sourceFrame ?? CGRect(origin: .zero, size: source.size)
        guard frame.width > 1, frame.height > 1 else { return }

        let from = CGRect(
            x: (badge.minX - frame.minX) / frame.width * source.size.width,
            y: (badge.minY - frame.minY) / frame.height * source.size.height,
            width: badge.width / frame.width * source.size.width,
            height: badge.height / frame.height * source.size.height
        )

        if let blurred = blurredPiece(from: source, rect: from) {
            blurred.draw(
                in: badge,
                from: CGRect(origin: .zero, size: blurred.size),
                operation: .copy,
                fraction: 1
            )
        } else {
            source.draw(in: badge, from: from, operation: .copy, fraction: 1)
        }
    }

    private static func blurredPiece(from image: NSImage, rect: CGRect) -> NSImage? {
        guard let cg = image.cgImage(forProposedRect: nil, context: nil, hints: nil) else { return nil }
        let scaleX = CGFloat(cg.width) / max(image.size.width, 1)
        let scaleY = CGFloat(cg.height) / max(image.size.height, 1)
        var crop = CGRect(
            x: rect.minX * scaleX,
            y: (image.size.height - rect.maxY) * scaleY,
            width: rect.width * scaleX,
            height: rect.height * scaleY
        ).integral
        crop = crop.intersection(CGRect(x: 0, y: 0, width: cg.width, height: cg.height))
        guard crop.width > 2, crop.height > 2, let piece = cg.cropping(to: crop) else { return nil }

        let input = CIImage(cgImage: piece)
        let radius = max(12, min(crop.width, crop.height) * 0.22)
        let blurred = input.clampedToExtent()
            .applyingGaussianBlur(sigma: radius)
            .cropped(to: input.extent)
        guard let out = ciContext.createCGImage(blurred, from: blurred.extent) else { return nil }
        return NSImage(cgImage: out, size: NSSize(width: rect.width, height: rect.height))
    }

    private static func roundedFont(size: CGFloat, weight: NSFont.Weight) -> NSFont {
        let base = NSFont.systemFont(ofSize: size, weight: weight)
        if let descriptor = base.fontDescriptor.withDesign(.rounded) {
            return NSFont(descriptor: descriptor, size: size) ?? base
        }
        return base
    }

    private static func stampDate() -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy.MM.dd  HH:mm"
        return formatter.string(from: Date())
    }
}
