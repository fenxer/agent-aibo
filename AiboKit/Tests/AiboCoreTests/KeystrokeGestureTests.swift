import Testing
@testable import AiboCore

private func key(_ id: String, modifier: Bool = false) -> KeystrokePress {
    KeystrokePress(id: id, isModifier: modifier, label: id, symbolName: nil)
}

@Test func pressesInsideTheGapStayOneGroup() {
    var gesture = KeystrokeGesture()
    gesture.press(key("command", modifier: true), at: 0)
    gesture.press(key("option", modifier: true), at: 0.12)
    gesture.press(key("space"), at: 0.28)

    #expect(gesture.displayed.map(\.physicalID) == ["command", "option", "space"])
    #expect(gesture.displayed.map(\.staggerIndex) == [0, 1, 2])

    #expect(gesture.release(id: "space") == false)
    #expect(gesture.displayed.map(\.physicalID) == ["command", "option", "space"])
    #expect(gesture.release(id: "option") == false)
    #expect(gesture.release(id: "command") == true)
    #expect(gesture.displayed.map(\.physicalID) == ["command", "option", "space"])

    gesture.clear()
    #expect(gesture.displayed.isEmpty)
}

@Test func aPressAfterTheGapStartsANewGroup() {
    var gesture = KeystrokeGesture()
    gesture.press(key("a"), at: 0)
    #expect(gesture.release(id: "a") == true)
    gesture.press(key("b"), at: 0.2)
    #expect(gesture.displayed.map(\.physicalID) == ["a", "b"])

    gesture.press(key("c"), at: 0.2 + KeystrokeGesture.groupGap + 0.01)
    #expect(gesture.displayed.map(\.physicalID) == ["c"])
    #expect(gesture.displayed.map(\.staggerIndex) == [0])
}

@Test func groupShowsAtMostTheChosenCount() {
    var gesture = KeystrokeGesture()
    for index in 0..<7 {
        let name = "k\(index)"
        gesture.press(key(name), at: Double(index) * 0.05, limit: 6)
        _ = gesture.release(id: name)
    }
    #expect(gesture.displayed.map(\.physicalID) == ["k1", "k2", "k3", "k4", "k5", "k6"])

    gesture.clamp(to: 4)
    #expect(gesture.displayed.map(\.physicalID) == ["k3", "k4", "k5", "k6"])
}

@Test func aZeroLimitKeepsTheIntervalGroupUntilTheRowCap() {
    var growing = KeystrokeGesture()
    for name in ["a", "b", "c", "d", "e", "f", "g"] {
        let index = growing.displayed.count
        growing.press(key(name), at: Double(index) * 0.05, limit: 0)
    }
    #expect(growing.displayed.map(\.physicalID) == ["a", "b", "c", "d", "e", "f", "g"])

    var capped = KeystrokeGesture()
    let total = KeystrokeStripLayout.visualCap + 1
    for index in 0..<total {
        capped.press(key("n\(index)"), at: Double(index) * 0.01, limit: 0)
        _ = capped.release(id: "n\(index)")
    }
    #expect(capped.displayed.count == KeystrokeStripLayout.visualCap)
    #expect(capped.displayed.first?.physicalID == "n1")
    #expect(capped.displayed.last?.physicalID == "n\(total - 1)")
}

@Test func theSameLetterCanAppearTwiceAfterRelease() {
    var gesture = KeystrokeGesture()
    gesture.press(key("a"), at: 0)
    #expect(gesture.release(id: "a") == true)
    gesture.press(key("a"), at: 0.1)
    #expect(gesture.displayed.map(\.physicalID) == ["a", "a"])
    #expect(Set(gesture.displayed.map(\.id)).count == 2)
}

@Test func stripShrinksAndWrapsAsTheGroupGrows() {
    let six = KeystrokeStripLayout.layout(count: 6)
    #expect(six.side == 72)
    #expect(six.rows == 1)
    #expect(six.keysPerRow == 6)

    let seven = KeystrokeStripLayout.layout(count: 7)
    #expect(seven.side == 40)
    #expect(seven.rows == 1)
    #expect(seven.keysPerRow == 10)

    let eleven = KeystrokeStripLayout.layout(count: 11)
    #expect(eleven.side == 40)
    #expect(eleven.rows == 2)

    let forty = KeystrokeStripLayout.layout(count: 40)
    #expect(forty.side == 40)
    #expect(forty.rows == 4)

    let fortyOne = KeystrokeStripLayout.layout(count: 41)
    #expect(fortyOne.side == 24)
    #expect(fortyOne.rows == 5)
    #expect(fortyOne.keysPerRow == 10)

    let full = KeystrokeStripLayout.layout(count: 100)
    #expect(full.side == 24)
    #expect(full.rows == 10)
    #expect(full.count == 100)
}

@Test func repeatPressDoesNotDuplicateAHeldKey() {
    var gesture = KeystrokeGesture()
    gesture.press(key("a"), at: 0)
    gesture.press(key("a"), at: 0.05)
    #expect(gesture.displayed.map(\.physicalID) == ["a"])
    #expect(gesture.release(id: "missing") == false)
}
