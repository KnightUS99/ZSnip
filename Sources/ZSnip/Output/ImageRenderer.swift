import AppKit
import CoreImage

/// Final output of a capture: the cropped screenshot with annotations flattened in.
struct RenderedImage {
    let cgImage: CGImage
    /// Size in points (pixels ÷ Retina scale), so pasted images appear at on-screen size.
    let pointSize: CGSize

    var pngData: Data? {
        let rep = NSBitmapImageRep(cgImage: cgImage)
        rep.size = pointSize
        return rep.representation(using: .png, properties: [:])
    }

    var tiffData: Data? {
        let rep = NSBitmapImageRep(cgImage: cgImage)
        rep.size = pointSize
        return rep.tiffRepresentation
    }
}

enum ImageRenderer {
    /// - Parameters:
    ///   - viewSize: size of the overlay view in points; `crop`, `sharpRect` and annotations are in that space (top-left origin).
    ///   - blurred, sharpRect: if given, `blurred` is used everywhere except `sharpRect`, which shows `snapshot`.
    static func render(snapshot: CGImage, viewSize: CGSize, annotations: [Annotation], crop: CGRect,
                       blurred: CGImage? = nil, sharpRect: CGRect? = nil) -> RenderedImage? {
        let scale = CGFloat(snapshot.width) / viewSize.width
        let pixelRect = CGRect(x: crop.minX * scale, y: crop.minY * scale,
                               width: crop.width * scale, height: crop.height * scale)
            .integral
            .intersection(CGRect(x: 0, y: 0, width: snapshot.width, height: snapshot.height))
        let width = Int(pixelRect.width), height = Int(pixelRect.height)
        guard width > 0, height > 0, let cropped = snapshot.cropping(to: pixelRect) else { return nil }

        let bitmapInfo = CGImageAlphaInfo.premultipliedLast.rawValue
        guard let ctx = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
                                  space: snapshot.colorSpace ?? CGColorSpaceCreateDeviceRGB(), bitmapInfo: bitmapInfo)
                ?? CGContext(data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
                             space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: bitmapInfo) else { return nil }

        let fullRect = CGRect(x: 0, y: 0, width: width, height: height)
        if let blurred, let sharpRect, let blurredCrop = blurred.cropping(to: pixelRect) {
            ctx.draw(blurredCrop, in: fullRect)
            // sharpRect → pixels relative to the crop, flipped to CG's bottom-left origin.
            let top = sharpRect.minY * scale - pixelRect.minY
            let clip = CGRect(x: sharpRect.minX * scale - pixelRect.minX, y: CGFloat(height) - top - sharpRect.height * scale,
                              width: sharpRect.width * scale, height: sharpRect.height * scale).integral
            ctx.saveGState()
            ctx.clip(to: clip)
            ctx.draw(cropped, in: fullRect)
            ctx.restoreGState()
        } else {
            ctx.draw(cropped, in: fullRect)
        }

        if !annotations.isEmpty {
            // Map the view's flipped point space onto this pixel buffer.
            ctx.translateBy(x: 0, y: CGFloat(height))
            ctx.scaleBy(x: scale, y: -scale)
            ctx.translateBy(x: -pixelRect.minX / scale, y: -pixelRect.minY / scale)

            NSGraphicsContext.saveGraphicsState()
            NSGraphicsContext.current = NSGraphicsContext(cgContext: ctx, flipped: true)
            for annotation in annotations { annotation.draw() }
            NSGraphicsContext.restoreGraphicsState()
        }

        guard let image = ctx.makeImage() else { return nil }
        return RenderedImage(cgImage: image, pointSize: CGSize(width: CGFloat(width) / scale,
                                                               height: CGFloat(height) / scale))
    }

    /// Gaussian-blurred copy of `image`; `radius` is in pixels. Strong enough to make text unreadable.
    static func blurred(_ image: CGImage, radius: CGFloat) -> CGImage? {
        let input = CIImage(cgImage: image)
        let output = input.clampedToExtent().applyingGaussianBlur(sigma: radius).cropped(to: input.extent)
        let space = image.colorSpace ?? CGColorSpace(name: CGColorSpace.sRGB)!
        return CIContext().createCGImage(output, from: input.extent, format: .RGBA8, colorSpace: space)
    }
}
