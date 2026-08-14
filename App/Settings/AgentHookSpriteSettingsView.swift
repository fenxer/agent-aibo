import AiboCore
import AppKit
import SwiftUI

/// Per-agent page: map each installed hook event to a Petdex sprite row.
struct AgentHookSpriteSettingsView: View {
    let agent: AgentKind
    var onBack: () -> Void

    @Bindable private var hookSprites = HookSpriteSettings.shared
    private var library = PetLibraryStore.shared

    /// Which Sprite Actions row the pointer is over; drives the sticky preview.
    @State private var hoveredHook: String?

    private var hooks: [String] {
        HookSpriteMapping.configurableHooks(for: agent)
    }

    private var previewHook: String? {
        hoveredHook ?? hooks.first
    }

    private var previewState: PetdexSpriteState {
        guard let previewHook else { return .idle }
        return hookSprites.sprite(for: agent, hookEventName: previewHook)
    }

    private var title: String {
        switch agent {
        case .cursor: String(localized: "Cursor Hooks")
        case .codex: String(localized: "Codex Hooks")
        case .deepseek: String(localized: "DeepSeek Hooks")
        }
    }

    /// Prefer the active Petdex pet; otherwise the first installed Petdex pack.
    private var previewRecord: PetLibraryRecord? {
        let selected = library.selectedRecord
        if selected.kind == .petdex { return selected }
        return library.records.first(where: { $0.kind == .petdex })
    }

    var body: some View {
        VStack(spacing: 0) {
            previewSection

            Divider()

            ScrollView {
                actionsColumn
                    .padding()
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .settingsDetailChrome(title: title, canGoBack: true, onBack: onBack)
    }

    /// Stays above the Sprite Actions scroll region (sticky header band).
    private var previewSection: some View {
        VStack(spacing: 12) {
            Text(String(localized: "Animation Preview"))
                .font(.headline)
                .frame(maxWidth: .infinity, alignment: .leading)

            Group {
                if let record = previewRecord {
                    PetdexSpritePreview(record: record, state: previewState, size: 120)
                        .accessibilityLabel(Text(localizedSpriteName(previewState)))
                } else {
                    ContentUnavailableView {
                        Label(
                            String(localized: "No Petdex Pet"),
                            systemImage: "pawprint"
                        )
                    } description: {
                        Text(String(localized: "Install or select a Petdex pet in Pet to preview animations."))
                    }
                    .frame(minHeight: 140)
                }
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 16)
            .background(.quaternary.opacity(0.35), in: RoundedRectangle(cornerRadius: 12, style: .continuous))

            Text(localizedSpriteName(previewState))
                .font(.subheadline)
                .foregroundStyle(.secondary)

            if let previewHook {
                Text(previewHook)
                    .font(.caption.monospaced())
                    .foregroundStyle(.tertiary)
            }

            Text(String(localized: "Hover a Sprite Action below to preview it."))
                .font(.caption)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .top)
    }

    private var actionsColumn: some View {
        Form {
            Section {
                ForEach(hooks, id: \.self) { hook in
                    Picker(selection: binding(for: hook)) {
                        ForEach(PetdexSpriteState.allCases, id: \.self) { state in
                            Text(localizedSpriteName(state)).tag(state)
                        }
                    } label: {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(hook)
                            if let example = StatusCopy.exampleBubblePhrase(
                                agent: agent,
                                hookEventName: hook
                            ) {
                                Text("\(String(localized: "示例："))\(example)")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                    .contentShape(Rectangle())
                    .onHover { hovering in
                        if hovering {
                            hoveredHook = hook
                        } else if hoveredHook == hook {
                            hoveredHook = nil
                        }
                    }
                }
            } header: {
                Text(String(localized: "Sprite Actions"))
            } footer: {
                Text(String(localized: "Choose which Petdex animation plays when each hook fires. Applies when a Petdex pet is selected."))
            }

            if hookSprites.hasCustomOverrides(for: agent) {
                Section {
                    Button(String(localized: "Reset to Defaults"), role: .destructive) {
                        hookSprites.resetAll(for: agent)
                    }
                }
            }
        }
        .formStyle(.grouped)
    }

    private func binding(for hook: String) -> Binding<PetdexSpriteState> {
        Binding(
            get: { hookSprites.sprite(for: agent, hookEventName: hook) },
            set: { hookSprites.setSprite($0, agent: agent, hookEventName: hook) }
        )
    }

    private func localizedSpriteName(_ state: PetdexSpriteState) -> String {
        switch state {
        case .idle: String(localized: "Idle")
        case .runningRight: String(localized: "Run Right")
        case .runningLeft: String(localized: "Run Left")
        case .waving: String(localized: "Waving")
        case .jumping: String(localized: "Jumping")
        case .failed: String(localized: "Failed")
        case .waiting: String(localized: "Waiting")
        case .running: String(localized: "Running")
        case .review: String(localized: "Review")
        }
    }
}

/// Loops one Petdex atlas row for settings preview (always animates, including Idle).
private struct PetdexSpritePreview: View {
    var record: PetLibraryRecord
    var state: PetdexSpriteState
    var size: CGFloat

    var body: some View {
        TimelineView(.animation(minimumInterval: frameInterval)) { timeline in
            let index = frameIndex(at: timeline.date)
            if let image = PetSpriteCache.shared.frame(for: record, state: state, frameIndex: index) {
                Image(nsImage: image)
                    .resizable()
                    .interpolation(.none)
                    .scaledToFit()
                    .frame(width: size, height: size)
            } else {
                ProgressView()
                    .frame(width: size, height: size)
            }
        }
        .id("\(record.id)-\(state.rawValue)")
    }

    private var frameInterval: TimeInterval {
        let ms = max(state.durationMilliseconds / max(state.frameCount, 1), 80)
        return Double(ms) / 1000.0
    }

    private func frameIndex(at date: Date) -> Int {
        guard frameInterval > 0 else { return 0 }
        return Int(date.timeIntervalSinceReferenceDate / frameInterval)
    }
}
