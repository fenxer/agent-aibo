import AiboCore
import AppKit
import SwiftUI

enum AiboSpritePixelLayout: Equatable {
    /// Integer-scale inside a square `nominal`×`nominal` slot (settings previews).
    case fit
    /// `nominal` is the target width; height follows the sprite aspect (desktop).
    case fillWidth
}

enum AiboSpriteDisplay {
    static let basePointSize: CGFloat = 96

    static func pixelOptimizationPercents(
        for record: AiboLibraryRecord,
        backingScale: CGFloat
    ) -> [Double] {
        guard record.kind != .builtInDefault,
              backingScale > 0,
              let source = AiboSpriteCache.shared.sourcePixelSize(for: record)
        else {
            return AppSettings.pixelOptimizationScalePercents
        }
        return PixelArtScale.distinctFillWidthPercents(
            sourceWidth: source.width,
            sourceHeight: source.height,
            backingScale: Double(backingScale),
            baseSize: Double(basePointSize),
            candidates: AppSettings.pixelOptimizationScalePercents
        )
    }

    static func desktopSize(
        for record: AiboLibraryRecord,
        nominal: CGFloat,
        backingScale: CGFloat
    ) -> CGSize {
        size(for: record, nominal: nominal, backingScale: backingScale, layout: .fillWidth)
    }

    static func size(
        for record: AiboLibraryRecord,
        nominal: CGFloat,
        backingScale: CGFloat,
        layout: AiboSpritePixelLayout
    ) -> CGSize {
        let square = CGSize(width: nominal, height: nominal)
        guard record.pixelOptimizationEnabled,
              record.kind != .builtInDefault,
              nominal > 0,
              backingScale > 0,
              let source = AiboSpriteCache.shared.sourcePixelSize(for: record)
        else { return square }

        let result: PixelArtScale.Layout
        switch layout {
        case .fillWidth:
            result = PixelArtScale.fillWidth(
                sourceWidth: source.width,
                sourceHeight: source.height,
                targetWidth: Double(nominal),
                backingScale: Double(backingScale)
            )
        case .fit:
            result = PixelArtScale.fit(
                sourceWidth: source.width,
                sourceHeight: source.height,
                targetWidth: Double(nominal),
                targetHeight: Double(nominal),
                backingScale: Double(backingScale)
            )
        }
        return CGSize(width: result.width, height: result.height)
    }
}
