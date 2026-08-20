import AppKit
import Combine

final class CaptureCoordinator: ObservableObject {
    static let shared = CaptureCoordinator()

    @Published private(set) var isCapturing = false

    private var overlayControllers: [CaptureOverlayController] = []
    private var hiddenWindows: [NSWindow] = []

    private init() {}

    func startAreaCapture() {
        beginCapture {
            let frames = try await ScreenCapturer.captureAllDisplays()
            await MainActor.run { self.presentAreaOverlays(frames: frames) }
        }
    }

    /// 长截图：自动滚动 + 多段拼接
    func startLongAreaCapture() {
        beginCapture {
            let frames = try await ScreenCapturer.captureAllDisplays()
            await MainActor.run { self.presentLongOverlays(frames: frames) }
        }
    }

    func startWindowCapture() {
        beginCapture {
            let frames = try await ScreenCapturer.captureAllDisplays()
            await MainActor.run { self.presentWindowOverlays(frames: frames) }
        }
    }

    func startFullScreenCapture() {
        beginCapture {
            let frame = try await self.captureActiveDisplay()
            await MainActor.run { self.finish(with: frame.image, scale: frame.scale) }
        }
    }

    func startDelayedCapture(seconds: Int) {
        guard Permissions.prepareForCapture() else { return }
        guard !isCapturing else { return }
        if ScreenRecorder.shared.isRecording {
            ToastController.shared.show("请先停止录屏")
            return
        }
        isCapturing = true
        hideFlareWindows()
        DelayOverlayController.shared.start(seconds: seconds) { [weak self] in
            guard let self else { return }
            Task {
                do {
                    let frame = try await self.captureActiveDisplay()
                    Permissions.markCaptureSucceeded()
                    await MainActor.run { self.finish(with: frame.image, scale: frame.scale) }
                } catch {
                    await MainActor.run {
                        self.restoreFlareWindows()
                        self.isCapturing = false
                        Permissions.handleCaptureFailure(error: error)
                    }
                }
            }
        } onCancel: { [weak self] in
            self?.restoreFlareWindows()
            self?.isCapturing = false
        }
    }

    func cancelCapture() {
        dismissOverlays()
        restoreFlareWindows()
        isCapturing = false
    }

    private func beginCapture(_ work: @escaping () async throws -> Void) {
        guard Permissions.prepareForCapture() else { return }
        guard !isCapturing else { return }
        if ScreenRecorder.shared.isRecording {
            ToastController.shared.show("请先停止录屏")
            return
        }

        isCapturing = true
        hideFlareWindows()
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
            Task {
                do {
                    try await work()
                    Permissions.markCaptureSucceeded()
                } catch {
                    await MainActor.run {
                        self.restoreFlareWindows()
                        self.isCapturing = false
                        Permissions.handleCaptureFailure(error: error)
                    }
                }
            }
        }
    }

    private func captureActiveDisplay() async throws -> CapturedFrame {
        let mouse = NSEvent.mouseLocation
        let screen = NSScreen.screens.first { NSMouseInRect(mouse, $0.frame, false) } ?? NSScreen.main
        let displayID = (screen?.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber)?.uint32Value ?? CGMainDisplayID()
        return try await ScreenCapturer.captureDisplay(displayID)
    }

    private func presentAreaOverlays(frames: [CapturedFrame]) {
        dismissOverlays()
        let windows = WindowCapturer.listWindows()
        overlayControllers = frames.map { frame in
            let controller = CaptureOverlayController(frame: frame, mode: .area, windows: windows)
            controller.onCancel = { [weak self] in self?.cancelCapture() }
            controller.onAreaSelected = { [weak self] image, scale, action in
                self?.completeArea(cgImage: image, scale: scale, action: action)
            }
            controller.show()
            return controller
        }
    }

    private func presentLongOverlays(frames: [CapturedFrame]) {
        dismissOverlays()
        let windows = WindowCapturer.listWindows()
        overlayControllers = frames.map { frame in
            let controller = CaptureOverlayController(frame: frame, mode: .longArea, windows: windows)
            controller.onCancel = { [weak self] in self?.cancelCapture() }
            controller.onLongAreaSelected = { [weak self] displayID, displayBounds, selectionRect, selectionScale in
                self?.completeLongArea(
                    displayID: displayID,
                    displayBoundsInPoints: displayBounds,
                    selectionRectInPoints: selectionRect,
                    selectionScale: selectionScale
                )
            }
            controller.show()
            return controller
        }
    }

    private func presentWindowOverlays(frames: [CapturedFrame]) {
        dismissOverlays()
        let windows = WindowCapturer.listWindows()
        overlayControllers = frames.map { frame in
            let controller = CaptureOverlayController(frame: frame, mode: .window, windows: windows)
            controller.onCancel = { [weak self] in self?.cancelCapture() }
            controller.onWindowSelected = { [weak self] windowID in
                self?.completeWindow(id: windowID)
            }
            controller.show()
            return controller
        }
    }

    private func completeArea(cgImage: CGImage, scale: CGFloat, action: CaptureFinishAction) {
        dismissOverlays()
        finish(with: cgImage, scale: scale, action: action)
    }

    private func completeLongArea(
        displayID: CGDirectDisplayID,
        displayBoundsInPoints: CGRect,
        selectionRectInPoints: CGRect,
        selectionScale: CGFloat
    ) {
        dismissOverlays()
        Task {
            do {
                let cgImage = try await LongScreenshot.capture(
                    session: .init(
                        displayID: displayID,
                        displayBoundsInPoints: displayBoundsInPoints,
                        selectionRectInPoints: selectionRectInPoints,
                        displayScale: selectionScale
                    )
                )
                await MainActor.run {
                    self.finish(with: cgImage, scale: selectionScale)
                }
            } catch {
                await MainActor.run {
                    self.restoreFlareWindows()
                    self.isCapturing = false
                    if let err = error as? LongScreenshot.Error, err == .cancelled {
                        ToastController.shared.show("已取消长截图")
                    } else {
                        Permissions.handleCaptureFailure(error: error)
                    }
                }
            }
        }
    }

    private func completeWindow(id: CGWindowID) {
        dismissOverlays()
        Task {
            do {
                let (image, scale) = try await ScreenCapturer.captureWindow(id: id)
                await MainActor.run { self.finish(with: image, scale: scale) }
            } catch {
                await MainActor.run {
                    self.restoreFlareWindows()
                    self.isCapturing = false
                    Permissions.handleCaptureFailure(error: error)
                }
            }
        }
    }

    private func dismissOverlays() {
        overlayControllers.forEach { $0.close() }
        overlayControllers.removeAll()
    }

    private func hideFlareWindows() {
        hiddenWindows = NSApp.windows.filter { $0.isVisible && $0.level != .screenSaver && $0.level != .statusBar }
        hiddenWindows.forEach { $0.orderOut(nil) }
    }

    private func restoreFlareWindows() {
        for window in hiddenWindows {
            window.orderFront(nil)
        }
        hiddenWindows.removeAll()
    }

    private func finish(with cgImage: CGImage, scale: CGFloat, action: CaptureFinishAction = .useSettings) {
        isCapturing = false
        restoreFlareWindows()
        SoundPlayer.playShutter()
        let image = ImageExporter.nsImage(from: cgImage, scale: scale)

        if action == .ocr {
            HistoryStore.shared.add(image: image)
            DispatchQueue.main.async { StatusBarController.shared?.reloadMenu() }
            ToastController.shared.show("正在识别文字…")
            Task {
                do {
                    let url = try await TextFileService.createTXTFromOCR(image: image, askWhere: true)
                    await MainActor.run {
                        ToastController.shared.show("已保存 \(url.lastPathComponent)")
                        TextFileService.reveal(url)
                    }
                } catch {
                    await MainActor.run {
                        if (error as? TextFileService.TextFileError) != .cancelled {
                            ToastController.shared.show("OCR 导出失败")
                        }
                    }
                }
            }
            return
        }

        let resolved: AfterCaptureAction
        switch action {
        case .useSettings: resolved = AppSettings.shared.afterCaptureAction
        case .editor: resolved = .editor
        case .clipboard: resolved = .clipboard
        case .save: resolved = .save
        case .pin: resolved = .pin
        case .ocr: resolved = .editor // unreachable
        }

        // 先完成动作，历史缩略图后台写入，避免截完卡顿
        switch resolved {
        case .editor:
            if AppSettings.shared.copyToClipboard {
                ImageExporter.copyToClipboard(image)
            }
            EditorWindowController.shared.present(image: image)
        case .clipboard:
            ImageExporter.copyToClipboard(image)
            ToastController.shared.show("已复制到剪贴板")
        case .save:
            do {
                let url = try ImageExporter.save(image)
                if AppSettings.shared.copyToClipboard {
                    ImageExporter.copyToClipboard(image)
                }
                ToastController.shared.show("已保存：\(url.lastPathComponent)")
                HistoryStore.shared.add(image: image, fileURL: url)
                StatusBarController.shared?.reloadMenu()
                return
            } catch {
                ToastController.shared.show("保存失败")
            }
        case .pin:
            PinWindowController.shared.pin(image: image)
        }

        HistoryStore.shared.add(image: image)
        DispatchQueue.main.async {
            StatusBarController.shared?.reloadMenu()
        }
    }

}
