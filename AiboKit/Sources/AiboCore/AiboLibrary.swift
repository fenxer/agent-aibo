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

    public init(
        id: String,
        kind: AiboKind,
        displayName: String,
        relativePath: String,
        slug: String? = nil,
        spriteFileName: String? = nil,
        spriteVersionNumber: Int? = nil,
        installedAt: Date? = nil,
        installSource: String? = nil
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
    }

    public static var builtInDefault: AiboLibraryRecord {
        AiboLibraryRecord(
            id: AiboLibraryDefaults.builtInID,
            kind: .builtInDefault,
            displayName: AiboLibraryDefaults.builtInDisplayName,
            relativePath: ""
        )
    }

    public var isRemovable: Bool {
        kind != .builtInDefault
    }
}

/// On-disk `library.json` shape. Does not include the built-in default.
public struct AiboLibraryFile: Codable, Sendable, Equatable {
    public var selectedID: String
    public var records: [AiboLibraryRecord]

    public init(selectedID: String = AiboLibraryDefaults.builtInID, records: [AiboLibraryRecord] = []) {
        self.selectedID = selectedID
        self.records = records
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
    public static func snapshot(from file: AiboLibraryFile) -> (selectedID: String, records: [AiboLibraryRecord]) {
        var records = [AiboLibraryRecord.builtInDefault]
        for record in file.records where record.kind != .builtInDefault {
            if !records.contains(where: { $0.id == record.id }) {
                records.append(record)
            }
        }
        let selected: String
        if records.contains(where: { $0.id == file.selectedID }) {
            selected = file.selectedID
        } else {
            selected = AiboLibraryDefaults.builtInID
        }
        return (selected, records)
    }
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
