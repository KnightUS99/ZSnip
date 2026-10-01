import AppKit
import ServiceManagement
import SwiftUI

/// First-run / permissions window. Shown on first launch, whenever Screen Recording
/// isn't granted, and from the menu bar ("Setup & Permissions…").
final class SetupWindowController: NSWindowController, NSWindowDelegate {
    static let shared = SetupWindowController()

    private let model = SetupModel()

    private init() {
        let hosting = NSHostingController(rootView: SetupView(model: model))
        hosting.sizingOptions = .preferredContentSize
        let window = NSWindow(contentViewController: hosting)
        window.title = "ZSnip Setup"
        window.styleMask = [.titled, .closable]
        window.isReleasedWhenClosed = false
        super.init(window: window)
        window.delegate = self
        model.close = { [weak self] in self?.window?.close() }
    }

    required init?(coder: NSCoder) { fatalError() }

    func show() {
        model.startPolling()
        if window?.isVisible != true { window?.center() }
        NSApp.activate(ignoringOtherApps: true)
        window?.makeKeyAndOrderFront(nil)
    }

    func windowWillClose(_ notification: Notification) {
        model.stopPolling()
    }
}

// MARK: - Model

final class SetupModel: ObservableObject {
    @Published var screenRecordingGranted = CGPreflightScreenCaptureAccess()
    @Published var openedSettings = false
    @Published var directAccessConfirmed = Settings.hasCapturedSuccessfully
    @Published var hotkey = Settings.hotkey.displayString
    @Published var launchAtLogin = SMAppService.mainApp.status == .enabled

    var close: () -> Void = {}
    private var timer: Timer?

    /// Permission and hotkey can change outside this window, so re-check every second while it's open.
    func startPolling() {
        refresh()
        timer?.invalidate()
        timer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in self?.refresh() }
    }

    func stopPolling() {
        timer?.invalidate()
        timer = nil
    }

    private func refresh() {
        let granted = CGPreflightScreenCaptureAccess()
        if granted != screenRecordingGranted { screenRecordingGranted = granted }
        let confirmed = Settings.hasCapturedSuccessfully
        if confirmed != directAccessConfirmed { directAccessConfirmed = confirmed }
        let key = Settings.hotkey.displayString
        if key != hotkey { hotkey = key }
    }

    func openScreenRecordingSettings() {
        // Makes sure ZSnip is listed in System Settings (and shows the system prompt the first time).
        CGRequestScreenCaptureAccess()
        let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_ScreenCapture")!
        NSWorkspace.shared.open(url)
        openedSettings = true
    }

    func relaunch() {
        let task = Process()
        task.executableURL = URL(fileURLWithPath: "/bin/sh")
        task.arguments = ["-c", "sleep 0.5; open \"$0\"", Bundle.main.bundlePath]
        try? task.run()
        NSApp.terminate(nil)
    }

    func changeHotkey() { HotkeyRecorderWindow.present() }

    func setLaunchAtLogin(_ enabled: Bool) {
        do {
            if enabled { try SMAppService.mainApp.register() } else { try SMAppService.mainApp.unregister() }
        } catch {
            Alerts.show(title: "Couldn't change Launch at Login", message: error.localizedDescription)
        }
        launchAtLogin = SMAppService.mainApp.status == .enabled
    }

    /// Leaves this window open so the user sees step 2 turn green after the capture.
    func tryCapture() {
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { CaptureController.shared.begin() }
    }

    func finish() {
        Settings.hasCompletedSetup = true
        close()
    }
}

// MARK: - View

struct SetupView: View {
    @ObservedObject var model: SetupModel

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            header
            screenRecordingCard
            directAccessCard
            hotkeyCard
            loginCard
            keysCard
            footer
        }
        .padding(24)
        .frame(width: 520)
    }

    private var header: some View {
        HStack(spacing: 14) {
            Image(nsImage: NSApp.applicationIconImage)
                .resizable()
                .frame(width: 64, height: 64)
            VStack(alignment: .leading, spacing: 2) {
                Text("Welcome to ZSnip").font(.title2.bold())
                Text("A couple of quick steps and you're ready to snip.")
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var screenRecordingCard: some View {
        Card(number: 1, title: "Allow Screen Recording", done: model.screenRecordingGranted) {
            if model.screenRecordingGranted {
                Text("Permission granted. ZSnip can capture your screen.")
                    .foregroundStyle(.secondary)
            } else {
                VStack(alignment: .leading, spacing: 10) {
                    Text("macOS requires this for any app that takes screenshots. ZSnip only captures when you press the hotkey.")
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                    VStack(alignment: .leading, spacing: 4) {
                        Instruction(n: 1, text: "Click **Open System Settings** below.")
                        Instruction(n: 2, text: "Find **ZSnip** in the list and turn it **on**.")
                        Instruction(n: 3, text: "Click **Relaunch ZSnip** so macOS applies the change.")
                    }
                    HStack {
                        Button("Open System Settings") { model.openScreenRecordingSettings() }
                            .buttonStyle(.borderedProminent)
                        Button("Relaunch ZSnip") { model.relaunch() }
                            .buttonStyle(.bordered)
                    }
                    if model.openedSettings {
                        Text("Not in the list? Click **+** at the bottom of the list and choose ZSnip from where you installed it.")
                            .font(.callout)
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
            }
        }
    }

    private var directAccessCard: some View {
        Card(number: 2, title: "Allow direct screen access", done: model.directAccessConfirmed) {
            if model.directAccessConfirmed {
                Text("Confirmed. macOS may ask again every month or so; just click **Allow**.")
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            } else {
                VStack(alignment: .leading, spacing: 10) {
                    Text("On your first capture, macOS asks whether ZSnip may **bypass the private window picker** and access your screen directly. Click **Allow**. Without it, ZSnip can't capture instantly.")
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                    Button("Take a Test Capture") { model.tryCapture() }
                        .buttonStyle(.borderedProminent)
                        .disabled(!model.screenRecordingGranted)
                    Text(model.screenRecordingGranted
                         ? "Press Esc to close the capture. This step turns green once it works."
                         : "Finish step 1 first.")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }
            }
        }
    }

    private var hotkeyCard: some View {
        Card(number: 3, title: "Capture hotkey", done: true) {
            HStack {
                Text(model.hotkey)
                    .font(.system(.body, design: .rounded).weight(.semibold))
                    .padding(.horizontal, 10)
                    .padding(.vertical, 4)
                    .background(RoundedRectangle(cornerRadius: 6).fill(Color.secondary.opacity(0.15)))
                Spacer()
                Button("Change…") { model.changeHotkey() }
            }
            Text("On a Windows keyboard, Print Screen is F13 on a Mac.")
                .font(.callout)
                .foregroundStyle(.secondary)
        }
    }

    private var loginCard: some View {
        Card(number: 4, title: "Start automatically", done: model.launchAtLogin, optional: true) {
            Toggle("Launch ZSnip at login", isOn: Binding(
                get: { model.launchAtLogin },
                set: { model.setLaunchAtLogin($0) }
            ))
        }
    }

    private var keysCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("How it works").font(.headline)
            Grid(alignment: .leading, horizontalSpacing: 12, verticalSpacing: 5) {
                KeyRow(keys: model.hotkey, action: "Start a capture")
                KeyRow(keys: "D", action: "Draw: R rectangle, C circle, F freehand, 1–5 colour")
                KeyRow(keys: "S", action: "Select an area")
                KeyRow(keys: "↩", action: "Copy to clipboard   (⌘Z undo, Esc cancel)")
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(14)
        .background(RoundedRectangle(cornerRadius: 10).strokeBorder(Color.secondary.opacity(0.25)))
    }

    private var footer: some View {
        HStack {
            Button("Try a Capture") { model.tryCapture() }
                .disabled(!model.screenRecordingGranted)
            Spacer()
            Button("Done") { model.finish() }
                .keyboardShortcut(.defaultAction)
        }
    }
}

private struct Card<Content: View>: View {
    let number: Int
    let title: String
    let done: Bool
    var optional = false
    @ViewBuilder let content: Content

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            ZStack {
                Circle().fill(done ? Color.green : optional ? Color.secondary.opacity(0.5) : Color.orange)
                if done {
                    Image(systemName: "checkmark").font(.system(size: 12, weight: .bold))
                } else {
                    Text("\(number)").font(.system(size: 13, weight: .bold))
                }
            }
            .foregroundStyle(.white)
            .frame(width: 24, height: 24)

            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 6) {
                    Text(title).font(.headline)
                    if optional { Text("Optional").font(.caption).foregroundStyle(.secondary) }
                }
                content
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(14)
        .background(RoundedRectangle(cornerRadius: 10).fill(Color.secondary.opacity(0.08)))
    }
}

private struct Instruction: View {
    let n: Int
    let text: LocalizedStringKey

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 6) {
            Text("\(n).").foregroundStyle(.secondary).monospacedDigit()
            Text(text)
        }
    }
}

private struct KeyRow: View {
    let keys: String
    let action: String

    var body: some View {
        GridRow {
            Text(keys)
                .font(.system(.callout, design: .rounded).weight(.semibold))
                .padding(.horizontal, 6)
                .padding(.vertical, 1)
                .background(RoundedRectangle(cornerRadius: 4).fill(Color.secondary.opacity(0.15)))
            Text(action).font(.callout)
        }
    }
}
