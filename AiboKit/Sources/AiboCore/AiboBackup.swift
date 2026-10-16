import Foundation

public enum AiboBackupError: Error, Equatable, Sendable {
    case unreadable
    case unsupportedFormat
    case invalidContents
    case unsafePath
    case ioFailed
}

public struct AiboBackupColor: Codable, Equatable, Sendable {
    public var red: Double
    public var green: Double
    public var blue: Double
    public var alpha: Double

    public init(red: Double, green: Double, blue: Double, alpha: Double) {
        self.red = Self.unit(red)
        self.green = Self.unit(green)
        self.blue = Self.unit(blue)
        self.alpha = Self.unit(alpha)
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        red = Self.unit(try container.decode(Double.self, forKey: .red))
        green = Self.unit(try container.decode(Double.self, forKey: .green))
        blue = Self.unit(try container.decode(Double.self, forKey: .blue))
        alpha = Self.unit(try container.decode(Double.self, forKey: .alpha))
    }

    private static func unit(_ value: Double) -> Double {
        guard value.isFinite else { return 0 }
        return min(max(value, 0), 1)
    }
}

/// Preferences written into a backup. Screen identity stays on the Mac that saved it.
public struct AiboBackupSettings: Codable, Equatable, Sendable {
    public var themeMode: String
    public var languageMode: String
    public var bubbleGlassStyle: String
    public var bubbleGlassTint: AiboBackupColor?
    public var cursorBubbleGlassStyle: String
    public var codexBubbleGlassStyle: String
    public var deepseekBubbleGlassStyle: String
    public var cursorBubbleGlassTint: AiboBackupColor?
    public var codexBubbleGlassTint: AiboBackupColor?
    public var deepseekBubbleGlassTint: AiboBackupColor?
    public var cursorCapsuleColor: AiboBackupColor?
    public var codexCapsuleColor: AiboBackupColor?
    public var deepseekCapsuleColor: AiboBackupColor?
    public var codexPlanProgressShaderEnabled: Bool
    public var codexPlanProgressShaderPrimary: AiboBackupColor?
    public var deepseekPlanProgressShaderEnabled: Bool
    public var deepseekPlanProgressShaderPrimary: AiboBackupColor?
    public var restoreLastAiboPosition: Bool
    public var hideWhenFullscreen: Bool
    public var disableMouseTracking: Bool
    public var mouseShakeDodgeEnabled: Bool
    /// Center of the aibo inside the display's visible frame, 0…1. Nil until the user has moved it.
    public var centerXPercent: Double?
    public var centerYPercent: Double?
    public var musicNotesEnabled: Bool
    public var musicNotesColorMode: String
    public var musicNotesCustomColor: AiboBackupColor
    public var customMusicNotificationNames: String
    public var webhookEnabled: Bool
    public var webhookPort: Int
    public var webhookDismissMode: String
    public var webhookAutoDismissSeconds: Int
    public var publicWebhookURL: String
    public var hookSprites: HookSpriteMappingFile
    public var actionSprites: [String: String]

    public init(
        themeMode: String,
        languageMode: String,
        bubbleGlassStyle: String,
        bubbleGlassTint: AiboBackupColor?,
        cursorBubbleGlassStyle: String,
        codexBubbleGlassStyle: String,
        deepseekBubbleGlassStyle: String,
        cursorBubbleGlassTint: AiboBackupColor?,
        codexBubbleGlassTint: AiboBackupColor?,
        deepseekBubbleGlassTint: AiboBackupColor?,
        cursorCapsuleColor: AiboBackupColor?,
        codexCapsuleColor: AiboBackupColor?,
        deepseekCapsuleColor: AiboBackupColor?,
        codexPlanProgressShaderEnabled: Bool,
        codexPlanProgressShaderPrimary: AiboBackupColor?,
        deepseekPlanProgressShaderEnabled: Bool,
        deepseekPlanProgressShaderPrimary: AiboBackupColor?,
        restoreLastAiboPosition: Bool,
        hideWhenFullscreen: Bool,
        disableMouseTracking: Bool,
        mouseShakeDodgeEnabled: Bool,
        centerXPercent: Double?,
        centerYPercent: Double?,
        musicNotesEnabled: Bool,
        musicNotesColorMode: String,
        musicNotesCustomColor: AiboBackupColor,
        customMusicNotificationNames: String,
        webhookEnabled: Bool,
        webhookPort: Int,
        webhookDismissMode: String,
        webhookAutoDismissSeconds: Int,
        publicWebhookURL: String,
        hookSprites: HookSpriteMappingFile,
        actionSprites: [String: String]
    ) {
        self.themeMode = themeMode
        self.languageMode = languageMode
        self.bubbleGlassStyle = bubbleGlassStyle
        self.bubbleGlassTint = bubbleGlassTint
        self.cursorBubbleGlassStyle = cursorBubbleGlassStyle
        self.codexBubbleGlassStyle = codexBubbleGlassStyle
        self.deepseekBubbleGlassStyle = deepseekBubbleGlassStyle
        self.cursorBubbleGlassTint = cursorBubbleGlassTint
        self.codexBubbleGlassTint = codexBubbleGlassTint
        self.deepseekBubbleGlassTint = deepseekBubbleGlassTint
        self.cursorCapsuleColor = cursorCapsuleColor
        self.codexCapsuleColor = codexCapsuleColor
        self.deepseekCapsuleColor = deepseekCapsuleColor
        self.codexPlanProgressShaderEnabled = codexPlanProgressShaderEnabled
        self.codexPlanProgressShaderPrimary = codexPlanProgressShaderPrimary
        self.deepseekPlanProgressShaderEnabled = deepseekPlanProgressShaderEnabled
        self.deepseekPlanProgressShaderPrimary = deepseekPlanProgressShaderPrimary
        self.restoreLastAiboPosition = restoreLastAiboPosition
        self.hideWhenFullscreen = hideWhenFullscreen
        self.disableMouseTracking = disableMouseTracking
        self.mouseShakeDodgeEnabled = mouseShakeDodgeEnabled
        self.centerXPercent = centerXPercent
        self.centerYPercent = centerYPercent
        self.musicNotesEnabled = musicNotesEnabled
        self.musicNotesColorMode = musicNotesColorMode
        self.musicNotesCustomColor = musicNotesCustomColor
        self.customMusicNotificationNames = customMusicNotificationNames
        self.webhookEnabled = webhookEnabled
        self.webhookPort = webhookPort
        self.webhookDismissMode = webhookDismissMode
        self.webhookAutoDismissSeconds = webhookAutoDismissSeconds
        self.publicWebhookURL = publicWebhookURL
        self.hookSprites = hookSprites
        self.actionSprites = actionSprites
    }

    /// Structural checks that do not depend on UI enums.
    public func hasCoherentValues(
        autoDismissRange: ClosedRange<Int> = 1...600
    ) -> Bool {
        guard webhookPort > 0, webhookPort <= Int(UInt16.max) else { return false }
        guard autoDismissRange.contains(webhookAutoDismissSeconds) else { return false }
        switch (centerXPercent, centerYPercent) {
        case (nil, nil):
            break
        case let (x?, y?):
            guard x.isFinite, y.isFinite, (0...1).contains(x), (0...1).contains(y) else { return false }
        default:
            return false
        }
        return true
    }

    /// How many saved preferences differ. The saved position counts as one item.
    public func differenceCount(from other: AiboBackupSettings) -> Int {
        var count = 0
        if themeMode != other.themeMode { count += 1 }
        if languageMode != other.languageMode { count += 1 }
        if bubbleGlassStyle != other.bubbleGlassStyle { count += 1 }
        if bubbleGlassTint != other.bubbleGlassTint { count += 1 }
        if cursorBubbleGlassStyle != other.cursorBubbleGlassStyle { count += 1 }
        if codexBubbleGlassStyle != other.codexBubbleGlassStyle { count += 1 }
        if deepseekBubbleGlassStyle != other.deepseekBubbleGlassStyle { count += 1 }
        if cursorBubbleGlassTint != other.cursorBubbleGlassTint { count += 1 }
        if codexBubbleGlassTint != other.codexBubbleGlassTint { count += 1 }
        if deepseekBubbleGlassTint != other.deepseekBubbleGlassTint { count += 1 }
        if cursorCapsuleColor != other.cursorCapsuleColor { count += 1 }
        if codexCapsuleColor != other.codexCapsuleColor { count += 1 }
        if deepseekCapsuleColor != other.deepseekCapsuleColor { count += 1 }
        if codexPlanProgressShaderEnabled != other.codexPlanProgressShaderEnabled { count += 1 }
        if codexPlanProgressShaderPrimary != other.codexPlanProgressShaderPrimary { count += 1 }
        if deepseekPlanProgressShaderEnabled != other.deepseekPlanProgressShaderEnabled { count += 1 }
        if deepseekPlanProgressShaderPrimary != other.deepseekPlanProgressShaderPrimary { count += 1 }
        if restoreLastAiboPosition != other.restoreLastAiboPosition { count += 1 }
        if hideWhenFullscreen != other.hideWhenFullscreen { count += 1 }
        if disableMouseTracking != other.disableMouseTracking { count += 1 }
        if mouseShakeDodgeEnabled != other.mouseShakeDodgeEnabled { count += 1 }
        if centerXPercent != other.centerXPercent || centerYPercent != other.centerYPercent { count += 1 }
        if musicNotesEnabled != other.musicNotesEnabled { count += 1 }
        if musicNotesColorMode != other.musicNotesColorMode { count += 1 }
        if musicNotesCustomColor != other.musicNotesCustomColor { count += 1 }
        if customMusicNotificationNames != other.customMusicNotificationNames { count += 1 }
        if webhookEnabled != other.webhookEnabled { count += 1 }
        if webhookPort != other.webhookPort { count += 1 }
        if webhookDismissMode != other.webhookDismissMode { count += 1 }
        if webhookAutoDismissSeconds != other.webhookAutoDismissSeconds { count += 1 }
        if publicWebhookURL != other.publicWebhookURL { count += 1 }
        if hookSprites != other.hookSprites { count += 1 }
        if actionSprites != other.actionSprites { count += 1 }
        return count
    }
}

public struct AiboBackupManifest: Codable, Equatable, Sendable {
    public var format: String
    public var formatVersion: Int
    public var exportedAt: Date
    public var appVersion: String

    public init(format: String, formatVersion: Int, exportedAt: Date, appVersion: String) {
        self.format = format
        self.formatVersion = formatVersion
        self.exportedAt = exportedAt
        self.appVersion = appVersion
    }
}

/// Settled companion time. No open session: in-progress time is folded in before export.
public struct AiboBackupPlaytimeFile: Codable, Equatable, Sendable {
    public var records: [PlaytimeRecord]
    public var daysByAiboID: [String: [String: Int]]

    public init(records: [PlaytimeRecord], daysByAiboID: [String: [String: Int]]) {
        self.records = records
        self.daysByAiboID = daysByAiboID
    }
}

public enum AiboBackupPlaytimeMode: Sendable, Equatable, Hashable {
    /// Same aibo, same local day: add the seconds. Lifetime becomes the sum of the merged days.
    case add
    /// The backup's ledger replaces this Mac's ledger.
    case replace
    /// Leave this Mac's ledger as it is.
    case skip
}

public enum AiboBackupPlaytimeMerge {
    public static func merge(
        local: AiboBackupPlaytimeFile,
        incoming: AiboBackupPlaytimeFile,
        mode: AiboBackupPlaytimeMode,
        now: Date
    ) -> AiboBackupPlaytimeFile {
        switch mode {
        case .replace:
            return AiboBackupPlaytimeFile(
                records: incoming.records,
                daysByAiboID: nonNegativeDays(incoming.daysByAiboID)
            )
        case .add:
            return add(local: local, incoming: incoming, now: now)
        case .skip:
            return local
        }
    }

    /// Lifetime seconds are the sum of daily buckets after the add.
    /// Seconds that exist only on `totalSeconds` and not in a day are dropped.
    private static func add(
        local: AiboBackupPlaytimeFile,
        incoming: AiboBackupPlaytimeFile,
        now: Date
    ) -> AiboBackupPlaytimeFile {
        var days = nonNegativeDays(incoming.daysByAiboID)
        let localDays = nonNegativeDays(local.daysByAiboID)
        var records = incoming.records
        let epoch = PlaytimeSnapshot.epoch(from: now)

        for localRecord in local.records {
            if let target = match(localRecord, in: records) {
                var bucket = days[target.id] ?? [:]
                for (day, seconds) in localDays[localRecord.id] ?? [:] {
                    bucket[day] = saturatingAdd(bucket[day] ?? 0, seconds)
                }
                if bucket.isEmpty {
                    days.removeValue(forKey: target.id)
                } else {
                    days[target.id] = bucket
                }
            } else {
                var bucket = days[localRecord.id] ?? [:]
                for (day, seconds) in localDays[localRecord.id] ?? [:] {
                    bucket[day] = saturatingAdd(bucket[day] ?? 0, seconds)
                }
                if bucket.isEmpty {
                    days.removeValue(forKey: localRecord.id)
                } else {
                    days[localRecord.id] = bucket
                }
                var orphan = localRecord
                orphan.isOrphan = true
                records.append(orphan)
            }
        }

        for index in records.indices {
            records[index].totalSeconds = totalSeconds(in: days[records[index].id] ?? [:])
            records[index].updatedAtEpoch = epoch
        }
        return AiboBackupPlaytimeFile(records: records, daysByAiboID: days)
    }

    /// Built-in matches its fixed id. Petdex matches slug. Anything still unmatched matches display name.
    private static func match(_ local: PlaytimeRecord, in incoming: [PlaytimeRecord]) -> PlaytimeRecord? {
        if let exact = incoming.first(where: { $0.id == local.id }) {
            return exact
        }
        if local.kind == .builtInDefault || local.id == AiboLibraryDefaults.builtInID {
            return nil
        }
        if let slug = local.slug?.trimmingCharacters(in: .whitespacesAndNewlines), !slug.isEmpty,
           let hit = incoming.first(where: { $0.slug == slug })
        {
            return hit
        }
        return incoming.first { candidate in
            candidate.kind != .builtInDefault
                && candidate.id != AiboLibraryDefaults.builtInID
                && AiboLibraryNaming.displayNamesMatch(candidate.displayName, local.displayName)
        }
    }

    private static func nonNegativeDays(_ days: [String: [String: Int]]) -> [String: [String: Int]] {
        var cleaned: [String: [String: Int]] = [:]
        for (id, book) in days {
            let kept = book.filter { $0.value > 0 }
            if !kept.isEmpty {
                cleaned[id] = kept
            }
        }
        return cleaned
    }

    private static func totalSeconds(in days: [String: Int]) -> Int {
        days.values.reduce(0) { saturatingAdd($0, $1) }
    }

    private static func saturatingAdd(_ lhs: Int, _ rhs: Int) -> Int {
        let (sum, overflow) = lhs.addingReportingOverflow(max(0, rhs))
        return overflow ? Int.max : sum
    }
}

/// What to do with backup aibos whose display name already exists on this Mac.
/// Matching is exact: case and spaces both count.
public enum AiboBackupDuplicateImport: Sendable, Equatable, Hashable {
    /// Copy the aibo and append `1` (then `2`, …) so the name stays unique.
    case add
    /// The backup's files and appearance replace the aibo that already has this name.
    case replace
    /// Leave the existing aibo, and do not bring the backup's copy in.
    case skip
}

public enum AiboBackupLibraryImport {
    public struct Summary: Equatable, Sendable {
        public var newCount: Int
        public var duplicateCount: Int
    }

    public struct Copy: Equatable, Sendable {
        public var fromRelativePath: String
        public var toRelativePath: String

        public init(fromRelativePath: String, toRelativePath: String) {
            self.fromRelativePath = fromRelativePath
            self.toRelativePath = toRelativePath
        }
    }

    public struct Result: Equatable, Sendable {
        public var records: [AiboLibraryRecord]
        public var builtInHidden: Bool
        public var copies: [Copy]
        public var removals: [String]
    }

    /// Installable aibos only. The built-in image is not a file in the backup.
    public static func summary(
        localRecords: [AiboLibraryRecord],
        incomingRecords: [AiboLibraryRecord]
    ) -> Summary {
        let localNames = Set(localRecords.map(\.displayName))
        var newCount = 0
        var duplicateCount = 0
        for record in incomingRecords where record.kind != .builtInDefault && !record.relativePath.isEmpty {
            if localNames.contains(record.displayName) {
                duplicateCount += 1
            } else {
                newCount += 1
            }
        }
        return Summary(newCount: newCount, duplicateCount: duplicateCount)
    }

    /// Names that are not already on this Mac are always added.
    /// A second incoming aibo with the same new name gets a numeric suffix so the result stays exact-unique.
    public static func merge(
        localRecords: [AiboLibraryRecord],
        localBuiltInHidden: Bool,
        incoming: AiboLibraryFile,
        duplicates: AiboBackupDuplicateImport
    ) -> Result {
        var records = localRecords
        var hidden = localBuiltInHidden
        var usedNames = Set(localRecords.map(\.displayName))
        var usedIDs = Set(localRecords.map(\.id))
        var usedPaths = Set(localRecords.map(\.relativePath).filter { !$0.isEmpty })
        let localNames = Set(localRecords.map(\.displayName))
        var copies: [Copy] = []
        var removals: [String] = []

        for incomingRecord in incoming.records where incomingRecord.kind != .builtInDefault && !incomingRecord.relativePath.isEmpty {
            if localNames.contains(incomingRecord.displayName) {
                switch duplicates {
                case .skip:
                    continue
                case .add:
                    addCopy(
                        incomingRecord,
                        records: &records,
                        usedNames: &usedNames,
                        usedIDs: &usedIDs,
                        usedPaths: &usedPaths,
                        copies: &copies
                    )
                case .replace:
                    if let index = records.firstIndex(where: {
                        $0.kind != .builtInDefault && $0.displayName == incomingRecord.displayName
                    }) {
                        replace(
                            local: records[index],
                            with: incomingRecord,
                            at: index,
                            records: &records,
                            usedPaths: &usedPaths,
                            copies: &copies,
                            removals: &removals
                        )
                    } else {
                        addCopy(
                            incomingRecord,
                            records: &records,
                            usedNames: &usedNames,
                            usedIDs: &usedIDs,
                            usedPaths: &usedPaths,
                            copies: &copies
                        )
                    }
                }
            } else {
                addNew(
                    incomingRecord,
                    records: &records,
                    usedNames: &usedNames,
                    usedIDs: &usedIDs,
                    usedPaths: &usedPaths,
                    copies: &copies
                )
            }
        }

        if duplicates == .replace,
           let incomingBuiltIn = incoming.records.first(where: { $0.id == AiboLibraryDefaults.builtInID }),
           let index = records.firstIndex(where: {
               $0.id == AiboLibraryDefaults.builtInID && $0.displayName == incomingBuiltIn.displayName
           })
        {
            records[index].bubblePlacement = incomingBuiltIn.bubblePlacement
            records[index].bubbleDistance = incomingBuiltIn.bubbleDistance
            records[index].scalePercent = incomingBuiltIn.scalePercent
            records[index].pixelOptimizationEnabled = incomingBuiltIn.pixelOptimizationEnabled
            hidden = incoming.builtInHidden
        }

        return Result(records: records, builtInHidden: hidden, copies: copies, removals: removals)
    }

    /// `Name1`, or `Name2` when `Name1` is already taken. Comparison is exact.
    public static func suffixedDisplayName(_ name: String, taken: Set<String>) -> String {
        var suffix = 1
        while taken.contains(name + String(suffix)) {
            suffix += 1
        }
        return name + String(suffix)
    }

    private static func addNew(
        _ incoming: AiboLibraryRecord,
        records: inout [AiboLibraryRecord],
        usedNames: inout Set<String>,
        usedIDs: inout Set<String>,
        usedPaths: inout Set<String>,
        copies: inout [Copy]
    ) {
        var record = incoming
        if usedNames.contains(record.displayName) {
            record.displayName = suffixedDisplayName(record.displayName, taken: usedNames)
        }
        usedNames.insert(record.displayName)
        record.id = freshID(preferred: record.id, kind: record.kind, used: &usedIDs)
        record.relativePath = freshPath(record.relativePath, used: &usedPaths)
        records.append(record)
        copies.append(Copy(fromRelativePath: incoming.relativePath, toRelativePath: record.relativePath))
    }

    private static func addCopy(
        _ incoming: AiboLibraryRecord,
        records: inout [AiboLibraryRecord],
        usedNames: inout Set<String>,
        usedIDs: inout Set<String>,
        usedPaths: inout Set<String>,
        copies: inout [Copy]
    ) {
        var record = incoming
        record.displayName = suffixedDisplayName(record.displayName, taken: usedNames)
        usedNames.insert(record.displayName)
        record.id = freshID(preferred: record.id, kind: record.kind, used: &usedIDs)
        record.relativePath = freshPath(record.relativePath, used: &usedPaths)
        records.append(record)
        copies.append(Copy(fromRelativePath: incoming.relativePath, toRelativePath: record.relativePath))
    }

    private static func replace(
        local: AiboLibraryRecord,
        with incoming: AiboLibraryRecord,
        at index: Int,
        records: inout [AiboLibraryRecord],
        usedPaths: inout Set<String>,
        copies: inout [Copy],
        removals: inout [String]
    ) {
        if !local.relativePath.isEmpty {
            removals.append(local.relativePath)
            usedPaths.remove(local.relativePath)
        }
        var record = incoming
        record.id = local.id
        record.displayName = local.displayName
        record.installedAt = local.installedAt
        record.relativePath = freshPath(incoming.relativePath, used: &usedPaths)
        records[index] = record
        copies.append(Copy(fromRelativePath: incoming.relativePath, toRelativePath: record.relativePath))
    }

    private static func freshID(preferred: String, kind: AiboKind, used: inout Set<String>) -> String {
        if !preferred.isEmpty, !used.contains(preferred) {
            used.insert(preferred)
            return preferred
        }
        let prefix = kind == .petdex ? "petdex" : "static"
        var id = "\(prefix).\(UUID().uuidString)"
        while used.contains(id) {
            id = "\(prefix).\(UUID().uuidString)"
        }
        used.insert(id)
        return id
    }

    private static func freshPath(_ relative: String, used: inout Set<String>) -> String {
        if !used.contains(relative) {
            used.insert(relative)
            return relative
        }
        let url = URL(fileURLWithPath: relative)
        let ext = url.pathExtension
        let base = url.deletingPathExtension().path
        var suffix = 2
        while true {
            let candidate = ext.isEmpty ? "\(base)-\(suffix)" : "\(base)-\(suffix).\(ext)"
            if !used.contains(candidate) {
                used.insert(candidate)
                return candidate
            }
            suffix += 1
        }
    }
}
