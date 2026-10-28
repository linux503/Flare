import AppKit

/// 区域 / 窗口录屏：先框选或点选窗口，再回调 SCK 用的 sourceRect（显示器坐标，左上原点）
enum RecordAreaPicker {
    struct Selection {
        let sourceRect: CGRect
        let displayID: CGDirectDisplayID
        let scale: CGFloat
        let windowID: CGWindowID?
    }

    static func pick(
        windowOnly: Bool = false,
        onPicked: @escaping (Selection) -> Void,
        onCancel: @escaping () -> Void
    ) {
        guard Permissions.prepareForCapture() else {
            onCancel()
            return
        }
        Task {
            do {
                let frames = try await ScreenCapturer.captureActiveDisplay()
                await MainActor.run {
                    present(frames: frames, windowOnly: windowOnly, onPicked: onPicked, onCancel: onCancel)
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
        windowOnly: Bool,
        onPicked: @escaping (Selection) -> Void,
        onCancel: @escaping () -> Void
    ) {
        final class Holder {
            var controllers: [CaptureOverlayController] = []
        }
        let holder = Holder()
        let windows = WindowCapturer.listWindows()

        let cleanup = {
            let list = holder.controllers
            holder.controllers.removeAll()
            for c in list {
                c.onCancel = nil
                c.onRecordAreaConfirmed = nil
                c.onWindowSelected = nil
                c.close()
            }
        }

        for frame in frames {
            let controller = CaptureOverlayController(
                frame: frame,
                mode: windowOnly ? .window : .recordArea,
                windows: windows
            )
            controller.onCancel = {
                cleanup()
                onCancel()
            }
            if windowOnly {
                controller.onWindowSelected = { windowID in
                    cleanup()
                    onPicked(Selection(
                        sourceRect: CGRect(x: 0, y: 0, width: 100, height: 100),
                        displayID: frame.displayID,
                        scale: frame.scale,
                        windowID: windowID
                    ))
                }
            } else {
                controller.onRecordAreaConfirmed = { viewRect, windowID in
                    cleanup()
                    guard let selection = makeSelection(viewRect: viewRect, frame: frame, windowID: windowID) else {
                        ToastController.shared.show("选区无效，请重试")
                        onCancel()
                        return
                    }
                    onPicked(selection)
                }
            }
            holder.controllers.append(controller)
            controller.show()
        }
    }

    ///  overlay 视图坐标 → 显示器 sourceRect（SCK 左上原点）
    private static func makeSelection(
        viewRect: CGRect,
        frame: CapturedFrame,
        windowID: CGWindowID?
    ) -> Selection? {
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
        return Selection(
            sourceRect: sourceRect,
            displayID: frame.displayID,
            scale: frame.scale,
            windowID: windowID
        )
    }
}
