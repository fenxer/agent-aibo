import Foundation

public enum PetdexSlugParser {
    public static func isValidSlug(_ slug: String) -> Bool {
        // Official install-pet gate: ^[a-z0-9][a-z0-9-]{0,62}$
        guard let first = slug.first, first.isASCII, first.isLetter || first.isNumber else {
            return false
        }
        guard slug.count <= 63 else { return false }
        return slug.unicodeScalars.allSatisfy { scalar in
            (scalar >= "a" && scalar <= "z")
                || (scalar >= "0" && scalar <= "9")
                || scalar == "-"
        }
    }

    /// Accepts a bare slug or a URL whose path contains `/pets/<slug>` or `/install-pet/<slug>` / `/install/<slug>`.
    public static func parse(_ raw: String) -> String? {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }

        if isValidSlug(trimmed) {
            return trimmed
        }

        guard let url = URL(string: trimmed), let host = url.host, !host.isEmpty else {
            return nil
        }

        let parts = url.path.split(separator: "/").map(String.init)
        guard let slug = slugFromPathComponents(parts) else { return nil }
        return isValidSlug(slug) ? slug : nil
    }

    private static func slugFromPathComponents(_ parts: [String]) -> String? {
        // /pets/boba, /en/pets/boba, /api/install-pet/boba, /install/boba
        let markers = ["pets", "install-pet", "install"]
        for index in parts.indices {
            let part = parts[index]
            guard markers.contains(part), parts.index(after: index) < parts.endIndex else { continue }
            let candidate = parts[parts.index(after: index)]
            // Skip locale-only segments mistaken as slug when pattern is /en/pets/...
            if markers.contains(candidate) { continue }
            return candidate.lowercased()
        }
        return parts.last.map { $0.lowercased() }
    }
}
