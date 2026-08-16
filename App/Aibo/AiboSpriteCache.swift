import AiboCore
import AppKit
import ImageIO

/// Decodes and caches Petdex spritesheets / static images for the desktop pet.
@MainActor
final class AiboSpriteCache {
    static let shared = AiboSpriteCache()

    private var sheets: [String: CachedSheet] = [:]
    private var staticImages: [String: NSImage] = [:]

    private struct CachedSheet {
        var frames: [PetdexSpriteState: [NSImage]]
        /// Same pixels as `frames`, kept unwrapped for `CALayer.contents`.
        var layerFrames: [PetdexSpriteState: [CGImage]]
        /// V2 rows 9–10; empty when the atlas has no look cells.
        var lookLayerFrames: [CGImage]
        var idlePreview: NSImage
    }

    private init() {}

    func invalidate(except keepID: String? = nil) {
        if let keepID {
            sheets = sheets.filter { $0.key == keepID }
            staticImages = staticImages.filter { $0.key == keepID }
        } else {
            sheets.removeAll()
            staticImages.removeAll()
        }
    }

    func previewImage(for record: AiboLibraryRecord) -> NSImage? {
        switch record.kind {
        case .builtInDefault:
            return NSImage(named: "DefaultAibo")
        case .staticImage:
            return staticImage(for: record)
        case .petdex:
            return sheet(for: record)?.idlePreview
        }
    }

    func frame(
        for record: AiboLibraryRecord,
        state: PetdexSpriteState,
        frameIndex: Int
    ) -> NSImage? {
        guard record.kind == .petdex, let sheet = sheet(for: record) else {
            return previewImage(for: record)
        }
        let frames = sheet.frames[state] ?? sheet.frames[.idle] ?? []
        guard !frames.isEmpty else { return sheet.idlePreview }
        let index = ((frameIndex % frames.count) + frames.count) % frames.count
        return frames[index]
    }

    /// One loop of `state`, ordered, for `CAKeyframeAnimation`. Empty when the
    /// record has no usable atlas — callers fall back to `previewImage(for:)`.
    func layerFrames(
        for record: AiboLibraryRecord,
        state: PetdexSpriteState
    ) -> [CGImage] {
        guard record.kind == .petdex, let sheet = sheet(for: record) else { return [] }
        return sheet.layerFrames[state] ?? sheet.layerFrames[.idle] ?? []
    }

    func supportsLookDirections(for record: AiboLibraryRecord) -> Bool {
        guard record.kind == .petdex, let sheet = sheet(for: record) else { return false }
        return sheet.lookLayerFrames.count == PetdexLookDirection.count
    }

    func lookLayerFrame(for record: AiboLibraryRecord, index: Int) -> CGImage? {
        guard record.kind == .petdex, let sheet = sheet(for: record) else { return nil }
        guard sheet.lookLayerFrames.indices.contains(index) else { return nil }
        return sheet.lookLayerFrames[index]
    }

    private func staticImage(for record: AiboLibraryRecord) -> NSImage? {
        if let cached = staticImages[record.id] { return cached }
        guard let url = AiboLibraryStore.shared.artworkURL(for: record),
              let image = NSImage(contentsOf: url)
        else { return nil }
        staticImages[record.id] = image
        return image
    }

    private func sheet(for record: AiboLibraryRecord) -> CachedSheet? {
        if let cached = sheets[record.id] { return cached }
        guard let url = AiboLibraryStore.shared.artworkURL(for: record),
              let decoded = loadCGImage(url: url),
              let atlas = detachedBitmap(decoded)
        else { return nil }

        let width = atlas.width
        let height = atlas.height

        guard let layout = PetdexSpriteLayout(pixelWidth: width, pixelHeight: height) else {
            let whole = NSImage(cgImage: atlas, size: NSSize(width: width, height: height))
            let cached = CachedSheet(
                frames: [.idle: [whole]],
                layerFrames: [.idle: [atlas]],
                lookLayerFrames: [],
                idlePreview: whole
            )
            sheets[record.id] = cached
            return cached
        }

        var frames: [PetdexSpriteState: [NSImage]] = [:]
        var layerFrames: [PetdexSpriteState: [CGImage]] = [:]
        for state in PetdexSpriteState.allCases {
            var images: [NSImage] = []
            var cgImages: [CGImage] = []
            images.reserveCapacity(state.frameCount)
            cgImages.reserveCapacity(state.frameCount)
            for index in 0..<state.frameCount {
                guard let rect = layout.frameRect(state: state, frameIndex: index),
                      let cropped = atlas.cropping(
                          to: CGRect(x: rect.x, y: rect.y, width: rect.w, height: rect.h)
                      ),
                      let frame = detachedBitmap(cropped)
                else { continue }
                cgImages.append(frame)
                images.append(
                    NSImage(
                        cgImage: frame,
                        size: NSSize(width: rect.w, height: rect.h)
                    )
                )
            }
            if !images.isEmpty {
                frames[state] = images
                layerFrames[state] = cgImages
            }
        }

        var lookLayerFrames: [CGImage] = []
        if layout.supportsLookDirections {
            lookLayerFrames.reserveCapacity(PetdexLookDirection.count)
            for index in 0..<PetdexLookDirection.count {
                guard let rect = layout.lookFrameRect(index: index),
                      let cropped = atlas.cropping(
                          to: CGRect(x: rect.x, y: rect.y, width: rect.w, height: rect.h)
                      ),
                      let frame = detachedBitmap(cropped)
                else { continue }
                lookLayerFrames.append(frame)
            }
            if lookLayerFrames.count != PetdexLookDirection.count {
                lookLayerFrames = []
            }
        }

        let idlePreview = frames[.idle]?.first
            ?? NSImage(cgImage: atlas, size: NSSize(width: width, height: height))
        let cached = CachedSheet(
            frames: frames,
            layerFrames: layerFrames,
            lookLayerFrames: lookLayerFrames,
            idlePreview: idlePreview
        )
        sheets[record.id] = cached
        return cached
    }

    private func loadCGImage(url: URL) -> CGImage? {
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil) else { return nil }
        return CGImageSourceCreateImageAtIndex(source, 0, nil)
    }

    /// Copies `image` into a freshly allocated bitmap.
    ///
    /// `CGImage.cropping(to:)` does not copy pixels: every frame stays attached to
    /// the lazily decoded atlas, and ImageIO then decodes the whole spritesheet
    /// again — and keeps that buffer alive — once per frame that gets drawn. For a
    /// 1536×1872 atlas that is 11 MB per frame instead of 156 KB.
    ///
    /// Uses BGRA (premultiplied first, little endian), the layout CoreAnimation
    /// uploads without conversion.
    private func detachedBitmap(_ image: CGImage) -> CGImage? {
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
