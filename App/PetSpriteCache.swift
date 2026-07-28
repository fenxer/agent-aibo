import AiboCore
import AppKit
import ImageIO

/// Decodes and caches Petdex spritesheets / static images for the desktop pet.
@MainActor
final class PetSpriteCache {
    static let shared = PetSpriteCache()

    private var sheets: [String: CachedSheet] = [:]
    private var staticImages: [String: NSImage] = [:]

    private struct CachedSheet {
        var frames: [PetdexSpriteState: [NSImage]]
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

    func previewImage(for record: PetLibraryRecord) -> NSImage? {
        switch record.kind {
        case .builtInDefault:
            return NSImage(named: "DefaultPet")
        case .staticImage:
            return staticImage(for: record)
        case .petdex:
            return sheet(for: record)?.idlePreview
        }
    }

    func frame(
        for record: PetLibraryRecord,
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

    private func staticImage(for record: PetLibraryRecord) -> NSImage? {
        if let cached = staticImages[record.id] { return cached }
        guard let url = PetLibraryStore.shared.artworkURL(for: record),
              let image = NSImage(contentsOf: url)
        else { return nil }
        staticImages[record.id] = image
        return image
    }

    private func sheet(for record: PetLibraryRecord) -> CachedSheet? {
        if let cached = sheets[record.id] { return cached }
        guard let url = PetLibraryStore.shared.artworkURL(for: record),
              let cgImage = loadCGImage(url: url)
        else { return nil }

        let width = cgImage.width
        let height = cgImage.height
        let whole = NSImage(cgImage: cgImage, size: NSSize(width: width, height: height))

        guard let layout = PetdexSpriteLayout(pixelWidth: width, pixelHeight: height) else {
            let cached = CachedSheet(frames: [.idle: [whole]], idlePreview: whole)
            sheets[record.id] = cached
            return cached
        }

        var frames: [PetdexSpriteState: [NSImage]] = [:]
        for state in PetdexSpriteState.allCases {
            var images: [NSImage] = []
            images.reserveCapacity(state.frameCount)
            for index in 0..<state.frameCount {
                guard let rect = layout.frameRect(state: state, frameIndex: index),
                      let cropped = cgImage.cropping(
                          to: CGRect(x: rect.x, y: rect.y, width: rect.w, height: rect.h)
                      )
                else { continue }
                images.append(
                    NSImage(
                        cgImage: cropped,
                        size: NSSize(width: rect.w, height: rect.h)
                    )
                )
            }
            if !images.isEmpty {
                frames[state] = images
            }
        }

        let idlePreview = frames[.idle]?.first ?? whole
        let cached = CachedSheet(frames: frames, idlePreview: idlePreview)
        sheets[record.id] = cached
        return cached
    }

    private func loadCGImage(url: URL) -> CGImage? {
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil) else { return nil }
        return CGImageSourceCreateImageAtIndex(source, 0, nil)
    }
}
