import AppKit

/// The menu-bar glyph: the app icon's dashed selection and pencil as an 18 pt template
/// image, so macOS tints it for light and dark menu bars and the highlighted state.
enum MenuBarIcon {
    static let image: NSImage = {
        let image = NSImage(size: NSSize(width: 18, height: 18), flipped: true) { _ in
            guard let ctx = NSGraphicsContext.current?.cgContext else { return false }
            draw(in: ctx)
            return true
        }
        image.isTemplate = true
        image.accessibilityDescription = "ZSnip"
        return image
    }()

    private static func draw(in ctx: CGContext) {
        ctx.setFillColor(NSColor.black.cgColor)
        ctx.setStrokeColor(NSColor.black.cgColor)

        // Selection: solid rounded corners plus one dash per side.
        ctx.setLineWidth(1.5)
        ctx.setLineCap(.round)
        ctx.addPath(selection(CGRect(x: 1.75, y: 2.25, width: 11.5, height: 10.5), radius: 2, leg: 1.3))
        ctx.strokePath()

        // Pencil, rotated −45° about (12.5, 12.5).
        ctx.translateBy(x: 12.5, y: 12.5)
        ctx.rotate(by: -.pi / 4)
        ctx.translateBy(x: -12.5, y: -12.5)
        let pencil = CGMutablePath()
        pencil.move(to: CGPoint(x: 6.6, y: 12.5))
        pencil.addLine(to: CGPoint(x: 9.6, y: 10.8))
        pencil.addLine(to: CGPoint(x: 17, y: 10.8))
        pencil.addArc(tangent1End: CGPoint(x: 18.3, y: 10.8), tangent2End: CGPoint(x: 18.3, y: 14.2), radius: 1)
        pencil.addArc(tangent1End: CGPoint(x: 18.3, y: 14.2), tangent2End: CGPoint(x: 9.6, y: 14.2), radius: 1)
        pencil.addLine(to: CGPoint(x: 9.6, y: 14.2))
        pencil.closeSubpath()

        // Knock a gap out of the selection around the pencil so the two don't merge.
        ctx.saveGState()
        ctx.setBlendMode(.clear)
        ctx.setLineWidth(2.2)
        ctx.setLineJoin(.round)
        ctx.addPath(pencil)
        ctx.strokePath()
        ctx.restoreGState()

        ctx.addPath(pencil)
        ctx.fillPath()
    }

    /// Four rounded corners with short legs, and one centred dash on each side.
    private static func selection(_ r: CGRect, radius: CGFloat, leg: CGFloat) -> CGPath {
        let p = CGMutablePath()
        let inset = radius + leg
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

        let gap: CGFloat = 1.6
        func dash(_ a: CGPoint, _ b: CGPoint) {
            let length = hypot(b.x - a.x, b.y - a.y)
            let ux = (b.x - a.x) / length, uy = (b.y - a.y) / length
            p.move(to: CGPoint(x: a.x + ux * gap, y: a.y + uy * gap))
            p.addLine(to: CGPoint(x: b.x - ux * gap, y: b.y - uy * gap))
        }
        dash(CGPoint(x: r.minX + inset, y: r.minY), CGPoint(x: r.maxX - inset, y: r.minY))
        dash(CGPoint(x: r.maxX, y: r.minY + inset), CGPoint(x: r.maxX, y: r.maxY - inset))
        dash(CGPoint(x: r.maxX - inset, y: r.maxY), CGPoint(x: r.minX + inset, y: r.maxY))
        dash(CGPoint(x: r.minX, y: r.maxY - inset), CGPoint(x: r.minX, y: r.minY + inset))
        return p
    }
}
