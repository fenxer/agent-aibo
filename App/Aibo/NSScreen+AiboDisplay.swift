import AppKit
import CoreGraphics

extension NSScreen {
    /// Stable identifier for this display. Survives arrangement changes; not `NSScreen.main`.
    var aiboDisplayUUID: String? {
        guard let number = deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber
        else { return nil }
        let displayID = CGDirectDisplayID(number.uint32Value)
        guard let cfUUID = CGDisplayCreateUUIDFromDisplayID(displayID)?.takeRetainedValue() else {
            return nil
        }
        return CFUUIDCreateString(nil, cfUUID) as String
    }

    static func aiboScreen(withDisplayUUID uuid: String?) -> NSScreen? {
        guard let uuid, !uuid.isEmpty else { return nil }
        return screens.first { $0.aiboDisplayUUID == uuid }
    }

    static func aiboScreenContaining(_ point: CGPoint) -> NSScreen? {
        screens.first { $0.frame.contains(point) }
    }
}
