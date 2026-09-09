import AppKit
import SwiftUI
import UniformTypeIdentifiers

final class EditorWindowController {
    static let shared = EditorWindowController()

    private var window: NSWindow?
    private var document: AnnotationDocument?
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

    private func applyWindowChrome() {
        guard let window, window.isVisible else { return }
        let theme = ThemeController.shared.palette
        window.appearance = theme.nsAppearance
        window.backgroundColor = theme.windowNS
    }

    func present(image: NSImage) {
        let doc = AnnotationDocument(image: image)
        self.document = doc

        let theme = ThemeController.shared.palette
        let root = EditorRootView(
            document: doc,
            onCopy: { [weak self] in self?.copy() },
            onSave: { [weak self] in self?.save() },
            onPin: { [weak self] in self?.pin() },
            onOCR: { [weak self] in self?.runOCR() },
            onClose: { [weak self] in self?.close() }
        )
        .environment(\.flareTheme, theme)
        .preferredColorScheme(theme.preferredColorScheme)

        let hosting = NSHostingController(rootView: root)
        let size = fittedSize(for: image)

        if let window {
            window.contentViewController = hosting
            window.setContentSize(size)
            window.makeKeyAndOrderFront(nil)
        } else {
            let window = NSWindow(
                contentRect: NSRect(origin: .zero, size: size),
                styleMask: [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView],
                backing: .buffered,
                defer: false
            )
            window.title = "\(FlareBrand.name) 编辑器"
            window.titlebarAppearsTransparent = true
            window.isMovableByWindowBackground = true
            window.contentViewController = hosting
            window.center()
            window.setFrameAutosaveName("FlareEditor")
            window.isReleasedWhenClosed = false
            window.minSize = NSSize(width: 720, height: 480)
            self.window = window
            window.makeKeyAndOrderFront(nil)
        }
        window?.appearance = theme.nsAppearance
        window?.backgroundColor = theme.windowNS
        NSApp.activate(ignoringOtherApps: true)
    }

    private func fittedSize(for image: NSImage) -> NSSize {
        let maxW: CGFloat = min((NSScreen.main?.visibleFrame.width ?? 1200) * 0.85, 1280)
        let maxH: CGFloat = min((NSScreen.main?.visibleFrame.height ?? 800) * 0.8, 900)
        let chrome: CGFloat = 130
        let aspect = image.size.width / max(image.size.height, 1)
        var w = image.size.width + 48
        var h = image.size.height + chrome + 48
        if w > maxW {
            w = maxW
            h = (maxW - 48) / aspect + chrome + 48
        }
        if h > maxH {
            h = maxH
            w = (maxH - chrome - 48) * aspect + 48
        }
        return NSSize(width: max(w, 760), height: max(h, 520))
    }

    private func copy() {
        guard let image = document?.renderedImage() else { return }
        Task { await PrivacyGuard.copyIfAllowed(image) }
    }

    private func save() {
        guard let image = document?.renderedImage() else { return }
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.png, .jpeg, .tiff]
        panel.nameFieldStringValue = "\(FlareBrand.name) \(formattedDate()).png"
        panel.directoryURL = AppSettings.shared.saveDirectory
        panel.begin { result in
            guard result == .OK, let url = panel.url else { return }
            let format: ImageFormat
            switch url.pathExtension.lowercased() {
            case "jpg", "jpeg": format = .jpeg
            case "tiff", "tif": format = .tiff
            default: format = .png
            }
            do {
                try ImageExporter.write(image, to: url, format: format)
                HistoryStore.shared.add(image: image, fileURL: url)
                StatusBarController.shared?.reloadMenu()
                ToastController.shared.show("已保存")
            } catch {
                let alert = NSAlert(error: error)
                alert.runModal()
            }
        }
    }

    private func pin() {
        guard let image = document?.renderedImage() else { return }
        Task { @MainActor in
            switch await PrivacyGuard.plan(for: image) {
            case .original:
                PinWindowController.shared.pin(image: image)
                ToastController.shared.show("已钉在屏幕上")
            case .redacted(let redacted):
                PinWindowController.shared.pin(image: redacted)
                ToastController.shared.show("已钉出脱敏图")
            case .localOnly:
                ToastController.shared.show("已取消钉出，原图请只留在本机")
            }
        }
    }

    private func runOCR() {
        guard let image = document?.renderedImage() else { return }
        ToastController.shared.show("正在识别…")
        Task {
            let text = await OCRService.recognize(image: image)
            await MainActor.run {
                let alert = NSAlert()
                if text.isEmpty {
                    alert.messageText = "未识别到文字"
                    alert.informativeText = "尝试截取更清晰、对比度更高的区域。"
                } else {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(text, forType: .string)
                    alert.messageText = "已复制识别文字"
                    alert.informativeText = text
                }
                alert.addButton(withTitle: "好")
                alert.runModal()
            }
        }
    }

    private func close() {
        window?.orderOut(nil)
    }

    private func formattedDate() -> String {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd HH.mm.ss"
        return f.string(from: Date())
    }
}

struct EditorRootView: View {
    @ObservedObject var document: AnnotationDocument
    @ObservedObject private var themeController = ThemeController.shared
    let onCopy: () -> Void
    let onSave: () -> Void
    let onPin: () -> Void
    let onOCR: () -> Void
    let onClose: () -> Void

    private var theme: FlarePalette { themeController.palette }

    private let colors: [NSColor] = AnnotationStyle.palette

    /// 常用工具：划线默认，少而精
    private static let primaryTools: [AnnotationTool] = [
        .select, .line, .arrow, .pen, .rect, .text, .blur
    ]

    var body: some View {
        VStack(spacing: 0) {
            toolbar
            Divider().overlay(theme.stroke)
            canvasArea
            Divider().overlay(theme.stroke)
            bottomBar
        }
        .background(EditorBackground())
        .environment(\.flareTheme, theme)
        .preferredColorScheme(theme.preferredColorScheme)
        .frame(minWidth: 720, minHeight: 480)
    }

    private var toolbar: some View {
        VStack(spacing: 10) {
            HStack(spacing: 12) {
                HStack(spacing: 8) {
                    FlareBrandMark(size: 22, cornerRadius: 6)
                    Text(FlareBrand.name)
                        .font(.system(size: 14, weight: .bold, design: .rounded))
                        .foregroundStyle(theme.textPrimary)
                }

                Text(sizeLabel)
                    .font(.system(size: 11, weight: .medium, design: .monospaced))
                    .foregroundStyle(theme.textMuted)

                Spacer()

                Text(document.tool.title)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(theme.textPrimary)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 4)
                    .background(theme.fillStrong)
                    .clipShape(Capsule())
            }

            HStack(spacing: 4) {
                ForEach(Self.primaryTools) { tool in
                    toolButton(tool)
                }

                Divider().frame(height: 18).overlay(theme.strokeStrong)

                ForEach(Array(colors.enumerated()), id: \.offset) { _, color in
                    Button {
                        document.setColor(color)
                    } label: {
                        Circle()
                            .fill(Color(nsColor: color))
                            .frame(width: 12, height: 12)
                            .overlay(
                                Circle().strokeBorder(
                                    approximatelyEqual(document.style.color, color)
                                        ? theme.textPrimary
                                        : theme.strokeStrong,
                                    lineWidth: approximatelyEqual(document.style.color, color) ? 1.5 : 0.8
                                )
                            )
                    }
                    .buttonStyle(.plain)
                    .help(color.hexString)
                }

                HStack(spacing: 4) {
                    SnapIcon(.stroke, size: .caption, opacity: 0.55, tint: theme.textMuted)
                    Slider(value: Binding(
                        get: { document.style.lineWidth },
                        set: { document.setLineWidth($0) }
                    ), in: 1...20)
                    .tint(theme.accent)
                    .frame(width: 72)
                    Text("\(Int(document.style.lineWidth))")
                        .font(.system(size: 10, design: .monospaced))
                        .foregroundStyle(theme.textSecondary)
                        .frame(width: 16)
                }

                if document.tool == .text {
                    HStack(spacing: 4) {
                        SnapIcon(.toolText, size: .caption, opacity: 0.55, tint: theme.textMuted)
                        Slider(value: Binding(
                            get: { document.style.fontSize },
                            set: { document.setFontSize($0) }
                        ), in: 12...42)
                        .tint(theme.accent)
                        .frame(width: 56)
                    }
                    .help("文字大小")
                }

                Spacer(minLength: 4)

                actionButton("撤销", glyph: .undo) { document.undo() }
                actionButton("重做", glyph: .redo) { document.redo() }
                actionButton("清空", glyph: .trash) { document.clear() }
            }
        }
        .padding(.horizontal, 12)
        .padding(.top, 10)
        .padding(.bottom, 8)
    }

    private var sizeLabel: String {
        let s = document.baseImage.size
        return "\(Int(s.width))×\(Int(s.height))"
    }

    private var canvasArea: some View {
        ZStack {
            CanvasHost(document: document)
                .padding(18)
                .background(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .fill(theme.fill)
                        .padding(10)
                )
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var bottomBar: some View {
        HStack(spacing: 10) {
            actionButton("OCR 识字", glyph: .ocr, action: onOCR)
            actionButton("钉在屏幕", glyph: .pin, action: onPin)
            Spacer()
            actionButton("复制", glyph: .copy, action: onCopy)
            Button(action: onSave) {
                HStack(spacing: 6) {
                    SnapIcon(.save, size: .menu, opacity: 1, tint: theme.inverseText)
                    Text("保存")
                        .font(.system(size: 13, weight: .semibold))
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 8)
                .background(theme.inverseFill)
                .foregroundStyle(theme.inverseText)
                .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
            }
            .buttonStyle(.plain)
            .keyboardShortcut("s", modifiers: .command)

            Button("完成", action: onClose)
                .buttonStyle(.plain)
                .foregroundStyle(theme.textMuted)
                .keyboardShortcut(.escape, modifiers: [])
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
    }

    private func toolButton(_ tool: AnnotationTool) -> some View {
        let selected = document.tool == tool
        let isText = tool == .text
        return Button {
            document.tool = tool
        } label: {
            Group {
                if isText {
                    Text("文字")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(selected ? theme.inverseText : theme.textSecondary)
                } else {
                    SnapIcon(
                        tool.glyph,
                        size: .menu,
                        opacity: selected ? 1 : 0.75,
                        tint: selected ? theme.inverseText : theme.textSecondary
                    )
                }
            }
            .frame(width: isText ? 36 : 28, height: 28)
            .background(
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .fill(selected ? theme.inverseFill : theme.fill)
            )
            .help(tool.title)
        }
        .buttonStyle(.plain)
    }

    private func actionButton(_ title: String, glyph: SnapGlyph, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 5) {
                SnapIcon(glyph, size: .caption, opacity: 0.9, tint: theme.textPrimary)
                Text(title)
                    .font(.system(size: 12, weight: .medium))
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 5)
            .background(theme.fillStrong)
            .foregroundStyle(theme.textPrimary)
            .clipShape(RoundedRectangle(cornerRadius: 7, style: .continuous))
        }
        .buttonStyle(.plain)
    }

    private func approximatelyEqual(_ a: NSColor, _ b: NSColor) -> Bool {
        guard let a = a.usingColorSpace(.sRGB), let b = b.usingColorSpace(.sRGB) else { return false }
        return abs(a.redComponent - b.redComponent) < 0.02
            && abs(a.greenComponent - b.greenComponent) < 0.02
            && abs(a.blueComponent - b.blueComponent) < 0.02
    }
}

struct EditorBackground: View {
    @Environment(\.flareTheme) private var theme

    var body: some View {
        ZStack {
            ThemeCanvas(palette: theme, opacity: 1)
            Canvas { context, size in
                let step: CGFloat = 16
                let a = theme.isDark ? 0.035 : 0.045
                let b = theme.isDark ? 0.015 : 0.02
                for x in stride(from: 0, through: size.width, by: step) {
                    for y in stride(from: 0, through: size.height, by: step) {
                        let dark = Int(x / step + y / step) % 2 == 0
                        context.fill(
                            Path(CGRect(x: x, y: y, width: step, height: step)),
                            with: .color(theme.textPrimary.opacity(dark ? a : b))
                        )
                    }
                }
            }
            .opacity(0.55)
        }
        .ignoresSafeArea()
    }
}

struct CanvasHost: NSViewRepresentable {
    @ObservedObject var document: AnnotationDocument

    func makeNSView(context: Context) -> NSScrollView {
        let scroll = NSScrollView()
        scroll.hasVerticalScroller = true
        scroll.hasHorizontalScroller = true
        scroll.borderType = .noBorder
        scroll.drawsBackground = false

        let canvas = AnnotationCanvasView(frame: NSRect(origin: .zero, size: document.baseImage.size))
        canvas.document = document
        canvas.onRequestOCRToTXT = {
            let image = document.renderedImage()
            Task {
                do {
                    let url = try await TextFileService.createTXTFromOCR(image: image, askWhere: true)
                    await MainActor.run {
                        ToastController.shared.show("已保存 \(url.lastPathComponent)")
                        TextFileService.reveal(url)
                    }
                } catch {
                    await MainActor.run {
                        if (error as? TextFileService.TextFileError) != .cancelled {
                            ToastController.shared.show("OCR 导出失败")
                        }
                    }
                }
            }
        }
        scroll.documentView = canvas
        context.coordinator.canvas = canvas
        return scroll
    }

    func updateNSView(_ scroll: NSScrollView, context: Context) {
        context.coordinator.canvas?.document = document
        context.coordinator.canvas?.frame = NSRect(origin: .zero, size: document.baseImage.size)
        context.coordinator.canvas?.needsDisplay = true
    }

    func makeCoordinator() -> Coordinator { Coordinator() }

    final class Coordinator {
        var canvas: AnnotationCanvasView?
    }
}
