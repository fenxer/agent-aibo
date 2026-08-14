import Foundation

/// Built-in Asset Catalog pet (`DefaultPet`). Always available; never persisted.
public enum PetLibraryDefaults {
    public static let builtInID = "builtin.default"
    public static let builtInDisplayName = "Default"
}

public enum PetKind: String, Codable, Sendable, Equatable {
    case builtInDefault
    case petdex
    case staticImage
}

/// One selectable pet appearance. Built-in is synthesized; others come from disk.
public struct PetLibraryRecord: Codable, Sendable, Equatable, Identifiable, Hashable {
    public var id: String
    public var kind: PetKind
    public var displayName: String
    /// Relative to `AiboPaths.petsDirectory`. Petdex: `petdex/<slug>`; static: `static/<file>`.
    public var relativePath: String
    public var slug: String?
    /// Filename inside the petdex folder (e.g. `spritesheet.webp`).
    public var spriteFileName: String?
    public var spriteVersionNumber: Int?
    /// First time this pet was added to the library. Omitted in older `library.json`.
    public var installedAt: Date?
    /// Origin shown in All Pets. Petdex: pet page URL. Local image: nil (UI shows Local).
    public var installSource: String?

    public init(
        id: String,
        kind: PetKind,
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

    public static var builtInDefault: PetLibraryRecord {
        PetLibraryRecord(
            id: PetLibraryDefaults.builtInID,
            kind: .builtInDefault,
            displayName: PetLibraryDefaults.builtInDisplayName,
            relativePath: ""
        )
    }

    public var isRemovable: Bool {
        kind != .builtInDefault
    }
}

/// On-disk `library.json` shape. Does not include the built-in default.
public struct PetLibraryFile: Codable, Sendable, Equatable {
    public var selectedID: String
    public var records: [PetLibraryRecord]

    public init(selectedID: String = PetLibraryDefaults.builtInID, records: [PetLibraryRecord] = []) {
        self.selectedID = selectedID
        self.records = records
    }
}

public enum PetLibraryCodec {
    public static func decode(_ data: Data) throws -> PetLibraryFile {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try decoder.decode(PetLibraryFile.self, from: data)
    }

    public static func encode(_ file: PetLibraryFile) throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        return try encoder.encode(file)
    }

    /// Merges disk file with the built-in default and resolves a valid selection.
    public static func snapshot(from file: PetLibraryFile) -> (selectedID: String, records: [PetLibraryRecord]) {
        var records = [PetLibraryRecord.builtInDefault]
        for record in file.records where record.kind != .builtInDefault {
            if !records.contains(where: { $0.id == record.id }) {
                records.append(record)
            }
        }
        let selected: String
        if records.contains(where: { $0.id == file.selectedID }) {
            selected = file.selectedID
        } else {
            selected = PetLibraryDefaults.builtInID
        }
        return (selected, records)
    }
}

public enum PetLibraryOrdering {
    /// Newest `installedAt` first. Records without a date sort last, then by name / id.
    public static func installedAtNewestFirst(_ records: [PetLibraryRecord]) -> [PetLibraryRecord] {
        records.sorted(by: compareInstalledAtNewestFirst)
    }

    public static func byDisplayName(_ records: [PetLibraryRecord]) -> [PetLibraryRecord] {
        records.sorted(by: compareNameThenID)
    }

    /// Largest first. Missing sizes count as 0, then name / id.
    public static func bySizeLargestFirst(
        _ records: [PetLibraryRecord],
        bytesForID: [String: Int64]
    ) -> [PetLibraryRecord] {
        records.sorted { lhs, rhs in
            let left = bytesForID[lhs.id] ?? 0
            let right = bytesForID[rhs.id] ?? 0
            if left != right { return left > right }
            return compareNameThenID(lhs, rhs)
        }
    }

    private static func compareInstalledAtNewestFirst(_ lhs: PetLibraryRecord, _ rhs: PetLibraryRecord) -> Bool {
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

    private static func compareNameThenID(_ lhs: PetLibraryRecord, _ rhs: PetLibraryRecord) -> Bool {
        let name = lhs.displayName.localizedStandardCompare(rhs.displayName)
        if name != .orderedSame {
            return name == .orderedAscending
        }
        return lhs.id < rhs.id
    }
}
