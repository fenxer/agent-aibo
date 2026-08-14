import AiboCore
import Foundation

/// Installs the DeepSeek Harness observe plugin into `$DSH_HOME/cordis.patch.yml`.
public enum DshAiboPluginFile {
    public static var installedPluginDirectory: URL {
        AiboPaths.applicationSupportDirectory
            .appendingPathComponent(DeepSeekHarnessPlugin.bundledDirectoryName, isDirectory: true)
    }

    public static var installedPluginMain: URL {
        installedPluginDirectory.appendingPathComponent(
            DeepSeekHarnessPlugin.pluginMainFileName,
            isDirectory: false
        )
    }

    public static func homeDirectory(
        environment: [String: String] = ProcessInfo.processInfo.environment,
        fileManager: FileManager = .default
    ) -> URL {
        if let override = environment["DSH_HOME"]?.trimmingCharacters(in: .whitespacesAndNewlines),
           !override.isEmpty
        {
            return URL(fileURLWithPath: override, isDirectory: true)
        }
        return fileManager.homeDirectoryForCurrentUser
            .appendingPathComponent(".dsh", isDirectory: true)
    }

    public static func patchURL(
        environment: [String: String] = ProcessInfo.processInfo.environment,
        fileManager: FileManager = .default
    ) -> URL {
        homeDirectory(environment: environment, fileManager: fileManager)
            .appendingPathComponent("cordis.patch.yml", isDirectory: false)
    }

    public static func bundledPluginDirectory(bundle: Bundle = .main) -> URL? {
        bundle.resourceURL?.appendingPathComponent(
            DeepSeekHarnessPlugin.bundledDirectoryName,
            isDirectory: true
        )
    }

    public static func install(
        sourceDirectory: URL,
        pluginInstallDirectory: URL = installedPluginDirectory,
        environment: [String: String] = ProcessInfo.processInfo.environment,
        fileManager: FileManager = .default
    ) throws {
        let main = sourceDirectory.appendingPathComponent(
            DeepSeekHarnessPlugin.pluginMainFileName,
            isDirectory: false
        )
        guard fileManager.fileExists(atPath: main.path) else {
            throw CocoaError(.fileNoSuchFile)
        }

        try fileManager.createDirectory(
            at: pluginInstallDirectory,
            withIntermediateDirectories: true
        )
        try copyPluginFiles(
            from: sourceDirectory,
            to: pluginInstallDirectory,
            fileManager: fileManager
        )

        let patchFile = patchURL(environment: environment, fileManager: fileManager)
        try fileManager.createDirectory(
            at: patchFile.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        let existing = try readText(from: patchFile, fileManager: fileManager)
        let pluginMain = pluginInstallDirectory.appendingPathComponent(
            DeepSeekHarnessPlugin.pluginMainFileName,
            isDirectory: false
        )
        let next = try DshHomePatch.install(
            existing: existing,
            pluginPath: pluginMain.path
        )
        try writeAtomicText(next, to: patchFile, fileManager: fileManager)
    }

    public static func uninstall(
        pluginInstallDirectory: URL = installedPluginDirectory,
        environment: [String: String] = ProcessInfo.processInfo.environment,
        fileManager: FileManager = .default
    ) throws {
        let patchFile = patchURL(environment: environment, fileManager: fileManager)
        if fileManager.fileExists(atPath: patchFile.path) {
            let existing = try readText(from: patchFile, fileManager: fileManager)
            let next = try DshHomePatch.uninstall(existing: existing)
            let trimmed = next.trimmingCharacters(in: .whitespacesAndNewlines)
            if trimmed.isEmpty {
                try? fileManager.removeItem(at: patchFile)
            } else {
                try writeAtomicText(next, to: patchFile, fileManager: fileManager)
            }
        }
        if fileManager.fileExists(atPath: pluginInstallDirectory.path) {
            try? fileManager.removeItem(at: pluginInstallDirectory)
        }
    }

    public static func isInstalled(
        environment: [String: String] = ProcessInfo.processInfo.environment,
        fileManager: FileManager = .default
    ) throws -> Bool {
        let patchFile = patchURL(environment: environment, fileManager: fileManager)
        let existing = try readText(from: patchFile, fileManager: fileManager)
        try DshHomePatch.validateMarkers(existing)
        return DshHomePatch.isInstalled(existing)
    }

    private static func copyPluginFiles(
        from source: URL,
        to destination: URL,
        fileManager: FileManager
    ) throws {
        let names = try fileManager.contentsOfDirectory(atPath: source.path)
        for name in names where !name.hasPrefix(".") {
            let from = source.appendingPathComponent(name)
            let to = destination.appendingPathComponent(name)
            if fileManager.fileExists(atPath: to.path) {
                try fileManager.removeItem(at: to)
            }
            try fileManager.copyItem(at: from, to: to)
        }
    }

    private static func readText(from url: URL, fileManager: FileManager) throws -> String {
        if !fileManager.fileExists(atPath: url.path) {
            return ""
        }
        let data = try Data(contentsOf: url)
        if data.isEmpty { return "" }
        guard let text = String(data: data, encoding: .utf8) else {
            throw CocoaError(.fileReadInapplicableStringEncoding)
        }
        return text
    }

    private static func writeAtomicText(
        _ text: String,
        to url: URL,
        fileManager: FileManager
    ) throws {
        try fileManager.createDirectory(
            at: url.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try Data(text.utf8).write(to: url, options: .atomic)
    }
}
