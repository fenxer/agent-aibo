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
    }

    private init() {}

    func invalidate(except keepID: String? = nil) {
        if let keepID {
            pets = pets.filter { $0.key == keepID }
            staticImages = staticImages.filter { $0.key == keepID }
        } else {
            pets.removeAll()
            staticImages.removeAll()
        }
    }

    func invalidateRecord(_ id: String) {
        pets[id] = nil
        staticImages[id] = nil
    }

    func previewImage(for record: AiboLibraryRecord) -> NSImage? {
        switch record.kind {
        case .builtInDefault:
            return NSImage(named: "DefaultAibo")
        case .staticImage:
            return staticImage(for: record)
        case .petdex:
            return pet(for: record)?.preview
        }
    }

    func frame(
        for record: AiboLibraryRecord,
        state: PetdexSpriteState,
        frameIndex: Int
    ) -> NSImage? {
        guard record.kind == .petdex else {
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
        guard record.kind == .petdex, var pet = pet(for: record) else { return [] }
        if let cached = pet.framesByState[state], !cached.isEmpty {
            return cached
        }
        let loaded = loadStateFrames(state, pet: pet)
        let frames = loaded.isEmpty ? loadStateFrames(.idle, pet: pet) : loaded
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
        guard record.kind == .petdex else { return false }
        return pet(for: record)?.lookSupported == true
    }

    func lookLayerFrame(for record: AiboLibraryRecord, index: Int) -> CGImage? {
        guard record.kind == .petdex, var pet = pet(for: record), pet.lookSupported else {
            return nil
        }
        if let cached = pet.lookByIndex[index] {
            if pet.lookByIndex.count > 1 {
                pet.lookByIndex = [index: cached]
                pets[record.id] = pet
            }
            return cached
        }
        guard let frame = loadLookFrame(index, pet: pet) else { return nil }
        pet.lookByIndex = [index: frame]
        pets[record.id] = pet
        return frame
    }

    private func staticImage(for record: AiboLibraryRecord) -> NSImage? {
        if let cached = staticImages[record.id] { return cached }
        guard let url = AiboLibraryStore.shared.artworkURL(for: record),
              let image = NSImage(contentsOf: url)
        else { return nil }
        staticImages[record.id] = image
        return image
    }

    private func pet(for record: AiboLibraryRecord) -> CachedPet? {
        if let cached = pets[record.id] { return cached }
        guard let directory = AiboSpritePack.directory(for: record) else { return nil }

        if let manifest = AiboSpritePack.loadManifest(in: directory),
           AiboSpritePack.isComplete(manifest, in: directory)
        {
            let cached = loadConvertedPet(directory: directory, manifest: manifest)
            pets[record.id] = cached
            return cached
        }

        guard let atlasURL = AiboSpritePack.spritesheetURL(
            in: directory,
            preferredFileName: record.spriteFileName
        ) else { return nil }
        let cached = loadUnconvertedPreview(directory: directory, atlasURL: atlasURL)
        pets[record.id] = cached
        return cached
    }

    private func loadConvertedPet(
        directory: URL,
        manifest: AiboSpritePackManifest
    ) -> CachedPet {
        let idleFrames = loadClipFrames(manifest: manifest, directory: directory, state: .idle)
        let previewSource = idleFrames.first
        let preview: NSImage
        if let previewSource {
            preview = NSImage(
                cgImage: previewSource,
                size: NSSize(width: previewSource.width, height: previewSource.height)
            )
        } else {
            preview = NSImage(size: .zero)
        }
        var cached = CachedPet(
            directory: directory,
            manifest: manifest,
            atlasURL: nil,
            lookSupported: manifest.look.count == PetdexLookDirection.count,
            preview: preview
        )
        if !idleFrames.isEmpty {
            cached.framesByState[.idle] = idleFrames
        }
        return cached
    }

    private func loadUnconvertedPreview(directory: URL, atlasURL: URL) -> CachedPet {
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

        let preview = NSImage(
            cgImage: idle,
            size: NSSize(width: idle.width, height: idle.height)
        )
        return CachedPet(
            directory: directory,
            manifest: nil,
            atlasURL: atlasURL,
            lookSupported: layout.supportsLookDirections,
            preview: preview
        )
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
