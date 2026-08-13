import AppKit
import SwiftUI

final class SettingsWindowController {
    static let shared = SettingsWindowController()
    private init() {}

    /// 不再新开窗口，切到主窗口「设置」页
    func show() {
        HomeWindowController.shared.showSettings()
    }
}

struct SettingsPane: View {
    var onBack: (() -> Void)? = nil

    @Environment(\.flareTheme) private var theme
    @State private var format = AppSettings.shared.imageFormat
    @State private var copyClipboard = AppSettings.shared.copyToClipboard
    @State private var playSound = AppSettings.shared.playSound
    @State private var showMagnifier = AppSettings.shared.showMagnifier
    @State private var afterAction = AppSettings.shared.afterCaptureAction
    @State private var savePath = AppSettings.shared.saveDirectory.path
    @State private var documentPath = AppSettings.shared.documentDirectory.path
    @State private var showInDock = AppSettings.shared.showInDock

    @State private var area = AppSettings.shared.shortcut(for: .area)
    @State private var window = AppSettings.shared.shortcut(for: .window)
    @State private var screen = AppSettings.shared.shortcut(for: .screen)
    @State private var delay = AppSettings.shared.shortcut(for: .delay)
    @State private var record = AppSettings.shared.shortcut(for: .record)
    @State private var history = AppSettings.shared.shortcut(for: .history)
    @State private var hotkeyError: String?
    @State private var permissionLabel = "检查中…"
    @State private var permissionOK = false
    @State private var checkingUpdate = false
    @State private var updateStatus = ""

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 28) {
                FlarePageHeader(
                    title: "设置",
                    subtitle: "外观、截图行为与全局快捷键"
                ) {
                    if let onBack {
                        FlareSecondaryButton(title: "返回截图", glyph: .area, action: onBack)
                    }
                }

                settingsBlock(title: "外观", subtitle: "黑白主题与窗口透明度") {
                    VStack(alignment: .leading, spacing: 16) {
                        ThemePickerGrid()
                        Divider().overlay(theme.stroke)
                        WindowOpacitySlider()
                    }
                }

                settingsBlock(title: "截图后", subtitle: "确认选区后的默认动作") {
                    VStack(alignment: .leading, spacing: 12) {
                        HStack {
                            Text("默认动作")
                                .font(.system(size: 12, weight: .medium))
                                .foregroundStyle(theme.textPrimary)
                            Spacer()
                            Picker("", selection: $afterAction) {
                                ForEach(AfterCaptureAction.allCases) { action in
                                    Text(action.displayName).tag(action)
                                }
                            }
                            .labelsHidden()
                            .frame(maxWidth: 180)
                            .onChange(of: afterAction) { _, newValue in
                                AppSettings.shared.afterCaptureAction = newValue
                            }
                        }

                        labeledToggle("同时复制到剪贴板", isOn: $copyClipboard) {
                            AppSettings.shared.copyToClipboard = $0
                        }
                        labeledToggle("截图提示音", isOn: $playSound) {
                            AppSettings.shared.playSound = $0
                        }
                        labeledToggle("显示放大镜与取色", isOn: $showMagnifier) {
                            AppSettings.shared.showMagnifier = $0
                        }
                        labeledToggle("在程序坞显示图标", isOn: $showInDock) { newValue in
                            AppSettings.shared.showInDock = newValue
                            NSApp.setActivationPolicy(newValue ? .regular : .accessory)
                        }
                    }
                }

                settingsBlock(title: "保存", subtitle: "图片格式与目录") {
                    VStack(alignment: .leading, spacing: 14) {
                        HStack {
                            Text("图片格式")
                                .font(.system(size: 12, weight: .medium))
                                .foregroundStyle(theme.textPrimary)
                            Spacer()
                            Picker("", selection: $format) {
                                ForEach(ImageFormat.allCases) { fmt in
                                    Text(fmt.displayName).tag(fmt)
                                }
                            }
                            .labelsHidden()
                            .frame(width: 110)
                            .onChange(of: format) { _, newValue in
                                AppSettings.shared.imageFormat = newValue
                            }
                        }

                        pathRow(title: "截图保存位置", path: savePath) { chooseFolder() }
                        pathRow(title: "新建文档位置", path: documentPath) { chooseDocumentFolder() }
                    }
                }

                settingsBlock(title: "快捷键", subtitle: "默认 ⌘⌥，避开系统截图 ⌘⇧3/4/5") {
                    VStack(alignment: .leading, spacing: 10) {
                        KeyRecorderButton(title: "区域截图", shortcut: $area) { save(.area, $0) }
                        KeyRecorderButton(title: "窗口截图", shortcut: $window) { save(.window, $0) }
                        KeyRecorderButton(title: "全屏截图", shortcut: $screen) { save(.screen, $0) }
                        KeyRecorderButton(title: "延时截图", shortcut: $delay) { save(.delay, $0) }
                        KeyRecorderButton(title: "屏幕录制", shortcut: $record) { save(.record, $0) }
                        KeyRecorderButton(title: "历史记录", shortcut: $history) { save(.history, $0) }

                        if let hotkeyError {
                            Text(hotkeyError)
                                .font(.caption)
                                .foregroundStyle(theme.warning)
                        }

                        Button("恢复默认快捷键") {
                            AppSettings.shared.resetHotkeys()
                            reloadShortcuts()
                            HotKeyManager.shared.registerDefaults()
                            StatusBarController.shared?.reloadMenu()
                            MainMenuController.shared?.reload()
                            hotkeyError = nil
                            ToastController.shared.show("已恢复默认快捷键")
                        }
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(theme.textSecondary)
                        .buttonStyle(.plain)
                    }
                }

                settingsBlock(title: "权限", subtitle: "打开开关后必须重启；请只授权「应用程序」里的副本") {
                    VStack(alignment: .leading, spacing: 10) {
                        HStack {
                            Text("屏幕录制")
                                .font(.system(size: 12, weight: .medium))
                                .foregroundStyle(theme.textPrimary)
                            Spacer()
                            Text(permissionLabel)
                                .font(.system(size: 12, weight: .semibold))
                                .foregroundStyle(permissionOK ? theme.success : theme.warning)
                        }
                        FlareSecondaryButton(title: "检查并修复权限", glyph: .permission) {
                            Permissions.clearRelaunchFlag()
                            Permissions.ensureScreenCaptureReady(presentUI: true)
                            Task { await refreshPermissionLabel() }
                        }
                        FlareSecondaryButton(title: "打开系统设置", glyph: .settings) {
                            Permissions.openScreenRecordingSettings()
                        }
                        FlarePrimaryButton(title: "重启 \(FlareBrand.name)", glyph: .relaunch) {
                            Permissions.clearRelaunchFlag()
                            Permissions.relaunchApp()
                        }
                        Text(Permissions.runningFromApplications()
                             ? "正在从 /Applications/Flare Pro.app 运行。"
                             : "⚠ 当前路径：\(Bundle.main.bundlePath)。请改用「应用程序」中的副本。")
                            .font(.caption)
                            .foregroundStyle(Permissions.runningFromApplications() ? theme.textMuted : theme.warning)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }

                settingsBlock(title: "关于", subtitle: FlareBrand.tagline) {
                    VStack(alignment: .leading, spacing: 12) {
                        HStack(spacing: 12) {
                            FlareBrandMark(size: 40, cornerRadius: 10)
                            VStack(alignment: .leading, spacing: 3) {
                                Text(FlareBrand.name)
                                    .font(.system(size: 14, weight: .semibold))
                                    .foregroundStyle(theme.textPrimary)
                                Text("版本 \(UpdateChecker.currentVersion) (\(UpdateChecker.currentBuild)) · \(archLabel)")
                                    .font(.system(size: 11))
                                    .foregroundStyle(theme.textMuted)
                            }
                        }
                        Text("Universal Binary · Apple Silicon & Intel")
                            .font(.caption)
                            .foregroundStyle(theme.textMuted)

                        if !updateStatus.isEmpty {
                            Text(updateStatus)
                                .font(.caption)
                                .foregroundStyle(theme.accent)
                        }

                        HStack(spacing: 8) {
                            FlarePrimaryButton(title: checkingUpdate ? "检查中…" : "检查更新", glyph: .refresh) {
                                Task { await runUpdateCheck() }
                            }
                            .disabled(checkingUpdate)

                            FlareSecondaryButton(title: "官网", glyph: .home) {
                                openURL(FlareBrand.websiteURL)
                            }
                            FlareSecondaryButton(title: "GitHub", glyph: .documents) {
                                openURL(FlareBrand.githubURL)
                            }
                        }

                        VStack(alignment: .leading, spacing: 6) {
                            linkRow("官方网站", FlareBrand.websiteURL)
                            linkRow("下载页面", FlareBrand.downloadURL)
                            linkRow("问题反馈", FlareBrand.supportEmail)
                        }
                        .padding(.top, 4)
                    }
                }
            }
            .padding(.horizontal, 28)
            .padding(.top, 40)
            .padding(.bottom, 40)
            .foregroundStyle(theme.textPrimary)
        }
        .onAppear { reloadShortcuts() }
        .task { await refreshPermissionLabel() }
        .onReceive(NotificationCenter.default.publisher(for: .flarePermissionChanged)) { _ in
            Task { await refreshPermissionLabel() }
        }
    }

    private func openURL(_ string: String) {
        guard let url = URL(string: string) else { return }
        NSWorkspace.shared.open(url)
    }

    private func linkRow(_ title: String, _ url: String) -> some View {
        Button {
            openURL(url)
        } label: {
            HStack(spacing: 8) {
                Text(title)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(theme.textSecondary)
                Text(url)
                    .font(.system(size: 10, design: .monospaced))
                    .foregroundStyle(theme.textMuted)
                    .lineLimit(1)
                    .truncationMode(.middle)
                Spacer(minLength: 0)
            }
        }
        .buttonStyle(.plain)
    }

    private func runUpdateCheck() async {
        await MainActor.run {
            checkingUpdate = true
            updateStatus = "正在检查…"
        }
        let result = await UpdateChecker.check()
        await MainActor.run {
            checkingUpdate = false
            switch result {
            case .upToDate(let current):
                updateStatus = "已是最新版 \(current)"
                ToastController.shared.show(updateStatus)
            case .updateAvailable(let remote):
                updateStatus = "发现新版本 \(remote.version)"
                let alert = NSAlert()
                alert.messageText = "发现新版本 \(remote.version)"
                alert.informativeText = (remote.notes?.isEmpty == false)
                    ? (remote.notes ?? "")
                    : "当前 \(UpdateChecker.currentVersion)，建议前往官网下载。"
                alert.addButton(withTitle: "前往下载")
                alert.addButton(withTitle: "稍后再说")
                if alert.runModal() == .alertFirstButtonReturn {
                    openURL(remote.downloadURL ?? FlareBrand.downloadURL)
                }
            case .failed(let message):
                updateStatus = "检查失败：\(message)"
                ToastController.shared.show(updateStatus)
            }
        }
    }

    private func refreshPermissionLabel() async {
        let state = await Permissions.strictState()
        await MainActor.run {
            switch state {
            case .granted:
                permissionLabel = "已就绪"
                permissionOK = true
            case .needsRelaunch:
                permissionLabel = "需重启生效"
                permissionOK = false
            case .denied, .unknown:
                permissionLabel = "未授权"
                permissionOK = false
            }
        }
    }

    private func labeledToggle(_ title: String, isOn: Binding<Bool>, onChange: @escaping (Bool) -> Void) -> some View {
        Toggle(isOn: Binding(
            get: { isOn.wrappedValue },
            set: { isOn.wrappedValue = $0; onChange($0) }
        )) {
            Text(title)
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(theme.textPrimary)
        }
        .toggleStyle(.switch)
        .tint(theme.accent)
    }

    private func settingsBlock<Content: View>(
        title: String,
        subtitle: String,
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.system(size: 14, weight: .semibold, design: .rounded))
                    .foregroundStyle(theme.textPrimary)
                Text(subtitle)
                    .font(.system(size: 11))
                    .foregroundStyle(theme.textMuted)
            }
            content()
                .padding(15)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .fill(theme.fill)
                        .overlay(
                            RoundedRectangle(cornerRadius: 14, style: .continuous)
                                .strokeBorder(theme.stroke, lineWidth: 1)
                        )
                )
        }
    }

    private func pathRow(title: String, path: String, choose: @escaping () -> Void) -> some View {
        HStack(alignment: .top, spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(theme.textPrimary)
                Text(path)
                    .font(.caption)
                    .foregroundStyle(theme.textMuted)
                    .lineLimit(2)
            }
            Spacer()
            Button("选择…", action: choose)
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(theme.textPrimary)
                .buttonStyle(.plain)
                .padding(.horizontal, 10)
                .padding(.vertical, 5)
                .background(theme.fillStrong)
                .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
        }
    }

    private func save(_ action: HotKeyAction, _ shortcut: HotKeyShortcut) {
        let others: [(HotKeyAction, HotKeyShortcut)] = [
            (.area, area), (.window, window), (.screen, screen), (.delay, delay), (.record, record), (.history, history)
        ]
        if let conflict = others.first(where: { $0.0 != action && $0.1 == shortcut }) {
            hotkeyError = "与「\(conflict.0.title)」冲突，请换一组快捷键"
            reloadShortcuts()
            return
        }

        AppSettings.shared.setShortcut(shortcut, for: action)
        HotKeyManager.shared.registerDefaults()
        StatusBarController.shared?.reloadMenu()
        MainMenuController.shared?.reload()
        hotkeyError = nil
        ToastController.shared.show("\(action.title)：\(shortcut.displayString)")
    }

    private func reloadShortcuts() {
        area = AppSettings.shared.shortcut(for: .area)
        window = AppSettings.shared.shortcut(for: .window)
        screen = AppSettings.shared.shortcut(for: .screen)
        delay = AppSettings.shared.shortcut(for: .delay)
        record = AppSettings.shared.shortcut(for: .record)
        history = AppSettings.shared.shortcut(for: .history)
    }

    private var archLabel: String {
        #if arch(arm64)
        return "Apple Silicon · Universal"
        #elseif arch(x86_64)
        return "Intel · Universal"
        #else
        return "Universal"
        #endif
    }

    private func chooseFolder() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        panel.directoryURL = AppSettings.shared.saveDirectory
        if panel.runModal() == .OK, let url = panel.url {
            AppSettings.shared.saveDirectory = url
            savePath = url.path
        }
    }

    private func chooseDocumentFolder() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        panel.directoryURL = AppSettings.shared.documentDirectory
        if panel.runModal() == .OK, let url = panel.url {
            AppSettings.shared.documentDirectory = url
            documentPath = url.path
        }
    }
}

/// 兼容旧测试/引用名
typealias SettingsView = SettingsPane
