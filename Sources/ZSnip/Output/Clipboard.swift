import AppKit

enum Clipboard {
    /// Writes PNG (preferred by browsers, Slack, Discord) plus TIFF (for older Cocoa apps).
    static func copy(_ image: RenderedImage) {
        let pb = NSPasteboard.general
        pb.clearContents()
        pb.declareTypes([.png, .tiff], owner: nil)
        if let png = image.pngData { pb.setData(png, forType: .png) }
        if let tiff = image.tiffData { pb.setData(tiff, forType: .tiff) }
    }

    static func copy(_ string: String) {
        let pb = NSPasteboard.general
        pb.clearContents()
        pb.setString(string, forType: .string)
    }
}
