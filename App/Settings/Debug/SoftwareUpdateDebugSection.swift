#if DEBUG
import SwiftUI

struct SoftwareUpdateDebugSection: View {
    private var updates = SoftwareUpdateController.shared

    var body: some View {
        Section {
            HStack {
                Button {
                    updates.debugShowAvailableUpdate()
                } label: {
                    Text(verbatim: "Show Update Available")
                }

                Button {
                    updates.debugShowUpToDate()
                } label: {
                    Text(verbatim: "Show Up to Date")
                }

                Button {
                    updates.debugClearPreview()
                } label: {
                    Text(verbatim: "Clear Pending Update")
                }
            }

            Text(verbatim: "Stand-in dialogs, not a real Sparkle download. Skip or Remind Later leaves v9.9.9 New and Update Now on the About page. Install does nothing.")
                .font(.caption)
                .foregroundStyle(.secondary)
        } header: {
            Text(verbatim: "Software Update")
        }
    }
}
#endif
