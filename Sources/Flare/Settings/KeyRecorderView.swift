import AppKit
import SwiftUI

/// 点击后录制下一组快捷键
struct KeyRecorderButton: View {
    let title: String
    @Binding var shortcut: HotKeyShortcut
    var onChange: (HotKeyShortcut) -> Void
    @Environment(\.flareTheme) private var theme

    @State private var recording = false

    var body: some View {
        HStack {
            Text(title)
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(theme.textPrimary)
            Spacer()
            KeyRecorderNSButton(shortcut: $shortcut, recording: $recording) { newValue in
                shortcut = newValue
                onChange(newValue)
                recording = false
            }
            .frame(width: 148, height: 28)
        }
    }
}

struct KeyRecorderNSButton: NSViewRepresentable {
    @Binding var shortcut: HotKeyShortcut
    @Binding var recording: Bool
    var onRecorded: (HotKeyShortcut) -> Void

    func makeNSView(context: Context) -> RecorderButton {
        let button = RecorderButton(frame: NSRect(x: 0, y: 0, width: 140, height: 28))
        button.onStart = {
            recording = true
        }
        button.onRecorded = { sc in
            onRecorded(sc)
        }
        button.onCancel = {
            recording = false
            button.refreshTitle(shortcut)
        }
        button.refreshTitle(shortcut)
        return button
    }

    func updateNSView(_ button: RecorderButton, context: Context) {
        if !recording {
            button.refreshTitle(shortcut)
        } else {
            button.showRecording()
        }
    }
}

final class RecorderButton: NSButton {
    var onStart: (() -> Void)?
    var onRecorded: ((HotKeyShortcut) -> Void)?
    var onCancel: (() -> Void)?

    private var monitor: Any?
    private var isRecording = false

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        bezelStyle = .rounded
        focusRingType = .default
        target = self
        action = #selector(clicked)
        font = NSFont.monospacedSystemFont(ofSize: 12, weight: .semibold)
        setButtonType(.momentaryPushIn)
    }

    required init?(coder: NSCoder) { fatalError() }

    deinit {
        stopMonitor()
    }

    func refreshTitle(_ shortcut: HotKeyShortcut) {
        isRecording = false
        title = shortcut.displayString
        contentTintColor = nil
    }

    func showRecording() {
        isRecording = true
        title = "按下快捷键…"
        contentTintColor = FlareBrand.accent
    }

    @objc private func clicked() {
        if isRecording {
            cancelRecording()
            return
        }
        beginRecording()
    }

    private func beginRecording() {
        showRecording()
        onStart?()
        window?.makeFirstResponder(self)
        stopMonitor()
        monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard let self, self.isRecording else { return event }
            if event.keyCode == 53 { // Esc cancel
                self.cancelRecording()
                return nil
            }
            if let shortcut = HotKeyShortcut.from(event: event) {
                self.finish(with: shortcut)
                return nil
            }
            return nil
        }
    }

    private func finish(with shortcut: HotKeyShortcut) {
        stopMonitor()
        isRecording = false
        refreshTitle(shortcut)
        onRecorded?(shortcut)
    }

    private func cancelRecording() {
        stopMonitor()
        isRecording = false
        onCancel?()
    }

    private func stopMonitor() {
        if let monitor {
            NSEvent.removeMonitor(monitor)
            self.monitor = nil
        }
    }

    override var acceptsFirstResponder: Bool { true }

    override func keyDown(with event: NSEvent) {
        guard isRecording else {
            super.keyDown(with: event)
            return
        }
        if event.keyCode == 53 {
            cancelRecording()
            return
        }
        if let shortcut = HotKeyShortcut.from(event: event) {
            finish(with: shortcut)
        }
    }
}
