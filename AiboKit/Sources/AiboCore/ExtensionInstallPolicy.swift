import Foundation

/// Why a plugin folder must not be copied into Application Support.
public struct ExtensionInstallBlock: Equatable, Sendable {
    /// Capabilities (`provides` values) no other installed plugin offers yet.
    public var missingCapabilities: [String]
    /// Slug already declared by a different installed plugin.
    public var duplicateSlug: String?

    public var isEmpty: Bool {
        missingCapabilities.isEmpty && duplicateSlug == nil
    }

    public init(missingCapabilities: [String] = [], duplicateSlug: String? = nil) {
        self.missingCapabilities = missingCapabilities
        self.duplicateSlug = duplicateSlug
    }
}

public enum ExtensionInstallPolicy {
    /// Replacing the same plugin id is allowed to keep its slug.
    /// A plugin does not satisfy its own capability requirements.
    public static func block(
        installing manifest: ExtensionManifest,
        alongside installed: [ExtensionManifest]
    ) -> ExtensionInstallBlock? {
        let others = installed.filter { $0.id != manifest.id }
        let provided = Set(others.flatMap(\.provides))
        let missing = manifest.requiredCapabilities.filter { !provided.contains($0) }
        let duplicate = manifest.slug.flatMap { slug in
            others.contains { $0.slug == slug } ? slug : nil
        }
        let block = ExtensionInstallBlock(missingCapabilities: missing, duplicateSlug: duplicate)
        return block.isEmpty ? nil : block
    }
}
