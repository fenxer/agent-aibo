import Foundation
import Testing
@testable import AiboCore
@testable import AiboIngest

@Test func extensionStoreInstallsAndUninstallsPackage() throws {
    let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
    let source = root.appendingPathComponent("source", isDirectory: true)
    try FileManager.default.createDirectory(at: source, withIntermediateDirectories: true)
    let manifest = """
    {"apiVersion":1,"id":"dev.aibo.sample","name":"Sample","description":"A sample.","version":"1.0.0","author":"aibo","runtime":"js","entry":"main.js","triggers":[{"kind":"manual"}]}
    """
    try manifest.write(to: source.appendingPathComponent("manifest.json"), atomically: true, encoding: .utf8)
    try "export function run() { return { resultType: 'complete', content: [] }; }\n"
        .write(to: source.appendingPathComponent("main.js"), atomically: true, encoding: .utf8)
    let store = ExtensionStore(
        extensionsRoot: root.appendingPathComponent("extensions"),
        dataRoot: root.appendingPathComponent("data"),
        registryURL: root.appendingPathComponent("registry.json")
    )
    let installed = try store.install(from: source)
    #expect(installed.id == "dev.aibo.sample")
    #expect(store.installed().map(\.manifest.id) == ["dev.aibo.sample"])
    var registry = ExtensionRegistry(enabledIDs: ["dev.aibo.sample"], invocationCounts: ["dev.aibo.sample": 2])
    try store.saveRegistry(registry)
    try store.saveSettings(id: installed.id, values: ["model": .string("demo")])
    #expect(store.loadSettings(id: installed.id)["model"]?.stringValue == "demo")
    try store.uninstall(id: installed.id)
    #expect(store.installed().isEmpty)
    registry = store.loadRegistry()
    #expect(registry.enabledIDs.isEmpty)
    #expect(registry.invocationCounts.isEmpty)
    #expect(store.loadSettings(id: installed.id).isEmpty)
}

@Test func extensionStoreRejectsSymlink() throws {
    let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
    let source = root.appendingPathComponent("source", isDirectory: true)
    try FileManager.default.createDirectory(at: source, withIntermediateDirectories: true)
    let manifest = """
    {"apiVersion":1,"id":"dev.aibo.sample","name":"Sample","description":"A sample.","version":"1.0.0","author":"aibo","runtime":"js","entry":"main.js","triggers":[]}
    """
    try manifest.write(to: source.appendingPathComponent("manifest.json"), atomically: true, encoding: .utf8)
    try "function run() {}\n".write(to: source.appendingPathComponent("main.js"), atomically: true, encoding: .utf8)
    let outside = root.appendingPathComponent("outside.txt")
    try "secret".write(to: outside, atomically: true, encoding: .utf8)
    try FileManager.default.createSymbolicLink(
        at: source.appendingPathComponent("leak.txt"),
        withDestinationURL: outside
    )
    let store = ExtensionStore(
        extensionsRoot: root.appendingPathComponent("extensions"),
        dataRoot: root.appendingPathComponent("data"),
        registryURL: root.appendingPathComponent("registry.json")
    )
    #expect(throws: ExtensionStoreError.self) {
        try store.install(from: source)
    }
}
