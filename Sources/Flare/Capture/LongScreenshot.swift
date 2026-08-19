import AppKit
import Carbon
import CoreGraphics

/// 长截图：对选区进行自动滚动截取，并把多段截图拼成长图
///
/// MVP 说明：
/// - 自动滚动使用 PageDown（需要目标窗口已获得焦点）
/// - 拼接使用“重叠区域最小差异”估计重叠高度（基于下采样灰度）
/// - 结束条件：达到最大段数或连续两次变化幅度很小
enum LongScreenshot {
    struct Session {
        let displayID: CGDirectDisplayID
        let displayBoundsInPoints: CGRect
        let selectionRectInPoints: CGRect // 以 screen overlay 坐标为准：左上/右上不影响，仅用于换算
        let displayScale: CGFloat // px / point
    }

    enum Error: LocalizedError {
        case cancelled
        case noSegment

        var errorDescription: String? {
            switch self {
            case .cancelled: return "已取消长截图"
            case .noSegment: return "未能截取到长截图内容"
            }
        }
    }

    static func capture(session: Session, maxSegments: Int = 12) async throws -> CGImage {
        try Task.checkCancellation()

        let expectedWidthPx = max(1, Int((session.selectionRectInPoints.width * session.displayScale).rounded()))
        let expectedHeightPx = max(1, Int((session.selectionRectInPoints.height * session.displayScale).rounded()))
        let expectedSize = CGSize(width: expectedWidthPx, height: expectedHeightPx)

        // 取消监控：按 Esc 立即停止
        let cancelMonitor = EscCancelMonitor()
        defer { cancelMonitor.stop() }

        // 聚焦到选区：点一下中心位置，保证 PageDown 生效
        let focusPointInScreen = CGPoint(
            x: session.displayBoundsInPoints.minX + session.selectionRectInPoints.midX,
            y: session.displayBoundsInPoints.minY + session.selectionRectInPoints.midY
        )
        focus(focusPointInScreen)

        // 第一段不滚动，直接截
        let first = try await captureSegment(
            displayID: session.displayID,
            selectionRectInPoints: session.selectionRectInPoints,
            targetSize: expectedSize,
            excludeSelf: true
        )
        var segments: [CGImage] = [first]

        // 连续“基本无变化”计数
        var unchangedCount = 0
        var lastSegment = first

        for _ in 0..<maxSegments - 1 {
            if cancelMonitor.isCancelled { throw Error.cancelled }

            scrollDownPage()

            // 给目标窗口滚动/渲染一点时间
            try await Task.sleep(nanoseconds: 550_000_000)

            if cancelMonitor.isCancelled { throw Error.cancelled }

            let next = try await captureSegment(
                displayID: session.displayID,
                selectionRectInPoints: session.selectionRectInPoints,
                targetSize: expectedSize,
                excludeSelf: true
            )

            // 如果连续两次几乎没变化，就认为到头了
            if nearlySame(a: lastSegment, b: next) {
                unchangedCount += 1
                if unchangedCount >= 2 { break }
            } else {
                unchangedCount = 0
            }

            segments.append(next)
            lastSegment = next
        }

        guard !segments.isEmpty else { throw Error.noSegment }
        return stitchVertical(segments: segments)
    }

    // MARK: - Segment capture

    private static func captureSegment(
        displayID: CGDirectDisplayID,
        selectionRectInPoints: CGRect,
        targetSize: CGSize,
        excludeSelf: Bool
    ) async throws -> CGImage {
        let frame = try await ScreenCapturer.captureDisplay(displayID, excludeSelf: excludeSelf)

        let cropPixel = CGRect(
            x: selectionRectInPoints.origin.x * frame.scale,
            y: (frame.bounds.height - selectionRectInPoints.origin.y - selectionRectInPoints.height) * frame.scale,
            width: selectionRectInPoints.width * frame.scale,
            height: selectionRectInPoints.height * frame.scale
        ).integral

        guard let cropped = frame.image.cropping(to: cropPixel) else {
            throw Error.noSegment
        }
        // 统一尺寸，避免拼接时因 scale 微小抖动导致的宽高不一致
        if CGSize(width: cropped.width, height: cropped.height) == targetSize {
            return cropped
        }
        return resized(cropped, to: targetSize)
    }

    // MARK: - Scroll control

    private static func focus(_ pointInScreen: CGPoint) {
        // 把鼠标移到目标区域附近并点击一次，让滚动事件落到对应窗口
        let loc = pointInScreen
        guard let move = CGEvent(source: nil) else { return }
        move.type = .mouseMoved
        move.location = CGPoint(x: loc.x, y: loc.y)
        move.post(tap: .cghidEventTap)

        guard let down = CGEvent(source: nil) else { return }
        down.type = .leftMouseDown
        down.location = CGPoint(x: loc.x, y: loc.y)
        down.post(tap: .cghidEventTap)

        guard let up = CGEvent(source: nil) else { return }
        up.type = .leftMouseUp
        up.location = CGPoint(x: loc.x, y: loc.y)
        up.post(tap: .cghidEventTap)
    }

    private static func scrollDownPage() {
        // PageDown：通常比滚轮更接近“网页长截图”的滚动步幅
        let source = CGEventSource(stateID: .combinedSessionState)
        guard let keyDown = CGEvent(keyboardEventSource: source, virtualKey: CGKeyCode(kVK_PageDown), keyDown: true) else { return }
        let keyUp = CGEvent(keyboardEventSource: source, virtualKey: CGKeyCode(kVK_PageDown), keyDown: false)
        keyDown.post(tap: .cghidEventTap)
        keyUp?.post(tap: .cghidEventTap)
    }

    // MARK: - Stitching

    private static func stitchVertical(segments: [CGImage]) -> CGImage {
        let width = segments[0].width
        let height = segments[0].height
        for s in segments where s.width != width || s.height != height {
            // 保险：理论上 captureSegment 已统一尺寸；不一致直接降级拼接（以第一个为基准）
            // 这里简单 return，避免复杂重采样逻辑影响稳定性
            return segments[0]
        }

        // 先用第 1 段作为底图
        var stitchedHeight = height
        var stitchedContext = CGContext(
            data: nil,
            width: width,
            height: stitchedHeight,
            bitsPerComponent: 8,
            bytesPerRow: 0,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        )!
        stitchedContext.draw(segments[0], in: CGRect(x: 0, y: 0, width: width, height: height))

        // 逐段拼接
        var last = segments[0]
        for next in segments.dropFirst() {
            // 用“下一段顶部 vs 上一段底部”的重叠区域最小差异来估计 overlap（在 downsample 空间算，再映射回原空间）
            let overlap = estimateOverlap(a: last, b: next, segmentHeight: height)
            let newHeight = stitchedHeight + height - overlap

            guard let newContext = CGContext(
                data: nil,
                width: width,
                height: newHeight,
                bitsPerComponent: 8,
                bytesPerRow: 0,
                space: CGColorSpaceCreateDeviceRGB(),
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
            ) else { break }

            // draw 现有 stitched
            let stitchedCG = stitchedContext.makeImage()
            if let stitchedCG { newContext.draw(stitchedCG, in: CGRect(x: 0, y: 0, width: width, height: stitchedHeight)) }

            // draw next：y 从 stitchedHeight - overlap 开始
            newContext.draw(next, in: CGRect(x: 0, y: stitchedHeight - overlap, width: width, height: height))

            stitchedContext = newContext
            stitchedHeight = newHeight
            last = next
        }

        return stitchedContext.makeImage()!
    }

    private static func estimateOverlap(a: CGImage, b: CGImage, segmentHeight: Int) -> Int {
        // 重叠搜索范围：10% ~ 40%
        let minOverlap = Int(Double(segmentHeight) * 0.10)
        let maxOverlap = Int(Double(segmentHeight) * 0.40)
        guard maxOverlap > minOverlap else { return minOverlap }

        // 下采样宽度固定，降低计算量
        let targetWidth = 180
        let downA = downsampleGray(a, targetWidth: targetWidth)
        let downB = downsampleGray(b, targetWidth: targetWidth)

        let scaleY = Double(downA.height) / Double(segmentHeight)
        func overlapFromDown(_ downOverlap: Int) -> Int {
            Int(Double(downOverlap) / scaleY).clamped(to: 1...segmentHeight - 1)
        }

        let minDown = Int((Double(minOverlap) * Double(downA.height)) / Double(segmentHeight))
        let maxDown = Int((Double(maxOverlap) * Double(downA.height)) / Double(segmentHeight))
        let step = 2

        var bestOverlapDown = minDown
        var bestScore = Double.greatestFiniteMagnitude

        for overlapDown in stride(from: minDown, through: maxDown, by: step) {
            // last overlap: A bottom overlapDown; next top overlapDown
            let aYStart = downA.height - overlapDown
            let bYStart = 0

            var acc = 0.0
            // x 采样步长：2
            for y in 0..<overlapDown {
                let aRow = (aYStart + y) * downA.width
                let bRow = (bYStart + y) * downB.width
                var x = 0
                while x < downA.width {
                    let av = downA.bytes[aRow + x]
                    let bv = downB.bytes[bRow + x]
                    acc += Double(abs(Int(av) - Int(bv)))
                    x += 2
                }
            }

            let score = acc / Double(overlapDown * (downA.width / 2))
            if score < bestScore {
                bestScore = score
                bestOverlapDown = overlapDown
            }
        }

        return overlapFromDown(bestOverlapDown)
    }

    private static func nearlySame(a: CGImage, b: CGImage) -> Bool {
        // 粗略判定：把两张图下采样到固定大小，比对像素平均差异
        let targetWidth = 120
        let da = downsampleGray(a, targetWidth: targetWidth)
        let db = downsampleGray(b, targetWidth: targetWidth)
        guard da.width == db.width, da.height == db.height else { return false }

        var acc = 0.0
        for i in 0..<min(da.bytes.count, db.bytes.count) {
            acc += Double(abs(Int(da.bytes[i]) - Int(db.bytes[i])))
        }
        let avg = acc / Double(min(da.bytes.count, db.bytes.count))
        // 阈值：越小越“没变化”
        return avg < 7.5
    }

    private static func downsampleGray(_ image: CGImage, targetWidth: Int) -> (bytes: [UInt8], width: Int, height: Int) {
        let w = image.width
        let h = image.height
        let scale = Double(targetWidth) / Double(max(1, w))
        let newW = targetWidth
        let newH = max(1, Int(Double(h) * scale))

        let bytesPerRow = newW
        let bitsPerComponent = 8
        let ctx = CGContext(
            data: nil,
            width: newW,
            height: newH,
            bitsPerComponent: bitsPerComponent,
            bytesPerRow: bytesPerRow,
            space: CGColorSpaceCreateDeviceGray(),
            bitmapInfo: CGImageAlphaInfo.none.rawValue
        )!
        ctx.interpolationQuality = .low
        ctx.draw(image, in: CGRect(x: 0, y: 0, width: newW, height: newH))

        guard let data = ctx.data else { return ([], newW, newH) }
        let buffer = data.bindMemory(to: UInt8.self, capacity: newW * newH)
        return (Array(UnsafeBufferPointer(start: buffer, count: newW * newH)), newW, newH)
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

// MARK: - Utilities

private final class EscCancelMonitor {
    private(set) var isCancelled = false
    private var monitor: Any?

    init() {
        monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard let self else { return event }
            // Esc
            if event.keyCode == 53 {
                self.isCancelled = true
                return nil
            }
            return event
        }
    }

    func stop() {
        if let monitor { NSEvent.removeMonitor(monitor) }
        monitor = nil
    }
}

private extension Int {
    func clamped(to range: ClosedRange<Int>) -> Int {
        Swift.min(Swift.max(self, range.lowerBound), range.upperBound)
    }
}

