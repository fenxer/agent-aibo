#if DEBUG
import AiboCore
import SwiftUI

/// DEBUG-only playtime inspector. Product UI comes later; data still accumulates.
struct PlaytimeDebugSection: View {
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
                        LabeledContent {
                            Text(verbatim: row.detail)
                                .foregroundStyle(.secondary)
                                .font(.caption)
                        } label: {
                            Text(verbatim: row.title)
                        }
                    }
                }
            }
            Text(verbatim: "Ledger is Keychain HMAC. Product surfaces stay empty until the settings design lands.")
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
                detail: "\(Self.format(seconds))\(suffix)"
            )
        }
    }

    private static func format(_ seconds: Int) -> String {
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

    private struct Row {
        var id: String
        var title: String
        var detail: String
    }
}
#endif
