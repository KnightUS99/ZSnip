import AppKit
import ScreenCaptureKit

/// Runs one capture session: freeze the screens, let the user draw/select, then output.
final class CaptureController {
    static let shared = CaptureController()

    enum Mode { case select, draw }

    /// Everything the user can do in the overlay, by key or by clicking the toolbar.
    enum Action {
        case selectMode, drawMode
        case tool(DrawTool)
        case color(Int)
        case thinner, thicker
        case toggleBlur
        case undo, copy, upload, cancel
    }

    private(set) var mode: Mode = .select
    private(set) var tool: DrawTool = .rectangle
    private(set) var colorIndex = 0
    private(set) var lineWidth: CGFloat = 4
    var color: NSColor { Palette.colors[colorIndex].color }

    private var windows: [OverlayWindow] = []
    private var views: [OverlayView] = []
    /// Views in the order annotations were added, so ⌘Z can undo across screens.
    private var undoStack: [OverlayView] = []
    private var isActive = false

    // MARK: - Lifecycle

    func begin() {
        guard !isActive else { return }
        isActive = true
        Task { @MainActor in
            do {
                let snapshots = try await ScreenCapturer.captureAllScreens()
                Settings.hasCapturedSuccessfully = true
                self.showOverlays(for: snapshots)
            } catch CaptureError.permissionDenied {
                self.isActive = false
                SetupWindowController.shared.show()
            } catch let error as SCStreamError where error.code == .userDeclined {
                // Clicked "Don't Allow" on the private window picker prompt.
                self.isActive = false
                Settings.hasCapturedSuccessfully = false
                SetupWindowController.shared.show()
            } catch {
                self.isActive = false
                Alerts.show(title: "Couldn't capture the screen", message: error.localizedDescription)
            }
        }
    }

    private func showOverlays(for snapshots: [ScreenSnapshot]) {
        mode = .select
        undoStack = []

        let mouse = NSEvent.mouseLocation
        var keyWindow: OverlayWindow?
        for snapshot in snapshots {
            let window = OverlayWindow(screen: snapshot.screen)
            let view = OverlayView(snapshot: snapshot, controller: self)
            window.contentView = view
            windows.append(window)
            views.append(view)
            if snapshot.screen.frame.contains(mouse) { keyWindow = window }
        }

        NSApp.activate(ignoringOtherApps: true)
        for window in windows { window.orderFrontRegardless() }
        let key = keyWindow ?? windows.first
        key?.makeKeyAndOrderFront(nil)
        key?.makeFirstResponder(key?.contentView)
        NSCursor.crosshair.set()
    }

    private func end() {
        for window in windows { window.orderOut(nil) }
        windows = []
        views = []
        undoStack = []
        isActive = false
    }

    // MARK: - Callbacks from OverlayView

    func selectionWillBegin(in view: OverlayView) {
        for other in views where other !== view { other.clearSelection() }
    }

    func selectionDidChange() {
        for view in views { view.refresh() }
    }

    func didAddAnnotation(in view: OverlayView) {
        undoStack.append(view)
        for view in views { view.refresh() }
    }

    /// When on, ↩ outputs the whole screen with everything outside the focus area blurred.
    var blurOutside: Bool { Settings.blurOutsideSelection }

    var canUpload: Bool { UploaderRegistry.shared.active != nil }

    /// Returns true if the key was handled.
    func handleKey(_ event: NSEvent) -> Bool {
        let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
        switch Int(event.keyCode) {
        case 53: perform(.cancel); return true                                   // Esc
        case 36, 76: perform(flags.contains(.shift) ? .upload : .copy); return true // Return, keypad Enter
        case 51, 117: perform(.undo); return true                                // Delete, Forward Delete
        default: break
        }

        guard let key = event.charactersIgnoringModifiers?.lowercased() else { return false }
        if flags.contains(.command) {
            if key == "z" { perform(.undo); return true }
            return false
        }

        switch key {
        case "s": perform(.selectMode)
        case "d": perform(.drawMode)
        case "r": perform(.tool(.rectangle))
        case "c", "e", "o": perform(.tool(.ellipse))
        case "f", "p": perform(.tool(.freehand))
        case "1", "2", "3", "4", "5": perform(.color(Int(key)! - 1))
        case "b": perform(.toggleBlur)
        case "[": perform(.thinner)
        case "]": perform(.thicker)
        default: return false
        }
        return true
    }

    func perform(_ action: Action) {
        switch action {
        case .selectMode: mode = .select
        case .drawMode: mode = .draw
        case .tool(let newTool): mode = .draw; tool = newTool
        case .color(let index): mode = .draw; colorIndex = min(max(index, 0), Palette.colors.count - 1)
        case .thinner: lineWidth = max(1, lineWidth - 1)
        case .thicker: lineWidth = min(30, lineWidth + 1)
        case .toggleBlur: Settings.blurOutsideSelection.toggle()
        case .undo: undo()
        case .copy: finish(upload: false); return
        case .upload: finish(upload: true); return
        case .cancel: end(); return
        }
        for view in views { view.refresh() }
    }

    // MARK: - Output

    private func undo() {
        guard let view = undoStack.popLast() else { return }
        view.removeLastAnnotation()
    }

    /// What ↩ will copy, in priority order:
    /// 1. an explicit selection,
    /// 2. the area around the drawings (preferring the screen under the mouse),
    /// 3. the whole screen under the mouse.
    private func outputTarget() -> (view: OverlayView, crop: CGRect)? {
        if let view = views.first(where: { $0.selection != nil }), let selection = view.selection {
            return (view, selection)
        }
        let mouse = NSEvent.mouseLocation
        let mouseView = views.first { $0.snapshot.screen.frame.contains(mouse) }
        if let view = [mouseView].compactMap({ $0 }).first(where: { $0.autoCropRect != nil })
                    ?? views.first(where: { $0.autoCropRect != nil }),
           let crop = view.autoCropRect {
            return (view, crop)
        }
        guard let view = mouseView ?? views.first else { return nil }
        return (view, view.bounds)
    }

    private func finish(upload: Bool) {
        guard let (view, crop) = outputTarget() else { return }
        let rendered: RenderedImage?
        if blurOutside, crop != view.bounds, let blurred = view.blurredSnapshot {
            // Whole screen, blurred everywhere except the chosen area.
            rendered = ImageRenderer.render(snapshot: view.snapshot.image, viewSize: view.bounds.size,
                                            annotations: view.annotations, crop: view.bounds,
                                            blurred: blurred, sharpRect: crop)
        } else {
            rendered = ImageRenderer.render(snapshot: view.snapshot.image, viewSize: view.bounds.size,
                                            annotations: view.annotations, crop: crop)
        }
        end()
        guard let rendered else { NSSound.beep(); return }

        if upload {
            UploadCoordinator.shared.upload(rendered)
        } else {
            Clipboard.copy(rendered)
            NSSound(named: "Tink")?.play()
        }
    }
}
