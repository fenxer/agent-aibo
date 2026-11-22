import Foundation
import Testing
@testable import AiboCore

@Test func antigravityInstallIsIdempotentAndKeepsForeignHooks() throws {
    let original: [String: Any] = [
        "lint": [
            "PostToolUse": [
                [
                    "matcher": "run_command",
                    "hooks": [
                        ["type": "command", "command": "./scripts/lint.sh"],
                    ],
                ],
            ],
        ],
        "aibo": [
            "PreToolUse": [
                [
                    "matcher": "run_command",
                    "hooks": [
                        ["type": "command", "command": "/usr/local/bin/other-hook"],
                    ],
                ],
            ],
        ],
    ]

    let binary = "/Applications/Aibo App/aibo.app/Contents/Helpers/aibo-hook"
    let once = AntigravityHooksInstaller.install(config: original, binaryPath: binary)
    let twice = AntigravityHooksInstaller.install(config: once, binaryPath: binary)

    let onceData = try HooksConfigJSON.encodePretty(once)
    let twiceData = try HooksConfigJSON.encodePretty(twice)
    #expect(onceData == twiceData)
    #expect(AntigravityHooksInstaller.isInstalled(twice))

    let lint = twice["lint"] as? [String: Any]
    let lintEvents = lint?["PostToolUse"] as? [[String: Any]]
    #expect(lintEvents?.count == 1)

    let aibo = try #require(twice["aibo"] as? [String: Any])
    #expect(aibo["enabled"] == nil)
    let pre = try #require(aibo["PreToolUse"] as? [[String: Any]])
    #expect(pre.count == 2)
    let foreign = pre[0]["hooks"] as? [[String: Any]]
    #expect(foreign?.first?["command"] as? String == "/usr/local/bin/other-hook")
    let ours = pre[1]["hooks"] as? [[String: Any]]
    let command = try #require(ours?.first?["command"] as? String)
    #expect(command.contains("'/Applications/Aibo App/aibo.app/Contents/Helpers/aibo-hook'"))
    #expect(command.contains(" antigravity PreToolUse"))
    #expect(ours?.first?["timeout"] as? Int == 10)

    let session = try #require(aibo["SessionStart"] as? [[String: Any]])
    #expect(session.first?["hooks"] == nil)
    #expect((session.first?["command"] as? String)?.contains(" antigravity SessionStart") == true)
}

@Test func antigravityUninstallRemovesOnlyAiboCommands() throws {
    let binary = "/tmp/aibo-hook"
    var config = AntigravityHooksInstaller.install(config: [:], binaryPath: binary)
    var aibo = config["aibo"] as! [String: Any]
    var stop = aibo["Stop"] as! [[String: Any]]
    stop.append(["type": "command", "command": "echo stay"])
    aibo["Stop"] = stop
    config["aibo"] = aibo

    let uninstalled = AntigravityHooksInstaller.uninstall(config: config)
    #expect(AntigravityHooksInstaller.isInstalled(uninstalled) == false)
    let kept = try #require(uninstalled["aibo"] as? [String: Any])
    #expect(kept["PreToolUse"] == nil)
    #expect(kept["SessionStart"] == nil)
    let remaining = try #require(kept["Stop"] as? [[String: Any]])
    #expect(remaining.count == 1)
    #expect(remaining.first?["command"] as? String == "echo stay")
}

@Test func antigravityToolEventsStayNestedAndLifecycleEventsStayFlat() {
    let installed = AntigravityHooksInstaller.install(
        config: [:],
        binaryPath: "/tmp/aibo-hook"
    )
    let aibo = installed["aibo"] as? [String: Any]
    for event in ["PreToolUse", "PostToolUse"] {
        let groups = aibo?[event] as? [[String: Any]]
        #expect(groups?.first?["matcher"] as? String == "*")
        #expect(groups?.first?["hooks"] != nil)
    }
    for event in ["SessionStart", "PreInvocation", "Stop"] {
        let entries = aibo?[event] as? [[String: Any]]
        #expect(entries?.first?["command"] != nil)
        #expect(entries?.first?["hooks"] == nil)
    }
}
