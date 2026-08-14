import AppKit

/// 区域录屏：先框选，再回调 SCK 用的 sourceRect（显示器坐标，左上原点）
enum RecordAreaPicker {
    struct Selection {
        let sourceRect: CGRect
        let displayID: CGDirectDisplayID
        let scale: CGFloat
    }

    static func pick(
        onPicked: @escaping (Selection) -> Void,
        onCancel: @escaping () -> Void
    ) {
        guard Permissions.prepareForCapture() else {
            onCancel()
            return
        }
        Task {
            do {
                let frames = try await ScreenCapturer.captureAllDisplays()
                await MainActor.run {
                    present(frames: frames, onPicked: onPicked, onCancel: onCancel)
                }
            } catch {
                await MainActor.run {
                    Permissions.handleCaptureFailure(error: error)
                    onCancel()
                }
            }
        }
    }

    private static func present(
        frames: [CapturedFrame],
        onPicked: @escaping (Selection) -> Void,
        onCancel: @escaping () -> Void
    ) {
        var controllers: [CaptureOverlayController] = []
        for frame in frames {
            let controller = CaptureOverlayController(frame: frame, mode: .recordArea)
            controller.onCancel = {
                controllers.forEach { $0.close() }
                controllers.removeAll()
                onCancel()
            }
            controller.onRecordAreaConfirmed = { viewRect in
                controllers.forEach { $0.close() }
                controllers.removeAll()
                guard let selection = makeSelection(viewRect: viewRect, frame: frame) else {
                    ToastController.shared.show("选区无效，请重试")
                    onCancel()
                    return
                }
                onPicked(selection)
            }
            controllers.append(controller)
            controller.show()
        }
    }

    ///  overlay 视图坐标 → 显示器 sourceRect（SCK 左上原点）
    private static func makeSelection(viewRect: CGRect, frame: CapturedFrame) -> Selection? {
        guard viewRect.width > 4, viewRect.height > 4 else { return nil }
        let displayFrame = frame.bounds
        let globalMinX = displayFrame.minX + viewRect.minX
        let globalMinY = displayFrame.minY + viewRect.minY
        let globalRect = CGRect(
            x: globalMinX,
            y: globalMinY,
            width: viewRect.width,
            height: viewRect.height
        )
        let relX = globalRect.minX - displayFrame.minX
        let relY = displayFrame.maxY - globalRect.maxY
        let sourceRect = CGRect(x: relX, y: relY, width: globalRect.width, height: globalRect.height)
        return Selection(sourceRect: sourceRect, displayID: frame.displayID, scale: frame.scale)
    }
}
