import SwiftUI

/// System Settings–style detail toolbar: nav capsule + leading title.
///
/// Relies on `SettingsWindowConfigurator` forcing `NSWindow.toolbarStyle`
/// off `.preference` (which centers items). With `.unified`, navigation
/// placement stays at the leading edge of the detail column.
///
/// Keep the nav `ControlGroup` and the title in **separate** `ToolbarItem`s.
/// Putting them in one item wraps both in the same glass capsule. Hide the
/// title item’s shared glass so only the nav pill keeps a background.
///
/// Trailing actions must live in this same toolbar, **after**
/// `ToolbarSpacer(.flexible)`. A second `.toolbar` with automatic items
/// joins the leading cluster (next to the title). macOS has no
/// `topBarTrailing`.
struct SettingsDetailChromeModifier<Trailing: ToolbarContent>: ViewModifier {
    var title: String
    var canGoBack: Bool
    var onBack: () -> Void
    var trailing: Trailing

    func body(content: Content) -> some View {
        content
            .navigationTitle(title)
            .toolbar(removing: .title)
            .toolbar {
                ToolbarItem(placement: .navigation) {
                    ControlGroup {
                        Button(action: onBack) {
                            Image(systemName: "chevron.backward")
                        }
                        .disabled(!canGoBack)
                        .help(String(localized: "Back"))
                        .accessibilityLabel(String(localized: "Back"))

                        Button {} label: {
                            Image(systemName: "chevron.forward")
                        }
                        .disabled(true)
                        .accessibilityLabel(String(localized: "Forward"))
                    }
                    .controlGroupStyle(.navigation)
                }

                ToolbarItem(placement: .navigation) {
                    Text(title)
                        .font(.title3)
                        .lineLimit(1)
                        .fixedSize(horizontal: true, vertical: false)
                        .accessibilityAddTraits(.isHeader)
                }
                .sharedBackgroundVisibility(.hidden)

                ToolbarSpacer(.flexible)

                trailing
            }
    }
}

extension View {
    func settingsDetailChrome(
        title: String,
        canGoBack: Bool = false,
        onBack: @escaping () -> Void = {}
    ) -> some View {
        settingsDetailChrome(title: title, canGoBack: canGoBack, onBack: onBack) {
            ToolbarItemGroup {}
        }
    }

    func settingsDetailChrome(
        title: String,
        canGoBack: Bool = false,
        onBack: @escaping () -> Void = {},
        @ToolbarContentBuilder trailing: () -> some ToolbarContent
    ) -> some View {
        modifier(
            SettingsDetailChromeModifier(
                title: title,
                canGoBack: canGoBack,
                onBack: onBack,
                trailing: trailing()
            )
        )
    }
}
