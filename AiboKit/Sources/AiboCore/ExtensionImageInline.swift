import Foundation

/// Turns a user-picked image path inside an `aibo/llm` request into bytes the provider can send.
///
/// Plugins never read the disk. The host only inlines a path that was one of this run's image fields,
/// so a plugin cannot point the model at some other file.
public enum ExtensionImageInline {
    public static let byteLimit = 8 * 1024 * 1024

    public struct Attachment: Equatable, Sendable {
        public var mime: String
        public var base64: String
    }

    public enum Failure: Equatable, Sendable, Error {
        case unreadable
        case tooLarge
        case unsupportedType
    }

    public static func load(path: String, byteLimit: Int = byteLimit) -> Result<Attachment, Failure> {
        let url = URL(fileURLWithPath: path)
        let ext = url.pathExtension
        guard let mime = mimeType(for: ext) else { return .failure(.unsupportedType) }
        let values = try? url.resourceValues(forKeys: [.fileSizeKey, .isRegularFileKey])
        guard values?.isRegularFile == true, let size = values?.fileSize, size > 0 else {
            return .failure(.unreadable)
        }
        if size > byteLimit { return .failure(.tooLarge) }
        guard let data = try? Data(contentsOf: url), !data.isEmpty else {
            return .failure(.unreadable)
        }
        return .success(Attachment(mime: mime, base64: data.base64EncodedString()))
    }

    /// Replace each message `image` path with `{ mime, data }`. Text-only requests stay as they are.
    public static func attach(
        params: [String: ExtensionValue],
        allowedPaths: Set<String>
    ) -> Result<[String: ExtensionValue], Failure> {
        guard let messages = params["messages"]?.arrayValue else { return .success(params) }
        let allowed = Set(allowedPaths.map(resolvedPath))
        var nextMessages: [ExtensionValue] = []
        nextMessages.reserveCapacity(messages.count)
        var changed = false
        for message in messages {
            guard var object = message.objectValue, let image = object["image"] else {
                nextMessages.append(message)
                continue
            }
            guard let path = image.stringValue else { return .failure(.unsupportedType) }
            let standard = resolvedPath(path)
            guard allowed.contains(standard) else { return .failure(.unreadable) }
            switch load(path: standard) {
            case .success(let attachment):
                object["image"] = .object([
                    "mime": .string(attachment.mime),
                    "data": .string(attachment.base64),
                ])
                nextMessages.append(.object(object))
                changed = true
            case .failure(let failure):
                return .failure(failure)
            }
        }
        guard changed else { return .success(params) }
        var next = params
        next["messages"] = .array(nextMessages)
        return .success(next)
    }

    private static func resolvedPath(_ path: String) -> String {
        URL(fileURLWithPath: path).resolvingSymlinksInPath().path
    }

    private static func mimeType(for fileExtension: String) -> String? {
        switch fileExtension.lowercased() {
        case "png": "image/png"
        case "jpg", "jpeg": "image/jpeg"
        default: nil
        }
    }
}
