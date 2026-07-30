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
                    localized: "Live stream updates when Appearance → Music Notes is on. Artwork base64 is omitted. Fetch Once works even if the stream is idle."
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
