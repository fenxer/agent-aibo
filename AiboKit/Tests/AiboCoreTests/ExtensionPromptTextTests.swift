import Foundation
import Testing
@testable import AiboCore

@Test func promptTextCollapsesPastedLineBreaks() {
    #expect(ExtensionPromptText.normalized("a\n\n\nb", multiline: true) == "a\nb")
    #expect(ExtensionPromptText.normalized("a\r\n\r\nb", multiline: true) == "a\nb")
    #expect(ExtensionPromptText.normalized("a\u{2028}\u{2028}b", multiline: true) == "a\nb")
    #expect(ExtensionPromptText.normalized("a\u{2029}b", multiline: true) == "a\nb")
    #expect(ExtensionPromptText.normalized("a\u{0085}\u{0085}b", multiline: true) == "a\nb")
    #expect(ExtensionPromptText.normalized("a\nb", multiline: true) == "a\nb")
    #expect(ExtensionPromptText.normalized("a\u{0000}b\u{0007}c", multiline: true) == "abc")
    #expect(ExtensionPromptText.normalized("a\tb", multiline: true) == "a\tb")
}

@Test func promptTextSingleLineBecomesOneSpace() {
    #expect(ExtensionPromptText.normalized("a\n\nb", multiline: false) == "a b")
    #expect(ExtensionPromptText.normalized("a \n b", multiline: false) == "a b")
    #expect(ExtensionPromptText.normalized("a  b", multiline: false) == "a  b")
    let once = ExtensionPromptText.normalized("a\r\n\r\nb", multiline: false)
    #expect(ExtensionPromptText.normalized(once, multiline: false) == once)
}

@Test func promptTextJSONBodyEscapesLineSeparators() throws {
    let raw = "{\"a\":\"x\u{2028}y\u{2029}z\"}"
    let translated = ExtensionPromptText.translatingJSONBody(raw)
    #expect(translated.contains("\\u2028"))
    #expect(translated.contains("\\u2029"))
    #expect(!translated.unicodeScalars.contains("\u{2028}"))
    #expect(!translated.unicodeScalars.contains("\u{2029}"))
    let object = try #require(JSONSerialization.jsonObject(with: Data(translated.utf8)) as? [String: String])
    #expect(object["a"] == "x\u{2028}y\u{2029}z")

    let plain = "{\"a\":\"line\\n\\\"q\\\"\"}"
    #expect(ExtensionPromptText.translatingJSONBody(plain) == plain)

    let user = ExtensionPromptText.normalized("say \"hi\"\n\nnext \\ path", multiline: true)
    let payload: [String: Any] = ["messages": [["role": "user", "content": user]]]
    let data = try JSONSerialization.data(withJSONObject: payload)
    let decoded = try #require(JSONSerialization.jsonObject(with: data) as? [String: Any])
    let messages = try #require(decoded["messages"] as? [[String: String]])
    #expect(messages.first?["content"] == "say \"hi\"\nnext \\ path")
}
