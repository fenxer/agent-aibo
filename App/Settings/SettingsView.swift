import AiboCore
import AppKit
import SwiftUI

private enum SettingsPane: String, CaseIterable, Identifiable {
    case pet
    case agentHook
    case webhook
    case appearance
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
        case .appearance: String(localized: "Appearance")
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
        case .appearance: .system("paintbrush.fill")
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
        case .appearance: .purple
        case .about: Color(nsColor: .systemGray)
        #if DEBUG
        case .development: .orange
        #endif
        }
    }

    init?(_ destination: SettingsNavigator.Pane) {
        switch destination {
        case .appearance: self = .appearance
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
                ForEach([SettingsPane.pet, .agentHook, .webhook, .appearance]) { pane in
                    SettingsSidebarRow(pane: pane)
                }
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
    private let assetIconSize: CGFloat = 18 
    private let symbolIconSize: CGFloat = 16

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
                        .frame(width: assetIconSize, height: assetIconSize)
                case .system(let name):
                    Image(nsImage: Self.centeredSymbol(name, pointSize: symbolIconSize))
                        .renderingMode(.template)
                        .resizable()
                        .scaledToFit()
                        .frame(width: symbolIconSize, height: symbolIconSize)
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
        case .appearance:
            AppearanceSettingsPane()
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

private struct AppearanceSettingsPane: View {
    @Bindable private var settings = AppSettings.shared

    var body: some View {
        Form {
            Section {
                Picker(String(localized: "Theme"), selection: $settings.themeMode) {
                    ForEach(AppThemeMode.allCases) { mode in
                        Text(mode.title).tag(mode)
                    }
                }
                .pickerStyle(.radioGroup)
            } header: {
                Text(String(localized: "Theme"))
            }

            Section {
                Toggle(
                    String(localized: "Music Notes"),
                    isOn: $settings.musicNotesEnabled
                )

                Text(String(localized: "When any app reports Now Playing (Apple Music, Spotify, NetEase, …), notes float up from the pet. Uses MediaRemoteAdapter plus Music/Spotify distributed notifications as fallback."))
                    .font(.caption)
                    .foregroundStyle(.secondary)

                DisclosureGroup(String(localized: "Advanced")) {
                    TextField(
                        String(localized: "Custom notification names"),
                        text: $settings.customMusicNotificationNames,
                        prompt: Text("com.example.playerInfo"),
                        axis: .vertical
                    )
                    .lineLimit(3...6)

                    Text(String(localized: "Optional fallback: one distributed notification name per line. Payload should include Player State = Playing / Paused. Most Chinese clients do not post these — Now Playing covers them instead."))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            } header: {
                Text(String(localized: "Music"))
            }

            Section {
                Picker(String(localized: "Bubble Position"), selection: $settings.bubblePlacement) {
                    ForEach(BubblePlacement.allCases) { placement in
                        Text(placement.title).tag(placement)
                    }
                }
                .pickerStyle(.radioGroup)

                Text(String(localized: "Choose where the status popover appears relative to the pet."))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } header: {
                Text(String(localized: "Status Bubble"))
            }
        }
        .formStyle(.grouped)
        .padding()
        .settingsDetailChrome(title: SettingsPane.appearance.title)
    }
}

private struct AboutSettingsPane: View {
    var body: some View {
        Form {
            Section {
                LabeledContent(String(localized: "Version")) {
                    Text(
                        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String
                            ?? "—"
                    )
                }
            } header: {
                Text(String(localized: "aibo"))
            }
        }
        .formStyle(.grouped)
        .padding()
        .settingsDetailChrome(title: SettingsPane.about.title)
    }
}

#Preview {
    SettingsView()
}
