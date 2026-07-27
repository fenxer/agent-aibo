import Foundation
import Testing
@testable import AiboCore

@Test func codexInstallIsIdempotentAndPreservesForeignHooks() throws {
    let original: [String: Any] = [
        "hooks": [
            "PreToolUse": [
                [
                    "matcher": "^Bash$",
                    "hooks": [
                        [
                            "type": "command",
                            "command": "/usr/local/bin/other-hook",
                        ],
                    ],
                ],
            ],
        ],
    ]

    let command = "/Applications/aibo.app/Contents/Helpers/aibo-hook"
    let once = try CodexHooksInstaller.install(config: original, command: command)
    let twice = try CodexHooksInstaller.install(config: once, command: command)

    let hooks = twice["hooks"] as? [String: Any]
    let pre = hooks?["PreToolUse"] as? [[String: Any]]
    #expect(pre?.count == 2)
    #expect(pre?.contains(where: { group in
        let nested = group["hooks"] as? [[String: Any]]
        return nested?.contains(where: { ($0["command"] as? String) == "/usr/local/bin/other-hook" })
            == true
    }) == true)
    #expect(pre?.filter { CodexHooksInstaller.isAiboGroup($0) }.count == 1)

    let onceData = try HooksConfigJSON.encodePretty(once)
    let twiceData = try HooksConfigJSON.encodePretty(twice)
    #expect(onceData == twiceData)
}

@Test func codexUninstallRemovesOnlyAiboGroups() throws {
    let command = "/tmp/aibo-hook"
    var config = try CodexHooksInstaller.install(config: [:], command: command)
    config = try CodexHooksInstaller.install(
        config: {
            var c = config
            var hooks = c["hooks"] as! [String: Any]
            var stop = hooks["Stop"] as! [[String: Any]]
            stop.append([
                "hooks": [
                    [
                        "type": "command",
                        "command": "echo foreign",
                    ],
                ],
            ])
            hooks["Stop"] = stop
            c["hooks"] = hooks
            return c
        }(),
        command: command
    )

    let uninstalled = try CodexHooksInstaller.uninstall(config: config)
    let hooks = uninstalled["hooks"] as? [String: Any]
    #expect(CodexHooksInstaller.isInstalled(uninstalled) == false)
    let stop = hooks?["Stop"] as? [[String: Any]]
    #expect(stop?.count == 1)
    let nested = stop?.first?["hooks"] as? [[String: Any]]
    #expect(nested?.first?["command"] as? String == "echo foreign")
}

@Test func codexNestedShapeUsesInnerHooksArray() throws {
    let command = "/tmp/aibo-hook"
    let installed = try CodexHooksInstaller.install(config: [:], command: command)
    let hooks = installed["hooks"] as? [String: Any]
    let permission = hooks?["PermissionRequest"] as? [[String: Any]]
    let nested = permission?.first?["hooks"] as? [[String: Any]]
    #expect(nested?.first?["type"] as? String == "command")
    #expect(nested?.first?["command"] as? String == command)
}
