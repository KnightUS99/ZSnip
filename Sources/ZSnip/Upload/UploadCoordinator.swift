import AppKit

/// Runs an upload with the active uploader and puts the resulting link on the clipboard.
final class UploadCoordinator {
    static let shared = UploadCoordinator()

    func upload(_ image: RenderedImage) {
        guard let uploader = UploaderRegistry.shared.active else {
            // No destination configured: fall back to a normal copy so the capture isn't lost.
            Clipboard.copy(image)
            Alerts.show(title: "No upload destination",
                        message: "The image was copied to the clipboard instead. Pick a destination under ZSnip → Upload Destination.")
            return
        }
        guard let png = image.pngData else { NSSound.beep(); return }

        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd-HHmmss"
        let payload = UploadPayload(pngData: png, filename: "ZSnip-\(formatter.string(from: Date())).png")

        Task { @MainActor in
            do {
                let result = try await uploader.upload(payload)
                Clipboard.copy(result.url.absoluteString)
                NSSound(named: "Glass")?.play()
            } catch {
                Clipboard.copy(image) // keep the capture so the user can paste it elsewhere
                Alerts.show(title: "Upload to \(uploader.displayName) failed",
                            message: "\(error.localizedDescription)\n\nThe image was copied to the clipboard instead.")
            }
        }
    }
}
