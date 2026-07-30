#if DEBUG
import SwiftUI

struct DistributedNotificationSnifferSection: View {
    @State private var sniffer = DistributedNotificationSniffer.shared

    var body: some View {
        Section {
            Text(
                String(
                    localized: "Catalina+ blocks wildcard (name: nil) for normal apps — that is why seen stayed 0 while Music Notes still worked. Probe explicit names instead."
                )
            )
            .font(.caption)
            .foregroundStyle(.secondary)

            Toggle(
                String(localized: "Listen for Probe Names"),
                isOn: Binding(
                    get: { sniffer.isRunning },
                    set: { running in
                        if running {
                            sniffer.start()
                        } else {
                            sniffer.stop()
                        }
                    }
                )
            )

            TextEditor(text: $sniffer.probeNamesRaw)
                .font(.system(.caption2, design: .monospaced))
                .frame(minHeight: 100, maxHeight: 160)

            HStack {
                Button(String(localized: "Reset Defaults")) {
                    sniffer.resetProbeNamesToDefaults()
                }
                Button(String(localized: "Scan NeteaseMusic.app")) {
                    sniffer.scanNetEaseMusicIfPresent()
                }
                Button(String(localized: "Apply Probe List")) {
                    sniffer.reloadSubscriptions()
                }
                .disabled(!sniffer.isRunning)
            }

            if let lastScanSummary = sniffer.lastScanSummary {
                Text(lastScanSummary)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            TextField(
                String(localized: "Log filter (| separated, optional)"),
                text: $sniffer.nameFilter
            )
            .font(.system(.caption, design: .monospaced))

            HStack {
                Button(String(localized: "Clear")) {
                    sniffer.clear()
                }
                .disabled(sniffer.entries.isEmpty && sniffer.capturedCount == 0)

                Button(String(localized: "Copy Log")) {
                    sniffer.copyLogToPasteboard()
                }
                .disabled(sniffer.entries.isEmpty)
            }

            Text(
                "subscribed \(sniffer.subscribedCount) · seen \(sniffer.capturedCount) · kept \(sniffer.entries.count) · filtered \(sniffer.droppedByFilter)"
            )
            .font(.caption.monospacedDigit())
            .foregroundStyle(.secondary)

            if sniffer.entries.isEmpty {
                Text(
                    String(
                        localized: "Start listening, play/pause Spotify (must appear), then NetEase. If only Spotify fires, NetEase is not on this bus."
                    )
                )
                .font(.caption)
                .foregroundStyle(.secondary)
            } else {
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 6) {
                        ForEach(sniffer.entries) { entry in
                            VStack(alignment: .leading, spacing: 2) {
                                Text(entry.name)
                                    .font(.system(.caption, design: .monospaced))
                                    .textSelection(.enabled)
                                if let object = entry.object {
                                    Text("object: \(object)")
                                        .font(.system(.caption2, design: .monospaced))
                                        .foregroundStyle(.secondary)
                                        .textSelection(.enabled)
                                }
                                if !entry.userInfoSummary.isEmpty {
                                    Text(entry.userInfoSummary)
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

            Text(
                String(
                    localized: "Leave Development to stop listening. Scan merges reverse-DNS strings from the NetEase binary into the probe list."
                )
            )
            .font(.caption)
            .foregroundStyle(.secondary)
        } header: {
            Text(String(localized: "Notification Sniffer"))
        }
    }
}
#endif
