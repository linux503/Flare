import AppKit
import Combine

final class CaptureCoordinator: ObservableObject {
    static let shared = CaptureCoordinator()

    @Published private(set) var isCapturing = false

    private var overlayControllers: [CaptureOverlayController] = []
    private var hiddenWindows: [NSWindow] = []
    private var suppressHomeUntil = Date.distantPast

    /// 截图层关掉后系统可能触发 reopen，短时间内不要弹出主界面
    var shouldSuppressHomeReveal: Bool {
        isCapturing || Date() < suppressHomeUntil
    }

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
        guard Permissions.prepareForCapture() else { return }
        guard !isCapturing else { return }
        if ScreenRecorder.shared.isRecording {
            ToastController.shared.show("请先停止录屏")
            return
        }

        let targetDisplayID = resolveTargetDisplayID()
        isCapturing = true
        suppressHomeUntil = Date().addingTimeInterval(4)
        resignForCapture()

        Task {
            try await Task.sleep(nanoseconds: 280_000_000)
            do {
                let frame = try await ScreenCapturer.captureDisplay(targetDisplayID, excludeSelf: true)
                await MainActor.run {
                    Permissions.markCaptureSucceeded()
                    self.finish(with: frame.image, scale: frame.scale)
                }
            } catch {
                await MainActor.run {
                    self.endCaptureSession(restoreHome: false)
                    Permissions.handleCaptureFailure(error: error)
                }
            }
        }
    }

    func startDelayedCapture(seconds: Int) {
        guard Permissions.prepareForCapture() else { return }
        guard !isCapturing else { return }
        if ScreenRecorder.shared.isRecording {
            ToastController.shared.show("请先停止录屏")
            return
        }
        let targetDisplayID = resolveTargetDisplayID()
        isCapturing = true
        suppressHomeUntil = Date().addingTimeInterval(Double(seconds) + 4)
        hideFlareWindows()
        DelayOverlayController.shared.start(seconds: seconds) { [weak self] in
            guard let self else { return }
            self.resignForCapture()
            Task {
                try await Task.sleep(nanoseconds: 180_000_000)
                do {
                    let frame = try await ScreenCapturer.captureDisplay(targetDisplayID, excludeSelf: true)
                    await MainActor.run {
                        Permissions.markCaptureSucceeded()
                        self.finish(with: frame.image, scale: frame.scale)
                    }
                } catch {
                    await MainActor.run {
                        self.endCaptureSession(restoreHome: false)
                        Permissions.handleCaptureFailure(error: error)
                    }
                }
            }
        } onCancel: { [weak self] in
            self?.endCaptureSession(restoreHome: true)
        }
    }

    func cancelCapture() {
        dismissOverlays()
        endCaptureSession(restoreHome: true)
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
                        self.endCaptureSession(restoreHome: true)
                        Permissions.handleCaptureFailure(error: error)
                    }
                }
            }
        }
    }

    private func captureActiveDisplay() async throws -> CapturedFrame {
        try await ScreenCapturer.captureDisplay(resolveTargetDisplayID(), excludeSelf: true)
    }

    /// 全屏/延时截图：优先截前台应用所在显示器，避免在 Flare 界面里误截另一块屏或桌面
    private func resolveTargetDisplayID() -> CGDirectDisplayID {
        if let screen = screenForFrontmostExternalApp() ?? screenUnderMouse() {
            return displayID(for: screen) ?? CGMainDisplayID()
        }
        return CGMainDisplayID()
    }

    private func screenUnderMouse() -> NSScreen? {
        let mouse = NSEvent.mouseLocation
        return NSScreen.screens.first { NSMouseInRect(mouse, $0.frame, false) } ?? NSScreen.main
    }

    private func displayID(for screen: NSScreen) -> CGDirectDisplayID? {
        (screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber)?.uint32Value
    }

    private func screenForFrontmostExternalApp() -> NSScreen? {
        guard let front = NSWorkspace.shared.frontmostApplication,
              front.bundleIdentifier != Bundle.main.bundleIdentifier else { return nil }

        guard let list = CGWindowListCopyWindowInfo([.optionOnScreenOnly], kCGNullWindowID) as? [[String: Any]] else {
            return nil
        }

        let pid = front.processIdentifier
        var best: CGRect?
        var bestArea: CGFloat = 0
        for info in list {
            guard
                let ownerPID = info[kCGWindowOwnerPID as String] as? pid_t,
                ownerPID == pid,
                let layer = info[kCGWindowLayer as String] as? Int,
                layer == 0,
                let boundsDict = info[kCGWindowBounds as String] as? [String: CGFloat]
            else { continue }

            let bounds = CGRect(
                x: boundsDict["X"] ?? 0,
                y: boundsDict["Y"] ?? 0,
                width: boundsDict["Width"] ?? 0,
                height: boundsDict["Height"] ?? 0
            )
            guard bounds.width > 80, bounds.height > 80 else { continue }
            let area = bounds.width * bounds.height
            if area > bestArea {
                bestArea = area
                best = bounds
            }
        }

        guard let rect = best else { return nil }
        let globalMaxY = NSScreen.screens.map(\.frame.maxY).max() ?? 0
        let appKitPoint = CGPoint(x: rect.midX, y: globalMaxY - rect.midY)
        return NSScreen.screens.first { NSMouseInRect(appKitPoint, $0.frame, false) }
    }

    /// 截图前隐藏 Flare 并尽量把焦点还给用户正在用的应用，避免截到 Flare 自己的界面
    private func resignForCapture() {
        hideFlareWindows()
        let front = NSWorkspace.shared.frontmostApplication
        NSApp.hide(nil)
        if let front,
           front.bundleIdentifier != Bundle.main.bundleIdentifier,
           front.activationPolicy == .regular {
            front.activate(options: [])
        }
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
        if !LongScreenshot.ensureAccessibility(prompt: true) {
            endCaptureSession(restoreHome: true)
            ToastController.shared.show("请在系统设置中打开「辅助功能」权限后再试长截图")
            NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")!)
            return
        }
        ToastController.shared.show("正在长截图…按 Esc 取消")
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
                    self.endCaptureSession(restoreHome: true)
                    if let err = error as? LongScreenshot.Error {
                        switch err {
                        case .cancelled:
                            ToastController.shared.show("已取消长截图")
                        case .needsAccessibility:
                            ToastController.shared.show("长截图需要「辅助功能」权限")
                        case .noSegment:
                            ToastController.shared.show("未能截取到可滚动内容，请对准网页或列表后再试")
                        }
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
                    self.endCaptureSession(restoreHome: true)
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

    private func restoreFlareWindows(includingHome: Bool) {
        for window in hiddenWindows {
            if !includingHome, HomeWindowController.isHomeWindow(window) {
                continue
            }
            window.orderFront(nil)
        }
        hiddenWindows.removeAll()
    }

    private func endCaptureSession(restoreHome: Bool) {
        isCapturing = false
        suppressHomeUntil = Date().addingTimeInterval(1.5)
        restoreFlareWindows(includingHome: restoreHome)
    }

    private func finish(with cgImage: CGImage, scale: CGFloat, action: CaptureFinishAction = .useSettings) {
        endCaptureSession(restoreHome: false)
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
            } catch {
                ToastController.shared.show("保存失败，已保留到历史")
                HistoryStore.shared.add(image: image)
            }
            StatusBarController.shared?.reloadMenu()
            return
        case .pin:
            PinWindowController.shared.pin(image: image)
        }

        HistoryStore.shared.add(image: image)
        DispatchQueue.main.async {
            StatusBarController.shared?.reloadMenu()
        }
    }

}
