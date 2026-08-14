import AiboCore
import Foundation

@MainActor
@Observable
final class HookSpriteSettings {
    static let shared = HookSpriteSettings()

    private enum Keys {
        static let mapping = "settings.hookSpriteMapping"
    }

    private(set) var file: HookSpriteMappingFile

    private init() {
        file = Self.load()
    }

    func sprite(for agent: AgentKind, hookEventName: String) -> PetdexSpriteState {
        HookSpriteMapping.effectiveSprite(
            agent: agent,
            hookEventName: hookEventName,
            overrides: file
        )
    }

    func setSprite(_ sprite: PetdexSpriteState, agent: AgentKind, hookEventName: String) {
        let defaultValue = HookSpriteMapping.defaultSprite(agent: agent, hookEventName: hookEventName)
        var next = file
        switch agent {
        case .cursor:
            if sprite == defaultValue {
                next.cursor.removeValue(forKey: hookEventName)
            } else {
                next.cursor[hookEventName] = sprite.rawValue
            }
        case .codex:
            if sprite == defaultValue {
                next.codex.removeValue(forKey: hookEventName)
            } else {
                next.codex[hookEventName] = sprite.rawValue
            }
        case .deepseek:
            if sprite == defaultValue {
                next.deepseek.removeValue(forKey: hookEventName)
            } else {
                next.deepseek[hookEventName] = sprite.rawValue
            }
        }
        file = next
        persist()
    }

    func resetAll(for agent: AgentKind) {
        var next = file
        switch agent {
        case .cursor: next.cursor = [:]
        case .codex: next.codex = [:]
        case .deepseek: next.deepseek = [:]
        }
        file = next
        persist()
    }

    func hasCustomOverrides(for agent: AgentKind) -> Bool {
        switch agent {
        case .cursor: !file.cursor.isEmpty
        case .codex: !file.codex.isEmpty
        case .deepseek: !file.deepseek.isEmpty
        }
    }

    func resolve(agent: AgentKind, hookEventName: String?, activity: PetActivityState) -> PetdexSpriteState {
        HookSpriteMapping.resolve(
            agent: agent,
            hookEventName: hookEventName,
            activity: activity,
            overrides: file
        )
    }

    private func persist() {
        do {
            let data = try JSONEncoder().encode(file)
            UserDefaults.standard.set(data, forKey: Keys.mapping)
        } catch {
            // Keep in-memory mapping if encode fails.
        }
    }

    private static func load() -> HookSpriteMappingFile {
        guard let data = UserDefaults.standard.data(forKey: Keys.mapping),
              let file = try? JSONDecoder().decode(HookSpriteMappingFile.self, from: data)
        else {
            return HookSpriteMappingFile()
        }
        return file
    }
}
