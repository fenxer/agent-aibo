import AppKit

/// One Mac key, already labeled for a 72pt cap. Left and right modifiers stay
/// distinct so both can be held, and they share a glyph.
struct MacKeycap: Equatable {
    var id: String
    var label: String
    var symbolName: String?
    var isModifier: Bool

    static func nonModifier(from event: NSEvent) -> MacKeycap? {
        let keyCode = event.keyCode
        guard modifierKeyCodes.contains(keyCode) == false else { return nil }
        if let special = special(keyCode: keyCode) { return special }
        guard let raw = event.charactersIgnoringModifiers, let first = raw.first else { return nil }
        guard first.isNewline == false else { return nil }
        let label = first.isLetter ? String(first).uppercased() : String(first)
        guard label.isEmpty == false else { return nil }
        return MacKeycap(id: "vk.\(keyCode)", label: label, symbolName: nil, isModifier: false)
    }

    static func modifier(keyCode: UInt16) -> MacKeycap? {
        switch keyCode {
        case 0x37: symbol("command.left", "command", modifier: true)
        case 0x36: symbol("command.right", "command", modifier: true)
        case 0x3A: symbol("option.left", "option", modifier: true)
        case 0x3D: symbol("option.right", "option", modifier: true)
        case 0x38: symbol("shift.left", "shift", modifier: true)
        case 0x3C: symbol("shift.right", "shift", modifier: true)
        case 0x3B: symbol("control.left", "control", modifier: true)
        case 0x3E: symbol("control.right", "control", modifier: true)
        case 0x3F, 0xB3: MacKeycap(id: "fn", label: "FN", symbolName: nil, isModifier: true)
        case 0x39: symbol("capsLock", "capslock", modifier: true)
        default: nil
        }
    }

    /// Left and right sides share one flag. The flag is the source of truth for
    /// “is this modifier still down”; keyCode only says which side changed.
    static func modifierFlag(keyCode: UInt16) -> NSEvent.ModifierFlags? {
        switch keyCode {
        case 0x37, 0x36: .command
        case 0x38, 0x3C: .shift
        case 0x3A, 0x3D: .option
        case 0x3B, 0x3E: .control
        case 0x3F, 0xB3: .function
        default: nil
        }
    }

    static let modifierGroups: [(NSEvent.ModifierFlags, [UInt16])] = [
        (.command, [0x37, 0x36]),
        (.shift, [0x38, 0x3C]),
        (.option, [0x3A, 0x3D]),
        (.control, [0x3B, 0x3E]),
        (.function, [0x3F, 0xB3]),
    ]

    private static let modifierKeyCodes: Set<UInt16> = [
        0x36, 0x37, 0x38, 0x39, 0x3A, 0x3B, 0x3C, 0x3D, 0x3E, 0x3F, 0xB3,
    ]

    private static func symbol(_ id: String, _ name: String, modifier: Bool) -> MacKeycap {
        MacKeycap(id: id, label: "", symbolName: name, isModifier: modifier)
    }

    private static func special(keyCode: UInt16) -> MacKeycap? {
        switch keyCode {
        case 0x31:
            MacKeycap(
                id: "space",
                label: String(localized: "keystroke.key.space", defaultValue: "SPACE"),
                symbolName: nil,
                isModifier: false
            )
        case 0x24, 0x4C: symbol("return.\(keyCode)", "return", modifier: false)
        case 0x30: MacKeycap(id: "tab", label: "TAB", symbolName: nil, isModifier: false)
        case 0x35: MacKeycap(id: "escape", label: "ESC", symbolName: nil, isModifier: false)
        case 0x33: symbol("delete", "delete.left", modifier: false)
        case 0x75: symbol("forwardDelete", "delete.forward", modifier: false)
        case 0x7B: symbol("left", "arrow.left", modifier: false)
        case 0x7C: symbol("right", "arrow.right", modifier: false)
        case 0x7D: symbol("down", "arrow.down", modifier: false)
        case 0x7E: symbol("up", "arrow.up", modifier: false)
        case 0x73: MacKeycap(id: "home", label: "HOME", symbolName: nil, isModifier: false)
        case 0x77: MacKeycap(id: "end", label: "END", symbolName: nil, isModifier: false)
        case 0x74: MacKeycap(id: "pageUp", label: "PGUP", symbolName: nil, isModifier: false)
        case 0x79: MacKeycap(id: "pageDown", label: "PGDN", symbolName: nil, isModifier: false)
        case 0x7A: function("F1")
        case 0x78: function("F2")
        case 0x63: function("F3")
        case 0x76: function("F4")
        case 0x60: function("F5")
        case 0x61: function("F6")
        case 0x62: function("F7")
        case 0x64: function("F8")
        case 0x65: function("F9")
        case 0x6D: function("F10")
        case 0x67: function("F11")
        case 0x6F: function("F12")
        case 0x69: function("F13")
        case 0x6B: function("F14")
        case 0x71: function("F15")
        case 0x6A: function("F16")
        case 0x40: function("F17")
        case 0x4F: function("F18")
        case 0x50: function("F19")
        case 0x5A: function("F20")
        default: nil
        }
    }

    private static func function(_ name: String) -> MacKeycap {
        MacKeycap(id: name, label: name, symbolName: nil, isModifier: false)
    }
}
