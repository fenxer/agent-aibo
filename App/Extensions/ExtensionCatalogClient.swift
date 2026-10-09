import AiboCore
import AiboIngest
import Foundation
import Observation

enum ExtensionCatalogSource: String {
    case local
    case online
}

/// Reads `catalog.json` and installs the directory it names.
///
/// Debug chooses a local file or the copy on `main`. Release always uses `main`.
@MainActor
@Observable
final class ExtensionCatalogClient {
    static let shared = ExtensionCatalogClient()

    private(set) var entries: [ExtensionCatalogEntry] = []
    private(set) var installingID: String?
    private(set) var statusText = ""
    #if DEBUG
    private(set) var source: ExtensionCatalogSource
    private(set) var catalogFilePath: String?
    #endif

    private var catalog: ExtensionCatalog?
    private var repositoryRoot: URL?
    private var loadFailed = false
    private var generation = 0
    private let session: URLSession
    private let center: ExtensionCenter

    private init() {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.requestCachePolicy = .reloadIgnoringLocalCacheData
        session = URLSession(configuration: configuration)
        center = .shared
        #if DEBUG
        let stored = UserDefaults.standard.string(forKey: Keys.source) ?? ""
        source = ExtensionCatalogSource(rawValue: stored) ?? .local
        catalogFilePath = UserDefaults.standard.string(forKey: Keys.file)
        #endif
    }

    func reload() async {
        generation += 1
        let token = generation
        let loaded = await load()
        guard token == generation else { return }
        catalog = loaded.catalog
        repositoryRoot = loaded.repositoryRoot
        entries = loaded.catalog?.listed ?? []
        loadFailed = loaded.failed
        statusText = loaded.status
    }

    func install(id: String) async {
        guard installingID == nil else { return }
        await reload()
        guard !loadFailed, let entry = entries.first(where: { $0.id == id }) else {
            let message = loadFailed
                ? String(localized: "Couldn't read the extension catalog.")
                : String(localized: "This plugin is not in the catalog.")
            center.noteInstallFailure(message)
            return
        }
        await install(entry)
    }

    /// Reloads the catalog. A newer `version` than the installed manifest is an update.
    func updateVersion(id: String, installed: String) -> String? {
        guard let entry = entries.first(where: { $0.id == id }) else { return nil }
        guard ExtensionVersion.isNewer(entry.version, than: installed) else { return nil }
        return entry.version
    }

    func checkForUpdates() async {
        guard installingID == nil else { return }
        await reload()
        if loadFailed {
            center.noteInstallFailure(String(localized: "Couldn't read the extension catalog."))
        }
    }

    func upgrade(id: String, installedVersion: String) async {
        guard installingID == nil else { return }
        await reload()
        guard !loadFailed, let entry = entries.first(where: { $0.id == id }) else {
            let message = loadFailed
                ? String(localized: "Couldn't read the extension catalog.")
                : String(localized: "This plugin is not in the catalog.")
            center.noteInstallFailure(message)
            return
        }
        guard ExtensionVersion.isNewer(entry.version, than: installedVersion) else { return }
        await install(entry)
    }

    func localPackageURL(id: String) -> URL? {
        #if DEBUG
        guard source == .local, let repositoryRoot, let entry = entries.first(where: { $0.id == id }) else {
            return nil
        }
        return entry.packageDirectory(in: repositoryRoot)
        #else
        _ = id
        return nil
        #endif
    }

    #if DEBUG
    func setSource(_ source: ExtensionCatalogSource) {
        self.source = source
        UserDefaults.standard.set(source.rawValue, forKey: Keys.source)
        Task { await reload() }
    }

    func setLocalCatalogFile(_ url: URL) {
        guard ExtensionCatalog.repositoryRoot(catalogFile: url) != nil else {
            statusText = "Choose Extensions/catalog.json inside the repository."
            return
        }
        catalogFilePath = url.path
        UserDefaults.standard.set(url.path, forKey: Keys.file)
        source = .local
        UserDefaults.standard.set(ExtensionCatalogSource.local.rawValue, forKey: Keys.source)
        Task { await reload() }
    }
    #endif

    private func install(_ entry: ExtensionCatalogEntry) async {
        installingID = entry.id
        defer { installingID = nil }
        #if DEBUG
        if source == .local {
            guard let repositoryRoot, let directory = entry.packageDirectory(in: repositoryRoot) else {
                center.noteInstallFailure(String(localized: "Couldn't install the plugin."))
                return
            }
            center.install(from: directory)
            return
        }
        #endif
        guard let catalog else {
            center.noteInstallFailure(String(localized: "Couldn't read the extension catalog."))
            return
        }
        do {
            let directory = try await downloadPackage(entry, catalog: catalog)
            defer { try? FileManager.default.removeItem(at: directory) }
            center.install(from: directory)
        } catch {
            center.noteInstallFailure(String(localized: "Couldn't install the plugin."))
        }
    }

    private func load() async -> LoadResult {
        #if DEBUG
        if source == .local {
            return loadLocal()
        }
        #endif
        return await loadOnline()
    }

    #if DEBUG
    private func loadLocal() -> LoadResult {
        guard let catalogFilePath else {
            return LoadResult(
                catalog: nil,
                repositoryRoot: nil,
                failed: true,
                status: "Choose Extensions/catalog.json"
            )
        }
        let file = URL(fileURLWithPath: catalogFilePath)
        guard let root = ExtensionCatalog.repositoryRoot(catalogFile: file) else {
            return LoadResult(
                catalog: nil,
                repositoryRoot: nil,
                failed: true,
                status: "Choose Extensions/catalog.json inside the repository."
            )
        }
        do {
            let catalog = try ExtensionCatalog.decode(Data(contentsOf: file))
            return LoadResult(
                catalog: catalog,
                repositoryRoot: root,
                failed: false,
                status: status(for: catalog.listed.count)
            )
        } catch {
            return LoadResult(catalog: nil, repositoryRoot: nil, failed: true, status: "Couldn't read the extension catalog.")
        }
    }
    #endif

    private func loadOnline() async -> LoadResult {
        guard let url = ExtensionCatalogLocation.rawCatalogURL else {
            return LoadResult(catalog: nil, repositoryRoot: nil, failed: true, status: "Couldn't read the extension catalog.")
        }
        do {
            let data = try await fetch(url, accept: "application/json")
            let catalog = try ExtensionCatalog.decode(data)
            return LoadResult(
                catalog: catalog,
                repositoryRoot: nil,
                failed: false,
                status: status(for: catalog.listed.count)
            )
        } catch {
            return LoadResult(catalog: nil, repositoryRoot: nil, failed: true, status: "Couldn't read the extension catalog.")
        }
    }

    private func downloadPackage(_ entry: ExtensionCatalogEntry, catalog: ExtensionCatalog) async throws -> URL {
        guard ExtensionCatalogPath.error(entry.path) == nil else { throw DownloadError.unsafe }
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("aibo-ext-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let tally = DownloadTally()
        do {
            try await download(remotePath: entry.path, entryPath: entry.path, into: root, catalog: catalog, tally: tally)
        } catch {
            try? FileManager.default.removeItem(at: root)
            throw error
        }
        return root
    }

    private func download(
        remotePath: String,
        entryPath: String,
        into root: URL,
        catalog: ExtensionCatalog,
        tally: DownloadTally
    ) async throws {
        guard let url = catalog.contentsAPIURL(path: remotePath) else { throw DownloadError.unsafe }
        let data = try await fetch(url, accept: "application/vnd.github+json")
        let items = try JSONDecoder().decode([GitHubContentItem].self, from: data)
        for item in items {
            guard item.path == entryPath || item.path.hasPrefix(entryPath + "/") else { throw DownloadError.unsafe }
            switch item.type {
            case "dir":
                try await download(remotePath: item.path, entryPath: entryPath, into: root, catalog: catalog, tally: tally)
            case "file":
                guard let downloadURL = item.downloadURL, isAllowedDownload(downloadURL) else { throw DownloadError.unsafe }
                let prefix = entryPath + "/"
                guard item.path.hasPrefix(prefix) else { throw DownloadError.unsafe }
                let relative = String(item.path.dropFirst(prefix.count))
                guard ExtensionCatalogPath.error(relative) == nil else { throw DownloadError.unsafe }
                let file = try await fetch(downloadURL, accept: nil)
                tally.files += 1
                tally.bytes += file.count
                if tally.files > ExtensionStore.maxFiles || tally.bytes > ExtensionStore.maxBytes {
                    throw DownloadError.tooLarge
                }
                let destination = root.appendingPathComponent(relative)
                try FileManager.default.createDirectory(
                    at: destination.deletingLastPathComponent(),
                    withIntermediateDirectories: true
                )
                try file.write(to: destination, options: .atomic)
            default:
                throw DownloadError.unsafe
            }
        }
    }

    private func fetch(_ url: URL, accept: String?) async throws -> Data {
        let host = url.host?.lowercased()
        guard host == "api.github.com" || host == "raw.githubusercontent.com" else {
            throw DownloadError.unsafe
        }
        var request = URLRequest(url: url, timeoutInterval: 20)
        request.setValue("aibo", forHTTPHeaderField: "User-Agent")
        if let accept {
            request.setValue(accept, forHTTPHeaderField: "Accept")
        }
        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse, http.statusCode == 200 else {
            throw DownloadError.failed
        }
        let finalHost = http.url?.host?.lowercased()
        let stayed = finalHost == host || finalHost == "objects.githubusercontent.com"
        guard stayed else { throw DownloadError.unsafe }
        return data
    }

    private func isAllowedDownload(_ url: URL) -> Bool {
        url.scheme == "https" && url.host?.lowercased() == "raw.githubusercontent.com"
    }

    private func status(for count: Int) -> String {
        count == 1 ? "Loaded 1 extension" : "Loaded \(count) extensions"
    }

    private struct LoadResult {
        var catalog: ExtensionCatalog?
        var repositoryRoot: URL?
        var failed: Bool
        var status: String
    }

    private struct GitHubContentItem: Decodable {
        var path: String
        var type: String
        var downloadURL: URL?

        enum CodingKeys: String, CodingKey {
            case path
            case type
            case downloadURL = "download_url"
        }
    }

    private final class DownloadTally {
        var files = 0
        var bytes = 0
    }

    private enum DownloadError: Error {
        case unsafe
        case tooLarge
        case failed
    }

    #if DEBUG
    private enum Keys {
        static let source = "debug.extensionCatalogSource"
        static let file = "debug.extensionCatalogFile"
    }
    #endif
}
