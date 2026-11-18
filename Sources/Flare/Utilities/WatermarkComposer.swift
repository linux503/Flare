import AppKit
import CoreImage
import CoreVideo

/// 截图 / 录屏右下角高级玻璃水印：磨砂底、香槟金描边、品牌标 + 自定义字标。
enum ScreenshotWatermark {
    static let gold = NSColor(calibratedRed: 0.86, green: 0.72, blue: 0.46, alpha: 1)
    static let goldSoft = NSColor(calibratedRed: 0.86, green: 0.72, blue: 0.46, alpha: 0.55)

    private static let ciContext = CIContext(options: [.useSoftwareRenderer: false])

    static func applyIfNeeded(_ image: NSImage) -> NSImage {
        guard AppSettings.shared.watermarkEnabled else { return image }
        return stamped(image)
    }

    static func stamped(_ image: NSImage, date: Date = Date()) -> NSImage {
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
        drawChrome(in: bounds, source: image, sourceFrame: bounds, date: date, frosted: true)
        NSGraphicsContext.restoreGraphicsState()
        let out = NSImage(size: size)
        out.addRepresentation(rep)
        return out
    }

    /// 在当前图形上下文里画预览（选区 / 编辑器画布），坐标原点左下。
    static func drawPreview(in rect: CGRect, source: NSImage?) {
        guard AppSettings.shared.watermarkEnabled else { return }
        drawConfigured(in: rect, source: source, date: Date(), frosted: true)
    }

    static func drawPreview(in rect: CGRect, sourceCG: CGImage, viewBounds: CGRect) {
        guard AppSettings.shared.watermarkEnabled else { return }
        let ns = NSImage(cgImage: sourceCG, size: viewBounds.size)
        drawConfigured(in: rect, source: ns, sourceFrame: viewBounds, date: Date(), frosted: true)
    }

    /// 设置页预览：不看开关，直接按当前样式绘制。
    static func drawConfigured(
        in rect: CGRect,
        source: NSImage?,
        sourceFrame: CGRect? = nil,
        date: Date = Date(),
        frosted: Bool = true
    ) {
        guard rect.width >= 72, rect.height >= 72 else { return }
        let covered = sourceFrame ?? CGRect(origin: .zero, size: source?.size ?? rect.size)
        drawChrome(in: rect, source: source, sourceFrame: covered, date: date, frosted: frosted)
    }

    /// 录屏用：透明底只含水印徽章的覆盖层（尺寸 = 视频像素尺寸）
    static func overlayImage(pixelWidth: Int, pixelHeight: Int, date: Date) -> CGImage? {
        guard AppSettings.shared.watermarkRecordEnabled else { return nil }
        guard pixelWidth >= 160, pixelHeight >= 120 else { return nil }
        guard let rep = NSBitmapImageRep(
            bitmapDataPlanes: nil,
            pixelsWide: pixelWidth,
            pixelsHigh: pixelHeight,
            bitsPerSample: 8,
            samplesPerPixel: 4,
            hasAlpha: true,
            isPlanar: false,
            colorSpaceName: .deviceRGB,
            bytesPerRow: 0,
            bitsPerPixel: 0
        ) else { return nil }
        let size = NSSize(width: pixelWidth, height: pixelHeight)
        rep.size = size
        NSGraphicsContext.saveGraphicsState()
        guard let ctx = NSGraphicsContext(bitmapImageRep: rep) else {
            NSGraphicsContext.restoreGraphicsState()
            return nil
        }
        NSGraphicsContext.current = ctx
        ctx.imageInterpolation = .high
        ctx.shouldAntialias = true
        let bounds = CGRect(origin: .zero, size: size)
        NSColor.clear.setFill()
        NSBezierPath(rect: bounds).fill()
        drawChrome(in: bounds, source: nil, sourceFrame: bounds, date: date, frosted: false)
        NSGraphicsContext.restoreGraphicsState()
        return rep.cgImage
    }

    /// 把预渲染的水印叠到像素缓冲（尽量用 adaptor 的 pool）
    static func stamp(pixelBuffer: CVPixelBuffer, overlay: CGImage, pool: CVPixelBufferPool?) -> CVPixelBuffer? {
        var out: CVPixelBuffer?
        if let pool {
            CVPixelBufferPoolCreatePixelBuffer(nil, pool, &out)
        }
        if out == nil {
            let w = CVPixelBufferGetWidth(pixelBuffer)
            let h = CVPixelBufferGetHeight(pixelBuffer)
            let attrs: [CFString: Any] = [
                kCVPixelBufferPixelFormatTypeKey: Int(kCVPixelFormatType_32BGRA),
                kCVPixelBufferWidthKey: w,
                kCVPixelBufferHeightKey: h,
                kCVPixelBufferIOSurfacePropertiesKey: [:] as CFDictionary
            ]
            CVPixelBufferCreate(nil, w, h, kCVPixelFormatType_32BGRA, attrs as CFDictionary, &out)
        }
        guard let dest = out else { return nil }
        CVPixelBufferLockBaseAddress(dest, [])
        defer { CVPixelBufferUnlockBaseAddress(dest, []) }
        guard let base = CVPixelBufferGetBaseAddress(dest) else { return nil }
        let width = CVPixelBufferGetWidth(dest)
        let height = CVPixelBufferGetHeight(dest)
        let bytesPerRow = CVPixelBufferGetBytesPerRow(dest)
        guard let colorSpace = CGColorSpace(name: CGColorSpace.sRGB),
              let ctx = CGContext(
                data: base,
                width: width,
                height: height,
                bitsPerComponent: 8,
                bytesPerRow: bytesPerRow,
                space: colorSpace,
                bitmapInfo: CGImageAlphaInfo.premultipliedFirst.rawValue | CGBitmapInfo.byteOrder32Little.rawValue
              ) else { return nil }
        let rect = CGRect(x: 0, y: 0, width: width, height: height)
        let ci = CIImage(cvPixelBuffer: pixelBuffer)
        if let frame = ciContext.createCGImage(ci, from: ci.extent) {
            ctx.draw(frame, in: rect)
        }
        ctx.draw(overlay, in: rect)
        return dest
    }

    // MARK: - Layout

    private static func badgeRect(in rect: CGRect) -> CGRect? {
        let settings = AppSettings.shared
        let minSide = min(rect.width, rect.height)
        guard minSide >= 72 else { return nil }
        let scale = CGFloat(settings.watermarkScale)
        let pad = max(8, minSide * 0.02)
        let height = min(44, max(24, minSide * 0.055)) * scale
        let text = settings.watermarkText
        let showLogo = settings.watermarkShowLogo
        let showDate = settings.watermarkShowDate
        let hasText = !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        guard showLogo || hasText || showDate else { return nil }

        var width = height * (showLogo ? 1.15 : 0.35)
        if hasText {
            let wordSize = max(8, height * 0.27)
            let wordFont = roundedFont(size: wordSize, weight: .semibold)
            let wordW = (text as NSString).size(withAttributes: [.font: wordFont]).width
            width += wordW + height * 0.55
        }
        if showDate && !hasText {
            width += height * 2.4
        }
        width = min(rect.width - pad * 2, max(height * (showLogo && !hasText ? 1.2 : 2.6), width))

        let x: CGFloat
        let y: CGFloat
        switch settings.watermarkPosition {
        case .bottomRight:
            x = rect.maxX - pad - width
            y = rect.minY + pad
        case .bottomLeft:
            x = rect.minX + pad
            y = rect.minY + pad
        case .topRight:
            x = rect.maxX - pad - width
            y = rect.maxY - pad - height
        case .topLeft:
            x = rect.minX + pad
            y = rect.maxY - pad - height
        }
        return CGRect(x: x, y: y, width: width, height: height)
    }

    private static func drawChrome(
        in rect: CGRect,
        source: NSImage?,
        sourceFrame: CGRect?,
        date: Date,
        frosted: Bool
    ) {
        guard let badge = badgeRect(in: rect) else { return }
        let opacity = CGFloat(AppSettings.shared.watermarkOpacity)
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current?.cgContext.setAlpha(opacity)
        drawBadge(badge, source: source, sourceFrame: sourceFrame, date: date, frosted: frosted)
        NSGraphicsContext.restoreGraphicsState()
    }

    private static func drawBadge(
        _ badge: CGRect,
        source: NSImage?,
        sourceFrame: CGRect?,
        date: Date,
        frosted: Bool
    ) {
        let settings = AppSettings.shared
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
        if frosted {
            drawFrost(in: badge, source: source, sourceFrame: sourceFrame)
        } else {
            NSColor.black.withAlphaComponent(0.52).setFill()
            path.fill()
        }
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
        var cursorX = badge.minX + inset * 1.05
        let showLogo = settings.watermarkShowLogo
        let text = settings.watermarkText.trimmingCharacters(in: .whitespacesAndNewlines)
        let showDate = settings.watermarkShowDate

        if showLogo {
            let logoSide = badge.height - inset * 2
            let logoRect = CGRect(
                x: cursorX,
                y: badge.minY + inset,
                width: logoSide,
                height: logoSide
            )
            drawLogo(in: logoRect)
            cursorX = logoRect.maxX + inset * 0.5
            if !text.isEmpty || showDate {
                gold.withAlphaComponent(0.22).setStroke()
                let divider = NSBezierPath()
                divider.move(to: CGPoint(x: cursorX, y: badge.minY + badge.height * 0.26))
                divider.line(to: CGPoint(x: cursorX, y: badge.maxY - badge.height * 0.26))
                divider.lineWidth = 0.5
                divider.stroke()
                cursorX += inset * 0.6
            }
        }

        let textWidth = max(8, badge.maxX - inset - cursorX)
        let wordSize = max(8, badge.height * 0.27)
        let wordFont = roundedFont(size: wordSize, weight: .semibold)
        let word = text.isEmpty ? nil : NSAttributedString(
            string: text,
            attributes: [
                .font: wordFont,
                .foregroundColor: NSColor.white.withAlphaComponent(0.72),
                .kern: max(0.4, wordSize * 0.08)
            ]
        )
        let wordHeight = word?.size().height ?? 0
        let subSize = max(6.5, badge.height * 0.17)
        let subFont = roundedFont(size: subSize, weight: .medium)
        let sub = showDate ? NSAttributedString(
            string: stampDate(date),
            attributes: [
                .font: subFont,
                .foregroundColor: gold.withAlphaComponent(0.55),
                .kern: 0.45
            ]
        ) : nil
        let subHeight = sub?.size().height ?? 0

        if let word, let sub {
            let stack = wordHeight + 1.5 + subHeight
            let textY = badge.midY - stack / 2
            word.draw(in: CGRect(x: cursorX, y: textY + subHeight + 1.5, width: textWidth, height: wordHeight))
            sub.draw(in: CGRect(x: cursorX, y: textY, width: textWidth, height: subHeight))
        } else if let word {
            let textY = badge.midY - wordHeight / 2
            word.draw(in: CGRect(x: cursorX, y: textY, width: textWidth, height: wordHeight))
        } else if let sub {
            let textY = badge.midY - subHeight / 2
            sub.draw(in: CGRect(x: cursorX, y: textY, width: textWidth, height: subHeight))
        }
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

    private static func stampDate(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy.MM.dd  HH:mm"
        return formatter.string(from: date)
    }
}
