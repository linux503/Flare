import AppKit
import SwiftUI

final class PermissionWindowController {
    static let shared = PermissionWindowController()
    private init() {}

    /// 在主窗口内以 sheet 展示，不新开窗口
    func show(preflightGranted: Bool, captureWorks: Bool) {
        HomeWindowController.shared.presentPermissionSheet(
            preflight: preflightGranted,
            works: captureWorks
        )
    }

    func close() {
        HomeWindowController.shared.dismissPermissionSheet()
    }
}

struct PermissionView: View {
    let preflightGranted: Bool
    let captureWorks: Bool
    @State private var checking = false
    @State private var statusText = ""
    @State private var livePreflight = false
    @State private var liveReady = false
    @State private var needsRelaunch = false
    @Environment(\.dismiss) private var dismiss
    @Environment(\.flareTheme) private var theme

    private var runningPath: String { Bundle.main.bundlePath }
    private var fromApps: Bool { Permissions.runningFromApplications() }

    var body: some View {
        ZStack {
            ThemeCanvas(palette: theme)

            VStack(alignment: .leading, spacing: 18) {
                HStack(spacing: 12) {
                    SnapIconWell(.permission, side: 44, iconSize: .hero, cornerRadius: 12)
                    VStack(alignment: .leading, spacing: 4) {
                        Text(needsRelaunch ? "权限已打开，需要重启" : (Permissions.needsReauthorizationAfterUpdate() ? "需要重新授权" : "无法截取屏幕"))
                            .font(.system(size: 22, weight: .bold, design: .serif))
                            .foregroundStyle(theme.textPrimary)
                        Text(needsRelaunch
                             ? "系统已授权，但必须完全重启后 ScreenCaptureKit 才会生效"
                             : Permissions.permissionIssueSummary())
                            .font(.subheadline)
                            .foregroundStyle(theme.textSecondary)
                    }
                    Spacer()
                    Button {
                        dismissSheet()
                    } label: {
                        SnapIcon(.close, size: .title, opacity: 0.4)
                    }
                    .buttonStyle(.plain)
                }

                VStack(alignment: .leading, spacing: 10) {
                    step(1, "点击「打开系统设置」")
                    step(2, "找到「屏幕与系统音频录制」→ \(FlareBrand.name)，打开开关")
                    step(3, needsRelaunch
                         ? "回到这里点「重启」；或等自动重启"
                         : "打开开关后回到这里；检测到授权会自动重启")
                }
                .padding(14)
                .background(theme.fill)
                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .strokeBorder(theme.stroke, lineWidth: 1)
                )

                HStack(spacing: 10) {
                    statusDot(livePreflight, "系统已记录授权")
                    statusDot(liveReady, "截屏已可用")
                }

                if !fromApps {
                    Text("当前不是从「应用程序」启动（\(runningPath)）。请只授权 /Applications/Flare Pro.app，否则开关无效。")
                        .font(.caption)
                        .foregroundStyle(theme.warning)
                        .fixedSize(horizontal: false, vertical: true)
                }

                if !statusText.isEmpty {
                    Text(statusText)
                        .font(.caption)
                        .foregroundStyle(theme.accent)
                }

                Text(Permissions.diagnosticDetails())
                    .font(.caption2)
                    .foregroundStyle(theme.textMuted)
                    .fixedSize(horizontal: false, vertical: true)

                if Permissions.needsReauthorizationAfterUpdate() {
                    Text("若系统设置里已有开关：先点 − 删除所有 Flare Pro，再重新打开开关，然后 ⌘Q 完全退出并重启本应用。")
                        .font(.caption)
                        .foregroundStyle(theme.warning)
                        .fixedSize(horizontal: false, vertical: true)
                }

                if Permissions.isAdHocSigned() {
                    Text("当前是临时签名：每次重新安装系统都会当成新应用，必须删除旧条目再勾选。请用 Scripts/install.sh 以开发者证书签名。")
                        .font(.caption)
                        .foregroundStyle(theme.warning)
                        .fixedSize(horizontal: false, vertical: true)
                }

                Spacer(minLength: 0)

                HStack(spacing: 10) {
                    Button {
                        Permissions.openScreenRecordingSettings()
                    } label: {
                        labelButton("打开系统设置", .settings, primary: !needsRelaunch)
                    }
                    .buttonStyle(.plain)

                    Button {
                        requestAndCheck()
                    } label: {
                        labelButton(checking ? "检测中…" : "重新检测", .refresh, primary: false)
                    }
                    .buttonStyle(.plain)
                    .disabled(checking)

                    Button {
                        Permissions.relaunchApp()
                    } label: {
                        labelButton("重启 \(FlareBrand.name)", .relaunch, primary: needsRelaunch)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(28)
        }
        .onAppear {
            livePreflight = preflightGranted
            liveReady = captureWorks
            applyState(Permissions.currentState())
            Permissions.startPolling()
        }
        .onReceive(NotificationCenter.default.publisher(for: .flarePermissionChanged)) { note in
            let state = (note.userInfo?["state"] as? String) ?? ""
            livePreflight = Permissions.hasScreenRecordingPermission
            liveReady = state == "granted"
            needsRelaunch = state == "needsRelaunch"
            if state == "granted" {
                statusText = "授权成功"
            } else if state == "needsRelaunch" {
                statusText = "权限已打开，正在重启…"
            }
        }
    }

    private func applyState(_ state: PermissionState) {
        switch state {
        case .granted:
            livePreflight = true
            liveReady = true
            needsRelaunch = false
            statusText = "已就绪"
        case .needsRelaunch:
            livePreflight = true
            liveReady = false
            needsRelaunch = true
            statusText = "权限已打开，请重启生效"
        case .denied:
            livePreflight = false
            liveReady = false
            needsRelaunch = false
            statusText = "请在系统设置中打开 \(FlareBrand.name) 的屏幕录制开关"
        case .unknown:
            livePreflight = true
            liveReady = false
            needsRelaunch = false
            statusText = "正在确认权限…"
        }
    }

    private func dismissSheet() {
        dismiss()
        PermissionWindowController.shared.close()
    }

    private func step(_ n: Int, _ text: String) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Text("\(n)")
                .font(.system(size: 11, weight: .bold, design: .rounded))
                .foregroundStyle(theme.inverseText)
                .frame(width: 20, height: 20)
                .background(theme.inverseFill)
                .clipShape(Circle())
            Text(text)
                .font(.system(size: 13))
                .foregroundStyle(theme.textSecondary)
        }
    }

    private func statusDot(_ ok: Bool, _ text: String) -> some View {
        HStack(spacing: 6) {
            Circle()
                .fill(ok ? theme.success : theme.warning)
                .frame(width: 8, height: 8)
            Text(text)
                .font(.caption)
                .foregroundStyle(theme.textSecondary)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(theme.fillStrong)
        .clipShape(Capsule())
    }

    private func labelButton(_ title: String, _ glyph: SnapGlyph, primary: Bool) -> some View {
        HStack(spacing: 6) {
            SnapIcon(
                glyph,
                size: .caption,
                opacity: 1,
                tint: primary ? theme.inverseText : theme.textPrimary
            )
            Text(title)
                .font(.system(size: 12, weight: .semibold))
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 9)
        .background(primary ? theme.inverseFill : theme.fillStrong)
        .foregroundStyle(primary ? theme.inverseText : theme.textPrimary)
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
    }

    private func requestAndCheck() {
        checking = true
        statusText = ""
        Task {
            try? await Task.sleep(nanoseconds: 450_000_000)
            let ok = await Permissions.verifyAccessSilently()
            let state = await Permissions.strictState()
            await MainActor.run {
                checking = false
                applyState(state)
                switch state {
                case .granted:
                    ToastController.shared.show("授权成功")
                    dismissSheet()
                case .needsRelaunch:
                    statusText = "权限已打开，请完全退出后重新打开 Flare Pro"
                case .denied, .unknown:
                    statusText = ok
                        ? "请再试一次截图"
                        : "仍未授权：请打开开关（若有灰色旧条目，先 − 删除再勾选）"
                }
            }
        }
    }
}
