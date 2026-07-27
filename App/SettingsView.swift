import SwiftUI

struct SettingsView: View {
    var body: some View {
        Form {
            LabeledContent(String(localized: "Version")) {
                Text(Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "—")
            }
        }
        .formStyle(.grouped)
        .frame(width: 360, height: 160)
        .navigationTitle(String(localized: "Settings"))
    }
}

#Preview {
    SettingsView()
}
