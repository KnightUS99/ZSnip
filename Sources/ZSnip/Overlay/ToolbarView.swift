import AppKit

/// The floating toolbar at the top of the capture overlay. Mirrors the keyboard
/// shortcuts, highlights the current mode/tool, and every item is clickable.
final class ToolbarView: NSView {
    private unowned let controller: CaptureController

    private enum Item {
        case button(symbol: String, title: String?, key: String?, active: Bool, action: CaptureController.Action)
        case swatch(NSColor, selected: Bool, action: CaptureController.Action)
        case toggle(title: String, key: String, on: Bool, action: CaptureController.Action)
        case sizeLabel(String)
        case divider
    }

    private static let barHeight: CGFloat = 46
    private static let itemHeight: CGFloat = 32
    private static let padding: CGFloat = 7
    private static let spacing: CGFloat = 3

    private static let titleFont = NSFont.systemFont(ofSize: 13, weight: .semibold)
    private static let keyFont = NSFont.systemFont(ofSize: 10.5, weight: .bold)

    private var hoveredIndex: Int?

    init(controller: CaptureController) {
        self.controller = controller
        super.init(frame: .zero)
        wantsLayer = true
        layer?.shadowColor = NSColor.black.cgColor
        layer?.shadowOpacity = 0.45
        layer?.shadowRadius = 14
        layer?.shadowOffset = CGSize(width: 0, height: -4)
    }

    required init?(coder: NSCoder) { fatalError() }

    override var isFlipped: Bool { true }
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    // MARK: - Content

    private var items: [Item] {
        let c = controller
        let drawing = c.mode == .draw
        var items: [Item] = [
            .button(symbol: "viewfinder", title: "Select", key: "S", active: !drawing, action: .selectMode),
            .button(symbol: "pencil.tip", title: "Draw", key: "D", active: drawing, action: .drawMode),
            .divider,
            .button(symbol: "rectangle", title: nil, key: "R", active: drawing && c.tool == .rectangle, action: .tool(.rectangle)),
            .button(symbol: "circle", title: nil, key: "C", active: drawing && c.tool == .ellipse, action: .tool(.ellipse)),
            .button(symbol: "scribble", title: nil, key: "F", active: drawing && c.tool == .freehand, action: .tool(.freehand)),
            .divider,
        ]
        for (index, entry) in Palette.colors.enumerated() {
            items.append(.swatch(entry.color, selected: index == c.colorIndex, action: .color(index)))
        }
        items += [
            .divider,
            .button(symbol: "minus", title: nil, key: "[", active: false, action: .thinner),
            .sizeLabel("\(Int(c.lineWidth))px"),
            .button(symbol: "plus", title: nil, key: "]", active: false, action: .thicker),
            .divider,
            .button(symbol: "arrow.uturn.backward", title: nil, key: "⌘Z", active: false, action: .undo),
            .divider,
            .toggle(title: "Blur", key: "B", on: c.blurOutside, action: .toggleBlur),
            .divider,
            .button(symbol: "doc.on.clipboard", title: "Copy", key: "↩", active: false, action: .copy),
        ]
        if c.canUpload {
            items.append(.button(symbol: "icloud.and.arrow.up", title: "Upload", key: "⌃↩", active: false, action: .upload))
        }
        items.append(.button(symbol: "xmark", title: nil, key: "Esc", active: false, action: .cancel))
        return items
    }

    // MARK: - Layout

    private func width(of item: Item) -> CGFloat {
        switch item {
        case .button(_, let title, let key, _, _):
            var w: CGFloat = 10 + 18 + 10
            if let title { w += 6 + textWidth(title, Self.titleFont) }
            if let key { w += 7 + keycapWidth(key) }
            return w
        case .toggle(let title, let key, _, _):
            return 10 + 18 + 6 + textWidth(title, Self.titleFont) + 7 + keycapWidth(key) + 10
        case .swatch: return 26
        case .sizeLabel(let text): return max(40, textWidth(text, Self.titleFont) + 8)
        case .divider: return 13
        }
    }

    private func layoutItems() -> [(item: Item, frame: CGRect)] {
        var x = Self.padding
        let y = (Self.barHeight - Self.itemHeight) / 2
        return items.map { item in
            let w = width(of: item)
            defer { x += w + Self.spacing }
            return (item, CGRect(x: x, y: y, width: w, height: Self.itemHeight))
        }
    }

    var preferredSize: CGSize {
        let total = items.reduce(0) { $0 + width(of: $1) + Self.spacing } - Self.spacing
        return CGSize(width: total + Self.padding * 2, height: Self.barHeight)
    }

    // MARK: - Drawing

    override func draw(_ dirtyRect: NSRect) {
        let bar = NSBezierPath(roundedRect: bounds.insetBy(dx: 0.5, dy: 0.5), xRadius: 13, yRadius: 13)
        NSColor(calibratedWhite: 0.11, alpha: 0.96).setFill()
        bar.fill()
        NSColor(calibratedWhite: 1, alpha: 0.14).setStroke()
        bar.lineWidth = 1
        bar.stroke()

        for (index, entry) in layoutItems().enumerated() {
            draw(entry.item, in: entry.frame, hovered: index == hoveredIndex)
        }
    }

    private func draw(_ item: Item, in frame: CGRect, hovered: Bool) {
        switch item {
        case .button(let symbol, let title, let key, let active, _):
            let pill = NSBezierPath(roundedRect: frame, xRadius: 8, yRadius: 8)
            if active {
                NSColor.controlAccentColor.setFill()
                pill.fill()
            } else if hovered {
                NSColor(calibratedWhite: 1, alpha: 0.12).setFill()
                pill.fill()
            }
            let fg = NSColor(calibratedWhite: 1, alpha: active ? 1 : 0.9)
            var x = frame.minX + 10
            drawSymbol(symbol, centeredIn: CGRect(x: x, y: frame.minY, width: 18, height: frame.height), color: fg)
            x += 18
            if let title {
                x += 6
                let size = drawText(title, font: Self.titleFont, color: fg, x: x, midY: frame.midY)
                x += size.width
            }
            if let key {
                x += 7
                drawKeycap(key, x: x, midY: frame.midY, onAccent: active)
            }

        case .toggle(let title, let key, let on, _):
            if hovered {
                NSColor(calibratedWhite: 1, alpha: 0.12).setFill()
                NSBezierPath(roundedRect: frame, xRadius: 8, yRadius: 8).fill()
            }
            var x = frame.minX + 10
            let box = CGRect(x: x, y: frame.minY, width: 18, height: frame.height)
            if on {
                drawSymbol("checkmark.square.fill", centeredIn: box, color: .controlAccentColor, background: .white)
            } else {
                drawSymbol("square", centeredIn: box, color: NSColor(calibratedWhite: 1, alpha: 0.9))
            }
            x += 18 + 6
            x += drawText(title, font: Self.titleFont, color: .white, x: x, midY: frame.midY).width + 7
            drawKeycap(key, x: x, midY: frame.midY, onAccent: false)

        case .swatch(let color, let selected, _):
            let dot = CGRect(x: frame.midX - 8, y: frame.midY - 8, width: 16, height: 16)
            color.setFill()
            NSBezierPath(ovalIn: dot).fill()
            NSColor(calibratedWhite: 1, alpha: 0.35).setStroke()
            NSBezierPath(ovalIn: dot.insetBy(dx: 0.5, dy: 0.5)).stroke()
            if selected || hovered {
                let ring = NSBezierPath(ovalIn: dot.insetBy(dx: -3.5, dy: -3.5))
                ring.lineWidth = 2
                NSColor(calibratedWhite: 1, alpha: selected ? 1 : 0.4).setStroke()
                ring.stroke()
            }

        case .sizeLabel(let text):
            let size = (text as NSString).size(withAttributes: [.font: Self.titleFont])
            drawText(text, font: Self.titleFont, color: .white, x: frame.midX - size.width / 2, midY: frame.midY)

        case .divider:
            NSColor(calibratedWhite: 1, alpha: 0.16).setFill()
            CGRect(x: frame.midX - 0.5, y: frame.minY + 6, width: 1, height: frame.height - 12).fill()
        }
    }

    /// `background` fills the symbol's secondary layer (e.g. the tick in checkmark.square.fill).
    private func drawSymbol(_ name: String, centeredIn rect: CGRect, color: NSColor, background: NSColor? = nil) {
        let palette = background.map { [$0, color] } ?? [color]
        let config = NSImage.SymbolConfiguration(pointSize: 14, weight: .semibold)
            .applying(.init(paletteColors: palette))
        guard let image = NSImage(systemSymbolName: name, accessibilityDescription: nil)?
            .withSymbolConfiguration(config) else { return }
        let s = image.size
        image.draw(in: CGRect(x: rect.midX - s.width / 2, y: rect.midY - s.height / 2, width: s.width, height: s.height),
                   from: .zero, operation: .sourceOver, fraction: 1, respectFlipped: true, hints: nil)
    }

    @discardableResult
    private func drawText(_ text: String, font: NSFont, color: NSColor, x: CGFloat, midY: CGFloat) -> CGSize {
        let attrs: [NSAttributedString.Key: Any] = [.font: font, .foregroundColor: color]
        let size = (text as NSString).size(withAttributes: attrs)
        (text as NSString).draw(at: CGPoint(x: x, y: midY - size.height / 2), withAttributes: attrs)
        return size
    }

    private func drawKeycap(_ key: String, x: CGFloat, midY: CGFloat, onAccent: Bool) {
        let rect = CGRect(x: x, y: midY - 9, width: keycapWidth(key), height: 18)
        NSColor(calibratedWhite: onAccent ? 1 : 0.5, alpha: onAccent ? 0.28 : 0.3).setFill()
        NSBezierPath(roundedRect: rect, xRadius: 4, yRadius: 4).fill()
        let attrs: [NSAttributedString.Key: Any] = [.font: Self.keyFont, .foregroundColor: NSColor.white]
        let size = (key as NSString).size(withAttributes: attrs)
        (key as NSString).draw(at: CGPoint(x: rect.midX - size.width / 2, y: rect.midY - size.height / 2), withAttributes: attrs)
    }

    private func keycapWidth(_ key: String) -> CGFloat { max(18, textWidth(key, Self.keyFont) + 9) }

    private func textWidth(_ text: String, _ font: NSFont) -> CGFloat {
        ceil((text as NSString).size(withAttributes: [.font: font]).width)
    }

    // MARK: - Mouse

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        trackingAreas.forEach(removeTrackingArea)
        addTrackingArea(NSTrackingArea(rect: .zero, options: [.mouseMoved, .mouseEnteredAndExited, .activeAlways, .inVisibleRect],
                                       owner: self, userInfo: nil))
    }

    override func resetCursorRects() {
        addCursorRect(bounds, cursor: .arrow)
    }

    private func itemIndex(at event: NSEvent) -> Int? {
        let p = convert(event.locationInWindow, from: nil)
        return layoutItems().firstIndex { entry in
            switch entry.item {
            case .button, .swatch, .toggle: return entry.frame.contains(p)
            case .sizeLabel, .divider: return false
            }
        }
    }

    override func mouseMoved(with event: NSEvent) {
        let index = itemIndex(at: event)
        if index != hoveredIndex { hoveredIndex = index; needsDisplay = true }
    }

    override func mouseExited(with event: NSEvent) {
        hoveredIndex = nil
        needsDisplay = true
    }

    /// Clicks on the bar itself are swallowed so they don't start a selection underneath.
    override func mouseDown(with event: NSEvent) {
        guard let index = itemIndex(at: event) else { return }
        switch layoutItems()[index].item {
        case .button(_, _, _, _, let action), .swatch(_, _, let action), .toggle(_, _, _, let action):
            controller.perform(action)
        case .sizeLabel, .divider:
            break
        }
    }

    override func mouseDragged(with event: NSEvent) {}
    override func mouseUp(with event: NSEvent) {}
}
