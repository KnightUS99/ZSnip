import Foundation

/// UserDefaults-backed preferences.
enum Settings {
    private static let defaults = UserDefaults.standard

    static var hotkey: KeyCombo {
        get {
            guard let data = defaults.data(forKey: "hotkey"),
                  let combo = try? JSONDecoder().decode(KeyCombo.self, from: data) else { return .default }
            return combo
        }
        set { defaults.set(try? JSONEncoder().encode(newValue), forKey: "hotkey") }
    }

    static var hasCompletedSetup: Bool {
        get { defaults.bool(forKey: "hasCompletedSetup") }
        set { defaults.set(newValue, forKey: "hasCompletedSetup") }
    }

    /// Set after the first capture that got past macOS's permission prompts. There's no API
    /// to check the "bypass private window picker" approval, so a successful capture is the proof.
    static var hasCapturedSuccessfully: Bool {
        get { defaults.bool(forKey: "hasCapturedSuccessfully") }
        set { defaults.set(newValue, forKey: "hasCapturedSuccessfully") }
    }

    /// "Blur" toolbar toggle: output the whole screen, blurred except the selection.
    static var blurOutsideSelection: Bool {
        get { defaults.bool(forKey: "blurOutsideSelection") }
        set { defaults.set(newValue, forKey: "blurOutsideSelection") }
    }

    /// Keep uploader configs in iCloud Drive › ZSnip › Uploaders instead of only on this Mac.
    static var syncUploadersWithICloud: Bool {
        get { defaults.bool(forKey: "syncUploadersWithICloud") }
        set { defaults.set(newValue, forKey: "syncUploadersWithICloud") }
    }

    /// ID of the uploader used by ⌃↩ / ⇧↩ in the overlay; nil means uploading is off.
    static var activeUploaderID: String? {
        get { defaults.string(forKey: "activeUploaderID") }
        set { defaults.set(newValue, forKey: "activeUploaderID") }
    }
}
