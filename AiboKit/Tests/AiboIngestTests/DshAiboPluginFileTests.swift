import Foundation
import Testing
@testable import AiboIngest

@Test func dshAiboPluginFileInstallsAndUninstallsHomePatch() throws {
    let fileManager = FileManager.default
    let scratch = fileManager.temporaryDirectory
        .appendingPathComponent("aibo-dsh-\(UUID().uuidString)", isDirectory: true)
    let source = scratch.appendingPathComponent("plugin-src", isDirectory: true)
    let home = scratch.appendingPathComponent("dsh-home", isDirectory: true)
    defer { try? fileManager.removeItem(at: scratch) }

    try fileManager.createDirectory(at: source, withIntermediateDirectories: true)
    try Data("export const name = 'aibo-observer'\n".utf8).write(
        to: source.appendingPathComponent("index.js")
    )

    let environment = ["DSH_HOME": home.path]
    let pluginInstall = scratch.appendingPathComponent("aibo-plugin", isDirectory: true)
    try DshAiboPluginFile.install(
        sourceDirectory: source,
        pluginInstallDirectory: pluginInstall,
        environment: environment,
        fileManager: fileManager
    )
    #expect(try DshAiboPluginFile.isInstalled(environment: environment, fileManager: fileManager))

    let patch = try String(
        contentsOf: DshAiboPluginFile.patchURL(environment: environment, fileManager: fileManager),
        encoding: .utf8
    )
    #expect(patch.contains("id: aibo-observer"))
    #expect(
        fileManager.fileExists(
            atPath: pluginInstall.appendingPathComponent("index.js").path
        )
    )

    try DshAiboPluginFile.uninstall(
        pluginInstallDirectory: pluginInstall,
        environment: environment,
        fileManager: fileManager
    )
    #expect(try DshAiboPluginFile.isInstalled(environment: environment, fileManager: fileManager) == false)
    #expect(fileManager.fileExists(atPath: DshAiboPluginFile.patchURL(environment: environment, fileManager: fileManager).path) == false)
}
