import AppKit
import SwiftUI

struct HomePane: View {
    var onOpenSettings: () -> Void
    var onOpenHistory: () -> Void

    @ObservedObject private var store = HistoryStore.shared
    @ObservedObject private var capture = CaptureCoordinator.shared
    @Environment(\.flareTheme) private var theme
    @State private var permissionOK: Bool? = nil
    @State private var permissionLabel = "检查中"
    @State private var shortcutTick = 0

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                topBar
                heroCapture
                secondaryRail
                if !store.items.isEmpty {
                    recentStrip
                } else {
                    tipRow
                }
            }
            .padding(.horizontal, 28)
            .padding(.top, 40)
            .padding(.bottom, 32)
        }
        .task { refreshPermission() }
        .onReceive(NotificationCenter.default.publisher(for: .flarePermissionChanged)) { _ in
            refreshPermission()
        }
        .onReceive(NotificationCenter.default.publisher(for: .flareSettingsChanged)) { _ in
            shortcutTick &+= 1
        }
    }

    private var topBar: some View {
        HStack(alignment: .center, spacing: 16) {
            VStack(alignment: .leading, spacing: 5) {
                Text("截图")
                    .font(.system(size: 26, weight: .bold, design: .rounded))
                    .foregroundStyle(theme.textPrimary)
                Text(capture.isCapturing ? "正在截图…" : "选区确认后可双击复制到剪贴板")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(theme.textMuted)
                    .animation(.easeOut(duration: 0.2), value: capture.isCapturing)
            }
            Spacer()
            permissionBadge
        }
    }

    private var permissionBadge: some View {
        Button {
            Permissions.promptScreenCaptureFromUser()
        } label: {
            HStack(spacing: 6) {
                SnapIcon(
                    permissionOK == true ? .success : .warning,
                    size: .caption,
                    opacity: 1,
                    tint: permissionOK == true ? theme.success : theme.warning
                )
                Text(permissionLabel)
                    .font(.system(size: 11, weight: .semibold))
            }
            .padding(.horizontal, 11)
            .padding(.vertical, 6)
            .background(
                Capsule().fill(theme.fillStrong)
            )
            .overlay(
                Capsule().strokeBorder(
                    permissionOK == true ? theme.success.opacity(0.35) : theme.strokeStrong,
                    lineWidth: 1
                )
            )
            .foregroundStyle(theme.textPrimary)
        }
        .buttonStyle(FlareChipButtonStyle())
        .help("检查屏幕录制权限")
    }

    private var heroCapture: some View {
        let _ = shortcutTick
        return Button {
            CaptureCoordinator.shared.startAreaCapture()
        } label: {
            HStack(alignment: .center, spacing: 16) {
                VStack(alignment: .leading, spacing: 6) {
                    Text("区域截图")
                        .font(.system(size: 17, weight: .bold, design: .rounded))
                        .foregroundStyle(theme.textPrimary)
                    Text("拖选画面后确认导出 · 菜单栏单击也可开始")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(theme.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                    Text(AppSettings.shared.shortcut(for: .area).displayString)
                        .font(.system(size: 10, weight: .semibold, design: .rounded))
                        .foregroundStyle(theme.textMuted)
                        .padding(.horizontal, 7)
                        .padding(.vertical, 3)
                        .background(theme.fillStrong)
                        .clipShape(RoundedRectangle(cornerRadius: 5, style: .continuous))
                }
                Spacer(minLength: 8)
                FlareBrandMark(size: 40, cornerRadius: 10)
            }
            .padding(14)
            .frame(maxWidth: .infinity, minHeight: 92, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .fill(theme.fill)
                    .overlay(
                        RoundedRectangle(cornerRadius: 18, style: .continuous)
                            .strokeBorder(theme.strokeStrong, lineWidth: 1)
                    )
            )
        }
        .buttonStyle(FlareCardButtonStyle(enabled: !capture.isCapturing))
        .disabled(capture.isCapturing)
    }

    private var secondaryRail: some View {
        let _ = shortcutTick
        return HStack(spacing: 10) {
            railItem("窗口", .window, .window) { CaptureCoordinator.shared.startWindowCapture() }
            railItem("全屏", .screen, .screen) { CaptureCoordinator.shared.startFullScreenCapture() }
            railItem("延时 3s", .delay, .delay) { CaptureCoordinator.shared.startDelayedCapture(seconds: 3) }
        }
    }

    private func railItem(_ title: String, _ glyph: SnapGlyph, _ action: HotKeyAction, run: @escaping () -> Void) -> some View {
        Button(action: run) {
            HStack(spacing: 9) {
                SnapIcon(glyph, size: .body, opacity: 0.9, tint: theme.textPrimary)
                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(theme.textPrimary)
                    Text(AppSettings.shared.shortcut(for: action).displayString)
                        .font(.system(size: 10, weight: .medium, design: .rounded))
                        .foregroundStyle(theme.textMuted)
                }
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 9)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(theme.fill)
                    .overlay(
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .strokeBorder(theme.stroke, lineWidth: 1)
                    )
            )
        }
        .buttonStyle(FlareCardButtonStyle(enabled: !capture.isCapturing))
        .disabled(capture.isCapturing)
    }

    private var tipRow: some View {
        HStack(spacing: 12) {
            SnapIcon(.tip, size: .body, opacity: 0.85, tint: theme.textSecondary)
            VStack(alignment: .leading, spacing: 3) {
                Text("更快开始")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(theme.textPrimary)
                Text("菜单栏图标单击 = 区域截图；侧栏「录制」可屏幕录制；设置里可切换主题。")
                    .font(.system(size: 11))
                    .foregroundStyle(theme.textMuted)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 8)
            Button("去录制") {
                HomeWindowController.shared.showRecord()
            }
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(theme.textPrimary)
                .buttonStyle(.plain)
                .padding(.horizontal, 10)
                .padding(.vertical, 5)
                .background(theme.fillStrong)
                .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
            Button("设置", action: onOpenSettings)
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(theme.textPrimary)
                .buttonStyle(.plain)
                .padding(.horizontal, 10)
                .padding(.vertical, 5)
                .background(theme.fillStrong)
                .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
        }
        .padding(14)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(theme.fill)
                .overlay(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .strokeBorder(theme.stroke, lineWidth: 1)
                )
        )
    }

    private var recentStrip: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("最近截图")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(theme.textSecondary)
                Spacer()
                Button("查看全部", action: onOpenHistory)
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(theme.textPrimary)
                    .buttonStyle(.plain)
            }
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 10) {
                    ForEach(Array(store.items.prefix(8))) { item in
                        Button {
                            if let image = store.image(for: item) {
                                EditorWindowController.shared.present(image: image)
                            }
                        } label: {
                            HistoryThumbnailView(item: item, height: 72)
                                .frame(width: 112)
                                .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                                .overlay(
                                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                                        .strokeBorder(theme.stroke, lineWidth: 1)
                                )
                        }
                        .buttonStyle(FlareCardButtonStyle())
                    }
                }
            }
        }
    }

    private func refreshPermission() {
        switch Permissions.currentState() {
            case .granted:
                permissionOK = true
                permissionLabel = "已就绪"
            case .needsRelaunch:
                permissionOK = false
                permissionLabel = "需重启"
            case .unknown:
                permissionOK = nil
                permissionLabel = "检查中"
            case .denied:
                permissionOK = false
                permissionLabel = "需授权"
        }
    }
}
