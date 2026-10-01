import AppKit

/// Shows one display's frozen screenshot and handles drawing and selecting on it.
/// Uses flipped (top-left origin) coordinates to match CGImage pixel rows.
final class OverlayView: NSView {
    let snapshot: ScreenSnapshot
    unowned let controller: CaptureController

    /// Space kept around drawings when ↩ is pressed with no selection.
    static let autoCropPadding: CGFloat = 12

    private(set) var annotations: [Annotation] = []
    private var inProgress: Annotation?
    private(set) var selection: CGRect?
    private var dragStart: CGPoint?
    private var lastDragPoint: CGPoint?
    /// Which way a Shift-constrained square extends from the start point (+1/−1 per axis).
    /// Only flips once the pointer is clearly past the start, so jitter near the axis doesn't flip it.
    private var constrainDirection = CGPoint(x: 1, y: 1)
    private static let directionFlipThreshold: CGFloat = 4

    private let toolbar: ToolbarView
    private lazy var backgroundImage = NSImage(cgImage: snapshot.image, size: bounds.size)

    /// Made on first use of Blur mode (it takes a moment on big displays), then reused.
    private(set) lazy var blurredSnapshot: CGImage? = {
        let scale = CGFloat(snapshot.image.width) / bounds.width
        return ImageRenderer.blurred(snapshot.image, radius: 12 * scale)
    }()
    private lazy var blurredBackground: NSImage? = blurredSnapshot.map { NSImage(cgImage: $0, size: bounds.size) }

    init(snapshot: ScreenSnapshot, controller: CaptureController) {
        self.snapshot = snapshot
        self.controller = controller
        toolbar = ToolbarView(controller: controller)
        super.init(frame: NSRect(origin: .zero, size: snapshot.screen.frame.size))
        addSubview(toolbar)
        layoutToolbar()
    }

    required init?(coder: NSCoder) { fatalError() }

    override var isFlipped: Bool { true }
    override var acceptsFirstResponder: Bool { true }
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    override func resetCursorRects() {
        addCursorRect(bounds, cursor: .crosshair)
    }

    /// The area around all drawings plus padding, used when there's no explicit selection.
    var autoCropRect: CGRect? {
        guard !annotations.isEmpty else { return nil }
        let union = annotations.reduce(CGRect.null) { $0.union($1.bounds) }
        let rect = union.insetBy(dx: -Self.autoCropPadding, dy: -Self.autoCropPadding).intersection(bounds)
        return rect.isEmpty ? nil : rect
    }

    /// The area that stays sharp in Blur mode: the selection, else the area around the drawings.
    private var focusRect: CGRect? { selection ?? autoCropRect }

    // MARK: - State changes driven by the controller

    /// Re-layouts the toolbar and redraws after any state change.
    func refresh() {
        layoutToolbar()
        toolbar.needsDisplay = true
        needsDisplay = true
    }

    func clearSelection() {
        guard selection != nil else { return }
        selection = nil
        refresh()
    }

    func removeLastAnnotation() {
        guard !annotations.isEmpty else { return }
        annotations.removeLast()
        refresh()
    }

    /// Centered near the top (below any notch); jumps to the bottom if it would cover the selection.
    private func layoutToolbar() {
        let size = toolbar.preferredSize
        let top = snapshot.screen.safeAreaInsets.top + 16
        var frame = CGRect(x: ((bounds.width - size.width) / 2).rounded(), y: top, width: size.width, height: size.height)
        let captionSpace = frame.insetBy(dx: -12, dy: -12).union(frame.offsetBy(dx: 0, dy: 40))
        if let selection, selection.intersects(captionSpace) {
            frame.origin.y = bounds.height - size.height - 56
        }
        if toolbar.frame != frame { toolbar.frame = frame }
    }

    // MARK: - Mouse

    override func mouseDown(with event: NSEvent) {
        let p = clamped(convert(event.locationInWindow, from: nil))
        dragStart = p
        lastDragPoint = p
        constrainDirection = CGPoint(x: 1, y: 1)
        switch controller.mode {
        case .select:
            controller.selectionWillBegin(in: self)
            selection = nil
        case .draw:
            inProgress = makeAnnotation(from: p, to: p, constrain: false)
        }
        needsDisplay = true
    }

    override func mouseDragged(with event: NSEvent) {
        guard let start = dragStart else { return }
        let p = clamped(convert(event.locationInWindow, from: nil))
        lastDragPoint = p
        switch controller.mode {
        case .select:
            selection = rect(from: start, to: p, constrain: false)
            layoutToolbar()
        case .draw:
            if var current = inProgress, case .freehand(var points) = current.shape {
                points.append(p)
                current.shape = .freehand(points)
                inProgress = current
            } else {
                updateShape(from: start, to: p)
            }
        }
        needsDisplay = true
    }

    /// Pressing or releasing Shift mid-drag reshapes immediately, without waiting for the mouse to move.
    override func flagsChanged(with event: NSEvent) {
        guard controller.mode == .draw, let start = dragStart, let p = lastDragPoint,
              let current = inProgress else { return super.flagsChanged(with: event) }
        if case .freehand = current.shape { return }
        updateShape(from: start, to: p)
        needsDisplay = true
    }

    private func updateShape(from start: CGPoint, to p: CGPoint) {
        // Live key state rather than the event's flags, which can lag behind a Shift press.
        let constrain = NSEvent.modifierFlags.contains(.shift)
        inProgress = makeAnnotation(from: start, to: p, constrain: constrain)
    }

    override func mouseUp(with event: NSEvent) {
        defer { dragStart = nil; lastDragPoint = nil; needsDisplay = true }
        switch controller.mode {
        case .select:
            if let s = selection, s.width < 3 || s.height < 3 { selection = nil }
            controller.selectionDidChange()
        case .draw:
            guard let annotation = inProgress else { return }
            inProgress = nil
            if annotation.isMeaningful {
                annotations.append(annotation)
                controller.didAddAnnotation(in: self)
            }
        }
    }

    override func keyDown(with event: NSEvent) {
        if !controller.handleKey(event) { super.keyDown(with: event) }
    }

    private func makeAnnotation(from a: CGPoint, to b: CGPoint, constrain: Bool) -> Annotation {
        let shape: Annotation.Shape
        switch controller.tool {
        case .rectangle: shape = .rectangle(rect(from: a, to: b, constrain: constrain))
        case .ellipse: shape = .ellipse(rect(from: a, to: b, constrain: constrain))
        case .freehand: shape = .freehand([a])
        }
        return Annotation(shape: shape, color: controller.color, lineWidth: controller.lineWidth)
    }

    /// Rect spanning two points; with `constrain` (Shift held) it becomes a square.
    private func rect(from a: CGPoint, to b: CGPoint, constrain: Bool) -> CGRect {
        var dx = b.x - a.x, dy = b.y - a.y
        if constrain {
            if abs(dx) > Self.directionFlipThreshold { constrainDirection.x = dx < 0 ? -1 : 1 }
            if abs(dy) > Self.directionFlipThreshold { constrainDirection.y = dy < 0 ? -1 : 1 }
            let side = max(abs(dx), abs(dy))
            dx = side * constrainDirection.x
            dy = side * constrainDirection.y
        }
        return CGRect(x: a.x, y: a.y, width: dx, height: dy).standardized
    }

    private func clamped(_ p: CGPoint) -> CGPoint {
        CGPoint(x: min(max(p.x, 0), bounds.width), y: min(max(p.y, 0), bounds.height))
    }

    // MARK: - Drawing

    override func draw(_ dirtyRect: NSRect) {
        if controller.blurOutside, let focus = focusRect, let blurred = blurredBackground {
            blurred.draw(in: bounds, from: .zero, operation: .copy, fraction: 1, respectFlipped: true, hints: nil)
            NSGraphicsContext.saveGraphicsState()
            focus.clip()
            drawBackground()
            NSGraphicsContext.restoreGraphicsState()
        } else {
            drawBackground()
        }

        for annotation in annotations { annotation.draw() }
        inProgress?.draw()

        drawDimming()
        if let selection {
            drawSelectionChrome(selection)
        } else if inProgress == nil, let autoCrop = autoCropRect {
            drawAutoCropPreview(autoCrop)
        }
        drawCaption()
    }

    private func drawBackground() {
        backgroundImage.draw(in: bounds, from: .zero, operation: .copy, fraction: 1,
                             respectFlipped: true, hints: [.interpolation: NSImageInterpolation.none])
    }

    /// Darkens everything outside the selection. With no selection, dims the whole
    /// screen in select mode (so it's obvious you're about to pick an area) but not in draw mode.
    private func drawDimming() {
        let dim = NSColor.black.withAlphaComponent(0.4)
        if controller.blurOutside && focusRect != nil {
            return // the blur already shows what's outside
        }
        if let selection {
            let path = NSBezierPath(rect: bounds)
            path.append(NSBezierPath(rect: selection))
            path.windingRule = .evenOdd
            dim.setFill()
            path.fill()
        } else if controller.mode == .select && dragStart == nil && autoCropRect == nil {
            dim.setFill()
            bounds.fill()
        }
    }

    private func drawSelectionChrome(_ rect: CGRect) {
        let outline = NSBezierPath(rect: rect.insetBy(dx: -0.5, dy: -0.5))
        outline.lineWidth = 1
        NSColor.white.setStroke()
        outline.stroke()
        drawSizeLabel(for: rect)
    }

    /// Dashed outline showing what ↩ will copy when nothing is selected.
    private func drawAutoCropPreview(_ rect: CGRect) {
        let outline = NSBezierPath(rect: rect.insetBy(dx: -0.5, dy: -0.5))
        outline.lineWidth = 1.5
        outline.setLineDash([6, 4], count: 2, phase: 0)
        NSColor.black.withAlphaComponent(0.6).setStroke()
        outline.stroke()
        outline.setLineDash([6, 4], count: 2, phase: 5)
        NSColor.white.setStroke()
        outline.stroke()
        drawSizeLabel(for: rect)
    }

    private func drawSizeLabel(for rect: CGRect) {
        let scale = CGFloat(snapshot.image.width) / bounds.width
        let label = "\(Int((rect.width * scale).rounded())) × \(Int((rect.height * scale).rounded()))"
        let attrs: [NSAttributedString.Key: Any] = [
            .font: NSFont.monospacedDigitSystemFont(ofSize: 11, weight: .semibold),
            .foregroundColor: NSColor.white,
        ]
        let size = (label as NSString).size(withAttributes: attrs)
        var origin = CGPoint(x: rect.minX, y: rect.minY - size.height - 10)
        if origin.y < 2 { origin = CGPoint(x: rect.minX + 4, y: rect.minY + 4) }
        let bg = CGRect(x: origin.x, y: origin.y, width: size.width + 12, height: size.height + 6)
        NSColor(calibratedWhite: 0.11, alpha: 0.9).setFill()
        NSBezierPath(roundedRect: bg, xRadius: 5, yRadius: 5).fill()
        (label as NSString).draw(at: CGPoint(x: bg.minX + 6, y: bg.minY + 3), withAttributes: attrs)
    }

    /// One line under the toolbar saying what's going on and what ↩ will do.
    private func drawCaption() {
        let text: String
        if controller.blurOutside {
            if selection != nil {
                text = "↩ copies the whole screen, blurred outside the selection  ·  B turns blur off"
            } else if !annotations.isEmpty {
                text = "↩ copies the whole screen, blurred outside the dashed area  ·  S to select instead"
            } else {
                text = "Blur is on: select the area to keep sharp  ·  B turns blur off"
            }
        } else if selection != nil {
            text = "↩ copies the selection  ·  D to draw on it  ·  drag again to reselect"
        } else if !annotations.isEmpty {
            text = "↩ copies the dashed area around your drawings  ·  S to select an area yourself"
        } else if controller.mode == .draw {
            text = "Drag to draw  ·  hold ⇧ for a perfect square or circle"
        } else {
            text = "Drag to select an area  ·  ↩ copies the whole screen"
        }

        let attrs: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 12, weight: .medium),
            .foregroundColor: NSColor(calibratedWhite: 1, alpha: 0.95),
        ]
        let size = (text as NSString).size(withAttributes: attrs)
        let height = size.height + 8
        let toolbarAtBottom = toolbar.frame.midY > bounds.midY
        let pill = CGRect(x: ((bounds.width - size.width) / 2 - 12).rounded(),
                          y: toolbarAtBottom ? toolbar.frame.minY - 8 - height : toolbar.frame.maxY + 8,
                          width: size.width + 24, height: height)
        NSColor(calibratedWhite: 0.11, alpha: 0.85).setFill()
        NSBezierPath(roundedRect: pill, xRadius: pill.height / 2, yRadius: pill.height / 2).fill()
        (text as NSString).draw(at: CGPoint(x: pill.minX + 12, y: pill.minY + 4), withAttributes: attrs)
    }
}

private extension Annotation {
    /// Filters out accidental clicks that would leave a zero-size shape.
    var isMeaningful: Bool {
        switch shape {
        case .rectangle(let r), .ellipse(let r): return r.width >= 2 || r.height >= 2
        case .freehand(let points): return points.count >= 2
        }
    }
}
