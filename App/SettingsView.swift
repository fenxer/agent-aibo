import SwiftUI

struct SettingsView: View {
    @State private var runtime = PetRuntime.shared

    var body: some View {
        Form {
            Section(String(localized: "Cursor Hooks")) {
                LabeledContent(String(localized: "Status")) {
                    Text(
                        runtime.cursorHooksInstalled
                            ? String(localized: "Installed")
                            : String(localized: "Not installed")
                    )
                }

                if runtime.cursorHooksInstalled {
                    Button(String(localized: "Uninstall")) {
                        runtime.uninstallCursorHooks()
                    }
                } else {
                    Button(String(localized: "Install")) {
                        runtime.installCursorHooks()
                    }
                }

                Text(String(localized: "Cursor has no waiting-for-user hook event yet."))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section(String(localized: "About")) {
                LabeledContent(String(localized: "Version")) {
                    Text(
                        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String
                            ?? "—"
                    )
                }
            }
        }
        .formStyle(.grouped)
        .frame(width: 420, height: 260)
        .navigationTitle(String(localized: "Settings"))
    }
}

#Preview {
    SettingsView()
}
