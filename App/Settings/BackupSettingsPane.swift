import AiboCore
import AppKit
import SwiftUI
import UniformTypeIdentifiers

@MainActor
@Observable
final class BackupSettingsModel {
    static let shared = BackupSettingsModel()

    var isWorking = false
    var errorMessage: String?
    var showPreview = false
    var playtimeMode: AiboBackupPlaytimeMode = .add
    private(set) var preview: BackupImportPreview?
    private var pendingRoot: URL?
    private var pendingDocument: AiboBackupArchive.Document?

    private static let archiveType = UTType(filenameExtension: AiboBackupArchive.fileExtension, conformingTo: .zip) ?? .zip

    func export() {
        guard !isWorking else { return }
        let panel = NSSavePanel()
        panel.canCreateDirectories = true
        panel.allowedContentTypes = [Self.archiveType]
        panel.allowsOtherFileTypes = false
        panel.isExtensionHidden = false
        panel.nameFieldStringValue = AiboBackupArchive.suggestedFileName(on: Date())
        guard panel.runModal() == .OK, let picked = panel.url else { return }
        let destination = Self.archiveURL(picked)

        let settings = AppSettings.shared.backupSnapshot()
        let playtime = PlaytimeStore.shared.ledgerForExport()
        let aibos = AiboPaths.aibosDirectory
        let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? ""
        isWorking = true
        Task.detached {
            do {
                try AiboBackupArchive.write(
                    settings: settings,
                    playtime: playtime,
                    aibosSource: aibos,
                    appVersion: version,
                    to: destination
                )
                await MainActor.run { BackupSettingsModel.shared.isWorking = false }
            } catch {
                await MainActor.run {
                    BackupSettingsModel.shared.isWorking = false
                    BackupSettingsModel.shared.errorMessage = Self.message(for: error, importing: false)
                }
            }
        }
    }

    func chooseImport() {
        guard !isWorking else { return }
        let panel = NSOpenPanel()
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = false
        panel.allowedContentTypes = [Self.archiveType, .zip]
        panel.allowsOtherFileTypes = true
        guard panel.runModal() == .OK, let url = panel.url else { return }

        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("aibo-import-\(UUID().uuidString)", isDirectory: true)
        isWorking = true
        Task.detached {
            do {
                let document = try AiboBackupArchive.read(archive: url, into: root)
                await MainActor.run {
                    BackupSettingsModel.shared.receiveImport(document, root: root)
                }
            } catch {
                try? FileManager.default.removeItem(at: root)
                await MainActor.run {
                    BackupSettingsModel.shared.isWorking = false
                    BackupSettingsModel.shared.errorMessage = Self.message(for: error, importing: true)
                }
            }
        }
    }

    func finishImport(mode: AiboBackupPlaytimeMode) {
        guard let document = pendingDocument, let root = pendingRoot else { return }
        pendingDocument = nil
        pendingRoot = nil
        preview = nil
        showPreview = false
        isWorking = true
        let settings = document.settings
        let playtime = document.playtime
        let aibos = document.aibosDirectory
        Task.detached {
            do {
                var replacement = try AiboBackupArchive.replaceLibrary(
                    at: AiboPaths.aibosDirectory,
                    with: aibos
                )
                await MainActor.run {
                    AiboLibraryStore.shared.adoptImportedLibrary()
                    PlaytimeStore.shared.importBackup(playtime, mode: mode)
                    let settingsModel = AppSettings.shared
                    settingsModel.applyBackup(settings)
                    if settingsModel.restoreLastAiboPosition,
                       let x = settingsModel.savedAiboCenterXPercent,
                       let y = settingsModel.savedAiboCenterYPercent
                    {
                        AiboPanelController.shared.placeAiboAtRelativePosition(xPercent: x, yPercent: y)
                    }
                }
                replacement.commit()
                await MainActor.run {
                    BackupSettingsModel.shared.isWorking = false
                    AppSettings.shared.applyBackupLanguage(settings)
                }
            } catch {
                await MainActor.run {
                    BackupSettingsModel.shared.isWorking = false
                    BackupSettingsModel.shared.errorMessage = Self.message(for: error, importing: true)
                }
            }
            try? FileManager.default.removeItem(at: root)
        }
    }

    func confirmImport() {
        finishImport(mode: playtimeMode)
    }

    /// The preview closed without `finishImport` taking the extracted backup.
    func notePreviewDismissed() {
        guard !isWorking, pendingRoot != nil else { return }
        cancelImport()
    }

    func cancelImport() {
        let root = pendingRoot
        pendingRoot = nil
        pendingDocument = nil
        preview = nil
        showPreview = false
        isWorking = false
        if let root {
            try? FileManager.default.removeItem(at: root)
        }
    }

    private func receiveImport(_ document: AiboBackupArchive.Document, root: URL) {
        guard AppSettings.shared.backupPreferencesAreReadable(document.settings) else {
            try? FileManager.default.removeItem(at: root)
            isWorking = false
            errorMessage = String(localized: "This backup's preferences can't be read.")
            return
        }
        pendingRoot = root
        pendingDocument = document
        preview = BackupImportPreview(document: document)
        playtimeMode = .add
        isWorking = false
        showPreview = true
    }

    private static func archiveURL(_ url: URL) -> URL {
        if url.pathExtension.lowercased() == AiboBackupArchive.fileExtension {
            return url
        }
        let stripped = url.deletingPathExtension()
        if url.pathExtension.lowercased() == "zip",
           stripped.pathExtension.lowercased() == AiboBackupArchive.fileExtension
        {
            return stripped
        }
        return url.appendingPathExtension(AiboBackupArchive.fileExtension)
    }

    private static func message(for error: Error, importing: Bool) -> String {
        guard let error = error as? AiboBackupError else {
            return importing
                ? String(localized: "Couldn't import the backup.")
                : String(localized: "Couldn't export the backup.")
        }
        switch error {
        case .unsupportedFormat:
            return String(localized: "This backup was made by a newer version of Aibo.")
        case .unsafePath:
            return String(localized: "This backup contains an unsafe file.")
        case .invalidContents, .unreadable:
            return String(localized: "This isn't an Aibo backup.")
        case .ioFailed:
            return importing
                ? String(localized: "Couldn't import the backup.")
                : String(localized: "Couldn't export the backup.")
        }
    }
}

struct BackupSettingsPane: View {
    @Bindable private var model = BackupSettingsModel.shared

    var body: some View {
        Form {
            Section {
                Button(String(localized: "Export…")) {
                    model.export()
                }
                .disabled(model.isWorking)

                Button(String(localized: "Import…")) {
                    model.chooseImport()
                }
                .disabled(model.isWorking)
            } footer: {
                Text(String(localized: "Includes aibos, preferences, and companion time. Webhook secrets and plugin settings stay on this Mac."))
            }
        }
        .formStyle(.grouped)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .settingsDetailChrome(title: String(localized: "Backup"))
        .sheet(isPresented: $model.showPreview, onDismiss: {
            model.notePreviewDismissed()
        }) {
            BackupImportSheet()
        }
        .alert(
            String(localized: "Backup"),
            isPresented: Binding(
                get: { model.errorMessage != nil },
                set: { if !$0 { model.errorMessage = nil } }
            )
        ) {
            Button(String(localized: "OK"), role: .cancel) {}
        } message: {
            Text(model.errorMessage ?? "")
        }
    }
}

struct BackupImportPreview {
    var exportedAt: Date
    var appVersion: String
    var aiboNames: [String]
    var includesPoliAdjustments: Bool
    var themeTitle: String
    var languageTitle: String
    var webhookEnabled: Bool
    var webhookPort: Int
    var playtimeLines: [(name: String, seconds: Int)]

    init(document: AiboBackupArchive.Document) {
        exportedAt = document.manifest.exportedAt
        appVersion = document.manifest.appVersion
        let libraryURL = document.aibosDirectory.appendingPathComponent(AiboPaths.libraryFileName)
        if let data = try? Data(contentsOf: libraryURL),
           let file = try? AiboLibraryCodec.decode(data)
        {
            aiboNames = file.records
                .filter { $0.kind != .builtInDefault }
                .map(\.displayName)
            includesPoliAdjustments = file.builtInHidden
                || file.records.contains { $0.id == AiboLibraryDefaults.builtInID }
        } else {
            aiboNames = []
            includesPoliAdjustments = false
        }
        themeTitle = (AppThemeMode(rawValue: document.settings.themeMode) ?? .system).title
        languageTitle = (AppLanguageMode(rawValue: document.settings.languageMode) ?? .system).title
        webhookEnabled = document.settings.webhookEnabled
        webhookPort = document.settings.webhookPort
        playtimeLines = document.playtime.records
            .filter { $0.totalSeconds > 0 }
            .sorted { $0.totalSeconds > $1.totalSeconds }
            .map { ($0.displayName, $0.totalSeconds) }
    }
}

private struct BackupImportSheet: View {
    @Bindable private var model = BackupSettingsModel.shared

    private static let listedPlaytimeLimit = 8

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            VStack(alignment: .leading, spacing: 4) {
                Text(String(localized: "Import This Backup?"))
                    .font(.title2)
                if let preview = model.preview {
                    Text(header(preview))
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
            }

            if let preview = model.preview {
                ScrollView {
                    VStack(alignment: .leading, spacing: 16) {
                        section(String(localized: "Aibos")) {
                            if preview.aiboNames.isEmpty {
                                Text(String(localized: "No installed aibos"))
                            } else {
                                Text(verbatim: preview.aiboNames.joined(separator: "\n"))
                            }
                            if preview.includesPoliAdjustments {
                                Text(String(localized: "Poli’s size and bubble in this file replace this Mac’s. The built-in image is not in the backup."))
                                    .font(.subheadline)
                                    .foregroundStyle(.secondary)
                            }
                        }

                        section(String(localized: "Preferences")) {
                            labeled(String(localized: "Theme"), preview.themeTitle)
                            labeled(String(localized: "Language"), preview.languageTitle)
                            labeled(String(localized: "Webhook"), webhookLine(preview))
                        }

                        section(String(localized: "Companion Time")) {
                            if preview.playtimeLines.isEmpty {
                                Text(String(localized: "No recorded time"))
                            } else {
                                let listed = preview.playtimeLines.prefix(Self.listedPlaytimeLimit)
                                Text(verbatim: listed.map { "\($0.name)  \(duration($0.seconds))" }.joined(separator: "\n"))
                                let extra = preview.playtimeLines.count - listed.count
                                if extra > 0 {
                                    Text(String(localized: "And \(extra) more"))
                                        .foregroundStyle(.secondary)
                                }
                            }
                        }
                    }
                }
                .frame(maxHeight: 320)

                Picker(String(localized: "Companion Time"), selection: $model.playtimeMode) {
                    Text(String(localized: "Add Time")).tag(AiboBackupPlaytimeMode.add)
                    Text(String(localized: "Replace Time")).tag(AiboBackupPlaytimeMode.replace)
                }
                .pickerStyle(.radioGroup)
                .labelsHidden()

                if model.playtimeMode == .add {
                    Text(String(localized: "Adding time counts any shared history twice."))
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                } else {
                    Text(String(localized: "Replace this Mac’s companion time with the backup."))
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
            }

            HStack {
                Spacer()
                Button(String(localized: "Cancel"), role: .cancel) {
                    model.cancelImport()
                }
                Button(String(localized: "Import")) {
                    model.confirmImport()
                }
                .keyboardShortcut(.defaultAction)
                .disabled(model.preview == nil || model.isWorking)
            }
        }
        .padding(20)
        .frame(width: 440)
    }

    private func header(_ preview: BackupImportPreview) -> String {
        let date = preview.exportedAt.formatted(date: .abbreviated, time: .shortened)
        let version = preview.appVersion.isEmpty ? "—" : preview.appVersion
        return String(localized: "Exported \(date) · Aibo \(version)")
    }

    private func webhookLine(_ preview: BackupImportPreview) -> String {
        if preview.webhookEnabled {
            return String(localized: "On, port \(preview.webhookPort)")
        }
        return String(localized: "Off")
    }

    private func duration(_ seconds: Int) -> String {
        switch PlaytimeCompanionSpan.from(seconds: seconds) {
        case .hoursAndMinutes(let hours, let minutes):
            return "\(hours)h \(minutes)m"
        case .daysAndHours(let days, let hours):
            return "\(days)d \(hours)h"
        }
    }

    private func section<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(.headline)
            content()
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private func labeled(_ title: String, _ value: String) -> some View {
        LabeledContent(title) {
            Text(value)
                .foregroundStyle(.secondary)
        }
    }
}
