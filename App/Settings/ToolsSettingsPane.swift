import AppKit
import SwiftUI

struct ToolsSettingsPane: View {
    private enum Page {
        case hookCleanup
    }

    @Bindable private var settings = AppSettings.shared
    private var keystrokes = KeystrokeMonitor.shared
    @State private var page: Page?

    var body: some View {
        if page == .hookCleanup {
            HookCleanupSettingsView { page = nil }
        } else {
            toolsForm
        }
    }

    private var toolsForm: some View {
        Form {
            Section {
                ToolsIntroRow()
            }

            Section {
                HookCleanupEntryRow {
                    page = .hookCleanup
                }
            }

            Section {
                Toggle(isOn: $settings.keystrokeOverlayEnabled) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(String(localized: "Keystroke"))
                        Text(String(localized: "Shows the keys you press beside Aibo."))
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
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
                    Text(String(localized: "Other bubbles stay hidden while this is on."))
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

private struct ToolsIntroRow: View {
    private let side: CGFloat = 28

    var body: some View {
        HStack(spacing: 12) {
            Image("ToolIcon")
                .resizable()
                .interpolation(.high)
                .frame(width: side, height: side)
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 2) {
                Text(String(localized: "Tools"))
                    .font(.body.weight(.semibold))
                Text(String(localized: "More ways to use Aibo as an input"))
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }

            Spacer(minLength: 0)
        }
        .accessibilityElement(children: .combine)
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
