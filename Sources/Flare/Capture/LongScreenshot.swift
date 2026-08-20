import AppKit
import ApplicationServices
import CoreGraphics

/// 长截图：选区自动滚动，多帧按重叠区精确拼接。
///
/// 拼接核心（ShareX / GoFullPage 同类思路）：
/// 1. 相邻两帧在「可滚动内容区」搜索最佳重叠行数 overlap
/// 2. 上一帧底部 overlap 行 ≈ 当前帧顶部 overlap 行
/// 3. 只追加当前帧底部 (H - overlap) 行新内容，固定顶栏不参与匹配
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

    /// 视觉坐标：row 0 = 图像顶部（浏览器地址栏一侧）
    private struct TopDownGray {
        let bytes: [UInt8]
        let width: Int
        let height: Int

        func rowMAD(with other: TopDownGray, selfRows: Range<Int>, otherRows: Range<Int>, xMargin: Int = 0) -> Double {
            guard selfRows.count == otherRows.count, !selfRows.isEmpty else { return .greatestFiniteMagnitude }
            let x0 = max(0, xMargin)
            let x1 = min(width, width - xMargin)
            guard x1 > x0 + 4 else { return .greatestFiniteMagnitude }
            var acc = 0.0
            var n = 0
            for (ra, rb) in zip(selfRows, otherRows) {
                let ba = ra * width
                let bb = rb * width
                var x = x0
                while x < x1 {
                    acc += Double(abs(Int(bytes[ba + x]) - Int(other.bytes[bb + x])))
                    n += 1
                    x += 2
                }
            }
            return n > 0 ? acc / Double(n) : .greatestFiniteMagnitude
        }
    }

    static func capture(session: Session, maxSegments: Int = 24) async throws -> CGImage {
        try Task.checkCancellation()
        guard ensureAccessibility() else { throw Error.needsAccessibility }

        let widthPx = max(1, Int((session.selectionRectInPoints.width * session.displayScale).rounded()))
        let heightPx = max(1, Int((session.selectionRectInPoints.height * session.displayScale).rounded()))
        let targetSize = CGSize(width: widthPx, height: heightPx)

        let cancelMonitor = EscCancelMonitor()
        defer { cancelMonitor.stop() }

        let focusPoint = CGPoint(
            x: session.displayBoundsInPoints.minX + session.selectionRectInPoints.midX,
            y: session.displayBoundsInPoints.minY + session.selectionRectInPoints.midY
        )

        try await Task.sleep(nanoseconds: 180_000_000)
        focus(at: focusPoint)
        try await Task.sleep(nanoseconds: 120_000_000)

        var frames: [CGImage] = []
        frames.append(try await captureSegment(
            displayID: session.displayID,
            selectionRectInPoints: session.selectionRectInPoints,
            targetSize: targetSize
        ))

        let wheelSteps: Int32 = -16
        var unchanged = 0
        var last = frames[0]

        for _ in 1..<maxSegments {
            if cancelMonitor.isCancelled { throw Error.cancelled }

            scrollWheel(at: focusPoint, lines: wheelSteps)
            try await Task.sleep(nanoseconds: 400_000_000)
            if cancelMonitor.isCancelled { throw Error.cancelled }

            let next = try await captureSegment(
                displayID: session.displayID,
                selectionRectInPoints: session.selectionRectInPoints,
                targetSize: targetSize
            )

            if nearlySame(a: last, b: next) {
                unchanged += 1
                if unchanged >= 2 { break }
                scrollWheel(at: focusPoint, lines: wheelSteps)
                try await Task.sleep(nanoseconds: 300_000_000)
                continue
            }
            unchanged = 0

            // 预估重叠，若几乎没滚动则跳过
            let overlap = findBestOverlap(previous: last, current: next)
            let fresh = heightPx - overlap
            if fresh < max(20, heightPx / 15) {
                unchanged += 1
                if unchanged >= 2 { break }
                continue
            }

            frames.append(next)
            last = next
        }

        guard frames.count >= 1 else { throw Error.noSegment }
        return stitchByOverlap(frames: frames)
    }

    // MARK: - Stitch

    /// 按相邻帧重叠区拼接：首帧全保留，后续只追加非重叠底部
    private static func stitchByOverlap(frames: [CGImage]) -> CGImage {
        guard let first = frames.first else { fatalError("unreachable") }
        let w = first.width
        let h = first.height

        var strips: [CGImage] = [first]

        for i in 1..<frames.count {
            let prev = frames[i - 1]
            let curr = frames[i]
            let overlap = findBestOverlap(previous: prev, current: curr)
            let freshRows = h - overlap
            guard freshRows > 0, freshRows < h else { continue }

            if let strip = cropTopDownRows(from: curr, startRow: overlap, rowCount: freshRows) {
                strips.append(strip)
            }
        }

        return composeVertical(strips: strips, width: w)
    }

    /// 搜索最佳重叠：prev 底部 overlap 行 ≈ curr 顶部 overlap 行
    private static func findBestOverlap(previous: CGImage, current: CGImage) -> Int {
        let h = previous.height
        let minOverlap = max(24, h / 8)
        let maxOverlap = min(h - 24, Int(Double(h) * 0.92))

        let staticTop = detectStaticTop(previous: previous, current: current)
        let staticBottom = detectStaticBottom(previous: previous, current: current)

        // 粗搜：下采样
        let tw = 200
        let prevG = toTopDownGray(previous, targetWidth: tw)
        let currG = toTopDownGray(current, targetWidth: tw)
        guard prevG.width == currG.width, prevG.height == currG.height else {
            return h / 2
        }

        let scale = Double(prevG.height) / Double(h)
        let minOD = max(4, Int(Double(minOverlap) * scale))
        let maxOD = min(prevG.height - 4, Int(Double(maxOverlap) * scale))
        guard maxOD > minOD else { return h / 2 }

        let skipTop = max(2, Int(Double(staticTop) * scale))
        let skipBottom = max(2, Int(Double(staticBottom) * scale))
        let xMargin = prevG.width / 12

        var bestOD = minOD
        var bestScore = Double.greatestFiniteMagnitude

        for od in stride(from: minOD, through: maxOD, by: 1) {
            // prev 底部 od 行 vs curr 顶部 od 行
            let prevRows = (prevG.height - skipBottom - od)..<(prevG.height - skipBottom)
            let currRows = skipTop..<(skipTop + od)
            guard prevRows.lowerBound >= 0, currRows.upperBound <= currG.height else { continue }

            let score = prevG.rowMAD(with: currG, selfRows: prevRows, otherRows: currRows, xMargin: xMargin)
            if score < bestScore {
                bestScore = score
                bestOD = od
            }
        }

        var overlap = Int((Double(bestOD) / scale).rounded()).clamped(to: minOverlap...maxOverlap)

        // 细搜：全分辨率 ±6px
        if bestScore < 28 {
            let refine = refineOverlap(
                previous: previous,
                current: current,
                center: overlap,
                radius: 6,
                staticTop: staticTop,
                staticBottom: staticBottom
            )
            if let refine { overlap = refine }
        }

        return overlap
    }

    private static func refineOverlap(
        previous: CGImage,
        current: CGImage,
        center: Int,
        radius: Int,
        staticTop: Int,
        staticBottom: Int
    ) -> Int? {
        let h = previous.height
        let lo = max(max(24, h / 8), center - radius)
        let hi = min(min(h - 24, Int(Double(h) * 0.92)), center + radius)
        guard hi > lo else { return nil }

        let prevG = toTopDownGray(previous, targetWidth: min(320, previous.width))
        let currG = toTopDownGray(current, targetWidth: min(320, current.width))
        guard prevG.width == currG.width, prevG.height == currG.height else { return nil }

        let xMargin = prevG.width / 12
        var best = center
        var bestScore = Double.greatestFiniteMagnitude
        let scale = Double(prevG.height) / Double(h)

        for overlap in lo...hi {
            let od = max(4, Int(Double(overlap) * scale))
            let skipTop = max(2, Int(Double(staticTop) * scale))
            let skipBottom = max(2, Int(Double(staticBottom) * scale))
            let prevRows = (prevG.height - skipBottom - od)..<(prevG.height - skipBottom)
            let currRows = skipTop..<(skipTop + od)
            guard prevRows.lowerBound >= 0, currRows.upperBound <= currG.height else { continue }
            let score = prevG.rowMAD(with: currG, selfRows: prevRows, otherRows: currRows, xMargin: xMargin)
            if score < bestScore {
                bestScore = score
                best = overlap
            }
        }
        return bestScore < 32 ? best : nil
    }

    /// 视觉 top-down 行裁剪：startRow=0 是顶部，rowCount 向下取
    private static func cropTopDownRows(from image: CGImage, startRow: Int, rowCount: Int) -> CGImage? {
        guard startRow >= 0, rowCount > 0, startRow + rowCount <= image.height else { return nil }
        // CGImage 原点在左下：视觉顶部 = 高 y
        let cgY = image.height - startRow - rowCount
        return image.cropping(to: CGRect(x: 0, y: cgY, width: image.width, height: rowCount))
    }

    /// 自上而下拼接多条 strip（strip[0] 在最上）
    private static func composeVertical(strips: [CGImage], width: Int) -> CGImage {
        var totalH = 0
        for s in strips { totalH += s.height }

        let ctx = CGContext(
            data: nil,
            width: width,
            height: totalH,
            bitsPerComponent: 8,
            bytesPerRow: 0,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        )!

        // CG 画布：y 越大越靠上；第一条 strip 画在最顶部
        var drawY = totalH
        for strip in strips {
            drawY -= strip.height
            ctx.draw(strip, in: CGRect(x: 0, y: drawY, width: width, height: strip.height))
        }
        return ctx.makeImage()!
    }

    // MARK: - Static chrome

    private static func detectStaticTop(previous: CGImage, current: CGImage) -> Int {
        detectStaticEdge(previous: previous, current: current, fromTop: true)
    }

    private static func detectStaticBottom(previous: CGImage, current: CGImage) -> Int {
        detectStaticEdge(previous: previous, current: current, fromTop: false)
    }

    private static func detectStaticEdge(previous: CGImage, current: CGImage, fromTop: Bool) -> Int {
        let tw = 160
        let a = toTopDownGray(previous, targetWidth: tw)
        let b = toTopDownGray(current, targetWidth: tw)
        guard a.width == b.width, a.height == b.height, a.height > 40 else { return 0 }

        let x0 = a.width / 10
        let x1 = a.width - x0
        let limit = min(a.height / 3, 110)
        let madThreshold = 4.0
        var staticRows = 0
        var gap = 0

        let indices: [Int] = fromTop
            ? Array(0..<limit)
            : Array((a.height - limit)..<a.height).reversed()

        for y in indices {
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
            if mad <= madThreshold {
                staticRows += 1
                gap = 0
            } else if staticRows > 0 {
                gap += 1
                if gap > 2 { break }
            } else if fromTop {
                break
            }
        }

        guard staticRows >= 6 else { return 0 }
        let scale = Double(previous.height) / Double(a.height)
        return Int(Double(staticRows) * scale)
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
        let crop = CGRect(
            x: selectionRectInPoints.origin.x * frame.scale,
            y: (frame.bounds.height - selectionRectInPoints.origin.y - selectionRectInPoints.height) * frame.scale,
            width: selectionRectInPoints.width * frame.scale,
            height: selectionRectInPoints.height * frame.scale
        ).integral

        guard let cropped = frame.image.cropping(to: crop) else { throw Error.noSegment }
        if cropped.width == Int(targetSize.width), cropped.height == Int(targetSize.height) { return cropped }
        return resized(cropped, to: targetSize)
    }

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

    // MARK: - Image utils

    private static func nearlySame(a: CGImage, b: CGImage) -> Bool {
        let da = toTopDownGray(a, targetWidth: 100)
        let db = toTopDownGray(b, targetWidth: 100)
        guard da.width == db.width, da.height == db.height, !da.bytes.isEmpty else { return false }
        var acc = 0.0
        for i in 0..<da.bytes.count {
            acc += Double(abs(Int(da.bytes[i]) - Int(db.bytes[i])))
        }
        return (acc / Double(da.bytes.count)) < 6.0
    }

    /// 转成 top-down 灰度：bytes[row * width + x]，row 0 = 视觉顶部
    private static func toTopDownGray(_ image: CGImage, targetWidth: Int) -> TopDownGray {
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
        ctx.translateBy(x: 0, y: CGFloat(newH))
        ctx.scaleBy(x: 1, y: -1)
        ctx.draw(image, in: CGRect(x: 0, y: 0, width: newW, height: newH))
        guard let data = ctx.data else { return TopDownGray(bytes: [], width: newW, height: newH) }
        let buf = data.bindMemory(to: UInt8.self, capacity: newW * newH)
        return TopDownGray(bytes: Array(UnsafeBufferPointer(start: buf, count: newW * newH)), width: newW, height: newH)
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
            if event.keyCode == 53 { self?.isCancelled = true; return nil }
            return event
        }
        global = NSEvent.addGlobalMonitorForEvents(matching: .keyDown) { [weak self] event in
            if event.keyCode == 53 { self?.isCancelled = true }
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
