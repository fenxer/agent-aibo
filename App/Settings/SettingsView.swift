import AiboCore
import AppKit
import SwiftUI

private enum SettingsPane: String, CaseIterable, Identifiable {
    case aibo
    case agentHook
    case webhook
    case extensions
    case general
    case about
    #if DEBUG
    case development
    #endif

    var id: String { rawValue }

    var title: String {
        switch self {
        case .aibo: String(localized: "Aibo")
        case .agentHook: String(localized: "Agent Hook")
        case .webhook: String(localized: "Webhook")
        case .extensions: String(localized: "Extensions")
        case .general: String(localized: "General")
        case .about: String(localized: "About")
        #if DEBUG
        case .development: String(localized: "Development")
        #endif
        }
    }

    enum Icon {
        case asset(String)
        case system(String)
    }

    var icon: Icon {
        switch self {
        case .aibo: .asset("HeartMenu")
        case .agentHook: .system("poweroutlet.type.b.fill")
        case .webhook: .system("globe")
        case .extensions: .system("square.text.square.fill")
        case .general: .system("gearshape.fill")
        case .about: .system("info.circle.fill")
        #if DEBUG
        case .development: .system("hammer.fill")
        #endif
        }
    }

    var iconColor: Color {
        switch self {
        case .aibo: .red
        case .agentHook: .blue
        case .webhook: .blue
        case .extensions: .teal
        case .general: .indigo
        case .about: Color(nsColor: .systemGray)
        #if DEBUG
        case .development: .orange
        #endif
        }
    }

    var iconSize: CGFloat {
        switch self {
        case .aibo: 18
        case .agentHook: 20
        case .webhook: 18
        case .extensions: 16
        case .general: 18
        case .about: 16
        #if DEBUG
        case .development: 16
        #endif
        }
    }

    init?(_ destination: SettingsNavigator.Pane) {
        switch destination {
        case .general: self = .general
        case .webhook: self = .webhook
        case .about: self = .about
        case .extensions: self = .extensions
        #if DEBUG
        case .development: self = .development
        #endif
        }
    }
}

private struct SettingsSidebar: View {
    @Binding var selection: SettingsPane?

    var body: some View {
        List(selection: $selection) {
            Section {
                ForEach([SettingsPane.aibo, .agentHook, .webhook]) { pane in
                    SettingsSidebarRow(pane: pane)
                }
            }
            Section {
                SettingsSidebarRow(pane: .extensions)
            }
            Section {
                SettingsSidebarRow(pane: .general)
                SettingsSidebarRow(pane: .about)
            }
            #if DEBUG
            Section {
                SettingsSidebarRow(pane: .development)
            }
            #endif
        }
        .listStyle(.sidebar)
        .environment(\.defaultMinListHeaderHeight, 0)
        // Width must come after sidebar-toggle removal. The other way around,
        // AppKit resets the column to its default (~144) and ignores ideal.
        .toolbar(removing: .sidebarToggle)
        .navigationSplitViewColumnWidth(min: 160, ideal: 200, max: 220)
    }
}

private struct SettingsSidebarRow: View {
    let pane: SettingsPane

    var body: some View {
        Label {
            Text(pane.title)
        } icon: {
            SettingsSidebarIcon(pane: pane)
        }
        .tag(pane)
    }
}

private struct SettingsSidebarIcon: View {
    let pane: SettingsPane

    private let side: CGFloat = 24

    var body: some View {
        RoundedRectangle(cornerRadius: side * 0.25, style: .continuous)
            .fill(pane.iconColor)
            .frame(width: side, height: side)
            .overlay {
                switch pane.icon {
                case .asset(let name):
                    Image(name)
                        .renderingMode(.template)
                        .resizable()
                        .scaledToFit()
                        .frame(width: pane.iconSize, height: pane.iconSize)
                case .system(let name):
                    Image(nsImage: Self.centeredSymbol(name, pointSize: pane.iconSize))
                        .renderingMode(.template)
                        .resizable()
                        .scaledToFit()
                        .frame(width: pane.iconSize, height: pane.iconSize)
                }
            }
            .foregroundStyle(.white)
    }

    /// SF Symbols keep a text-baseline alignment rect, so `Image(systemName:)`
    /// sits low in a square. Bake a plain template image to center geometrically.
    private static func centeredSymbol(_ name: String, pointSize: CGFloat) -> NSImage {
        let config = NSImage.SymbolConfiguration(pointSize: pointSize, weight: .medium)
        guard let symbol = NSImage(systemSymbolName: name, accessibilityDescription: nil)?
            .withSymbolConfiguration(config)
        else {
            return NSImage()
        }
        let baked = NSImage(size: symbol.size, flipped: false) { rect in
            symbol.draw(in: rect, from: .zero, operation: .sourceOver, fraction: 1)
            return true
        }
        baked.isTemplate = true
        return baked
    }
}

struct SettingsView: View {
    @State private var selection: SettingsPane?
    @Bindable private var navigator = SettingsNavigator.shared

    init() {
        _selection = State(initialValue: Self.initialPane())
    }

    var body: some View {
        NavigationSplitView {
            SettingsSidebar(selection: $selection)
        } detail: {
            // Detail panes own in-column sub-navigation and apply
            // `settingsDetailChrome` for the System Settings–style toolbar.
            detailRoot
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        }
        // Fill the window. Size is the window's, not this view's ideal size
        // (`SettingsWindowController` clears `sizingOptions`).
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .onAppear {
            applyPendingPane()
            navigator.rememberPane(id: selection?.rawValue)
        }
        .onChange(of: navigator.pendingPane) { _, newValue in
            guard newValue != nil else { return }
            applyPendingPane()
        }
        .onChange(of: selection) { _, newValue in
            navigator.rememberPane(id: newValue?.rawValue)
        }
    }

    /// Deep link wins over the pane from the last time Settings was open.
    private static func initialPane() -> SettingsPane {
        if let pending = SettingsNavigator.shared.pendingPane, let pane = SettingsPane(pending) {
            return pane
        }
        if let id = SettingsNavigator.shared.rememberedPaneID,
           let pane = SettingsPane(rawValue: id)
        {
            return pane
        }
        return .aibo
    }

    private func applyPendingPane() {
        guard let pending = navigator.consumePendingPane(),
              let pane = SettingsPane(pending)
        else { return }
        selection = pane
    }

    @ViewBuilder
    private var detailRoot: some View {
        switch selection ?? .aibo {
        case .aibo:
            AiboSettingsPane()
        case .agentHook:
            AgentHookSettingsPane()
        case .general:
            GeneralSettingsPane()
        case .webhook:
            WebhookSettingsPane()
        case .extensions:
            ExtensionSettingsPage()
        case .about:
            AboutSettingsPane()
        #if DEBUG
        case .development:
            DevelopmentSettingsPane()
        #endif
        }
    }
}

#Preview {
    SettingsView()
}
