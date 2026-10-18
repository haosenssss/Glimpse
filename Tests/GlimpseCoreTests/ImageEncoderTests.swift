import CoreGraphics
import Foundation
import ImageIO
import Testing
@testable import GlimpseCore

@Suite struct ImageEncoderTests {
    func makeImage(width: Int, height: Int) throws -> CGImage {
        let context = try #require(CGContext(
            data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
            space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ))
        context.setFillColor(CGColor(red: 1, green: 0.5, blue: 0, alpha: 1))
        context.fill(CGRect(x: 0, y: 0, width: width, height: height))
        return try #require(context.makeImage())
    }

    @Test func scalesDownLongSide() {
        #expect(ImageEncoder.scaledSize(width: 3200, height: 1000, maxLongSide: 1600) == CGSize(width: 1600, height: 500))
        #expect(ImageEncoder.scaledSize(width: 800, height: 2400, maxLongSide: 1600) == CGSize(width: 533, height: 1600))
    }

    @Test func keepsSmallImagesUnchanged() {
        #expect(ImageEncoder.scaledSize(width: 640, height: 480, maxLongSide: 1600) == CGSize(width: 640, height: 480))
    }

    @Test func encodesJPEGWithinSizeLimit() throws {
        let image = try makeImage(width: 3000, height: 1000)
        let base64 = try ImageEncoder.encodeJPEGBase64(image, maxLongSide: 1600)
        let data = try #require(Data(base64Encoded: base64))

        #expect(data.prefix(2) == Data([0xFF, 0xD8]))
        let source = try #require(CGImageSourceCreateWithData(data as CFData, nil))
        let decoded = try #require(CGImageSourceCreateImageAtIndex(source, 0, nil))
        #expect(decoded.width == 1600)
        #expect(decoded.height == 533)
    }
}
