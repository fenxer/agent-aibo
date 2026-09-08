import Testing
@testable import AiboCore

@Test func onboardingPresentsOnFreshFirstLaunch() {
    #expect(
        OnboardingGate.shouldPresentOnLaunch(
            storedCompleted: nil,
            hasExistingInstallEvidence: false
        )
    )
}

@Test func onboardingSkipsWhenAlreadyCompleted() {
    #expect(
        OnboardingGate.shouldPresentOnLaunch(
            storedCompleted: true,
            hasExistingInstallEvidence: false
        ) == false
    )
    #expect(
        OnboardingGate.shouldPresentOnLaunch(
            storedCompleted: true,
            hasExistingInstallEvidence: true
        ) == false
    )
}

@Test func onboardingSkipsExistingInstallWithoutFlag() {
    #expect(
        OnboardingGate.shouldPresentOnLaunch(
            storedCompleted: nil,
            hasExistingInstallEvidence: true
        ) == false
    )
}

@Test func onboardingPresentsWhenFlagExplicitlyIncomplete() {
    #expect(
        OnboardingGate.shouldPresentOnLaunch(
            storedCompleted: false,
            hasExistingInstallEvidence: true
        )
    )
}
