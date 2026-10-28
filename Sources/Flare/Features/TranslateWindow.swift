import AppKit
import NaturalLanguage
import SwiftUI

final class TranslateWindowController {
    static let shared = TranslateWindowController()

    private var window: NSWindow?
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

    func present(image: NSImage) {
        let theme = ThemeController.shared.palette
        let root = TranslateRootView(image: image, onClose: { [weak self] in self?.close() })
            .environment(\.flareTheme, theme)
            .preferredColorScheme(theme.preferredColorScheme)

        let hosting = NSHostingController(rootView: root)
        if let window {
            window.contentViewController = hosting
            window.makeKeyAndOrderFront(nil)
        } else {
            let window = NSWindow(
                contentRect: NSRect(x: 0, y: 0, width: 720, height: 620),
                styleMask: [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView],
                backing: .buffered,
                defer: false
            )
            window.title = "截图翻译"
            window.titlebarAppearsTransparent = true
            window.isMovableByWindowBackground = true
            window.contentViewController = hosting
            window.center()
            window.setFrameAutosaveName("FlareTranslate")
            window.isReleasedWhenClosed = false
            window.minSize = NSSize(width: 560, height: 480)
            self.window = window
            window.makeKeyAndOrderFront(nil)
        }
        applyWindowChrome()
        NSApp.activate(ignoringOtherApps: true)
    }

    private func applyWindowChrome() {
        guard let window, window.isVisible else { return }
        FlareWindowChrome.apply(window)
    }

    private func close() {
        window?.orderOut(nil)
    }
}

private enum TranslatePhase: Equatable {
    case recognizing
    case translating
    case done
    case empty
    case skipped
    case failed(String)
}

struct TranslateRootView: View {
    let image: NSImage
    let onClose: () -> Void

    @ObservedObject private var themeController = ThemeController.shared
    @State private var target = AppSettings.shared.translateTargetLanguage
    @State private var original = ""
    @State private var translated = ""
    @State private var detected: NLLanguage?
    @State private var phase: TranslatePhase = .recognizing
    @State private var jobID = 0

    private var theme: FlarePalette { themeController.palette }

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider().overlay(theme.stroke)
            content
            Divider().overlay(theme.stroke)
            footer
        }
        .background(ThemeCanvas(palette: theme, opacity: themeController.windowOpacity))
        .environment(\.flareTheme, theme)
        .preferredColorScheme(theme.preferredColorScheme)
        .task { await recognizeAndTranslate() }
        .onReceive(NotificationCenter.default.publisher(for: .flareSettingsChanged)) { _ in
            let next = AppSettings.shared.translateTargetLanguage
            guard next != target else { return }
            target = next
            retryTranslate()
        }
    }

    private var header: some View {
        HStack(spacing: 12) {
            SnapIcon(.translate, size: .title, opacity: 1, tint: theme.textPrimary)
            VStack(alignment: .leading, spacing: 2) {
                Text("截图翻译")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(theme.textPrimary)
                Text(statusLine)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(theme.textMuted)
            }
            Spacer(minLength: 8)
            VStack(alignment: .trailing, spacing: 4) {
                Text("目标语言")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(theme.textMuted)
                Picker("", selection: $target) {
                    ForEach(TranslateTargetLanguage.allCases) { language in
                        Text(language.displayName).tag(language)
                    }
                }
                .labelsHidden()
                .frame(width: 128)
                .onChange(of: target) { _, newValue in
                    AppSettings.shared.translateTargetLanguage = newValue
                    retryTranslate()
                }
            }
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 14)
    }

    private var content: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .top, spacing: 14) {
                Image(nsImage: image)
                    .resizable()
                    .scaledToFit()
                    .frame(maxWidth: 220, maxHeight: 120)
                    .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                    .overlay(
                        RoundedRectangle(cornerRadius: 10, style: .continuous)
                            .strokeBorder(theme.stroke, lineWidth: 1)
                    )
                VStack(alignment: .leading, spacing: 8) {
                    infoChip("原文语言", detectedName)
                    infoChip("目标语言", target.displayName)
                    Text("框选后自动识字、判断语言，再译到设置里的目标语言。")
                        .font(.system(size: 11))
                        .foregroundStyle(theme.textMuted)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 0)
            }

            textBlock(title: "原文", text: $original, placeholder: "正在识别…")
            textBlock(title: "译文", text: $translated, placeholder: translationPlaceholder)
        }
        .padding(20)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    private var footer: some View {
        HStack(spacing: 10) {
            FlareSecondaryButton(title: "复制原文", glyph: .copy) {
                copy(original, toast: "已复制原文")
            }
            .disabled(original.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            FlareSecondaryButton(title: "复制译文", glyph: .ocr) {
                copy(translated, toast: "已复制译文")
            }
            .disabled(translated.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            Spacer()
            FlareSecondaryButton(title: "重新翻译", glyph: .refresh, action: retryTranslate)
                .disabled(original.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            FlarePrimaryButton(title: "完成", glyph: .success, action: onClose)
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 12)
    }

    private var statusLine: String {
        switch phase {
        case .recognizing: return "正在识别文字并判断语言…"
        case .translating: return "已识别为\(detectedName)，正在译成\(target.displayName)…"
        case .done: return "\(detectedName) → \(target.displayName)"
        case .empty: return "没有识别到文字"
        case .skipped: return "原文已是\(target.displayName)"
        case .failed(let message): return message
        }
    }

    private var detectedName: String {
        TranslateTargetLanguage.displayName(for: detected)
    }

    private var translationPlaceholder: String {
        switch phase {
        case .recognizing: return "等待识别…"
        case .translating: return "正在翻译…"
        case .empty: return "未识别到文字"
        case .skipped: return "无需翻译"
        case .failed(let message): return message
        case .done: return "译文"
        }
    }

    private func infoChip(_ title: String, _ value: String) -> some View {
        HStack(spacing: 8) {
            Text(title)
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(theme.textMuted)
            Text(value)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(theme.textPrimary)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(theme.card)
                .overlay(
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .strokeBorder(theme.stroke, lineWidth: 1)
                )
        )
    }

    private func textBlock(title: String, text: Binding<String>, placeholder: String) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(theme.textSecondary)
            ZStack(alignment: .topLeading) {
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(theme.card)
                    .overlay(
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .strokeBorder(theme.stroke, lineWidth: 1)
                    )
                if text.wrappedValue.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    Text(placeholder)
                        .font(.system(size: 13))
                        .foregroundStyle(theme.textMuted)
                        .padding(12)
                }
                TextEditor(text: text)
                    .font(.system(size: 13))
                    .scrollContentBackground(.hidden)
                    .padding(6)
                    .frame(minHeight: 110)
            }
        }
    }

    private func recognizeAndTranslate() async {
        phase = .recognizing
        translated = ""
        let result = await OCRService.recognizeDetailed(image: image)
        await MainActor.run {
            original = result.text
            detected = result.language
            startTranslationIfNeeded()
        }
    }

    private func retryTranslate() {
        startTranslationIfNeeded()
    }

    private func startTranslationIfNeeded() {
        jobID += 1
        let id = jobID
        let trimmed = original.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            translated = ""
            phase = .empty
            return
        }
        if target.matches(detected) {
            translated = original
            phase = .skipped
            return
        }
        translated = ""
        phase = .translating
        let source = detectedName
        let language = target
        Task {
            do {
                let text = try await TranslateService.translate(
                    text: trimmed,
                    sourceName: source,
                    target: language
                )
                await MainActor.run {
                    guard id == jobID else { return }
                    translated = text
                    phase = .done
                }
            } catch {
                await MainActor.run {
                    guard id == jobID else { return }
                    phase = .failed(error.localizedDescription)
                }
            }
        }
    }

    private func copy(_ text: String, toast: String) {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
        ToastController.shared.show(toast)
    }
}
