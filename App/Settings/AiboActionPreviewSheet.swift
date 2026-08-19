import AiboCore
import SwiftUI

/// Sheet: sidebar lists actions; detail plays the selected clip.
struct AiboActionPreviewSheet: View {
    var record: AiboLibraryRecord

    @Environment(\.dismiss) private var dismiss
    @State private var selected: ActionPreviewSelection = .sprite(.idle)

    var body: some View {
        NavigationSplitView {
            AiboActionPreviewSidebar(selection: $selected)
                .navigationSplitViewColumnWidth(min: 160, ideal: 180, max: 220)
                .toolbar(removing: .sidebarToggle)
        } detail: {
            ZStack(alignment: .bottomTrailing) {
                AiboActionPreviewCanvas(record: record, selection: selected)

                Button(String(localized: "Done"), action: dismiss.callAsFunction)
                    .buttonStyle(.borderedProminent)
                    .keyboardShortcut(.defaultAction)
                    .padding(16)
            }
        }
        .navigationTitle(String(localized: "Preview"))
        .frame(width: 640, height: 420)
        .presentationSizing(.fitted)
        .onAppear { selected = .sprite(.idle) }
    }
}

private enum ActionPreviewSelection: Hashable {
    case sprite(PetdexSpriteState)
    case followMouse
}

private struct AiboActionPreviewSidebar: View {
    @Binding var selection: ActionPreviewSelection

    private var listSelection: Binding<ActionPreviewSelection?> {
        Binding(
            get: { selection },
            set: { if let value = $0 { selection = value } }
        )
    }

    var body: some View {
        List(selection: listSelection) {
            ForEach(PetdexSpriteState.allCases, id: \.self) { state in
                Text(state.localizedTitle)
                    .tag(ActionPreviewSelection.sprite(state))
            }
            Text(String(localized: "Follow Mouse"))
                .badge("V2")
                .badgeProminence(.decreased)
                .tag(ActionPreviewSelection.followMouse)
        }
        .listStyle(.sidebar)
        .accessibilityLabel(String(localized: "Actions"))
    }
}

private struct AiboActionPreviewCanvas: View {
    var record: AiboLibraryRecord
    var selection: ActionPreviewSelection

    @State private var lookDirection: PetdexLookDirection?
    @State private var canvasSize: CGSize = .zero

    private static let previewSize: CGFloat = 200

    private var isFollowMouse: Bool {
        if case .followMouse = selection { return true }
        return false
    }

    private var spriteState: PetdexSpriteState {
        switch selection {
        case .sprite(let state): state
        case .followMouse: .idle
        }
    }

    private var accessibilityTitle: String {
        switch selection {
        case .sprite(let state): state.localizedTitle
        case .followMouse: String(localized: "Follow Mouse")
        }
    }

    var body: some View {
        ZStack {
            Color(nsColor: .controlBackgroundColor)
            AiboSpriteView(
                record: record,
                activity: .idle,
                spriteState: spriteState,
                size: Self.previewSize,
                lookDirection: isFollowMouse ? lookDirection : nil,
                alwaysAnimates: !isFollowMouse
            )
            .id(spriteIdentity)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .onGeometryChange(for: CGSize.self) { proxy in
            proxy.size
        } action: { size in
            canvasSize = size
        }
        .onContinuousHover { phase in
            guard isFollowMouse else { return }
            switch phase {
            case .active(let location):
                updateLook(at: location)
            case .ended:
                if lookDirection != nil { lookDirection = nil }
            }
        }
        .onChange(of: selection) { _, _ in
            lookDirection = nil
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilityTitle)
    }

    private var spriteIdentity: String {
        let selected: String
        switch selection {
        case .sprite(let state): selected = state.rawValue
        case .followMouse: selected = "follow-mouse"
        }
        return "\(record.id)-\(selected)-\(record.pixelOptimizationEnabled)"
    }

    /// Same 22.5° buckets and half-aibo deadzone as the desktop pet.
    private func updateLook(at location: CGPoint) {
        guard canvasSize.width > 0, canvasSize.height > 0 else { return }
        let next = PetdexLookDirection.resolve(
            deltaX: Double(location.x - canvasSize.width / 2),
            deltaYDown: Double(location.y - canvasSize.height / 2),
            deadzone: Double(Self.previewSize * 0.5)
        )
        if lookDirection != next {
            lookDirection = next
        }
    }
}
