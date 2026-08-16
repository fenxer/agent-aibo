import Foundation

/// Atomically writes `pet.json` + spritesheet into `petdex/<slug>/`.
enum PetdexPackStore {
    static func writeAtomically(
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
}
