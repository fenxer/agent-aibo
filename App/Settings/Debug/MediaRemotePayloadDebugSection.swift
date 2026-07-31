#if DEBUG
import AppKit
import SwiftUI

struct MediaRemotePayloadDebugSection: View {
    @State private var monitor = MusicPlaybackMonitor.shared

    var body: some View {
        Section {
            HStack {
                Button(String(localized: "Fetch Once")) {
                    monitor.debugFetchMediaRemoteOnce()
                }
                Button(String(localized: "Copy")) {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(monitor.debugLastMediaRemoteDump, forType: .string)
                }
                .disabled(monitor.debugLastMediaRemoteDump.isEmpty)
            }

            Text("updates \(monitor.debugMediaRemoteUpdateCount) · playing \(monitor.isPlaying ? "yes" : "no")")
                .font(.caption.monospacedDigit())
                .foregroundStyle(.secondary)

            ScrollView {
                Text(monitor.debugLastMediaRemoteDump)
                    .font(.system(.caption2, design: .monospaced))
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .frame(minHeight: 120, maxHeight: 220)

            Text(
                String(
                    localized: "Live stream only pushes isPlaying (every few seconds). Fetch Once calls full Now Playing get() — title/artwork/etc. Artwork base64 is omitted here."
                )
            )
            .font(.caption)
            .foregroundStyle(.secondary)
        } header: {
            Text(String(localized: "MediaRemote Payload"))
        }
    }
}
#endif
