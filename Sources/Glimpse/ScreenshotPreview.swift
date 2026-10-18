import AppKit

/// Shows the image most recently sent to the model, straight from memory, so a
/// wrong or blank capture can be spotted at a glance.
@MainActor
final class ScreenshotPreview {
    private static let maxSide: CGFloat = 640

    private var window: NSWindow?

    func show(jpeg: Data) {
        guard let image = NSImage(data: jpeg), let rep = image.representations.first else { return }
        let pixels = NSSize(width: rep.pixelsWide, height: rep.pixelsHigh)
        let scale = min(1, Self.maxSide / max(pixels.width, pixels.height, 1))
        let size = NSSize(width: pixels.width * scale, height: pixels.height * scale)

        let imageView = NSImageView(frame: NSRect(origin: .zero, size: size))
        imageView.image = image
        imageView.imageScaling = .scaleProportionallyUpOrDown

        let window = self.window ?? NSWindow(
            contentRect: NSRect(origin: .zero, size: size), styleMask: [.titled, .closable, .resizable],
            backing: .buffered, defer: false
        )
        window.isReleasedWhenClosed = false
        window.title = "Last Screenshot — \(Int(pixels.width))×\(Int(pixels.height)) px sent"
        window.contentView = imageView
        window.setContentSize(size)
        window.center()
        self.window = window

        NSApp.activate(ignoringOtherApps: true)
        window.makeKeyAndOrderFront(nil)
    }
}
