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
    @State private var watermarkEnabled = AppSettings.shared.watermarkEnabled
    @State private var afterAction = AppSettings.shared.afterCaptureAction
    @State private var translateTarget = AppSettings.shared.translateTargetLanguage
    @State private var historyRetention = AppSettings.shared.historyRetention
    @State private var savePath = AppSettings.shared.saveDirectory.path
    @State private var documentPath = AppSettings.shared.documentDirectory.path
    @State private var showInDock = AppSettings.shared.showInDock
    @State private var privacyMode = AppSettings.shared.privacyModeEnabled
    @State private var privacyAutoRedact = AppSettings.shared.privacyAutoRedact

    @State private var area = AppSettings.shared.shortcut(for: .area)
    @State private var window = AppSettings.shared.shortcut(for: .window)
    @State private var screen = AppSettings.shared.shortcut(for: .screen)
    @State private var delay = AppSettings.shared.shortcut(for: .delay)
    @State private var longShot = AppSettings.shared.shortcut(for: .longShot)
    @State private var translate = AppSettings.shared.shortcut(for: .translate)
    @State private var appLanguage = L10n.language
    @State private var record = AppSettings.shared.shortcut(for: .record)
    @State private var history = AppSettings.shared.shortcut(for: .history)
    @State private var hotkeyError: String?
    @State private var permissionLabel = L("检查中…")
    @State private var permissionOK = false
    @State private var checkingUpdate = false
    @State private var updateStatus = ""

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 28) {
                FlarePageHeader(
                    title: L("设置"),
                    subtitle: L("外观、截图行为与全局快捷键")
                ) {
                    if let onBack {
                        FlareSecondaryButton(title: L("返回截图"), glyph: .area, action: onBack)
                    }
                }

                settingsBlock(title: L("外观"), subtitle: L("Logo、主题与窗口透明度")) {
                    VStack(alignment: .leading, spacing: 16) {
                        HStack {
                            Text(L("语言 / Language"))
                                .font(.system(size: 12, weight: .semibold))
                                .foregroundStyle(theme.textPrimary)
                            Spacer()
                            Picker("", selection: $appLanguage) {
                                ForEach(AppLanguage.allCases) { language in
                                    Text(language.displayName).tag(language)
                                }
                            }
                            .labelsHidden()
                            .frame(width: 140)
                            .onChange(of: appLanguage) { _, newValue in
                                guard newValue != L10n.language else { return }
                                UserDefaults.standard.set(newValue.rawValue, forKey: L10n.defaultsKey)
                                ToastController.shared.show(L("切换语言，正在重启…"))
                                DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) {
                                    Permissions.relaunchApp()
                                }
                            }
                        }
                        Divider().overlay(theme.stroke)
                        LogoPickerRow()
                        Divider().overlay(theme.stroke)
                        ThemePickerGrid()
                        Divider().overlay(theme.stroke)
                        WindowOpacitySlider()
                    }
                }

                settingsBlock(title: L("截图后"), subtitle: L("双击选区、回车确认后的默认动作与历史保留")) {
                    VStack(alignment: .leading, spacing: 16) {
                        VStack(alignment: .leading, spacing: 8) {
                            Text(L("默认动作"))
                                .font(.system(size: 12, weight: .semibold))
                                .foregroundStyle(theme.textPrimary)
                            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 8) {
                                ForEach(AfterCaptureAction.allCases) { action in
                                    Button {
                                        afterAction = action
                                        AppSettings.shared.afterCaptureAction = action
                                    } label: {
                                        VStack(alignment: .leading, spacing: 4) {
                                            Text(action.displayName)
                                                .font(.system(size: 12, weight: .semibold))
                                                .foregroundStyle(theme.textPrimary)
                                            Text(action.hint)
                                                .font(.system(size: 10))
                                                .foregroundStyle(theme.textMuted)
                                                .lineLimit(2)
                                                .fixedSize(horizontal: false, vertical: true)
                                        }
                                        .frame(maxWidth: .infinity, alignment: .leading)
                                        .padding(10)
                                        .background(
                                            RoundedRectangle(cornerRadius: 10, style: .continuous)
                                                .fill(afterAction == action ? theme.accentSoft : theme.fill)
                                        )
                                    }
                                    .buttonStyle(.plain)
                                }
                            }
                        }

                        Divider().overlay(theme.stroke)

                        VStack(alignment: .leading, spacing: 8) {
                            HStack {
                                Text(L("历史保留"))
                                    .font(.system(size: 12, weight: .semibold))
                                    .foregroundStyle(theme.textPrimary)
                                Spacer()
                                Text(historyRetention.displayName)
                                    .font(.system(size: 11, weight: .medium))
                                    .foregroundStyle(theme.textMuted)
                            }
                            Picker("", selection: $historyRetention) {
                                ForEach(HistoryRetention.allCases) { item in
                                    Text(item.displayName).tag(item)
                                }
                            }
                            .pickerStyle(.segmented)
                            .labelsHidden()
                            .onChange(of: historyRetention) { _, newValue in
                                AppSettings.shared.historyRetention = newValue
                                HistoryStore.shared.pruneExpired()
                                ToastController.shared.show(L("历史保留：%@", newValue.displayName))
                            }
                            Text(L("超过所选时长的记录会自动删除（仅清理应用管理的截图文件）。"))
                                .font(.system(size: 10))
                                .foregroundStyle(theme.textMuted)
                                .fixedSize(horizontal: false, vertical: true)
                        }

                        Divider().overlay(theme.stroke)

                        VStack(alignment: .leading, spacing: 10) {
                            labeledToggle(L("同时复制到剪贴板"), isOn: $copyClipboard) {
                                AppSettings.shared.copyToClipboard = $0
                            }
                            labeledToggle(L("截图提示音"), isOn: $playSound) {
                                AppSettings.shared.playSound = $0
                            }
                            labeledToggle(L("显示放大镜与取色"), isOn: $showMagnifier) {
                                AppSettings.shared.showMagnifier = $0
                            }
                            labeledToggle(L("截图加水印"), isOn: $watermarkEnabled) {
                                AppSettings.shared.watermarkEnabled = $0
                                ToastController.shared.show($0 ? L("已加水印") : L("已取消水印"))
                            }
                            labeledToggle(L("在程序坞显示图标"), isOn: $showInDock) { newValue in
                                AppSettings.shared.showInDock = newValue
                                NSApp.setActivationPolicy(newValue ? .regular : .accessory)
                            }
                        }
                    }
                }

                settingsBlock(title: L("截图翻译"), subtitle: L("自动识别截图文字的语言，再译到你选择的目标语言")) {
                    VStack(alignment: .leading, spacing: 10) {
                        HStack {
                            Text(L("目标语言"))
                                .font(.system(size: 12, weight: .semibold))
                                .foregroundStyle(theme.textPrimary)
                            Spacer()
                            Picker("", selection: $translateTarget) {
                                ForEach(TranslateTargetLanguage.allCases) { language in
                                    Text(language.displayName).tag(language)
                                }
                            }
                            .labelsHidden()
                            .frame(width: 140)
                            .onChange(of: translateTarget) { _, newValue in
                                AppSettings.shared.translateTargetLanguage = newValue
                                ToastController.shared.show(L("翻译目标：%@", newValue.displayName))
                            }
                        }
                        Text(L("任务栏、菜单「翻译」、编辑器和历史里的翻译都会先识字、判断原文语言，再译到这里设置的语言。"))
                            .font(.system(size: 10))
                            .foregroundStyle(theme.textMuted)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }

                settingsBlock(title: L("隐私安全"), subtitle: L("截图完成或复制分享前，在本机检查敏感内容")) {
                    VStack(alignment: .leading, spacing: 10) {
                        labeledToggle(L("隐私安全模式"), isOn: $privacyMode) {
                            AppSettings.shared.privacyModeEnabled = $0
                        }
                        labeledToggle(L("发现后自动遮挡"), isOn: $privacyAutoRedact) {
                            AppSettings.shared.privacyAutoRedact = $0
                        }
                        .disabled(!privacyMode)
                        .opacity(privacyMode ? 1 : 0.45)
                        Text(L("检测 API Key、助记词、私钥、钱包地址、银行卡、证件、邮箱、电话、客户资料、二维码、Cookie / Token。关闭自动遮挡时，可选择「脱敏后分享」或「原图仅本地保存」。"))
                            .font(.system(size: 10))
                            .foregroundStyle(theme.textMuted)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }

                settingsBlock(title: L("保存"), subtitle: L("图片格式与目录")) {
                    VStack(alignment: .leading, spacing: 14) {
                        HStack {
                            Text(L("图片格式"))
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

                        pathRow(title: L("截图保存位置"), path: savePath) { chooseFolder() }
                        pathRow(title: L("新建文档位置"), path: documentPath) { chooseDocumentFolder() }
                    }
                }

                settingsBlock(title: L("快捷键"), subtitle: L("默认 ⌘⌥，避开系统截图 ⌘⇧3/4/5")) {
                    VStack(alignment: .leading, spacing: 10) {
                        KeyRecorderButton(title: L("区域截图"), shortcut: $area) { save(.area, $0) }
                        KeyRecorderButton(title: L("窗口截图"), shortcut: $window) { save(.window, $0) }
                        KeyRecorderButton(title: L("全屏截图"), shortcut: $screen) { save(.screen, $0) }
                        KeyRecorderButton(title: L("延时截图"), shortcut: $delay) { save(.delay, $0) }
                        KeyRecorderButton(title: L("长截图"), shortcut: $longShot) { save(.longShot, $0) }
                        KeyRecorderButton(title: L("翻译"), shortcut: $translate) { save(.translate, $0) }
                        KeyRecorderButton(title: L("屏幕录制"), shortcut: $record) { save(.record, $0) }
                        KeyRecorderButton(title: L("历史记录"), shortcut: $history) { save(.history, $0) }

                        if let hotkeyError {
                            Text(hotkeyError)
                                .font(.caption)
                                .foregroundStyle(theme.warning)
                        }

                        Button(L("恢复默认快捷键")) {
                            AppSettings.shared.resetHotkeys()
                            reloadShortcuts()
                            HotKeyManager.shared.registerDefaults()
                            StatusBarController.shared?.reloadMenu()
                            MainMenuController.shared?.reload()
                            hotkeyError = nil
                            ToastController.shared.show(L("已恢复默认快捷键"))
                        }
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(theme.textSecondary)
                        .buttonStyle(.plain)
                    }
                }

                settingsBlock(title: L("权限"), subtitle: L("授权一次即可；打开开关后若仍不能截图，点重启")) {
                    VStack(alignment: .leading, spacing: 10) {
                        HStack {
                            Text(L("屏幕录制"))
                                .font(.system(size: 12, weight: .medium))
                                .foregroundStyle(theme.textPrimary)
                            Spacer()
                            Text(permissionLabel)
                                .font(.system(size: 12, weight: .semibold))
                                .foregroundStyle(permissionOK ? theme.success : theme.warning)
                        }
                        FlareSecondaryButton(title: L("检查并修复权限"), glyph: .permission) {
                            Permissions.promptScreenCaptureFromUser()
                            refreshPermissionLabel()
                        }
                        FlareSecondaryButton(title: L("打开系统设置"), glyph: .settings) {
                            Permissions.openScreenRecordingSettings()
                        }
                        FlarePrimaryButton(title: L("重启 %@", FlareBrand.name), glyph: .relaunch) {
                            Permissions.relaunchApp()
                        }
                        Text(Permissions.runningFromApplications()
                             ? L("正在从 /Applications/Flare Pro.app 运行。")
                             : L("⚠ 当前路径：%@。请改用「应用程序」中的副本。", Bundle.main.bundlePath))
                            .font(.caption)
                            .foregroundStyle(Permissions.runningFromApplications() ? theme.textMuted : theme.warning)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }

                settingsBlock(title: L("关于"), subtitle: FlareBrand.tagline) {
                    VStack(alignment: .leading, spacing: 12) {
                        HStack(spacing: 12) {
                            FlareBrandMark(size: 32, cornerRadius: 8)
                            VStack(alignment: .leading, spacing: 3) {
                                Text(FlareBrand.name)
                                    .font(.system(size: 14, weight: .semibold))
                                    .foregroundStyle(theme.textPrimary)
                                Text(L("版本 %@ (%@) · %@", UpdateChecker.currentVersion, UpdateChecker.currentBuild, archLabel))
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
                            FlarePrimaryButton(title: checkingUpdate ? L("检查中…") : L("检查更新"), glyph: .refresh) {
                                Task { await runUpdateCheck() }
                            }
                            .disabled(checkingUpdate)

                            FlareSecondaryButton(title: L("官网"), glyph: .home) {
                                openURL(FlareBrand.websiteURL)
                            }
                            FlareSecondaryButton(title: "GitHub", glyph: .documents) {
                                openURL(FlareBrand.githubURL)
                            }
                        }

                        VStack(alignment: .leading, spacing: 6) {
                            linkRow(L("官方网站"), FlareBrand.websiteURL)
                            linkRow(L("下载页面"), FlareBrand.downloadURL)
                            linkRow(L("问题反馈"), FlareBrand.supportEmail)
                        }
                        .padding(.top, 4)
                    }
                }
            }
            .padding(.horizontal, 28)
            .padding(.top, 40)
            .padding(.bottom, 32)
            .foregroundStyle(theme.textPrimary)
        }
        .onAppear { reloadShortcuts() }
        .task { refreshPermissionLabel() }
        .onReceive(NotificationCenter.default.publisher(for: .flarePermissionChanged)) { _ in
            refreshPermissionLabel()
        }
        .onReceive(NotificationCenter.default.publisher(for: .flareSettingsChanged)) { _ in
            reloadShortcuts()
            afterAction = AppSettings.shared.afterCaptureAction
            translateTarget = AppSettings.shared.translateTargetLanguage
            format = AppSettings.shared.imageFormat
            copyClipboard = AppSettings.shared.copyToClipboard
            playSound = AppSettings.shared.playSound
            showMagnifier = AppSettings.shared.showMagnifier
            watermarkEnabled = AppSettings.shared.watermarkEnabled
            historyRetention = AppSettings.shared.historyRetention
            savePath = AppSettings.shared.saveDirectory.path
            documentPath = AppSettings.shared.documentDirectory.path
            showInDock = AppSettings.shared.showInDock
            privacyMode = AppSettings.shared.privacyModeEnabled
            privacyAutoRedact = AppSettings.shared.privacyAutoRedact
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
            updateStatus = L("正在检查…")
        }
        let result = await UpdateChecker.check()
        await MainActor.run {
            checkingUpdate = false
            switch result {
            case .upToDate(let current):
                updateStatus = L("已是最新版 %@", current)
                ToastController.shared.show(updateStatus)
            case .updateAvailable(let remote):
                updateStatus = L("发现新版本 %@", remote.version)
                let alert = NSAlert()
                alert.messageText = L("发现新版本 %@", remote.version)
                alert.informativeText = (remote.notes?.isEmpty == false)
                    ? (remote.notes ?? "")
                    : L("当前 %@，建议前往官网下载。", UpdateChecker.currentVersion)
                alert.addButton(withTitle: L("前往下载"))
                alert.addButton(withTitle: L("稍后再说"))
                if alert.runModal() == .alertFirstButtonReturn {
                    openURL(remote.downloadURL ?? FlareBrand.downloadURL)
                }
            case .failed(let message):
                updateStatus = L("检查失败：%@", message)
                ToastController.shared.show(updateStatus)
            }
        }
    }

    private func refreshPermissionLabel() {
        switch Permissions.currentState() {
        case .granted:
            permissionLabel = L("已就绪")
            permissionOK = true
        case .needsRelaunch:
            permissionLabel = L("需重启生效")
            permissionOK = false
        case .unknown:
            permissionLabel = L("检查中…")
            permissionOK = false
        case .denied:
            permissionLabel = L("未授权")
            permissionOK = false
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
            Button(L("选择…"), action: choose)
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
            (.area, area), (.window, window), (.screen, screen), (.delay, delay), (.longShot, longShot), (.translate, translate), (.record, record), (.history, history)
        ]
        if let conflict = others.first(where: { $0.0 != action && $0.1 == shortcut }) {
            hotkeyError = L("与「%@」冲突，请换一组快捷键", conflict.0.title)
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
        longShot = AppSettings.shared.shortcut(for: .longShot)
        translate = AppSettings.shared.shortcut(for: .translate)
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

private struct LogoPickerRow: View {
    @Environment(\.flareTheme) private var theme
    @State private var kind = AppSettings.shared.logoKind

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(L("菜单栏与应用内 Logo"))
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(theme.textPrimary)
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 72), spacing: 10)], alignment: .leading, spacing: 12) {
                ForEach(AppLogoKind.presets) { item in
                    Button {
                        AppSettings.shared.logoKind = item
                        kind = item
                    } label: {
                        VStack(spacing: 6) {
                            logoThumb(LogoCatalog.presetImage(item), selected: kind == item)
                            Text(item.title)
                                .font(.system(size: 10, weight: kind == item ? .semibold : .regular))
                                .foregroundStyle(kind == item ? theme.accent : theme.textMuted)
                                .lineLimit(1)
                        }
                        .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.plain)
                }

                Button(action: pickCustom) {
                    VStack(spacing: 6) {
                        logoThumb(
                            kind == .custom ? LogoCatalog.currentImage() : nil,
                            selected: kind == .custom,
                            placeholder: L("自选")
                        )
                        Text(L("自选图片"))
                            .font(.system(size: 10, weight: kind == .custom ? .semibold : .regular))
                            .foregroundStyle(kind == .custom ? theme.accent : theme.textMuted)
                    }
                    .frame(maxWidth: .infinity)
                }
                .buttonStyle(.plain)
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .flareSettingsChanged)) { _ in
            kind = AppSettings.shared.logoKind
        }
    }

    private func logoThumb(_ image: NSImage?, selected: Bool, placeholder: String? = nil) -> some View {
        ZStack {
            if let image {
                Image(nsImage: image)
                    .resizable()
                    .interpolation(.high)
                    .aspectRatio(contentMode: .fit)
            } else {
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(Color(red: 0.12, green: 0.12, blue: 0.13))
                if let placeholder {
                    Text(placeholder)
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(.white.opacity(0.7))
                }
            }
        }
        .frame(width: 40, height: 40)
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .strokeBorder(selected ? theme.accent : theme.stroke, lineWidth: selected ? 2 : 1)
        )
    }

    private func pickCustom() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = false
        panel.allowedFileTypes = ["png", "jpg", "jpeg", "heic", "tif", "tiff", "webp"]
        panel.title = L("选择 Logo 图片")
        guard panel.runModal() == .OK, let url = panel.url else { return }
        if LogoCatalog.installCustom(from: url) {
            kind = .custom
            ToastController.shared.show(L("已更换 Logo"))
        } else {
            ToastController.shared.show(L("无法读取这张图片"))
        }
    }
}

/// 兼容旧测试/引用名
typealias SettingsView = SettingsPane
