import AppKit
import CoreGraphics
// import OSLog

// MARK: - Private Spaces API (undocumented; degrades to false if unavailable)

private typealias CGSConnectionID = Int32
private typealias CGSSpaceID = UInt64

@_silgen_name("CGSMainConnectionID")
private func CGSMainConnectionID() -> CGSConnectionID

@_silgen_name("CGSGetActiveSpace")
private func CGSGetActiveSpace(_ cid: CGSConnectionID) -> CGSSpaceID

/// Returns an array of per-display dictionaries describing managed Spaces.
@_silgen_name("CGSCopyManagedDisplaySpaces")
private func CGSCopyManagedDisplaySpaces(_ cid: CGSConnectionID) -> Unmanaged<CFArray>?

/// Native fullscreen Space type used by the green-button / Space fullscreen path.
private let cgsSpaceTypeFullscreen = 4

// private let fullscreenLog = Logger(subsystem: "work.fenx.aibo", category: "Fullscreen")

/// Event-driven fullscreen detector:
/// 1. `NSApp.currentSystemPresentationOptions` contains `.fullScreen`
/// 2. Private Spaces API: **active** Space `type == 4` (not “any display”)
///
/// No Accessibility permission, no polling. Private API failure → not fullscreen.
@MainActor
final class FullscreenSpaceMonitor {
    var onChange: ((Bool) -> Void)?
    /// Fired when detection stays `false` across a Space switch — panel must re-assert itself.
    var onReaffirmVisible: (() -> Void)?

    /// Preferred screen for logging / secondary Current Space check (pet's screen).
    var screenProvider: (() -> NSScreen?)?

    private(set) var isFullscreen = false
    private var spaceObserver: NSObjectProtocol?
    private var activateObserver: NSObjectProtocol?
    private var presentationObservation: NSKeyValueObservation?

    func start() {
        guard spaceObserver == nil else {
            evaluate(reason: "start-again")
            return
        }

        let workspace = NSWorkspace.shared.notificationCenter
        spaceObserver = workspace.addObserver(
            forName: NSWorkspace.activeSpaceDidChangeNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.evaluate(reason: "activeSpaceDidChange")
            }
        }
        activateObserver = workspace.addObserver(
            forName: NSWorkspace.didActivateApplicationNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.evaluate(reason: "didActivateApplication")
            }
        }
        presentationObservation = NSApp.observe(
            \.currentSystemPresentationOptions,
            options: [.initial, .new]
        ) { [weak self] _, _ in
            // KVO may arrive off-main; hop without an extra outer delay when already main.
            if Thread.isMainThread {
                MainActor.assumeIsolated {
                    self?.evaluate(reason: "presentationOptions")
                }
            } else {
                Task { @MainActor [weak self] in
                    self?.evaluate(reason: "presentationOptions")
                }
            }
        }
        evaluate(reason: "start")
    }

    func stop() {
        if let spaceObserver {
            NSWorkspace.shared.notificationCenter.removeObserver(spaceObserver)
            self.spaceObserver = nil
        }
        if let activateObserver {
            NSWorkspace.shared.notificationCenter.removeObserver(activateObserver)
            self.activateObserver = nil
        }
        presentationObservation?.invalidate()
        presentationObservation = nil
        if isFullscreen {
            isFullscreen = false
            onChange?(false)
        }
    }

    func evaluate(reason: String) {
        let screen = screenProvider?()
        let next = Self.detect(on: screen, reason: reason)
        if next != isFullscreen {
            // fullscreenLog.info("fullscreen \(next, privacy: .public) ← \(reason, privacy: .public)")
            isFullscreen = next
            onChange?(next)
            return
        }
        // Desktop Space switch: relocate pet onto the active Space (moveToActiveSpace).
        if !next, reason == "activeSpaceDidChange" {
            // fullscreenLog.debug("reaffirm visible ← \(reason, privacy: .public)")
            onReaffirmVisible?()
        }
    }

    static func detect(on screen: NSScreen?, reason: String) -> Bool {
        let options = NSApp.currentSystemPresentationOptions
        let presentationFS = options.contains(.fullScreen)
        let spaceFS = isActiveSpaceFullscreen(on: screen, reason: reason)
        let result = presentationFS || spaceFS
        // fullscreenLog.debug(
        //     "detect[\(reason, privacy: .public)] presentationFS=\(presentationFS, privacy: .public) spaceFS=\(spaceFS, privacy: .public) options=\(String(describing: options.rawValue), privacy: .public) → \(result, privacy: .public)"
        // )
        return result
    }

    /// True only when the **active** Space (what the user is viewing) has type 4.
    private static func isActiveSpaceFullscreen(on screen: NSScreen?, reason: String) -> Bool {
        guard let displays = copyManagedDisplaySpaces() else {
            // fullscreenLog.debug("detect[\(reason, privacy: .public)] CGSCopyManagedDisplaySpaces failed")
            return false
        }

        let activeID = CGSGetActiveSpace(CGSMainConnectionID())
        var activeType: Int?

        for display in displays {
            if let type = typeOfSpace(id: activeID, in: display) {
                activeType = type
                break
            }
        }

        // fullscreenLog.debug(
        //     "detect[\(reason, privacy: .public)] activeSpaceID=\(activeID, privacy: .public) activeType=\(String(describing: activeType), privacy: .public) petScreen=\(screen?.localizedName ?? "nil", privacy: .public)"
        // )

        if let activeType {
            return activeType == cgsSpaceTypeFullscreen
        }

        // Last resort: pet screen's Current Space only — never “any display is fullscreen”.
        if let screen,
           let display = displayMatching(screen, in: displays),
           let type = currentSpaceType(of: display)
        {
            // fullscreenLog.debug(
            //     "detect[\(reason, privacy: .public)] fallback pet Current Space type=\(type, privacy: .public)"
            // )
            return type == cgsSpaceTypeFullscreen
        }

        // fullscreenLog.debug("detect[\(reason, privacy: .public)] no active space type resolved → false")
        return false
    }

    private static func typeOfSpace(id: CGSSpaceID, in display: [String: Any]) -> Int? {
        if let current = display["Current Space"] as? [String: Any],
           spaceID(current) == id
        {
            return resolvedType(current: current, display: display)
        }
        guard let spaces = display["Spaces"] as? [[String: Any]] else { return nil }
        guard let match = spaces.first(where: { spaceID($0) == id }) else { return nil }
        return intValue(match["type"])
    }

    private static func resolvedType(current: [String: Any], display: [String: Any]) -> Int? {
        if let type = intValue(current["type"]) {
            return type
        }
        guard let currentID = spaceID(current),
              let spaces = display["Spaces"] as? [[String: Any]],
              let match = spaces.first(where: { spaceID($0) == currentID })
        else { return nil }
        return intValue(match["type"])
    }

    private static func displayMatching(_ screen: NSScreen, in displays: [[String: Any]]) -> [String: Any]? {
        guard let uuid = displayUUIDString(for: screen) else { return nil }
        let needle = uuid.lowercased()
        return displays.first {
            displayIdentifier(of: $0)?.lowercased() == needle
        }
    }

    private static func copyManagedDisplaySpaces() -> [[String: Any]]? {
        guard let unmanaged = CGSCopyManagedDisplaySpaces(CGSMainConnectionID()) else {
            return nil
        }
        return unmanaged.takeRetainedValue() as? [[String: Any]]
    }

    private static func displayIdentifier(of display: [String: Any]) -> String? {
        display["Display Identifier"] as? String
    }

    private static func currentSpaceType(of display: [String: Any]) -> Int? {
        guard let current = display["Current Space"] as? [String: Any] else { return nil }
        return resolvedType(current: current, display: display)
    }

    private static func spaceID(_ space: [String: Any]) -> CGSSpaceID? {
        if let id = space["id64"] as? UInt64 { return id }
        if let id = space["ManagedSpaceID"] as? UInt64 { return id }
        if let id = space["id64"] as? Int { return CGSSpaceID(id) }
        if let id = space["ManagedSpaceID"] as? Int { return CGSSpaceID(id) }
        if let id = space["id64"] as? Int64 { return CGSSpaceID(id) }
        if let id = space["ManagedSpaceID"] as? Int64 { return CGSSpaceID(id) }
        return nil
    }

    private static func intValue(_ raw: Any?) -> Int? {
        switch raw {
        case let value as Int: value
        case let value as NSNumber: value.intValue
        default: nil
        }
    }

    private static func displayUUIDString(for screen: NSScreen) -> String? {
        guard let number = screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber
        else { return nil }
        let displayID = CGDirectDisplayID(number.uint32Value)
        guard let cfUUID = CGDisplayCreateUUIDFromDisplayID(displayID)?.takeRetainedValue() else {
            return nil
        }
        return CFUUIDCreateString(nil, cfUUID) as String
    }
}
