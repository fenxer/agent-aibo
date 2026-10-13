import Foundation

/// `aibo://extension/<slug>` names an installed plugin.
/// The host opens its interactive bubble when it has one, and Settings otherwise.
public enum ExtensionLink {
    public static func slug(from url: URL) -> String? {
        guard url.scheme?.lowercased() == "aibo" else { return nil }
        if url.host?.lowercased() == "extension" {
            return singlePathSlug(url.path)
        }
        let parts = pathParts(url.path)
        guard parts.count == 2, parts[0].lowercased() == "extension" else { return nil }
        return validated(parts[1])
    }

    private static func singlePathSlug(_ path: String) -> String? {
        let parts = pathParts(path)
        guard parts.count == 1 else { return nil }
        return validated(parts[0])
    }

    private static func pathParts(_ path: String) -> [String] {
        path.split(separator: "/").map(String.init)
    }

    private static func validated(_ raw: String) -> String? {
        let slug = raw.lowercased()
        return ExtensionManifestValidator.isValidSlug(slug) ? slug : nil
    }
}
