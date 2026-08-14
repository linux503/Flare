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
            window.title = FlareBrand.name
            window.titlebarAppearsTransparent = true
            window.titleVisibility = .hidden
            window.isMovableByWindowBackground = true
            window.contentViewController = hosting
            window.center()
            window.setFrameAutosaveName("FlareHome")
            window.isReleasedWhenClosed = false
            window.minSize = NSSize(width: 840, height: 580)
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
                    .frame(width: 200)

                Rectangle()
                    .fill(theme.stroke.opacity(0.85))
                    .frame(width: 1)

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
        .environment(\.flareTheme, theme)
        .preferredColorScheme(theme.preferredColorScheme)
        .frame(minWidth: 840, minHeight: 580)
        .sheet(item: $model.permissionSheet) { state in
            PermissionView(preflightGranted: state.preflight, captureWorks: state.works)
                .environment(\.flareTheme, theme)
                .preferredColorScheme(theme.preferredColorScheme)
                .frame(width: 520, height: 420)
        }
    }

    private func select(_ tab: MainTab) {
        withAnimation(.easeInOut(duration: 0.2)) {
            model.tab = tab
        }
    }

    private func sidebar(_ theme: FlarePalette) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 11) {
                FlareBrandMark(size: 34, cornerRadius: 9)
                VStack(alignment: .leading, spacing: 2) {
                    Text(FlareBrand.name)
                        .font(.system(size: 14, weight: .bold, design: .rounded))
                        .foregroundStyle(theme.textPrimary)
                    Text(FlareBrand.tagline)
                        .font(.system(size: 10, weight: .medium))
                        .foregroundStyle(theme.textMuted)
                }
            }
            .padding(.leading, 18)
            .padding(.trailing, 14)
            .padding(.top, 46)
            .padding(.bottom, 26)

            VStack(spacing: 3) {
                ForEach(MainTab.allCases) { tab in
                    Button {
                        select(tab)
                    } label: {
                        HStack(spacing: 10) {
                            SnapIcon(
                                tab.glyph,
                                size: .menu,
                                opacity: model.tab == tab ? 1 : 0.6,
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
                        .padding(.horizontal, 12)
                        .padding(.vertical, 9)
                        .background(
                            RoundedRectangle(cornerRadius: 9, style: .continuous)
                                .fill(model.tab == tab ? theme.fillStrong : Color.clear)
                        )
                        .foregroundStyle(model.tab == tab ? theme.textPrimary : theme.textSecondary)
                    }
                    .buttonStyle(FlareChipButtonStyle())
                }
            }
            .padding(.horizontal, 12)

            Spacer()

            VStack(alignment: .leading, spacing: 6) {
                Text(themeController.kind.title)
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(theme.textMuted)
                Text("v\(FlareBrand.version)")
                    .font(.system(size: 10, weight: .medium, design: .monospaced))
                    .foregroundStyle(theme.textMuted.opacity(0.85))
            }
            .padding(.horizontal, 22)
            .padding(.bottom, 18)
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
