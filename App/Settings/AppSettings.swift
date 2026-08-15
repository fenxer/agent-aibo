import AiboCore
import AiboIngest
import AppKit
import Foundation
import Security
import SwiftUI

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
        static let petScalePercent = "settings.petScalePercent"
        static let restoreLastPetPosition = "settings.restoreLastPetPosition"
        static let hideWhenFullscreen = "settings.hideWhenFullscreen"
        static let petPositionXPercent = "settings.petPositionXPercent"
        static let petPositionYPercent = "settings.petPositionYPercent"
        static let musicNotesEnabled = "settings.musicNotesEnabled"
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
    /// Pet image size as a percentage of the base 96pt sprite. Range 0…200; default 100.
    static let defaultPetScalePercent: Double = 100
    static let petScalePercentRange: ClosedRange<Double> = 0...200
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
            PetPanelController.shared.refreshContent()
        }
    }

    var bubblePlacement: BubblePlacement {
        didSet {
            guard oldValue != bubblePlacement else { return }
            UserDefaults.standard.set(bubblePlacement.rawValue, forKey: Keys.bubblePlacement)
            PetPanelController.shared.refreshContent()
        }
    }

    /// Pet sprite scale relative to the default size (`100` = 96×96 pt).
    var petScalePercent: Double {
        didSet {
            let clamped = Self.clampPetScalePercent(petScalePercent)
            if clamped != petScalePercent {
                petScalePercent = clamped
                return
            }
            guard oldValue != petScalePercent else { return }
            UserDefaults.standard.set(petScalePercent, forKey: Keys.petScalePercent)
            PetPanelController.shared.refreshContent()
        }
    }

    /// When true, the pet opens at its last screen-relative position. Default on.
    var restoreLastPetPosition: Bool {
        didSet {
            guard oldValue != restoreLastPetPosition else { return }
            UserDefaults.standard.set(restoreLastPetPosition, forKey: Keys.restoreLastPetPosition)
        }
    }

    /// When true, hide the pet for native fullscreen (Spaces type 4) or
    /// `currentSystemPresentationOptions` containing `.fullScreen`. Default on.
    var hideWhenFullscreen: Bool {
        didSet {
            guard oldValue != hideWhenFullscreen else { return }
            UserDefaults.standard.set(hideWhenFullscreen, forKey: Keys.hideWhenFullscreen)
            PetPanelController.shared.syncFullscreenPolicy()
        }
    }

    /// Pet center X within the screen `visibleFrame`, 0…1. `nil` until the user has moved the pet.
    private(set) var savedPetCenterXPercent: Double?
    /// Pet center Y within the screen `visibleFrame`, 0…1. `nil` until the user has moved the pet.
    private(set) var savedPetCenterYPercent: Double?

    /// Overlay music-note rise effect while a known player is playing. Default on.
    var musicNotesEnabled: Bool {
        didSet {
            guard oldValue != musicNotesEnabled else { return }
            UserDefaults.standard.set(musicNotesEnabled, forKey: Keys.musicNotesEnabled)
            PetRuntime.shared.syncMusicPlaybackMonitor()
            PetPanelController.shared.refreshContent()
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
            PetPanelController.shared.refreshContent()
        }
    }

    /// Optional glass tint. `nil` means no tint (system default).
    var bubbleGlassTint: Color? {
        didSet {
            guard oldValue != bubbleGlassTint else { return }
            Self.persistColor(bubbleGlassTint, key: Keys.bubbleGlassTint)
            PetPanelController.shared.refreshContent()
        }
    }

    /// Optional Cursor agent-capsule fill. `nil` keeps the default black/white capsule.
    var cursorCapsuleColor: Color? {
        didSet {
            guard oldValue != cursorCapsuleColor else { return }
            Self.persistColor(cursorCapsuleColor, key: Keys.cursorCapsuleColor)
            PetPanelController.shared.refreshContent()
        }
    }

    /// Optional Codex agent-capsule fill. `nil` keeps the default black/white capsule.
    var codexCapsuleColor: Color? {
        didSet {
            guard oldValue != codexCapsuleColor else { return }
            Self.persistColor(codexCapsuleColor, key: Keys.codexCapsuleColor)
            PetPanelController.shared.refreshContent()
        }
    }

    /// Optional DeepSeek agent-capsule fill. `nil` keeps the default black/white capsule.
    var deepseekCapsuleColor: Color? {
        didSet {
            guard oldValue != deepseekCapsuleColor else { return }
            Self.persistColor(deepseekCapsuleColor, key: Keys.deepseekCapsuleColor)
            PetPanelController.shared.refreshContent()
        }
    }

    /// Cursor bubble glass. Seeded from the former global style when unset.
    var cursorBubbleGlassStyle: BubbleGlassStyle {
        didSet {
            guard oldValue != cursorBubbleGlassStyle else { return }
            UserDefaults.standard.set(cursorBubbleGlassStyle.rawValue, forKey: Keys.cursorBubbleGlassStyle)
            PetPanelController.shared.refreshContent()
        }
    }

    var codexBubbleGlassStyle: BubbleGlassStyle {
        didSet {
            guard oldValue != codexBubbleGlassStyle else { return }
            UserDefaults.standard.set(codexBubbleGlassStyle.rawValue, forKey: Keys.codexBubbleGlassStyle)
            PetPanelController.shared.refreshContent()
        }
    }

    var deepseekBubbleGlassStyle: BubbleGlassStyle {
        didSet {
            guard oldValue != deepseekBubbleGlassStyle else { return }
            UserDefaults.standard.set(deepseekBubbleGlassStyle.rawValue, forKey: Keys.deepseekBubbleGlassStyle)
            PetPanelController.shared.refreshContent()
        }
    }

    /// Optional Cursor glass tint. `nil` means no tint.
    var cursorBubbleGlassTint: Color? {
        didSet {
            guard oldValue != cursorBubbleGlassTint else { return }
            Self.persistColor(cursorBubbleGlassTint, key: Keys.cursorBubbleGlassTint)
            PetPanelController.shared.refreshContent()
        }
    }

    var codexBubbleGlassTint: Color? {
        didSet {
            guard oldValue != codexBubbleGlassTint else { return }
            Self.persistColor(codexBubbleGlassTint, key: Keys.codexBubbleGlassTint)
            PetPanelController.shared.refreshContent()
        }
    }

    var deepseekBubbleGlassTint: Color? {
        didSet {
            guard oldValue != deepseekBubbleGlassTint else { return }
            Self.persistColor(deepseekBubbleGlassTint, key: Keys.deepseekBubbleGlassTint)
            PetPanelController.shared.refreshContent()
        }
    }

    var webhookEnabled: Bool {
        didSet {
            guard oldValue != webhookEnabled else { return }
            UserDefaults.standard.set(webhookEnabled, forKey: Keys.webhookEnabled)
            PetRuntime.shared.syncWebhookServer()
            TunnelHealthMonitor.shared.scheduleCheck(reason: .settingsChanged)
        }
    }

    var webhookPort: UInt16 {
        didSet {
            guard oldValue != webhookPort else { return }
            UserDefaults.standard.set(Int(webhookPort), forKey: Keys.webhookPort)
            PetRuntime.shared.syncWebhookServer()
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

        if UserDefaults.standard.object(forKey: Keys.petScalePercent) != nil {
            petScalePercent = Self.clampPetScalePercent(
                UserDefaults.standard.double(forKey: Keys.petScalePercent)
            )
        } else {
            petScalePercent = Self.defaultPetScalePercent
        }

        if UserDefaults.standard.object(forKey: Keys.restoreLastPetPosition) != nil {
            restoreLastPetPosition = UserDefaults.standard.bool(forKey: Keys.restoreLastPetPosition)
        } else {
            restoreLastPetPosition = true
        }

        if UserDefaults.standard.object(forKey: Keys.hideWhenFullscreen) != nil {
            hideWhenFullscreen = UserDefaults.standard.bool(forKey: Keys.hideWhenFullscreen)
        } else {
            hideWhenFullscreen = true
        }

        if UserDefaults.standard.object(forKey: Keys.petPositionXPercent) != nil,
           UserDefaults.standard.object(forKey: Keys.petPositionYPercent) != nil
        {
            savedPetCenterXPercent = UserDefaults.standard.double(forKey: Keys.petPositionXPercent)
            savedPetCenterYPercent = UserDefaults.standard.double(forKey: Keys.petPositionYPercent)
        } else {
            savedPetCenterXPercent = nil
            savedPetCenterYPercent = nil
        }

        if UserDefaults.standard.object(forKey: Keys.musicNotesEnabled) != nil {
            musicNotesEnabled = UserDefaults.standard.bool(forKey: Keys.musicNotesEnabled)
        } else {
            musicNotesEnabled = true
        }
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

    func regenerateWebhookSecret() {
        webhookSecret = Self.makeSecret()
        try? KeychainStore.setString(webhookSecret, forAccount: Keys.webhookSecretAccount)
        PetRuntime.shared.syncWebhookServer()
    }

    func resetPetScalePercent() {
        petScalePercent = Self.defaultPetScalePercent
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

    /// Persist pet center as fractions of the screen visible frame (resolution-independent).
    func savePetCenterRelativePosition(xPercent: Double, yPercent: Double) {
        let x = min(max(xPercent, 0), 1)
        let y = min(max(yPercent, 0), 1)
        guard savedPetCenterXPercent != x || savedPetCenterYPercent != y else { return }
        savedPetCenterXPercent = x
        savedPetCenterYPercent = y
        UserDefaults.standard.set(x, forKey: Keys.petPositionXPercent)
        UserDefaults.standard.set(y, forKey: Keys.petPositionYPercent)
    }

    func saveSettingsWindowHeight(_ height: CGFloat) {
        let clamped = Self.clampSettingsWindowHeight(height)
        guard abs(settingsWindowHeight - clamped) >= 0.5 else { return }
        settingsWindowHeight = clamped
        UserDefaults.standard.set(Double(clamped), forKey: Keys.settingsWindowHeight)
    }

    private static func applyAppearance(_ mode: AppThemeMode) {
        NSApp.appearance = mode.nsAppearance
    }

    private static func clampPetScalePercent(_ value: Double) -> Double {
        min(max(value, petScalePercentRange.lowerBound), petScalePercentRange.upperBound)
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
