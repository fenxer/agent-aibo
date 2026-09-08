import Foundation
import Testing
@testable import AiboCore

@Test func launchPortalRingFollowsTl3Steps() {
    let start = AiboLaunchPortalTimeline.frame(at: 0)
    #expect(start.ringRadius == 0)
    #expect(start.ringOpacity == 0)
    #expect(abs(start.ringThickness - 0.34) < 1e-9)
    #expect(abs(start.ringDepth - 0.35) < 1e-9)
    #expect(start.poliProgress == 0)
    #expect(start.opacity == 0)
    #expect(!start.isFinished)

    let opened = AiboLaunchPortalTimeline.frame(at: 0.8)
    #expect(abs(opened.ringRadius - 2) < 1e-9)
    #expect(abs(opened.ringOpacity - 1) < 1e-9)
    #expect(abs(opened.ringThickness - 0.15) < 1e-9)

    let held = AiboLaunchPortalTimeline.frame(at: 1.4)
    #expect(abs(held.ringRadius - 2) < 1e-9)
    #expect(abs(held.ringThickness - 0.1) < 1e-9)

    let done = AiboLaunchPortalTimeline.frame(at: AiboLaunchPortalTimeline.duration)
    #expect(abs(done.ringRadius) < 1e-9)
    #expect(abs(done.ringOpacity) < 1e-9)
    #expect(done.isFinished)
}

@Test func launchPortalPoliPathUsesTl3HalvedWebPixels() {
    #expect(AiboLaunchPortalTimeline.poliDelay == 0.9)
    #expect(AiboLaunchPortalTimeline.xTo == 24)
    #expect(AiboLaunchPortalTimeline.yFrom == 0)
    #expect(AiboLaunchPortalTimeline.yTo == 12)
    #expect(AiboLaunchPortalTimeline.arc == 35)

    let before = AiboLaunchPortalTimeline.frame(at: AiboLaunchPortalTimeline.poliDelay - 0.01)
    #expect(before.poliProgress == 0)
    #expect(before.y == 0)

    let midTime = AiboLaunchPortalTimeline.poliDelay + AiboLaunchPortalTimeline.poliClipDuration * 0.5
    let mid = AiboLaunchPortalTimeline.frame(at: midTime)
    #expect(abs(mid.poliProgress - 0.5) < 1e-9)
    #expect(abs(mid.x - 12) < 1e-9)
    #expect(abs(mid.y - (-29)) < 1e-9)

    let landed = AiboLaunchPortalTimeline.frame(
        at: AiboLaunchPortalTimeline.poliDelay + AiboLaunchPortalTimeline.poliClipDuration
    )
    #expect(abs(landed.poliProgress - 1) < 1e-9)
    #expect(abs(landed.x - 24) < 1e-9)
    #expect(abs(landed.y - 12) < 1e-9)
    #expect(abs(landed.restRelativeX) < 1e-9)
    #expect(abs(landed.restRelativeY) < 1e-9)
    #expect(abs(mid.restRelativeX - (12 - 24)) < 1e-9)
    #expect(abs(mid.restRelativeY - (-29 - 12)) < 1e-9)
}

@Test func launchPortalBlurFollowsTl3HalvedWebPixels() {
    #expect(AiboLaunchPortalTimeline.blurFrom == 32)
    #expect(AiboLaunchPortalTimeline.blurTo == 0)
    #expect(AiboLaunchPortalTimeline.blurDuration == 0.5)

    let before = AiboLaunchPortalTimeline.frame(at: AiboLaunchPortalTimeline.poliDelay)
    #expect(abs(before.blur - 32) < 1e-9)

    let sharp = AiboLaunchPortalTimeline.frame(
        at: AiboLaunchPortalTimeline.poliDelay + AiboLaunchPortalTimeline.blurDuration
    )
    #expect(abs(sharp.blur) < 1e-9)
}

@Test func launchPortalCubicBezierAnchors() {
    let ease = AiboLaunchPortalTimeline.ringEase
    #expect(ease.value(at: 0) == 0)
    #expect(ease.value(at: 1) == 1)
    #expect(ease.value(at: -1) == 0)
    #expect(ease.value(at: 2) == 1)
}

@Test func launchPortalSpringSettlesToOne() {
    let spring = AiboLaunchPortalTimeline.scaleSpring
    #expect(spring.progress(at: 0) == 0)
    #expect(abs(spring.progress(at: spring.settleDuration) - 1) < 1e-9)
    #expect(abs(spring.progress(at: 8) - 1) < 1e-9)
}

@Test func launchPortalLayoutIsCenteredOnSettledAibo() {
    let layout = AiboLaunchPortalTimeline.layout(aiboSize: CGSize(width: 96, height: 96))
    #expect(layout.canvas.width > 96)
    #expect(layout.extraLeading > 0)
    #expect(abs(layout.extraLeading - layout.extraTrailing) < 1e-9)
    #expect(abs(layout.extraTop - layout.extraBottom) < 1e-9)
    #expect(layout.xEnd == 24)
    #expect(layout.yEnd == 12)
    // Ring is 24pt left of rest; canvas half-width must cover ring + visual radius.
    #expect(layout.canvas.width / 2 >= 24 + 96 * 1.2)
}

@Test func launchPortalRestCenterMatchesBottomSlotWhenBubblesHidden() {
    let layout = AiboLaunchPortalTimeline.layout(aiboSize: CGSize(width: 96, height: 96))
    let panel = CGSize(width: 400, height: 400)
    let center = layout.restCenterYDown(
        panelSize: panel,
        leading: 20,
        trailing: 20,
        top: 20,
        bottom: 20,
        placement: .top
    )
    #expect(abs(center.x - 200) < 1e-9)
    // AppKit origin y = 20, center y = 68 → flipped 400 - 68 = 332.
    #expect(abs(center.y - 332) < 1e-9)

    let trailingHeavy = layout.restCenterYDown(
        panelSize: panel,
        leading: 20,
        trailing: 80,
        top: 20,
        bottom: 20,
        placement: .top
    )
    #expect(trailingHeavy.x < center.x)
}

@Test func reversePortalStartsAtRestAndJumpsIn() {
    let start = AiboLaunchPortalTimeline.frame(at: 0, playback: .reverse)
    let landed = AiboLaunchPortalTimeline.frame(at: AiboLaunchPortalTimeline.duration)
    #expect(abs(start.restRelativeX - landed.restRelativeX) < 1e-9)
    #expect(abs(start.restRelativeY - landed.restRelativeY) < 1e-9)
    #expect(abs(start.scale - landed.scale) < 1e-9)
    #expect(abs(start.opacity - 1) < 1e-9)
    #expect(abs(start.ringOpacity) < 1e-9)
    #expect(!start.isFinished)

    let ringOpen = AiboLaunchPortalTimeline.frame(at: 0.8, playback: .reverse)
    #expect(abs(ringOpen.ringRadius - 2) < 1e-9)
    #expect(abs(ringOpen.ringOpacity - 1) < 1e-9)
    #expect(!ringOpen.isFinished)

    let done = AiboLaunchPortalTimeline.frame(
        at: AiboLaunchPortalTimeline.duration,
        playback: .reverse
    )
    let origin = AiboLaunchPortalTimeline.frame(at: 0)
    #expect(abs(done.opacity - origin.opacity) < 1e-9)
    #expect(abs(done.scale - origin.scale) < 1e-9)
    #expect(done.isFinished)
}
