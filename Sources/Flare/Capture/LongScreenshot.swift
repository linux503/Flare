import AppKit
import ApplicationServices
import CoreGraphics

/// 长截图：选区自动滚动并拼接成长图。
///
/// 策略（向下滚动）：
/// 1. 点击选区中心聚焦目标窗口（需辅助功能权限）
/// 2. 在选区中心发送滚轮事件
/// 3. 用内容区模板匹配估计滚动位移
/// 4. 只裁切底部「新增」条带拼到上一张下方，避开顶部固定栏
enum LongScreenshot {
    struct Session {
        let displayID: CGDirectDisplayID
        let displayBoundsInPoints: CGRect
        let selectionRectInPoints: CGRect
        let displayScale: CGFloat
    }

    enum Error: LocalizedError, Equatable {
        case cancelled
        case noSegment
        case needsAccessibility

        var errorDescription: String? {
            switch self {
            case .cancelled: return "已取消长截图"
            case .noSegment: return "未能截取到长截图内容"
            case .needsAccessibility: return "长截图需要「辅助功能」权限才能自动滚动"
            }
        }
    }

    private struct Segment {
        let image: CGImage
        /// 相对上一段向下滚动的像素数（新内容高度）
        let freshHeight: Int
        let staticTop: Int
    }

    static func capture(session: Session, maxSegments: Int = 20) async throws -> CGImage {
        try Task.checkCancellation()

        guard ensureAccessibility() else {
            throw Error.needsAccessibility
        }

        let widthPx = max(1, Int((session.selectionRectInPoints.width * session.displayScale).rounded()))
        let heightPx = max(1, Int((session.selectionRectInPoints.height * session.displayScale).rounded()))
        let targetSize = CGSize(width: widthPx, height: heightPx)

        let cancelMonitor = EscCancelMonitor()
        defer { cancelMonitor.stop() }

        let focusPoint = CGPoint(
            x: session.displayBoundsInPoints.minX + session.selectionRectInPoints.midX,
            y: session.displayBoundsInPoints.minY + session.selectionRectInPoints.midY
        )

        // 等遮罩消失后再点选区，避免点到 Flare 自己
        try await Task.sleep(nanoseconds: 180_000_000)
        focus(at: focusPoint)
        try await Task.sleep(nanoseconds: 120_000_000)

        let first = try await captureSegment(
            displayID: session.displayID,
            selectionRectInPoints: session.selectionRectInPoints,
            targetSize: targetSize
        )

        var segments: [Segment] = [
            Segment(image: first, freshHeight: heightPx, staticTop: 0)
        ]
        var last = first
        var unchanged = 0

        // 每段滚动约半屏，重叠越大拼接越稳
        let wheelSteps: Int32 = -18
        let minFresh = max(32, heightPx / 10)

        for _ in 1..<maxSegments {
            if cancelMonitor.isCancelled { throw Error.cancelled }

            scrollWheel(at: focusPoint, lines: wheelSteps)
            try await Task.sleep(nanoseconds: 380_000_000)
            if cancelMonitor.isCancelled { throw Error.cancelled }

            let next = try await captureSegment(
                displayID: session.displayID,
                selectionRectInPoints: session.selectionRectInPoints,
                targetSize: targetSize
            )

            if nearlySame(a: last, b: next) {
                unchanged += 1
                if unchanged >= 2 { break }
                // 再滚深一点再试
                scrollWheel(at: focusPoint, lines: wheelSteps)
                try await Task.sleep(nanoseconds: 320_000_000)
                continue
            }
            unchanged = 0

            let staticTop = detectStaticTop(previous: last, current: next)
            let shift = estimateScrollShift(
                previous: last,
                current: next,
                staticTop: staticTop
            ) ?? max(minFresh, heightPx / 2)

            let fresh = min(max(shift, minFresh), heightPx - max(staticTop, 1))
            // 滚动过小说明几乎没动，再试一轮
            if fresh < minFresh {
                unchanged += 1
                if unchanged >= 2 { break }
                continue
            }

            segments.append(Segment(image: next, freshHeight: fresh, staticTop: staticTop))
            last = next
        }

        guard !segments.isEmpty else { throw Error.noSegment }
        return stitchTopDown(segments: segments)
    }

    // MARK: - Accessibility

    @discardableResult
    static func ensureAccessibility(prompt: Bool = true) -> Bool {
        if AXIsProcessTrusted() { return true }
        if prompt {
            let opts = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary
            _ = AXIsProcessTrustedWithOptions(opts)
        }
        return AXIsProcessTrusted()
    }

    // MARK: - Capture

    private static func captureSegment(
        displayID: CGDirectDisplayID,
        selectionRectInPoints: CGRect,
        targetSize: CGSize
    ) async throws -> CGImage {
        let frame = try await ScreenCapturer.captureDisplay(displayID, excludeSelf: true)

        // selection 为 AppKit 点坐标（左上原点）；CGImage 裁剪为左下原点
        let crop = CGRect(
            x: selectionRectInPoints.origin.x * frame.scale,
            y: (frame.bounds.height - selectionRectInPoints.origin.y - selectionRectInPoints.height) * frame.scale,
            width: selectionRectInPoints.width * frame.scale,
            height: selectionRectInPoints.height * frame.scale
        ).integral

        guard let cropped = frame.image.cropping(to: crop) else {
            throw Error.noSegment
        }
        if cropped.width == Int(targetSize.width), cropped.height == Int(targetSize.height) {
            return cropped
        }
        return resized(cropped, to: targetSize)
    }

    // MARK: - Input

    private static func focus(at point: CGPoint) {
        postMouse(.mouseMoved, at: point)
        postMouse(.leftMouseDown, at: point)
        postMouse(.leftMouseUp, at: point)
    }

    private static func postMouse(_ type: CGEventType, at point: CGPoint) {
        guard let event = CGEvent(source: nil) else { return }
        event.type = type
        event.location = point
        event.post(tap: .cghidEventTap)
    }

    /// 在指定屏幕位置发送滚轮（必须带 location，否则滚不到目标窗口）
    private static func scrollWheel(at point: CGPoint, lines: Int32) {
        guard let event = CGEvent(
            scrollWheelEvent2Source: nil,
            units: .line,
            wheelCount: 1,
            wheel1: lines,
            wheel2: 0,
            wheel3: 0
        ) else { return }
        event.location = point
        event.post(tap: .cghidEventTap)
    }

    // MARK: - Stitch (top → bottom)

    private static func stitchTopDown(segments: [Segment]) -> CGImage {
        let width = segments[0].image.width
        let height = segments[0].image.height

        var totalHeight = height
        for seg in segments.dropFirst() {
            totalHeight += seg.freshHeight
        }

        let ctx = CGContext(
            data: nil,
            width: width,
            height: totalHeight,
            bitsPerComponent: 8,
            bytesPerRow: 0,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        )!

        // CG 原点在左下：把「页面顶部」画在高 Y，后续内容往下（低 Y）拼
        var topY = totalHeight
        // 第一段整张
        topY -= height
        ctx.draw(segments[0].image, in: CGRect(x: 0, y: topY, width: width, height: height))

        for seg in segments.dropFirst() {
            let fresh = seg.freshHeight
            // 新内容在视口底部。CGImage y=0 是图像底边 → 直接裁底部 fresh 行
            let cropRect = CGRect(x: 0, y: 0, width: width, height: fresh)
            guard let strip = seg.image.cropping(to: cropRect) else { continue }
            topY -= fresh
            ctx.draw(strip, in: CGRect(x: 0, y: topY, width: width, height: fresh))
        }

        return ctx.makeImage()!
    }

    // MARK: - Analysis

    /// 估计向下滚动了多少像素（上一张内容在下一张里上移的量）
    private static func estimateScrollShift(previous: CGImage, current: CGImage, staticTop: Int) -> Int? {
        let h = previous.height
        let minShift = max(16, h / 12)
        let maxShift = max(minShift + 8, Int(Double(h) * 0.85))

        let tw = 160
        let a = downsampleGray(previous, targetWidth: tw)
        let b = downsampleGray(current, targetWidth: tw)
        guard a.width == b.width, a.height == b.height, a.height > 24 else { return nil }

        let scaleY = Double(a.height) / Double(h)
        let topSkip = max(2, Int(Double(max(staticTop, Int(Double(h) * 0.06))) * scaleY))
        let bottomSkip = max(2, Int(Double(h) * 0.04 * scaleY))
        let minD = max(1, Int(Double(minShift) * scaleY))
        let maxD = min(a.height - topSkip - bottomSkip - 2, Int(Double(maxShift) * scaleY))
        guard maxD > minD else { return nil }

        var best = minD
        var bestScore = Double.greatestFiniteMagnitude
        let x0 = a.width / 10
        let x1 = a.width - x0

        // previous[y+shift] ≈ current[y]（内容上移）
        for shift in stride(from: minD, through: maxD, by: 1) {
            var acc = 0.0
            var n = 0
            let yStart = topSkip
            let yEnd = a.height - bottomSkip - shift
            guard yEnd > yStart else { continue }
            var y = yStart
            while y < yEnd {
                let ra = (y + shift) * a.width
                let rb = y * b.width
                var x = x0
                while x < x1 {
                    acc += Double(abs(Int(a.bytes[ra + x]) - Int(b.bytes[rb + x])))
                    n += 1
                    x += 2
                }
                y += 2
            }
            guard n > 0 else { continue }
            let score = acc / Double(n)
            if score < bestScore {
                bestScore = score
                best = shift
            }
        }

        // 匹配太差就退回半屏
        guard bestScore < 22 else {
            return h / 2
        }
        return Int((Double(best) / scaleY).rounded()).clamped(to: 1...(h - 1))
    }

    private static func detectStaticTop(previous: CGImage, current: CGImage) -> Int {
        let a = downsampleGray(previous, targetWidth: 140)
        let b = downsampleGray(current, targetWidth: 140)
        guard a.width == b.width, a.height == b.height else { return 0 }

        let x0 = a.width / 10
        let x1 = a.width - x0
        var staticRows = 0
        var gap = 0
        let limit = min(a.height / 3, 100)

        for y in 0..<limit {
            var acc = 0.0
            var n = 0
            let ba = y * a.width
            let bb = y * b.width
            var x = x0
            while x < x1 {
                acc += Double(abs(Int(a.bytes[ba + x]) - Int(b.bytes[bb + x])))
                n += 1
                x += 2
            }
            let mad = n > 0 ? acc / Double(n) : 999
            // 图像顶 = CG 高 y；downsample 的 y=0 对应图像顶（绘制时 top-down 进 gray context）
            if mad <= 4.5 {
                staticRows += 1
                gap = 0
            } else if staticRows > 0 {
                gap += 1
                if gap > 2 { break }
            } else {
                break
            }
        }

        guard staticRows >= 8 else { return 0 }
        let scale = Double(previous.height) / Double(a.height)
        return Int(Double(staticRows) * scale)
    }

    private static func nearlySame(a: CGImage, b: CGImage) -> Bool {
        let da = downsampleGray(a, targetWidth: 100)
        let db = downsampleGray(b, targetWidth: 100)
        guard da.width == db.width, da.height == db.height, !da.bytes.isEmpty else { return false }
        var acc = 0.0
        for i in 0..<da.bytes.count {
            acc += Double(abs(Int(da.bytes[i]) - Int(db.bytes[i])))
        }
        return (acc / Double(da.bytes.count)) < 6.5
    }

    private static func downsampleGray(_ image: CGImage, targetWidth: Int) -> (bytes: [UInt8], width: Int, height: Int) {
        let scale = Double(targetWidth) / Double(max(1, image.width))
        let newW = targetWidth
        let newH = max(1, Int(Double(image.height) * scale))
        let ctx = CGContext(
            data: nil,
            width: newW,
            height: newH,
            bitsPerComponent: 8,
            bytesPerRow: newW,
            space: CGColorSpaceCreateDeviceGray(),
            bitmapInfo: CGImageAlphaInfo.none.rawValue
        )!
        ctx.interpolationQuality = .low
        // 注意：默认 CG 会把图像底画在 y=0；这里用翻转，让 bytes 行 0 = 视觉顶部，便于扫「顶栏」
        ctx.translateBy(x: 0, y: CGFloat(newH))
        ctx.scaleBy(x: 1, y: -1)
        ctx.draw(image, in: CGRect(x: 0, y: 0, width: newW, height: newH))
        guard let data = ctx.data else { return ([], newW, newH) }
        let buf = data.bindMemory(to: UInt8.self, capacity: newW * newH)
        return (Array(UnsafeBufferPointer(start: buf, count: newW * newH)), newW, newH)
    }

    private static func resized(_ image: CGImage, to size: CGSize) -> CGImage {
        let w = Int(size.width)
        let h = Int(size.height)
        let ctx = CGContext(
            data: nil,
            width: w,
            height: h,
            bitsPerComponent: 8,
            bytesPerRow: 0,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        )!
        ctx.interpolationQuality = .high
        ctx.draw(image, in: CGRect(x: 0, y: 0, width: w, height: h))
        return ctx.makeImage()!
    }
}

// MARK: - Esc

private final class EscCancelMonitor {
    private(set) var isCancelled = false
    private var local: Any?
    private var global: Any?

    init() {
        local = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            if event.keyCode == 53 {
                self?.isCancelled = true
                return nil
            }
            return event
        }
        global = NSEvent.addGlobalMonitorForEvents(matching: .keyDown) { [weak self] event in
            if event.keyCode == 53 {
                self?.isCancelled = true
            }
        }
    }

    func stop() {
        if let local { NSEvent.removeMonitor(local) }
        if let global { NSEvent.removeMonitor(global) }
        local = nil
        global = nil
    }
}

private extension Int {
    func clamped(to range: ClosedRange<Int>) -> Int {
        Swift.min(Swift.max(self, range.lowerBound), range.upperBound)
    }
}
