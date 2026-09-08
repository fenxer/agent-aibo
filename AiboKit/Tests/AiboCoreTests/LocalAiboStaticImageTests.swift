import CoreGraphics
import Foundation
import ImageIO
import Testing
import UniformTypeIdentifiers
@testable import AiboCore

@Test func localAiboImporterCopiesStaticImageWithinPixelCap() throws {
    let directory = FileManager.default.temporaryDirectory
        .appendingPathComponent("aibo-static-\(UUID().uuidString)", isDirectory: true)
    defer { try? FileManager.default.removeItem(at: directory) }
    let source = directory.appendingPathComponent("source.png")
    try writeSolidPNG(width: 48, height: 32, to: source)

    let fileName = try LocalAiboImporter.installCappedStaticImage(
        from: source,
        into: directory,
        id: "small",
        maxPixelDimension: 64
    )
    #expect(fileName == "small.png")
    let installed = directory.appendingPathComponent(fileName)
    let size = try #require(pngPixelSize(installed))
    #expect(size.width == 48)
    #expect(size.height == 32)
}

@Test func localAiboImporterDownsamplesOversizedStaticImage() throws {
    let directory = FileManager.default.temporaryDirectory
        .appendingPathComponent("aibo-static-\(UUID().uuidString)", isDirectory: true)
    defer { try? FileManager.default.removeItem(at: directory) }
    let source = directory.appendingPathComponent("huge.png")
    try writeSolidPNG(width: 200, height: 80, to: source)

    let fileName = try LocalAiboImporter.installCappedStaticImage(
        from: source,
        into: directory,
        id: "huge",
        maxPixelDimension: 64
    )
    #expect(fileName == "huge.png")
    let installed = directory.appendingPathComponent(fileName)
    let size = try #require(pngPixelSize(installed))
    #expect(max(size.width, size.height) == 64)
    #expect(size.width == 64)
    #expect((25...26).contains(size.height))
}

@Test func localAiboImporterRejectsNonImageAsStaticInstall() throws {
    let directory = FileManager.default.temporaryDirectory
        .appendingPathComponent("aibo-static-\(UUID().uuidString)", isDirectory: true)
    defer { try? FileManager.default.removeItem(at: directory) }
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    let source = directory.appendingPathComponent("notes.png")
    try Data("not an image".utf8).write(to: source)

    #expect(throws: LocalAiboImportError.unsupportedFile) {
        try LocalAiboImporter.installCappedStaticImage(
            from: source,
            into: directory,
            id: "bad"
        )
    }
}

private func writeSolidPNG(width: Int, height: Int, to url: URL) throws {
    let directory = url.deletingLastPathComponent()
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
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
          ),
          let image = {
              context.setFillColor(CGColor(srgbRed: 0.2, green: 0.4, blue: 0.8, alpha: 1))
              context.fill(CGRect(x: 0, y: 0, width: width, height: height))
              return context.makeImage()
          }()
    else {
        throw LocalAiboImportError.ioFailed
    }
    guard let destination = CGImageDestinationCreateWithURL(
        url as CFURL,
        UTType.png.identifier as CFString,
        1,
        nil
    ) else {
        throw LocalAiboImportError.ioFailed
    }
    CGImageDestinationAddImage(destination, image, nil)
    guard CGImageDestinationFinalize(destination) else {
        throw LocalAiboImportError.ioFailed
    }
}

private func pngPixelSize(_ url: URL) -> (width: Int, height: Int)? {
    guard let source = CGImageSourceCreateWithURL(url as CFURL, nil),
          let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any]
    else { return nil }
    func intValue(_ key: CFString) -> Int? {
        if let number = properties[key] as? Int { return number }
        if let number = properties[key] as? Double { return Int(number) }
        if let number = properties[key] as? NSNumber { return number.intValue }
        return nil
    }
    guard let width = intValue(kCGImagePropertyPixelWidth),
          let height = intValue(kCGImagePropertyPixelHeight)
    else { return nil }
    return (width, height)
}
