import Foundation

public enum SettingsShowDestination: Codable, Sendable, Equatable {
    case plain
    case webhookRoot
    case extensionDetail(id: String)
    case backup(importArchivePath: String?)
    case hookCleanup
}

public enum SettingsTunnelHealthWire: String, Codable, Sendable, Equatable {
    case unknown
    case skipped
    case checking
    case ok
    case down
    case listenerStopped
}

/// Complete preferences payload mirrored between main and settings processes so
/// edits apply immediately without waiting on cross-process `cfprefsd` caching.
public struct SettingsAppPreferencesWire: Codable, Sendable, Equatable {
    public var backup: AiboBackupSettings
    public var savedAiboPositionScreenUUID: String?
    public var keystrokeOverlayEnabled: Bool
    public var keystrokeLingerSeconds: Int
    public var keystrokeMaxCount: Int
    public var webhookSecret: String

    public init(
        backup: AiboBackupSettings,
        savedAiboPositionScreenUUID: String?,
        keystrokeOverlayEnabled: Bool,
        keystrokeLingerSeconds: Int,
        keystrokeMaxCount: Int,
        webhookSecret: String
    ) {
        self.backup = backup
        self.savedAiboPositionScreenUUID = savedAiboPositionScreenUUID
        self.keystrokeOverlayEnabled = keystrokeOverlayEnabled
        self.keystrokeLingerSeconds = keystrokeLingerSeconds
        self.keystrokeMaxCount = keystrokeMaxCount
        self.webhookSecret = webhookSecret
    }
}

public struct SettingsMainSnapshot: Codable, Sendable, Equatable {
    public var cursorHooksInstalled: Bool
    public var codexHooksInstalled: Bool
    public var deepseekPluginInstalled: Bool
    public var antigravityHooksInstalled: Bool
    public var cursorHostAppInstalled: Bool
    public var codexHostAppInstalled: Bool
    public var antigravityHostAppInstalled: Bool
    public var webhookListening: Bool
    public var tunnelHealthStatus: SettingsTunnelHealthWire
    public var lastRuntimeErrorMessage: String?
    public var ingestLoggingEnabled: Bool
    public var ingestLogEntryCount: Int
    public var receiveLogEntries: [ReceiveLogEntry]
    public var receiveLogTotalCount: Int

    public var hasUpdateFeed: Bool
    public var canCheckForUpdates: Bool
    public var automaticallyChecksForUpdates: Bool
    public var availableUpdateDisplayVersion: String?

    public var keystrokeAccessibilityTrusted: Bool

    public var playtimeSnapshot: PlaytimeSnapshot
    public var playtimeDaily: PlaytimeDailyBook

    public var showHitRegionDebug: Bool
    public var musicDebugForcePlaying: Bool
    public var musicIsPlaying: Bool
    public var mediaRemoteUpdateCount: Int
    public var mediaRemoteLastDump: String

    public init(
        cursorHooksInstalled: Bool = false,
        codexHooksInstalled: Bool = false,
        deepseekPluginInstalled: Bool = false,
        antigravityHooksInstalled: Bool = false,
        cursorHostAppInstalled: Bool = false,
        codexHostAppInstalled: Bool = false,
        antigravityHostAppInstalled: Bool = false,
        webhookListening: Bool = false,
        tunnelHealthStatus: SettingsTunnelHealthWire = .unknown,
        lastRuntimeErrorMessage: String? = nil,
        ingestLoggingEnabled: Bool = false,
        ingestLogEntryCount: Int = 0,
        receiveLogEntries: [ReceiveLogEntry] = [],
        receiveLogTotalCount: Int = 0,
        hasUpdateFeed: Bool = false,
        canCheckForUpdates: Bool = false,
        automaticallyChecksForUpdates: Bool = false,
        availableUpdateDisplayVersion: String? = nil,
        keystrokeAccessibilityTrusted: Bool = true,
        playtimeSnapshot: PlaytimeSnapshot = PlaytimeSnapshot(),
        playtimeDaily: PlaytimeDailyBook = PlaytimeDailyBook(),
        showHitRegionDebug: Bool = false,
        musicDebugForcePlaying: Bool = false,
        musicIsPlaying: Bool = false,
        mediaRemoteUpdateCount: Int = 0,
        mediaRemoteLastDump: String = "(no update yet)"
    ) {
        self.cursorHooksInstalled = cursorHooksInstalled
        self.codexHooksInstalled = codexHooksInstalled
        self.deepseekPluginInstalled = deepseekPluginInstalled
        self.antigravityHooksInstalled = antigravityHooksInstalled
        self.cursorHostAppInstalled = cursorHostAppInstalled
        self.codexHostAppInstalled = codexHostAppInstalled
        self.antigravityHostAppInstalled = antigravityHostAppInstalled
        self.webhookListening = webhookListening
        self.tunnelHealthStatus = tunnelHealthStatus
        self.lastRuntimeErrorMessage = lastRuntimeErrorMessage
        self.ingestLoggingEnabled = ingestLoggingEnabled
        self.ingestLogEntryCount = ingestLogEntryCount
        self.receiveLogEntries = receiveLogEntries
        self.receiveLogTotalCount = receiveLogTotalCount
        self.hasUpdateFeed = hasUpdateFeed
        self.canCheckForUpdates = canCheckForUpdates
        self.automaticallyChecksForUpdates = automaticallyChecksForUpdates
        self.availableUpdateDisplayVersion = availableUpdateDisplayVersion
        self.keystrokeAccessibilityTrusted = keystrokeAccessibilityTrusted
        self.playtimeSnapshot = playtimeSnapshot
        self.playtimeDaily = playtimeDaily
        self.showHitRegionDebug = showHitRegionDebug
        self.musicDebugForcePlaying = musicDebugForcePlaying
        self.musicIsPlaying = musicIsPlaying
        self.mediaRemoteUpdateCount = mediaRemoteUpdateCount
        self.mediaRemoteLastDump = mediaRemoteLastDump
    }
}

public struct SettingsDebugBubblePayload: Codable, Sendable, Equatable {
    public var text: String
    public var agentName: String
    public var projectName: String?
    public var modelName: String?
    public var showCursorIcon: Bool
    public var isSubagent: Bool
    public var stack: Bool
    public var isAwaitingApproval: Bool
    public var showsPlanProgress: Bool
    public var planProgressIntervalSeconds: Int

    public init(
        text: String,
        agentName: String,
        projectName: String?,
        modelName: String?,
        showCursorIcon: Bool,
        isSubagent: Bool,
        stack: Bool,
        isAwaitingApproval: Bool,
        showsPlanProgress: Bool,
        planProgressIntervalSeconds: Int
    ) {
        self.text = text
        self.agentName = agentName
        self.projectName = projectName
        self.modelName = modelName
        self.showCursorIcon = showCursorIcon
        self.isSubagent = isSubagent
        self.stack = stack
        self.isAwaitingApproval = isAwaitingApproval
        self.showsPlanProgress = showsPlanProgress
        self.planProgressIntervalSeconds = planProgressIntervalSeconds
    }
}

public enum SettingsLibraryMutation: Codable, Sendable, Equatable {
    case select(id: String)
    case setScalePercent(percent: Double)
    case setBubbleDistance(distance: Double)
    case setBubblePlacement(placement: BubblePlacement)
    case setPixelOptimization(enabled: Bool)
    case rename(id: String, name: String)
    case remove(ids: [String])
    case reloadAfterDiskImport(installedID: String)
}

public enum SettingsCommand: Codable, Sendable, Equatable {
    case refreshHostAppPresence
    case refreshHookInstallation
    case recheckAccessibility
    case installHooks(AgentKind)
    case uninstallHooks(AgentKind)
    case scheduleTunnelCheck
    case clearReceiveLog
    case regenerateWebhookSecret
    case setIngestLoggingEnabled(Bool)
    case refreshIngestLogCount
    case clearIngestLog
    case checkForUpdates
    case setAutomaticallyChecksForUpdates(Bool)
    case reloadExtensions
    case hookSpriteMappingChanged
    case actionSpriteMappingChanged
    case relaunchMainApp

    case debugShowBubble(SettingsDebugBubblePayload)
    case debugShowTunnelWarningBubble
    case debugClearBubble
    case debugReplayOnboarding
    case debugReplayLaunchPortal
    case debugSetShowHitRegion(Bool)
    case debugSetMusicForcePlaying(Bool)
    case debugFetchMediaRemoteOnce
    case debugTriggerDodge
    case debugMouseShakeConfigChanged(MouseShakeConfig)
    case debugPresentExtensionWindow(running: Bool)
    case debugIngestWebhookBody(Data)
    case debugShowAvailableUpdate
    case debugShowUpToDate
    case debugClearUpdatePreview
}

public enum SettingsRPCRequest: Codable, Sendable, Equatable {
    case prepareBackupExport(includeHookLog: Bool)
    case finishBackupImport(
        hookLogPath: String?,
        playtimeFile: AiboBackupPlaytimeFile,
        playtimeMode: AiboBackupPlaytimeMode,
        applySettings: AiboBackupSettings?
    )
    case postTestWebhook(body: Data)
    case exportReceiveLog
    case copyIngestLogJSONL
}

public enum SettingsRPCReply: Codable, Sendable, Equatable {
    case backupExportPrepared(playtime: AiboBackupPlaytimeFile, hookLogTempPath: String?)
    case backupImportFinished(errorMessage: String?)
    case testWebhookResult(errorMessage: String?)
    case receiveLogData(Data?)
    case ingestLogJSONL(String?)
    case failed(String)
}

public enum MainToSettingsMessage: Codable, Sendable, Equatable {
    case show(destination: SettingsShowDestination, rememberedPaneID: String?)
    case snapshot(SettingsMainSnapshot)
    case preferences(SettingsAppPreferencesWire)
    case libraryReload
    case extensionsReload
    case hookSpritesReload
    case actionSpritesReload
    case reply(id: UInt64, reply: SettingsRPCReply)
    case readyToClose
    case terminate
}

public enum SettingsToMainMessage: Codable, Sendable, Equatable {
    case ready(pid: Int32)
    case rememberPane(id: String?)
    case preferences(SettingsAppPreferencesWire)
    case library(SettingsLibraryMutation)
    case command(SettingsCommand)
    case request(id: UInt64, request: SettingsRPCRequest)
    case openURLs([String])
    case closing
}
