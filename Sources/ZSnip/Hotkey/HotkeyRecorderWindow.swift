import AppKit

/// Small window that captures the next key combination the user presses.
final class HotkeyRecorderWindow: NSWindowController, NSWindowDelegate {
    private static var current: HotkeyRecorderWindow?

    /// Shows the recorder; on success saves and re-registers the hotkey.
    static func present() {
        if let current { current.show(); return }
        // Unregister while recording, otherwise pressing the current hotkey would start a capture.
        HotKeyManager.shared.unregister()
        current = HotkeyRecorderWindow(current: Settings.hotkey) { combo in
            if let combo { Settings.hotkey = combo }
            HotKeyManager.shared.registerSaved()
            Self.current = nil
        }
        current?.show()
    }

    private let onFinish: (KeyCombo?) -> Void
    private var monitor: Any?
    private let label = NSTextField(labelWithString: "")
    private let hint = NSTextField(labelWithString: "")
    private var finished = false

    /// `onFinish` receives the new combo, or nil if the user cancelled.
    init(current: KeyCombo, onFinish: @escaping (KeyCombo?) -> Void) {
        self.onFinish = onFinish
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 360, height: 150),
                              styleMask: [.titled, .closable], backing: .buffered, defer: false)
        window.title = "Set Capture Hotkey"
        super.init(window: window)
        window.delegate = self

        label.stringValue = current.displayString
        label.font = .systemFont(ofSize: 22, weight: .semibold)
        label.alignment = .center
        hint.stringValue = "Press a new shortcut…  (Esc to cancel)"
        hint.textColor = .secondaryLabelColor
        hint.alignment = .center

        let reset = NSButton(title: "Reset to Print Screen", target: self, action: #selector(resetToDefault))
        let stack = NSStackView(views: [label, hint, reset])
        stack.orientation = .vertical
        stack.spacing = 10
        stack.edgeInsets = NSEdgeInsets(top: 20, left: 20, bottom: 20, right: 20)
        window.contentView = stack

        monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            self?.handle(event)
            return nil
        }
    }

    required init?(coder: NSCoder) { fatalError() }

    func show() {
        window?.center()
        NSApp.activate(ignoringOtherApps: true)
        window?.makeKeyAndOrderFront(nil)
    }

    private func handle(_ event: NSEvent) {
        if event.keyCode == 53 /* Esc */ && event.modifierFlags.intersection(.deviceIndependentFlagsMask).isEmpty {
            finish(nil)
            return
        }
        let combo = KeyCombo(event: event)
        guard combo.isAllowedAsGlobalHotkey else {
            label.stringValue = combo.displayString
            hint.stringValue = "Add a modifier (⌘ ⌥ ⌃ ⇧) or use an F-key."
            hint.textColor = .systemRed
            return
        }
        finish(combo)
    }

    @objc private func resetToDefault() { finish(.default) }

    private func finish(_ combo: KeyCombo?) {
        guard !finished else { return }
        finished = true
        if let monitor { NSEvent.removeMonitor(monitor) }
        monitor = nil
        window?.close()
        onFinish(combo)
    }

    func windowWillClose(_ notification: Notification) { finish(nil) }
}
