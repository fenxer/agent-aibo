#if DEBUG
import SwiftUI

struct SoftwareUpdateDebugSection: View {
    private var updates = SoftwareUpdateController.shared

    var body: some View {
        Section {
            HStack {
                Button(String(localized: "Show Update Available")) {
                    updates.debugShowAvailableUpdate()
                }

                Button(String(localized: "Show Up to Date")) {
                    updates.debugShowUpToDate()
                }

                Button(String(localized: "Clear Pending Update")) {
                    updates.debugClearPreview()
                }
            }

            Text(
                String(
                    localized: "Stand-in dialogs, not a real Sparkle download. Skip or Remind Later leaves v9.9.9 New and Update Now on the About page. Install does nothing."
                )
            )
            .font(.caption)
            .foregroundStyle(.secondary)
        } header: {
            Text(String(localized: "Software Update"))
        }
    }
}
#endif
