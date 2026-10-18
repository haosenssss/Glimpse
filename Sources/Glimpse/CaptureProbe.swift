import AppKit
import GlimpseCore

/// Diagnostics: `Glimpse --probe-capture X Y W H OUT.jpg` captures a rect (global Cocoa
/// coordinates) through exactly the same capture + encode path as a real request and
/// writes the JPEG that would have been sent. Only runs when invoked explicitly.
enum CaptureProbe {
    static let flag = "--probe-capture"

    @MainActor
    static func run(_ arguments: [String]) -> Never {
        let numbers = arguments.prefix(4).compactMap(Double.init)
        guard numbers.count == 4, arguments.count >= 5 else {
            fail("usage: Glimpse \(flag) X Y W H OUT.jpg")
        }
        let rect = CGRect(x: numbers[0], y: numbers[1], width: numbers[2], height: numbers[3])
        guard let screen = NSScreen.screens.first(where: { $0.frame.contains(CGPoint(x: rect.midX, y: rect.midY)) }),
              let target = CaptureTarget(rect: rect, screen: screen)
        else { fail("no screen contains \(rect)") }

        let output = URL(fileURLWithPath: arguments[4])
        print("screen frame \(screen.frame) scale \(screen.backingScaleFactor); source rect \(target.displayLocalRect)")
        Task {
            do {
                let image = try await ScreenCapturer.capture(target)
                print("captured \(image.width)x\(image.height), alpha \(image.alphaInfo.rawValue), bpc \(image.bitsPerComponent)")
                guard let jpeg = Data(base64Encoded: try ImageEncoder.encodeJPEGBase64(image)) else { fail("encode failed") }
                try jpeg.write(to: output)
                print("wrote \(output.path)")
                exit(0)
            } catch {
                fail("\(error)")
            }
        }
        dispatchMain()
    }

    private static func fail(_ message: String) -> Never {
        FileHandle.standardError.write(Data("probe: \(message)\n".utf8))
        exit(1)
    }
}
