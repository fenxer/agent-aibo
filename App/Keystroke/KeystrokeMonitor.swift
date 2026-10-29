import AiboCore
import AppKit
import ApplicationServices

/// Global keystrokes for the recording overlay. Monitors exist only while the
/// tool is on. After every key is up the group stays for the Stay Time in
/// Settings, unless that time is 0 or a new group replaces it. The sleep is
/// one-shot and is cancelled by the next press.
@MainActor
@Observable
final class KeystrokeMonitor {
    static let shared = KeystrokeMonitor()

    private(set) var displayed: [KeystrokePress] = []
    private(set) var accessibilityTrusted = true

    private var gesture = KeystrokeGesture()
    private var heldModifierCodes: Set<UInt16> = []
    private var localMonitor: Any?
    private var globalMonitor: Any?
    /// The last group is fully released and still on screen.
    private var groupWaitingToClear = false
    private var lingerTask: Task<Void, Never>?

    private init() {}

    func setEnabled(_ enabled: Bool, promptForAccessibility: Bool) {
        guard enabled else {
            stop()
            return
        }
        if promptForAccessibility {
            accessibilityTrusted = Self.isTrusted(prompt: true)
        }
        installMonitors()
    }

    func recheckAccessibility() {
        guard AppSettings.shared.keystrokeOverlayEnabled else { return }
        accessibilityTrusted = Self.isTrusted(prompt: false)
        if accessibilityTrusted {
            installGlobalMonitorIfNeeded()
        }
    }

    private func stop() {
        lingerTask?.cancel()
        lingerTask = nil
        groupWaitingToClear = false
        gesture.clear()
        heldModifierCodes.removeAll()
        if displayed.isEmpty == false {
            displayed = []
            AiboPanelController.shared.syncKeystrokeGeometry()
        }
        removeMonitors()
    }

    private func installMonitors() {
        let mask: NSEvent.EventTypeMask = [.keyDown, .keyUp, .flagsChanged]
        if localMonitor == nil {
            localMonitor = NSEvent.addLocalMonitorForEvents(matching: mask) { [weak self] event in
                self?.handle(event)
                return event
            }
        }
        installGlobalMonitorIfNeeded()
    }

    private func installGlobalMonitorIfNeeded() {
        guard globalMonitor == nil else { return }
        let trusted = Self.isTrusted(prompt: false)
        accessibilityTrusted = trusted
        guard trusted else { return }
        let mask: NSEvent.EventTypeMask = [.keyDown, .keyUp, .flagsChanged]
        globalMonitor = NSEvent.addGlobalMonitorForEvents(matching: mask) { [weak self] event in
            self?.handle(event)
        }
    }

    private func removeMonitors() {
        if let localMonitor {
            NSEvent.removeMonitor(localMonitor)
            self.localMonitor = nil
        }
        if let globalMonitor {
            NSEvent.removeMonitor(globalMonitor)
            self.globalMonitor = nil
        }
    }

    private func handle(_ event: NSEvent) {
        switch event.type {
        case .keyDown:
            guard event.isARepeat == false, let keycap = MacKeycap.nonModifier(from: event) else { return }
            notePress(keycap, at: event.timestamp)
        case .keyUp:
            guard let keycap = MacKeycap.nonModifier(from: event) else { return }
            noteRelease(keycap.id)
        case .flagsChanged:
            handleFlags(event)
        default:
            break
        }
    }

    /// `flagsChanged` is the physical down/up for modifiers. Caps Lock only
    /// toggles a sticky flag, so each event is shown as a tap.
    private func handleFlags(_ event: NSEvent) {
        let keyCode = event.keyCode
        guard let keycap = MacKeycap.modifier(keyCode: keyCode) else { return }
        if keyCode == 0x39 {
            notePress(keycap, at: event.timestamp)
            noteRelease(keycap.id)
            return
        }
        if heldModifierCodes.contains(keyCode) {
            heldModifierCodes.remove(keyCode)
            noteRelease(keycap.id)
        } else {
            heldModifierCodes.insert(keyCode)
            notePress(keycap, at: event.timestamp)
        }
    }

    func lingerDurationChanged() {
        guard groupWaitingToClear else { return }
        scheduleLinger()
    }

    func maxCountChanged() {
        gesture.clamp(to: AppSettings.shared.keystrokeMaxCount)
        publish()
    }

    private func notePress(_ keycap: MacKeycap, at time: TimeInterval) {
        lingerTask?.cancel()
        lingerTask = nil
        groupWaitingToClear = false
        gesture.press(
            KeystrokePress(
                id: keycap.id,
                physicalID: keycap.id,
                isModifier: keycap.isModifier,
                label: keycap.label,
                symbolName: keycap.symbolName
            ),
            at: time,
            limit: AppSettings.shared.keystrokeMaxCount
        )
        publish()
    }

    private func noteRelease(_ id: String) {
        let wasHolding = gesture.hasHeldKeys
        let ended = gesture.release(id: id)
        publish()
        guard wasHolding else { return }
        guard ended else {
            groupWaitingToClear = false
            lingerTask?.cancel()
            lingerTask = nil
            return
        }
        groupWaitingToClear = true
        scheduleLinger()
    }

    private func scheduleLinger() {
        lingerTask?.cancel()
        lingerTask = nil
        let seconds = AppSettings.shared.keystrokeLingerSeconds
        guard seconds > 0 else { return }
        lingerTask = Task { @MainActor in
            try? await Task.sleep(for: .seconds(seconds))
            guard Task.isCancelled == false else { return }
            self.groupWaitingToClear = false
            self.gesture.clear()
            self.publish()
        }
    }

    private func publish() {
        let next = gesture.displayed
        guard next != displayed else { return }
        displayed = next
        AiboPanelController.shared.syncKeystrokeGeometry()
    }

    private static func isTrusted(prompt: Bool) -> Bool {
        let key = kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String
        let options = [key: prompt] as CFDictionary
        return AXIsProcessTrustedWithOptions(options)
    }
}
