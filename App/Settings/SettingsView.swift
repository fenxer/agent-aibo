import AiboCore
import AppKit
import SwiftUI

private enum SettingsPane: String, CaseIterable, Identifiable {
    case pet
    case agentHook
    case webhook
    case general
    case about
    #if DEBUG
    case development
    #endif

    var id: String { rawValue }

    var title: String {
        switch self {
        case .pet: String(localized: "Pet")
        case .agentHook: String(localized: "Agent Hook")
        case .webhook: String(localized: "Webhook")
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
        case .pet: .asset("HeartMenu")
        case .agentHook: .system("poweroutlet.type.b.fill")
        case .webhook: .system("globe")
        case .general: .system("gearshape.fill")
        case .about: .system("info.circle.fill")
        #if DEBUG
        case .development: .system("hammer.fill")
        #endif
        }
    }

    var iconColor: Color {
        switch self {
        case .pet: .red
        case .agentHook: .blue
        case .webhook: .blue
        case .general: .indigo
        case .about: Color(nsColor: .systemGray)
        #if DEBUG
        case .development: .orange
        #endif
        }
    }

    var iconSize: CGFloat {
        switch self {
        case .pet: 18
        case .agentHook: 20
        case .webhook: 18
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
                ForEach([SettingsPane.pet, .agentHook, .webhook]) { pane in
                    SettingsSidebarRow(pane: pane)
                }
            }
            Section {
                SettingsSidebarRow(pane: .general)
            }
            Section {
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
        .navigationSplitViewColumnWidth(min: 160, ideal: 180, max: 220)
        .toolbar(removing: .sidebarToggle)
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
    @State private var selection: SettingsPane? = .pet
    @Bindable private var navigator = SettingsNavigator.shared

    var body: some View {
        NavigationSplitView {
            SettingsSidebar(selection: $selection)
        } detail: {
            // Detail panes own in-column sub-navigation and apply
            // `settingsDetailChrome` for the System Settings–style toolbar.
            detailRoot
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        }
        // Fixed width; unbounded max height so `.windowResizability(.contentMinSize)`
        // reports "no maximum" and the window stays user-resizable in height.
        .frame(width: AppSettings.settingsWindowWidth)
        .frame(minHeight: AppSettings.settingsWindowMinHeight, maxHeight: .infinity)
        .background { SettingsWindowConfigurator() }
        .onAppear { applyPendingPane() }
        .onChange(of: navigator.pendingPane) { _, newValue in
            guard newValue != nil else { return }
            applyPendingPane()
        }
    }

    private func applyPendingPane() {
        guard let pending = navigator.consumePendingPane(),
              let pane = SettingsPane(pending)
        else { return }
        selection = pane
    }

    @ViewBuilder
    private var detailRoot: some View {
        switch selection ?? .pet {
        case .pet:
            PetSettingsPane()
        case .agentHook:
            AgentHookSettingsPane()
        case .general:
            GeneralSettingsPane()
        case .webhook:
            WebhookSettingsPane()
        case .about:
            AboutSettingsPane()
        #if DEBUG
        case .development:
            DevelopmentSettingsPane()
                .settingsDetailChrome(title: SettingsPane.development.title)
        #endif
        }
    }
}

#Preview {
    SettingsView()
}
