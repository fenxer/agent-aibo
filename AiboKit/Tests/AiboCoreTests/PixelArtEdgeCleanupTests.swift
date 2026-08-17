import CoreGraphics
import Foundation
import Testing
@testable import AiboCore

@Test func pixelArtEdgeCleanupSnapsFogToClear() throws {
    var pixels = [UInt8](repeating: 0, count: 2 * 2 * 4)
    // Premultiplied gray fog (alpha 40).
    pixels[0] = 20
    pixels[1] = 20
    pixels[2] = 20
    pixels[3] = 40
    pixels[4] = 80
    pixels[5] = 40
    pixels[6] = 200
    pixels[7] = 255

    let source = try makeCleanupImage(pixels: pixels, width: 2, height: 2)
    let cleaned = try #require(PixelArtEdgeCleanup.clean(source))
    let fog = try #require(pixelAt(cleaned, x: 0, y: 0))
    #expect(fog.alpha == 0)
    #expect(fog.red == 0)
    #expect(fog.green == 0)
    #expect(fog.blue == 0)

    let solid = try #require(pixelAt(cleaned, x: 1, y: 0))
    #expect(solid.alpha == 255)
    #expect(solid.red == 200)
    #expect(solid.green == 40)
    #expect(solid.blue == 80)
}

@Test func pixelArtEdgeCleanupUnpremultipliesNearOpaqueFringe() throws {
    var pixels = [UInt8](repeating: 0, count: 4)
    // Premultiplied red at alpha 200 → RGB 200 after unpremultiply.
    pixels[0] = 0
    pixels[1] = 0
    pixels[2] = 157
    pixels[3] = 200

    let source = try makeCleanupImage(pixels: pixels, width: 1, height: 1)
    let cleaned = try #require(PixelArtEdgeCleanup.clean(source))
    let pixel = try #require(pixelAt(cleaned, x: 0, y: 0))
    #expect(pixel.alpha == 255)
    #expect(pixel.red >= 198)
    #expect(pixel.red <= 202)
    #expect(pixel.green == 0)
    #expect(pixel.blue == 0)
}

private func makeCleanupImage(pixels: [UInt8], width: Int, height: Int) throws -> CGImage {
    let data = pixels.withUnsafeBytes { buffer in
        Data(buffer.bindMemory(to: UInt8.self))
    } as CFData
    guard let provider = CGDataProvider(data: data),
          let space = CGColorSpace(name: CGColorSpace.sRGB),
          let image = CGImage(
              width: width,
              height: height,
              bitsPerComponent: 8,
              bitsPerPixel: 32,
              bytesPerRow: width * 4,
              space: space,
              bitmapInfo: CGBitmapInfo(
                  rawValue: CGImageAlphaInfo.premultipliedFirst.rawValue
                      | CGBitmapInfo.byteOrder32Little.rawValue
              ),
              provider: provider,
              decode: nil,
              shouldInterpolate: false,
              intent: .defaultIntent
          )
    else {
        throw PixelArtCleanupTestError.makeImageFailed
    }
    return image
}

private func pixelAt(
    _ image: CGImage,
    x: Int,
    y: Int
) -> (red: UInt8, green: UInt8, blue: UInt8, alpha: UInt8)? {
    guard let cropped = image.cropping(to: CGRect(x: x, y: y, width: 1, height: 1)),
          let space = CGColorSpace(name: CGColorSpace.sRGB),
          let context = CGContext(
              data: nil,
              width: 1,
              height: 1,
              bitsPerComponent: 8,
              bytesPerRow: 4,
              space: space,
              bitmapInfo: CGImageAlphaInfo.premultipliedFirst.rawValue
                  | CGBitmapInfo.byteOrder32Little.rawValue
          )
    else { return nil }
    context.interpolationQuality = .none
    context.draw(cropped, in: CGRect(x: 0, y: 0, width: 1, height: 1))
    guard let data = context.data else { return nil }
    let bytes = data.bindMemory(to: UInt8.self, capacity: 4)
    return (red: bytes[2], green: bytes[1], blue: bytes[0], alpha: bytes[3])
}

private enum PixelArtCleanupTestError: Error {
    case makeImageFailed
}
