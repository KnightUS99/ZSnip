import AppKit
import ServiceManagement

final class AppDelegate: NSObject, NSApplicationDelegate, NSMenuDelegate {
    private var statusItem: NSStatusItem!

    func applicationDidFinishLaunching(_ notification: Notification) {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        statusItem.button?.image = MenuBarIcon.image
        let menu = NSMenu()
        menu.delegate = self
        statusItem.menu = menu

        HotKeyManager.shared.onPress = { CaptureController.shared.begin() }
        HotKeyManager.shared.registerSaved()
        _ = Updater.shared

        if !Settings.hasCompletedSetup || !CGPreflightScreenCaptureAccess() {
            SetupWindowController.shared.show()
        }
    }

    // MARK: - Menu

    func menuNeedsUpdate(_ menu: NSMenu) {
        menu.removeAllItems()

        menu.addItem(item("Capture", #selector(capture)))
        menu.addItem(.separator())

        let hotkey = NSMenuItem(title: "Hotkey: \(Settings.hotkey.displayString)", action: nil, keyEquivalent: "")
        hotkey.isEnabled = false
        menu.addItem(hotkey)
        menu.addItem(item("Change Hotkey…", #selector(changeHotkey)))
        menu.addItem(.separator())

        let uploadItem = NSMenuItem(title: "Upload Destination (⇧↩)", action: nil, keyEquivalent: "")
        uploadItem.submenu = uploadMenu()
        menu.addItem(uploadItem)

        let login = item("Launch at Login", #selector(toggleLaunchAtLogin))
        login.state = SMAppService.mainApp.status == .enabled ? .on : .off
        menu.addItem(login)
        menu.addItem(item("Setup & Permissions…", #selector(showSetup)))
        if Updater.shared.isAvailable {
            menu.addItem(item("Check for Updates…", #selector(checkForUpdates)))
        }
        menu.addItem(.separator())

        menu.addItem(item("Quit ZSnip", #selector(quit), key: "q"))
    }

    private func uploadMenu() -> NSMenu {
        let registry = UploaderRegistry.shared
        registry.reload()
        let menu = NSMenu()

        let none = item("None", #selector(selectUploader(_:)))
        none.representedObject = nil
        none.state = registry.active == nil ? .on : .off
        menu.addItem(none)

        for uploader in registry.uploaders {
            let entry = item(uploader.displayName, #selector(selectUploader(_:)))
            entry.representedObject = uploader.id
            entry.state = registry.active?.id == uploader.id ? .on : .off
            menu.addItem(entry)
        }

        for error in registry.loadErrors {
            let bad = NSMenuItem(title: "⚠︎ \(error)", action: nil, keyEquivalent: "")
            bad.isEnabled = false
            menu.addItem(bad)
        }

        menu.addItem(.separator())
        menu.addItem(item("Open Uploaders Folder", #selector(openUploadersFolder)))
        return menu
    }

    private func item(_ title: String, _ action: Selector, key: String = "") -> NSMenuItem {
        let item = NSMenuItem(title: title, action: action, keyEquivalent: key)
        item.target = self
        return item
    }

    // MARK: - Actions

    @objc private func capture() {
        // Let the menu finish closing so it isn't in the screenshot.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) { CaptureController.shared.begin() }
    }

    @objc private func changeHotkey() { HotkeyRecorderWindow.present() }

    @objc private func showSetup() { SetupWindowController.shared.show() }

    @objc private func checkForUpdates() { Updater.shared.checkForUpdates() }

    @objc private func selectUploader(_ sender: NSMenuItem) {
        Settings.activeUploaderID = sender.representedObject as? String
    }

    @objc private func openUploadersFolder() {
        NSWorkspace.shared.open(UploaderRegistry.configDirectory)
    }

    @objc private func toggleLaunchAtLogin() {
        do {
            if SMAppService.mainApp.status == .enabled {
                try SMAppService.mainApp.unregister()
            } else {
                try SMAppService.mainApp.register()
            }
        } catch {
            Alerts.show(title: "Couldn't change Launch at Login", message: error.localizedDescription)
        }
    }

    @objc private func quit() { NSApp.terminate(nil) }
}
