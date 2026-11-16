import Foundation
import Testing
@testable import AiboCore

private let home = URL(fileURLWithPath: "/Users/tester", isDirectory: true)
private let cursorBase = URL(fileURLWithPath: "/Users/tester/.cursor", isDirectory: true)
private let codexBase = URL(fileURLWithPath: "/Users/tester/.codex", isDirectory: true)

@Test func cursorGroupsTheSameAppAcrossEventsAndKeepsOtherOwners() {
    let agentPet = "\"/Applications/AgentPet.app/Contents/MacOS/agentpet\" hook --agent cursor"
    let aibo = "/Applications/aibo.app/Contents/Helpers/aibo-hook"
    let config: [String: Any] = [
        "version": 1,
        "hooks": [
            "stop": [
                ["type": "command", "command": agentPet],
                ["type": "command", "command": aibo],
            ],
            "sessionStart": [
                ["type": "command", "command": agentPet],
            ],
            "preToolUse": [
                [
                    "command": "/usr/local/bin/format.sh",
                    "matcher": "Write",
                    "failClosed": true,
                ],
            ],
        ],
    ]

    let inventory = HookInventoryEditor.inventory(
        config: config,
        style: .cursor,
        baseDirectory: cursorBase,
        homeDirectory: home
    )

    let pet = inventory.owners.first { $0.title == "AgentPet" }
    #expect(pet?.kind == .application)
    #expect(pet?.bundlePath == "/Applications/AgentPet.app")
    #expect(pet?.placements.map(\.eventName) == ["sessionStart", "stop"])

    let installed = inventory.owners.first { $0.bundlePath == "/Applications/aibo.app" }
    #expect(installed?.suggestsRemoval { $0 == "/Applications/aibo.app" } == false)
    #expect(pet?.suggestsRemoval { $0 == "/Applications/aibo.app" } == true)

    let script = inventory.owners.first { $0.title == "format.sh" }
    #expect(script?.kind == .file)
    #expect(script?.placements.first?.matcher == "Write")
    #expect(script?.suggestsRemoval { _ in true } == false)
    #expect(script?.suggestsRemoval { _ in false } == true)
}

@Test func separateAiboInstallsStaySeparateOwners() {
    let config: [String: Any] = [
        "hooks": [
            "stop": [
                ["command": "/Applications/aibo.app/Contents/Helpers/aibo-hook"],
                ["command": "/Users/tester/Build/Debug/aibo.app/Contents/Helpers/aibo-hook"],
            ],
        ],
    ]
    let inventory = HookInventoryEditor.inventory(
        config: config,
        style: .cursor,
        baseDirectory: cursorBase,
        homeDirectory: home
    )
    #expect(inventory.owners.count == 2)
    let installed = inventory.owners.first { $0.bundlePath == "/Applications/aibo.app" }
    let derived = inventory.owners.first { $0.bundlePath == "/Users/tester/Build/Debug/aibo.app" }
    #expect(installed?.suggestsRemoval { $0 == "/Applications/aibo.app" } == false)
    #expect(derived?.suggestsRemoval { $0 == "/Applications/aibo.app" } == true)
}

@Test func quotedPathsCommandsAndPromptsAreClassified() {
    let config: [String: Any] = [
        "hooks": [
            "beforeShellExecution": [
                ["command": "\"/Applications/Foo Bar.app/Contents/MacOS/foo\" --flag"],
                ["command": "/Applications/Foo\\ Bar.app/Contents/MacOS/foo"],
                ["command": "echo hello"],
                ["command": "~/bin/hook.sh"],
                ["command": "./hooks/format.sh"],
                ["type": "prompt", "prompt": "Only allow read-only commands."],
            ],
        ],
    ]
    let inventory = HookInventoryEditor.inventory(
        config: config,
        style: .cursor,
        baseDirectory: cursorBase,
        homeDirectory: home
    )

    let app = inventory.owners.first { $0.title == "Foo Bar" }
    #expect(app?.kind == .application)
    #expect(app?.placements.count == 2)
    #expect(app?.bundlePath == "/Applications/Foo Bar.app")

    let command = inventory.owners.first { $0.kind == .command }
    #expect(command?.title == "echo")
    #expect(command?.detail == "echo hello")
    #expect(command?.suggestsRemoval { _ in false } == false)

    let tilde = inventory.owners.first { $0.resolvedPath == "/Users/tester/bin/hook.sh" }
    #expect(tilde?.kind == .file)

    let script = inventory.owners.first { $0.title == "format.sh" }
    #expect(script?.kind == .script)
    #expect(script?.resolvedPath == "/Users/tester/.cursor/hooks/format.sh")

    let prompt = inventory.owners.first { $0.kind == .prompt }
    #expect(prompt?.title == "Only allow read-only commands.")
    #expect(prompt?.suggestsRemoval { _ in false } == false)
}

@Test func cursorRemovalDropsOnlyTheChosenOwner() throws {
    let config: [String: Any] = [
        "version": 1,
        "note": "keep",
        "hooks": [
            "preToolUse": [
                [
                    "command": "/Applications/Gone.app/Contents/MacOS/gone",
                    "type": "command",
                    "timeout": 5,
                ],
                [
                    "command": "/usr/local/bin/keep",
                    "matcher": "Shell",
                    "failClosed": true,
                ],
            ],
            "stop": [
                ["command": "echo stay"],
                "not-an-entry",
            ],
            "sessionEnd": [
                ["command": "/Applications/Gone.app/Contents/MacOS/gone"],
            ],
        ],
    ]
    let inventory = HookInventoryEditor.inventory(
        config: config,
        style: .cursor,
        baseDirectory: cursorBase,
        homeDirectory: home
    )
    let gone = try #require(inventory.owners.first { $0.title == "Gone" })
    #expect(inventory.unrecognizedCount == 1)

    let removed = HookInventoryEditor.removingOwner(
        id: gone.id,
        from: config,
        style: .cursor,
        baseDirectory: cursorBase,
        homeDirectory: home
    )
    #expect(removed["version"] as? Int == 1)
    #expect(removed["note"] as? String == "keep")

    let hooks = try #require(removed["hooks"] as? [String: Any])
    let pre = try #require(hooks["preToolUse"] as? [[String: Any]])
    #expect(pre.count == 1)
    #expect(pre[0]["command"] as? String == "/usr/local/bin/keep")
    #expect(pre[0]["matcher"] as? String == "Shell")
    #expect(pre[0]["failClosed"] as? Bool == true)

    let stop = try #require(hooks["stop"] as? [Any])
    #expect(stop.count == 2)
    #expect(stop[1] as? String == "not-an-entry")
    #expect(hooks["sessionEnd"] == nil)

    let again = HookInventoryEditor.removingOwner(
        id: gone.id,
        from: removed,
        style: .cursor,
        baseDirectory: cursorBase,
        homeDirectory: home
    )
    let againHooks = try #require(again["hooks"] as? [String: Any])
    #expect((againHooks["preToolUse"] as? [[String: Any]])?.count == 1)
}

@Test func codexRemovalKeepsSiblingCommandsAndMatchers() throws {
    let config: [String: Any] = [
        "hooks": [
            "PreToolUse": [
                [
                    "matcher": "Bash",
                    "hooks": [
                        ["type": "command", "command": "/Applications/Gone.app/Contents/MacOS/gone"],
                        ["type": "command", "command": "/usr/local/bin/keep", "timeout": 3],
                    ],
                ],
            ],
            "Stop": [
                [
                    "hooks": [
                        ["command": "/Applications/Gone.app/Contents/MacOS/gone"],
                    ],
                ],
                [
                    "matcher": "Read",
                    "hooks": [
                        ["command": "echo stay"],
                    ],
                ],
            ],
        ],
    ]
    let inventory = HookInventoryEditor.inventory(
        config: config,
        style: .codex,
        baseDirectory: codexBase,
        homeDirectory: home
    )
    let gone = try #require(inventory.owners.first { $0.title == "Gone" })
    #expect(gone.placements.map(\.eventName) == ["PreToolUse", "Stop"])

    let removed = HookInventoryEditor.removingOwner(
        id: gone.id,
        from: config,
        style: .codex,
        baseDirectory: codexBase,
        homeDirectory: home
    )
    let hooks = try #require(removed["hooks"] as? [String: Any])
    let pre = try #require(hooks["PreToolUse"] as? [[String: Any]])
    #expect(pre.count == 1)
    #expect(pre[0]["matcher"] as? String == "Bash")
    let nested = try #require(pre[0]["hooks"] as? [[String: Any]])
    #expect(nested.count == 1)
    #expect(nested[0]["command"] as? String == "/usr/local/bin/keep")
    #expect(nested[0]["timeout"] as? Int == 3)

    let stop = try #require(hooks["Stop"] as? [[String: Any]])
    #expect(stop.count == 1)
    #expect(stop[0]["matcher"] as? String == "Read")
    #expect(hooks["sessionStart"] == nil)

    let encoded = try HooksConfigJSON.encodePretty(removed)
    let parsed = try HooksConfigJSON.parseObject(from: encoded)
    #expect(parsed["hooks"] is [String: Any])
}

@Test func unknownOwnerDoesNotChangeTheFile() {
    let config: [String: Any] = [
        "version": 1,
        "hooks": [
            "stop": [
                ["command": "echo stay"],
            ],
        ],
    ]
    let removed = HookInventoryEditor.removingOwner(
        id: "path:/missing",
        from: config,
        style: .cursor,
        baseDirectory: cursorBase,
        homeDirectory: home
    )
    let hooks = removed["hooks"] as? [String: Any]
    let stop = hooks?["stop"] as? [[String: Any]]
    #expect(stop?.first?["command"] as? String == "echo stay")
    #expect(removed["version"] as? Int == 1)
}

@Test func claudeSettingsKeepOtherKeysAndDetectHttpAndMCP() throws {
    let config: [String: Any] = [
        "model": "claude",
        "permissions": ["allow"],
        "hooks": [
            "PreToolUse": [
                [
                    "matcher": "Bash",
                    "hooks": [
                        ["type": "command", "command": "/Applications/Gone.app/Contents/MacOS/gone"],
                        [
                            "type": "http",
                            "url": "http://localhost:8080/hooks/pre-tool-use",
                        ],
                        [
                            "type": "mcp_tool",
                            "server": "my_server",
                            "tool": "security_scan",
                        ],
                    ],
                ],
            ],
            "Notification": [
                [
                    "hooks": [
                        ["type": "command", "command": "osascript -e 'display notification \"hi\"'"],
                    ],
                ],
            ],
        ],
    ]
    let inventory = HookInventoryEditor.inventory(
        config: config,
        style: .codex,
        baseDirectory: home.appending(path: ".claude"),
        homeDirectory: home
    )
    let gone = try #require(inventory.owners.first { $0.title == "Gone" })
    let http = try #require(inventory.owners.first { $0.kind == .network })
    #expect(http.title == "localhost")
    #expect(http.suggestsRemoval { _ in false } == false)
    let mcp = try #require(inventory.owners.first { $0.kind == .mcpTool })
    #expect(mcp.title == "my_server · security_scan")
    #expect(inventory.owners.contains { $0.kind == .command && $0.title == "osascript" })

    let removed = HookInventoryEditor.removingOwner(
        id: gone.id,
        from: config,
        style: .codex,
        baseDirectory: home.appending(path: ".claude"),
        homeDirectory: home
    )
    #expect(removed["model"] as? String == "claude")
    #expect(removed["permissions"] as? [String] == ["allow"])
    let hooks = try #require(removed["hooks"] as? [String: Any])
    let pre = try #require(hooks["PreToolUse"] as? [[String: Any]])
    let nested = try #require(pre[0]["hooks"] as? [[String: Any]])
    #expect(nested.count == 2)
    #expect(nested.contains { ($0["type"] as? String) == "http" })
}

@Test func copilotBashAndExecPointAtTheApp() {
    let config: [String: Any] = [
        "version": 1,
        "trustedFolders": ["/tmp"],
        "hooks": [
            "preToolUse": [
                [
                    "type": "command",
                    "bash": "\"/Applications/AgentPet.app/Contents/MacOS/agentpet\" hook --agent copilot",
                    "powershell": "unused",
                ],
                [
                    "type": "command",
                    "exec": "node",
                    "args": ["./check.js"],
                ],
            ],
        ],
    ]
    let inventory = HookInventoryEditor.inventory(
        config: config,
        style: .cursor,
        baseDirectory: home.appending(path: ".copilot/hooks"),
        homeDirectory: home
    )
    let pet = inventory.owners.first { $0.title == "AgentPet" }
    #expect(pet?.kind == .application)
    #expect(pet?.bundlePath == "/Applications/AgentPet.app")
    let script = inventory.owners.first { $0.title == "check.js" }
    #expect(script?.kind == .script)
    #expect(script?.resolvedPath == "/Users/tester/.copilot/hooks/check.js")
    #expect(inventory.owners.contains { $0.title == "unused" } == false)
}

@Test func variablePathsAreNotReportedMissing() {
    let config: [String: Any] = [
        "hooks": [
            "BeforeTool": [
                [
                    "matcher": "write_file|replace",
                    "hooks": [
                        [
                            "type": "command",
                            "command": "$GEMINI_PROJECT_DIR/.gemini/hooks/security.sh",
                        ],
                    ],
                ],
            ],
        ],
    ]
    let inventory = HookInventoryEditor.inventory(
        config: config,
        style: .codex,
        baseDirectory: home.appending(path: ".gemini"),
        homeDirectory: home
    )
    let script = inventory.owners.first { $0.title == "security.sh" }
    #expect(script?.kind == .script)
    #expect(script?.resolvedPath == nil)
    #expect(script?.suggestsRemoval { _ in false } == false)
}

@Test func factoryRootAndAntigravityNamesRemoveOnlyTheChosenHook() throws {
    let factory: [String: Any] = [
        "description": "keep",
        "PreToolUse": [
            [
                "matcher": "Execute",
                "hooks": [
                    ["type": "command", "command": "/Applications/Gone.app/Contents/MacOS/gone"],
                ],
            ],
        ],
        "Stop": [
            [
                "hooks": [
                    ["command": "echo stay"],
                ],
            ],
        ],
    ]
    let factoryInventory = HookInventoryEditor.inventory(
        config: factory,
        style: .factory,
        baseDirectory: home.appending(path: ".factory"),
        homeDirectory: home
    )
    let gone = try #require(factoryInventory.owners.first { $0.title == "Gone" })
    let factoryRemoved = HookInventoryEditor.removingOwner(
        id: gone.id,
        from: factory,
        style: .factory,
        baseDirectory: home.appending(path: ".factory"),
        homeDirectory: home
    )
    #expect(factoryRemoved["description"] as? String == "keep")
    #expect(factoryRemoved["PreToolUse"] == nil)
    let stop = factoryRemoved["Stop"] as? [[String: Any]]
    #expect(stop?.count == 1)

    let antigravity: [String: Any] = [
        "safety-gate": [
            "enabled": true,
            "PreToolUse": [
                [
                    "matcher": "run_command",
                    "hooks": [
                        ["type": "command", "command": "/Applications/Gone.app/Contents/MacOS/gone"],
                    ],
                ],
            ],
        ],
        "reminder": [
            "PreInvocation": [
                ["type": "command", "command": "./scripts/reminder.sh"],
            ],
        ],
    ]
    let named = HookInventoryEditor.inventory(
        config: antigravity,
        style: .named,
        baseDirectory: home.appending(path: ".gemini/config"),
        homeDirectory: home
    )
    let namedGone = try #require(named.owners.first { $0.title == "Gone" })
    let reminder = try #require(named.owners.first { $0.title == "reminder.sh" })
    #expect(reminder.kind == .script)
    #expect(reminder.resolvedPath == "/Users/tester/.gemini/config/scripts/reminder.sh")

    let namedRemoved = HookInventoryEditor.removingOwner(
        id: namedGone.id,
        from: antigravity,
        style: .named,
        baseDirectory: home.appending(path: ".gemini/config"),
        homeDirectory: home
    )
    #expect(namedRemoved["safety-gate"] == nil)
    let kept = try #require(namedRemoved["reminder"] as? [String: Any])
    let events = try #require(kept["PreInvocation"] as? [[String: Any]])
    #expect(events.first?["command"] as? String == "./scripts/reminder.sh")
}
