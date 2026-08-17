import CoreGraphics
import Foundation
import Testing
@testable import AiboCore

@Test func outlineSpecksRecolorsIsolatedWhiteOnBlackStroke() throws {
    var pixels = borderedSprite(fill: (red: 200, green: 40, blue: 40), stroke: .black)
    setPixel(&pixels, x: 2, y: 0, color: .white)
    let source = try makeSpeckImage(pixels: pixels, width: 8, height: 8)
    let result = try #require(PixelArtOutlineSpecks.remove(source))
    let speck = try #require(pixelAt(result, x: 2, y: 0))
    #expect(speck.red == 0)
    #expect(speck.green == 0)
    #expect(speck.blue == 0)
    #expect(speck.alpha == 255)
}

@Test func outlineSpecksRecolorsIsolatedWhiteOnColoredStroke() throws {
    var pixels = borderedSprite(fill: (red: 30, green: 30, blue: 180), stroke: .red)
    setPixel(&pixels, x: 3, y: 0, color: .white)
    let source = try makeSpeckImage(pixels: pixels, width: 8, height: 8)
    let result = try #require(PixelArtOutlineSpecks.remove(source))
    let speck = try #require(pixelAt(result, x: 3, y: 0))
    #expect(speck.red == 200)
    #expect(speck.green == 20)
    #expect(speck.blue == 20)
}

@Test func outlineSpecksLeavesInteriorHighlight() throws {
    var pixels = borderedSprite(fill: (red: 200, green: 40, blue: 40), stroke: .black)
    setPixel(&pixels, x: 3, y: 3, color: .white)
    setPixel(&pixels, x: 4, y: 3, color: .white)
    let source = try makeSpeckImage(pixels: pixels, width: 8, height: 8)
    let result = PixelArtOutlineSpecks.remove(source) ?? source
    let eye = try #require(pixelAt(result, x: 3, y: 3))
    #expect(eye.red == 255)
    #expect(eye.green == 255)
    #expect(eye.blue == 255)
}

@Test func outlineSpecksSkipsWhenRingHasNoStroke() throws {
    var pixels = [UInt8](repeating: 0, count: 8 * 8 * 4)
    for y in 1..<7 {
        for x in 1..<7 {
            setPixel(&pixels, x: x, y: y, color: RGBA(red: 90, green: 90, blue: 90, alpha: 255))
        }
    }
    for x in 0..<8 {
        setPixel(&pixels, x: x, y: 0, color: RGBA(red: UInt8(20 + x * 28), green: 80, blue: 40, alpha: 255))
        setPixel(&pixels, x: x, y: 7, color: RGBA(red: 40, green: UInt8(20 + x * 28), blue: 80, alpha: 255))
    }
    for y in 1..<7 {
        setPixel(&pixels, x: 0, y: y, color: RGBA(red: 80, green: 40, blue: UInt8(20 + y * 28), alpha: 255))
        setPixel(&pixels, x: 7, y: y, color: RGBA(red: UInt8(20 + y * 28), green: 40, blue: 80, alpha: 255))
    }
    setPixel(&pixels, x: 2, y: 0, color: .white)
    let source = try makeSpeckImage(pixels: pixels, width: 8, height: 8)
    let result = PixelArtOutlineSpecks.remove(source) ?? source
    let edge = try #require(pixelAt(result, x: 2, y: 0))
    #expect(edge.red == 255)
    #expect(edge.green == 255)
    #expect(edge.blue == 255)
}

@Test func outlineSpecksLeavesLongEdgeHighlight() throws {
    var pixels = borderedSprite(fill: (red: 200, green: 40, blue: 40), stroke: .black)
    setPixel(&pixels, x: 2, y: 0, color: .white)
    setPixel(&pixels, x: 3, y: 0, color: .white)
    setPixel(&pixels, x: 4, y: 0, color: .white)
    let source = try makeSpeckImage(pixels: pixels, width: 8, height: 8)
    let result = PixelArtOutlineSpecks.remove(source) ?? source
    let mid = try #require(pixelAt(result, x: 3, y: 0))
    #expect(mid.red == 255)
    #expect(mid.green == 255)
    #expect(mid.blue == 255)
}

private struct RGBA {
    var red: UInt8
    var green: UInt8
    var blue: UInt8
    var alpha: UInt8

    static let black = RGBA(red: 0, green: 0, blue: 0, alpha: 255)
    static let white = RGBA(red: 255, green: 255, blue: 255, alpha: 255)
    static let red = RGBA(red: 200, green: 20, blue: 20, alpha: 255)
}

private func borderedSprite(fill: (red: UInt8, green: UInt8, blue: UInt8), stroke: RGBA) -> [UInt8] {
    var pixels = [UInt8](repeating: 0, count: 8 * 8 * 4)
    for y in 0..<8 {
        for x in 0..<8 {
            let onBorder = x == 0 || x == 7 || y == 0 || y == 7
            if onBorder {
                setPixel(&pixels, x: x, y: y, color: stroke)
            } else {
                setPixel(
                    &pixels,
                    x: x,
                    y: y,
                    color: RGBA(red: fill.red, green: fill.green, blue: fill.blue, alpha: 255)
                )
            }
        }
    }
    return pixels
}

private func setPixel(_ pixels: inout [UInt8], x: Int, y: Int, color: RGBA) {
    let offset = (y * 8 + x) * 4
    pixels[offset] = color.blue
    pixels[offset + 1] = color.green
    pixels[offset + 2] = color.red
    pixels[offset + 3] = color.alpha
}

private func makeSpeckImage(pixels: [UInt8], width: Int, height: Int) throws -> CGImage {
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
        throw PixelArtSpeckTestError.makeImageFailed
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

private enum PixelArtSpeckTestError: Error {
    case makeImageFailed
}
