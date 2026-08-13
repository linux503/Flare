import AppKit
import AVFoundation
import Combine
import CoreMedia
import ScreenCaptureKit

/// 全屏屏幕录制（ScreenCaptureKit → H.264 MOV）
final class ScreenRecorder: NSObject, ObservableObject {
    static let shared = ScreenRecorder()

    @Published private(set) var isRecording = false
    @Published private(set) var elapsedSeconds: Int = 0

    private var stream: SCStream?
    private var writer: AVAssetWriter?
    private var videoInput: AVAssetWriterInput?
    private var adaptor: AVAssetWriterInputPixelBufferAdaptor?
    private var outputURL: URL?
    private var sessionStarted = false
    private var firstPTS: CMTime?
    private var timer: Timer?
    private var startedAt: Date?
    private let writingQueue = DispatchQueue(label: "app.flare.recorder.write")

    private override init() {
        super.init()
    }

    /// 开始 / 停止切换
    func toggle() {
        if isRecording {
            stop()
        } else {
            start()
        }
    }

    func start() {
        DispatchQueue.main.async {
            self.startOnMain()
        }
    }

    func stop() {
        DispatchQueue.main.async {
            guard self.isRecording else { return }
            Task { await self.finishRecording() }
        }
    }

    private func startOnMain() {
        guard !isRecording else { return }
        guard !CaptureCoordinator.shared.isCapturing else {
            ToastController.shared.show("请先结束截图再录屏")
            return
        }
        guard Permissions.canAttemptCapture() else {
            Permissions.ensureScreenCaptureReady(presentUI: true)
            return
        }

        Task {
            do {
                try await beginRecording()
            } catch {
                await MainActor.run {
                    Permissions.handleCaptureFailure()
                    ToastController.shared.show("无法开始录屏：\(error.localizedDescription)")
                    self.cleanup(failed: true)
                }
            }
        }
    }

    private func beginRecording() async throws {
        let content = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: true)
        let mouse = NSEvent.mouseLocation
        let screen = NSScreen.screens.first { NSMouseInRect(mouse, $0.frame, false) } ?? NSScreen.main
        let displayID = (screen?.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber)?.uint32Value
            ?? CGMainDisplayID()
        guard let display = content.displays.first(where: { $0.displayID == displayID }) ?? content.displays.first else {
            throw RecorderError.noDisplay
        }

        let scale = screen?.backingScaleFactor ?? 2.0
        let pointW = screen?.frame.width ?? CGFloat(display.width)
        let pointH = screen?.frame.height ?? CGFloat(display.height)
        let pixelW = max(Int((pointW * scale).rounded()), 2)
        let pixelH = max(Int((pointH * scale).rounded()), 2)
        let width = pixelW - (pixelW % 2)
        let height = pixelH - (pixelH % 2)

        let dir = AppSettings.shared.saveDirectory
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let stamp: String = {
            let f = DateFormatter()
            f.dateFormat = "yyyy-MM-dd HH.mm.ss"
            return f.string(from: Date())
        }()
        let url = dir.appendingPathComponent("\(FlareBrand.name) 录屏 \(stamp).mov")
        if FileManager.default.fileExists(atPath: url.path) {
            try FileManager.default.removeItem(at: url)
        }

        let writer = try AVAssetWriter(outputURL: url, fileType: .mov)
        let videoSettings: [String: Any] = [
            AVVideoCodecKey: AVVideoCodecType.h264,
            AVVideoWidthKey: width,
            AVVideoHeightKey: height,
            AVVideoCompressionPropertiesKey: [
                AVVideoAverageBitRateKey: max(width * height * 4, 2_500_000),
                AVVideoProfileLevelKey: AVVideoProfileLevelH264HighAutoLevel,
                AVVideoExpectedSourceFrameRateKey: 30
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
        guard writer.startWriting() else {
            throw writer.error ?? RecorderError.writerSetup
        }

        self.outputURL = url
        self.writer = writer
        self.videoInput = input
        self.adaptor = adaptor
        self.sessionStarted = false
        self.firstPTS = nil

        let filter = SCContentFilter(display: display, excludingWindows: [])
        let config = SCStreamConfiguration()
        config.width = width
        config.height = height
        config.scalesToFit = false
        config.showsCursor = true
        config.queueDepth = 6
        config.pixelFormat = kCVPixelFormatType_32BGRA
        config.colorSpaceName = CGColorSpace.sRGB
        config.minimumFrameInterval = CMTime(value: 1, timescale: 30)

        let stream = SCStream(filter: filter, configuration: config, delegate: self)
        try stream.addStreamOutput(self, type: .screen, sampleHandlerQueue: writingQueue)
        try await stream.startCapture()
        self.stream = stream

        await MainActor.run {
            self.isRecording = true
            self.elapsedSeconds = 0
            self.startedAt = Date()
            Permissions.markCaptureSucceeded()
            RecordingHUDController.shared.show()
            self.startTimer()
            ToastController.shared.show("开始录屏 · 再次快捷键或点停止结束")
            StatusBarController.shared?.reloadMenu()
            MainMenuController.shared?.reload()
        }
    }

    private func finishRecording() async {
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
            self.elapsedSeconds = 0
            self.cleanup(failed: !finishResult.1)
            StatusBarController.shared?.reloadMenu()
            MainMenuController.shared?.reload()
            if finishResult.1, let url = finishResult.0 {
                ToastController.shared.show("录屏已保存：\(url.lastPathComponent)")
                NSWorkspace.shared.activateFileViewerSelecting([url])
                SoundPlayer.playShutter()
            } else {
                let msg = finishResult.2?.localizedDescription ?? "录屏保存失败"
                ToastController.shared.show(msg)
            }
        }
    }

    private func cleanup(failed: Bool) {
        stream = nil
        writer = nil
        videoInput = nil
        adaptor = nil
        sessionStarted = false
        firstPTS = nil
        startedAt = nil
        if failed, let url = outputURL {
            try? FileManager.default.removeItem(at: url)
        }
        if !failed {
            outputURL = nil
        } else {
            outputURL = nil
        }
    }

    private func startTimer() {
        timer?.invalidate()
        timer = Timer.scheduledTimer(withTimeInterval: 0.25, repeats: true) { [weak self] _ in
            guard let self, let startedAt = self.startedAt else { return }
            let sec = Int(Date().timeIntervalSince(startedAt))
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
                Task { await self.finishRecording() }
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
        guard type == .screen, sampleBuffer.isValid else { return }
        guard let input = videoInput, let writer = writer, let adaptor = adaptor else { return }
        guard writer.status == .writing else { return }

        // 仅写入完整帧
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
}
