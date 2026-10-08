import Foundation

/// Prompt-field text before it is shown and before a plugin puts it in a request body.
public enum ExtensionPromptText {
    /// Collapse pasted line breaks to a single `\n`. Single-line fields turn each
    /// break, and the spaces beside it, into one space.
    ///
    /// U+2028 / U+2029 count as line breaks here. `JSON.stringify` leaves those
    /// scalars raw inside strings, which splits a JSON body on the wire.
    public static func normalized(_ raw: String, multiline: Bool) -> String {
        let collapsed = collapsingBreaks(raw)
        guard multiline == false else { return collapsed }
        var scalars = String.UnicodeScalarView()
        scalars.reserveCapacity(collapsed.unicodeScalars.count)
        var index = collapsed.unicodeScalars.startIndex
        let source = collapsed.unicodeScalars
        while index < source.endIndex {
            let scalar = source[index]
            if scalar == "\n" {
                if scalars.last != " " {
                    scalars.append(" ")
                }
                index = source.index(after: index)
                while index < source.endIndex, source[index] == " " {
                    index = source.index(after: index)
                }
                continue
            }
            scalars.append(scalar)
            index = source.index(after: index)
        }
        return String(scalars)
    }

    /// Rewrite line / paragraph separators that `JSON.stringify` does not escape.
    /// Other characters stay for the JSON encoder. A body without those scalars
    /// is returned unchanged so a normal payload is not reformatted.
    public static func translatingJSONBody(_ body: String) -> String {
        guard body.unicodeScalars.contains(where: { $0 == "\u{2028}" || $0 == "\u{2029}" }) else {
            return body
        }
        var scalars = String.UnicodeScalarView()
        scalars.reserveCapacity(body.unicodeScalars.count + 6)
        for scalar in body.unicodeScalars {
            switch scalar {
            case "\u{2028}":
                scalars.append(contentsOf: "\\u2028".unicodeScalars)
            case "\u{2029}":
                scalars.append(contentsOf: "\\u2029".unicodeScalars)
            default:
                scalars.append(scalar)
            }
        }
        return String(scalars)
    }

    /// One `\n` per run of CR, LF, Unicode line separators. Drops other C0 controls; keeps tabs.
    private static func collapsingBreaks(_ raw: String) -> String {
        var scalars = String.UnicodeScalarView()
        scalars.reserveCapacity(raw.unicodeScalars.count)
        var inBreak = false
        for scalar in raw.unicodeScalars {
            if isLineBreak(scalar) {
                if inBreak { continue }
                inBreak = true
                scalars.append("\n")
                continue
            }
            inBreak = false
            if scalar.value < 0x20 || scalar.value == 0x7F {
                if scalar == "\t" {
                    scalars.append(scalar)
                }
                continue
            }
            scalars.append(scalar)
        }
        return String(scalars)
    }

    private static func isLineBreak(_ scalar: Unicode.Scalar) -> Bool {
        scalar == "\n" || scalar == "\r" || scalar == "\u{2028}" || scalar == "\u{2029}" || scalar == "\u{0085}"
    }
}
