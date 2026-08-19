import Foundation

/// Built-in Asset Catalog aibo (`DefaultAibo`). Always available; never persisted.
public enum AiboLibraryDefaults {
    public static let builtInID = "builtin.default"
    public static let builtInDisplayName = "Default"
}

public enum AiboKind: String, Codable, Sendable, Equatable {
    case builtInDefault
    case petdex
    case staticImage
}

/// One selectable aibo appearance. Built-in is synthesized; others come from disk.
public struct AiboLibraryRecord: Codable, Sendable, Equatable, Identifiable, Hashable {
    public static let defaultBubbleDistance: Double = 6
    public static let bubbleDistanceRange: ClosedRange<Double> = -40...40
    public static let defaultScalePercent: Double = 100
    public static let scalePercentRange: ClosedRange<Double> = 0...300

    public var id: String
    public var kind: AiboKind
    public var displayName: String
    /// Relative to `AiboPaths.aibosDirectory`. Petdex: `petdex/<slug>`; static: `static/<file>`.
    public var relativePath: String
    public var slug: String?
    /// Filename inside the petdex folder (e.g. `spritesheet.webp`).
    public var spriteFileName: String?
    public var spriteVersionNumber: Int?
    /// First time this aibo was added to the library. Omitted in older `library.json`.
    public var installedAt: Date?
    /// Origin shown in All Aibos. Petdex: page URL. Local image: nil (UI shows Local).
    public var installSource: String?
    /// Per-aibo bubble side. Default `.top`; omitted in older `library.json`.
    public var bubblePlacement: BubblePlacement
    /// Per-aibo gap to the bubble, in points. Default 6; omitted in older `library.json`.
    public var bubbleDistance: Double
    /// Per-aibo size as a percent of the 96pt base. Default 100; omitted in older `library.json`.
    public var scalePercent: Double
    /// Per-aibo integer-scale pixel-art display. Default off; omitted in older `library.json`.
    public var pixelOptimizationEnabled: Bool

    public var hasCustomAppearance: Bool {
        hasCustomBubbleLayout
            || scalePercent != Self.defaultScalePercent
            || pixelOptimizationEnabled
    }

    public var hasCustomBubbleLayout: Bool {
        bubblePlacement != .top || bubbleDistance != Self.defaultBubbleDistance
    }

    public init(
        id: String,
        kind: AiboKind,
        displayName: String,
        relativePath: String,
        slug: String? = nil,
        spriteFileName: String? = nil,
        spriteVersionNumber: Int? = nil,
        installedAt: Date? = nil,
        installSource: String? = nil,
        bubblePlacement: BubblePlacement = .top,
        bubbleDistance: Double = defaultBubbleDistance,
        scalePercent: Double = defaultScalePercent,
        pixelOptimizationEnabled: Bool = false
    ) {
        self.id = id
        self.kind = kind
        self.displayName = displayName
        self.relativePath = relativePath
        self.slug = slug
        self.spriteFileName = spriteFileName
        self.spriteVersionNumber = spriteVersionNumber
        self.installedAt = installedAt
        self.installSource = installSource
        self.bubblePlacement = bubblePlacement
        self.bubbleDistance = Self.clampedBubbleDistance(bubbleDistance)
        self.scalePercent = Self.clampedScalePercent(scalePercent)
        self.pixelOptimizationEnabled = pixelOptimizationEnabled
    }

    public static func clampedBubbleDistance(_ value: Double) -> Double {
        min(max(value.rounded(), bubbleDistanceRange.lowerBound), bubbleDistanceRange.upperBound)
    }

    public static func clampedScalePercent(_ value: Double) -> Double {
        min(max(value.rounded(), scalePercentRange.lowerBound), scalePercentRange.upperBound)
    }

    enum CodingKeys: String, CodingKey {
        case id
        case kind
        case displayName
        case relativePath
        case slug
        case spriteFileName
        case spriteVersionNumber
        case installedAt
        case installSource
        case bubblePlacement
        case bubbleDistance
        case scalePercent
        case pixelOptimizationEnabled
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(String.self, forKey: .id)
        kind = try container.decode(AiboKind.self, forKey: .kind)
        displayName = try container.decode(String.self, forKey: .displayName)
        relativePath = try container.decode(String.self, forKey: .relativePath)
        slug = try container.decodeIfPresent(String.self, forKey: .slug)
        spriteFileName = try container.decodeIfPresent(String.self, forKey: .spriteFileName)
        spriteVersionNumber = try container.decodeIfPresent(Int.self, forKey: .spriteVersionNumber)
        installedAt = try container.decodeIfPresent(Date.self, forKey: .installedAt)
        installSource = try container.decodeIfPresent(String.self, forKey: .installSource)
        if let raw = try container.decodeIfPresent(String.self, forKey: .bubblePlacement) {
            bubblePlacement = BubblePlacement(rawValue: raw) ?? .top
        } else {
            bubblePlacement = .top
        }
        if let distance = try container.decodeIfPresent(Double.self, forKey: .bubbleDistance) {
            bubbleDistance = Self.clampedBubbleDistance(distance)
        } else {
            bubbleDistance = Self.defaultBubbleDistance
        }
        if let percent = try container.decodeIfPresent(Double.self, forKey: .scalePercent) {
            scalePercent = Self.clampedScalePercent(percent)
        } else {
            scalePercent = Self.defaultScalePercent
        }
        pixelOptimizationEnabled =
            try container.decodeIfPresent(Bool.self, forKey: .pixelOptimizationEnabled) ?? false
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(kind, forKey: .kind)
        try container.encode(displayName, forKey: .displayName)
        try container.encode(relativePath, forKey: .relativePath)
        try container.encodeIfPresent(slug, forKey: .slug)
        try container.encodeIfPresent(spriteFileName, forKey: .spriteFileName)
        try container.encodeIfPresent(spriteVersionNumber, forKey: .spriteVersionNumber)
        try container.encodeIfPresent(installedAt, forKey: .installedAt)
        try container.encodeIfPresent(installSource, forKey: .installSource)
        if bubblePlacement != .top {
            try container.encode(bubblePlacement, forKey: .bubblePlacement)
        }
        if bubbleDistance != Self.defaultBubbleDistance {
            try container.encode(bubbleDistance, forKey: .bubbleDistance)
        }
        if scalePercent != Self.defaultScalePercent {
            try container.encode(scalePercent, forKey: .scalePercent)
        }
        if pixelOptimizationEnabled {
            try container.encode(true, forKey: .pixelOptimizationEnabled)
        }
    }

    public static var builtInDefault: AiboLibraryRecord {
        AiboLibraryRecord(
            id: AiboLibraryDefaults.builtInID,
            kind: .builtInDefault,
            displayName: AiboLibraryDefaults.builtInDisplayName,
            relativePath: ""
        )
    }

    /// Built-in Default has no on-disk files; hiding it only drops it from the list.
    public var removesOnDiskFiles: Bool {
        kind != .builtInDefault
    }
}

/// On-disk `library.json` shape. Built-in Default is included when renamed or its bubble layout is custom.
public struct AiboLibraryFile: Codable, Sendable, Equatable {
    public var selectedID: String
    public var records: [AiboLibraryRecord]
    /// When true, Default is omitted from the library as long as another aibo remains.
    public var builtInHidden: Bool

    enum CodingKeys: String, CodingKey {
        case selectedID
        case records
        case builtInHidden
    }

    public init(
        selectedID: String = AiboLibraryDefaults.builtInID,
        records: [AiboLibraryRecord] = [],
        builtInHidden: Bool = false
    ) {
        self.selectedID = selectedID
        self.records = records
        self.builtInHidden = builtInHidden
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        selectedID = try container.decode(String.self, forKey: .selectedID)
        records = try container.decode([AiboLibraryRecord].self, forKey: .records)
        builtInHidden = try container.decodeIfPresent(Bool.self, forKey: .builtInHidden) ?? false
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(selectedID, forKey: .selectedID)
        try container.encode(records, forKey: .records)
        if builtInHidden {
            try container.encode(true, forKey: .builtInHidden)
        }
    }
}

public enum AiboLibraryCodec {
    public static func decode(_ data: Data) throws -> AiboLibraryFile {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try decoder.decode(AiboLibraryFile.self, from: data)
    }

    public static func encode(_ file: AiboLibraryFile) throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        return try encoder.encode(file)
    }

    /// Merges disk file with the built-in default and resolves a valid selection.
    public static func snapshot(
        from file: AiboLibraryFile
    ) -> (selectedID: String, records: [AiboLibraryRecord], builtInHidden: Bool) {
        var builtIn = AiboLibraryRecord.builtInDefault
        if let saved = file.records.first(where: { $0.id == AiboLibraryDefaults.builtInID }) {
            if let name = AiboLibraryNaming.normalizedDisplayName(saved.displayName) {
                builtIn.displayName = name
            }
            builtIn.bubblePlacement = saved.bubblePlacement
            builtIn.bubbleDistance = saved.bubbleDistance
            builtIn.scalePercent = saved.scalePercent
            builtIn.pixelOptimizationEnabled = saved.pixelOptimizationEnabled
        }
        var records: [AiboLibraryRecord] = []
        var hidden = file.builtInHidden
        if !hidden {
            records.append(builtIn)
        }
        for record in file.records where record.kind != .builtInDefault {
            if !records.contains(where: { $0.id == record.id }) {
                records.append(record)
            }
        }
        if records.isEmpty {
            records = [builtIn]
            hidden = false
        }
        let selected: String
        if records.contains(where: { $0.id == file.selectedID }) {
            selected = file.selectedID
        } else {
            selected = records[0].id
        }
        return (selected, records, hidden)
    }

    /// Records written to `library.json`. Built-in is included when renamed or when appearance is custom.
    public static func persistableRecords(from records: [AiboLibraryRecord]) -> [AiboLibraryRecord] {
        var persisted = records.filter { $0.kind != .builtInDefault }
        if let builtIn = records.first(where: { $0.id == AiboLibraryDefaults.builtInID }) {
            let customName = AiboLibraryNaming.normalizedDisplayName(builtIn.displayName)
                .map { $0 != AiboLibraryDefaults.builtInDisplayName } ?? false
            if customName || builtIn.hasCustomAppearance {
                var saved = AiboLibraryRecord.builtInDefault
                saved.displayName = builtIn.displayName
                saved.bubblePlacement = builtIn.bubblePlacement
                saved.bubbleDistance = builtIn.bubbleDistance
                saved.scalePercent = builtIn.scalePercent
                saved.pixelOptimizationEnabled = builtIn.pixelOptimizationEnabled
                persisted.insert(saved, at: 0)
            }
        }
        return persisted
    }
}

public enum AiboLibraryNaming {
    /// Trimmed display name, or `nil` if empty after trimming.
    public static func normalizedDisplayName(_ raw: String) -> String? {
        let name = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        return name.isEmpty ? nil : name
    }

    public static func displayNamesMatch(_ lhs: String, _ rhs: String) -> Bool {
        lhs.trimmingCharacters(in: .whitespacesAndNewlines)
            .caseInsensitiveCompare(rhs.trimmingCharacters(in: .whitespacesAndNewlines))
            == .orderedSame
    }

    /// Existing aibo that shares this slug or display name.
    public static func collidingRecord(
        slug: String?,
        displayName: String,
        in records: [AiboLibraryRecord],
        excludingID: String? = nil
    ) -> AiboLibraryRecord? {
        records.first { record in
            if record.id == excludingID { return false }
            if let slug {
                if record.slug == slug { return true }
                if record.id == "petdex.\(slug)" { return true }
            }
            return displayNamesMatch(record.displayName, displayName)
        }
    }

    /// `Base-2`, then `-3` if that name is taken.
    public static func suggestedCopyDisplayName(
        base: String,
        existingNames: [String]
    ) -> String {
        let name = normalizedDisplayName(base) ?? base
        var suffix = 2
        while existingNames.contains(where: { displayNamesMatch($0, "\(name)-\(suffix)") }) {
            suffix += 1
        }
        return "\(name)-\(suffix)"
    }
}

public enum AiboLibraryDeletion {
    /// IDs that can be removed without emptying the library.
    /// `nil` means the request would leave zero aibos.
    public static func idsToRemove(
        requested: some Sequence<String>,
        from records: [AiboLibraryRecord]
    ) -> [String]? {
        let wanted = Set(requested)
        let known = records.map(\.id).filter { wanted.contains($0) }
        guard !known.isEmpty else { return [] }
        let remaining = records.contains { !wanted.contains($0.id) }
        return remaining ? known : nil
    }
}

public enum AiboRenameOutcome: Equatable, Sendable {
    case renamed
    case unchanged
    case nameTaken(existingDisplayName: String, suggestedDisplayName: String)
}

public enum AiboLibraryOrdering {
    /// Newest `installedAt` first. Records without a date sort last, then by name / id.
    public static func installedAtNewestFirst(_ records: [AiboLibraryRecord]) -> [AiboLibraryRecord] {
        records.sorted(by: compareInstalledAtNewestFirst)
    }

    public static func byDisplayName(_ records: [AiboLibraryRecord]) -> [AiboLibraryRecord] {
        records.sorted(by: compareNameThenID)
    }

    /// Largest first. Missing sizes count as 0, then name / id.
    public static func bySizeLargestFirst(
        _ records: [AiboLibraryRecord],
        bytesForID: [String: Int64]
    ) -> [AiboLibraryRecord] {
        records.sorted { lhs, rhs in
            let left = bytesForID[lhs.id] ?? 0
            let right = bytesForID[rhs.id] ?? 0
            if left != right { return left > right }
            return compareNameThenID(lhs, rhs)
        }
    }

    private static func compareInstalledAtNewestFirst(_ lhs: AiboLibraryRecord, _ rhs: AiboLibraryRecord) -> Bool {
        switch (lhs.installedAt, rhs.installedAt) {
        case let (left?, right?):
            if left != right { return left > right }
            return compareNameThenID(lhs, rhs)
        case (_?, nil):
            return true
        case (nil, _?):
            return false
        case (nil, nil):
            return compareNameThenID(lhs, rhs)
        }
    }

    private static func compareNameThenID(_ lhs: AiboLibraryRecord, _ rhs: AiboLibraryRecord) -> Bool {
        let name = lhs.displayName.localizedStandardCompare(rhs.displayName)
        if name != .orderedSame {
            return name == .orderedAscending
        }
        return lhs.id < rhs.id
    }
}
