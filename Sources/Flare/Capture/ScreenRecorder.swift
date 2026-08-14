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
    private var micInput: AVAssetWriterInput?
    private var adaptor: AVAssetWriterInputPixelBufferAdaptor?
    private var outputURL: URL?
    private var sessionStarted = false
    private var sessionSourceTime = CMTime.invalid
    private var timer: Timer?
    private var startedAt: Date?
    private var pausedAccumulated: TimeInterval = 0
    private var pauseWallClock: Date?
    private let writingQueue = DispatchQueue(label: "app.flare.recorder.write")
    private let audioQueue = DispatchQueue(label: "app.flare.recorder.audio")
    private let timelineLock = NSLock()
    private var dropSamples = false
    private var timelineOffset = CMTime.zero
    private var pauseBeganPTS: CMTime?
    private var pendingCountdown = false
    private var pendingPlan: RecordPlan?
    private var capturesSystemAudio = false
    private var capturesMicrophone = false
    private var micEngine: AVAudioEngine?
    private var micConverter: AVAudioConverter?
    private var micSampleCount: Int64 = 0
    private var micTargetFormat: AVAudioFormat?

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
        guard Permissions.prepareForCapture() else { return }
        pendingPlan = nil
        DispatchQueue.main.async {
            self.startOnMain(countdown: countdown)
        }
    }

    func startArea(countdown: Bool? = nil) {
        guard Permissions.prepareForCapture() else { return }
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
        Task { @MainActor in
            await self.stopInternal(discard: false)
        }
    }

    func cancelAndDiscard() {
        Task { @MainActor in
            await self.stopInternal(discard: true)
        }
    }

    @MainActor
    func stopInternal(discard: Bool) async {
        if isCountingDown {
            cancelCountdown()
            return
        }
        guard isRecording else { return }
        await finishRecording(discard: discard)
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

        var useSystem = AppSettings.shared.recordAudioSource.capturesSystem
        var useMic = AppSettings.shared.recordAudioSource.capturesMicrophone
        if useMic {
            let granted = await Permissions.requestMicrophoneAccess()
            if !granted {
                useMic = false
                await MainActor.run {
                    ToastController.shared.show("未授权麦克风，已跳过人声")
                }
            }
        }

        func makeAudioInput() throws -> AVAssetWriterInput {
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
            return aInput
        }

        audioInput = nil
        micInput = nil
        if useSystem || useMic {
            audioInput = try makeAudioInput()
            if useSystem && useMic {
                micInput = try makeAudioInput()
            }
        }

        guard writer.startWriting() else {
            throw writer.error ?? RecorderError.writerSetup
        }

        self.outputURL = url
        self.writer = writer
        self.videoInput = input
        if !(useSystem && useMic) {
            self.micInput = nil
        }
        if !useSystem && !useMic {
            self.audioInput = nil
        }
        self.adaptor = adaptor
        self.sessionStarted = false
        self.sessionSourceTime = .invalid
        self.capturesSystemAudio = useSystem
        self.capturesMicrophone = useMic
        timelineLock.lock()
        dropSamples = false
        timelineOffset = .zero
        pauseBeganPTS = nil
        timelineLock.unlock()

        let filter: SCContentFilter
        if AppSettings.shared.recordExcludeFlare,
           let app = content.applications.first(where: { $0.bundleIdentifier == Bundle.main.bundleIdentifier }) {
            filter = SCContentFilter(display: display, excludingApplications: [app], exceptingWindows: [])
        } else {
            filter = SCContentFilter(display: display, excludingWindows: [])
        }
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
        config.capturesAudio = useSystem
        config.excludesCurrentProcessAudio = AppSettings.shared.recordExcludeFlare
        if #available(macOS 15.0, *), useMic {
            config.captureMicrophone = true
        }

        await MainActor.run {
            if AppSettings.shared.recordHideFlareWindows {
                NSApp.windows.filter { $0.isVisible && $0.level != .statusBar }.forEach { $0.orderOut(nil) }
            }
        }

        let stream = SCStream(filter: filter, configuration: config, delegate: self)
        try stream.addStreamOutput(self, type: .screen, sampleHandlerQueue: writingQueue)
        if useSystem {
            try stream.addStreamOutput(self, type: .audio, sampleHandlerQueue: audioQueue)
        }
        if useMic, #available(macOS 15.0, *) {
            try stream.addStreamOutput(self, type: .microphone, sampleHandlerQueue: audioQueue)
        }
        try await stream.startCapture()
        self.stream = stream
        if useMic {
            if #available(macOS 15.0, *) {
                // 麦克风走 ScreenCaptureKit，与画面同一时钟
            } else {
                try await MainActor.run {
                    try self.startMicrophoneEngine()
                }
            }
        }

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
            let audioHint = AppSettings.shared.recordAudioSource.toastHint
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
        timelineLock.lock()
        dropSamples = true
        pauseBeganPTS = nil
        timelineLock.unlock()
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
        timelineLock.lock()
        dropSamples = false
        timelineLock.unlock()
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
        stopMicrophoneEngine()

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
                self.micInput?.markAsFinished()
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
        micInput = nil
        adaptor = nil
        capturesSystemAudio = false
        capturesMicrophone = false
        sessionStarted = false
        sessionSourceTime = .invalid
        startedAt = nil
        pausedAccumulated = 0
        pauseWallClock = nil
        stopMicrophoneEngine()
        timelineLock.lock()
        dropSamples = false
        timelineOffset = .zero
        pauseBeganPTS = nil
        micSampleCount = 0
        timelineLock.unlock()
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
                StatusBarController.shared?.refreshRecordingAppearance()
            }
        }
        if let timer {
            RunLoop.main.add(timer, forMode: .common)
        }
    }

    enum RecorderError: LocalizedError {
        case noDisplay
        case writerSetup
        case microphoneUnavailable

        var errorDescription: String? {
            switch self {
            case .noDisplay: return "未找到显示器"
            case .writerSetup: return "无法创建视频文件"
            case .microphoneUnavailable: return "无法使用麦克风"
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
            appendAudioSample(sampleBuffer, to: audioInput)
        default:
            if #available(macOS 15.0, *), type == .microphone {
                appendAudioSample(sampleBuffer, to: micTrack())
            }
        }
    }

    private func mappedPTS(_ sampleBuffer: CMSampleBuffer, consumePause: Bool) -> CMTime? {
        guard sampleBuffer.isValid else { return nil }
        let pts = CMSampleBufferGetPresentationTimeStamp(sampleBuffer)
        timelineLock.lock()
        defer { timelineLock.unlock() }
        if dropSamples {
            if consumePause, pauseBeganPTS == nil || pauseBeganPTS == .invalid {
                pauseBeganPTS = pts
            }
            return nil
        }
        if !consumePause, pauseBeganPTS != nil {
            return nil
        }
        if consumePause, let began = pauseBeganPTS, began.isValid {
            timelineOffset = CMTimeAdd(timelineOffset, CMTimeSubtract(pts, began))
            pauseBeganPTS = nil
        }
        return CMTimeSubtract(pts, timelineOffset)
    }

    private func appendVideoSample(_ sampleBuffer: CMSampleBuffer) {
        guard sampleBuffer.isValid else { return }
        guard let attachmentsArray = CMSampleBufferGetSampleAttachmentsArray(sampleBuffer, createIfNecessary: false) as? [[SCStreamFrameInfo: Any]],
              let attachment = attachmentsArray.first else { return }
        if let statusRaw = attachment[.status] as? Int,
           let status = SCFrameStatus(rawValue: statusRaw),
           status != .complete {
            return
        }
        guard let outPTS = mappedPTS(sampleBuffer, consumePause: true) else { return }
        guard let input = videoInput, let writer = writer, let adaptor = adaptor else { return }
        guard writer.status == .writing else { return }
        guard let pixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) else { return }
        if !sessionStarted {
            writer.startSession(atSourceTime: outPTS)
            sessionStarted = true
            sessionSourceTime = outPTS
        }
        guard input.isReadyForMoreMediaData else { return }
        _ = adaptor.append(pixelBuffer, withPresentationTime: outPTS)
    }

    private func micTrack() -> AVAssetWriterInput? {
        micInput ?? (capturesMicrophone ? audioInput : nil)
    }

    private func appendAudioSample(_ sampleBuffer: CMSampleBuffer, to input: AVAssetWriterInput?) {
        guard let input, let writer = writer else { return }
        guard let outPTS = mappedPTS(sampleBuffer, consumePause: false) else { return }
        guard writer.status == .writing, sessionStarted else { return }
        guard input.isReadyForMoreMediaData else { return }
        guard let shifted = Self.sampleBuffer(sampleBuffer, withPTS: outPTS) else { return }
        input.append(shifted)
    }

    private func startMicrophoneEngine() throws {
        let engine = AVAudioEngine()
        let inputNode = engine.inputNode
        let inFormat = inputNode.inputFormat(forBus: 0)
        guard inFormat.sampleRate > 0, inFormat.channelCount > 0 else {
            throw RecorderError.microphoneUnavailable
        }
        guard let outFormat = AVAudioFormat(
            commonFormat: .pcmFormatInt16,
            sampleRate: 48_000,
            channels: 2,
            interleaved: true
        ) else {
            throw RecorderError.microphoneUnavailable
        }
        guard let converter = AVAudioConverter(from: inFormat, to: outFormat) else {
            throw RecorderError.microphoneUnavailable
        }
        micConverter = converter
        micTargetFormat = outFormat
        micSampleCount = 0
        inputNode.installTap(onBus: 0, bufferSize: 1024, format: inFormat) { [weak self] buffer, _ in
            self?.appendEngineMicBuffer(buffer)
        }
        try engine.start()
        micEngine = engine
    }

    private func stopMicrophoneEngine() {
        if let engine = micEngine {
            engine.inputNode.removeTap(onBus: 0)
            engine.stop()
        }
        micEngine = nil
        micConverter = nil
        micTargetFormat = nil
        micSampleCount = 0
    }

    private func appendEngineMicBuffer(_ buffer: AVAudioPCMBuffer) {
        timelineLock.lock()
        let dropping = dropSamples || !sessionStarted || !sessionSourceTime.isValid
        timelineLock.unlock()
        guard !dropping else { return }
        guard capturesMicrophone, let outFormat = micTargetFormat, let converted = convertMicBuffer(buffer, to: outFormat) else { return }
        let frames = Int64(converted.frameLength)
        guard frames > 0 else { return }
        timelineLock.lock()
        let local = CMTime(value: micSampleCount, timescale: Int32(outFormat.sampleRate))
        micSampleCount += frames
        let base = sessionSourceTime
        timelineLock.unlock()
        let pts = CMTimeAdd(base, local)
        guard let sample = Self.cmSampleBuffer(from: converted, pts: pts) else { return }
        audioQueue.async { [weak self] in
            guard let self, let input = self.micTrack(), let writer = self.writer else { return }
            guard writer.status == .writing, input.isReadyForMoreMediaData else { return }
            input.append(sample)
        }
    }

    private func convertMicBuffer(_ buffer: AVAudioPCMBuffer, to format: AVAudioFormat) -> AVAudioPCMBuffer? {
        guard let converter = micConverter else { return nil }
        let ratio = format.sampleRate / buffer.format.sampleRate
        let capacity = AVAudioFrameCount((Double(buffer.frameLength) * ratio).rounded(.up) + 32)
        guard let out = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: capacity) else { return nil }
        var error: NSError?
        var consumed = false
        let status = converter.convert(to: out, error: &error) { _, outStatus in
            if consumed {
                outStatus.pointee = .noDataNow
                return nil
            }
            consumed = true
            outStatus.pointee = .haveData
            return buffer
        }
        guard status != .error, out.frameLength > 0 else { return nil }
        return out
    }

    private static func cmSampleBuffer(from pcm: AVAudioPCMBuffer, pts: CMTime) -> CMSampleBuffer? {
        var asbd = pcm.format.streamDescription.pointee
        var formatDesc: CMAudioFormatDescription?
        guard CMAudioFormatDescriptionCreate(
            allocator: kCFAllocatorDefault,
            asbd: &asbd,
            layoutSize: 0,
            layout: nil,
            magicCookieSize: 0,
            magicCookie: nil,
            extensions: nil,
            formatDescriptionOut: &formatDesc
        ) == noErr, let formatDesc else { return nil }

        let abl = pcm.audioBufferList.pointee
        let bytes = Int(abl.mBuffers.mDataByteSize)
        guard bytes > 0, let src = abl.mBuffers.mData else { return nil }

        var block: CMBlockBuffer?
        guard CMBlockBufferCreateWithMemoryBlock(
            allocator: kCFAllocatorDefault,
            memoryBlock: nil,
            blockLength: bytes,
            blockAllocator: kCFAllocatorDefault,
            customBlockSource: nil,
            offsetToData: 0,
            dataLength: bytes,
            flags: 0,
            blockBufferOut: &block
        ) == noErr, let block else { return nil }
        guard CMBlockBufferReplaceDataBytes(
            with: src,
            blockBuffer: block,
            offsetIntoDestination: 0,
            dataLength: bytes
        ) == noErr else { return nil }

        var timing = CMSampleTimingInfo(
            duration: CMTime(value: Int64(pcm.frameLength), timescale: CMTimeScale(pcm.format.sampleRate)),
            presentationTimeStamp: pts,
            decodeTimeStamp: .invalid
        )
        var sample: CMSampleBuffer?
        let status = CMSampleBufferCreate(
            allocator: kCFAllocatorDefault,
            dataBuffer: block,
            dataReady: true,
            makeDataReadyCallback: nil,
            refcon: nil,
            formatDescription: formatDesc,
            sampleCount: CMItemCount(pcm.frameLength),
            sampleTimingEntryCount: 1,
            sampleTimingArray: &timing,
            sampleSizeEntryCount: 0,
            sampleSizeArray: nil,
            sampleBufferOut: &sample
        )
        return status == noErr ? sample : nil
    }

    private static func sampleBuffer(_ sampleBuffer: CMSampleBuffer, withPTS pts: CMTime) -> CMSampleBuffer? {
        var timing = CMSampleTimingInfo(
            duration: CMSampleBufferGetDuration(sampleBuffer),
            presentationTimeStamp: pts,
            decodeTimeStamp: .invalid
        )
        var copy: CMSampleBuffer?
        let status = CMSampleBufferCreateCopyWithNewTiming(
            allocator: kCFAllocatorDefault,
            sampleBuffer: sampleBuffer,
            sampleTimingEntryCount: 1,
            sampleTimingArray: &timing,
            sampleBufferOut: &copy
        )
        return status == noErr ? copy : nil
    }
}
