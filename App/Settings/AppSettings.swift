import AiboCore
import AiboIngest
import AppKit
import Foundation
import Security
import SwiftUI

enum MusicNotesColorMode: String, CaseIterable, Identifiable, Sendable, Hashable {
    case aiboAccent
    case custom

    var id: String { rawValue }

    var title: String {
        switch self {
        case .aiboAccent: String(localized: "Aibo Accent Color")
        case .custom: String(localized: "Custom")
        }
    }
}

@MainActor
@Observable
final class AppSettings {
    static let shared = AppSettings()

    private enum Keys {
        static let themeMode = "settings.themeMode"
        static let bubblePlacement = "settings.bubblePlacement"
        static let bubbleGlassStyle = "settings.bubbleGlassStyle"
        static let bubbleGlassTint = "settings.bubbleGlassTint"
        static let cursorBubbleGlassStyle = "settings.agentBubbleGlassStyle.cursor"
        static let codexBubbleGlassStyle = "settings.agentBubbleGlassStyle.codex"
        static let deepseekBubbleGlassStyle = "settings.agentBubbleGlassStyle.deepseek"
        static let cursorBubbleGlassTint = "settings.agentBubbleGlassTint.cursor"
        static let codexBubbleGlassTint = "settings.agentBubbleGlassTint.codex"
        static let deepseekBubbleGlassTint = "settings.agentBubbleGlassTint.deepseek"
        static let cursorCapsuleColor = "settings.agentCapsuleColor.cursor"
        static let codexCapsuleColor = "settings.agentCapsuleColor.codex"
        static let deepseekCapsuleColor = "settings.agentCapsuleColor.deepseek"
        static let aiboScalePercent = "settings.aiboScalePercent"
        static let pixelOptimizationEnabled = "settings.pixelOptimizationEnabled"
        static let restoreLastAiboPosition = "settings.restoreLastAiboPosition"
        static let hideWhenFullscreen = "settings.hideWhenFullscreen"
        static let disableMouseTracking = "settings.disableMouseTracking"
        static let aiboPositionXPercent = "settings.aiboPositionXPercent"
        static let aiboPositionYPercent = "settings.aiboPositionYPercent"
        static let musicNotesEnabled = "settings.musicNotesEnabled"
        static let musicNotesColorMode = "settings.musicNotesColorMode"
        static let musicNotesCustomColor = "settings.musicNotesCustomColor"
        static let customMusicNotificationNames = "settings.customMusicNotificationNames"
        static let webhookEnabled = "settings.webhookEnabled"
        static let webhookPort = "settings.webhookPort"
        static let webhookDismissMode = "settings.webhookDismissMode"
        static let webhookAutoDismissSeconds = "settings.webhookAutoDismissSeconds"
        static let publicWebhookURL = "settings.publicWebhookURL"
        static let settingsWindowHeight = "settings.windowHeight"
        static let webhookSecretAccount = "webhook.sharedSecret"
    }

    static let defaultWebhookPort: UInt16 = 8787
    /// Aibo image size as a percentage of the base 96pt sprite. Range 0…300; default 100.
    static let defaultAiboScalePercent: Double = 100
    static let aiboScalePercentRange: ClosedRange<Double> = 0...300
    /// Discrete sizes while Pixel Optimization is on (integer-scale display).
    static let pixelOptimizationScalePercents: [Double] = [50, 100, 150, 200, 250, 300]
    static let defaultWebhookAutoDismissSeconds = 12
    static let webhookAutoDismissSecondsRange = 1...600

    /// Settings window content width (fixed; only height is user-resizable).
    static let settingsWindowWidth: CGFloat = 680
    static let defaultSettingsWindowHeight: CGFloat = 720
    static let settingsWindowMinHeight: CGFloat = 420

    /// Color scheme: follow system (default), force light, or force dark.
    var themeMode: AppThemeMode {
        didSet {
            guard oldValue != themeMode else { return }
            UserDefaults.standard.set(themeMode.rawValue, forKey: Keys.themeMode)
            Self.applyAppearance(themeMode)
            AiboPanelController.shared.refreshContent()
        }
    }

    var bubblePlacement: BubblePlacement {
        didSet {
            guard oldValue != bubblePlacement else { return }
            UserDefaults.standard.set(bubblePlacement.rawValue, forKey: Keys.bubblePlacement)
            AiboPanelController.shared.refreshContent()
        }
    }

    /// Aibo sprite scale relative to the default size (`100` = 96×96 pt).
    var aiboScalePercent: Double {
        didSet {
            let adjusted = Self.normalizedAiboScalePercent(
                aiboScalePercent,
                pixelOptimizationEnabled: pixelOptimizationEnabled
            )
            if adjusted != aiboScalePercent {
                aiboScalePercent = adjusted
                return
            }
            guard oldValue != aiboScalePercent else { return }
            UserDefaults.standard.set(aiboScalePercent, forKey: Keys.aiboScalePercent)
            AiboPanelController.shared.refreshContent()
        }
    }

    /// Integer-scale pixel-art display plus grid recovery. Default off.
    var pixelOptimizationEnabled: Bool = false {
        didSet {
            guard oldValue != pixelOptimizationEnabled else { return }
            UserDefaults.standard.set(pixelOptimizationEnabled, forKey: Keys.pixelOptimizationEnabled)
            if pixelOptimizationEnabled {
                let steps = AiboSpriteDisplay.pixelOptimizationPercents(
                    for: AiboLibraryStore.shared.selectedRecord,
                    backingScale: NSScreen.main?.backingScaleFactor ?? 2
                )
                aiboScalePercent = Self.snapAiboScalePercentToPixelSteps(
                    aiboScalePercent,
                    steps: steps
                )
            }
            AiboSpriteCache.shared.invalidate()
            AiboAppearance.invalidateDominantColorCache()
            AiboPanelController.shared.updateHitTestImage()
            AiboPanelController.shared.refreshContent()
        }
    }

    /// When true, the aibo opens at its last screen-relative position. Default on.
    var restoreLastAiboPosition: Bool {
        didSet {
            guard oldValue != restoreLastAiboPosition else { return }
            UserDefaults.standard.set(restoreLastAiboPosition, forKey: Keys.restoreLastAiboPosition)
        }
    }

    /// When true, hide the aibo for native fullscreen (Spaces type 4) or
    /// `currentSystemPresentationOptions` containing `.fullScreen`. Default on.
    var hideWhenFullscreen: Bool {
        didSet {
            guard oldValue != hideWhenFullscreen else { return }
            UserDefaults.standard.set(hideWhenFullscreen, forKey: Keys.hideWhenFullscreen)
            AiboPanelController.shared.syncFullscreenPolicy()
        }
    }

    /// When true, V2 idle pets stay on idle instead of looking at the pointer. Default off.
    var disableMouseTracking: Bool {
        didSet {
            guard oldValue != disableMouseTracking else { return }
            UserDefaults.standard.set(disableMouseTracking, forKey: Keys.disableMouseTracking)
            AiboPanelController.shared.syncLookDirection()
        }
    }

    /// Pet center X within the screen `visibleFrame`, 0…1. `nil` until the user has moved the aibo.
    private(set) var savedAiboCenterXPercent: Double?
    /// Pet center Y within the screen `visibleFrame`, 0…1. `nil` until the user has moved the aibo.
    private(set) var savedAiboCenterYPercent: Double?

    /// Overlay music-note rise effect while a known player is playing. Default on.
    var musicNotesEnabled: Bool {
        didSet {
            guard oldValue != musicNotesEnabled else { return }
            UserDefaults.standard.set(musicNotesEnabled, forKey: Keys.musicNotesEnabled)
            AiboRuntime.shared.syncMusicPlaybackMonitor()
            AiboPanelController.shared.refreshContent()
        }
    }

    /// Default `.aiboAccent` — notes follow the selected aibo’s dominant color.
    var musicNotesColorMode: MusicNotesColorMode {
        didSet {
            guard oldValue != musicNotesColorMode else { return }
            UserDefaults.standard.set(musicNotesColorMode.rawValue, forKey: Keys.musicNotesColorMode)
            AiboPanelController.shared.refreshContent()
        }
    }

    /// Used when `musicNotesColorMode == .custom`.
    var musicNotesCustomColor: Color {
        didSet {
            guard oldValue != musicNotesCustomColor else { return }
            Self.persistColor(musicNotesCustomColor, key: Keys.musicNotesCustomColor)
            AiboPanelController.shared.refreshContent()
        }
    }

    /// Extra distributed notification names (one per line) beyond built-in Music / Spotify.
    var customMusicNotificationNames: String {
        didSet {
            guard oldValue != customMusicNotificationNames else { return }
            UserDefaults.standard.set(customMusicNotificationNames, forKey: Keys.customMusicNotificationNames)
            MusicPlaybackMonitor.shared.reloadObservers()
        }
    }

    /// Liquid Glass variant for the status bubble. Default matches prior `.clear` look.
    var bubbleGlassStyle: BubbleGlassStyle {
        didSet {
            guard oldValue != bubbleGlassStyle else { return }
            UserDefaults.standard.set(bubbleGlassStyle.rawValue, forKey: Keys.bubbleGlassStyle)
            AiboPanelController.shared.refreshContent()
        }
    }

    /// Optional glass tint. `nil` means no tint (system default).
    var bubbleGlassTint: Color? {
        didSet {
            guard oldValue != bubbleGlassTint else { return }
            Self.persistColor(bubbleGlassTint, key: Keys.bubbleGlassTint)
            AiboPanelController.shared.refreshContent()
        }
    }

    /// Optional Cursor agent-capsule fill. `nil` keeps the default black/white capsule.
    var cursorCapsuleColor: Color? {
        didSet {
            guard oldValue != cursorCapsuleColor else { return }
            Self.persistColor(cursorCapsuleColor, key: Keys.cursorCapsuleColor)
            AiboPanelController.shared.refreshContent()
        }
    }

    /// Optional Codex agent-capsule fill. `nil` keeps the default black/white capsule.
    var codexCapsuleColor: Color? {
        didSet {
            guard oldValue != codexCapsuleColor else { return }
            Self.persistColor(codexCapsuleColor, key: Keys.codexCapsuleColor)
            AiboPanelController.shared.refreshContent()
        }
    }

    /// Optional DeepSeek agent-capsule fill. `nil` keeps the default black/white capsule.
    var deepseekCapsuleColor: Color? {
        didSet {
            guard oldValue != deepseekCapsuleColor else { return }
            Self.persistColor(deepseekCapsuleColor, key: Keys.deepseekCapsuleColor)
            AiboPanelController.shared.refreshContent()
        }
    }

    /// Cursor bubble glass. Seeded from the former global style when unset.
    var cursorBubbleGlassStyle: BubbleGlassStyle {
        didSet {
            guard oldValue != cursorBubbleGlassStyle else { return }
            UserDefaults.standard.set(cursorBubbleGlassStyle.rawValue, forKey: Keys.cursorBubbleGlassStyle)
            AiboPanelController.shared.refreshContent()
        }
    }

    var codexBubbleGlassStyle: BubbleGlassStyle {
        didSet {
            guard oldValue != codexBubbleGlassStyle else { return }
            UserDefaults.standard.set(codexBubbleGlassStyle.rawValue, forKey: Keys.codexBubbleGlassStyle)
            AiboPanelController.shared.refreshContent()
        }
    }

    var deepseekBubbleGlassStyle: BubbleGlassStyle {
        didSet {
            guard oldValue != deepseekBubbleGlassStyle else { return }
            UserDefaults.standard.set(deepseekBubbleGlassStyle.rawValue, forKey: Keys.deepseekBubbleGlassStyle)
            AiboPanelController.shared.refreshContent()
        }
    }

    /// Optional Cursor glass tint. `nil` means no tint.
    var cursorBubbleGlassTint: Color? {
        didSet {
            guard oldValue != cursorBubbleGlassTint else { return }
            Self.persistColor(cursorBubbleGlassTint, key: Keys.cursorBubbleGlassTint)
            AiboPanelController.shared.refreshContent()
        }
    }

    var codexBubbleGlassTint: Color? {
        didSet {
            guard oldValue != codexBubbleGlassTint else { return }
            Self.persistColor(codexBubbleGlassTint, key: Keys.codexBubbleGlassTint)
            AiboPanelController.shared.refreshContent()
        }
    }

    var deepseekBubbleGlassTint: Color? {
        didSet {
            guard oldValue != deepseekBubbleGlassTint else { return }
            Self.persistColor(deepseekBubbleGlassTint, key: Keys.deepseekBubbleGlassTint)
            AiboPanelController.shared.refreshContent()
        }
    }

    var webhookEnabled: Bool {
        didSet {
            guard oldValue != webhookEnabled else { return }
            UserDefaults.standard.set(webhookEnabled, forKey: Keys.webhookEnabled)
            AiboRuntime.shared.syncWebhookServer()
            TunnelHealthMonitor.shared.scheduleCheck(reason: .settingsChanged)
        }
    }

    var webhookPort: UInt16 {
        didSet {
            guard oldValue != webhookPort else { return }
            UserDefaults.standard.set(Int(webhookPort), forKey: Keys.webhookPort)
            AiboRuntime.shared.syncWebhookServer()
            TunnelHealthMonitor.shared.scheduleCheck(reason: .settingsChanged)
        }
    }

    /// Public HTTPS URL that reaches this Mac via the user’s tunnel (e.g. Cloudflare Tunnel).
    /// Empty → skip tunnel health checks. Not the loopback listener URL.
    var publicWebhookURLString: String {
        didSet {
            let trimmed = Self.normalizedPublicWebhookURL(publicWebhookURLString)
            if trimmed != publicWebhookURLString {
                publicWebhookURLString = trimmed
                return
            }
            guard oldValue != publicWebhookURLString else { return }
            UserDefaults.standard.set(publicWebhookURLString, forKey: Keys.publicWebhookURL)
            TunnelHealthMonitor.shared.scheduleCheck(reason: .settingsChanged)
        }
    }

    /// Default `.onClick` — webhook bubbles stay until the user dismisses them.
    var webhookDismissMode: WebhookDismissMode {
        didSet {
            guard oldValue != webhookDismissMode else { return }
            UserDefaults.standard.set(webhookDismissMode.rawValue, forKey: Keys.webhookDismissMode)
        }
    }

    /// Used when `webhookDismissMode == .afterSeconds`.
    var webhookAutoDismissSeconds: Int {
        didSet {
            let clamped = Self.clampWebhookAutoDismissSeconds(webhookAutoDismissSeconds)
            if clamped != webhookAutoDismissSeconds {
                webhookAutoDismissSeconds = clamped
                return
            }
            guard oldValue != webhookAutoDismissSeconds else { return }
            UserDefaults.standard.set(webhookAutoDismissSeconds, forKey: Keys.webhookAutoDismissSeconds)
        }
    }

    private(set) var webhookSecret: String

    /// Last Settings window content height. Width stays `settingsWindowWidth`.
    private(set) var settingsWindowHeight: CGFloat

    var webhookURLString: String {
        "http://127.0.0.1:\(webhookPort)\(WebhookRequestHandler.path)"
    }

    /// Trimmed public URL suitable for probing, or `nil` when unset/invalid.
    var resolvedPublicWebhookURL: URL? {
        let raw = publicWebhookURLString.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !raw.isEmpty, let url = URL(string: raw), let scheme = url.scheme?.lowercased(),
              scheme == "https" || scheme == "http",
              url.host != nil
        else { return nil }
        return url
    }

    private init() {
        Self.migrateLegacyPetKeys()

        let themeRaw = UserDefaults.standard.string(forKey: Keys.themeMode)
            ?? AppThemeMode.system.rawValue
        let resolvedTheme = AppThemeMode(rawValue: themeRaw) ?? .system
        themeMode = resolvedTheme
        Self.applyAppearance(resolvedTheme)

        let raw = UserDefaults.standard.string(forKey: Keys.bubblePlacement) ?? BubblePlacement.top.rawValue
        bubblePlacement = BubblePlacement(rawValue: raw) ?? .top

        let glassRaw = UserDefaults.standard.string(forKey: Keys.bubbleGlassStyle)
            ?? BubbleGlassStyle.clear.rawValue
        let resolvedGlassStyle = BubbleGlassStyle(rawValue: glassRaw) ?? .clear
        let resolvedGlassTint = Self.loadColor(key: Keys.bubbleGlassTint)
        bubbleGlassStyle = resolvedGlassStyle
        bubbleGlassTint = resolvedGlassTint
        let cursorGlass = Self.migrateAgentGlass(
            styleKey: Keys.cursorBubbleGlassStyle,
            tintKey: Keys.cursorBubbleGlassTint,
            globalStyle: resolvedGlassStyle,
            globalTint: resolvedGlassTint
        )
        cursorBubbleGlassStyle = cursorGlass.style
        cursorBubbleGlassTint = cursorGlass.tint
        let codexGlass = Self.migrateAgentGlass(
            styleKey: Keys.codexBubbleGlassStyle,
            tintKey: Keys.codexBubbleGlassTint,
            globalStyle: resolvedGlassStyle,
            globalTint: resolvedGlassTint
        )
        codexBubbleGlassStyle = codexGlass.style
        codexBubbleGlassTint = codexGlass.tint
        let deepseekGlass = Self.migrateAgentGlass(
            styleKey: Keys.deepseekBubbleGlassStyle,
            tintKey: Keys.deepseekBubbleGlassTint,
            globalStyle: resolvedGlassStyle,
            globalTint: resolvedGlassTint
        )
        deepseekBubbleGlassStyle = deepseekGlass.style
        deepseekBubbleGlassTint = deepseekGlass.tint
        cursorCapsuleColor = Self.loadColor(key: Keys.cursorCapsuleColor)
        codexCapsuleColor = Self.loadColor(key: Keys.codexCapsuleColor)
        deepseekCapsuleColor = Self.loadColor(key: Keys.deepseekCapsuleColor)

        if UserDefaults.standard.object(forKey: Keys.aiboScalePercent) != nil {
            aiboScalePercent = Self.clampAiboScalePercent(
                UserDefaults.standard.double(forKey: Keys.aiboScalePercent)
            )
        } else {
            aiboScalePercent = Self.defaultAiboScalePercent
        }

        pixelOptimizationEnabled = UserDefaults.standard.bool(forKey: Keys.pixelOptimizationEnabled)

        if UserDefaults.standard.object(forKey: Keys.restoreLastAiboPosition) != nil {
            restoreLastAiboPosition = UserDefaults.standard.bool(forKey: Keys.restoreLastAiboPosition)
        } else {
            restoreLastAiboPosition = true
        }

        if UserDefaults.standard.object(forKey: Keys.hideWhenFullscreen) != nil {
            hideWhenFullscreen = UserDefaults.standard.bool(forKey: Keys.hideWhenFullscreen)
        } else {
            hideWhenFullscreen = true
        }

        disableMouseTracking = UserDefaults.standard.bool(forKey: Keys.disableMouseTracking)

        if UserDefaults.standard.object(forKey: Keys.aiboPositionXPercent) != nil,
           UserDefaults.standard.object(forKey: Keys.aiboPositionYPercent) != nil
        {
            savedAiboCenterXPercent = UserDefaults.standard.double(forKey: Keys.aiboPositionXPercent)
            savedAiboCenterYPercent = UserDefaults.standard.double(forKey: Keys.aiboPositionYPercent)
        } else {
            savedAiboCenterXPercent = nil
            savedAiboCenterYPercent = nil
        }

        if UserDefaults.standard.object(forKey: Keys.musicNotesEnabled) != nil {
            musicNotesEnabled = UserDefaults.standard.bool(forKey: Keys.musicNotesEnabled)
        } else {
            musicNotesEnabled = true
        }
        let notesColorRaw = UserDefaults.standard.string(forKey: Keys.musicNotesColorMode)
            ?? MusicNotesColorMode.aiboAccent.rawValue
        musicNotesColorMode = MusicNotesColorMode(rawValue: notesColorRaw) ?? .aiboAccent
        musicNotesCustomColor = Self.loadColor(key: Keys.musicNotesCustomColor)
            ?? Color(nsColor: .systemPink)
        customMusicNotificationNames =
            UserDefaults.standard.string(forKey: Keys.customMusicNotificationNames) ?? ""

        webhookEnabled = UserDefaults.standard.bool(forKey: Keys.webhookEnabled)
        let storedPort = UserDefaults.standard.integer(forKey: Keys.webhookPort)
        if storedPort > 0, storedPort <= Int(UInt16.max) {
            webhookPort = UInt16(storedPort)
        } else {
            webhookPort = Self.defaultWebhookPort
        }

        publicWebhookURLString = Self.normalizedPublicWebhookURL(
            UserDefaults.standard.string(forKey: Keys.publicWebhookURL) ?? ""
        )

        let dismissRaw = UserDefaults.standard.string(forKey: Keys.webhookDismissMode)
            ?? WebhookDismissMode.onClick.rawValue
        webhookDismissMode = WebhookDismissMode(rawValue: dismissRaw) ?? .onClick

        if UserDefaults.standard.object(forKey: Keys.webhookAutoDismissSeconds) != nil {
            webhookAutoDismissSeconds = Self.clampWebhookAutoDismissSeconds(
                UserDefaults.standard.integer(forKey: Keys.webhookAutoDismissSeconds)
            )
        } else {
            webhookAutoDismissSeconds = Self.defaultWebhookAutoDismissSeconds
        }

        if UserDefaults.standard.object(forKey: Keys.settingsWindowHeight) != nil {
            settingsWindowHeight = Self.clampSettingsWindowHeight(
                CGFloat(UserDefaults.standard.double(forKey: Keys.settingsWindowHeight))
            )
        } else {
            settingsWindowHeight = Self.defaultSettingsWindowHeight
        }

        if let existing = KeychainStore.string(forAccount: Keys.webhookSecretAccount), !existing.isEmpty {
            webhookSecret = existing
        } else {
            webhookSecret = Self.makeSecret()
            try? KeychainStore.setString(webhookSecret, forAccount: Keys.webhookSecretAccount)
        }
    }

    func resolvedMusicNotesColor(for record: AiboLibraryRecord) -> Color {
        switch musicNotesColorMode {
        case .aiboAccent:
            AiboAppearance.dominantColor(for: record)
        case .custom:
            musicNotesCustomColor
        }
    }

    func regenerateWebhookSecret() {
        webhookSecret = Self.makeSecret()
        try? KeychainStore.setString(webhookSecret, forAccount: Keys.webhookSecretAccount)
        AiboRuntime.shared.syncWebhookServer()
    }

    func resetAiboScalePercent() {
        aiboScalePercent = Self.defaultAiboScalePercent
    }

    /// Custom agent-capsule fill, or `nil` for the default black/white look.
    func agentCapsuleColor(for agent: AgentKind) -> Color? {
        switch agent {
        case .cursor: cursorCapsuleColor
        case .codex: codexCapsuleColor
        case .deepseek: deepseekCapsuleColor
        }
    }

    func setAgentCapsuleColor(_ color: Color?, for agent: AgentKind) {
        switch agent {
        case .cursor: cursorCapsuleColor = color
        case .codex: codexCapsuleColor = color
        case .deepseek: deepseekCapsuleColor = color
        }
    }

    /// Per-agent bubble glass. Webhook / warning bubbles keep `bubbleGlassStyle`.
    func agentBubbleGlassStyle(for agent: AgentKind) -> BubbleGlassStyle {
        switch agent {
        case .cursor: cursorBubbleGlassStyle
        case .codex: codexBubbleGlassStyle
        case .deepseek: deepseekBubbleGlassStyle
        }
    }

    func setAgentBubbleGlassStyle(_ style: BubbleGlassStyle, for agent: AgentKind) {
        switch agent {
        case .cursor: cursorBubbleGlassStyle = style
        case .codex: codexBubbleGlassStyle = style
        case .deepseek: deepseekBubbleGlassStyle = style
        }
    }

    func agentBubbleGlassTint(for agent: AgentKind) -> Color? {
        switch agent {
        case .cursor: cursorBubbleGlassTint
        case .codex: codexBubbleGlassTint
        case .deepseek: deepseekBubbleGlassTint
        }
    }

    func setAgentBubbleGlassTint(_ color: Color?, for agent: AgentKind) {
        switch agent {
        case .cursor: cursorBubbleGlassTint = color
        case .codex: codexBubbleGlassTint = color
        case .deepseek: deepseekBubbleGlassTint = color
        }
    }

    /// Agent bubbles use that agent’s glass; webhook / warning use the global style.
    func bubbleGlassStyle(for agent: AgentKind?) -> BubbleGlassStyle {
        guard let agent else { return bubbleGlassStyle }
        return agentBubbleGlassStyle(for: agent)
    }

    func bubbleGlassTint(for agent: AgentKind?) -> Color? {
        guard let agent else { return bubbleGlassTint }
        return agentBubbleGlassTint(for: agent)
    }

    /// Persist aibo center as fractions of the screen visible frame (resolution-independent).
    func saveAiboCenterRelativePosition(xPercent: Double, yPercent: Double) {
        let x = min(max(xPercent, 0), 1)
        let y = min(max(yPercent, 0), 1)
        guard savedAiboCenterXPercent != x || savedAiboCenterYPercent != y else { return }
        savedAiboCenterXPercent = x
        savedAiboCenterYPercent = y
        UserDefaults.standard.set(x, forKey: Keys.aiboPositionXPercent)
        UserDefaults.standard.set(y, forKey: Keys.aiboPositionYPercent)
    }

    func saveSettingsWindowHeight(_ height: CGFloat) {
        let clamped = Self.clampSettingsWindowHeight(height)
        guard abs(settingsWindowHeight - clamped) >= 0.5 else { return }
        settingsWindowHeight = clamped
        UserDefaults.standard.set(Double(clamped), forKey: Keys.settingsWindowHeight)
    }

    /// Copies pre-rename `settings.pet*` keys (and `petAccent`) into the aibo names once.
    private static func migrateLegacyPetKeys() {
        let defaults = UserDefaults.standard
        let pairs = [
            ("settings.petScalePercent", Keys.aiboScalePercent),
            ("settings.restoreLastPetPosition", Keys.restoreLastAiboPosition),
            ("settings.petPositionXPercent", Keys.aiboPositionXPercent),
            ("settings.petPositionYPercent", Keys.aiboPositionYPercent),
        ]
        for (old, new) in pairs {
            guard defaults.object(forKey: new) == nil,
                  let value = defaults.object(forKey: old)
            else { continue }
            defaults.set(value, forKey: new)
            defaults.removeObject(forKey: old)
        }
        if defaults.string(forKey: Keys.musicNotesColorMode) == "petAccent" {
            defaults.set(MusicNotesColorMode.aiboAccent.rawValue, forKey: Keys.musicNotesColorMode)
        }
    }

    private static func applyAppearance(_ mode: AppThemeMode) {
        NSApp.appearance = mode.nsAppearance
    }

    private static func clampAiboScalePercent(_ value: Double) -> Double {
        min(max(value, aiboScalePercentRange.lowerBound), aiboScalePercentRange.upperBound)
    }

    private static func normalizedAiboScalePercent(
        _ value: Double,
        pixelOptimizationEnabled: Bool
    ) -> Double {
        let clamped = clampAiboScalePercent(value)
        guard pixelOptimizationEnabled else { return clamped }
        return snapAiboScalePercentToPixelSteps(clamped)
    }

    static func snapAiboScalePercentToPixelSteps(
        _ value: Double,
        steps: [Double] = pixelOptimizationScalePercents
    ) -> Double {
        let resolved = steps.isEmpty ? pixelOptimizationScalePercents : steps
        return resolved.min { lhs, rhs in
            let left = abs(lhs - value)
            let right = abs(rhs - value)
            if left != right { return left < right }
            return lhs > rhs
        } ?? defaultAiboScalePercent
    }

    private static func clampSettingsWindowHeight(_ value: CGFloat) -> CGFloat {
        min(max(value, settingsWindowMinHeight), 4000)
    }

    private static func clampWebhookAutoDismissSeconds(_ value: Int) -> Int {
        min(max(value, webhookAutoDismissSecondsRange.lowerBound), webhookAutoDismissSecondsRange.upperBound)
    }

    private static func normalizedPublicWebhookURL(_ value: String) -> String {
        value.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func makeSecret() -> String {
        var bytes = [UInt8](repeating: 0, count: 32)
        _ = SecRandomCopyBytes(kSecRandomDefault, bytes.count, &bytes)
        return bytes.map { String(format: "%02x", $0) }.joined()
    }

    private static func migrateAgentGlass(
        styleKey: String,
        tintKey: String,
        globalStyle: BubbleGlassStyle,
        globalTint: Color?
    ) -> (style: BubbleGlassStyle, tint: Color?) {
        let hasStyle = UserDefaults.standard.object(forKey: styleKey) != nil
        let hasTint = UserDefaults.standard.object(forKey: tintKey) != nil
        if hasStyle || hasTint {
            return (
                loadGlassStyle(key: styleKey, fallback: globalStyle),
                loadColor(key: tintKey)
            )
        }
        UserDefaults.standard.set(globalStyle.rawValue, forKey: styleKey)
        persistColor(globalTint, key: tintKey)
        return (globalStyle, globalTint)
    }

    private static func loadGlassStyle(key: String, fallback: BubbleGlassStyle) -> BubbleGlassStyle {
        guard let raw = UserDefaults.standard.string(forKey: key),
              let style = BubbleGlassStyle(rawValue: raw)
        else { return fallback }
        return style
    }

    private static func persistColor(_ color: Color?, key: String) {
        guard let color else {
            UserDefaults.standard.removeObject(forKey: key)
            return
        }
        guard let rgb = NSColor(color).usingColorSpace(.sRGB) else { return }
        let components: [Double] = [
            rgb.redComponent,
            rgb.greenComponent,
            rgb.blueComponent,
            rgb.alphaComponent,
        ]
        UserDefaults.standard.set(components, forKey: key)
    }

    private static func loadColor(key: String) -> Color? {
        guard let numbers = UserDefaults.standard.array(forKey: key) as? [NSNumber],
              numbers.count == 4
        else { return nil }
        return Color(
            .sRGB,
            red: numbers[0].doubleValue,
            green: numbers[1].doubleValue,
            blue: numbers[2].doubleValue,
            opacity: numbers[3].doubleValue
        )
    }
}
