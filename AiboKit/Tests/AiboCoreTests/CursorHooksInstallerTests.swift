import Foundation
import Testing
@testable import AiboCore

@Test func installIsIdempotentAndPreservesForeignHooks() throws {
    let original: [String: Any] = [
        "version": 1,
        "hooks": [
            "preToolUse": [
                [
                    "type": "command",
                    "command": "/usr/local/bin/other-hook",
                ],
            ],
        ],
    ]

    let command = "/Applications/aibo.app/Contents/Helpers/aibo-hook"
    let once = try CursorHooksInstaller.install(config: original, command: command)
    let twice = try CursorHooksInstaller.install(config: once, command: command)

    let hooks = twice["hooks"] as? [String: Any]
    let pre = hooks?["preToolUse"] as? [[String: Any]]
    #expect(pre?.count == 2)
    #expect(pre?.contains(where: { ($0["command"] as? String) == "/usr/local/bin/other-hook" }) == true)
    #expect(pre?.filter { CursorHooksInstaller.isAiboEntry($0) }.count == 1)

    let onceData = try CursorHooksInstaller.encodePretty(once)
    let twiceData = try CursorHooksInstaller.encodePretty(twice)
    #expect(onceData == twiceData)
}

@Test func uninstallRemovesOnlyAiboEntries() throws {
    let command = "/tmp/aibo-hook"
    var config = try CursorHooksInstaller.install(config: [:], command: command)
    config = try CursorHooksInstaller.install(
        config: {
            var c = config
            var hooks = c["hooks"] as! [String: Any]
            var stop = hooks["stop"] as! [[String: Any]]
            stop.append([
                "type": "command",
                "command": "echo foreign",
            ])
            hooks["stop"] = stop
            c["hooks"] = hooks
            return c
        }(),
        command: command
    )

    let uninstalled = try CursorHooksInstaller.uninstall(config: config)
    let hooks = uninstalled["hooks"] as? [String: Any]
    #expect(CursorHooksInstaller.isInstalled(uninstalled) == false)
    let stop = hooks?["stop"] as? [[String: Any]]
    #expect(stop?.count == 1)
    #expect(stop?.first?["command"] as? String == "echo foreign")
}

@Test func parseRejectsNonObjectJSON() {
    let data = Data("[]".utf8)
    #expect(throws: HooksInstallerError.invalidJSONObject) {
        try CursorHooksInstaller.parseObject(from: data)
    }
}
