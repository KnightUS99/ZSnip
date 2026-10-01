import AppKit
import ScreenCaptureKit

/// A frozen image of one display, paired with the NSScreen it came from.
struct ScreenSnapshot {
    let screen: NSScreen
    let image: CGImage
}

enum CaptureError: LocalizedError {
    case permissionDenied
    case noDisplays

    var errorDescription: String? {
        switch self {
        case .permissionDenied:
            return "ZSnip needs Screen Recording permission. Enable it in System Settings → Privacy & Security → Screen & System Audio Recording, then relaunch ZSnip."
        case .noDisplays:
            return "No displays were found to capture."
        }
    }
}

enum ScreenCapturer {
    /// Captures every connected display at native (Retina) resolution.
    @MainActor
    static func captureAllScreens() async throws -> [ScreenSnapshot] {
        guard CGPreflightScreenCaptureAccess() else { throw CaptureError.permissionDenied }

        let content = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: true)
        let screensByID = Dictionary(uniqueKeysWithValues: NSScreen.screens.compactMap { screen in
            (screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? CGDirectDisplayID)
                .map { ($0, screen) }
        })

        var snapshots: [ScreenSnapshot] = []
        for display in content.displays {
            guard let screen = screensByID[display.displayID] else { continue }
            let filter = SCContentFilter(display: display, excludingWindows: [])
            let config = SCStreamConfiguration()
            let scale = CGFloat(filter.pointPixelScale)
            config.width = Int(filter.contentRect.width * scale)
            config.height = Int(filter.contentRect.height * scale)
            config.showsCursor = false
            config.captureResolution = .best
            let image = try await SCScreenshotManager.captureImage(contentFilter: filter, configuration: config)
            snapshots.append(ScreenSnapshot(screen: screen, image: image))
        }

        if snapshots.isEmpty { throw CaptureError.noDisplays }
        return snapshots
    }
}
