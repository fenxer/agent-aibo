import CoreGraphics
import Foundation
import ImageIO
import Testing
import UniformTypeIdentifiers
@testable import AiboCore

@Test func aiboSpritePackManifestRoundTrips() throws {
    let manifest = AiboSpritePackManifest(
        extends: "petdex-v2",
        cellWidth: 192,
        cellHeight: 208,
        clips: [
            "idle": AiboSpriteClip(file: "clips/idle.png", frames: 6, durationMilliseconds: 1100),
        ],
        look: [AiboSpriteLookFrame(index: 0, file: "clips/look-00.png")]
    )
    let data = try JSONEncoder().encode(manifest)
    let decoded = try JSONDecoder().decode(AiboSpritePackManifest.self, from: data)
    #expect(decoded == manifest)
}

@Test func bundledDefaultAiboPackOnDiskIsComplete() throws {
    let pack = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent()
        .deletingLastPathComponent()
        .deletingLastPathComponent()
        .deletingLastPathComponent()
        .appendingPathComponent("App/Aibo/default-aibo", isDirectory: true)
    #expect(FileManager.default.fileExists(atPath: pack.path))
    let manifest = try #require(AiboSpritePack.loadManifest(in: pack))
    #expect(AiboSpritePack.isComplete(manifest, in: pack))
    #expect(manifest.extends == "petdex-v2")
    #expect(manifest.cellWidth == 192)
    #expect(manifest.cellHeight == 208)
    #expect(manifest.look.count == PetdexLookDirection.count)
    #expect(manifest.clips["idle"]?.frames == 6)
    #expect(manifest.clips["idle"]?.file == "clips/idle.png")
}

@Test func aiboSpritePackBuiltInDirectoryIsNotApplicationSupport() {
    if let bundled = AiboSpritePack.directory(for: .builtInDefault) {
        #expect(bundled.standardizedFileURL != AiboPaths.aibosDirectory.standardizedFileURL)
        #expect(AiboSpritePack.loadManifest(in: bundled) != nil)
    }
}

@Test func aiboSpritePackRejectsPathTraversal() {
    let directory = FileManager.default.temporaryDirectory
        .appendingPathComponent("aibo-pack-path-\(UUID().uuidString)", isDirectory: true)
    defer { try? FileManager.default.removeItem(at: directory) }
    try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    #expect(AiboSpritePack.resolveExistingFile(named: "../outside.png", in: directory) == nil)
    #expect(AiboSpritePack.resolveExistingFile(named: "/etc/passwd", in: directory) == nil)
}

@Test func aiboSpritePackManifestDecodeDefaultsMissingLook() throws {
    let json = """
    {"format":"aibo","formatVersion":1,"sliceVersion":1,"cellWidth":192,"cellHeight":208,"clips":{"idle":{"file":"clips/idle.png","frames":1}}}
    """
    let decoded = try JSONDecoder().decode(AiboSpritePackManifest.self, from: Data(json.utf8))
    #expect(decoded.look.isEmpty)
    #expect(decoded.clips["idle"]?.frames == 1)
}

@Test func petdexClipSlicerLeavesInvalidAtlasUnchanged() throws {
    let directory = FileManager.default.temporaryDirectory
        .appendingPathComponent("aibo-slice-stub-\(UUID().uuidString)", isDirectory: true)
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: directory) }

    try Data(#"{"id":"stub","spritesheetPath":"spritesheet.webp"}"#.utf8)
        .write(to: directory.appendingPathComponent("pet.json"))
    try Data([0x52, 0x49, 0x46, 0x46]).write(to: directory.appendingPathComponent("spritesheet.webp"))

    #expect(PetdexClipSlicer.convertIfNeeded(in: directory) == .unchanged)
    #expect(
        FileManager.default.fileExists(
            atPath: directory.appendingPathComponent("spritesheet.webp").path
        )
    )
    #expect(
        FileManager.default.fileExists(
            atPath: directory.appendingPathComponent("aibo.json").path
        ) == false
    )
}

@Test func petdexClipSlicerWritesClipsAndDeletesAtlas() throws {
    let directory = FileManager.default.temporaryDirectory
        .appendingPathComponent("aibo-slice-v1-\(UUID().uuidString)", isDirectory: true)
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: directory) }

    try Data(#"{"id":"slicer","spriteVersionNumber":1,"spritesheetPath":"spritesheet.png"}"#.utf8)
        .write(to: directory.appendingPathComponent("pet.json"))
    try writeAtlasPNG(
        to: directory.appendingPathComponent("spritesheet.png"),
        rows: PetdexSpriteLayout.v1Rows,
        empty: [Cell(row: PetdexSpriteState.waving.row, column: 3)]
    )

    #expect(PetdexClipSlicer.convertIfNeeded(in: directory) == .converted)
    #expect(
        FileManager.default.fileExists(
            atPath: directory.appendingPathComponent("spritesheet.png").path
        ) == false
    )

    let manifest = AiboSpritePack.loadManifest(in: directory)
    #expect(manifest?.extends == "petdex-v1")
    #expect(manifest?.look.isEmpty == true)
    #expect(AiboSpritePack.isComplete(manifest!, in: directory))
    #expect(manifest?.clips["idle"]?.frames == 6)
    #expect(manifest?.clips["waving"]?.frames == 3)

    let idleURL = AiboSpritePack.resolveExistingFile(named: "clips/idle.png", in: directory)
    let idle = loadCGImage(url: idleURL!)
    #expect(idle?.width == PetdexSpriteLayout.cellWidth * 6)
    #expect(idle?.height == PetdexSpriteLayout.cellHeight)
    #expect(pixel00(idle!)! == (red: 20, green: 20, blue: 128, alpha: 255))

    let wavingURL = AiboSpritePack.resolveExistingFile(named: "clips/waving.png", in: directory)
    let waving = loadCGImage(url: wavingURL!)
    #expect(waving?.width == PetdexSpriteLayout.cellWidth * 3)

    #expect(PetdexClipSlicer.convertIfNeeded(in: directory) == .alreadyConverted)
}

private struct Cell: Hashable {
    var row: Int
    var column: Int
}

private func writeAtlasPNG(to url: URL, rows: Int, empty: Set<Cell>) throws {
    let cellW = PetdexSpriteLayout.cellWidth
    let cellH = PetdexSpriteLayout.cellHeight
    let columns = PetdexSpriteLayout.columns
    let width = columns * cellW
    let height = rows * cellH
    var pixels = [UInt8](repeating: 0, count: width * height * 4)
    for row in 0..<rows {
        for column in 0..<columns {
            if empty.contains(Cell(row: row, column: column)) { continue }
            let originX = column * cellW
            let originY = row * cellH
            let offset = (originY * width + originX) * 4
            pixels[offset] = 128
            pixels[offset + 1] = UInt8(20 + column)
            pixels[offset + 2] = UInt8(20 + row)
            pixels[offset + 3] = 255
        }
    }

    let image = try makeBGRAImage(pixels: pixels, width: width, height: height)
    guard let destination = CGImageDestinationCreateWithURL(
        url as CFURL,
        UTType.png.identifier as CFString,
        1,
        nil
    ) else {
        throw PetdexInstallError.ioFailed
    }
    CGImageDestinationAddImage(destination, image, nil)
    guard CGImageDestinationFinalize(destination) else {
        throw PetdexInstallError.ioFailed
    }
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
        throw PetdexInstallError.ioFailed
    }
    return image
}

private func loadCGImage(url: URL) -> CGImage? {
    guard let source = CGImageSourceCreateWithURL(url as CFURL, nil) else { return nil }
    return CGImageSourceCreateImageAtIndex(source, 0, nil)
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
