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
    var body: some View {
        Section {
            LabeledContent {
                // Unpublished local builds have no update feed yet.
                Button(String(localized: "Check")) {}
            } label: {
                Text(String(localized: "Aibo Update"))
            }
        } header: {
            Text(String(localized: "Updates"))
        }
    }
}

private struct AboutLinksSection: View {
    var body: some View {
        Section {
            AboutLinkRow(title: String(localized: "Doc"), url: nil)
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
            Image(systemName: "arrow.up.right")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
                .accessibilityHidden(true)
        }
        .contentShape(Rectangle())
    }
}
