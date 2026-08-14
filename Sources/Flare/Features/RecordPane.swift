import AppKit
import SwiftUI

struct RecordPane: View {
    @ObservedObject private var recorder = ScreenRecorder.shared
    @Environment(\.flareTheme) private var theme
    @State private var showCursor = AppSettings.shared.recordShowCursor
    @State private var excludeFlare = AppSettings.shared.recordExcludeFlare
    @State private var hideWindows = AppSettings.shared.recordHideFlareWindows
    @State private var systemAudio = AppSettings.shared.recordSystemAudio
    @State private var countdown = AppSettings.shared.recordCountdownSeconds
    @State private var fps = AppSettings.shared.recordFPS
    @State private var recordMode = AppSettings.shared.recordMode
    @State private var quality = AppSettings.shared.recordQuality
    @State private var recordPath = AppSettings.shared.recordDirectory.path

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                FlarePageHeader(
                    title: "屏幕录制",
                    subtitle: recorder.isRecording
                        ? (recorder.isPaused ? "已暂停 · \(format(recorder.elapsedSeconds))" : "录制中 · \(format(recorder.elapsedSeconds))")
                        : "全屏 / 区域 · H.264 MOV · 快捷键 \(AppSettings.shared.shortcut(for: .record).displayString)"
                )

                heroCard
                controls
                optionsBlock
                folderRow
            }
            .padding(.horizontal, 28)
            .padding(.top, 40)
            .padding(.bottom, 32)
        }
    }

    private var heroCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 12) {
                ZStack {
                    Circle()
                        .fill(recorder.isRecording ? Color.red.opacity(0.2) : theme.fillStrong)
                        .frame(width: 52, height: 52)
                    SnapIcon(
                        .record,
                        size: .hero,
                        opacity: 1,
                        tint: recorder.isRecording ? .red : theme.textPrimary
                    )
                }
                VStack(alignment: .leading, spacing: 4) {
                    Text(statusTitle)
                        .font(.system(size: 18, weight: .bold, design: .rounded))
                        .foregroundStyle(theme.textPrimary)
                    Text(statusSubtitle)
                        .font(.system(size: 12))
                        .foregroundStyle(theme.textMuted)
                }
                Spacer()
                if recorder.isRecording {
                    Text(format(recorder.elapsedSeconds))
                        .font(.system(size: 22, weight: .semibold, design: .monospaced))
                        .foregroundStyle(theme.textPrimary)
                }
            }

            HStack(spacing: 10) {
                if recorder.isRecording {
                    FlareSecondaryButton(
                        title: recorder.isPaused ? "继续" : "暂停",
                        glyph: recorder.isPaused ? .refresh : .delay
                    ) {
                        ScreenRecorder.shared.togglePause()
                    }
                    FlarePrimaryButton(title: "停止并保存", glyph: .save) {
                        ScreenRecorder.shared.stop()
                    }
                    FlareSecondaryButton(title: "丢弃", glyph: .trash) {
                        ScreenRecorder.shared.cancelAndDiscard()
                    }
                } else if recorder.isCountingDown {
                    FlarePrimaryButton(title: "取消倒计时", glyph: .close) {
                        ScreenRecorder.shared.stop()
                    }
                } else {
                    FlarePrimaryButton(title: "全屏录屏", glyph: .screen) {
                        ScreenRecorder.shared.startFullScreen()
                    }
                    FlareSecondaryButton(title: "区域录屏", glyph: .area) {
                        ScreenRecorder.shared.startArea()
                    }
                    FlareSecondaryButton(title: "立即开始", glyph: .play) {
                        if recordMode == .area {
                            ScreenRecorder.shared.startArea(countdown: false)
                        } else {
                            ScreenRecorder.shared.startFullScreen(countdown: false)
                        }
                    }
                }
            }
        }
        .padding(18)
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(theme.fill)
                .overlay(
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .strokeBorder(recorder.isRecording ? Color.red.opacity(0.4) : theme.stroke, lineWidth: 1)
                )
        )
    }

    private var controls: some View {
        HStack(spacing: 10) {
            tipChip("⌘⌥R", "开始/停止")
            tipChip("Esc", "停止")
            tipChip("⌘P", "暂停/继续")
        }
    }

    private var optionsBlock: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("录制选项")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(theme.textSecondary)

            pickerRow("默认范围", selection: $recordMode, options: RecordCaptureMode.allCases, label: \.displayName) { mode in
                AppSettings.shared.recordMode = mode
            }

            pickerRow("清晰度", selection: $quality, options: RecordQualityPreset.allCases, label: \.displayName) { preset in
                AppSettings.shared.recordQuality = preset
            }

            toggleRow("录制系统声音", $systemAudio) {
                AppSettings.shared.recordSystemAudio = $0
            }

            toggleRow("显示鼠标指针", $showCursor) {
                AppSettings.shared.recordShowCursor = $0
            }
            toggleRow("排除 Flare 窗口", $excludeFlare) {
                AppSettings.shared.recordExcludeFlare = $0
            }
            toggleRow("开始时隐藏 Flare 窗口", $hideWindows) {
                AppSettings.shared.recordHideFlareWindows = $0
            }

            HStack {
                Text("开始前倒计时")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(theme.textPrimary)
                Spacer()
                Picker("", selection: $countdown) {
                    Text("关闭").tag(0)
                    Text("3 秒").tag(3)
                    Text("5 秒").tag(5)
                    Text("10 秒").tag(10)
                }
                .labelsHidden()
                .frame(width: 100)
                .onChange(of: countdown) { _, v in
                    AppSettings.shared.recordCountdownSeconds = v
                }
            }

            HStack {
                Text("帧率")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(theme.textPrimary)
                Spacer()
                Picker("", selection: $fps) {
                    Text("15 FPS").tag(15)
                    Text("24 FPS").tag(24)
                    Text("30 FPS").tag(30)
                    Text("60 FPS").tag(60)
                }
                .labelsHidden()
                .frame(width: 100)
                .onChange(of: fps) { _, v in
                    AppSettings.shared.recordFPS = v
                }
            }
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(theme.fill)
                .overlay(
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .strokeBorder(theme.stroke, lineWidth: 1)
                )
        )
    }

    private var folderRow: some View {
        HStack(spacing: 12) {
            FlareSecondaryButton(title: "打开录屏文件夹", glyph: .folder) {
                ScreenRecorder.shared.openRecordingsFolder()
            }
            Text(recordPath)
                .font(.caption2)
                .foregroundStyle(theme.textMuted)
                .lineLimit(1)
                .truncationMode(.middle)
            Spacer()
            Button("选择…") { chooseFolder() }
                .font(.system(size: 11, weight: .semibold))
                .buttonStyle(.plain)
                .foregroundStyle(theme.textPrimary)
                .padding(.horizontal, 10)
                .padding(.vertical, 5)
                .background(theme.fillStrong)
                .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
        }
    }

    private var statusTitle: String {
        if recorder.isCountingDown { return "倒计时中" }
        if recorder.isPaused { return "已暂停" }
        if recorder.isRecording { return "正在录屏" }
        return "准备就绪"
    }

    private var statusSubtitle: String {
        if recorder.isCountingDown { return "按 Esc 可取消" }
        if recorder.isRecording {
            let audio = AppSettings.shared.recordSystemAudio ? " · 含系统声音" : ""
            return "浮动条可停止 · MOV\(audio)"
        }
        return "全屏录当前显示器，或框选区域录制"
    }

    private func tipChip(_ key: String, _ label: String) -> some View {
        HStack(spacing: 6) {
            Text(key)
                .font(.system(size: 11, weight: .semibold, design: .rounded))
                .padding(.horizontal, 7)
                .padding(.vertical, 3)
                .background(theme.fillStrong)
                .clipShape(RoundedRectangle(cornerRadius: 5, style: .continuous))
            Text(label)
                .font(.system(size: 11))
                .foregroundStyle(theme.textMuted)
        }
    }

    private func toggleRow(_ title: String, _ binding: Binding<Bool>, onChange: @escaping (Bool) -> Void) -> some View {
        Toggle(isOn: Binding(
            get: { binding.wrappedValue },
            set: { binding.wrappedValue = $0; onChange($0) }
        )) {
            Text(title)
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(theme.textPrimary)
        }
        .toggleStyle(.switch)
        .tint(theme.accent)
    }

    private func pickerRow<T: Hashable & Identifiable>(
        _ title: String,
        selection: Binding<T>,
        options: [T],
        label keyPath: KeyPath<T, String>,
        onChange: @escaping (T) -> Void
    ) -> some View {
        HStack {
            Text(title)
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(theme.textPrimary)
            Spacer()
            Picker("", selection: Binding(
                get: { selection.wrappedValue },
                set: { selection.wrappedValue = $0; onChange($0) }
            )) {
                ForEach(options) { option in
                    Text(option[keyPath: keyPath]).tag(option)
                }
            }
            .labelsHidden()
            .frame(width: 148)
        }
    }

    private func format(_ seconds: Int) -> String {
        String(format: "%02d:%02d", seconds / 60, seconds % 60)
    }

    private func chooseFolder() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        panel.directoryURL = AppSettings.shared.recordDirectory
        if panel.runModal() == .OK, let url = panel.url {
            AppSettings.shared.recordDirectory = url
            recordPath = url.path
        }
    }
}
