import CoreGraphics
import Foundation
import ImageIO
import UniformTypeIdentifiers

// Usage: MakeIcon <artwork.png> <output.png>
//
// Fits square artwork into Apple's macOS icon grid: a 1024 canvas with an 824pt
// rounded square (corner radius ~185) and a soft drop shadow, transparent outside.

let canvasSide = 1024
let shapeRect = CGRect(x: 100, y: 100, width: 824, height: 824)
let cornerRadius: CGFloat = 185.4

func fail(_ message: String) -> Never {
    FileHandle.standardError.write(Data("MakeIcon: \(message)\n".utf8))
    exit(1)
}

func loadImage(_ path: String) -> CGImage {
    guard let source = CGImageSourceCreateWithURL(URL(fileURLWithPath: path) as CFURL, nil),
          let image = CGImageSourceCreateImageAtIndex(source, 0, nil)
    else { fail("cannot read \(path)") }
    return image
}

/// Scales the artwork to cover `rect` (cropping the overflow), centered.
func aspectFillRect(for image: CGImage, in rect: CGRect) -> CGRect {
    let scale = max(rect.width / CGFloat(image.width), rect.height / CGFloat(image.height))
    let size = CGSize(width: CGFloat(image.width) * scale, height: CGFloat(image.height) * scale)
    return CGRect(x: rect.midX - size.width / 2, y: rect.midY - size.height / 2, width: size.width, height: size.height)
}

func renderIcon(from artwork: CGImage) -> CGImage {
    guard let context = CGContext(
        data: nil, width: canvasSide, height: canvasSide, bitsPerComponent: 8, bytesPerRow: 0,
        space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
    ) else { fail("cannot create drawing context") }

    let shape = CGPath(roundedRect: shapeRect, cornerWidth: cornerRadius, cornerHeight: cornerRadius, transform: nil)

    context.saveGState()
    context.setShadow(offset: CGSize(width: 0, height: -10), blur: 24, color: CGColor(gray: 0, alpha: 0.35))
    context.addPath(shape)
    context.setFillColor(CGColor(gray: 0, alpha: 1))
    context.fillPath()
    context.restoreGState()

    context.addPath(shape)
    context.clip()
    context.interpolationQuality = .high
    context.draw(artwork, in: aspectFillRect(for: artwork, in: shapeRect))

    guard let icon = context.makeImage() else { fail("cannot render icon") }
    return icon
}

func writePNG(_ image: CGImage, to path: String) {
    let url = URL(fileURLWithPath: path) as CFURL
    guard let destination = CGImageDestinationCreateWithURL(url, UTType.png.identifier as CFString, 1, nil) else {
        fail("cannot write \(path)")
    }
    CGImageDestinationAddImage(destination, image, nil)
    guard CGImageDestinationFinalize(destination) else { fail("cannot write \(path)") }
}

let arguments = CommandLine.arguments
guard arguments.count == 3 else { fail("usage: MakeIcon <artwork.png> <output.png>") }
writePNG(renderIcon(from: loadImage(arguments[1])), to: arguments[2])
