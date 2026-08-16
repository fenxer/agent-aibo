import Foundation

/// Response from `GET https://petdex.dev/api/install-pet/{slug}`.
public struct PetdexInstallAPIResponse: Codable, Sendable, Equatable {
    public var ok: Bool
    public var pet: PetdexInstallablePet?
    public var error: String?
    public var slug: String?

    public init(ok: Bool, pet: PetdexInstallablePet? = nil, error: String? = nil, slug: String? = nil) {
        self.ok = ok
        self.pet = pet
        self.error = error
        self.slug = slug
    }
}

public struct PetdexInstallablePet: Codable, Sendable, Equatable {
    public var slug: String
    public var displayName: String
    public var petJsonUrl: String
    public var spritesheetUrl: String
    public var spriteExt: String

    public init(
        slug: String,
        displayName: String,
        petJsonUrl: String,
        spritesheetUrl: String,
        spriteExt: String
    ) {
        self.slug = slug
        self.displayName = displayName
        self.petJsonUrl = petJsonUrl
        self.spritesheetUrl = spritesheetUrl
        self.spriteExt = spriteExt
    }
}

/// Minimal `pet.json` fields we persist / read after download.
public struct PetdexPetJSON: Codable, Sendable, Equatable {
    public var id: String?
    public var displayName: String?
    public var description: String?
    public var spriteVersionNumber: Int?
    public var spritesheetPath: String?

    public init(
        id: String? = nil,
        displayName: String? = nil,
        description: String? = nil,
        spriteVersionNumber: Int? = nil,
        spritesheetPath: String? = nil
    ) {
        self.id = id
        self.displayName = displayName
        self.description = description
        self.spriteVersionNumber = spriteVersionNumber
        self.spritesheetPath = spritesheetPath
    }
}

public enum PetdexInstallError: Error, Sendable, Equatable {
    case invalidSlug
    case notFound(String)
    case api(String)
    case badURL
    case downloadFailed
    case invalidSpritesheet
    case ioFailed
}

public enum PetdexInstallAPI {
    public static let baseURL = URL(string: "https://petdex.dev")!
    public static let referer = "https://petdex.dev/"

    public static func installPetURL(slug: String) -> URL {
        baseURL.appendingPathComponent("api/install-pet/\(slug)")
    }

    public static func petPageURL(slug: String) -> URL {
        baseURL.appendingPathComponent("pets").appendingPathComponent(slug)
    }

    public static func decodeResponse(_ data: Data) throws -> PetdexInstallAPIResponse {
        try JSONDecoder().decode(PetdexInstallAPIResponse.self, from: data)
    }

    public static func decodePetJSON(_ data: Data) throws -> PetdexPetJSON {
        try JSONDecoder().decode(PetdexPetJSON.self, from: data)
    }

    /// Builds the library record after files are on disk under `petdex/<slug>/`.
    public static func makeRecord(
        installable: PetdexInstallablePet,
        petJSON: PetdexPetJSON?
    ) -> AiboLibraryRecord {
        let ext = installable.spriteExt.lowercased()
        let spriteName = "spritesheet.\(ext.isEmpty ? "webp" : ext)"
        return AiboLibraryRecord(
            id: "petdex.\(installable.slug)",
            kind: .petdex,
            displayName: petJSON?.displayName ?? installable.displayName,
            relativePath: "\(AiboPaths.petdexDirectoryName)/\(installable.slug)",
            slug: installable.slug,
            spriteFileName: spriteName,
            spriteVersionNumber: petJSON?.spriteVersionNumber,
            installedAt: Date(),
            installSource: petPageURL(slug: installable.slug).absoluteString
        )
    }
}
