import AiboCore
import CoreGraphics

enum KeystrokeMetrics {
    static let keySide = CGFloat(KeystrokeStripLayout.regularSide)
    static let spacing = CGFloat(KeystrokeStripLayout.spacing)
    static let cornerRadius: CGFloat = 16
    /// Liquid Glass draws past the cap. The panel keeps this outside the row.
    static let shadowRoom: CGFloat = 12

    static func stripSize(count: Int) -> CGSize {
        let layout = KeystrokeStripLayout.layout(count: count)
        return CGSize(width: layout.width, height: layout.height)
    }
}
