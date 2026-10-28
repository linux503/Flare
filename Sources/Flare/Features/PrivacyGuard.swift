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

    /// 翻译走 OCR 文本，必须用原图识字。脱敏图会把字涂掉，导致译不出来。
    static func presentTranslate(from image: NSImage) async {
        TranslateWindowController.shared.present(image: image)
    }

    /// 复制到剪贴板。返回 false 表示用户选择了仅本地保存。
    @discardableResult
    static func copyIfAllowed(_ image: NSImage, localOnlyMessage: String = L("已取消分享，原图请只保存在本机")) async -> Bool {
        switch await plan(for: image) {
        case .original:
            ImageExporter.copyToClipboard(ScreenshotWatermark.applyIfNeeded(image))
            ToastController.shared.show(L("已复制到剪贴板"))
            return true
        case .redacted(let redacted):
            ImageExporter.copyToClipboard(ScreenshotWatermark.applyIfNeeded(redacted))
            ToastController.shared.show(L("已脱敏复制，原图未分享"))
            return true
        case .localOnly:
            ToastController.shared.show(localOnlyMessage)
            return false
        }
    }

    private static func ask(image: NSImage, findings: [PrivacyFinding]) -> PrivacySharePlan {
        let alert = NSAlert()
        alert.alertStyle = .warning
        alert.messageText = L("发现敏感信息")
        let kinds = PrivacyScanner.summary(of: findings)
        alert.informativeText = L("检测到：%@\n\n脱敏后分享：剪贴板 / 分享使用遮挡图，原图只留在本地历史。\n原图仅本地保存：不复制、不外发。\n检测只在本机进行。", kinds)
        alert.addButton(withTitle: L("脱敏后分享"))
        alert.addButton(withTitle: L("原图仅本地保存"))
        alert.addButton(withTitle: L("仍分享原图"))
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
