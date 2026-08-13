import AppKit
import ScreenCaptureKit
import CoreGraphics

struct CapturedFrame {
    let image: CGImage
    let displayID: CGDirectDisplayID
    let bounds: CGRect // AppKit screen frame (points, bottom-left origin)
    let scale: CGFloat // pixels / point
}

enum ScreenCapturer {
    static func captureAllDisplays() async throws -> [CapturedFrame] {
        let content = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: true)
        var frames: [CapturedFrame] = []

        for display in content.displays {
            let nsScreen = NSScreen.screens.first { screen in
                let num = screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber
                return num?.uint32Value == display.displayID
            }
            let pointBounds = nsScreen?.frame
                ?? CGRect(x: 0, y: 0, width: CGFloat(display.width), height: CGFloat(display.height))
            let scale = nsScreen?.backingScaleFactor ?? 2.0

            // 按物理像素抓取，避免模糊/错位
            let pixelW = Int((pointBounds.width * scale).rounded())
            let pixelH = Int((pointBounds.height * scale).rounded())

            let filter = SCContentFilter(display: display, excludingWindows: [])
            let config = SCStreamConfiguration()
            config.width = max(pixelW, 1)
            config.height = max(pixelH, 1)
            config.showsCursor = false
            config.scalesToFit = false
            config.pixelFormat = kCVPixelFormatType_32BGRA
            config.colorSpaceName = CGColorSpace.sRGB

            let cgImage = try await SCScreenshotManager.captureImage(contentFilter: filter, configuration: config)
            let realScale = CGFloat(cgImage.width) / max(pointBounds.width, 1)
            frames.append(CapturedFrame(image: cgImage, displayID: display.displayID, bounds: pointBounds, scale: realScale))
        }

        if frames.isEmpty { throw CaptureError.noDisplay }
        return frames
    }

    static func captureDisplay(_ displayID: CGDirectDisplayID) async throws -> CapturedFrame {
        let content = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: true)
        guard let display = content.displays.first(where: { $0.displayID == displayID }) ?? content.displays.first else {
            throw CaptureError.noDisplay
        }

        let nsScreen = NSScreen.screens.first { screen in
            let num = screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber
            return num?.uint32Value == display.displayID
        }
        let pointBounds = nsScreen?.frame
            ?? CGRect(x: 0, y: 0, width: CGFloat(display.width), height: CGFloat(display.height))
        let scale = nsScreen?.backingScaleFactor ?? 2.0
        let pixelW = Int((pointBounds.width * scale).rounded())
        let pixelH = Int((pointBounds.height * scale).rounded())

        let filter = SCContentFilter(display: display, excludingWindows: [])
        let config = SCStreamConfiguration()
        config.width = max(pixelW, 1)
        config.height = max(pixelH, 1)
        config.showsCursor = false
        config.scalesToFit = false
        config.pixelFormat = kCVPixelFormatType_32BGRA
        config.colorSpaceName = CGColorSpace.sRGB

        let cgImage = try await SCScreenshotManager.captureImage(contentFilter: filter, configuration: config)
        let realScale = CGFloat(cgImage.width) / max(pointBounds.width, 1)
        return CapturedFrame(image: cgImage, displayID: display.displayID, bounds: pointBounds, scale: realScale)
    }

    static func captureWindow(id: CGWindowID) async throws -> (CGImage, CGFloat) {
        let content = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: true)
        if let scWindow = content.windows.first(where: { $0.windowID == id }) {
            let filter = SCContentFilter(desktopIndependentWindow: scWindow)
            let scale = NSScreen.main?.backingScaleFactor ?? 2.0
            let pixelW = max(Int((scWindow.frame.width * scale).rounded()), 1)
            let pixelH = max(Int((scWindow.frame.height * scale).rounded()), 1)
            let config = SCStreamConfiguration()
            config.width = pixelW
            config.height = pixelH
            config.showsCursor = false
            config.scalesToFit = false
            config.pixelFormat = kCVPixelFormatType_32BGRA
            let image = try await SCScreenshotManager.captureImage(contentFilter: filter, configuration: config)
            let realScale = CGFloat(image.width) / max(scWindow.frame.width, 1)
            return (image, realScale)
        }

        // 回退：旧 API
        if let image = CGWindowListCreateImage(.null, .optionIncludingWindow, id, [.boundsIgnoreFraming, .bestResolution]) {
            return (image, NSScreen.main?.backingScaleFactor ?? 2.0)
        }
        throw CaptureError.windowNotFound
    }

    enum CaptureError: LocalizedError {
        case noDisplay
        case cancelled
        case permissionDenied
        case windowNotFound

        var errorDescription: String? {
            switch self {
            case .noDisplay: return "未找到可用显示器"
            case .cancelled: return "已取消"
            case .permissionDenied: return "没有屏幕录制权限"
            case .windowNotFound: return "未找到目标窗口"
            }
        }
    }
}

enum WindowCapturer {
    struct WindowInfo: Identifiable {
        let id: CGWindowID
        let name: String
        let owner: String
        let bounds: CGRect // Quartz top-left global
        let layer: Int
    }

    static func listWindows() -> [WindowInfo] {
        guard let list = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID) as? [[String: Any]] else {
            return []
        }
        return list.compactMap { info in
            guard
                let id = info[kCGWindowNumber as String] as? CGWindowID,
                let boundsDict = info[kCGWindowBounds as String] as? [String: CGFloat],
                let layer = info[kCGWindowLayer as String] as? Int,
                layer == 0
            else { return nil }

            let bounds = CGRect(
                x: boundsDict["X"] ?? 0,
                y: boundsDict["Y"] ?? 0,
                width: boundsDict["Width"] ?? 0,
                height: boundsDict["Height"] ?? 0
            )
            guard bounds.width > 40, bounds.height > 40 else { return nil }

            let name = info[kCGWindowName as String] as? String ?? ""
            let owner = info[kCGWindowOwnerName as String] as? String ?? "Unknown"
            if owner == "Flare" || owner == "Flare Pro" || owner == "Snap" || owner == "Window Server" { return nil }
            return WindowInfo(id: id, name: name, owner: owner, bounds: bounds, layer: layer)
        }
    }
}
