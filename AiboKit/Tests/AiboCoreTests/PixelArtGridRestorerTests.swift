import CoreGraphics
import Foundation
import Testing
@testable import AiboCore

@Test func pixelArtGridRestorerRecoversNearestUpscaledTexels() throws {
    let original = makeIndexedPixels(width: 12, height: 13)
    let source = try makeBGRAImage(pixels: original, width: 12, height: 13)
    let upscaled = try nearestScale(source, factor: 4)
    #expect(upscaled.width == 48)
    #expect(upscaled.height == 52)

    let restored = try #require(PixelArtGridRestorer.restore(upscaled))
    #expect(restored.width == 12)
    #expect(restored.height == 13)
    let restoredOrigin = try #require(pixel00(restored))
    let sourceOrigin = try #require(pixel00(source))
    #expect(restoredOrigin.red == sourceOrigin.red)
    #expect(restoredOrigin.green == sourceOrigin.green)
    #expect(restoredOrigin.blue == sourceOrigin.blue)
    #expect(restoredOrigin.alpha == sourceOrigin.alpha)
}

@Test func pixelArtGridRestorerSkipsAlreadyOneToOneArt() throws {
    let source = try makeBGRAImage(pixels: makeIndexedPixels(width: 24, height: 26), width: 24, height: 26)
    #expect(PixelArtGridRestorer.restore(source) == nil)
}

@Test func pixelArtGridRestorerSkipsSmoothGradient() throws {
    var pixels = [UInt8](repeating: 0, count: 64 * 64 * 4)
    for y in 0..<64 {
        for x in 0..<64 {
            let offset = (y * 64 + x) * 4
            pixels[offset] = UInt8(x * 4)
            pixels[offset + 1] = UInt8(y * 4)
            pixels[offset + 2] = 80
            pixels[offset + 3] = 255
        }
    }
    let image = try makeBGRAImage(pixels: pixels, width: 64, height: 64)
    #expect(PixelArtGridRestorer.restore(image) == nil)
}

@Test func pixelArtScaleFillWidthIsOneToOneAtDefaultPetdexSize() {
    let layout = PixelArtScale.fillWidth(
        sourceWidth: 192,
        sourceHeight: 208,
        targetWidth: 96,
        backingScale: 2
    )
    #expect(layout.width == 96)
    #expect(layout.height == 104)
    #expect(layout.integerScale == 1)
}

@Test func pixelArtScaleFillWidthUsesIntegerScaleAfterGridRestore() {
    let layout = PixelArtScale.fillWidth(
        sourceWidth: 48,
        sourceHeight: 52,
        targetWidth: 96,
        backingScale: 2
    )
    #expect(layout.width == 96)
    #expect(layout.height == 104)
    #expect(layout.integerScale == 4)
}

@Test func pixelArtScaleDistinctPercentsDrop150WhenItMatches200() {
    let percents = PixelArtScale.distinctFillWidthPercents(
        sourceWidth: 192,
        sourceHeight: 208,
        backingScale: 2,
        baseSize: 96,
        candidates: [50, 100, 150, 200, 250, 300]
    )
    #expect(percents == [50, 100, 200, 300])
}

@Test func pixelArtScaleDistinctPercentsKeep150AfterGridRestore() {
    let percents = PixelArtScale.distinctFillWidthPercents(
        sourceWidth: 96,
        sourceHeight: 104,
        backingScale: 2,
        baseSize: 96,
        candidates: [50, 100, 150, 200, 250, 300]
    )
    #expect(percents == [50, 100, 150, 200, 250, 300])
}

@Test func pixelArtScaleFillWidthSnapsHalfScale() {
    let layout = PixelArtScale.fillWidth(
        sourceWidth: 192,
        sourceHeight: 208,
        targetWidth: 48,
        backingScale: 2
    )
    #expect(layout.width == 48)
    #expect(layout.height == 52)
    #expect(layout.integerScale == -2)
}

@Test func pixelArtScaleFitStaysInsidePreviewBox() {
    let layout = PixelArtScale.fit(
        sourceWidth: 192,
        sourceHeight: 208,
        targetWidth: 48,
        targetHeight: 48,
        backingScale: 2
    )
    #expect(layout.width <= 48)
    #expect(layout.height <= 48)
    #expect(layout.width > 0)
    #expect(layout.height > 0)
}

private func makeIndexedPixels(width: Int, height: Int) -> [UInt8] {
    var pixels = [UInt8](repeating: 0, count: width * height * 4)
    for y in 0..<height {
        for x in 0..<width {
            let offset = (y * width + x) * 4
            pixels[offset] = UInt8(20 + (x * 9) % 180)
            pixels[offset + 1] = UInt8(40 + (y * 7) % 160)
            pixels[offset + 2] = UInt8(80 + ((x + y) * 5) % 120)
            pixels[offset + 3] = 255
        }
    }
    return pixels
}

private func nearestScale(_ image: CGImage, factor: Int) throws -> CGImage {
    let width = image.width * factor
    let height = image.height * factor
    guard let space = CGColorSpace(name: CGColorSpace.sRGB),
          let context = CGContext(
              data: nil,
              width: width,
              height: height,
              bitsPerComponent: 8,
              bytesPerRow: 0,
              space: space,
              bitmapInfo: CGImageAlphaInfo.premultipliedFirst.rawValue
                  | CGBitmapInfo.byteOrder32Little.rawValue
          )
    else {
        throw PixelArtTestError.makeImageFailed
    }
    context.interpolationQuality = .none
    context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
    guard let scaled = context.makeImage() else { throw PixelArtTestError.makeImageFailed }
    return scaled
}

private func makeBGRAImage(pixels: [UInt8], width: Int, height: Int) throws -> CGImage {
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
        throw PixelArtTestError.makeImageFailed
    }
    return image
}

private func pixel00(_ image: CGImage) -> (red: UInt8, green: UInt8, blue: UInt8, alpha: UInt8)? {
    guard let cropped = image.cropping(to: CGRect(x: 0, y: 0, width: 1, height: 1)),
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

private enum PixelArtTestError: Error {
    case makeImageFailed
}
