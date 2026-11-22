import AiboCore
import AppKit
import SwiftUI

extension AppSettings {
    func backupPreferencesAreReadable(_ backup: AiboBackupSettings) -> Bool {
        guard backup.hasCoherentValues(
            autoDismissRange: Self.webhookAutoDismissSecondsRange
        ) else { return false }
        guard AppThemeMode(rawValue: backup.themeMode) != nil else { return false }
        guard AppLanguageMode(rawValue: backup.languageMode) != nil else { return false }
        guard BubbleGlassStyle(rawValue: backup.bubbleGlassStyle) != nil else { return false }
        guard BubbleGlassStyle(rawValue: backup.cursorBubbleGlassStyle) != nil else { return false }
        guard BubbleGlassStyle(rawValue: backup.codexBubbleGlassStyle) != nil else { return false }
        guard BubbleGlassStyle(rawValue: backup.deepseekBubbleGlassStyle) != nil else { return false }
        guard BubbleGlassStyle(rawValue: backup.antigravityBubbleGlassStyle) != nil else { return false }
        guard MusicNotesColorMode(rawValue: backup.musicNotesColorMode) != nil else { return false }
        guard WebhookDismissMode(rawValue: backup.webhookDismissMode) != nil else { return false }
        return true
    }

    func backupSnapshot() -> AiboBackupSettings {
        AiboBackupSettings(
            themeMode: themeMode.rawValue,
            languageMode: languageMode.rawValue,
            bubbleGlassStyle: bubbleGlassStyle.rawValue,
            bubbleGlassTint: Self.backupColor(bubbleGlassTint),
            cursorBubbleGlassStyle: cursorBubbleGlassStyle.rawValue,
            codexBubbleGlassStyle: codexBubbleGlassStyle.rawValue,
            deepseekBubbleGlassStyle: deepseekBubbleGlassStyle.rawValue,
            antigravityBubbleGlassStyle: antigravityBubbleGlassStyle.rawValue,
            cursorBubbleGlassTint: Self.backupColor(cursorBubbleGlassTint),
            codexBubbleGlassTint: Self.backupColor(codexBubbleGlassTint),
            deepseekBubbleGlassTint: Self.backupColor(deepseekBubbleGlassTint),
            antigravityBubbleGlassTint: Self.backupColor(antigravityBubbleGlassTint),
            cursorCapsuleColor: Self.backupColor(cursorCapsuleColor),
            codexCapsuleColor: Self.backupColor(codexCapsuleColor),
            deepseekCapsuleColor: Self.backupColor(deepseekCapsuleColor),
            antigravityCapsuleColor: Self.backupColor(antigravityCapsuleColor),
            codexPlanProgressShaderEnabled: codexPlanProgressShaderEnabled,
            codexPlanProgressShaderPrimary: Self.backupColor(codexPlanProgressShaderPrimary),
            deepseekPlanProgressShaderEnabled: deepseekPlanProgressShaderEnabled,
            deepseekPlanProgressShaderPrimary: Self.backupColor(deepseekPlanProgressShaderPrimary),
            restoreLastAiboPosition: restoreLastAiboPosition,
            hideWhenFullscreen: hideWhenFullscreen,
            disableMouseTracking: disableMouseTracking,
            mouseShakeDodgeEnabled: mouseShakeDodgeEnabled,
            centerXPercent: savedAiboCenterXPercent,
            centerYPercent: savedAiboCenterYPercent,
            musicNotesEnabled: musicNotesEnabled,
            musicNotesColorMode: musicNotesColorMode.rawValue,
            musicNotesCustomColor: Self.backupColor(musicNotesCustomColor)
                ?? AiboBackupColor(red: 1, green: 0.4, blue: 0.7, alpha: 1),
            customMusicNotificationNames: customMusicNotificationNames,
            webhookEnabled: webhookEnabled,
            webhookPort: Int(webhookPort),
            webhookDismissMode: webhookDismissMode.rawValue,
            webhookAutoDismissSeconds: webhookAutoDismissSeconds,
            publicWebhookURL: publicWebhookURLString,
            hookSprites: HookSpriteSettings.shared.file,
            actionSprites: AiboActionSettings.shared.overrides
        )
    }

    /// Applies everything except language. Language restarts the app, so call `applyBackupLanguage` last.
    func applyBackup(_ backup: AiboBackupSettings) {
        let wasApplying = isApplyingRemoteSync
        isApplyingRemoteSync = true
        applyBackupFields(backup, screenUUID: nil, includeLanguage: false)
        isApplyingRemoteSync = wasApplying

        HookSpriteSettings.shared.replace(with: backup.hookSprites)
        AiboActionSettings.shared.replace(with: backup.actionSprites)
        if !wasApplying {
            notifyPeerPreferencesChanged()
        }
    }

    func applyBackupLanguage(_ backup: AiboBackupSettings) {
        guard let mode = AppLanguageMode(rawValue: backup.languageMode) else { return }
        if languageMode != mode {
            languageMode = mode
        }
    }

    func syncPreferencesWire() -> SettingsAppPreferencesWire {
        SettingsAppPreferencesWire(
            backup: backupSnapshot(),
            savedAiboPositionScreenUUID: savedAiboPositionScreenUUID,
            keystrokeOverlayEnabled: keystrokeOverlayEnabled,
            keystrokeLingerSeconds: keystrokeLingerSeconds,
            keystrokeMaxCount: keystrokeMaxCount,
            webhookSecret: webhookSecret
        )
    }

    func applyRemotePreferencesWire(_ wire: SettingsAppPreferencesWire) {
        let wasApplying = isApplyingRemoteSync
        isApplyingRemoteSync = true
        defer { isApplyingRemoteSync = wasApplying }

        applyBackupFields(wire.backup, screenUUID: wire.savedAiboPositionScreenUUID, includeLanguage: true)
        if keystrokeOverlayEnabled != wire.keystrokeOverlayEnabled {
            keystrokeOverlayEnabled = wire.keystrokeOverlayEnabled
        }
        if keystrokeLingerSeconds != wire.keystrokeLingerSeconds {
            keystrokeLingerSeconds = wire.keystrokeLingerSeconds
        }
        if keystrokeMaxCount != wire.keystrokeMaxCount {
            keystrokeMaxCount = wire.keystrokeMaxCount
        }
        if !wire.webhookSecret.isEmpty, webhookSecret != wire.webhookSecret {
            webhookSecret = wire.webhookSecret
        }
    }

    private func applyBackupFields(
        _ backup: AiboBackupSettings,
        screenUUID: String?,
        includeLanguage: Bool
    ) {
        if let mode = AppThemeMode(rawValue: backup.themeMode), themeMode != mode {
            themeMode = mode
        }
        if includeLanguage, let mode = AppLanguageMode(rawValue: backup.languageMode), languageMode != mode {
            languageMode = mode
        }
        if let style = BubbleGlassStyle(rawValue: backup.bubbleGlassStyle), bubbleGlassStyle != style {
            bubbleGlassStyle = style
        }
        let nextGlassTint = backup.bubbleGlassTint.map(Self.color(from:))
        if bubbleGlassTint != nextGlassTint { bubbleGlassTint = nextGlassTint }
        if let style = BubbleGlassStyle(rawValue: backup.cursorBubbleGlassStyle), cursorBubbleGlassStyle != style {
            cursorBubbleGlassStyle = style
        }
        if let style = BubbleGlassStyle(rawValue: backup.codexBubbleGlassStyle), codexBubbleGlassStyle != style {
            codexBubbleGlassStyle = style
        }
        if let style = BubbleGlassStyle(rawValue: backup.deepseekBubbleGlassStyle), deepseekBubbleGlassStyle != style {
            deepseekBubbleGlassStyle = style
        }
        if let style = BubbleGlassStyle(rawValue: backup.antigravityBubbleGlassStyle), antigravityBubbleGlassStyle != style {
            antigravityBubbleGlassStyle = style
        }
        let nextCursorTint = backup.cursorBubbleGlassTint.map(Self.color(from:))
        if cursorBubbleGlassTint != nextCursorTint { cursorBubbleGlassTint = nextCursorTint }
        let nextCodexTint = backup.codexBubbleGlassTint.map(Self.color(from:))
        if codexBubbleGlassTint != nextCodexTint { codexBubbleGlassTint = nextCodexTint }
        let nextDeepseekTint = backup.deepseekBubbleGlassTint.map(Self.color(from:))
        if deepseekBubbleGlassTint != nextDeepseekTint { deepseekBubbleGlassTint = nextDeepseekTint }
        let nextAntigravityTint = backup.antigravityBubbleGlassTint.map(Self.color(from:))
        if antigravityBubbleGlassTint != nextAntigravityTint { antigravityBubbleGlassTint = nextAntigravityTint }
        let nextCursorCapsule = backup.cursorCapsuleColor.map(Self.color(from:))
        if cursorCapsuleColor != nextCursorCapsule { cursorCapsuleColor = nextCursorCapsule }
        let nextCodexCapsule = backup.codexCapsuleColor.map(Self.color(from:))
        if codexCapsuleColor != nextCodexCapsule { codexCapsuleColor = nextCodexCapsule }
        let nextDeepseekCapsule = backup.deepseekCapsuleColor.map(Self.color(from:))
        if deepseekCapsuleColor != nextDeepseekCapsule { deepseekCapsuleColor = nextDeepseekCapsule }
        let nextAntigravityCapsule = backup.antigravityCapsuleColor.map(Self.color(from:))
        if antigravityCapsuleColor != nextAntigravityCapsule { antigravityCapsuleColor = nextAntigravityCapsule }
        if codexPlanProgressShaderEnabled != backup.codexPlanProgressShaderEnabled {
            codexPlanProgressShaderEnabled = backup.codexPlanProgressShaderEnabled
        }
        let nextCodexShader = backup.codexPlanProgressShaderPrimary.map(Self.color(from:))
        if codexPlanProgressShaderPrimary != nextCodexShader { codexPlanProgressShaderPrimary = nextCodexShader }
        if deepseekPlanProgressShaderEnabled != backup.deepseekPlanProgressShaderEnabled {
            deepseekPlanProgressShaderEnabled = backup.deepseekPlanProgressShaderEnabled
        }
        let nextDeepseekShader = backup.deepseekPlanProgressShaderPrimary.map(Self.color(from:))
        if deepseekPlanProgressShaderPrimary != nextDeepseekShader { deepseekPlanProgressShaderPrimary = nextDeepseekShader }
        if restoreLastAiboPosition != backup.restoreLastAiboPosition {
            restoreLastAiboPosition = backup.restoreLastAiboPosition
        }
        if hideWhenFullscreen != backup.hideWhenFullscreen {
            hideWhenFullscreen = backup.hideWhenFullscreen
        }
        if disableMouseTracking != backup.disableMouseTracking {
            disableMouseTracking = backup.disableMouseTracking
        }
        if mouseShakeDodgeEnabled != backup.mouseShakeDodgeEnabled {
            mouseShakeDodgeEnabled = backup.mouseShakeDodgeEnabled
        }
        if let x = backup.centerXPercent, let y = backup.centerYPercent {
            if savedAiboCenterXPercent != x || savedAiboCenterYPercent != y || savedAiboPositionScreenUUID != screenUUID {
                saveAiboCenterRelativePosition(
                    xPercent: x,
                    yPercent: y,
                    screenUUID: screenUUID
                )
            }
        } else if savedAiboCenterXPercent != nil || savedAiboCenterYPercent != nil || savedAiboPositionScreenUUID != nil {
            clearSavedAiboPosition()
        }
        if musicNotesEnabled != backup.musicNotesEnabled {
            musicNotesEnabled = backup.musicNotesEnabled
        }
        if let mode = MusicNotesColorMode(rawValue: backup.musicNotesColorMode), musicNotesColorMode != mode {
            musicNotesColorMode = mode
        }
        let nextNotesColor = Self.color(from: backup.musicNotesCustomColor)
        if musicNotesCustomColor != nextNotesColor {
            musicNotesCustomColor = nextNotesColor
        }
        if customMusicNotificationNames != backup.customMusicNotificationNames {
            customMusicNotificationNames = backup.customMusicNotificationNames
        }
        if webhookEnabled != backup.webhookEnabled {
            webhookEnabled = backup.webhookEnabled
        }
        if backup.webhookPort > 0, backup.webhookPort <= Int(UInt16.max) {
            let nextPort = UInt16(backup.webhookPort)
            if webhookPort != nextPort { webhookPort = nextPort }
        }
        if let mode = WebhookDismissMode(rawValue: backup.webhookDismissMode), webhookDismissMode != mode {
            webhookDismissMode = mode
        }
        if webhookAutoDismissSeconds != backup.webhookAutoDismissSeconds {
            webhookAutoDismissSeconds = backup.webhookAutoDismissSeconds
        }
        if publicWebhookURLString != backup.publicWebhookURL {
            publicWebhookURLString = backup.publicWebhookURL
        }
    }

    static func normalizedSRGBColor(_ color: Color) -> Color {
        guard let backup = backupColor(color) else { return color }
        return Self.color(from: backup)
    }

    private static func backupColor(_ color: Color?) -> AiboBackupColor? {
        guard let color, let rgb = NSColor(color).usingColorSpace(.sRGB) else { return nil }
        return AiboBackupColor(
            red: rgb.redComponent,
            green: rgb.greenComponent,
            blue: rgb.blueComponent,
            alpha: rgb.alphaComponent
        )
    }

    private static func color(from backup: AiboBackupColor) -> Color {
        Color(.sRGB, red: backup.red, green: backup.green, blue: backup.blue, opacity: backup.alpha)
    }
}
