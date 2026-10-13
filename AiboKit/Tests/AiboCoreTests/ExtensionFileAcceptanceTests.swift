import Foundation
import Testing
@testable import AiboCore

@Test func extensionFileAcceptanceMatchesExtensionsAndJPEGAlias() {
    #expect(ExtensionFileAcceptance.matches(fileExtension: "png", accepts: ["png", "jpg"]))
    #expect(ExtensionFileAcceptance.matches(fileExtension: "PNG", accepts: ["png"]))
    #expect(ExtensionFileAcceptance.matches(fileExtension: ".jpg", accepts: ["jpg"]))
    #expect(ExtensionFileAcceptance.matches(fileExtension: "jpeg", accepts: ["jpg"]))
    #expect(ExtensionFileAcceptance.matches(fileExtension: "jpg", accepts: ["jpeg"]))
    #expect(ExtensionFileAcceptance.matches(fileExtension: "gif", accepts: ["png", "jpg"]) == false)
    #expect(ExtensionFileAcceptance.matches(fileExtension: "", accepts: ["png"]) == false)
    #expect(ExtensionFileAcceptance.matches(fileExtension: "png", accepts: []) == false)
    let url = URL(fileURLWithPath: "/tmp/Photo.JPEG")
    #expect(ExtensionFileAcceptance.matches(url: url, accepts: ["jpg"]))
    #expect(ExtensionFileAcceptance.matches(url: url, accepts: ["png"]) == false)
}

@Test func extensionImageInlineReadsPNGAndRejectsTheRest() throws {
    let directory = FileManager.default.temporaryDirectory
        .appendingPathComponent("aibo-image-inline-\(UUID().uuidString)", isDirectory: true)
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: directory) }

    let png = directory.appendingPathComponent("cat.png")
    let bytes = Data("hello".utf8)
    try bytes.write(to: png)
    guard case .success(let loaded) = ExtensionImageInline.load(path: png.path) else {
        Issue.record("expected a png payload")
        return
    }
    #expect(loaded.mime == "image/png")
    #expect(loaded.base64 == bytes.base64EncodedString())

    let jpeg = directory.appendingPathComponent("cat.jpeg")
    try bytes.write(to: jpeg)
    guard case .success(let jpegLoaded) = ExtensionImageInline.load(path: jpeg.path) else {
        Issue.record("expected a jpeg payload")
        return
    }
    #expect(jpegLoaded.mime == "image/jpeg")

    let gif = directory.appendingPathComponent("cat.gif")
    try bytes.write(to: gif)
    #expect(ExtensionImageInline.load(path: gif.path) == .failure(.unsupportedType))
    #expect(ExtensionImageInline.load(path: png.path, byteLimit: 2) == .failure(.tooLarge))
    #expect(
        ExtensionImageInline.load(path: directory.appendingPathComponent("missing.png").path)
            == .failure(.unreadable)
    )
}

@Test func extensionImageInlineAttachesOnlyAllowedPaths() throws {
    let directory = FileManager.default.temporaryDirectory
        .appendingPathComponent("aibo-image-attach-\(UUID().uuidString)", isDirectory: true)
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: directory) }
    let png = directory.appendingPathComponent("cat.png")
    try Data("hello".utf8).write(to: png)

    let textOnly: [String: ExtensionValue] = [
        "messages": .array([
            .object(["role": .string("user"), "text": .string("Hi")]),
        ]),
    ]
    #expect(ExtensionImageInline.attach(params: textOnly, allowedPaths: []) == .success(textOnly))

    let withImage: [String: ExtensionValue] = [
        "messages": .array([
            .object([
                "role": .string("user"),
                "text": .string("Describe"),
                "image": .string(png.path),
            ]),
        ]),
    ]
    #expect(ExtensionImageInline.attach(params: withImage, allowedPaths: []) == .failure(.unreadable))

    guard case .success(let attached) = ExtensionImageInline.attach(params: withImage, allowedPaths: [png.path]) else {
        Issue.record("expected the image to be inlined")
        return
    }
    let image = attached["messages"]?.arrayValue?.first?.objectValue?["image"]?.objectValue
    #expect(image?["mime"]?.stringValue == "image/png")
    #expect(image?["data"]?.stringValue == Data("hello".utf8).base64EncodedString())
    #expect(image?["path"] == nil)
}
