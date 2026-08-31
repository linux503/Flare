import AppKit
import CoreGraphics

/// 直角窗口保持直角；圆角窗口按像素识别半径并裁成透明圆角。
enum WindowCornerClipper {
    static func apply(_ image: CGImage, scale: CGFloat, quartzBounds: CGRect) -> CGImage {
        if isEssentiallyFullscreen(quartzBounds) {
            return image
        }
        return roundIfNeeded(image, scale: scale)
    }

    static func roundIfNeeded(_ image: CGImage, scale: CGFloat) -> CGImage {
        let detected = detectRadiusPixels(image)
        let maxR = min(CGFloat(image.width), CGFloat(image.height)) * 0.25
        let minMeaningful = max(3, scale * 1.5)
        guard detected >= minMeaningful else { return image }
        let radius = min(detected, maxR)
        return clipRounded(image, radiusPx: radius) ?? image
    }

    static func systemDefaultRadiusPoints() -> CGFloat {
        let major = ProcessInfo.processInfo.operatingSystemVersion.majorVersion
        if major >= 16 { return 18 }
        if major >= 15 { return 16 }
        return 10
    }

    private static func isEssentiallyFullscreen(_ bounds: CGRect) -> Bool {
        for screen in NSScreen.screens {
            let f = screen.frame
            if abs(f.width - bounds.width) < 2, abs(f.height - bounds.height) < 8 {
                return true
            }
        }
        return false
    }

    /// 返回圆角半径（像素）。直角 / 无法确认时返回 0，绝不强行套默认圆角。
    private static func detectRadiusPixels(_ image: CGImage) -> CGFloat {
        let w = image.width
        let h = image.height
        guard w > 48, h > 48 else { return 0 }
        var buf = [UInt8](repeating: 0, count: w * h * 4)
        guard let ctx = CGContext(
            data: &buf,
            width: w,
            height: h,
            bitsPerComponent: 8,
            bytesPerRow: w * 4,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else { return 0 }
        ctx.draw(image, in: CGRect(x: 0, y: 0, width: w, height: h))

        func pix(_ x: Int, _ y: Int) -> (r: Int, g: Int, b: Int, a: Int) {
            let o = (y * w + x) * 4
            return (Int(buf[o]), Int(buf[o + 1]), Int(buf[o + 2]), Int(buf[o + 3]))
        }
        func diff(_ a: (Int, Int, Int, Int), _ b: (Int, Int, Int, Int)) -> Int {
            abs(a.0 - b.0) + abs(a.1 - b.1) + abs(a.2 - b.2) + abs(a.3 - b.3)
        }

        let inset = min(max(Int((scaleGuess(w, h) * 22).rounded()), 16), min(w, h) / 6)
        let limit = min(w, h) / 5

        /// 位图 y=0 为底。四个角：(x,y) + 指向内部的 (dx,dy)
        let corners: [(Int, Int, Int, Int)] = [
            (0, h - 1, 1, -1),
            (w - 1, h - 1, -1, -1),
            (0, 0, 1, 1),
            (w - 1, 0, -1, 1)
        ]

        var radii: [CGFloat] = []
        var squareVotes = 0

        for (cx, cy, dx, dy) in corners {
            let ix = min(max(cx + dx * inset, 0), w - 1)
            let iy = min(max(cy + dy * inset, 0), h - 1)
            let corner = pix(cx, cy)
            let inside = pix(ix, iy)

            // 透明角：沿两边数透明像素
            if corner.a < 40 {
                let rx = clearRun(buf: buf, w: w, h: h, x: cx, y: cy, dx: dx, dy: 0, limit: limit)
                let ry = clearRun(buf: buf, w: w, h: h, x: cx, y: cy, dx: 0, dy: dy, limit: limit)
                let r = CGFloat(rx + ry) / 2
                if r > 2 { radii.append(r * 1.08) }
                continue
            }

            // 角和内部几乎同色 → 直角（内容铺到边）
            if diff(corner, inside) < 36 {
                squareVotes += 1
                continue
            }

            // 圆角：沿顶/底边走到与内部同色的位置
            var hit = 0
            for i in 1...limit {
                let x = min(max(cx + dx * i, 0), w - 1)
                if diff(pix(x, cy), inside) < 40 {
                    hit = i
                    break
                }
            }
            var hitY = 0
            for i in 1...limit {
                let y = min(max(cy + dy * i, 0), h - 1)
                if diff(pix(cx, y), inside) < 40 {
                    hitY = i
                    break
                }
            }
            let r = CGFloat(max(hit, hitY))
            if r > 3 {
                radii.append(r)
            } else {
                squareVotes += 1
            }
        }

        // 多数角是直角 → 整窗按直角
        if squareVotes >= 3 { return 0 }
        guard radii.count >= 2 else { return 0 }
        radii.sort()
        let median = radii[radii.count / 2]
        // 各角半径差太大，不可靠
        let spread = radii.last! - radii.first!
        if spread > max(median * 0.7, 12) { return median }
        return median
    }

    private static func scaleGuess(_ w: Int, _ h: Int) -> CGFloat {
        // 粗略：大图更可能是 2x
        w >= 2000 || h >= 1200 ? 2 : 1
    }

    private static func clearRun(buf: [UInt8], w: Int, h: Int, x: Int, y: Int, dx: Int, dy: Int, limit: Int) -> Int {
        var n = 0
        var px = x
        var py = y
        while n < limit, px >= 0, py >= 0, px < w, py < h {
            let a = Int(buf[(py * w + px) * 4 + 3])
            if a >= 40 { break }
            n += 1
            px += dx
            py += dy
        }
        return n
    }

    /// 用路径裁切，不用 CALayer.render（后者会忽略 cornerRadius）。
    private static func clipRounded(_ image: CGImage, radiusPx: CGFloat) -> CGImage? {
        let w = image.width
        let h = image.height
        let colorSpace = CGColorSpaceCreateDeviceRGB()
        let bitmapInfo = CGImageAlphaInfo.premultipliedLast.rawValue
        guard let ctx = CGContext(
            data: nil,
            width: w,
            height: h,
            bitsPerComponent: 8,
            bytesPerRow: 0,
            space: colorSpace,
            bitmapInfo: bitmapInfo
        ) else { return nil }

        ctx.clear(CGRect(x: 0, y: 0, width: w, height: h))
        let rect = CGRect(x: 0, y: 0, width: w, height: h)
        ctx.addPath(CGPath(roundedRect: rect, cornerWidth: radiusPx, cornerHeight: radiusPx, transform: nil))
        ctx.clip()
        ctx.draw(image, in: rect)
        return ctx.makeImage()
    }
}
