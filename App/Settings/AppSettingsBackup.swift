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
            cursorBubbleGlassTint: Self.backupColor(cursorBubbleGlassTint),
            codexBubbleGlassTint: Self.backupColor(codexBubbleGlassTint),
            deepseekBubbleGlassTint: Self.backupColor(deepseekBubbleGlassTint),
            cursorCapsuleColor: Self.backupColor(cursorCapsuleColor),
            codexCapsuleColor: Self.backupColor(codexCapsuleColor),
            deepseekCapsuleColor: Self.backupColor(deepseekCapsuleColor),
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
        if let mode = AppThemeMode(rawValue: backup.themeMode) {
            themeMode = mode
        }
        if let style = BubbleGlassStyle(rawValue: backup.bubbleGlassStyle) {
            bubbleGlassStyle = style
        }
        bubbleGlassTint = backup.bubbleGlassTint.map(Self.color(from:))
        if let style = BubbleGlassStyle(rawValue: backup.cursorBubbleGlassStyle) {
            cursorBubbleGlassStyle = style
        }
        if let style = BubbleGlassStyle(rawValue: backup.codexBubbleGlassStyle) {
            codexBubbleGlassStyle = style
        }
        if let style = BubbleGlassStyle(rawValue: backup.deepseekBubbleGlassStyle) {
            deepseekBubbleGlassStyle = style
        }
        cursorBubbleGlassTint = backup.cursorBubbleGlassTint.map(Self.color(from:))
        codexBubbleGlassTint = backup.codexBubbleGlassTint.map(Self.color(from:))
        deepseekBubbleGlassTint = backup.deepseekBubbleGlassTint.map(Self.color(from:))
        cursorCapsuleColor = backup.cursorCapsuleColor.map(Self.color(from:))
        codexCapsuleColor = backup.codexCapsuleColor.map(Self.color(from:))
        deepseekCapsuleColor = backup.deepseekCapsuleColor.map(Self.color(from:))
        codexPlanProgressShaderEnabled = backup.codexPlanProgressShaderEnabled
        codexPlanProgressShaderPrimary = backup.codexPlanProgressShaderPrimary.map(Self.color(from:))
        deepseekPlanProgressShaderEnabled = backup.deepseekPlanProgressShaderEnabled
        deepseekPlanProgressShaderPrimary = backup.deepseekPlanProgressShaderPrimary.map(Self.color(from:))
        restoreLastAiboPosition = backup.restoreLastAiboPosition
        hideWhenFullscreen = backup.hideWhenFullscreen
        disableMouseTracking = backup.disableMouseTracking
        mouseShakeDodgeEnabled = backup.mouseShakeDodgeEnabled
        if let x = backup.centerXPercent, let y = backup.centerYPercent {
            saveAiboCenterRelativePosition(xPercent: x, yPercent: y, screenUUID: nil)
        } else {
            clearSavedAiboPosition()
        }
        musicNotesEnabled = backup.musicNotesEnabled
        if let mode = MusicNotesColorMode(rawValue: backup.musicNotesColorMode) {
            musicNotesColorMode = mode
        }
        musicNotesCustomColor = Self.color(from: backup.musicNotesCustomColor)
        customMusicNotificationNames = backup.customMusicNotificationNames
        webhookEnabled = backup.webhookEnabled
        if backup.webhookPort > 0, backup.webhookPort <= Int(UInt16.max) {
            webhookPort = UInt16(backup.webhookPort)
        }
        if let mode = WebhookDismissMode(rawValue: backup.webhookDismissMode) {
            webhookDismissMode = mode
        }
        webhookAutoDismissSeconds = backup.webhookAutoDismissSeconds
        publicWebhookURLString = backup.publicWebhookURL
        HookSpriteSettings.shared.replace(with: backup.hookSprites)
        AiboActionSettings.shared.replace(with: backup.actionSprites)
    }

    func applyBackupLanguage(_ backup: AiboBackupSettings) {
        guard let mode = AppLanguageMode(rawValue: backup.languageMode) else { return }
        languageMode = mode
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
