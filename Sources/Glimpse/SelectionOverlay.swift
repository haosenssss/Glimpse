import AppKit

/// Transparent, non-activating panels (one per screen) for dragging out a capture
/// region. The frontmost app keeps keyboard focus the whole time.
@MainActor
final class SelectionOverlay {
    /// `rect` is in global Cocoa screen coordinates (origin bottom-left of the main screen).
    typealias Completion = (_ rect: CGRect, _ screen: NSScreen) -> Void

    private static let minimumSide: CGFloat = 4
    /// Fully clear windows let clicks fall through to the app below; 1/255 alpha is invisible but hit-testable.
    private static let hitTestableClear = NSColor(white: 0, alpha: 1.0 / 255.0)

    private var panels: [NSPanel] = []
    private let onComplete: Completion
    private let onCancel: () -> Void

    init(onComplete: @escaping Completion, onCancel: @escaping () -> Void) {
        self.onComplete = onComplete
        self.onCancel = onCancel
    }

    func show() {
        panels = NSScreen.screens.map(makePanel)
        panels.forEach { $0.orderFrontRegardless() }
    }

    func close() {
        panels.forEach { $0.orderOut(nil) }
        panels = []
    }

    private func makePanel(for screen: NSScreen) -> NSPanel {
        let panel = PassivePanel(contentRect: screen.frame, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        panel.level = .screenSaver
        panel.isOpaque = false
        panel.backgroundColor = Self.hitTestableClear
        panel.hasShadow = false
        panel.ignoresMouseEvents = false
        panel.hidesOnDeactivate = false
        panel.isReleasedWhenClosed = false
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]

        let view = SelectionView(frame: CGRect(origin: .zero, size: screen.frame.size))
        view.onFinish = { [weak self] localRect in self?.finish(localRect, on: screen) }
        panel.contentView = view
        panel.setFrame(screen.frame, display: false)
        return panel
    }

    private func finish(_ localRect: CGRect, on screen: NSScreen) {
        close()
        guard localRect.width >= Self.minimumSide, localRect.height >= Self.minimumSide else {
            onCancel()
            return
        }
        onComplete(localRect.offsetBy(dx: screen.frame.minX, dy: screen.frame.minY), screen)
    }
}

/// Never becomes key or main, so showing it can't pull focus from the frontmost app.
final class PassivePanel: NSPanel {
    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }
}

/// Draws the drag rectangle as a two-tone hairline: visible on any background, never loud.
final class SelectionView: NSView {
    var onFinish: ((CGRect) -> Void)?

    private var start: CGPoint?
    private var current: CGPoint?

    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    override func mouseDown(with event: NSEvent) {
        start = location(of: event)
        current = start
        needsDisplay = true
    }

    override func mouseDragged(with event: NSEvent) {
        current = location(of: event)
        needsDisplay = true
    }

    override func mouseUp(with event: NSEvent) {
        current = location(of: event)
        let rect = selectionRect ?? .zero
        start = nil
        current = nil
        needsDisplay = true
        onFinish?(rect)
    }

    override func draw(_ dirtyRect: NSRect) {
        guard let rect = selectionRect?.integral, rect.width > 1, rect.height > 1 else { return }
        stroke(rect.insetBy(dx: 0.5, dy: 0.5), color: NSColor(white: 1, alpha: 0.35))
        stroke(rect.insetBy(dx: 1.5, dy: 1.5), color: NSColor(white: 0, alpha: 0.25))
    }

    private var selectionRect: CGRect? {
        guard let start, let current else { return nil }
        return CGRect(x: min(start.x, current.x), y: min(start.y, current.y), width: abs(start.x - current.x), height: abs(start.y - current.y))
    }

    private func location(of event: NSEvent) -> CGPoint {
        let point = convert(event.locationInWindow, from: nil)
        return CGPoint(x: min(max(point.x, 0), bounds.maxX), y: min(max(point.y, 0), bounds.maxY))
    }

    private func stroke(_ rect: CGRect, color: NSColor) {
        let path = NSBezierPath(rect: rect)
        path.lineWidth = 1
        color.setStroke()
        path.stroke()
    }
}
