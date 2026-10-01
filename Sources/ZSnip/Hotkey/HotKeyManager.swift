import Carbon.HIToolbox
import Foundation

/// Registers a single system-wide hotkey via Carbon. Unlike a CGEventTap this
/// needs no Accessibility permission, and it swallows the key so other apps don't see it.
final class HotKeyManager {
    static let shared = HotKeyManager()

    var onPress: (() -> Void)?

    private var hotKeyRef: EventHotKeyRef?
    private var handlerRef: EventHandlerRef?
    private let hotKeyID = EventHotKeyID(signature: OSType(0x5A53_4E50) /* "ZSNP" */, id: 1)

    private init() {
        var spec = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
        InstallEventHandler(GetApplicationEventTarget(), { _, _, _ in
            DispatchQueue.main.async { HotKeyManager.shared.onPress?() }
            return noErr
        }, 1, &spec, nil, &handlerRef)
    }

    /// Returns false if the combo couldn't be registered (usually because another app owns it).
    @discardableResult
    func register(_ combo: KeyCombo) -> Bool {
        unregister()
        let status = RegisterEventHotKey(combo.keyCode, combo.carbonModifiers, hotKeyID,
                                         GetApplicationEventTarget(), 0, &hotKeyRef)
        return status == noErr
    }

    /// Registers the saved hotkey, telling the user if it's taken.
    func registerSaved() {
        let combo = Settings.hotkey
        if !register(combo) {
            Alerts.show(title: "Couldn't register \(combo.displayString)",
                        message: "Another app may already be using this shortcut. Choose a different one from the ZSnip menu.")
        }
    }

    func unregister() {
        if let ref = hotKeyRef {
            UnregisterEventHotKey(ref)
            hotKeyRef = nil
        }
    }
}
