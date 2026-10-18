import AppKit
import GlimpseCore
import QuartzCore

/// The tiny on-screen signal: a spinning arc while working, a closed ring with a
/// check when the answer is ready, a thin × on error. No text, low contrast.
@MainActor
final class StatusIndicator {
    private static let padding: CGFloat = 4
    /// Extra grab area around the mark while it's being dragged into place.
    private static let editingPadding: CGFloat = 18
    private static let editingMinOpacity: CGFloat = 0.8
    private static let defaultInset: CGFloat = 24

    private let panel: PassivePanel
    private let view: IndicatorView
    private var settings: IndicatorSettings
    private(set) var isEditing = false
    private var moveObserver: NSObjectProtocol?

    var onPositionChanged: ((CGPoint) -> Void)?

    init(settings: IndicatorSettings) {
        self.settings = settings.clamped()
        panel = PassivePanel(contentRect: .zero, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        view = IndicatorView(frame: .zero)
        configurePanel()
        layout()
    }

    func apply(_ newSettings: IndicatorSettings) {
        settings = newSettings.clamped()
        layout()
        if panel.isVisible { panel.alphaValue = currentOpacity }
    }

    func show(_ style: IndicatorStyle) {
        guard !isEditing else { return }
        guard style != .hidden else {
            panel.orderOut(nil)
            return
        }
        view.style = style
        layout()
        panel.alphaValue = currentOpacity
        panel.orderFrontRegardless()
    }

    func beginEditing() {
        isEditing = true
        view.isEditing = true
        view.style = .ready
        panel.ignoresMouseEvents = false
        // Start where the user can see it: the saved spot, or else the middle of the screen they're on.
        layout(center: savedCenter ?? Self.mouseScreen.map { CGPoint(x: $0.visibleFrame.midX, y: $0.visibleFrame.midY) })
        panel.alphaValue = currentOpacity
        panel.orderFrontRegardless()
        // The window server moves the panel during the drag; record wherever it lands.
        moveObserver = NotificationCenter.default.addObserver(
            forName: NSWindow.didMoveNotification, object: panel, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.panelMoved() }
        }
    }

    func endEditing() {
        guard isEditing else { return }
        if let moveObserver { NotificationCenter.default.removeObserver(moveObserver) }
        moveObserver = nil
        isEditing = false
        view.isEditing = false
        panel.ignoresMouseEvents = true
        panel.orderOut(nil)
        layout()
    }

    private var currentOpacity: CGFloat {
        isEditing ? max(settings.opacity, Self.editingMinOpacity) : settings.opacity
    }

    private func configurePanel() {
        panel.level = .statusBar
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = false
        panel.ignoresMouseEvents = true
        panel.hidesOnDeactivate = false
        panel.isReleasedWhenClosed = false
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]
        panel.contentView = view
    }

    private func layout(center: CGPoint? = nil) {
        let padding = isEditing ? Self.editingPadding : Self.padding
        let side = settings.size + padding * 2
        let center = center ?? savedCenter ?? defaultCenter()
        panel.setFrame(CGRect(x: center.x - side / 2, y: center.y - side / 2, width: side, height: side), display: true)
        view.markInset = padding
        view.needsLayout = true
    }

    /// The dragged position, if it is still on a connected screen.
    private var savedCenter: CGPoint? {
        guard let x = settings.centerX, let y = settings.centerY else { return nil }
        let point = CGPoint(x: x, y: y)
        return NSScreen.screens.contains(where: { $0.frame.contains(point) }) ? point : nil
    }

    /// Bottom-right corner of the screen under the mouse — after a capture, that's the screen being looked at.
    private func defaultCenter() -> CGPoint {
        let frame = (Self.mouseScreen ?? NSScreen.main ?? NSScreen.screens.first)?.visibleFrame ?? .zero
        return CGPoint(x: frame.maxX - Self.defaultInset, y: frame.minY + Self.defaultInset)
    }

    private static var mouseScreen: NSScreen? {
        let mouse = NSEvent.mouseLocation
        return NSScreen.screens.first { NSMouseInRect(mouse, $0.frame, false) }
    }

    private func panelMoved() {
        guard isEditing else { return }
        let center = CGPoint(x: panel.frame.midX, y: panel.frame.midY)
        settings = IndicatorSettings(size: settings.size, opacity: settings.opacity, centerX: center.x, centerY: center.y)
        onPositionChanged?(center)
    }
}

final class IndicatorView: NSView {
    private static let tint = NSColor(white: 0.55, alpha: 1).cgColor
    private static let spinKey = "spin"
    private static let workingArc: CGFloat = 0.28

    var style: IndicatorStyle = .hidden { didSet { needsLayout = true } }
    var isEditing = false { didSet { needsLayout = true } }
    var markInset: CGFloat = 4

    private let ring = CAShapeLayer()
    private let mark = CAShapeLayer()

    /// Faint disc behind the mark while editing, so it's clear what to grab.
    private let haloLayer: CALayer = {
        let layer = CALayer()
        layer.backgroundColor = NSColor(white: 0.5, alpha: 0.22).cgColor
        return layer
    }()

    override init(frame: NSRect) {
        super.init(frame: frame)
        wantsLayer = true
        layer?.addSublayer(haloLayer)
        [ring, mark].forEach { shape in
            shape.fillColor = nil
            shape.strokeColor = Self.tint
            shape.lineCap = .round
            shape.lineJoin = .round
            layer?.addSublayer(shape)
        }
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    override func layout() {
        super.layout()
        let box = bounds.insetBy(dx: markInset, dy: markInset)
        let halo = bounds.insetBy(dx: max(0, markInset - 6), dy: max(0, markInset - 6))
        let lineWidth = max(1, box.width / 9)

        CATransaction.begin()
        CATransaction.setDisableActions(true)
        [ring, mark].forEach { shape in
            shape.frame = bounds
            shape.lineWidth = lineWidth
        }
        ring.path = CGPath(ellipseIn: box, transform: nil)
        haloLayer.frame = halo
        haloLayer.cornerRadius = halo.width / 2
        haloLayer.isHidden = !isEditing
        applyStyle(in: box)
        CATransaction.commit()
    }

    private func applyStyle(in box: CGRect) {
        ring.removeAnimation(forKey: Self.spinKey)
        switch style {
        case .hidden:
            ring.isHidden = true
            mark.isHidden = true
        case .working:
            ring.isHidden = false
            ring.strokeEnd = Self.workingArc
            mark.isHidden = true
            ring.add(Self.spinAnimation(), forKey: Self.spinKey)
        case .ready:
            ring.isHidden = false
            ring.strokeEnd = 1
            mark.isHidden = false
            mark.path = Self.checkPath(in: box)
        case .error:
            ring.isHidden = true
            mark.isHidden = false
            mark.path = Self.crossPath(in: box)
        }
    }

    private static func spinAnimation() -> CABasicAnimation {
        let animation = CABasicAnimation(keyPath: "transform.rotation.z")
        animation.fromValue = 0
        animation.toValue = -2 * Double.pi
        animation.duration = 1.2
        animation.repeatCount = .infinity
        return animation
    }

    private static func checkPath(in box: CGRect) -> CGPath {
        let path = CGMutablePath()
        path.move(to: point(0.30, 0.52, in: box))
        path.addLine(to: point(0.45, 0.36, in: box))
        path.addLine(to: point(0.71, 0.64, in: box))
        return path
    }

    private static func crossPath(in box: CGRect) -> CGPath {
        let path = CGMutablePath()
        path.move(to: point(0.25, 0.25, in: box))
        path.addLine(to: point(0.75, 0.75, in: box))
        path.move(to: point(0.25, 0.75, in: box))
        path.addLine(to: point(0.75, 0.25, in: box))
        return path
    }

    private static func point(_ x: CGFloat, _ y: CGFloat, in box: CGRect) -> CGPoint {
        CGPoint(x: box.minX + box.width * x, y: box.minY + box.height * y)
    }

    // MARK: - Dragging (only while editing the position)

    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    /// Hands the drag to the window server so the indicator tracks the cursor exactly.
    override func mouseDown(with event: NSEvent) {
        guard isEditing else { return }
        window?.performDrag(with: event)
    }
}
