import Foundation

/// Downloads one pet via `/api/install-pet/{slug}` into `AiboPaths.petdexPetsDirectory`.
public struct PetdexInstaller: Sendable {
    public typealias DataFetcher = @Sendable (URL, [String: String]) async throws -> Data

    private let fetch: DataFetcher

    public init(fetch: @escaping DataFetcher = PetdexInstaller.defaultFetch) {
        self.fetch = fetch
    }

    public func install(slugOrURL: String) async throws -> PetLibraryRecord {
        guard let slug = PetdexSlugParser.parse(slugOrURL) else {
            throw PetdexInstallError.invalidSlug
        }
        return try await install(slug: slug)
    }

    public func install(slug: String) async throws -> PetLibraryRecord {
        guard PetdexSlugParser.isValidSlug(slug) else {
            throw PetdexInstallError.invalidSlug
        }

        let metaURL = PetdexInstallAPI.installPetURL(slug: slug)
        let metaData = try await fetch(metaURL, Self.petdexHeaders)
        let response = try PetdexInstallAPI.decodeResponse(metaData)
        guard response.ok, let pet = response.pet else {
            if response.error == "not_found" {
                throw PetdexInstallError.notFound(slug)
            }
            throw PetdexInstallError.api(response.error ?? "unknown")
        }

        guard let petJSONURL = URL(string: pet.petJsonUrl),
              let spriteURL = URL(string: pet.spritesheetUrl)
        else {
            throw PetdexInstallError.badURL
        }

        let petJSONData = try await fetch(petJSONURL, Self.petdexHeaders)
        let spriteData = try await fetch(spriteURL, Self.petdexHeaders)
        guard !spriteData.isEmpty else { throw PetdexInstallError.downloadFailed }

        let petJSON = try? PetdexInstallAPI.decodePetJSON(petJSONData)
        let record = PetdexInstallAPI.makeRecord(installable: pet, petJSON: petJSON)

        let destination = AiboPaths.petdexPetDirectory(slug: pet.slug)
        try materialize(
            destination: destination,
            petJSONData: petJSONData,
            spriteData: spriteData,
            spriteFileName: record.spriteFileName ?? "spritesheet.webp"
        )
        return record
    }

    private func materialize(
        destination: URL,
        petJSONData: Data,
        spriteData: Data,
        spriteFileName: String
    ) throws {
        let fileManager = FileManager.default
        let parent = destination.deletingLastPathComponent()
        try fileManager.createDirectory(at: parent, withIntermediateDirectories: true)

        let staging = parent.appendingPathComponent(
            ".staging-\(destination.lastPathComponent)-\(UUID().uuidString)",
            isDirectory: true
        )
        try? fileManager.removeItem(at: staging)
        try fileManager.createDirectory(at: staging, withIntermediateDirectories: true)

        do {
            try petJSONData.write(to: staging.appendingPathComponent("pet.json"), options: .atomic)
            try spriteData.write(
                to: staging.appendingPathComponent(spriteFileName),
                options: .atomic
            )
            if fileManager.fileExists(atPath: destination.path) {
                try fileManager.removeItem(at: destination)
            }
            try fileManager.moveItem(at: staging, to: destination)
        } catch {
            try? fileManager.removeItem(at: staging)
            throw PetdexInstallError.ioFailed
        }
    }

    private static let petdexHeaders: [String: String] = [
        "User-Agent": "aibo/1.0 (macOS; Petdex client)",
        "Referer": PetdexInstallAPI.referer,
        "Accept": "*/*",
    ]

    public static func defaultFetch(_ url: URL, _ headers: [String: String]) async throws -> Data {
        var request = URLRequest(url: url)
        for (key, value) in headers {
            request.setValue(value, forHTTPHeaderField: key)
        }
        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse, (200...299).contains(http.statusCode) else {
            throw PetdexInstallError.downloadFailed
        }
        return data
    }
}
