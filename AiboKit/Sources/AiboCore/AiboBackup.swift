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
