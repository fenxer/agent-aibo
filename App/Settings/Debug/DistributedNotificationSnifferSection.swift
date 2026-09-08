#if DEBUG
import SwiftUI

struct DistributedNotificationSnifferSection: View {
    @State private var sniffer = DistributedNotificationSniffer.shared

    var body: some View {
        Section {
            Text(verbatim: "Catalina+ blocks wildcard (name: nil) for normal apps — that is why seen stayed 0 while Music Notes still worked. Probe explicit names instead.")
                .font(.caption)
                .foregroundStyle(.secondary)

            Toggle(isOn: listenBinding) {
                Text(verbatim: "Listen for Probe Names")
            }

            TextEditor(text: $sniffer.probeNamesRaw)
                .font(.system(.caption2, design: .monospaced))
                .frame(minHeight: 100, maxHeight: 160)

            HStack {
                Button {
                    sniffer.resetProbeNamesToDefaults()
                } label: {
                    Text(verbatim: "Reset Defaults")
                }
                Button {
                    sniffer.scanNetEaseMusicIfPresent()
                } label: {
                    Text(verbatim: "Scan NeteaseMusic.app")
                }
                Button {
                    sniffer.reloadSubscriptions()
                } label: {
                    Text(verbatim: "Apply Probe List")
                }
                .disabled(!sniffer.isRunning)
            }

            if let lastScanSummary = sniffer.lastScanSummary {
                Text(verbatim: lastScanSummary)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            TextField(text: $sniffer.nameFilter) {
                Text(verbatim: "Log filter (| separated, optional)")
            }
            .font(.system(.caption, design: .monospaced))

            HStack {
                Button {
                    sniffer.clear()
                } label: {
                    Text(verbatim: "Clear")
                }
                .disabled(sniffer.entries.isEmpty && sniffer.capturedCount == 0)

                Button {
                    sniffer.copyLogToPasteboard()
                } label: {
                    Text(verbatim: "Copy Log")
                }
                .disabled(sniffer.entries.isEmpty)
            }

            Text(
                verbatim: "subscribed \(sniffer.subscribedCount) · seen \(sniffer.capturedCount) · kept \(sniffer.entries.count) · filtered \(sniffer.droppedByFilter)"
            )
            .font(.caption.monospacedDigit())
            .foregroundStyle(.secondary)

            if sniffer.entries.isEmpty {
                Text(verbatim: "Start listening, play/pause Spotify (must appear), then NetEase. If only Spotify fires, NetEase is not on this bus.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else {
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 6) {
                        ForEach(sniffer.entries) { entry in
                            VStack(alignment: .leading, spacing: 2) {
                                Text(verbatim: entry.name)
                                    .font(.system(.caption, design: .monospaced))
                                    .textSelection(.enabled)
                                if let object = entry.object {
                                    Text(verbatim: "object: \(object)")
                                        .font(.system(.caption2, design: .monospaced))
                                        .foregroundStyle(.secondary)
                                        .textSelection(.enabled)
                                }
                                if !entry.userInfoSummary.isEmpty {
                                    Text(verbatim: entry.userInfoSummary)
                                        .font(.system(.caption2, design: .monospaced))
                                        .foregroundStyle(.secondary)
                                        .textSelection(.enabled)
                                }
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)
                        }
                    }
                }
                .frame(minHeight: 160, maxHeight: 280)
            }

            Text(verbatim: "Leave Development to stop listening. Scan merges reverse-DNS strings from the NetEase binary into the probe list.")
                .font(.caption)
                .foregroundStyle(.secondary)
        } header: {
            Text(verbatim: "Notification Sniffer")
        }
    }

    private var listenBinding: Binding<Bool> {
        Binding(
            get: { sniffer.isRunning },
            set: { running in
                if running {
                    sniffer.start()
                } else {
                    sniffer.stop()
                }
            }
        )
    }
}
#endif
