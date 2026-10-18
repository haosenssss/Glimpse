import AppKit
import GlimpseCore
import ScreenCaptureKit

/// Plain values describing what to capture, so the capture can run off the main actor.
struct CaptureTarget: Sendable {
    /// Selection in global Cocoa coordinates (origin bottom-left of the main screen).
    let rect: CGRect
    let displayID: CGDirectDisplayID
    let screenFrame: CGRect
    let scale: CGFloat

    @MainActor
    init?(rect: CGRect, screen: NSScreen) {
        guard let displayID = screen.displayID else { return nil }
        self.rect = rect
        self.displayID = displayID
        screenFrame = screen.frame
        scale = screen.backingScaleFactor
    }

    /// ScreenCaptureKit wants display-local points with a top-left origin.
    var displayLocalRect: CGRect {
        CGRect(x: rect.minX - screenFrame.minX, y: screenFrame.maxY - rect.maxY, width: rect.width, height: rect.height)
    }

    /// The same rect in global CoreGraphics coordinates (top-left origin of the main display).
    var globalDisplayRect: CGRect {
        let bounds = CGDisplayBounds(displayID)
        return displayLocalRect.offsetBy(dx: bounds.minX, dy: bounds.minY)
    }
}

enum ScreenCapturer {
    /// Captures the target at the screen's native resolution.
    static func capture(_ target: CaptureTarget) async throws -> CGImage {
        guard CGPreflightScreenCaptureAccess() else {
            CGRequestScreenCaptureAccess()
            throw ChatError.capture("Screen Recording permission required")
        }
        if #available(macOS 15.2, *) {
            return try await captureRegion(target)
        }
        return try await captureDisplay(target)
    }

    /// Region capture, the path the system screenshot tool uses. The per-display filter
    /// capture below returns partially blank frames on virtual displays such as Sidecar.
    @available(macOS 15.2, *)
    private static func captureRegion(_ target: CaptureTarget) async throws -> CGImage {
        do {
            return try await SCScreenshotManager.captureImage(in: target.globalDisplayRect)
        } catch {
            throw ChatError.capture("Capture failed: \(error.localizedDescription)")
        }
    }

    /// Pre-15.2 fallback: capture through a display filter, leaving Glimpse's own windows out.
    private static func captureDisplay(_ target: CaptureTarget) async throws -> CGImage {
        let content: SCShareableContent
        do {
            content = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: true)
        } catch {
            throw ChatError.capture("Screen capture unavailable: \(error.localizedDescription)")
        }

        guard let display = content.displays.first(where: { $0.displayID == target.displayID }) else {
            throw ChatError.capture("Display not found")
        }

        let ownPID = ProcessInfo.processInfo.processIdentifier
        let ownApps = content.applications.filter { $0.processID == ownPID }
        let filter = SCContentFilter(display: display, excludingApplications: ownApps, exceptingWindows: [])

        let configuration = SCStreamConfiguration()
        configuration.sourceRect = target.displayLocalRect
        configuration.width = Int((target.rect.width * target.scale).rounded())
        configuration.height = Int((target.rect.height * target.scale).rounded())
        configuration.showsCursor = false
        configuration.captureResolution = .best

        do {
            return try await SCScreenshotManager.captureImage(contentFilter: filter, configuration: configuration)
        } catch {
            throw ChatError.capture("Capture failed: \(error.localizedDescription)")
        }
    }
}

extension NSScreen {
    var displayID: CGDirectDisplayID? {
        deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? CGDirectDisplayID
    }
}
