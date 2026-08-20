import AppKit
import CoreGraphics
import Foundation

/// 模拟「浏览器固定顶栏 + 向下滚动内容」，跑真实 LongScreenshot.stitchFramesForTesting，
/// 断言顶栏颜色带在结果里只出现 1 次。
@main
enum StitchTest {
    static let width = 400
    static let height = 500
    static let chromeH = 90
    /// 顶栏用高对比红色，便于检测
    static let chromeRGB: (UInt8, UInt8, UInt8) = (220, 36, 36)
    static let shift = 140
    static let frameCount = 6

    static func main() {
        print("==> Long screenshot stitch test")
        print("    frames=\(frameCount) chromeH=\(chromeH) shift=\(shift)")

        var frames: [CGImage] = []
        for i in 0..<frameCount {
            frames.append(makeFrame(scrollOffset: i * shift))
        }

        let dir = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
            .appendingPathComponent(".build-stitch-test")
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)

        for (i, f) in frames.enumerated() {
            save(f, to: dir.appendingPathComponent(String(format: "frame_%02d.png", i)))
        }

        let stitched = LongScreenshot.stitchFramesForTesting(frames)
        let outURL = dir.appendingPathComponent("stitched.png")
        save(stitched, to: outURL)

        // 自检：源帧 row340 应是内容色，不是顶栏红
        let rep0 = NSBitmapImageRep(cgImage: frames[0])
        let top = rep0.colorAt(x: 200, y: 0)!
        let mid = rep0.colorAt(x: 200, y: 340)!
        print("    frame0 top RGB=(\(Int(top.redComponent*255)),\(Int(top.greenComponent*255)),\(Int(top.blueComponent*255))) row340=(\(Int(mid.redComponent*255)),\(Int(mid.greenComponent*255)),\(Int(mid.blueComponent*255)))")

        print("    output: \(outURL.path) (\(stitched.width)x\(stitched.height))")

        let chromeHits = countChromeBands(in: stitched)
        let chromeBelowHeader = countChromeRows(in: stitched, belowY: chromeH + 10)
        print("    chrome band hits: \(chromeHits)")
        print("    chrome rows below header: \(chromeBelowHeader)")

        let expectedMinH = height + (frameCount - 1) * (shift / 2)
        if stitched.height < expectedMinH {
            fputs("FAIL: stitched height \(stitched.height) too short (expected >= \(expectedMinH))\n", stderr)
            exit(1)
        }

        if chromeBelowHeader > 0 {
            fputs("FAIL: repeated chrome below header (\(chromeBelowHeader) rows)\n", stderr)
            exit(1)
        }

        if chromeHits != 1 {
            fputs("FAIL: browser chrome should appear exactly once, got \(chromeHits)\n", stderr)
            exit(1)
        }

        // 内容应随滚动变长，且不应几乎等于 N 倍整帧（那是傻叠）
        let naiveStack = height * frameCount
        if stitched.height > Int(Double(naiveStack) * 0.92) {
            fputs("FAIL: height \(stitched.height) looks like full-frame stacking (naive=\(naiveStack))\n", stderr)
            exit(1)
        }

        print("✅ PASS: stitch removes repeated chrome and grows content")
    }

    /// 顶栏固定；内容区按 scrollOffset 画不同色带
    static func makeFrame(scrollOffset: Int) -> CGImage {
        let cs = CGColorSpaceCreateDeviceRGB()
        let ctx = CGContext(
            data: nil,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: 0,
            space: cs,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        )!

        // CG y=0 在底部。先画内容（整幅），再盖顶栏
        let bandH = 40
        var yContent = 0
        while yContent < height {
            let logicalTopDown = height - yContent - bandH
            let contentIndex = (logicalTopDown + scrollOffset) / bandH
            let color = bandColor(contentIndex)
            ctx.setFillColor(CGColor(srgbRed: color.0, green: color.1, blue: color.2, alpha: 1))
            ctx.fill(CGRect(x: 0, y: yContent, width: width, height: bandH))
            yContent += bandH
        }

        // 顶栏：视觉顶部 = CG 高 y
        ctx.setFillColor(CGColor(
            srgbRed: CGFloat(chromeRGB.0) / 255,
            green: CGFloat(chromeRGB.1) / 255,
            blue: CGFloat(chromeRGB.2) / 255,
            alpha: 1
        ))
        ctx.fill(CGRect(x: 0, y: height - chromeH, width: width, height: chromeH))

        // 顶栏里画一条深色线，模拟地址栏
        ctx.setFillColor(CGColor(srgbRed: 0.15, green: 0.05, blue: 0.05, alpha: 1))
        ctx.fill(CGRect(x: 20, y: height - chromeH + 35, width: width - 40, height: 18))

        return ctx.makeImage()!
    }

    static func bandColor(_ index: Int) -> (CGFloat, CGFloat, CGFloat) {
        let palette: [(CGFloat, CGFloat, CGFloat)] = [
            (0.85, 0.95, 0.88),
            (0.75, 0.88, 0.95),
            (0.95, 0.90, 0.75),
            (0.88, 0.80, 0.95),
            (0.70, 0.92, 0.80),
            (0.92, 0.78, 0.78),
            (0.78, 0.85, 0.70),
            (0.80, 0.80, 0.92)
        ]
        return palette[((index % palette.count) + palette.count) % palette.count]
    }

    static func rowIsChrome(in rep: NSBitmapImageRep, y: Int) -> Bool {
        var hit = 0, n = 0
        var x = 0
        while x < rep.pixelsWide {
            let c = rep.colorAt(x: x, y: y)!
            let r = Int(c.redComponent * 255)
            let g = Int(c.greenComponent * 255)
            let b = Int(c.blueComponent * 255)
            if abs(r - Int(chromeRGB.0)) < 30,
               abs(g - Int(chromeRGB.1)) < 30,
               abs(b - Int(chromeRGB.2)) < 30 {
                hit += 1
            }
            n += 1
            x += 2
        }
        return n > 0 && Double(hit) / Double(n) > 0.72
    }

    static func countChromeRows(in image: CGImage, belowY: Int) -> Int {
        let rep = NSBitmapImageRep(cgImage: image)
        var hits = 0
        for y in belowY..<rep.pixelsHigh where rowIsChrome(in: rep, y: y) {
            hits += 1
        }
        return hits
    }

    /// 统计「整行几乎全是顶栏红」的连续色带数量（分隔的块数）
    static func countChromeBands(in image: CGImage) -> Int {
        let rep = NSBitmapImageRep(cgImage: image)
        let h = rep.pixelsHigh

        var bands = 0
        var inBand = false
        var bandLen = 0
        var gap = 0
        let mergeGap = max(20, chromeH / 2) // 地址栏细线可能打断顶栏
        for y in 0..<h {
            if rowIsChrome(in: rep, y: y) {
                if !inBand, gap > 0, gap <= mergeGap, bandLen >= max(10, chromeH / 3) {
                    bandLen += gap + 1
                } else if !inBand {
                    bandLen = 0
                }
                bandLen += 1
                inBand = true
                gap = 0
            } else if inBand {
                gap += 1
                if gap > mergeGap {
                    if bandLen >= max(10, chromeH / 3) { bands += 1 }
                    inBand = false
                    bandLen = 0
                    gap = 0
                }
            }
        }
        if inBand, bandLen >= max(10, chromeH / 3) { bands += 1 }
        return bands
    }

    static func save(_ image: CGImage, to url: URL) {
        let rep = NSBitmapImageRep(cgImage: image)
        let data = rep.representation(using: .png, properties: [:])
        try? data?.write(to: url)
    }
}
