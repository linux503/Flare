import AppKit
import ApplicationServices
import CoreGraphics

/// 长截图：自动滚动 + 按位移拼接（统一 top-down 像素坐标，row 0 = 视觉顶部）。
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

    private struct Gray {
        let bytes: [UInt8]
        let width: Int
        let height: Int
    }

    private struct Captured {
        let image: CGImage
        let shift: Int
        let stickyTop: Int
    }

    /// row 0 = 视觉顶部，避免 CGImage 左下原点带来的裁切/检测错乱
    private struct TopDownImage {
        let width: Int
        let height: Int
        let rgba: [UInt8]

        init(cgImage: CGImage) {
            width = cgImage.width
            height = cgImage.height
            let rowBytes = width * 4
            let ctx = CGContext(
                data: nil,
                width: width,
                height: height,
                bitsPerComponent: 8,
                bytesPerRow: rowBytes,
                space: CGColorSpaceCreateDeviceRGB(),
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
            )!
            ctx.translateBy(x: 0, y: CGFloat(height))
            ctx.scaleBy(x: 1, y: -1)
            ctx.draw(cgImage, in: CGRect(x: 0, y: 0, width: width, height: height))
            let ptr = ctx.data!.bindMemory(to: UInt8.self, capacity: rowBytes * height)
            // CGContext 内存行 0 仍是视觉底部；复制时翻成 top-down（row 0 = 顶）
            var rows = [UInt8]()
            rows.reserveCapacity(rowBytes * height)
            for r in 0..<height {
                let src = ptr.advanced(by: (height - 1 - r) * rowBytes)
                rows.append(contentsOf: UnsafeBufferPointer(start: src, count: rowBytes))
            }
            rgba = rows
        }

        init(width: Int, height: Int, rgba: [UInt8]) {
            self.width = width
            self.height = height
            self.rgba = rgba
        }

        func crop(startRow: Int, rowCount: Int) -> TopDownImage {
            precondition(startRow >= 0 && rowCount > 0 && startRow + rowCount <= height)
            var out = [UInt8]()
            out.reserveCapacity(width * rowCount * 4)
            let rb = width * 4
            for r in startRow..<(startRow + rowCount) {
                let src = r * rb
                out.append(contentsOf: rgba[src..<(src + rb)])
            }
            return TopDownImage(width: width, height: rowCount, rgba: out)
        }

        /// 对齐到目标宽度（居中裁切或补黑边），避免缩放糊图
        func aligned(toWidth targetW: Int) -> TopDownImage {
            if width == targetW { return self }
            let rb = targetW * 4
            var out = [UInt8](repeating: 0, count: rb * height)
            let copyW = min(width, targetW)
            let srcX = max(0, (width - copyW) / 2)
            let dstX = max(0, (targetW - copyW) / 2)
            let srcRB = width * 4
            for r in 0..<height {
                let src = r * srcRB + srcX * 4
                let dst = r * rb + dstX * 4
                out.replaceSubrange(dst..<(dst + copyW * 4), with: rgba[src..<(src + copyW * 4)])
            }
            return TopDownImage(width: targetW, height: height, rgba: out)
        }

        func toCGImage() -> CGImage {
            let rowBytes = width * 4
            let ctx = CGContext(
                data: nil,
                width: width,
                height: height,
                bitsPerComponent: 8,
                bytesPerRow: rowBytes,
                space: CGColorSpaceCreateDeviceRGB(),
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
            )!
            guard let dst = ctx.data else { fatalError("ctx") }
            rgba.withUnsafeBytes { src in
                guard let base = src.baseAddress else { return }
                for r in 0..<height {
                    let off = r * rowBytes
                    dst.advanced(by: off).copyMemory(from: base.advanced(by: off), byteCount: rowBytes)
                }
            }
            return ctx.makeImage()!
        }

        func grayDownsample(targetWidth: Int) -> Gray {
            let newW = targetWidth
            let newH = max(1, Int(Double(height) * Double(newW) / Double(max(1, width))))
            var bytes = [UInt8]()
            bytes.reserveCapacity(newW * newH)
            for y in 0..<newH {
                let srcY = min(height - 1, y * height / newH)
                for x in 0..<newW {
                    let srcX = min(width - 1, x * width / newW)
                    let i = (srcY * width + srcX) * 4
                    let r = Double(rgba[i])
                    let g = Double(rgba[i + 1])
                    let b = Double(rgba[i + 2])
                    bytes.append(UInt8((0.299 * r + 0.587 * g + 0.114 * b).rounded()))
                }
            }
            return Gray(bytes: bytes, width: newW, height: newH)
        }

        static func composeVertical(_ parts: [TopDownImage]) -> CGImage {
            guard let first = parts.first else { fatalError("empty") }
            let w = first.width
            let totalH = parts.reduce(0) { $0 + $1.height }
            var buf = [UInt8](repeating: 0, count: w * totalH * 4)
            let rb = w * 4
            var dstRow = 0
            for part in parts {
                for r in 0..<part.height {
                    let src = r * rb
                    let dst = dstRow * rb
                    buf.replaceSubrange(dst..<(dst + rb), with: part.rgba[src..<(src + rb)])
                    dstRow += 1
                }
            }
            return TopDownImage(width: w, height: totalH, rgba: buf).toCGImage()
        }
    }

    static func capture(session: Session, maxSegments: Int = 40) async throws -> CGImage {
        try Task.checkCancellation()
        guard ensureAccessibility() else { throw Error.needsAccessibility }

        let widthPx = max(1, Int((session.selectionRectInPoints.width * session.displayScale).rounded()))
        let heightPx = max(1, Int((session.selectionRectInPoints.height * session.displayScale).rounded()))
        let targetSize = CGSize(width: widthPx, height: heightPx)
        // 小步滚动，保证帧间 25%+ 重叠，便于精确对缝
        let minShift = max(16, heightPx / 20)
        let idealShift = max(minShift, heightPx / 3)

        let cancelMonitor = EscCancelMonitor()
        defer { cancelMonitor.stop() }

        let focusPoint = CGPoint(
            x: session.displayBoundsInPoints.minX + session.selectionRectInPoints.midX,
            y: session.displayBoundsInPoints.minY + session.selectionRectInPoints.midY
        )

        try await Task.sleep(nanoseconds: 180_000_000)
        focus(at: focusPoint)
        try await Task.sleep(nanoseconds: 160_000_000)

        let first = try await captureStableSegment(
            displayID: session.displayID,
            selectionRectInPoints: session.selectionRectInPoints,
            targetSize: targetSize
        )

        var frames: [Captured] = [Captured(image: first, shift: 0, stickyTop: 0)]
        var last = first
        var globalSticky = 0
        var unchanged = 0
        // 像素滚动比「行」更稳定，减少网页不定高行导致的位移抖动
        let pixelStep = Int32(-max(80, min(220, idealShift * 2 / 3)))

        for _ in 1..<maxSegments {
            if cancelMonitor.isCancelled { throw Error.cancelled }

            scrollWheelPixels(at: focusPoint, delta: pixelStep)
            try await Task.sleep(nanoseconds: 280_000_000)
            if cancelMonitor.isCancelled { throw Error.cancelled }

            let next = try await captureStableSegment(
                displayID: session.displayID,
                selectionRectInPoints: session.selectionRectInPoints,
                targetSize: targetSize
            )

            if nearlySame(a: last, b: next) {
                unchanged += 1
                if unchanged >= 2 { break }
                scrollWheelPixels(at: focusPoint, delta: pixelStep)
                try await Task.sleep(nanoseconds: 320_000_000)
                continue
            }

            let stickyTop = max(
                globalSticky,
                detectStickyTop(previous: first, current: next)
            )
            globalSticky = max(globalSticky, stickyTop)
            let stickyBottom = detectStickyBottom(previous: last, current: next)

            let guessed = estimateShift(
                previous: last,
                current: next,
                stickyTop: stickyTop,
                stickyBottom: stickyBottom
            ) ?? idealShift

            // 用上一帧底部条带在下一帧里精修位移，消除接缝
            let refined = refineOverlap(
                previous: last,
                current: next,
                stickyTop: stickyTop,
                stickyBottom: stickyBottom,
                guess: guessed
            )
            let maxFresh = max(8, heightPx - stickyTop - max(stickyBottom, 2) - 4)
            let fresh = min(max(refined, 8), maxFresh)

            if ProcessInfo.processInfo.environment["FLARE_STITCH_DEBUG"] == "1" {
                print("shift guess=\(guessed) refined=\(refined) fresh=\(fresh) sticky=\(stickyTop)")
            }

            // 位移过小说明几乎没滚，再试一次
            if fresh < minShift {
                unchanged += 1
                if unchanged >= 3 { break }
                last = next
                continue
            }

            frames.append(Captured(image: next, shift: fresh, stickyTop: stickyTop))
            last = next
            unchanged = 0
        }

        guard !frames.isEmpty else { throw Error.noSegment }
        return stitch(frames: frames)
    }

    static func stitchFramesForTesting(_ images: [CGImage]) -> CGImage {
        precondition(!images.isEmpty)
        let first = images[0]
        let h = first.height
        let idealShift = max(24, h / 3)
        var globalSticky = 0
        for i in 1..<images.count {
            globalSticky = max(globalSticky, detectStickyTop(previous: first, current: images[i]))
        }
        var captured: [Captured] = [Captured(image: first, shift: 0, stickyTop: globalSticky)]
        for i in 1..<images.count {
            let prev = images[i - 1]
            let curr = images[i]
            let stickyTop = max(globalSticky, detectStickyTop(previous: first, current: curr))
            let stickyBottom = detectStickyBottom(previous: prev, current: curr)
            let guessed = estimateShift(
                previous: prev,
                current: curr,
                stickyTop: stickyTop,
                stickyBottom: stickyBottom
            ) ?? idealShift
            let refined = refineOverlap(
                previous: prev,
                current: curr,
                stickyTop: stickyTop,
                stickyBottom: stickyBottom,
                guess: guessed
            )
            let maxFresh = max(8, h - stickyTop - max(stickyBottom, 2) - 4)
            let fresh = min(max(refined, 8), maxFresh)
            captured.append(Captured(image: curr, shift: fresh, stickyTop: stickyTop))
        }
        return stitch(frames: captured)
    }

    // MARK: - Stitch

    private static func stitch(frames: [Captured]) -> CGImage {
        let firstTD = TopDownImage(cgImage: frames[0].image)
        let w = firstTD.width
        let h = firstTD.height
        let sticky = frames.map(\.stickyTop).max() ?? 0

        var parts: [TopDownImage] = [firstTD]

        for frame in frames.dropFirst() {
            let frameSticky = max(sticky, frame.stickyTop)
            guard frameSticky < h - 16 else { continue }

            let td = TopDownImage(cgImage: frame.image).aligned(toWidth: w)
            let hh = td.height

            // 再对「已拼结果底部」与「新帧」做一次对缝，避免累计漂移
            let prevPart = parts.last!
            let localGuess = frame.shift
            let cut = refineAppendCut(
                accumulated: prevPart,
                next: td,
                stickyTop: frameSticky,
                guessFresh: localGuess
            )
            let startRow = max(frameSticky, hh - cut)
            let rowCount = hh - startRow
            guard rowCount > 4, startRow >= frameSticky, startRow + rowCount <= hh else { continue }

            if ProcessInfo.processInfo.environment["FLARE_STITCH_DEBUG"] == "1" {
                print("    append sticky=\(frameSticky) cut=\(cut) startRow=\(startRow) rows=\(rowCount)")
            }

            parts.append(td.crop(startRow: startRow, rowCount: rowCount))
        }

        return TopDownImage.composeVertical(parts)
    }

    /// 在下一帧中定位上一帧底部条带，得到应追加的新像素高度
    private static func refineOverlap(
        previous: CGImage,
        current: CGImage,
        stickyTop: Int,
        stickyBottom: Int,
        guess: Int
    ) -> Int {
        let prev = TopDownImage(cgImage: previous)
        let curr = TopDownImage(cgImage: current)
        guard prev.height == curr.height, prev.width == curr.width else { return guess }

        let h = prev.height
        let contentBottom = h - max(stickyBottom, 0)
        let templateH = min(64, max(24, (contentBottom - stickyTop) / 5))
        guard contentBottom - stickyTop > templateH + 8 else { return guess }

        let a = prev.grayDownsample(targetWidth: 280)
        let b = curr.grayDownsample(targetWidth: 280)
        guard a.width == b.width, a.height == b.height else { return guess }

        let scale = Double(a.height) / Double(h)
        let stickyD = max(0, Int(Double(stickyTop) * scale))
        let bottomD = max(0, Int(Double(max(stickyBottom, 0)) * scale))
        let templateHD = max(8, Int(Double(templateH) * scale))
        let templateStartD = max(stickyD, a.height - bottomD - templateHD)
        let contentEndD = a.height - bottomD

        let expectedY = max(stickyD, min(contentEndD - templateHD, Int((Double(h - guess - templateH) * scale).rounded())))
        let searchPad = max(12, Int(Double(h) * 0.12 * scale))
        let yMin = max(stickyD, expectedY - searchPad)
        let yMax = min(contentEndD - templateHD, expectedY + searchPad)
        guard yMax >= yMin else { return guess }

        let x0 = a.width / 12
        let x1 = a.width - x0
        var bestY = expectedY
        var bestScore = Double.greatestFiniteMagnitude

        for y in yMin...yMax {
            var acc = 0.0
            var n = 0
            var row = 0
            while row < templateHD {
                let ra = (templateStartD + row) * a.width
                let rb = (y + row) * b.width
                var x = x0
                while x < x1 {
                    acc += Double(abs(Int(a.bytes[ra + x]) - Int(b.bytes[rb + x])))
                    n += 1
                    x += 2
                }
                row += 1
            }
            guard n > 0 else { continue }
            // 略偏好接近 guess 的解，避免跳到重复纹理
            let score = acc / Double(n) + Double(abs(y - expectedY)) * 0.015
            if score < bestScore {
                bestScore = score
                bestY = y
            }
        }

        guard bestScore < 22 else { return guess }
        let matchedTop = Int((Double(bestY) / scale).rounded())
        // prev 底部 template 对齐到 curr 的 matchedTop → 新内容高度 = h - (matchedTop + templateH)
        let fresh = h - (matchedTop + templateH)
        let minFresh = 8
        let maxFresh = max(minFresh, h - stickyTop - max(stickyBottom, 2) - 2)
        return fresh.clamped(to: minFresh...maxFresh)
    }

    /// 拼到累计图时，用累计图底部与新帧再对一次缝
    private static func refineAppendCut(
        accumulated: TopDownImage,
        next: TopDownImage,
        stickyTop: Int,
        guessFresh: Int
    ) -> Int {
        let h = next.height
        let templateH = min(56, max(20, (h - stickyTop) / 6))
        guard accumulated.height >= templateH, h - stickyTop > templateH + 8 else {
            return min(max(guessFresh, 8), h - stickyTop - 2)
        }

        let aFull = accumulated
        let a = aFull.grayDownsample(targetWidth: 260)
        let b = next.grayDownsample(targetWidth: 260)
        guard a.width == b.width else {
            return min(max(guessFresh, 8), h - stickyTop - 2)
        }

        let scaleA = Double(a.height) / Double(aFull.height)
        let scaleB = Double(b.height) / Double(h)
        let templateHD = max(8, Int(Double(templateH) * scaleA))
        let templateStartD = max(0, a.height - templateHD)
        let stickyD = max(0, Int(Double(stickyTop) * scaleB))
        let expectedY = max(stickyD, min(b.height - templateHD, Int((Double(h - guessFresh - templateH) * scaleB).rounded())))
        let searchPad = max(10, Int(0.1 * Double(b.height)))
        let yMin = max(stickyD, expectedY - searchPad)
        let yMax = min(b.height - templateHD, expectedY + searchPad)
        guard yMax >= yMin else {
            return min(max(guessFresh, 8), h - stickyTop - 2)
        }

        let x0 = a.width / 12
        let x1 = min(a.width, b.width) - x0
        var bestY = expectedY
        var bestScore = Double.greatestFiniteMagnitude

        for y in yMin...yMax {
            var acc = 0.0
            var n = 0
            var row = 0
            while row < templateHD {
                let ra = (templateStartD + row) * a.width
                let rb = (y + row) * b.width
                var x = x0
                while x < x1 {
                    acc += Double(abs(Int(a.bytes[ra + x]) - Int(b.bytes[rb + x])))
                    n += 1
                    x += 2
                }
                row += 1
            }
            guard n > 0 else { continue }
            let score = acc / Double(n) + Double(abs(y - expectedY)) * 0.02
            if score < bestScore {
                bestScore = score
                bestY = y
            }
        }

        if bestScore < 24 {
            let matchedTop = Int((Double(bestY) / scaleB).rounded())
            let fresh = h - (matchedTop + templateH)
            return fresh.clamped(to: 8...(h - stickyTop - 2))
        }
        return min(max(guessFresh, 8), h - stickyTop - 2)
    }

    // MARK: - Analysis

    private static func detectStickyTop(previous: CGImage, current: CGImage) -> Int {
        let a = TopDownImage(cgImage: previous).grayDownsample(targetWidth: 200)
        let b = TopDownImage(cgImage: current).grayDownsample(targetWidth: 200)
        guard a.width == b.width, a.height == b.height, a.height > 40 else { return 0 }

        let x0 = a.width / 14
        let x1 = a.width - x0
        let scale = Double(a.height) / Double(previous.height)
        // 浏览器顶栏通常 < 140px；禁止扫到下方可滚动内容区
        let maxStickyPx = min(140, previous.height / 4)
        let limit = max(8, min(a.height - 1, Int(Double(maxStickyPx) * scale)))
        let threshold = 10.0

        var stickyRows = 0
        for y in 0..<limit {
            if rowMAD(a, b, y, y, x0, x1) <= threshold {
                stickyRows = y + 1
            } else if stickyRows >= 10 {
                break
            }
        }

        guard stickyRows >= 6 else { return 0 }
        return Int(Double(stickyRows) / scale) + 4
    }

    private static func detectStickyBottom(previous: CGImage, current: CGImage) -> Int {
        let a = TopDownImage(cgImage: previous).grayDownsample(targetWidth: 160)
        let b = TopDownImage(cgImage: current).grayDownsample(targetWidth: 160)
        guard a.width == b.width, a.height == b.height else { return 0 }

        let x0 = a.width / 14
        let x1 = a.width - x0
        let limit = min(a.height / 5, 60)
        let threshold = 6.5
        var stickyRows = 0
        var gap = 0

        for offset in 0..<limit {
            let y = a.height - 1 - offset
            if rowMAD(a, b, y, y, x0, x1) <= threshold {
                stickyRows = offset + 1
                gap = 0
            } else {
                gap += 1
                if stickyRows > 0, gap > 4 { break }
                if stickyRows == 0 { break }
            }
        }

        guard stickyRows >= 5 else { return 0 }
        let scale = Double(previous.height) / Double(a.height)
        return Int(Double(stickyRows) * scale)
    }

    private static func rowMAD(_ a: Gray, _ b: Gray, _ ya: Int, _ yb: Int, _ x0: Int, _ x1: Int) -> Double {
        var acc = 0.0
        var n = 0
        let ba = ya * a.width
        let bb = yb * b.width
        var x = x0
        while x < x1 {
            acc += Double(abs(Int(a.bytes[ba + x]) - Int(b.bytes[bb + x])))
            n += 1
            x += 2
        }
        return n > 0 ? acc / Double(n) : 999
    }

    private static func estimateShift(
        previous: CGImage,
        current: CGImage,
        stickyTop: Int,
        stickyBottom: Int
    ) -> Int? {
        let h = previous.height
        let top = stickyTop
        let bottom = max(stickyBottom, 2)
        let contentH = h - top - bottom
        guard contentH > 48 else { return nil }

        let minShift = max(12, contentH / 16)
        let maxShift = max(minShift + 4, Int(Double(contentH) * 0.72))

        let a = TopDownImage(cgImage: previous).grayDownsample(targetWidth: 260)
        let b = TopDownImage(cgImage: current).grayDownsample(targetWidth: 260)
        guard a.width == b.width, a.height == b.height else { return nil }

        let scale = Double(a.height) / Double(h)
        let topD = max(1, Int(Double(top) * scale))
        let bottomD = max(1, Int(Double(bottom) * scale))
        let minD = max(2, Int(Double(minShift) * scale))
        let maxD = min(a.height - topD - bottomD - 2, Int(Double(maxShift) * scale))
        guard maxD > minD else { return nil }

        let x0 = a.width / 10
        let x1 = a.width - x0
        var best = minD
        var bestScore = Double.greatestFiniteMagnitude

        for shiftD in stride(from: minD, through: maxD, by: 1) {
            let yEnd = a.height - bottomD - shiftD
            guard yEnd > topD else { continue }
            var acc = 0.0
            var n = 0
            var y = topD
            while y < yEnd {
                let ra = (y + shiftD) * a.width
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
                best = shiftD
            }
        }

        guard bestScore < 18 else { return nil }
        return Int((Double(best) / scale).rounded()).clamped(to: minShift...maxShift)
    }

    // MARK: - Capture / input

    @discardableResult
    static func ensureAccessibility(prompt: Bool = true) -> Bool {
        if AXIsProcessTrusted() { return true }
        if prompt {
            let opts = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary
            _ = AXIsProcessTrustedWithOptions(opts)
        }
        return AXIsProcessTrusted()
    }

    /// 滚动后等到画面静止再截，避免半动画帧造成接缝
    private static func captureStableSegment(
        displayID: CGDirectDisplayID,
        selectionRectInPoints: CGRect,
        targetSize: CGSize
    ) async throws -> CGImage {
        var last = try await captureSegment(
            displayID: displayID,
            selectionRectInPoints: selectionRectInPoints,
            targetSize: targetSize
        )
        for _ in 0..<3 {
            try await Task.sleep(nanoseconds: 90_000_000)
            let next = try await captureSegment(
                displayID: displayID,
                selectionRectInPoints: selectionRectInPoints,
                targetSize: targetSize
            )
            if nearlySame(a: last, b: next) { return next }
            last = next
        }
        return last
    }

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
        // 统一到目标尺寸，保证各帧宽高一致，便于对缝
        let tw = Int(targetSize.width)
        let th = Int(targetSize.height)
        if cropped.width == tw, cropped.height == th {
            return cropped
        }
        if abs(cropped.width - tw) <= 1, abs(cropped.height - th) <= 1 {
            return cropped
        }
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

    private static func scrollWheelPixels(at point: CGPoint, delta: Int32) {
        guard let event = CGEvent(
            scrollWheelEvent2Source: nil,
            units: .pixel,
            wheelCount: 1,
            wheel1: delta,
            wheel2: 0,
            wheel3: 0
        ) else { return }
        event.location = point
        event.post(tap: .cghidEventTap)
    }

    private static func nearlySame(a: CGImage, b: CGImage) -> Bool {
        let da = TopDownImage(cgImage: a).grayDownsample(targetWidth: 96)
        let db = TopDownImage(cgImage: b).grayDownsample(targetWidth: 96)
        guard da.width == db.width, da.height == db.height, !da.bytes.isEmpty else { return false }
        var acc = 0.0
        for i in 0..<da.bytes.count {
            acc += Double(abs(Int(da.bytes[i]) - Int(db.bytes[i])))
        }
        return (acc / Double(da.bytes.count)) < 5.0
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
        ctx.setShouldAntialias(false)
        ctx.draw(image, in: CGRect(x: 0, y: 0, width: w, height: h))
        return ctx.makeImage()!
    }
}

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
