import AppKit
import SwiftUI

enum MainTab: String, CaseIterable, Identifiable {
    case home, record, documents, history, settings
    var id: String { rawValue }
    var title: String {
        switch self {
        case .home: return "截图"
        case .record: return "录制"
        case .documents: return "新建"
        case .history: return "历史"
        case .settings: return "设置"
        }
    }
    var glyph: SnapGlyph {
        switch self {
        case .home: return .area
        case .record: return .record
        case .documents: return .documents
        case .history: return .history
        case .settings: return .settings
        }
    }
}

final class HomeWindowController {
    static let shared = HomeWindowController()
    private var window: NSWindow?
    private var model = MainShellModel()
    private var themeObserver: NSObjectProtocol?
    private var settingsObserver: NSObjectProtocol?

    private init() {
        themeObserver = NotificationCenter.default.addObserver(
            forName: .flareThemeChanged,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            self?.applyWindowChrome()
        }
        settingsObserver = NotificationCenter.default.addObserver(
            forName: .flareSettingsChanged,
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
        withAnimation(.easeInOut(duration: 0.2)) {
            model.tab = tab
        }
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
            window.minSize = NSSize(width: 880, height: 580)
            window.animationBehavior = .documentWindow
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
                    .frame(width: 208)

                Rectangle()
                    .fill(theme.stroke.opacity(0.85))
                    .frame(width: 1)

                VStack(spacing: 0) {
                    if let remote = model.availableUpdate {
                        updateBanner(remote, theme: theme)
                    }

                    ZStack {
                        switch model.tab {
                        case .home:
                            HomePane(
                                onOpenSettings: { select(.settings) },
                                onOpenHistory: { select(.history) }
                            )
                            .flareTabTransition()
                            .id(MainTab.home)
                        case .record:
                            RecordPane()
                                .flareTabTransition()
                                .id(MainTab.record)
                        case .documents:
                            DocumentsPane()
                                .flareTabTransition()
                                .id(MainTab.documents)
                        case .history:
                            HistoryPane()
                                .flareTabTransition()
                                .id(MainTab.history)
                        case .settings:
                            SettingsPane(onBack: { select(.home) })
                                .flareTabTransition()
                                .id(MainTab.settings)
                        }
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .animation(.easeInOut(duration: 0.2), value: model.tab)
                }
            }
        }
        .environment(\.flareTheme, theme)
        .preferredColorScheme(theme.preferredColorScheme)
        .frame(minWidth: 880, minHeight: 580)
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
                Text("发现新版本 \(remote.version)")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(theme.textPrimary)
                Text((remote.notes?.isEmpty == false) ? (remote.notes ?? "") : "当前 \(UpdateChecker.currentVersion)，建议更新以获得更快体验。")
                    .font(.system(size: 11))
                    .foregroundStyle(theme.textMuted)
                    .lineLimit(2)
            }
            Spacer(minLength: 8)
            Button("立即更新") {
                model.openUpdateDownload()
            }
            .font(.system(size: 12, weight: .semibold))
            .foregroundStyle(.white)
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .background(theme.accent, in: Capsule())
            .buttonStyle(.plain)

            Button("稍后") {
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

    private func select(_ tab: MainTab) {
        withAnimation(.easeInOut(duration: 0.2)) {
            model.tab = tab
        }
    }

    private func sidebar(_ theme: FlarePalette) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 10) {
                FlareBrandMark(size: 32, cornerRadius: 8)
                VStack(alignment: .leading, spacing: 2) {
                    Text(FlareBrand.name)
                        .font(.system(size: 15, weight: .bold, design: .rounded))
                        .foregroundStyle(theme.textPrimary)
                    Text(FlareBrand.tagline)
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(theme.textMuted)
                }
            }
            .padding(.leading, 16)
            .padding(.trailing, 12)
            .padding(.top, 44)
            .padding(.bottom, 18)

            VStack(spacing: 2) {
                ForEach(MainTab.allCases) { tab in
                    Button {
                        select(tab)
                    } label: {
                        HStack(spacing: 10) {
                            SnapIcon(
                                tab.glyph,
                                size: .body,
                                opacity: model.tab == tab ? 1 : 0.55,
                                tint: model.tab == tab ? theme.textPrimary : theme.textMuted
                            )
                            Text(tab.title)
                                .font(.system(size: 13, weight: model.tab == tab ? .semibold : .medium))
                            Spacer()
                            if model.tab == tab {
                                Circle()
                                    .fill(theme.accent)
                                    .frame(width: 5, height: 5)
                            }
                        }
                        .padding(.horizontal, 10)
                        .padding(.vertical, 7)
                        .background(
                            RoundedRectangle(cornerRadius: 8, style: .continuous)
                                .fill(model.tab == tab ? theme.fillStrong : Color.clear)
                        )
                        .foregroundStyle(model.tab == tab ? theme.textPrimary : theme.textSecondary)
                    }
                    .buttonStyle(FlareChipButtonStyle())
                }
            }
            .padding(.horizontal, 10)

            Spacer()

            VStack(alignment: .leading, spacing: 8) {
                if model.availableUpdate != nil {
                    Button {
                        model.openUpdateDownload()
                    } label: {
                        HStack(spacing: 6) {
                            Circle()
                                .fill(theme.accent)
                                .frame(width: 6, height: 6)
                            Text("有新版本可更新")
                                .font(.system(size: 11, weight: .semibold))
                        }
                        .foregroundStyle(theme.accent)
                    }
                    .buttonStyle(.plain)
                }

                Button {
                    Task { await UpdateChecker.checkAndPrompt() }
                } label: {
                    Text("检查更新")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(theme.textMuted)
                }
                .buttonStyle(.plain)

                Text("v\(FlareBrand.version)")
                    .font(.system(size: 12, weight: .medium, design: .monospaced))
                    .foregroundStyle(theme.textMuted.opacity(0.85))
            }
            .padding(.horizontal, 24)
            .padding(.bottom, 20)
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
}
