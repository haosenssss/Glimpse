import AppKit

MainActor.assumeIsolated {
    let arguments = CommandLine.arguments
    if let index = arguments.firstIndex(of: CaptureProbe.flag) {
        CaptureProbe.run(Array(arguments[(index + 1)...]))
    }

    let app = NSApplication.shared
    let delegate = AppDelegate()
    app.delegate = delegate
    app.setActivationPolicy(.accessory)
    app.run()
}
