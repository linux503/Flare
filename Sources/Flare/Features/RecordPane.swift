import AppKit
import SwiftUI

struct RecordPane: View {
    @ObservedObject private var recorder = ScreenRecorder.shared
    @Environment(\.flareTheme) private var theme
    @State private var showCursor = AppSettings.shared.recordShowCursor
    @State private var excludeFlare = AppSettings.shared.recordExcludeFlare
    @State private var hideWindows = AppSettings.shared.recordHideFlareWindows
    @State private var audioSource = AppSettings.shared.recordAudioSource
    @State private var countdown = AppSettings.shared.recordCountdownSeconds
    @State private var fps = AppSettings.shared.recordFPS
    @State private var recordMode = AppSettings.shared.recordMode
    @State private var quality = AppSettings.shared.recordQuality
    @State private var recordPath = AppSettings.shared.recordDirectory.path

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                FlarePageHeader(
                    title: L("屏幕录制"),
                    subtitle: recorder.isRecording
                        ? (recorder.isPaused ? L("已暂停 · %@", format(recorder.elapsedSeconds)) : L("录制中 · %@", format(recorder.elapsedSeconds)))
                        : L("全屏 / 区域 / 窗口 · H.264 MOV · 快捷键 %@", AppSettings.shared.shortcut(for: .record).displayString)
                )

                heroCard
                controls
                optionsBlock
                folderRow
            }
            .padding(.horizontal, 28)
            .padding(.top, 40)
            .padding(.bottom, 32)
            .onAppear {
                recordMode = AppSettings.shared.recordMode
            }
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

            if !recorder.isRecording, !recorder.isCountingDown {
                VStack(alignment: .leading, spacing: 8) {
                    Text(L("默认范围"))
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(theme.textMuted)
                    Picker("", selection: $recordMode) {
                        ForEach(RecordCaptureMode.allCases) { mode in
                            Text(mode.displayName).tag(mode)
                        }
                    }
                    .pickerStyle(.segmented)
                    .labelsHidden()
                    .onChange(of: recordMode) { _, mode in
                        AppSettings.shared.recordMode = mode
                    }
                    Text(recordMode.hint)
                        .font(.system(size: 12))
                        .foregroundStyle(theme.textSecondary)
                }
            }

            HStack(spacing: 10) {
                if recorder.isRecording {
                    FlareSecondaryButton(
                        title: recorder.isPaused ? L("继续") : L("暂停"),
                        glyph: recorder.isPaused ? .refresh : .delay
                    ) {
                        ScreenRecorder.shared.togglePause()
                    }
                    FlarePrimaryButton(title: L("停止并保存"), glyph: .save) {
                        ScreenRecorder.shared.stop()
                    }
                    FlareSecondaryButton(title: L("丢弃"), glyph: .trash) {
                        ScreenRecorder.shared.cancelAndDiscard()
                    }
                } else if recorder.isCountingDown {
                    FlarePrimaryButton(title: L("取消倒计时"), glyph: .close) {
                        ScreenRecorder.shared.stop()
                    }
                } else {
                    FlarePrimaryButton(title: L("开始%@录制", recordMode.displayName), glyph: .play) {
                        ScreenRecorder.shared.start()
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
            tipChip("⌘⌥R", L("开始/停止"))
            tipChip("Esc", L("停止"))
            tipChip("⌘P", L("暂停/继续"))
        }
    }

    private var optionsBlock: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(L("录制选项"))
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(theme.textSecondary)
                .padding(.bottom, 14)

            optionRow(L("清晰度")) {
                menuPicker($quality, RecordQualityPreset.allCases, \.displayName) {
                    AppSettings.shared.recordQuality = $0
                }
            }
            rowDivider
            optionRow(L("帧率")) {
                Picker("", selection: $fps) {
                    Text("15 FPS").tag(15)
                    Text("24 FPS").tag(24)
                    Text("30 FPS").tag(30)
                    Text("60 FPS").tag(60)
                }
                .labelsHidden()
                .pickerStyle(.menu)
                .onChange(of: fps) { _, v in
                    AppSettings.shared.recordFPS = v
                }
            }
            rowDivider
            optionRow(L("声音")) {
                menuPicker($audioSource, RecordAudioSource.allCases, \.displayName) {
                    AppSettings.shared.recordAudioSource = $0
                }
            }
            rowDivider
            optionRow(L("开始前倒计时")) {
                Picker("", selection: $countdown) {
                    Text(L("关闭")).tag(0)
                    Text(L("3 秒")).tag(3)
                    Text(L("5 秒")).tag(5)
                    Text(L("10 秒")).tag(10)
                }
                .labelsHidden()
                .pickerStyle(.menu)
                .onChange(of: countdown) { _, v in
                    AppSettings.shared.recordCountdownSeconds = v
                }
            }

            groupDivider

            optionRow(L("显示鼠标指针")) {
                alignedToggle($showCursor) { AppSettings.shared.recordShowCursor = $0 }
            }
            rowDivider
            optionRow(L("排除 Flare 窗口")) {
                alignedToggle($excludeFlare) { AppSettings.shared.recordExcludeFlare = $0 }
            }
            rowDivider
            optionRow(L("开始时隐藏窗口")) {
                alignedToggle($hideWindows) { AppSettings.shared.recordHideFlareWindows = $0 }
            }
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 16)
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
            FlareSecondaryButton(title: L("打开录屏文件夹"), glyph: .folder) {
                ScreenRecorder.shared.openRecordingsFolder()
            }
            Text(recordPath)
                .font(.caption2)
                .foregroundStyle(theme.textMuted)
                .lineLimit(1)
                .truncationMode(.middle)
            Spacer()
            Button(L("选择…")) { chooseFolder() }
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
        if recorder.isCountingDown { return L("倒计时中") }
        if recorder.isPaused { return L("已暂停") }
        if recorder.isRecording { return L("正在录屏") }
        return L("准备就绪")
    }

    private var statusSubtitle: String {
        if recorder.isCountingDown { return L("按 Esc 可取消") }
        if recorder.isRecording {
            let audio = AppSettings.shared.recordAudioSource.toastHint
            return L("浮动条可停止 · MOV%@", audio)
        }
        return L("默认 %@ · %@ · 快捷键按此开始", recordMode.displayName, recordMode.hint)
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

    private var rowDivider: some View {
        Rectangle()
            .fill(theme.stroke)
            .frame(height: 1)
            .padding(.vertical, 6)
    }

    private var groupDivider: some View {
        Rectangle()
            .fill(theme.strokeStrong.opacity(0.85))
            .frame(height: 1)
            .padding(.vertical, 10)
    }

    private func optionRow<Control: View>(_ title: String, @ViewBuilder control: () -> Control) -> some View {
        HStack(alignment: .center, spacing: 16) {
            Text(title)
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(theme.textPrimary)
                .lineLimit(1)
                .frame(minWidth: 132, alignment: .leading)
            Spacer(minLength: 8)
            control()
                .frame(width: 168, alignment: .trailing)
        }
        .frame(minHeight: 30)
    }

    private func alignedToggle(_ binding: Binding<Bool>, onChange: @escaping (Bool) -> Void) -> some View {
        HStack {
            Spacer(minLength: 0)
            Toggle("", isOn: Binding(
                get: { binding.wrappedValue },
                set: { binding.wrappedValue = $0; onChange($0) }
            ))
            .labelsHidden()
            .toggleStyle(.switch)
            .tint(theme.accent)
        }
    }

    private func menuPicker<T: Hashable & Identifiable>(
        _ selection: Binding<T>,
        _ options: [T],
        _ keyPath: KeyPath<T, String>,
        onChange: @escaping (T) -> Void
    ) -> some View {
        Picker("", selection: Binding(
            get: { selection.wrappedValue },
            set: { selection.wrappedValue = $0; onChange($0) }
        )) {
            ForEach(options) { option in
                Text(option[keyPath: keyPath]).tag(option)
            }
        }
        .labelsHidden()
        .pickerStyle(.menu)
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
