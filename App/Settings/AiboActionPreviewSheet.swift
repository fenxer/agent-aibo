import AiboCore
import SwiftUI

/// Sheet: sidebar lists actions; detail plays the selected clip.
struct AiboActionPreviewSheet: View {
    var record: AiboLibraryRecord

    @Environment(\.dismiss) private var dismiss
    @State private var selected: PetdexSpriteState = .idle

    var body: some View {
        NavigationSplitView {
            AiboActionPreviewSidebar(selection: $selected)
                .navigationSplitViewColumnWidth(min: 160, ideal: 180, max: 220)
                .toolbar(removing: .sidebarToggle)
        } detail: {
            ZStack(alignment: .bottomTrailing) {
                AiboActionPreviewCanvas(record: record, state: selected)

                Button(String(localized: "Done"), action: dismiss.callAsFunction)
                    .buttonStyle(.borderedProminent)
                    .keyboardShortcut(.defaultAction)
                    .padding(16)
            }
        }
        .navigationTitle(String(localized: "Preview"))
        .frame(width: 640, height: 420)
        .presentationSizing(.fitted)
        .onAppear { selected = .idle }
    }
}

private struct AiboActionPreviewSidebar: View {
    @Binding var selection: PetdexSpriteState

    private var listSelection: Binding<PetdexSpriteState?> {
        Binding(
            get: { selection },
            set: { if let value = $0 { selection = value } }
        )
    }

    var body: some View {
        List(PetdexSpriteState.allCases, id: \.self, selection: listSelection) { state in
            Text(state.localizedTitle)
                .tag(state)
        }
        .listStyle(.sidebar)
        .accessibilityLabel(String(localized: "Actions"))
    }
}

private struct AiboActionPreviewCanvas: View {
    var record: AiboLibraryRecord
    var state: PetdexSpriteState

    var body: some View {
        ZStack {
            Color(nsColor: .controlBackgroundColor)
            AiboSpriteView(
                record: record,
                activity: .idle,
                spriteState: state,
                size: 200,
                alwaysAnimates: true
            )
            .id("\(record.id)-\(state.rawValue)-\(AppSettings.shared.pixelOptimizationEnabled)")
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(state.localizedTitle)
    }
}
