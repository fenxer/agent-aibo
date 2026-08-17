import CoreGraphics
import Foundation
import ImageIO
import UniformTypeIdentifiers

public enum PetdexClipConversion: Sendable, Equatable {
    /// Wrote clips and removed the original atlas.
    case converted
    /// Clips were already complete; leftover atlas removed if present.
    case alreadyConverted
    /// Not a Petdex atlas, or slicing failed. Original files are left as-is.
    case unchanged
}

/// Slices a Petdex spritesheet into per-state PNG clips.
///
/// ImageIO can read WebP but cannot write it without extra libraries, so clips
/// are PNG. Conversion failure must not delete the atlas.
public enum PetdexClipSlicer: Sendable {
    /// Converts `directory` if it still has a Petdex atlas and no complete clip pack.
    @discardableResult
    public static func convertIfNeeded(in directory: URL) -> PetdexClipConversion {
        let fileManager = FileManager.default
        if let manifest = AiboSpritePack.loadManifest(in: directory),
           AiboSpritePack.isComplete(manifest, in: directory)
        {
            if manifest.sliceVersion == AiboSpritePackManifest.currentSliceVersion
                || AiboSpritePack.spritesheetURL(in: directory) == nil
            {
                removeSpritesheet(in: directory)
                return .alreadyConverted
            }
        }

        guard let atlasURL = AiboSpritePack.spritesheetURL(in: directory),
              let decoded = loadCGImage(url: atlasURL),
              let atlas = detachedBitmap(decoded),
              let layout = PetdexSpriteLayout(pixelWidth: atlas.width, pixelHeight: atlas.height)
        else { return .unchanged }

        let staging = directory.appendingPathComponent(
            ".staging-clips-\(UUID().uuidString)",
            isDirectory: true
        )
        do {
            try fileManager.createDirectory(at: staging, withIntermediateDirectories: true)
            let stagingClips = AiboSpritePack.clipsDirectory(in: staging)
            try fileManager.createDirectory(at: stagingClips, withIntermediateDirectories: true)

            var clips: [String: AiboSpriteClip] = [:]
            for state in PetdexSpriteState.allCases {
                let frames = visibleFrames(state: state, layout: layout, atlas: atlas)
                guard !frames.isEmpty,
                      let image = stripImage(frames: frames)
                else { continue }
                let relative = AiboSpritePack.clipRelativePath(state: state)
                try writePNG(image, to: staging.appendingPathComponent(relative))
                clips[state.rawValue] = AiboSpriteClip(
                    file: relative,
                    frames: frames.count,
                    durationMilliseconds: state.durationMilliseconds
                )
            }
            guard clips[PetdexSpriteState.idle.rawValue] != nil else {
                try? fileManager.removeItem(at: staging)
                return .unchanged
            }

            var look: [AiboSpriteLookFrame] = []
            if layout.supportsLookDirections {
                var lookImages: [CGImage] = []
                lookImages.reserveCapacity(PetdexLookDirection.count)
                for index in 0..<PetdexLookDirection.count {
                    guard let rect = layout.lookFrameRect(index: index),
                          let frame = croppedFrame(atlas: atlas, rect: rect),
                          !isFullyTransparent(frame)
                    else {
                        lookImages = []
                        break
                    }
                    lookImages.append(frame)
                }
                if lookImages.count == PetdexLookDirection.count {
                    var lookFrames: [AiboSpriteLookFrame] = []
                    lookFrames.reserveCapacity(PetdexLookDirection.count)
                    for (index, frame) in lookImages.enumerated() {
                        let relative = AiboSpritePack.lookRelativePath(index: index)
                        try writePNG(frame, to: staging.appendingPathComponent(relative))
                        lookFrames.append(AiboSpriteLookFrame(index: index, file: relative))
                    }
                    look = lookFrames
                }
            }

            let extendsName = layout.supportsLookDirections ? "petdex-v2" : "petdex-v1"
            let manifest = AiboSpritePackManifest(
                extends: extendsName,
                cellWidth: layout.cellPixelWidth,
                cellHeight: layout.cellPixelHeight,
                clips: clips,
                look: look
            )
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            let manifestData = try encoder.encode(manifest)
            try manifestData.write(
                to: AiboSpritePack.manifestURL(in: staging),
                options: .atomic
            )

            let clipsDest = AiboSpritePack.clipsDirectory(in: directory)
            if fileManager.fileExists(atPath: clipsDest.path) {
                try fileManager.removeItem(at: clipsDest)
            }
            try fileManager.moveItem(at: stagingClips, to: clipsDest)

            let manifestDest = AiboSpritePack.manifestURL(in: directory)
            if fileManager.fileExists(atPath: manifestDest.path) {
                try fileManager.removeItem(at: manifestDest)
            }
            try fileManager.moveItem(
                at: AiboSpritePack.manifestURL(in: staging),
                to: manifestDest
            )
            try? fileManager.removeItem(at: staging)

            guard AiboSpritePack.isComplete(manifest, in: directory) else {
                return .unchanged
            }
            removeSpritesheet(in: directory)
            return .converted
        } catch {
            try? fileManager.removeItem(at: staging)
            return .unchanged
        }
    }

    private static func visibleFrames(
        state: PetdexSpriteState,
        layout: PetdexSpriteLayout,
        atlas: CGImage
    ) -> [CGImage] {
        var frames: [CGImage] = []
        frames.reserveCapacity(state.frameCount)
        for index in 0..<state.frameCount {
            guard let rect = layout.frameRect(state: state, frameIndex: index),
                  let frame = croppedFrame(atlas: atlas, rect: rect)
            else { break }
            if isFullyTransparent(frame) { break }
            frames.append(frame)
        }
        return frames
    }

    private static func croppedFrame(
        atlas: CGImage,
        rect: (x: Int, y: Int, w: Int, h: Int)
    ) -> CGImage? {
        guard let cropped = atlas.cropping(
            to: CGRect(x: rect.x, y: rect.y, width: rect.w, height: rect.h)
        ) else { return nil }
        return detachedBitmap(cropped)
    }

    private static func stripImage(frames: [CGImage]) -> CGImage? {
        guard let first = frames.first else { return nil }
        if frames.count == 1 { return first }
        let cellW = first.width
        let cellH = first.height
        guard let space = CGColorSpace(name: CGColorSpace.sRGB),
              let context = CGContext(
                  data: nil,
                  width: cellW * frames.count,
                  height: cellH,
                  bitsPerComponent: 8,
                  bytesPerRow: 0,
                  space: space,
                  bitmapInfo: CGImageAlphaInfo.premultipliedFirst.rawValue
                      | CGBitmapInfo.byteOrder32Little.rawValue
              )
        else { return nil }
        context.interpolationQuality = .none
        for (index, frame) in frames.enumerated() {
            context.draw(
                frame,
                in: CGRect(x: index * cellW, y: 0, width: cellW, height: cellH)
            )
        }
        return context.makeImage()
    }

    private static func isFullyTransparent(_ image: CGImage) -> Bool {
        guard let bitmap = detachedBitmap(image),
              let provider = bitmap.dataProvider,
              let data = provider.data
        else { return true }
        guard let pointer = CFDataGetBytePtr(data) else { return true }
        let height = bitmap.height
        let width = bitmap.width
        let bytesPerRow = bitmap.bytesPerRow
        for y in 0..<height {
            let row = pointer.advanced(by: y * bytesPerRow)
            for x in 0..<width {
                if row.advanced(by: x * 4 + 3).pointee != 0 { return false }
            }
        }
        return true
    }

    private static func writePNG(_ image: CGImage, to url: URL) throws {
        let directory = url.deletingLastPathComponent()
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let staging = url.appendingPathExtension("writing")
        try? FileManager.default.removeItem(at: staging)
        guard let destination = CGImageDestinationCreateWithURL(
            staging as CFURL,
            UTType.png.identifier as CFString,
            1,
            nil
        ) else {
            throw PetdexInstallError.ioFailed
        }
        CGImageDestinationAddImage(destination, image, nil)
        guard CGImageDestinationFinalize(destination) else {
            try? FileManager.default.removeItem(at: staging)
            throw PetdexInstallError.ioFailed
        }
        if FileManager.default.fileExists(atPath: url.path) {
            try FileManager.default.removeItem(at: url)
        }
        try FileManager.default.moveItem(at: staging, to: url)
    }

    private static func removeSpritesheet(in directory: URL) {
        var seen: Set<String> = []
        while let url = AiboSpritePack.spritesheetURL(in: directory) {
            let path = url.standardizedFileURL.path
            guard seen.insert(path).inserted else { break }
            try? FileManager.default.removeItem(at: url)
        }
    }

    private static func loadCGImage(url: URL) -> CGImage? {
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil) else { return nil }
        return CGImageSourceCreateImageAtIndex(source, 0, nil)
    }

    /// Copies `image` into a BGRA bitmap so crops and alpha scans own their pixels.
    private static func detachedBitmap(_ image: CGImage) -> CGImage? {
        guard let space = CGColorSpace(name: CGColorSpace.sRGB),
              let context = CGContext(
                  data: nil,
                  width: image.width,
                  height: image.height,
                  bitsPerComponent: 8,
                  bytesPerRow: 0,
                  space: space,
                  bitmapInfo: CGImageAlphaInfo.premultipliedFirst.rawValue
                      | CGBitmapInfo.byteOrder32Little.rawValue
              )
        else { return nil }
        context.interpolationQuality = .none
        context.draw(
            image,
            in: CGRect(x: 0, y: 0, width: image.width, height: image.height)
        )
        return context.makeImage()
    }
}
