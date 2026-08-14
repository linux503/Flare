import AppKit
import AVFoundation
import Combine
import CoreMedia
import ScreenCaptureKit

/// 全屏屏幕录制（ScreenCaptureKit → H.264 MOV）
final class ScreenRecorder: NSObject, ObservableObject {
    static let shared = ScreenRecorder()

    @Published private(set) var isRecording = false
    @Published private(set) var isPaused = false
    @Published private(set) var isCountingDown = false
    @Published private(set) var elapsedSeconds: Int = 0

    private var stream: SCStream?
    private var writer: AVAssetWriter?
    private var videoInput: AVAssetWriterInput?
    private var audioInput: AVAssetWriterInput?
    private var adaptor: AVAssetWriterInputPixelBufferAdaptor?
    private var outputURL: URL?
    private var sessionStarted = false
    private var firstPTS: CMTime?
    private var pausedDuration: CMTime = .zero
    private var pauseStartedAt: CMTime?
    private var timer: Timer?
    private var startedAt: Date?
    private var pausedAccumulated: TimeInterval = 0
    private var pauseWallClock: Date?
    private let writingQueue = DispatchQueue(label: "app.flare.recorder.write")
    private let audioQueue = DispatchQueue(label: "app.flare.recorder.audio")
    private var pendingCountdown = false
    private var pendingPlan: RecordPlan?
    private var capturesSystemAudio = false

    private struct RecordPlan {
        let displayID: CGDirectDisplayID
        let sourceRect: CGRect?
        let displayScale: CGFloat
        let pointWidth: CGFloat
        let pointHeight: CGFloat
        let isArea: Bool
    }

    private override init() {
        super.init()
    }

    var recordingsDirectory: URL {
        AppSettings.shared.recordDirectory
    }

    /// 开始 / 停止切换
    func toggle() {
        if isRecording || isCountingDown {
            stop()
        } else {
            start()
        }
    }

    func start(countdown: Bool? = nil) {
        switch AppSettings.shared.recordMode {
        case .fullScreen:
            startFullScreen(countdown: countdown)
        case .area:
            startArea(countdown: countdown)
        }
    }

    func startFullScreen(countdown: Bool? = nil) {
        pendingPlan = nil
        DispatchQueue.main.async {
            self.startOnMain(countdown: countdown)
        }
    }

    func startArea(countdown: Bool? = nil) {
        guard !isRecording, !isCountingDown else { return }
        guard !CaptureCoordinator.shared.isCapturing else {
            ToastController.shared.show("请先结束截图再录屏")
            return
        }
        RecordAreaPicker.pick(
            onPicked: { [weak self] selection in
                guard let self else { return }
                self.pendingPlan = RecordPlan(
                    displayID: selection.displayID,
                    sourceRect: selection.sourceRect,
                    displayScale: selection.scale,
                    pointWidth: selection.sourceRect.width,
                    pointHeight: selection.sourceRect.height,
                    isArea: true
                )
                self.startOnMain(countdown: countdown)
            },
            onCancel: {}
        )
    }

    func stop() {
        DispatchQueue.main.async {
            if self.isCountingDown {
                self.cancelCountdown()
                return
            }
            guard self.isRecording else { return }
            Task { await self.finishRecording(discard: false) }
        }
    }

    func cancelAndDiscard() {
        DispatchQueue.main.async {
            if self.isCountingDown {
                self.cancelCountdown()
                return
            }
            guard self.isRecording else { return }
            Task { await self.finishRecording(discard: true) }
        }
    }

    func togglePause() {
        DispatchQueue.main.async {
            guard self.isRecording else { return }
            if self.isPaused {
                self.resumeRecording()
            } else {
                self.pauseRecording()
            }
        }
    }

    func openRecordingsFolder() {
        let dir = recordingsDirectory
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        NSWorkspace.shared.open(dir)
    }

    // MARK: - Private

    private func startOnMain(countdown: Bool?) {
        guard !isRecording, !isCountingDown else { return }
        guard !CaptureCoordinator.shared.isCapturing else {
            ToastController.shared.show("请先结束截图再录屏")
            return
        }

        let useCountdown = countdown ?? (AppSettings.shared.recordCountdownSeconds > 0)
        let seconds = max(0, AppSettings.shared.recordCountdownSeconds)
        if useCountdown, seconds > 0 {
            beginCountdown(seconds: seconds)
            return
        }

        Task {
            do {
                try await beginRecording()
            } catch {
                await MainActor.run {
                    Permissions.handleCaptureFailure(error: error)
                    ToastController.shared.show("无法开始录屏：\(error.localizedDescription)")
                    self.cleanup(failed: true)
                }
            }
        }
    }

    private func beginCountdown(seconds: Int) {
        isCountingDown = true
        pendingCountdown = true
        MainMenuController.shared?.reload()
        StatusBarController.shared?.refreshRecordingAppearance()
        ToastController.shared.show("\(seconds) 秒后开始录屏…")
        DelayOverlayController.shared.start(seconds: seconds, onFire: { [weak self] in
            guard let self else { return }
            self.isCountingDown = false
            self.pendingCountdown = false
            Task {
                do {
                    try await self.beginRecording()
                } catch {
                    await MainActor.run {
                        Permissions.handleCaptureFailure(error: error)
                        ToastController.shared.show("无法开始录屏：\(error.localizedDescription)")
                        self.cleanup(failed: true)
                        MainMenuController.shared?.reload()
                        StatusBarController.shared?.refreshRecordingAppearance()
                    }
                }
            }
        }, onCancel: { [weak self] in
            self?.cancelCountdown()
        })
    }

    private func cancelCountdown() {
        DelayOverlayController.shared.cancelExternal()
        isCountingDown = false
        pendingCountdown = false
        ToastController.shared.show("已取消录屏倒计时")
        MainMenuController.shared?.reload()
        StatusBarController.shared?.refreshRecordingAppearance()
    }

    private func beginRecording() async throws {
        let content = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: true)

        let plan: RecordPlan
        if let pending = pendingPlan {
            plan = pending
            pendingPlan = nil
        } else {
            let mouse = NSEvent.mouseLocation
            let screen = NSScreen.screens.first { NSMouseInRect(mouse, $0.frame, false) } ?? NSScreen.main
            let displayID = (screen?.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber)?.uint32Value
                ?? CGMainDisplayID()
            let scale = screen?.backingScaleFactor ?? 2.0
            let pointW = screen?.frame.width ?? 1920
            let pointH = screen?.frame.height ?? 1080
            plan = RecordPlan(
                displayID: displayID,
                sourceRect: nil,
                displayScale: scale,
                pointWidth: pointW,
                pointHeight: pointH,
                isArea: false
            )
        }

        guard let display = content.displays.first(where: { $0.displayID == plan.displayID }) ?? content.displays.first else {
            throw RecorderError.noDisplay
        }

        let quality = AppSettings.shared.recordQuality
        let rawPixelW = Int((plan.pointWidth * plan.displayScale * quality.resolutionScale).rounded())
        let rawPixelH = Int((plan.pointHeight * plan.displayScale * quality.resolutionScale).rounded())
        let width = evenDimension(rawPixelW)
        let height = evenDimension(rawPixelH)

        let dir = recordingsDirectory
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let stamp: String = {
            let f = DateFormatter()
            f.dateFormat = "yyyy-MM-dd HH.mm.ss"
            return f.string(from: Date())
        }()
        let kind = plan.isArea ? "区域录屏" : "录屏"
        let url = dir.appendingPathComponent("\(FlareBrand.name) \(kind) \(stamp).mov")
        if FileManager.default.fileExists(atPath: url.path) {
            try FileManager.default.removeItem(at: url)
        }

        let fps = AppSettings.shared.recordFPS
        let baseBitrate = max(width * height * 3, 2_000_000)
        let bitrate = Int(Double(baseBitrate) * quality.bitrateMultiplier)
        let writer = try AVAssetWriter(outputURL: url, fileType: .mov)
        let videoSettings: [String: Any] = [
            AVVideoCodecKey: AVVideoCodecType.h264,
            AVVideoWidthKey: width,
            AVVideoHeightKey: height,
            AVVideoCompressionPropertiesKey: [
                AVVideoAverageBitRateKey: bitrate,
                AVVideoProfileLevelKey: AVVideoProfileLevelH264HighAutoLevel,
                AVVideoExpectedSourceFrameRateKey: fps
            ]
        ]
        let input = AVAssetWriterInput(mediaType: .video, outputSettings: videoSettings)
        input.expectsMediaDataInRealTime = true
        let adaptor = AVAssetWriterInputPixelBufferAdaptor(
            assetWriterInput: input,
            sourcePixelBufferAttributes: [
                kCVPixelBufferPixelFormatTypeKey as String: Int(kCVPixelFormatType_32BGRA),
                kCVPixelBufferWidthKey as String: width,
                kCVPixelBufferHeightKey as String: height
            ]
        )
        guard writer.canAdd(input) else { throw RecorderError.writerSetup }
        writer.add(input)

        capturesSystemAudio = AppSettings.shared.recordSystemAudio
        var audioTrack: AVAssetWriterInput?
        if capturesSystemAudio {
            let audioSettings: [String: Any] = [
                AVFormatIDKey: kAudioFormatMPEG4AAC,
                AVSampleRateKey: 48_000,
                AVNumberOfChannelsKey: 2,
                AVEncoderBitRateKey: 192_000
            ]
            let aInput = AVAssetWriterInput(mediaType: .audio, outputSettings: audioSettings)
            aInput.expectsMediaDataInRealTime = true
            guard writer.canAdd(aInput) else { throw RecorderError.writerSetup }
            writer.add(aInput)
            audioTrack = aInput
        }

        guard writer.startWriting() else {
            throw writer.error ?? RecorderError.writerSetup
        }

        self.outputURL = url
        self.writer = writer
        self.videoInput = input
        self.audioInput = audioTrack
        self.adaptor = adaptor
        self.sessionStarted = false
        self.firstPTS = nil
        self.pausedDuration = .zero
        self.pauseStartedAt = nil

        var excluded: [SCWindow] = []
        if AppSettings.shared.recordExcludeFlare {
            let bid = Bundle.main.bundleIdentifier
            excluded = content.windows.filter { $0.owningApplication?.bundleIdentifier == bid }
        }
        let filter = SCContentFilter(display: display, excludingWindows: excluded)
        let config = SCStreamConfiguration()
        if let rect = plan.sourceRect {
            config.sourceRect = rect
        }
        config.width = width
        config.height = height
        config.scalesToFit = false
        config.showsCursor = AppSettings.shared.recordShowCursor
        config.queueDepth = 6
        config.pixelFormat = kCVPixelFormatType_32BGRA
        config.colorSpaceName = CGColorSpace.sRGB
        config.minimumFrameInterval = CMTime(value: 1, timescale: CMTimeScale(max(fps, 1)))
        config.capturesAudio = capturesSystemAudio
        config.excludesCurrentProcessAudio = AppSettings.shared.recordExcludeFlare

        await MainActor.run {
            if AppSettings.shared.recordHideFlareWindows {
                NSApp.windows.filter { $0.isVisible && $0.level != .statusBar }.forEach { $0.orderOut(nil) }
            }
        }

        let stream = SCStream(filter: filter, configuration: config, delegate: self)
        try stream.addStreamOutput(self, type: .screen, sampleHandlerQueue: writingQueue)
        if capturesSystemAudio {
            try stream.addStreamOutput(self, type: .audio, sampleHandlerQueue: audioQueue)
        }
        try await stream.startCapture()
        self.stream = stream

        await MainActor.run {
            self.isRecording = true
            self.isPaused = false
            self.isCountingDown = false
            self.elapsedSeconds = 0
            self.startedAt = Date()
            self.pausedAccumulated = 0
            self.pauseWallClock = nil
            Permissions.markCaptureSucceeded()
            RecordingHUDController.shared.show()
            self.startTimer()
            let audioHint = capturesSystemAudio ? " · 含系统声音" : ""
            ToastController.shared.show("录屏中\(audioHint) · ⌘⌥R 停止 · Esc 停止")
            StatusBarController.shared?.refreshRecordingAppearance()
            MainMenuController.shared?.reload()
        }
    }

    private func evenDimension(_ value: Int) -> Int {
        let v = max(2, value)
        return v - (v % 2)
    }

    private func pauseRecording() {
        guard isRecording, !isPaused else { return }
        isPaused = true
        pauseWallClock = Date()
        writingQueue.async {
            // 标记暂停起点（基于媒体时间）
            // 实际丢帧在 sample handler 中处理
        }
        RecordingHUDController.shared.updatePaused(true)
        ToastController.shared.show("已暂停录屏")
        MainMenuController.shared?.reload()
        StatusBarController.shared?.refreshRecordingAppearance()
    }

    private func resumeRecording() {
        guard isRecording, isPaused else { return }
        if let pauseWallClock {
            pausedAccumulated += Date().timeIntervalSince(pauseWallClock)
        }
        pauseWallClock = nil
        isPaused = false
        RecordingHUDController.shared.updatePaused(false)
        ToastController.shared.show("继续录屏")
        MainMenuController.shared?.reload()
        StatusBarController.shared?.refreshRecordingAppearance()
    }

    private func finishRecording(discard: Bool) async {
        await MainActor.run {
            self.timer?.invalidate()
            self.timer = nil
            RecordingHUDController.shared.hide()
        }

        let stream = await MainActor.run { () -> SCStream? in
            let s = self.stream
            self.stream = nil
            return s
        }
        if let stream {
            try? await stream.stopCapture()
        }

        let finishResult: (URL?, Bool, Error?) = await withCheckedContinuation { cont in
            writingQueue.async {
                self.videoInput?.markAsFinished()
                self.audioInput?.markAsFinished()
                guard let writer = self.writer else {
                    cont.resume(returning: (self.outputURL, false, nil))
                    return
                }
                writer.finishWriting {
                    cont.resume(returning: (self.outputURL, writer.status == .completed, writer.error))
                }
            }
        }

        await MainActor.run {
            self.isRecording = false
            self.isPaused = false
            self.elapsedSeconds = 0
            let url = finishResult.0
            let ok = finishResult.1 && !discard
            if discard {
                if let url { try? FileManager.default.removeItem(at: url) }
                self.cleanup(failed: true)
                ToastController.shared.show("已丢弃录屏")
            } else {
                self.cleanup(failed: !ok)
                if ok, let url {
                    ToastController.shared.show("录屏已保存：\(url.lastPathComponent)")
                    NSWorkspace.shared.activateFileViewerSelecting([url])
                    SoundPlayer.playShutter()
                } else {
                    ToastController.shared.show(finishResult.2?.localizedDescription ?? "录屏保存失败")
                }
            }
            // 恢复被隐藏的窗口
            if AppSettings.shared.recordHideFlareWindows {
                HomeWindowController.shared.show(tab: .record)
            }
            StatusBarController.shared?.refreshRecordingAppearance()
            MainMenuController.shared?.reload()
        }
    }

    private func cleanup(failed: Bool) {
        stream = nil
        writer = nil
        videoInput = nil
        audioInput = nil
        adaptor = nil
        capturesSystemAudio = false
        sessionStarted = false
        firstPTS = nil
        startedAt = nil
        pausedAccumulated = 0
        pauseWallClock = nil
        pausedDuration = .zero
        pauseStartedAt = nil
        if failed, let url = outputURL {
            try? FileManager.default.removeItem(at: url)
        }
        outputURL = nil
    }

    private func startTimer() {
        timer?.invalidate()
        timer = Timer.scheduledTimer(withTimeInterval: 0.2, repeats: true) { [weak self] _ in
            guard let self, let startedAt = self.startedAt else { return }
            var pauseExtra = self.pausedAccumulated
            if self.isPaused, let pauseWallClock = self.pauseWallClock {
                pauseExtra += Date().timeIntervalSince(pauseWallClock)
            }
            let sec = max(0, Int(Date().timeIntervalSince(startedAt) - pauseExtra))
            DispatchQueue.main.async {
                self.elapsedSeconds = sec
                RecordingHUDController.shared.update(seconds: sec)
            }
        }
        if let timer {
            RunLoop.main.add(timer, forMode: .common)
        }
    }

    enum RecorderError: LocalizedError {
        case noDisplay
        case writerSetup

        var errorDescription: String? {
            switch self {
            case .noDisplay: return "未找到显示器"
            case .writerSetup: return "无法创建视频文件"
            }
        }
    }
}

extension ScreenRecorder: SCStreamDelegate {
    func stream(_ stream: SCStream, didStopWithError error: Error) {
        DispatchQueue.main.async {
            if self.isRecording {
                ToastController.shared.show("录屏中断")
                Task { await self.finishRecording(discard: false) }
            }
        }
    }
}

extension ScreenRecorder: SCStreamOutput {
    func stream(
        _ stream: SCStream,
        didOutputSampleBuffer sampleBuffer: CMSampleBuffer,
        of type: SCStreamOutputType
    ) {
        switch type {
        case .screen:
            appendVideoSample(sampleBuffer)
        case .audio:
            appendAudioSample(sampleBuffer)
        default:
            break
        }
    }

    private func appendVideoSample(_ sampleBuffer: CMSampleBuffer) {
        guard sampleBuffer.isValid else { return }
        if isPaused { return }
        guard let input = videoInput, let writer = writer, let adaptor = adaptor else { return }
        guard writer.status == .writing else { return }

        guard let attachmentsArray = CMSampleBufferGetSampleAttachmentsArray(sampleBuffer, createIfNecessary: false) as? [[SCStreamFrameInfo: Any]],
              let attachment = attachmentsArray.first else { return }
        if let statusRaw = attachment[.status] as? Int,
           let status = SCFrameStatus(rawValue: statusRaw),
           status != .complete {
            return
        }

        guard let pixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) else { return }
        var pts = CMSampleBufferGetPresentationTimeStamp(sampleBuffer)

        if !sessionStarted {
            writer.startSession(atSourceTime: pts)
            sessionStarted = true
            firstPTS = pts
        }
        guard input.isReadyForMoreMediaData else { return }
        if let first = firstPTS {
            pts = CMTimeSubtract(pts, first)
        }
        _ = adaptor.append(pixelBuffer, withPresentationTime: pts)
    }

    private func appendAudioSample(_ sampleBuffer: CMSampleBuffer) {
        guard capturesSystemAudio, sampleBuffer.isValid, !isPaused else { return }
        guard let input = audioInput, let writer = writer else { return }
        guard writer.status == .writing, sessionStarted else { return }
        guard input.isReadyForMoreMediaData else { return }
        input.append(sampleBuffer)
    }
}
