import Foundation
import Testing
@testable import AiboCore

@Test func aiboSwitchCubicInOutAnchorsAndMidpoint() {
    #expect(AiboSwitchTransition.cubicInOut(0) == 0)
    #expect(AiboSwitchTransition.cubicInOut(1) == 1)
    #expect(AiboSwitchTransition.cubicInOut(0.5) == 0.5)
    #expect(AiboSwitchTransition.cubicInOut(0.25) == 0.0625)
    #expect(AiboSwitchTransition.cubicInOut(0.75) == 0.9375)
}

@Test func aiboSwitchCubicInOutClamps() {
    #expect(AiboSwitchTransition.cubicInOut(-1) == 0)
    #expect(AiboSwitchTransition.cubicInOut(2) == 1)
}

@Test func aiboSwitchGlslModMatchesFloorDefinition() {
    #expect(AiboSwitchTransition.glslMod(1.3, 2) == 1.3)
    #expect(AiboSwitchTransition.glslMod(-0.3, 2) == 1.7)
    #expect(AiboSwitchTransition.glslMod(2.0, 2) == 0)
}

@Test func aiboSwitchMirrorFoldsEachSide() {
    #expect(AiboSwitchTransition.mirror(0.3) == 0.3)
    #expect(AiboSwitchTransition.mirror(1.3) == 0.7)
    #expect(abs(AiboSwitchTransition.mirror(-0.3) - 0.3) < 1e-12)
    #expect(abs(AiboSwitchTransition.mirror(2.3) - 0.3) < 1e-12)
}

@Test func aiboSwitchStepMaskIsExclusiveAtTheEnds() {
    for mask in [0.0, 0.2, 0.8, 1.0] {
        #expect(AiboSwitchTransition.stepMask(mask: mask, progress: 0) == 1)
        #expect(AiboSwitchTransition.stepMask(mask: mask, progress: 1) == 0)
    }
}

@Test func aiboSwitchStepMaskFollowsMaskMidTransition() {
    #expect(abs(AiboSwitchTransition.stepMask(mask: 0.8, progress: 0.5) - 0.3) < 1e-12)
}
