import AiboCore
import Foundation

/// Queues `aibo://extension/<slug>` until installed plugins have been loaded.
/// A manual plugin opens its bubble; other plugins open Settings.
@MainActor
enum ExtensionLinkRouter {
    private static var pendingSlugs: [String] = []

    static func accept(_ urls: [URL]) {
        let slugs = urls.compactMap(ExtensionLink.slug(from:))
        guard !slugs.isEmpty else { return }
        pendingSlugs.append(contentsOf: slugs)
        deliver()
    }

    static func deliver() {
        guard !pendingSlugs.isEmpty else { return }
        guard ExtensionCenter.shared.isReady else { return }
        let slugs = pendingSlugs
        pendingSlugs.removeAll()
        guard let slug = slugs.last else { return }
        ExtensionCenter.shared.openLinkedPlugin(slug: slug)
    }
}
