import Foundation

/// Which dropped files a plugin's `accepts` list claims.
public enum ExtensionFileAcceptance {
    /// `jpg` and `jpeg` are one image type, so listing either is enough.
    private static let aliases: [Set<String>] = [
        ["jpg", "jpeg"],
    ]

    public static func matches(url: URL, accepts: [String]) -> Bool {
        matches(fileExtension: url.pathExtension, accepts: accepts)
    }

    public static func matches(fileExtension: String, accepts: [String]) -> Bool {
        let ext = normalize(fileExtension)
        guard !ext.isEmpty else { return false }
        let declared = Set(accepts.map(normalize).filter { !$0.isEmpty })
        if declared.contains(ext) { return true }
        for group in aliases where group.contains(ext) {
            if !declared.isDisjoint(with: group) { return true }
        }
        return false
    }

    private static func normalize(_ value: String) -> String {
        var text = value.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        if text.hasPrefix(".") { text.removeFirst() }
        return text
    }
}
