import AiboCore
import AppKit
import ImageIO

/// Decodes Petdex / Aibo clip frames on demand for the desktop pet.
@MainActor
final class AiboSpriteCache {
    static let shared = AiboSpriteCache()

    private var pets: [String: CachedPet] = [:]
    private var staticImages: [String: NSImage] = [:]

    private struct CachedPet {
        var directory: URL
        var manifest: AiboSpritePackManifest?
        var atlasURL: URL?
        var lookSupported: Bool
        var preview: NSImage
        var framesByState: [PetdexSpriteState: [CGImage]] = [:]
        var lookByIndex: [Int: CGImage] = [:]
        var gridRestore: GridRestore = .pending
    }

    private enum GridRestore: Equatable {
        case pending
        case skipped
        case texel(Int)
    }

    private init() {}

    func invalidate(except keepID: String? = nil) {
        invalidate(keeping: keepID.map { [$0] } ?? [])
    }

    func invalidate(keeping keepIDs: Set<String>) {
        if keepIDs.isEmpty {
            pets.removeAll()
            staticImages.removeAll()
        } else {
            pets = pets.filter { keepIDs.contains($0.key) }
            staticImages = staticImages.filter { keepIDs.contains($0.key) }
        }
    }

    func invalidateRecord(_ id: String) {
        pets[id] = nil
        staticImages[id] = nil
    }

    func previewImage(for record: AiboLibraryRecord) -> NSImage? {
        switch record.kind {
        case .builtInDefault:
            return pet(for: record)?.preview
        case .staticImage:
            return staticImage(for: record)
        case .petdex:
            return pet(for: record)?.preview
        }
    }

    /// Pixel size of the artwork that will be drawn (after optional grid restore).
    func sourcePixelSize(for record: AiboLibraryRecord) -> (width: Int, height: Int)? {
        guard record.kind != .builtInDefault,
              let image = previewImage(for: record),
              let cgImage = image.cgImage(forProposedRect: nil, context: nil, hints: nil),
              cgImage.width > 0, cgImage.height > 0
        else { return nil }
        return (cgImage.width, cgImage.height)
    }

    func frame(
        for record: AiboLibraryRecord,
        state: PetdexSpriteState,
        frameIndex: Int
    ) -> NSImage? {
        guard playsClips(record) else {
            return previewImage(for: record)
        }
        let frames = layerFrames(for: record, state: state)
        guard !frames.isEmpty else { return previewImage(for: record) }
        let index = ((frameIndex % frames.count) + frames.count) % frames.count
        let image = frames[index]
        return NSImage(
            cgImage: image,
            size: NSSize(width: image.width, height: image.height)
        )
    }

    /// One loop of `state`, ordered, for `CAKeyframeAnimation`. Empty when the
    /// record has no usable artwork — callers fall back to `previewImage(for:)`.
    func layerFrames(
        for record: AiboLibraryRecord,
        state: PetdexSpriteState
    ) -> [CGImage] {
        guard playsClips(record), var pet = pet(for: record) else { return [] }
        if let cached = pet.framesByState[state], !cached.isEmpty {
            return cached
        }
        let loaded = restoreFrames(
            loadStateFrames(state, pet: pet),
            pet: &pet,
            pixelOptimizationEnabled: record.pixelOptimizationEnabled
        )
        let frames = loaded.isEmpty
            ? restoreFrames(
                loadStateFrames(.idle, pet: pet),
                pet: &pet,
                pixelOptimizationEnabled: record.pixelOptimizationEnabled
            )
            : loaded
        guard !frames.isEmpty else { return [] }
        pet.framesByState[state] = frames
        if loaded.isEmpty, state != .idle {
            pet.framesByState[.idle] = frames
        }
        evictUnusedStates(in: &pet, keeping: [state, .idle])
        pets[record.id] = pet
        return frames
    }

    func supportsLookDirections(for record: AiboLibraryRecord) -> Bool {
        guard playsClips(record) else { return false }
        return pet(for: record)?.lookSupported == true
    }

    func lookLayerFrame(for record: AiboLibraryRecord, index: Int) -> CGImage? {
        guard playsClips(record), var pet = pet(for: record), pet.lookSupported else {
            return nil
        }
        if let cached = pet.lookByIndex[index] {
            if pet.lookByIndex.count > 1 {
                pet.lookByIndex = [index: cached]
                pets[record.id] = pet
            }
            return cached
        }
        guard let raw = loadLookFrame(index, pet: pet) else { return nil }
        let frame = restoreFrames(
            [raw],
            pet: &pet,
            pixelOptimizationEnabled: record.pixelOptimizationEnabled
        ).first ?? raw
        pet.lookByIndex = [index: frame]
        pets[record.id] = pet
        return frame
    }

    private func staticImage(for record: AiboLibraryRecord) -> NSImage? {
        if let cached = staticImages[record.id] { return cached }
        guard let url = AiboLibraryStore.shared.artworkURL(for: record),
              var image = NSImage(contentsOf: url)
        else { return nil }
        if record.pixelOptimizationEnabled,
           let cgImage = image.cgImage(forProposedRect: nil, context: nil, hints: nil)
        {
            let restored = PixelArtGridRestorer.restore(cgImage) ?? cgImage
            let refined = refinePixelArt(restored)
            image = NSImage(
                cgImage: refined,
                size: NSSize(width: refined.width, height: refined.height)
            )
        }
        staticImages[record.id] = image
        return image
    }

    private func playsClips(_ record: AiboLibraryRecord) -> Bool {
        record.kind == .petdex || record.kind == .builtInDefault
    }

    private func pet(for record: AiboLibraryRecord) -> CachedPet? {
        if let cached = pets[record.id] { return cached }
        guard let directory = AiboSpritePack.directory(for: record) else { return nil }

        if let manifest = AiboSpritePack.loadManifest(in: directory),
           AiboSpritePack.isComplete(manifest, in: directory)
        {
            let cached = loadConvertedPet(
                directory: directory,
                manifest: manifest,
                pixelOptimizationEnabled: record.pixelOptimizationEnabled
            )
            pets[record.id] = cached
            return cached
        }

        guard record.kind != .builtInDefault,
              let atlasURL = AiboSpritePack.spritesheetURL(
                  in: directory,
                  preferredFileName: record.spriteFileName
              )
        else { return nil }
        let cached = loadUnconvertedPreview(
            directory: directory,
            atlasURL: atlasURL,
            pixelOptimizationEnabled: record.pixelOptimizationEnabled
        )
        pets[record.id] = cached
        return cached
    }

    private func loadConvertedPet(
        directory: URL,
        manifest: AiboSpritePackManifest,
        pixelOptimizationEnabled: Bool
    ) -> CachedPet {
        var cached = CachedPet(
            directory: directory,
            manifest: manifest,
            atlasURL: nil,
            lookSupported: manifest.look.count == PetdexLookDirection.count,
            preview: NSImage(size: .zero)
        )
        let idleFrames = restoreFrames(
            loadClipFrames(manifest: manifest, directory: directory, state: .idle),
            pet: &cached,
            pixelOptimizationEnabled: pixelOptimizationEnabled
        )
        if let previewSource = idleFrames.first {
            cached.preview = NSImage(
                cgImage: previewSource,
                size: NSSize(width: previewSource.width, height: previewSource.height)
            )
        }
        if !idleFrames.isEmpty {
            cached.framesByState[.idle] = idleFrames
        }
        return cached
    }

    private func loadUnconvertedPreview(
        directory: URL,
        atlasURL: URL,
        pixelOptimizationEnabled: Bool
    ) -> CachedPet {
        guard let decoded = loadCGImage(url: atlasURL),
              let atlas = detachedBitmap(decoded)
        else {
            return CachedPet(
                directory: directory,
                manifest: nil,
                atlasURL: atlasURL,
                lookSupported: false,
                preview: NSImage(size: .zero)
            )
        }

        let width = atlas.width
        let height = atlas.height
        guard let layout = PetdexSpriteLayout(pixelWidth: width, pixelHeight: height),
              let rect = layout.frameRect(state: .idle, frameIndex: 0),
              let cropped = atlas.cropping(
                  to: CGRect(x: rect.x, y: rect.y, width: rect.w, height: rect.h)
              ),
              let idle = detachedBitmap(cropped)
        else {
            let whole = NSImage(cgImage: atlas, size: NSSize(width: width, height: height))
            return CachedPet(
                directory: directory,
                manifest: nil,
                atlasURL: atlasURL,
                lookSupported: false,
                preview: whole,
                framesByState: [.idle: [atlas]]
            )
        }

        var cached = CachedPet(
            directory: directory,
            manifest: nil,
            atlasURL: atlasURL,
            lookSupported: layout.supportsLookDirections,
            preview: NSImage(size: .zero)
        )
        let restoredIdle = restoreFrames(
            [idle],
            pet: &cached,
            pixelOptimizationEnabled: pixelOptimizationEnabled
        )
        let previewSource = restoredIdle.first ?? idle
        cached.preview = NSImage(
            cgImage: previewSource,
            size: NSSize(width: previewSource.width, height: previewSource.height)
        )
        return cached
    }

    private func loadStateFrames(_ state: PetdexSpriteState, pet: CachedPet) -> [CGImage] {
        if let manifest = pet.manifest {
            return loadClipFrames(manifest: manifest, directory: pet.directory, state: state)
        }
        guard let atlasURL = pet.atlasURL else { return [] }
        return loadAtlasStateFrames(state, atlasURL: atlasURL)
    }

    private func loadLookFrame(_ index: Int, pet: CachedPet) -> CGImage? {
        if let manifest = pet.manifest {
            guard let entry = manifest.look.first(where: { $0.index == index }),
                  let url = AiboSpritePack.resolveExistingFile(named: entry.file, in: pet.directory),
                  let decoded = loadCGImage(url: url)
            else { return nil }
            return detachedBitmap(decoded)
        }
        guard let atlasURL = pet.atlasURL,
              let decoded = loadCGImage(url: atlasURL),
              let atlas = detachedBitmap(decoded),
              let layout = PetdexSpriteLayout(pixelWidth: atlas.width, pixelHeight: atlas.height),
              let rect = layout.lookFrameRect(index: index),
              let cropped = atlas.cropping(
                  to: CGRect(x: rect.x, y: rect.y, width: rect.w, height: rect.h)
              )
        else { return nil }
        return detachedBitmap(cropped)
    }

    private func loadClipFrames(
        manifest: AiboSpritePackManifest,
        directory: URL,
        state: PetdexSpriteState
    ) -> [CGImage] {
        guard let clip = manifest.clips[state.rawValue],
              let url = AiboSpritePack.resolveExistingFile(named: clip.file, in: directory),
              let decoded = loadCGImage(url: url),
              let image = detachedBitmap(decoded)
        else { return [] }
        let frames = max(clip.frames, 1)
        if frames == 1 { return [image] }
        let cellW = manifest.cellWidth
        let cellH = manifest.cellHeight
        var result: [CGImage] = []
        result.reserveCapacity(frames)
        for index in 0..<frames {
            let rect = CGRect(x: index * cellW, y: 0, width: cellW, height: cellH)
            guard let cropped = image.cropping(to: rect),
                  let copy = detachedBitmap(cropped)
            else { continue }
            result.append(copy)
        }
        return result
    }

    private func loadAtlasStateFrames(_ state: PetdexSpriteState, atlasURL: URL) -> [CGImage] {
        guard let decoded = loadCGImage(url: atlasURL),
              let atlas = detachedBitmap(decoded),
              let layout = PetdexSpriteLayout(pixelWidth: atlas.width, pixelHeight: atlas.height)
        else { return [] }
        var frames: [CGImage] = []
        frames.reserveCapacity(state.frameCount)
        for index in 0..<state.frameCount {
            guard let rect = layout.frameRect(state: state, frameIndex: index),
                  let cropped = atlas.cropping(
                      to: CGRect(x: rect.x, y: rect.y, width: rect.w, height: rect.h)
                  ),
                  let frame = detachedBitmap(cropped)
            else { continue }
            frames.append(frame)
        }
        return frames
    }

    private func restoreFrames(
        _ frames: [CGImage],
        pet: inout CachedPet,
        pixelOptimizationEnabled: Bool
    ) -> [CGImage] {
        guard pixelOptimizationEnabled, !frames.isEmpty else { return frames }
        switch pet.gridRestore {
        case .pending:
            if let first = frames.first,
               let texel = PixelArtGridRestorer.detectTexelSize(in: first)
            {
                pet.gridRestore = .texel(texel)
            } else {
                pet.gridRestore = .skipped
            }
        case .skipped, .texel:
            break
        }
        let recovered: [CGImage]
        if case .texel(let texel) = pet.gridRestore {
            recovered = frames.map { PixelArtGridRestorer.downsample($0, texelSize: texel) ?? $0 }
        } else {
            recovered = frames
        }
        return recovered.map(refinePixelArt)
    }

    private func refinePixelArt(_ image: CGImage) -> CGImage {
        let cleaned = PixelArtEdgeCleanup.clean(image) ?? image
        return PixelArtOutlineSpecks.remove(cleaned) ?? cleaned
    }

    private func evictUnusedStates(in pet: inout CachedPet, keeping: Set<PetdexSpriteState>) {
        pet.framesByState = pet.framesByState.filter { keeping.contains($0.key) }
    }

    private func loadCGImage(url: URL) -> CGImage? {
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil) else { return nil }
        return CGImageSourceCreateImageAtIndex(source, 0, nil)
    }

    /// Copies `image` into a freshly allocated bitmap.
    ///
    /// `CGImage.cropping(to:)` does not copy pixels: every frame stays attached to
    /// the lazily decoded atlas, and ImageIO then decodes the whole spritesheet
    /// again — and keeps that buffer alive — once per frame that gets drawn.
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
