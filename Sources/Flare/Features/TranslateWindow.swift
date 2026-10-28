import AppKit
import NaturalLanguage
import SwiftUI

@MainActor
final class TranslateWindowController {
    static let shared = TranslateWindowController()

    private var window: NSWindow?
    private var session: TranslateSession?
    private var themeObserver: NSObjectProtocol?

    private init() {
        themeObserver = NotificationCenter.default.addObserver(
            forName: .flareThemeChanged,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.applyWindowChrome() }
        }
    }

    func present(image: NSImage) {
        session?.cancel()
        let theme = ThemeController.shared.palette
        let session = TranslateSession(image: image)
        self.session = session
        let root = TranslateRootView(session: session, onClose: { [weak self] in self?.close() })
            .environment(\.flareTheme, theme)
            .preferredColorScheme(theme.preferredColorScheme)

        let hosting = NSHostingController(rootView: root)
        hosting.view.wantsLayer = true

        if let window {
            window.contentViewController = hosting
            fitFrame(window)
            bringForward(window)
        } else {
            let size = preferredSize()
            let window = NSWindow(
                contentRect: NSRect(origin: .zero, size: size),
                styleMask: [.titled, .closable, .miniaturizable, .resizable],
                backing: .buffered,
                defer: false
            )
            window.title = L("截图翻译")
            window.titleVisibility = .visible
            window.titlebarAppearsTransparent = false
            window.contentViewController = hosting
            window.isReleasedWhenClosed = false
            window.minSize = NSSize(width: 460, height: 380)
            window.maxSize = NSSize(width: 820, height: 760)
            window.hidesOnDeactivate = false
            window.isRestorable = false
            window.setContentSize(size)
            window.center()
            self.window = window
            bringForward(window)
        }
        applyWindowChrome()
        session.start()
    }

    private func preferredSize(from screen: NSScreen? = nil) -> NSSize {
        let visible = (screen ?? NSScreen.main)?.visibleFrame.size ?? NSSize(width: 1280, height: 800)
        return NSSize(
            width: min(580, max(500, visible.width * 0.36)),
            height: min(500, max(400, visible.height * 0.46))
        )
    }

    private func fitFrame(_ window: NSWindow) {
        let frame = window.frame
        guard frame.width > 820 || frame.height > 760 || frame.width < 460 || frame.height < 380 else { return }
        let size = preferredSize(from: window.screen)
        window.setContentSize(size)
        window.center()
    }

    private func bringForward(_ window: NSWindow) {
        window.collectionBehavior.insert(.moveToActiveSpace)
        window.makeKeyAndOrderFront(nil)
        window.orderFrontRegardless()
        NSApp.activate(ignoringOtherApps: true)
    }

    private func applyWindowChrome() {
        guard let window else { return }
        let palette = ThemeController.shared.palette
        window.appearance = palette.nsAppearance
        window.isOpaque = true
        window.hasShadow = true
        window.backgroundColor = palette.windowNS
    }

    private func close() {
        session?.cancel()
        session = nil
        window?.orderOut(nil)
    }
}

enum TranslatePhase: Equatable {
    case recognizing
    case translating
    case done
    case empty
    case failed(String)
}

@MainActor
final class TranslateSession: ObservableObject {
    let image: NSImage
    @Published var original = ""
    @Published var translated = ""
    @Published private(set) var detected: NLLanguage?
    @Published private(set) var target = AppSettings.shared.translateTargetLanguage
    @Published private(set) var effectiveTarget = AppSettings.shared.translateTargetLanguage
    @Published private(set) var phase: TranslatePhase = .recognizing
    @Published private(set) var ocrSeconds: Double?
    @Published private(set) var translateSeconds: Double?

    private var detectedConfidence = 0.0
    private var work: Task<Void, Never>?
    private var runToken = UUID()

    init(image: NSImage) {
        self.image = image
    }

    var busy: Bool { phase == .recognizing || phase == .translating }
    var hasOriginal: Bool { !original.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
    var hasTranslation: Bool { !translated.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
    var sourceName: String { TranslateTargetLanguage.displayName(for: detected) }
    var swappedTarget: Bool { effectiveTarget != target }

    func start() {
        work?.cancel()
        work = Task { [weak self] in await self?.recognizeThenTranslate() }
    }

    func retranslate() {
        guard hasOriginal else { return }
        work?.cancel()
        detected = OCRService.detectLanguage(in: original)
        detectedConfidence = OCRService.detectLanguageDetailed(in: original).confidence
        work = Task { [weak self] in await self?.translateNow() }
    }

    func setTarget(_ language: TranslateTargetLanguage) {
        guard language != target else { return }
        target = language
        AppSettings.shared.translateTargetLanguage = language
        if phase != .recognizing, hasOriginal { retranslate() }
    }

    func cancel() {
        work?.cancel()
        work = nil
    }

    private func recognizeThenTranslate() async {
        phase = .recognizing
        original = ""
        translated = ""
        detected = nil
        ocrSeconds = nil
        translateSeconds = nil
        let started = Date()
        let result = await OCRService.recognizeDetailed(image: image)
        guard !Task.isCancelled else { return }
        ocrSeconds = Date().timeIntervalSince(started)
        original = result.text
        detected = result.language
        detectedConfidence = result.languageConfidence
        await translateNow()
    }

    private func translateNow() async {
        let text = original.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else {
            translated = ""
            phase = .empty
            return
        }
        effectiveTarget = resolveTarget()
        translated = ""
        translateSeconds = nil
        phase = .translating
        let token = UUID()
        runToken = token
        let started = Date()
        do {
            let result = try await TranslateService.translate(
                text: text,
                sourceName: sourceName,
                target: effectiveTarget,
                onPartial: { [weak self] partial in
                    guard let self, self.runToken == token, self.phase == .translating else { return }
                    self.translated = partial
                }
            )
            guard !Task.isCancelled, runToken == token else { return }
            translated = result
            translateSeconds = Date().timeIntervalSince(started)
            phase = .done
        } catch is CancellationError {
            return
        } catch {
            guard !Task.isCancelled else { return }
            phase = .failed(error.localizedDescription)
        }
    }

    /// 原文已是目标语言时自动换向：中文译英文，其他译中文。
    private func resolveTarget() -> TranslateTargetLanguage {
        guard target.matches(detected), detectedConfidence >= 0.5 else { return target }
        return (target == .zhHans || target == .zhHant) ? .en : .zhHans
    }
}

struct TranslateRootView: View {
    @ObservedObject var session: TranslateSession
    let onClose: () -> Void
    @ObservedObject private var themeController = ThemeController.shared

    private var theme: FlarePalette { themeController.palette }

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider().overlay(theme.stroke)
            GeometryReader { geo in
                VStack(spacing: 10) {
                    originalCard
                        .frame(height: max(92, geo.size.height * 0.36))
                    translationCard
                        .frame(maxHeight: .infinity)
                }
                .padding(12)
            }
            Divider().overlay(theme.stroke)
            footer
        }
        .background(Color(nsColor: theme.windowNS))
        .environment(\.flareTheme, theme)
        .preferredColorScheme(theme.preferredColorScheme)
        .background(shortcuts)
    }

    // MARK: Header

    private var header: some View {
        HStack(spacing: 10) {
            Image(nsImage: session.image)
                .resizable()
                .interpolation(.medium)
                .scaledToFill()
                .frame(width: 38, height: 38)
                .clipShape(RoundedRectangle(cornerRadius: 7, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 7, style: .continuous)
                        .strokeBorder(theme.stroke, lineWidth: 1)
                )

            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    if session.busy {
                        ProgressView().controlSize(.mini)
                    } else if case .failed = session.phase {
                        Circle().fill(theme.warning).frame(width: 7, height: 7)
                    } else {
                        Circle().fill(theme.success).frame(width: 7, height: 7)
                    }
                    Text(statusTitle)
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(theme.textPrimary)
                        .lineLimit(1)
                }
                Text(timingLine)
                    .font(.system(size: 10, weight: .medium, design: .rounded))
                    .foregroundStyle(theme.textMuted)
                    .lineLimit(1)
            }

            Spacer(minLength: 8)

            languageBar
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
    }

    private var languageBar: some View {
        HStack(spacing: 6) {
            Text(session.sourceName)
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(theme.textSecondary)
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(theme.fill, in: Capsule())
            Image(systemName: "arrow.right")
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(theme.textMuted)
            Menu {
                ForEach(TranslateTargetLanguage.allCases) { language in
                    Button {
                        session.setTarget(language)
                    } label: {
                        if language == session.target {
                            Label(language.displayName, systemImage: "checkmark")
                        } else {
                            Text(language.displayName)
                        }
                    }
                }
            } label: {
                Text("\(session.effectiveTarget.displayName) ▾")
                    .font(.system(size: 11, weight: .semibold))
            }
            .menuStyle(.borderlessButton)
            .menuIndicator(.hidden)
            .fixedSize()
            .tint(theme.accent)
            .padding(.horizontal, 9)
            .padding(.vertical, 4)
            .background(theme.accentSoft, in: Capsule())
            .help(L("目标语言"))
        }
    }

    // MARK: Cards

    private var originalCard: some View {
        card(
            title: L("原文"),
            trailing: {
                HStack(spacing: 10) {
                    linkButton(L("重新识别"), disabled: session.busy) { session.start() }
                    linkButton(L("复制"), disabled: !session.hasOriginal) { copy(session.original, toast: L("已复制原文")) }
                }
            }
        ) {
            ZStack(alignment: .topLeading) {
                if !session.hasOriginal {
                    Text(session.phase == .recognizing ? L("正在识别截图里的文字…") : L("没识别到文字，可以直接粘贴原文，再按 ⌘↩ 翻译"))
                        .font(.system(size: 12))
                        .foregroundStyle(theme.textMuted)
                        .padding(.horizontal, 5)
                        .padding(.vertical, 2)
                        .allowsHitTesting(false)
                }
                TextEditor(text: $session.original)
                    .font(.system(size: 13))
                    .scrollContentBackground(.hidden)
                    .foregroundStyle(theme.textSecondary)
                    .disabled(session.phase == .recognizing)
            }
        }
    }

    private var translationCard: some View {
        card(
            title: session.swappedTarget ? L("译文 · 原文已是%@，改译%@", session.target.displayName, session.effectiveTarget.displayName) : L("译文"),
            emphasized: true,
            trailing: {
                linkButton(L("复制"), disabled: !session.hasTranslation) { copy(session.translated, toast: L("已复制译文")) }
            }
        ) {
            if case .failed(let message) = session.phase {
                VStack(alignment: .leading, spacing: 10) {
                    Text(message)
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(theme.warning)
                        .fixedSize(horizontal: false, vertical: true)
                    Button(L("重试")) { session.retranslate() }
                        .buttonStyle(.plain)
                        .font(.system(size: 12, weight: .semibold))
                        .padding(.horizontal, 12)
                        .padding(.vertical, 5)
                        .background(theme.fillStrong, in: RoundedRectangle(cornerRadius: 6, style: .continuous))
                        .foregroundStyle(theme.textPrimary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                .padding(4)
            } else if !session.hasTranslation {
                HStack(spacing: 8) {
                    if session.busy {
                        ProgressView().controlSize(.small)
                    }
                    Text(translationPlaceholder)
                        .font(.system(size: 13))
                        .foregroundStyle(theme.textMuted)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                .padding(4)
            } else {
                ScrollView {
                    Text(session.translated + (session.phase == .translating ? " ▍" : ""))
                        .font(.system(size: 15))
                        .lineSpacing(4)
                        .foregroundStyle(theme.textPrimary)
                        .textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .topLeading)
                        .padding(4)
                }
            }
        }
    }

    private func card<Trailing: View, Content: View>(
        title: String,
        emphasized: Bool = false,
        @ViewBuilder trailing: () -> Trailing,
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 8) {
                Text(title)
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(emphasized ? theme.accent : theme.textMuted)
                    .lineLimit(1)
                Spacer(minLength: 6)
                trailing()
            }
            content()
        }
        .padding(10)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(emphasized ? theme.card : theme.fill)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .strokeBorder(emphasized ? theme.accent.opacity(0.25) : theme.stroke, lineWidth: 1)
        )
    }

    // MARK: Footer

    private var footer: some View {
        HStack(spacing: 8) {
            Text(L("⌘↩ 翻译 · ⌘R 重识 · ⌘⇧C 复制译文"))
                .font(.system(size: 10))
                .foregroundStyle(theme.textMuted)
                .lineLimit(1)
            Spacer(minLength: 8)
            pillButton(L("翻译"), primary: false, disabled: session.busy || !session.hasOriginal) {
                session.retranslate()
            }
            pillButton(L("复制译文"), primary: true, disabled: !session.hasTranslation) {
                copy(session.translated, toast: L("已复制译文"))
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 9)
    }

    private var shortcuts: some View {
        Group {
            Button("") { session.retranslate() }
                .keyboardShortcut(.return, modifiers: .command)
            Button("") { session.start() }
                .keyboardShortcut("r", modifiers: .command)
            Button("") { copy(session.translated, toast: L("已复制译文")) }
                .keyboardShortcut("c", modifiers: [.command, .shift])
            Button("") { onClose() }
                .keyboardShortcut(.cancelAction)
        }
        .opacity(0)
        .allowsHitTesting(false)
    }

    private func linkButton(_ title: String, disabled: Bool, action: @escaping () -> Void) -> some View {
        Button(title, action: action)
            .buttonStyle(.plain)
            .font(.system(size: 11, weight: .medium))
            .foregroundStyle(theme.accent)
            .disabled(disabled)
            .opacity(disabled ? 0.4 : 1)
    }

    private func pillButton(_ title: String, primary: Bool, disabled: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title)
                .font(.system(size: 12, weight: .semibold))
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
                .background(primary ? theme.inverseFill : theme.fillStrong)
                .foregroundStyle(primary ? theme.inverseText : theme.textPrimary)
                .clipShape(RoundedRectangle(cornerRadius: 7, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 7, style: .continuous)
                        .strokeBorder(primary ? Color.clear : theme.stroke, lineWidth: 1)
                )
        }
        .buttonStyle(.plain)
        .disabled(disabled)
        .opacity(disabled ? 0.45 : 1)
    }

    // MARK: Text

    private var statusTitle: String {
        switch session.phase {
        case .recognizing: return L("正在识别文字…")
        case .translating: return L("正在翻译…")
        case .done: return L("翻译完成")
        case .empty: return L("没有识别到文字")
        case .failed: return L("翻译没成功")
        }
    }

    private var timingLine: String {
        var parts: [String] = []
        if let ocr = session.ocrSeconds { parts.append(L("识别 %@", format(ocr))) }
        if let tr = session.translateSeconds { parts.append(L("翻译 %@", format(tr))) }
        return parts.isEmpty ? L("截图翻译") : parts.joined(separator: " · ")
    }

    private var translationPlaceholder: String {
        switch session.phase {
        case .recognizing: return L("识别完成后自动翻译")
        case .translating: return L("正在翻译…")
        case .empty: return L("先识别或粘贴原文")
        case .done, .failed: return L("译文会显示在这里")
        }
    }

    private func format(_ seconds: Double) -> String {
        String(format: L("%.1f 秒"), seconds)
    }

    private func copy(_ text: String, toast: String) {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(trimmed, forType: .string)
        ToastController.shared.show(toast)
    }
}
