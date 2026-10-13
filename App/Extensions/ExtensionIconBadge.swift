import AiboCore
import AppKit
import SwiftUI

/// Square plugin tile. An image file fills the square. Otherwise the tile is a
/// background plus an SF Symbol. Declared symbol color wins; otherwise the
/// glyph is black or white from the background contrast.
struct ExtensionIconBadge: View {
    var icon: ExtensionIcon
    var directory: URL?
    var side: CGFloat
    var cornerRadius: CGFloat
    var symbolPointSize: CGFloat

    @Environment(\.colorScheme) private var colorScheme
    @State private var image: NSImage?

    var body: some View {
        Group {
            if let image {
                Image(nsImage: image)
                    .resizable()
                    .interpolation(.high)
                    .scaledToFill()
            } else {
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .fill(tileColor)
                    .overlay {
                        Image(nsImage: centeredSymbol)
                            .renderingMode(.template)
                            .foregroundStyle(inkColor)
                    }
            }
        }
        .frame(width: side, height: side)
        .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
        .accessibilityHidden(true)
        .onAppear(perform: loadImage)
        .onChange(of: directory) { _, _ in loadImage() }
        .onChange(of: icon) { _, _ in loadImage() }
    }

    private var tileColor: Color {
        let dark = colorScheme == .dark
        if let hex = icon.backgroundHex(dark: dark), let parsed = ExtensionIconColor.parse(hex) {
            return parsed
        }
        return dark ? .white : .black
    }

    private var inkColor: Color {
        let dark = colorScheme == .dark
        if let hex = icon.symbolHex(dark: dark), let parsed = ExtensionIconColor.parse(hex) {
            return parsed
        }
        return ExtensionIconColor.ink(on: tileColor)
    }

    /// SF Symbols keep a text-baseline alignment rect, so `Image(systemName:)`
    /// sits low in a square. Bake the ink centered in the tile.
    private var centeredSymbol: NSImage {
        let name = icon.symbol.isEmpty ? ExtensionIcon.defaultSymbol : icon.symbol
        let config = NSImage.SymbolConfiguration(pointSize: symbolPointSize, weight: .medium)
        guard let symbol = NSImage(systemSymbolName: name, accessibilityDescription: nil)?
            .withSymbolConfiguration(config)
        else {
            return NSImage(size: NSSize(width: side, height: side))
        }
        let canvas = NSImage(size: NSSize(width: side, height: side))
        canvas.isTemplate = true
        canvas.lockFocus()
        let ink = symbol.alignmentRect
        symbol.draw(
            in: NSRect(
                x: (side - ink.width) / 2 - ink.origin.x,
                y: (side - ink.height) / 2 - ink.origin.y,
                width: symbol.size.width,
                height: symbol.size.height
            ),
            from: NSRect(origin: .zero, size: symbol.size),
            operation: .sourceOver,
            fraction: 1
        )
        canvas.unlockFocus()
        return canvas
    }

    private func loadImage() {
        guard let directory, let name = icon.image, !name.isEmpty else {
            image = nil
            return
        }
        let file = directory.appendingPathComponent(name)
        image = NSImage(contentsOf: file)
    }
}

enum ExtensionIconColor {
    static func parse(_ hex: String) -> Color? {
        var text = hex.trimmingCharacters(in: .whitespacesAndNewlines)
        if text.hasPrefix("#") { text.removeFirst() }
        guard text.count == 3 || text.count == 6, let value = UInt32(text, radix: 16) else { return nil }
        let red: Double
        let green: Double
        let blue: Double
        if text.count == 3 {
            red = Double((value >> 8) & 0xF) / 15
            green = Double((value >> 4) & 0xF) / 15
            blue = Double(value & 0xF) / 15
        } else {
            red = Double((value >> 16) & 0xFF) / 255
            green = Double((value >> 8) & 0xFF) / 255
            blue = Double(value & 0xFF) / 255
        }
        return Color(red: red, green: green, blue: blue)
    }

    /// Black or white, whichever contrasts with the tile.
    static func ink(on color: Color) -> Color {
        let resolved = NSColor(color).usingColorSpace(.sRGB) ?? NSColor(color)
        let luminance = relativeLuminance(
            red: resolved.redComponent,
            green: resolved.greenComponent,
            blue: resolved.blueComponent
        )
        return luminance > 0.179 ? .black : .white
    }

    private static func relativeLuminance(red: CGFloat, green: CGFloat, blue: CGFloat) -> CGFloat {
        func channel(_ value: CGFloat) -> CGFloat {
            if value <= 0.04045 { return value / 12.92 }
            return pow((value + 0.055) / 1.055, 2.4)
        }
        return 0.2126 * channel(red) + 0.7152 * channel(green) + 0.0722 * channel(blue)
    }
}
