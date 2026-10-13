import AiboCore
import AppKit
import UniformTypeIdentifiers

/// Image copied to the clipboard, as a png or jpeg path the plugin can send.
enum ExtensionClipboardImage {
    /// `Command-V` aimed at this bubble, and not at a text field inside it.
    static func isPasteShortcut(_ event: NSEvent, chrome: ExtensionBubbleChrome) -> Bool {
        let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
        guard flags == .command else { return false }
        guard event.charactersIgnoringModifiers?.lowercased() == "v" else { return false }
        guard let window = event.window else { return false }
        switch chrome {
        case .anchored:
            guard window is AiboPanel else { return false }
        case .window:
            guard window is ExtensionBubbleWindow else { return false }
        }
        if window.firstResponder is NSTextView { return false }
        return true
    }

    /// png and jpeg stay as copied. Any other image is written out as PNG.
    static func fileURL() -> URL? {
        let pasteboard = NSPasteboard.general
        if let url = imageFileURL(on: pasteboard) {
            if ExtensionFileAcceptance.matches(url: url, accepts: ["png", "jpg", "jpeg"]) {
                return url
            }
            if let image = NSImage(contentsOf: url), let png = pngData(from: image) {
                return write(png, pathExtension: "png")
            }
        }
        if let data = pasteboard.data(forType: .png), !data.isEmpty {
            return write(data, pathExtension: "png")
        }
        let jpeg = NSPasteboard.PasteboardType(UTType.jpeg.identifier)
        if let data = pasteboard.data(forType: jpeg), !data.isEmpty {
            return write(data, pathExtension: "jpg")
        }
        guard let image = NSImage(pasteboard: pasteboard), let png = pngData(from: image) else {
            return nil
        }
        return write(png, pathExtension: "png")
    }

    private static func imageFileURL(on pasteboard: NSPasteboard) -> URL? {
        let options: [NSPasteboard.ReadingOptionKey: Any] = [.urlReadingFileURLsOnly: true]
        guard let urls = pasteboard.readObjects(forClasses: [NSURL.self], options: options) as? [URL] else {
            return nil
        }
        return urls.first { url in
            guard let type = UTType(filenameExtension: url.pathExtension) else { return false }
            return type.conforms(to: .image)
        }
    }

    private static func pngData(from image: NSImage) -> Data? {
        guard let tiff = image.tiffRepresentation, let rep = NSBitmapImageRep(data: tiff) else { return nil }
        return rep.representation(using: .png, properties: [:])
    }

    private static func write(_ data: Data, pathExtension: String) -> URL? {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("aibo-paste-\(UUID().uuidString)")
            .appendingPathExtension(pathExtension)
        do {
            try data.write(to: url, options: .atomic)
            return url
        } catch {
            return nil
        }
    }
}
