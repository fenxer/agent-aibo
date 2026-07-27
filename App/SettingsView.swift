import SwiftUI

private enum SettingsPane: String, CaseIterable, Identifiable {
    case appearance
    case integrations
    case about

    var id: String { rawValue }

    var title: String {
        switch self {
        case .appearance: String(localized: "Appearance")
        case .integrations: String(localized: "Integrations")
        case .about: String(localized: "About")
        }
    }

    var systemImage: String {
        switch self {
        case .appearance: "paintbrush"
        case .integrations: "link"
        case .about: "info.circle"
        }
    }
}

struct SettingsView: View {
    @State private var selection: SettingsPane? = .appearance

    var body: some View {
        NavigationSplitView {
            List(SettingsPane.allCases, selection: $selection) { pane in
                NavigationLink(value: pane) {
                    Label(pane.title, systemImage: pane.systemImage)
                }
            }
            .navigationSplitViewColumnWidth(min: 160, ideal: 180, max: 220)
            .toolbar(removing: .sidebarToggle)
        } detail: {
            Group {
                switch selection ?? .appearance {
                case .appearance:
                    AppearanceSettingsPane()
                case .integrations:
                    IntegrationsSettingsPane()
                case .about:
                    AboutSettingsPane()
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        }
        .navigationTitle(selection?.title ?? String(localized: "Settings"))
        .frame(minWidth: 680, minHeight: 420)
    }
}

private struct AppearanceSettingsPane: View {
    @Bindable private var settings = AppSettings.shared

    var body: some View {
        Form {
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
    }
}

private struct IntegrationsSettingsPane: View {
    @State private var runtime = PetRuntime.shared

    var body: some View {
        Form {
            Section {
                LabeledContent(String(localized: "Status")) {
                    Text(
                        runtime.cursorHooksInstalled
                            ? String(localized: "Installed")
                            : String(localized: "Not installed")
                    )
                }

                if runtime.cursorHooksInstalled {
                    Button(String(localized: "Uninstall Cursor Hooks")) {
                        runtime.uninstallCursorHooks()
                    }
                } else {
                    Button(String(localized: "Install Cursor Hooks")) {
                        runtime.installCursorHooks()
                    }
                }

                Text(String(localized: "Cursor has no waiting-for-user hook event yet."))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } header: {
                Text(String(localized: "Cursor"))
            }
        }
        .formStyle(.grouped)
        .padding()
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
    }
}

#Preview {
    SettingsView()
}
