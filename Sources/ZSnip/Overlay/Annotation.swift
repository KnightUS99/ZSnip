import AppKit

enum DrawTool: String {
    case rectangle = "Rectangle"
    case ellipse = "Circle"
    case freehand = "Freehand"
}

/// A shape drawn on top of the frozen screenshot, in the overlay view's (flipped, point) coordinates.
struct Annotation {
    enum Shape {
        case rectangle(CGRect)
        case ellipse(CGRect)
        case freehand([CGPoint])
    }

    var shape: Shape
    var color: NSColor
    var lineWidth: CGFloat

    /// Area the shape covers on screen, including half the stroke width.
    var bounds: CGRect {
        let rect: CGRect
        switch shape {
        case .rectangle(let r), .ellipse(let r):
            rect = r
        case .freehand(let points):
            let xs = points.map(\.x), ys = points.map(\.y)
            guard let minX = xs.min(), let maxX = xs.max(), let minY = ys.min(), let maxY = ys.max() else { return .null }
            rect = CGRect(x: minX, y: minY, width: maxX - minX, height: maxY - minY)
        }
        return rect.insetBy(dx: -lineWidth / 2, dy: -lineWidth / 2)
    }

    func draw() {
        let path: NSBezierPath
        switch shape {
        case .rectangle(let rect):
            path = NSBezierPath(rect: rect)
        case .ellipse(let rect):
            path = NSBezierPath(ovalIn: rect)
        case .freehand(let points):
            path = NSBezierPath()
            guard let first = points.first else { return }
            path.move(to: first)
            for p in points.dropFirst() { path.line(to: p) }
        }
        path.lineWidth = lineWidth
        path.lineJoinStyle = .round
        path.lineCapStyle = .round
        color.setStroke()
        path.stroke()
    }
}

/// Colours selectable with the 1–5 keys while drawing.
enum Palette {
    static let colors: [(name: String, color: NSColor)] = [
        ("Red", .systemRed),
        ("Yellow", .systemYellow),
        ("Green", .systemGreen),
        ("Blue", .systemBlue),
        ("White", .white),
    ]
}
