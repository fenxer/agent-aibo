import SwiftUI

struct AboutSettingsPane: View {
    var body: some View {
        VStack(spacing: 0) {
            AboutIdentityHeader()
            Form {
                AboutUpdatesSection()
                AboutLinksSection()
            }
            .formStyle(.grouped)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .settingsDetailChrome(title: String(localized: "About"))
    }
}

private struct AboutIdentityHeader: View {
    var body: some View {
        VStack(spacing: 2) {
            Image("HeartIcon")
                .resizable()
                .scaledToFit()
                .frame(width: 128)
                .accessibilityHidden(true)

            VStack(spacing: 2) {
                Text(verbatim: "Aibo")
                    .font(.system(size: 24, weight: .regular).width(.expanded))

                Text(versionText)
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
            }
            // HeartIcon PNG keeps transparent inset below the gem.
            .padding(.top, -8)
        }
        .frame(maxWidth: .infinity)
        .padding(.top, 8)
        .accessibilityElement(children: .combine)
    }

    private var versionText: String {
        let short = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "—"
        let build = Bundle.main.object(forInfoDictionaryKey: kCFBundleVersionKey as String) as? String ?? "—"
        return "\(short)(\(build))"
    }
}

private struct AboutUpdatesSection: View {
    private var updates = SoftwareUpdateController.shared

    var body: some View {
        Section {
            LabeledContent {
                Button(String(localized: "Check")) {
                    updates.checkForUpdates()
                }
                .disabled(!updates.hasUpdateFeed || !updates.canCheckForUpdates)
            } label: {
                Text(String(localized: "Software Update"))
            }
            .labeledContentStyle(VerticallyCenteredLabeledContentStyle())

            Toggle(isOn: automaticChecksBinding) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(verbatim: "Automatically Check for Updates")
                    Text(verbatim: "Check daily in the background.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
            }
            .disabled(!updates.hasUpdateFeed)
            .toggleStyle(VerticallyCenteredSwitchToggleStyle())
        } header: {
            Text(String(localized: "Updates"))
        }
    }

    private var automaticChecksBinding: Binding<Bool> {
        Binding(
            get: { updates.automaticallyChecksForUpdates },
            set: { updates.setAutomaticallyChecksForUpdates($0) }
        )
    }
}

/// Form `Toggle` aligns the switch to the title baseline, so a subtitle
/// makes the control sit high. Center against the whole label instead.
private struct VerticallyCenteredSwitchToggleStyle: ToggleStyle {
    func makeBody(configuration: Configuration) -> some View {
        HStack(alignment: .center, spacing: 12) {
            configuration.label
            Spacer(minLength: 8)
            Toggle(configuration)
                .labelsHidden()
                .toggleStyle(.switch)
        }
    }
}

/// Form `LabeledContent` aligns to the title baseline, so a taller trailing
/// button sits visually low. Center against the label instead.
private struct VerticallyCenteredLabeledContentStyle: LabeledContentStyle {
    func makeBody(configuration: Configuration) -> some View {
        HStack(alignment: .center, spacing: 12) {
            configuration.label
            Spacer(minLength: 8)
            configuration.content
        }
    }
}

private struct AboutLinksSection: View {
    var body: some View {
        Section {
            AboutLinkRow(title: "Doc")
            AboutLinkRow(title: "GitHub", url: AboutLinks.github)
            AboutLinkRow(title: "X", url: AboutLinks.x)
        } header: {
            Text(String(localized: "Links"))
        }
    }
}

private enum AboutLinks {
    static let github = URL(string: "https://github.com/fenxer/agent-aibo")
    static let x = URL(string: "https://x.com/haxfenx")
}

private struct AboutLinkRow: View {
    var title: String
    var url: URL?

    @Environment(\.openURL) private var openURL

    var body: some View {
        if let url {
            Button {
                openURL(url)
            } label: {
                rowLabel
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
        } else {
            rowLabel
        }
    }

    private var rowLabel: some View {
        HStack {
            Text(title)
                .foregroundStyle(.primary)
            Spacer()
            if url != nil {
                Image(systemName: "arrow.up.right")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .accessibilityHidden(true)
            } else {
                Text(verbatim: "Coming Soon")
                    .foregroundStyle(.secondary)
            }
        }
    }
}
