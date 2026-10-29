import AppKit
import SwiftUI

struct ToolsSettingsPane: View {
    @Bindable private var settings = AppSettings.shared
    private var keystrokes = KeystrokeMonitor.shared

    var body: some View {
        Form {
            Section {
                Toggle(String(localized: "Keystroke"), isOn: $settings.keystrokeOverlayEnabled)
                if settings.keystrokeOverlayEnabled {
                    LabeledContent {
                        stayTimeField
                    } label: {
                        settingLabel(
                            String(localized: "Stay Time"),
                            detail: String(localized: "0 seconds keeps the keys on screen until the next group replaces them.")
                        )
                    }
                    .labeledContentStyle(KeystrokeSettingLabelStyle())
                    LabeledContent {
                        maxKeysField
                    } label: {
                        settingLabel(
                            String(localized: "Max Keys"),
                            detail: String(localized: "0 keeps every key from the same interval in one group, up to 10 rows.")
                        )
                    }
                    .labeledContentStyle(KeystrokeSettingLabelStyle())
                }
            } footer: {
                VStack(alignment: .leading, spacing: 6) {
                    Text(String(localized: "Shows the keys you press beside Aibo. Other bubbles stay hidden while this is on."))
                    if settings.keystrokeOverlayEnabled, keystrokes.accessibilityTrusted == false {
                        Text(String(localized: "Aibo needs Accessibility access to see keys you press in other apps."))
                        Button(String(localized: "Open Accessibility Settings")) {
                            Self.openAccessibilitySettings()
                        }
                        .buttonStyle(.link)
                    }
                }
            }
        }
        .formStyle(.grouped)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .settingsDetailChrome(title: String(localized: "Tools"))
    }

    private var stayTimeField: some View {
        HStack(spacing: 6) {
            TextField(
                String(localized: "Stay Time"),
                value: $settings.keystrokeLingerSeconds,
                format: .number.grouping(.never)
            )
            .labelsHidden()
            .textFieldStyle(.roundedBorder)
            .multilineTextAlignment(.trailing)
            .monospacedDigit()
            .frame(width: 64)
            Text(String(localized: "keystroke.linger.unit", defaultValue: "s"))
                .foregroundStyle(.secondary)
        }
    }

    private var maxKeysField: some View {
        TextField(
            String(localized: "Max Keys"),
            value: $settings.keystrokeMaxCount,
            format: .number.grouping(.never)
        )
        .labelsHidden()
        .textFieldStyle(.roundedBorder)
        .multilineTextAlignment(.trailing)
        .monospacedDigit()
        .frame(width: 64)
    }

    private func settingLabel(_ title: String, detail: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title)
            Text(detail)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private static func openAccessibilitySettings() {
        let url = URL(string: "x-apple.systempreferences:com.apple.settings.PrivacySecurity.extension?Privacy_Accessibility")
        guard let url else { return }
        NSWorkspace.shared.open(url)
    }
}

/// Form labels align to the title baseline, so a subtitle leaves the field high.
private struct KeystrokeSettingLabelStyle: LabeledContentStyle {
    func makeBody(configuration: Configuration) -> some View {
        HStack(alignment: .center, spacing: 12) {
            configuration.label
            Spacer(minLength: 8)
            configuration.content
        }
    }
}
