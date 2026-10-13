#if DEBUG
import AiboCore
import SwiftUI

/// DEBUG-only playtime inspector. Product UI comes later; data still accumulates.
struct PlaytimeDebugSection: View {
    var onOpen: (String) -> Void

    @State private var store = PlaytimeStore.shared
    @State private var library = AiboLibraryStore.shared

    var body: some View {
        Section {
            TimelineView(.periodic(from: .now, by: 1)) { context in
                let rows = displayRows(now: context.date)
                if rows.isEmpty {
                    Text(verbatim: "No records yet. Time accrues while the selected aibo is on the desktop.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(rows, id: \.id) { row in
                        Button {
                            onOpen(row.id)
                        } label: {
                            HStack(spacing: 8) {
                                Text(verbatim: row.title)
                                    .foregroundStyle(.primary)
                                    .lineLimit(1)
                                Spacer(minLength: 8)
                                Text(verbatim: row.detail)
                                    .foregroundStyle(.secondary)
                                    .font(.caption)
                                    .lineLimit(1)
                                Image(systemName: "chevron.right")
                                    .font(.caption.weight(.semibold))
                                    .foregroundStyle(.tertiary)
                            }
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
            Text(verbatim: "Lifetime is Keychain HMAC. Daily totals are Application Support/aibo/playtime-daily.json. Product calendar stays empty until the settings design lands.")
                .font(.caption)
                .foregroundStyle(.secondary)
        } header: {
            Text(verbatim: "Playtime")
        }
    }

    private func displayRows(now: Date) -> [Row] {
        let records = store.snapshot.records.sorted { lhs, rhs in
            if lhs.isOrphan != rhs.isOrphan { return !lhs.isOrphan && rhs.isOrphan }
            return lhs.displayName.localizedCaseInsensitiveCompare(rhs.displayName) == .orderedAscending
        }
        return records.map { record in
            let seconds = store.displayedSeconds(id: record.id, now: now)
            let running = store.snapshot.openSession?.aiboID == record.id
            let selected = library.selectedID == record.id
            var flags: [String] = []
            if running { flags.append("timing") }
            else if selected { flags.append("selected") }
            if record.isOrphan { flags.append("orphan") }
            if let slug = record.slug, !slug.isEmpty { flags.append(slug) }
            let suffix = flags.isEmpty ? "" : " · \(flags.joined(separator: " · "))"
            return Row(
                id: record.id,
                title: record.displayName,
                detail: "\(PlaytimeDebugFormat.seconds(seconds))\(suffix)"
            )
        }
    }

    private struct Row {
        var id: String
        var title: String
        var detail: String
    }
}

struct PlaytimeDebugDetail: View {
    var aiboID: String
    var onBack: () -> Void

    @State private var store = PlaytimeStore.shared

    var body: some View {
        TimelineView(.periodic(from: .now, by: 1)) { context in
            detailForm(now: context.date)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .settingsDetailChrome(title: title, canGoBack: true, onBack: onBack)
        .onChange(of: store.snapshot.records.map(\.id)) { _, ids in
            if !ids.contains(aiboID) {
                onBack()
            }
        }
    }

    private var title: String {
        store.snapshot.records.first { $0.id == aiboID }?.displayName ?? "Playtime"
    }

    private func detailForm(now: Date) -> some View {
        let seconds = store.displayedSeconds(id: aiboID, now: now)
        let days = store.displayedDayKeys(id: aiboID, now: now).map { key in
            DayRow(
                key: key,
                detail: PlaytimeDebugFormat.seconds(
                    store.displayedDailySeconds(id: aiboID, dayKey: key, now: now)
                )
            )
        }
        return Form {
            Section {
                LabeledContent {
                    Text(verbatim: PlaytimeDebugFormat.seconds(seconds))
                        .foregroundStyle(.secondary)
                        .font(.caption)
                        .monospacedDigit()
                } label: {
                    Text(verbatim: "Total")
                }
                if days.isEmpty {
                    Text(verbatim: "No daily totals yet.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(days, id: \.key) { day in
                        LabeledContent {
                            Text(verbatim: day.detail)
                                .foregroundStyle(.secondary)
                                .font(.caption)
                                .monospacedDigit()
                        } label: {
                            Text(verbatim: day.key)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
            }
        }
        .formStyle(.grouped)
    }

    private struct DayRow {
        var key: String
        var detail: String
    }
}

private enum PlaytimeDebugFormat {
    static func seconds(_ seconds: Int) -> String {
        let hours = seconds / 3600
        let minutes = (seconds % 3600) / 60
        let remainder = seconds % 60
        if hours > 0 {
            return "\(hours)h \(minutes)m \(remainder)s"
        }
        if minutes > 0 {
            return "\(minutes)m \(remainder)s"
        }
        return "\(remainder)s"
    }
}
#endif
