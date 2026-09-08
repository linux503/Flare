import AppKit

final class EvidenceWindowController: NSObject, NSTextFieldDelegate {
    static let shared = EvidenceWindowController()

    private var window: NSWindow?
    private let urlField = NSTextField()
    private let noteField = NSTextField()
    private let statusLabel = NSTextField(wrappingLabelWithString: "填写报价页、聊天记录、订单页或链上交易页地址。")
    private let runButton = NSButton(title: "生成快照", target: nil, action: nil)
    private var running = false

    func show() {
        if window == nil { build() }
        window?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    private func build() {
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 560, height: 420),
            styleMask: [.titled, .closable, .miniaturizable],
            backing: .buffered,
            defer: false
        )
        window.title = "网页证据快照"
        window.isReleasedWhenClosed = false

        let title = NSTextField(labelWithString: "网页证据快照")
        title.font = .systemFont(ofSize: 22, weight: .bold)
        title.frame = NSRect(x: 24, y: 352, width: 512, height: 28)

        let hint = NSTextField(wrappingLabelWithString: "用于保存报价、聊天记录、订单和链上交易页面。仅作业务留档，不具备司法证据效力。")
        hint.font = .systemFont(ofSize: 12)
        hint.textColor = .secondaryLabelColor
        hint.frame = NSRect(x: 24, y: 304, width: 512, height: 40)

        let urlLabel = NSTextField(labelWithString: "网址")
        urlLabel.font = .systemFont(ofSize: 12, weight: .semibold)
        urlLabel.frame = NSRect(x: 24, y: 276, width: 80, height: 18)
        urlField.placeholderString = "https://"
        urlField.frame = NSRect(x: 24, y: 244, width: 512, height: 26)

        let noteLabel = NSTextField(labelWithString: "备注")
        noteLabel.font = .systemFont(ofSize: 12, weight: .semibold)
        noteLabel.frame = NSRect(x: 24, y: 214, width: 80, height: 18)
        noteField.placeholderString = "客户、订单号或交易说明"
        noteField.frame = NSRect(x: 24, y: 182, width: 512, height: 26)

        statusLabel.font = .systemFont(ofSize: 12)
        statusLabel.textColor = .secondaryLabelColor
        statusLabel.frame = NSRect(x: 24, y: 92, width: 512, height: 72)

        runButton.target = self
        runButton.action = #selector(start)
        runButton.bezelStyle = .rounded
        runButton.keyEquivalent = "\r"
        runButton.frame = NSRect(x: 430, y: 24, width: 106, height: 32)

        let content = NSView(frame: window.contentRect(forFrameRect: window.frame))
        for view in [title, hint, urlLabel, urlField, noteLabel, noteField, statusLabel, runButton] {
            content.addSubview(view)
        }
        window.contentView = content
        self.window = window
    }

    @objc private func start() {
        guard !running else { return }
        running = true
        runButton.isEnabled = false
        statusLabel.stringValue = "正在检查页面…"
        let url = urlField.stringValue
        let note = noteField.stringValue
        Task {
            do {
                let result = try await EvidenceSnapshot.capture(urlString: url, note: note) { text in
                    Task { @MainActor in
                        self.statusLabel.stringValue = text
                    }
                }
                await MainActor.run {
                    self.running = false
                    self.runButton.isEnabled = true
                    self.statusLabel.stringValue = "已保存：\(result.folder.lastPathComponent)"
                    NSWorkspace.shared.activateFileViewerSelecting([result.pdf])
                }
            } catch {
                await MainActor.run {
                    self.running = false
                    self.runButton.isEnabled = true
                    self.statusLabel.stringValue = error.localizedDescription
                }
            }
        }
    }
}
