import AppKit

enum PrivacySharePlan {
    case original
    case redacted(NSImage)
    case localOnly
}

/// 分享/复制前的隐私闸门。检测在本机完成，不上传图片。
@MainActor
enum PrivacyGuard {
    static func plan(for image: NSImage) async -> PrivacySharePlan {
        guard AppSettings.shared.privacyModeEnabled else { return .original }
        let findings = await PrivacyScanner.scan(image: image)
        guard !findings.isEmpty else { return .original }
        if AppSettings.shared.privacyAutoRedact {
            return .redacted(PrivacyScanner.redact(image, findings: findings))
        }
        return ask(image: image, findings: findings)
    }

    /// 复制到剪贴板。返回 false 表示用户选择了仅本地保存。
    @discardableResult
    static func copyIfAllowed(_ image: NSImage, localOnlyMessage: String = "已取消分享，原图请只保存在本机") async -> Bool {
        switch await plan(for: image) {
        case .original:
            ImageExporter.copyToClipboard(image)
            ToastController.shared.show("已复制到剪贴板")
            return true
        case .redacted(let redacted):
            ImageExporter.copyToClipboard(redacted)
            ToastController.shared.show("已脱敏复制，原图未分享")
            return true
        case .localOnly:
            ToastController.shared.show(localOnlyMessage)
            return false
        }
    }

    private static func ask(image: NSImage, findings: [PrivacyFinding]) -> PrivacySharePlan {
        let alert = NSAlert()
        alert.alertStyle = .warning
        alert.messageText = "发现敏感信息"
        let kinds = PrivacyScanner.summary(of: findings)
        alert.informativeText = """
        检测到：\(kinds)

        脱敏后分享：剪贴板 / 分享使用遮挡图，原图只留在本地历史。
        原图仅本地保存：不复制、不外发。
        检测只在本机进行。
        """
        alert.addButton(withTitle: "脱敏后分享")
        alert.addButton(withTitle: "原图仅本地保存")
        alert.addButton(withTitle: "仍分享原图")
        switch alert.runModal() {
        case .alertFirstButtonReturn:
            return .redacted(PrivacyScanner.redact(image, findings: findings))
        case .alertSecondButtonReturn:
            return .localOnly
        default:
            return .original
        }
    }
}
