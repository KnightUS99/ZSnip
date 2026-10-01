// Renders the ZSnip app icon ("Mark Up": a dashed selection with a pencil) and
// writes Resources/AppIcon.icns. Run from the repo root:
//
//     swift scripts/make-icon.swift
//
// Artwork is described in a 100 × 100 design space (y down), the same space as the
// concept sketches; it's mapped onto Apple's 824 px icon body inside a 1024 px canvas.
import AppKit

let top = NSColor(srgbRed: 0x8E / 255, green: 0x8B / 255, blue: 0xFF / 255, alpha: 1)
let bottom = NSColor(srgbRed: 0x46 / 255, green: 0x32 / 255, blue: 0xD8 / 255, alpha: 1)
let graphite = NSColor(srgbRed: 0x2A / 255, green: 0x1F / 255, blue: 0x8F / 255, alpha: 1)

/// Apple-style continuous-corner squircle (superellipse, n = 5) filling `rect`.
func squircle(in rect: CGRect) -> CGPath {
    let path = CGMutablePath()
    let n = 5.0, steps = 240
    for i in 0..<steps {
        let t = Double(i) / Double(steps) * 2 * .pi
        let c = cos(t), s = sin(t)
        let x = rect.midX + rect.width / 2 * CGFloat(copysign(pow(abs(c), 2 / n), c))
        let y = rect.midY + rect.height / 2 * CGFloat(copysign(pow(abs(s), 2 / n), s))
        i == 0 ? path.move(to: CGPoint(x: x, y: y)) : path.addLine(to: CGPoint(x: x, y: y))
    }
    path.closeSubpath()
    return path
}

func renderIcon(pixels: Int) -> CGImage {
    let size = CGFloat(pixels)
    let ctx = CGContext(data: nil, width: pixels, height: pixels, bitsPerComponent: 8, bytesPerRow: 0,
                        space: CGColorSpace(name: CGColorSpace.sRGB)!,
                        bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
    ctx.interpolationQuality = .high
    // y-down, 1024-unit canvas regardless of output size.
    ctx.translateBy(x: 0, y: size)
    ctx.scaleBy(x: size / 1024, y: -size / 1024)

    // Apple's macOS grid: 824 × 824 body centred in 1024, with a soft drop shadow.
    let body = CGRect(x: 100, y: 100, width: 824, height: 824)
    let shape = squircle(in: body)

    ctx.saveGState()
    ctx.setShadow(offset: CGSize(width: 0, height: -10 * size / 1024), blur: 28 * size / 1024,
                  color: NSColor.black.withAlphaComponent(0.32).cgColor)
    ctx.addPath(shape)
    ctx.setFillColor(bottom.cgColor)
    ctx.fillPath()
    ctx.restoreGState()

    ctx.saveGState()
    ctx.addPath(shape)
    ctx.clip()

    // Top-lit gradient plus a white sheen over the upper half.
    let space = CGColorSpace(name: CGColorSpace.sRGB)!
    let bg = CGGradient(colorsSpace: space, colors: [top.cgColor, bottom.cgColor] as CFArray, locations: [0, 1])!
    ctx.drawLinearGradient(bg, start: CGPoint(x: 512, y: 100), end: CGPoint(x: 512, y: 924), options: [])
    let sheen = CGGradient(colorsSpace: space,
                           colors: [NSColor.white.withAlphaComponent(0.22).cgColor, NSColor.white.withAlphaComponent(0).cgColor] as CFArray,
                           locations: [0, 1])!
    ctx.drawLinearGradient(sheen, start: CGPoint(x: 512, y: 100), end: CGPoint(x: 512, y: 100 + 824 * 0.55), options: [])

    // Artwork in the 100-unit design space.
    ctx.saveGState()
    ctx.translateBy(x: body.minX, y: body.minY)
    ctx.scaleBy(x: body.width / 100, y: body.height / 100)
    drawArtwork(ctx, pixels: pixels)
    ctx.restoreGState()

    // Hairline inner edge.
    ctx.addPath(shape)
    ctx.setStrokeColor(NSColor.white.withAlphaComponent(0.28).cgColor)
    ctx.setLineWidth(10)
    ctx.strokePath()
    ctx.restoreGState()

    return ctx.makeImage()!
}

/// Small renders get simpler artwork, the way Apple's own icons do: at 16 px the dashes
/// would blur into a smudge, so the selection becomes a solid line and the pencil grows.
func drawArtwork(_ ctx: CGContext, pixels: Int) {
    let white = NSColor.white.cgColor

    // Selection: solid rounded corners with evenly spaced dashes along each side.
    ctx.saveGState()
    ctx.setStrokeColor(white)
    ctx.setLineCap(.round)
    ctx.setLineJoin(.round)
    let selection = CGRect(x: 18, y: 20, width: 48, height: 44)
    if pixels <= 16 {
        ctx.setLineWidth(7)
        ctx.addPath(CGPath(roundedRect: selection, cornerWidth: 6, cornerHeight: 6, transform: nil))
    } else if pixels <= 32 {
        ctx.setLineWidth(5.5)
        ctx.addPath(selectionPath(selection, radius: 5.5, leg: 5, dashes: 1, gap: 6.5))
    } else {
        ctx.setLineWidth(4.2)
        ctx.addPath(selectionPath(selection, radius: 5.5, leg: 4.5, dashes: 2, gap: 5))
    }
    ctx.strokePath()
    ctx.restoreGState()

    // Pencil, rotated −45° about (66, 66), with a soft shadow so it sits above the selection.
    ctx.saveGState()
    ctx.translateBy(x: 66, y: 66)
    ctx.rotate(by: -.pi / 4)
    if pixels <= 32 { ctx.scaleBy(x: 1.15, y: 1.15) }
    ctx.translateBy(x: -66, y: -66)
    ctx.setShadow(offset: .zero, blur: 2.5, color: graphite.withAlphaComponent(0.45).cgColor)
    // One outline: square where the wood starts, rounded at the eraser end.
    let pencil = CGMutablePath()
    pencil.move(to: CGPoint(x: 41, y: 66))
    pencil.addLine(to: CGPoint(x: 52, y: 60))
    pencil.addLine(to: CGPoint(x: 81.5, y: 60))
    pencil.addArc(tangent1End: CGPoint(x: 84, y: 60), tangent2End: CGPoint(x: 84, y: 72), radius: 2.5)
    pencil.addArc(tangent1End: CGPoint(x: 84, y: 72), tangent2End: CGPoint(x: 52, y: 72), radius: 2.5)
    pencil.addLine(to: CGPoint(x: 52, y: 72))
    pencil.closeSubpath()
    ctx.addPath(pencil)
    ctx.setFillColor(white)
    ctx.fillPath()
    ctx.setShadow(offset: .zero, blur: 0, color: nil)

    // Where the sharpened wood starts.
    ctx.setFillColor(bottom.withAlphaComponent(0.22).cgColor)
    ctx.fill(CGRect(x: 51.6, y: 60, width: 0.9, height: 12))

    // Graphite point and ferrule band.
    ctx.move(to: CGPoint(x: 45.4, y: 63.6))
    ctx.addLine(to: CGPoint(x: 45.4, y: 68.4))
    ctx.addLine(to: CGPoint(x: 41, y: 66))
    ctx.closePath()
    ctx.setFillColor(graphite.cgColor)
    ctx.fillPath()
    ctx.setFillColor(bottom.withAlphaComponent(0.3).cgColor)
    ctx.fill(CGRect(x: 75, y: 60, width: 3.5, height: 12))
    ctx.restoreGState()
}

/// Rounded rectangle drawn as four solid corners (arc plus a short leg each way) and
/// `dashes` evenly spaced dashes on every side, so the corners always read cleanly.
func selectionPath(_ r: CGRect, radius: CGFloat, leg: CGFloat, dashes: Int, gap: CGFloat) -> CGPath {
    let p = CGMutablePath()
    let inset = radius + leg
    // Corners, each from the end of one leg to the end of the next.
    p.move(to: CGPoint(x: r.minX, y: r.minY + inset))
    p.addArc(tangent1End: CGPoint(x: r.minX, y: r.minY), tangent2End: CGPoint(x: r.maxX, y: r.minY), radius: radius)
    p.addLine(to: CGPoint(x: r.minX + inset, y: r.minY))
    p.move(to: CGPoint(x: r.maxX - inset, y: r.minY))
    p.addArc(tangent1End: CGPoint(x: r.maxX, y: r.minY), tangent2End: CGPoint(x: r.maxX, y: r.maxY), radius: radius)
    p.addLine(to: CGPoint(x: r.maxX, y: r.minY + inset))
    p.move(to: CGPoint(x: r.maxX, y: r.maxY - inset))
    p.addArc(tangent1End: CGPoint(x: r.maxX, y: r.maxY), tangent2End: CGPoint(x: r.minX, y: r.maxY), radius: radius)
    p.addLine(to: CGPoint(x: r.maxX - inset, y: r.maxY))
    p.move(to: CGPoint(x: r.minX + inset, y: r.maxY))
    p.addArc(tangent1End: CGPoint(x: r.minX, y: r.maxY), tangent2End: CGPoint(x: r.minX, y: r.minY), radius: radius)
    p.addLine(to: CGPoint(x: r.minX, y: r.maxY - inset))

    // Dashes between the corners.
    func side(from a: CGPoint, to b: CGPoint) {
        let length = hypot(b.x - a.x, b.y - a.y)
        let dash = (length - CGFloat(dashes + 1) * gap) / CGFloat(dashes)
        let ux = (b.x - a.x) / length, uy = (b.y - a.y) / length
        for i in 0..<dashes {
            let start = gap + CGFloat(i) * (dash + gap)
            p.move(to: CGPoint(x: a.x + ux * start, y: a.y + uy * start))
            p.addLine(to: CGPoint(x: a.x + ux * (start + dash), y: a.y + uy * (start + dash)))
        }
    }
    side(from: CGPoint(x: r.minX + inset, y: r.minY), to: CGPoint(x: r.maxX - inset, y: r.minY))
    side(from: CGPoint(x: r.maxX, y: r.minY + inset), to: CGPoint(x: r.maxX, y: r.maxY - inset))
    side(from: CGPoint(x: r.maxX - inset, y: r.maxY), to: CGPoint(x: r.minX + inset, y: r.maxY))
    side(from: CGPoint(x: r.minX, y: r.maxY - inset), to: CGPoint(x: r.minX, y: r.minY + inset))
    return p
}

func writePNG(_ image: CGImage, to url: URL) {
    let rep = NSBitmapImageRep(cgImage: image)
    try! rep.representation(using: .png, properties: [:])!.write(to: url)
}

// MARK: - Main

let root = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
let iconset = root.appendingPathComponent(".build/AppIcon.iconset")
try? FileManager.default.removeItem(at: iconset)
try! FileManager.default.createDirectory(at: iconset, withIntermediateDirectories: true)

for base in [16, 32, 128, 256, 512] {
    writePNG(renderIcon(pixels: base), to: iconset.appendingPathComponent("icon_\(base)x\(base).png"))
    writePNG(renderIcon(pixels: base * 2), to: iconset.appendingPathComponent("icon_\(base)x\(base)@2x.png"))
}

let icns = root.appendingPathComponent("Resources/AppIcon.icns")
let task = Process()
task.executableURL = URL(fileURLWithPath: "/usr/bin/iconutil")
task.arguments = ["-c", "icns", iconset.path, "-o", icns.path]
try! task.run()
task.waitUntilExit()
guard task.terminationStatus == 0 else { fatalError("iconutil failed") }
print("Wrote \(icns.path)")

if CommandLine.arguments.contains("--preview") {
    writePNG(renderIcon(pixels: 1024), to: root.appendingPathComponent(".build/AppIcon-preview.png"))
    print("Wrote .build/AppIcon-preview.png")
}
