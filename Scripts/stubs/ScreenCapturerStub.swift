import CoreGraphics

struct CapturedFrame {
    let image: CGImage
    let displayID: CGDirectDisplayID
    let bounds: CGRect
    let scale: CGFloat
}

enum ScreenCapturer {
    static func captureDisplay(_ displayID: CGDirectDisplayID, excludeSelf: Bool = true) async throws -> CapturedFrame {
        fatalError("ScreenCapturer stub — stitch test only")
    }
}
