import AppKit
import SwiftUI

enum MainTab: String, CaseIterable, Identifiable {
    case home, record, mailbox, documents, history, settings
    var id: String { rawValue }
    var title: String {
        switch self {
        case .home: return L("截图")
        case .record: return L("录制")
        case .mailbox: return L("临邮")
        case .documents: return L("新建")
        case .history: return L("历史")
        case .settings: return L("设置")
        }
    }
    var glyph: SnapGlyph {
        switch self {
        case .home: return .area
        case .record: return .record
        case .mailbox: return .mail
        case .documents: return .documents
        case .history: return .history
        case .settings: return .settings
        }
    }

    static let captureTabs: [MainTab] = [.home, .record]
    static let toolTabs: [MainTab] = [.mailbox, .documents]
    static let libraryTabs: [MainTab] = [.history]
}

final class HomeWindowController {
    static let shared = HomeWindowController()
    private var window: NSWindow?
    private var model = MainShellModel()
    private var themeObserver: NSObjectProtocol?

    private init() {
        themeObserver = NotificationCenter.default.addObserver(
            forName: .flareThemeChanged,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            self?.applyWindowChrome()
        }
    }

    static func isHomeWindow(_ window: NSWindow) -> Bool {
        window.identifier?.rawValue == "FlareHome" || window.frameAutosaveName == "FlareHome"
    }

    func show(tab: MainTab = .home) {
        model.tab = tab
        if window == nil {
            let hosting = NSHostingController(rootView: MainShellView(model: model))
            let window = NSWindow(
                contentRect: NSRect(x: 0, y: 0, width: 980, height: 660),
                styleMask: [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView],
                backing: .buffered,
                defer: false
            )
            window.identifier = NSUserInterfaceItemIdentifier("FlareHome")
            window.title = FlareBrand.name
            window.titlebarAppearsTransparent = true
            window.titleVisibility = .hidden
            window.isMovableByWindowBackground = true
            window.contentViewController = hosting
            window.center()
            window.setFrameAutosaveName("FlareHome")
            window.isReleasedWhenClosed = false
            window.minSize = NSSize(width: 860, height: 580)
            window.animationBehavior = .utilityWindow
            self.window = window
            applyWindowChrome()
        }
        window?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    private func applyWindowChrome() {
        guard let window else { return }
        let palette = ThemeController.shared.palette
        let opacity = CGFloat(ThemeController.shared.windowOpacity)
        window.appearance = palette.nsAppearance
        if opacity < 0.995 {
            window.isOpaque = false
            window.backgroundColor = palette.windowNS.withAlphaComponent(opacity)
        } else {
            window.isOpaque = true
            window.backgroundColor = palette.windowNS
        }
    }

    func showSettings() { show(tab: .settings) }
    func showHistory() { show(tab: .history) }
    func showDocuments() { show(tab: .documents) }
    func showRecord() { show(tab: .record) }
    func showMailbox() { show(tab: .mailbox) }

    func presentPermissionSheet(preflight: Bool, works: Bool) {
        show(tab: .home)
        model.permissionSheet = PermissionSheetState(preflight: preflight, works: works)
    }

    func dismissPermissionSheet() {
        model.permissionSheet = nil
    }

    func showAbout() {
        show(tab: .settings)
        ToastController.shared.show("\(FlareBrand.name) \(FlareBrand.version)")
    }
}

final class MainShellModel: ObservableObject {
    @Published var tab: MainTab = .home
    @Published var permissionSheet: PermissionSheetState?
    /// 官网有新版时展示提醒条；用户点「稍后」会记住版本号，下次同版本不再弹
    @Published var availableUpdate: UpdateChecker.RemoteVersion?

    private static let skippedKey = "flareSkippedUpdateVersion"

    @MainActor
    func applyUpdateCheck(_ result: UpdateChecker.CheckResult) {
        switch result {
        case .updateAvailable(let remote):
            let skipped = UserDefaults.standard.string(forKey: Self.skippedKey)
            if skipped != remote.version {
                availableUpdate = remote
            }
        case .upToDate, .failed:
            break
        }
    }

    @MainActor
    func dismissUpdate(skipVersion: Bool) {
        if skipVersion, let version = availableUpdate?.version {
            UserDefaults.standard.set(version, forKey: Self.skippedKey)
        }
        availableUpdate = nil
    }

    @MainActor
    func openUpdateDownload() {
        guard let remote = availableUpdate else { return }
        let link = remote.downloadURL.flatMap(URL.init(string:))
            ?? URL(string: FlareBrand.downloadURL)
            ?? URL(string: FlareBrand.websiteURL)
        if let link {
            NSWorkspace.shared.open(link)
        }
    }

    func refreshUpdateQuietly() async {
        guard !UpdateChecker.isMacAppStoreBuild else { return }
        let result = await UpdateChecker.check()
        await MainActor.run { applyUpdateCheck(result) }
    }
}

struct PermissionSheetState: Identifiable {
    let id = UUID()
    let preflight: Bool
    let works: Bool
}

struct MainShellView: View {
    @ObservedObject var model: MainShellModel
    @ObservedObject private var themeController = ThemeController.shared

    var body: some View {
        let theme = themeController.palette
        ZStack {
            ThemeCanvas(palette: theme, opacity: themeController.windowOpacity)

            HStack(spacing: 0) {
                sidebar(theme)
                    .frame(width: 188)

                Rectangle()
                    .fill(theme.stroke.opacity(0.7))
                    .frame(width: 1)

                VStack(spacing: 0) {
                    if let remote = model.availableUpdate {
                        updateBanner(remote, theme: theme)
                    }

                    tabContent
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .transaction { $0.animation = nil }
                }
            }
        }
        .environment(\.flareTheme, theme)
        .preferredColorScheme(theme.preferredColorScheme)
        .frame(minWidth: 860, minHeight: 580)
        .task {
            await model.refreshUpdateQuietly()
        }
        .sheet(item: $model.permissionSheet) { state in
            PermissionView(preflightGranted: state.preflight, captureWorks: state.works)
                .environment(\.flareTheme, theme)
                .preferredColorScheme(theme.preferredColorScheme)
                .frame(width: 520, height: 420)
        }
    }

    private func updateBanner(_ remote: UpdateChecker.RemoteVersion, theme: FlarePalette) -> some View {
        HStack(spacing: 12) {
            SnapIcon(.update, size: .body, opacity: 1, tint: theme.accent)
            VStack(alignment: .leading, spacing: 2) {
                Text(L("发现新版本 %@", remote.version))
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(theme.textPrimary)
                Text((remote.notes?.isEmpty == false) ? (remote.notes ?? "") : L("当前 %@，建议更新以获得更快体验。", UpdateChecker.currentVersion))
                    .font(.system(size: 11))
                    .foregroundStyle(theme.textMuted)
                    .lineLimit(2)
            }
            Spacer(minLength: 8)
            Button(L("立即更新")) {
                model.openUpdateDownload()
            }
            .font(.system(size: 12, weight: .semibold))
            .foregroundStyle(.white)
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .background(theme.accent, in: Capsule())
            .buttonStyle(.plain)

            Button(L("稍后")) {
                model.dismissUpdate(skipVersion: true)
            }
            .font(.system(size: 12, weight: .medium))
            .foregroundStyle(theme.textSecondary)
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 12)
        .background(theme.fillStrong.opacity(0.95))
        .overlay(alignment: .bottom) {
            Rectangle()
                .fill(theme.stroke)
                .frame(height: 1)
        }
    }

    @ViewBuilder
    private var tabContent: some View {
        switch model.tab {
        case .home:
            HomePane(
                onOpenSettings: { select(.settings) },
                onOpenHistory: { select(.history) }
            )
        case .record:
            RecordPane()
        case .mailbox:
            MailboxPane()
        case .documents:
            DocumentsPane()
        case .history:
            HistoryPane()
        case .settings:
            SettingsPane(onBack: { select(.home) })
        }
    }

    private func select(_ tab: MainTab) {
        guard model.tab != tab else { return }
        model.tab = tab
    }

    private func sidebar(_ theme: FlarePalette) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 9) {
                FlareBrandMark(size: 28, cornerRadius: 7)
                VStack(alignment: .leading, spacing: 1) {
                    Text(FlareBrand.name)
                        .font(.system(size: 14, weight: .bold, design: .rounded))
                        .foregroundStyle(theme.textPrimary)
                    Text(FlareBrand.tagline)
                        .font(.system(size: 10, weight: .medium))
                        .foregroundStyle(theme.textMuted)
                }
            }
            .padding(.leading, 14)
            .padding(.trailing, 10)
            .padding(.top, 42)
            .padding(.bottom, 10)

            VStack(alignment: .leading, spacing: 2) {
                sidebarSection(L("捕获"), tabs: MainTab.captureTabs, theme: theme)
                sidebarSection(L("工具"), tabs: MainTab.toolTabs, theme: theme)
                sidebarSection(L("资料"), tabs: MainTab.libraryTabs, theme: theme)
            }
            .padding(.horizontal, 8)

            Spacer(minLength: 8)

            VStack(alignment: .leading, spacing: 8) {
                if model.availableUpdate != nil {
                    Button {
                        model.openUpdateDownload()
                    } label: {
                        HStack(spacing: 6) {
                            Circle()
                                .fill(theme.accent)
                                .frame(width: 6, height: 6)
                            Text(L("有新版本"))
                                .font(.system(size: 11, weight: .semibold))
                        }
                        .foregroundStyle(theme.accent)
                    }
                    .buttonStyle(.plain)
                    .padding(.horizontal, 10)
                }

                SidebarNavRow(
                    tab: .settings,
                    selected: model.tab == .settings,
                    theme: theme
                ) {
                    select(.settings)
                }
                .padding(.horizontal, 8)

                HStack {
                    Text("v\(FlareBrand.version)")
                        .font(.system(size: 11, weight: .medium, design: .monospaced))
                        .foregroundStyle(theme.textMuted.opacity(0.8))
                    Spacer()
                    Button(L("检查更新")) {
                        Task { await UpdateChecker.checkAndPrompt() }
                    }
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(theme.textMuted)
                    .buttonStyle(.plain)
                }
                .padding(.horizontal, 14)
            }
            .padding(.bottom, 16)
        }
        .background {
            ZStack {
                if themeController.windowOpacity < 0.98 {
                    VisualEffectView(
                        material: theme.isDark ? .sidebar : .headerView,
                        blendingMode: .withinWindow
                    )
                }
                theme.sidebar.opacity(themeController.windowOpacity < 0.98 ? 0.55 : 0.96)
            }
        }
    }

    @ViewBuilder
    private func sidebarSection(_ title: String, tabs: [MainTab], theme: FlarePalette) -> some View {
        Text(title)
            .font(.system(size: 10, weight: .semibold))
            .foregroundStyle(theme.textMuted)
            .padding(.horizontal, 10)
            .padding(.top, 12)
            .padding(.bottom, 4)
        ForEach(tabs) { tab in
            SidebarNavRow(
                tab: tab,
                selected: model.tab == tab,
                theme: theme
            ) {
                select(tab)
            }
        }
    }
}

private struct SidebarNavRow: View {
    let tab: MainTab
    let selected: Bool
    let theme: FlarePalette
    let action: () -> Void
    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 8) {
                RoundedRectangle(cornerRadius: 1.5, style: .continuous)
                    .fill(selected ? theme.accent : Color.clear)
                    .frame(width: 3, height: 14)
                SnapIcon(
                    tab.glyph,
                    size: .body,
                    opacity: selected ? 1 : (hovering ? 0.85 : 0.55),
                    tint: selected ? theme.textPrimary : theme.textMuted
                )
                Text(tab.title)
                    .font(.system(size: 13, weight: selected ? .semibold : .medium))
                Spacer(minLength: 0)
            }
            .padding(.trailing, 8)
            .padding(.vertical, 6)
            .background(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(selected ? theme.fillStrong : (hovering ? theme.fill : Color.clear))
            )
            .foregroundStyle(selected ? theme.textPrimary : theme.textSecondary)
            .contentShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
        .help(tab.title)
    }
}
