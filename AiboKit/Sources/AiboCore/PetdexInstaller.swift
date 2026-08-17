import Foundation

/// Downloads one aibo via `/api/install-pet/{slug}` into `AiboPaths.petdexDirectory`.
public struct PetdexInstaller: Sendable {
    public typealias DataFetcher = @Sendable (URL, [String: String]) async throws -> Data

    private let fetch: DataFetcher

    public init(fetch: @escaping DataFetcher = PetdexInstaller.defaultFetch) {
        self.fetch = fetch
    }

    public func install(slugOrURL: String) async throws -> AiboLibraryRecord {
        guard let slug = PetdexSlugParser.parse(slugOrURL) else {
            throw PetdexInstallError.invalidSlug
        }
        return try await install(slug: slug)
    }

    public func install(slug: String) async throws -> AiboLibraryRecord {
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

        let destination = AiboPaths.petdexAiboDirectory(slug: pet.slug)
        try PetdexPackStore.writeAtomically(
            destination: destination,
            petJSONData: petJSONData,
            spriteData: spriteData,
            spriteFileName: record.spriteFileName ?? "spritesheet.webp"
        )
        PetdexClipSlicer.convertIfNeeded(in: destination)
        return record
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
