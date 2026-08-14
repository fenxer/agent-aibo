import Foundation
import Testing
@testable import AiboCore

@Test func dshHomePatchInstallsIdempotentlyAndPreservesForeignYAML() throws {
    let original = """
    - insert:
        - id: hello
          name: dsh-hello-plugin
    """
    let once = try DshHomePatch.install(existing: original, pluginPath: "/tmp/aibo/dsh-aibo/index.js")
    let twice = try DshHomePatch.install(existing: once, pluginPath: "/tmp/aibo/dsh-aibo/index.js")
    #expect(DshHomePatch.isInstalled(once))
    #expect(once.contains("id: hello"))
    #expect(once.contains("name: \"/tmp/aibo/dsh-aibo/index.js\""))
    #expect(once.components(separatedBy: "id: \(DeepSeekHarnessPlugin.pluginID)").count - 1 == 1)
    #expect(once == twice)
}

@Test func dshHomePatchUninstallRemovesOnlyMarkedBlock() throws {
    let original = """
    - insert:
        - id: hello
          name: dsh-hello-plugin
    """
    let installed = try DshHomePatch.install(existing: original, pluginPath: "/tmp/plugin.js")
    let uninstalled = try DshHomePatch.uninstall(existing: installed)
    #expect(DshHomePatch.isInstalled(uninstalled) == false)
    #expect(uninstalled.contains("id: hello"))
    #expect(uninstalled.contains(DeepSeekHarnessPlugin.pluginID) == false)
}

@Test func dshHomePatchRejectsUnmatchedMarkers() {
    let broken = """
    # BEGIN aibo-observer
    - insert:
        - id: aibo-observer
          name: "/tmp/index.js"
    """
    #expect(throws: DshHomePatchError.unmatchedMarker) {
        try DshHomePatch.install(existing: broken, pluginPath: "/tmp/index.js")
    }
}

@Test func dshHomePatchRejectsUnmarkedPluginId() {
    let foreign = """
    - insert:
        - id: aibo-observer
          name: "/tmp/other.js"
    """
    #expect(throws: DshHomePatchError.unmarkedPluginEntry) {
        try DshHomePatch.uninstall(existing: foreign)
    }
}

@Test func dshHomePatchEmptyInstallWritesOnlyOurBlock() throws {
    let installed = try DshHomePatch.install(existing: "", pluginPath: "/tmp/index.js")
    #expect(DshHomePatch.isInstalled(installed))
    #expect(installed.contains(DeepSeekHarnessPlugin.beginMarker))
    #expect(installed.contains(DeepSeekHarnessPlugin.endMarker))
}
