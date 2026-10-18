import CoreGraphics
import Foundation
import ImageIO
import UniformTypeIdentifiers

/// Shrinks a capture to a size vision models handle well and encodes it as JPEG.
public enum ImageEncoder {
    public static let defaultMaxLongSide = 1600
    static let jpegQuality = 0.9

    public static func scaledSize(width: Int, height: Int, maxLongSide: Int) -> CGSize {
        let longSide = max(width, height)
        guard longSide > maxLongSide else { return CGSize(width: width, height: height) }
        let scale = Double(maxLongSide) / Double(longSide)
        return CGSize(width: Int((Double(width) * scale).rounded(.down)), height: Int((Double(height) * scale).rounded(.down)))
    }

    public static func encodeJPEGBase64(_ image: CGImage, maxLongSide: Int = defaultMaxLongSide) throws -> String {
        let resized = try resize(image, maxLongSide: maxLongSide)
        let data = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(data, UTType.jpeg.identifier as CFString, 1, nil) else {
            throw ChatError.capture("Could not encode screenshot")
        }
        CGImageDestinationAddImage(destination, resized, [kCGImageDestinationLossyCompressionQuality: jpegQuality] as CFDictionary)
        guard CGImageDestinationFinalize(destination) else { throw ChatError.capture("Could not encode screenshot") }
        return (data as Data).base64EncodedString()
    }

    private static func resize(_ image: CGImage, maxLongSide: Int) throws -> CGImage {
        let size = scaledSize(width: image.width, height: image.height, maxLongSide: maxLongSide)
        guard Int(size.width) != image.width || Int(size.height) != image.height else { return image }

        guard let context = CGContext(
            data: nil, width: Int(size.width), height: Int(size.height), bitsPerComponent: 8, bytesPerRow: 0,
            space: CGColorSpace(name: CGColorSpace.sRGB) ?? CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue
        ) else { throw ChatError.capture("Could not resize screenshot") }

        context.interpolationQuality = .high
        context.draw(image, in: CGRect(origin: .zero, size: size))
        guard let resized = context.makeImage() else { throw ChatError.capture("Could not resize screenshot") }
        return resized
    }
}
