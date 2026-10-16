import AiboCore
import AppKit
import SwiftUI
import UniformTypeIdentifiers

private enum BackupExportPreference {
    static let hookLogKey = "settings.backup.exportHookLog"
}

@MainActor
@Observable
final class BackupSettingsModel {
    static let shared = BackupSettingsModel()

    /// When on, an export copies the hook log into the archive. Off by default, and not itself part of the backup.
    var exportHookLog = UserDefaults.standard.bool(forKey: BackupExportPreference.hookLogKey) {
        didSet {
            UserDefaults.standard.set(exportHookLog, forKey: BackupExportPreference.hookLogKey)
        }
    }
    var isWorking = false
    var errorMessage: String?
    var showPreview = false
    var settingsImport: BackupSettingsImport = .skip
    var duplicateImport: AiboBackupDuplicateImport = .add
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
        let hookLogCopy: URL?
        if exportHookLog {
            do {
                hookLogCopy = try AiboRuntime.shared.copyIngestLogForBackup()
            } catch {
                errorMessage = Self.message(for: error, importing: false)
                return
            }
        } else {
            hookLogCopy = nil
        }
        isWorking = true
        Task.detached {
            defer {
                if let hookLogCopy {
                    try? FileManager.default.removeItem(at: hookLogCopy)
                }
            }
            do {
                try AiboBackupArchive.write(
                    settings: settings,
                    playtime: playtime,
                    aibosSource: aibos,
                    hookLogSource: hookLogCopy,
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
        startImport(from: url)
    }

    /// Finder double-click. Opens Backup, then the same preview as Import….
    func importArchiveFromOutside(_ url: URL) {
        SettingsNavigator.shared.showBackup()
        guard !isWorking else { return }
        if pendingRoot != nil || showPreview {
            cancelImport()
        }
        startImport(from: url)
    }

    private func startImport(from url: URL) {
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

    func finishImport(
        settingsChoice: BackupSettingsImport,
        duplicates: AiboBackupDuplicateImport,
        playtime: AiboBackupPlaytimeMode
    ) {
        guard let document = pendingDocument, let root = pendingRoot else { return }
        pendingDocument = nil
        pendingRoot = nil
        preview = nil
        showPreview = false
        isWorking = true
        let settings = document.settings
        let playtimeFile = document.playtime
        let aibos = document.aibosDirectory
        let localRecords = AiboLibraryStore.shared.records
        let localSelectedID = AiboLibraryStore.shared.selectedID
        Task.detached {
            do {
                var replacement = try AiboBackupArchive.mergeLibrary(
                    at: AiboPaths.aibosDirectory,
                    with: aibos,
                    localRecords: localRecords,
                    localSelectedID: localSelectedID,
                    duplicates: duplicates
                )
                if let hookLog = document.hookLogURL {
                    do {
                        try await MainActor.run {
                            try AiboRuntime.shared.importIngestLog(from: hookLog)
                        }
                    } catch {
                        try? replacement.restore()
                        await MainActor.run {
                            AiboLibraryStore.shared.adoptImportedLibrary()
                            BackupSettingsModel.shared.isWorking = false
                            BackupSettingsModel.shared.errorMessage = Self.message(for: error, importing: true)
                        }
                        try? FileManager.default.removeItem(at: root)
                        return
                    }
                }
                await MainActor.run {
                    AiboLibraryStore.shared.adoptImportedLibrary()
                    if playtime != .skip {
                        PlaytimeStore.shared.importBackup(playtimeFile, mode: playtime)
                    }
                    guard settingsChoice == .apply else { return }
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
                    if settingsChoice == .apply {
                        AppSettings.shared.applyBackupLanguage(settings)
                    }
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
        finishImport(
            settingsChoice: settingsImport,
            duplicates: duplicateImport,
            playtime: playtimeMode
        )
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
        preview = BackupImportPreview(
            document: document,
            localNames: AiboLibraryStore.shared.records.map(\.displayName),
            currentSettings: AppSettings.shared.backupSnapshot()
        )
        settingsImport = .skip
        duplicateImport = .add
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
                Toggle(String(localized: "Export Hook Log"), isOn: $model.exportHookLog)
                    .disabled(model.isWorking)

                BackupActionRow(
                    systemName: "arrowshape.down.fill",
                    title: String(localized: "Export"),
                    subtitle: String(localized: "Back up Aibo's data"),
                    buttonTitle: String(localized: "Export"),
                    isEnabled: !model.isWorking,
                    action: model.export
                )
            } header: {
                Text(String(localized: "Export"))
            } footer: {
                Text(String(localized: "API keys and other private information are not exported."))
            }

            Section {
                BackupActionRow(
                    systemName: "arrowshape.up.fill",
                    title: String(localized: "Import"),
                    subtitle: String(localized: "You'll confirm the backup before restoring it."),
                    buttonTitle: String(localized: "Import"),
                    isEnabled: !model.isWorking,
                    action: model.chooseImport
                )
            } header: {
                Text(String(localized: "Import"))
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

enum BackupSettingsImport: Sendable, Equatable, Hashable {
    case apply
    case skip
}

struct BackupImportPreview {
    var exportedAt: Date
    var appVersion: String
    var newAiboCount: Int
    var duplicateAiboCount: Int
    var settingsDifferenceCount: Int
    var playtimeLines: [(name: String, seconds: Int)]

    init(
        document: AiboBackupArchive.Document,
        localNames: [String],
        currentSettings: AiboBackupSettings
    ) {
        exportedAt = document.manifest.exportedAt
        appVersion = document.manifest.appVersion
        let libraryURL = document.aibosDirectory.appendingPathComponent(AiboPaths.libraryFileName)
        let incoming: [AiboLibraryRecord]
        if let data = try? Data(contentsOf: libraryURL),
           let file = try? AiboLibraryCodec.decode(data)
        {
            incoming = file.records
        } else {
            incoming = []
        }
        let local = localNames.map {
            AiboLibraryRecord(id: "local", kind: .staticImage, displayName: $0, relativePath: "local")
        }
        let summary = AiboBackupLibraryImport.summary(localRecords: local, incomingRecords: incoming)
        newAiboCount = summary.newCount
        duplicateAiboCount = summary.duplicateCount
        settingsDifferenceCount = document.settings.differenceCount(from: currentSettings)
        playtimeLines = document.playtime.records
            .filter { $0.totalSeconds > 0 }
            .sorted { $0.totalSeconds > $1.totalSeconds }
            .map { ($0.displayName, $0.totalSeconds) }
    }
}

private struct BackupImportSheet: View {
    @Bindable private var model = BackupSettingsModel.shared

    private static let playtimeRowHeight: CGFloat = 20
    private static let visiblePlaytimeRows = 6

    var body: some View {
        VStack(spacing: 0) {
            Form {
                Section {
                    if let preview = model.preview {
                        LabeledContent(String(localized: "Backup Version")) {
                            Text(verbatim: preview.appVersion.isEmpty ? "—" : preview.appVersion)
                                .foregroundStyle(.secondary)
                        }
                        LabeledContent(String(localized: "Backup Time")) {
                            Text(verbatim: backupTime(preview.exportedAt))
                                .foregroundStyle(.secondary)
                        }
                        LabeledContent(String(localized: "Aibo Count")) {
                            Text(aiboCount(preview))
                                .foregroundStyle(.secondary)
                        }
                        LabeledContent(String(localized: "Preferences")) {
                            Text(settingsCount(preview))
                                .foregroundStyle(.secondary)
                        }
                        LabeledContent(String(localized: "Companion Time List")) {
                            playtimeList(preview)
                        }
                    }
                } header: {
                    Text(String(localized: "Import Preview"))
                }

                Section {
                    optionRow(String(localized: "Import Preferences"), selection: $model.settingsImport) {
                        Text(String(localized: "Import")).tag(BackupSettingsImport.apply)
                        Text(String(localized: "Don't Import")).tag(BackupSettingsImport.skip)
                    }
                    optionRow(String(localized: "Duplicate Aibos"), selection: $model.duplicateImport) {
                        Text(String(localized: "Add as New")).tag(AiboBackupDuplicateImport.add)
                        Text(String(localized: "Overwrite")).tag(AiboBackupDuplicateImport.replace)
                        Text(String(localized: "Don't Import")).tag(AiboBackupDuplicateImport.skip)
                    }
                    optionRow(String(localized: "Import Companion Time"), selection: $model.playtimeMode) {
                        Text(String(localized: "Add On")).tag(AiboBackupPlaytimeMode.add)
                        Text(String(localized: "Overwrite")).tag(AiboBackupPlaytimeMode.replace)
                        Text(String(localized: "Don't Import")).tag(AiboBackupPlaytimeMode.skip)
                    }
                } header: {
                    Text(String(localized: "Import Options"))
                } footer: {
                    if model.playtimeMode == .add {
                        Text(String(localized: "Adding time counts any shared history twice."))
                    }
                }
            }
            .formStyle(.grouped)

            HStack {
                Spacer()
                Button(String(localized: "Cancel"), role: .cancel) {
                    model.cancelImport()
                }
                Button(String(localized: "Import")) {
                    model.confirmImport()
                }
                .keyboardShortcut(.defaultAction)
                .buttonStyle(.borderedProminent)
                .disabled(model.preview == nil || model.isWorking)
            }
            .padding([.horizontal, .bottom], 20)
        }
        .frame(width: 560)
    }

    private func optionRow<Choice: Hashable, Content: View>(
        _ title: String,
        selection: Binding<Choice>,
        @ViewBuilder content: () -> Content
    ) -> some View {
        LabeledContent(title) {
            Picker(title, selection: selection) {
                content()
            }
            .pickerStyle(.radioGroup)
            .horizontalRadioGroupLayout()
            .labelsHidden()
            .fixedSize(horizontal: true, vertical: false)
        }
    }

    private func aiboCount(_ preview: BackupImportPreview) -> String {
        if preview.newAiboCount == 0, preview.duplicateAiboCount == 0 {
            return differenceCount(0)
        }
        return String(localized: "\(preview.newAiboCount) new, \(preview.duplicateAiboCount) with the same name")
    }

    private func settingsCount(_ preview: BackupImportPreview) -> String {
        differenceCount(preview.settingsDifferenceCount)
    }

    private func differenceCount(_ count: Int) -> String {
        String(localized: "\(count) differences")
    }

    private func backupTime(_ date: Date) -> String {
        let parts = Calendar.current.dateComponents([.year, .month, .day, .hour, .minute], from: date)
        return String(
            format: "%04d.%02d.%02d %02d:%02d",
            parts.year ?? 0,
            parts.month ?? 0,
            parts.day ?? 0,
            parts.hour ?? 0,
            parts.minute ?? 0
        )
    }

    @ViewBuilder
    private func playtimeList(_ preview: BackupImportPreview) -> some View {
        if preview.playtimeLines.isEmpty {
            Text(String(localized: "No recorded time"))
                .foregroundStyle(.secondary)
        } else {
            let height = CGFloat(min(preview.playtimeLines.count, Self.visiblePlaytimeRows)) * Self.playtimeRowHeight
            ScrollView {
                VStack(alignment: .trailing, spacing: 2) {
                    ForEach(Array(preview.playtimeLines.enumerated()), id: \.offset) { _, line in
                        Text(verbatim: "\(duration(line.seconds)) · \(line.name)")
                            .foregroundStyle(.secondary)
                            .frame(maxWidth: .infinity, alignment: .trailing)
                    }
                }
            }
            .frame(height: height)
        }
    }

    private func duration(_ seconds: Int) -> String {
        switch PlaytimeCompanionSpan.from(seconds: seconds) {
        case .hoursAndMinutes(let hours, let minutes):
            return "\(hours)h \(minutes)m"
        case .daysAndHours(let days, let hours):
            return "\(days)d \(hours)h"
        }
    }
}

private struct BackupActionRow: View {
    var systemName: String
    var title: String
    var subtitle: String
    var buttonTitle: String
    var isEnabled: Bool
    var action: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            BackupActionIcon(systemName: systemName)
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                Text(subtitle)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 12)
            Button(buttonTitle, action: action)
                .buttonStyle(.bordered)
                .disabled(!isEnabled)
        }
    }
}

private struct BackupActionIcon: View {
    var systemName: String

    private let side: CGFloat = 28

    var body: some View {
        RoundedRectangle(cornerRadius: 6, style: .continuous)
            .fill(.primary)
            .frame(width: side, height: side)
            .overlay {
                Image(nsImage: Self.centeredSymbol(systemName, pointSize: 20))
                    .renderingMode(.template)
                    .resizable()
                    .scaledToFit()
                    .frame(width: 14, height: 14)
                    .foregroundStyle(Color(nsColor: .windowBackgroundColor))
            }
    }

    private static func centeredSymbol(_ name: String, pointSize: CGFloat) -> NSImage {
        let config = NSImage.SymbolConfiguration(pointSize: pointSize, weight: .semibold)
        guard let symbol = NSImage(systemSymbolName: name, accessibilityDescription: nil)?
            .withSymbolConfiguration(config)
        else {
            return NSImage()
        }
        let baked = NSImage(size: symbol.size, flipped: false) { rect in
            symbol.draw(in: rect, from: .zero, operation: .sourceOver, fraction: 1)
            return true
        }
        baked.isTemplate = true
        return baked
    }
}
