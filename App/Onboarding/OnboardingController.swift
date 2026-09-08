import AiboCore
import AppKit
import Foundation
import UniformTypeIdentifiers

/// First-launch tour. Replay from Development does not clear the completed flag.
@MainActor
@Observable
final class OnboardingController {
    static let shared = OnboardingController()

    private static let completedKey = "onboarding.completed"
    private static let petdexSiteURL = URL(string: "https://petdex.dev/")!

    private(set) var isActive = false
    private(set) var step: OnboardingStep = .welcome
    private(set) var choosePhase: OnboardingChoosePhase = .options
    private(set) var errorMessage: String?

    var petdexURL = ""
    var namingDraft = ""
    var namingScalePercent = AiboLibraryRecord.defaultScalePercent
    var namingBubbleDistance = AiboLibraryRecord.defaultBubbleDistance

    /// Replay restores this after Skip / last-step Continue. First launch leaves the aibo where it is.
    private var restoreXPercent: Double?
    private var restoreYPercent: Double?
    private var replaySnapshot: AiboLibraryStore.OnboardingReplaySnapshot?
    private var namingRecordID: String?
    private(set) var namingIsPendingPack = false
    /// Set when the tour installs a custom aibo; later bubbles use it instead of Poli.
    private var tourCompanionName: String?

    private init() {}

    var currentBubbleItems: [StatusBubbleItem] {
        guard isActive else { return [] }
        let onboarding = StatusBubbleItem(
            id: step.bubbleID,
            text: bodyText,
            lastEventAt: .distantFuture,
            kind: .onboarding,
            animatesEllipsis: false,
            projectName: OnboardingChrome.projectName,
            modelName: tourCompanionName ?? OnboardingChrome.companionName
        )
        if step == .cursorExample {
            return [Self.cursorDemoBubble, onboarding]
        }
        return [onboarding]
    }

    var allowsKeyWindow: Bool {
        isActive && step == .chooseAibo && (choosePhase == .petdexInput || choosePhase == .naming)
    }

    /// Naming sliders keep the bubble fixed on screen; only the aibo moves.
    var pinsBubbleDuringLayout: Bool {
        isActive && step == .chooseAibo && choosePhase == .naming
    }

    var showsContinueHint: Bool { isActive && step.advancesOnBubbleTap }

    var showsSkip: Bool { isActive && step.showsSkipPill }

    var showsActionPills: Bool { isActive && (showsSkip || showsContinueHint) }

    var continueHintTitle: String { step.continueHintTitle }

    /// Only while the tour is running. Finish clears `isActive` (and `step`);
    /// without that, leftover tour flags would steal agent bubble taps.
    var bubbleTapAdvances: Bool { isActive && step.advancesOnBubbleTap }

    private var isChoosingAibo: Bool { isActive && step == .chooseAibo }

    private var bodyText: String {
        if step == .chooseAibo, choosePhase == .naming {
            return OnboardingStep.namingBodyText
        }
        return step.bodyText
    }

    /// Fake Cursor status stacked above the onboarding bubble (newest-first).
    private static var cursorDemoBubble: StatusBubbleItem {
        StatusBubbleItem(
            id: OnboardingChrome.cursorDemoBubbleID,
            text: StatusCopy.statusPhrase(for: .thinking) ?? "is thinking",
            lastEventAt: .distantFuture,
            kind: .agent,
            animatesEllipsis: true,
            agentName: StatusCopy.displayName(.cursor),
            iconAssetName: "cursor",
            projectName: OnboardingChrome.cursorDemoProjectName,
            modelName: OnboardingChrome.cursorDemoModelName,
            agent: .cursor
        )
    }

    /// Call before `AiboRuntime.start()` / first panel show so existing-install
    /// detection is not polluted by first-launch library migration flags.
    func startIfNeeded() {
        let stored = Self.storedCompleted
        let evidence = Self.hasExistingInstallEvidence()
        if OnboardingGate.shouldPresentOnLaunch(
            storedCompleted: stored,
            hasExistingInstallEvidence: evidence
        ) {
            // Persist in-progress so a quit before Skip/Continue still re-shows
            // after AiboLibraryStore writes its first-launch migration flags.
            if stored == nil {
                UserDefaults.standard.set(false, forKey: Self.completedKey)
            }
            begin()
            return
        }
        if stored == nil {
            Self.markCompleted()
        }
    }

    /// Development: run the tour again from the portal jump, then the welcome bubble.
    func replay() {
        let library = AiboLibraryStore.shared
        if replaySnapshot == nil {
            AiboPanelController.shared.persistRelativePositionNow()
            restoreXPercent = AppSettings.shared.savedAiboCenterXPercent
            restoreYPercent = AppSettings.shared.savedAiboCenterYPercent
            replaySnapshot = library.captureOnboardingReplaySnapshot()
        }
        if let snapshot = replaySnapshot {
            library.applyStockBuiltInForOnboardingReplay(snapshot)
        }
        begin()
        if !AiboPanelController.shared.isLaunchPortalPlaying {
            AiboPanelController.shared.syncGeometryNow()
            AiboPanelController.shared.placeAiboForOnboarding()
        }
    }

    func skip() {
        finish()
    }

    func advance() {
        guard isActive else { return }
        let all = OnboardingStep.allCases
        guard let index = all.firstIndex(of: step), all.index(after: index) < all.endIndex else {
            finish()
            return
        }
        let previous = step
        step = all[all.index(after: index)]
        if step == .chooseAibo || previous == .chooseAibo {
            resetChooseAiboState()
        }
        if step == .agentHook {
            errorMessage = nil
        }
        refreshPresentation()
    }

    func installTourHook(_ agent: AgentKind) {
        guard isActive, step == .agentHook else { return }
        guard OnboardingChrome.hookSetupAgents.contains(agent) else { return }
        let runtime = AiboRuntime.shared
        guard runtime.isHostAppInstalled(for: agent) else { return }
        guard !runtime.isHookInstalled(for: agent) else { return }
        runtime.installHooks(for: agent)
        errorMessage = runtime.lastErrorMessage
        refreshPresentation()
    }

    func completeAgentHookSetup() {
        guard isActive, step == .agentHook else { return }
        advance()
    }

    func useDefaultAibo() {
        guard isActive, step == .chooseAibo, choosePhase != .naming else { return }
        AiboLibraryStore.shared.cancelPendingNamedImport()
        advance()
    }

    func revealPetdexInput() {
        guard isActive, step == .chooseAibo, choosePhase != .naming else { return }
        guard choosePhase != .petdexInput else { return }
        errorMessage = nil
        choosePhase = .petdexInput
        refreshPresentation()
    }

    func presentLocalFilePicker() {
        guard isActive, step == .chooseAibo, choosePhase != .naming else { return }
        guard !AiboLibraryStore.shared.isInstalling else { return }

        let panel = NSOpenPanel()
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = false
        panel.allowedContentTypes = [.png, .jpeg, .webP, .heic, .tiff, .image, .zip]
        NSApp.activate()
        panel.begin { response in
            guard response == .OK, let url = panel.url else { return }
            Task { @MainActor in
                await OnboardingController.shared.importPickedFile(url)
            }
        }
    }

    func fetchPetdex() async {
        guard isActive, step == .chooseAibo, choosePhase == .petdexInput else { return }
        let input = petdexURL.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !input.isEmpty, !AiboLibraryStore.shared.isInstalling else { return }
        errorMessage = nil
        if let record = await AiboLibraryStore.shared.installPetdex(from: input) {
            guard isChoosingAibo else { return }
            presentNaming(
                preferredName: record.displayName,
                recordID: record.id,
                isPendingPack: false
            )
        } else {
            guard isChoosingAibo else { return }
            errorMessage = AiboLibraryStore.shared.lastErrorMessage
            refreshPresentation()
        }
    }

    func saveImportedName() async {
        guard isActive, step == .chooseAibo, choosePhase == .naming else { return }
        guard let name = AiboLibraryNaming.normalizedDisplayName(namingDraft) else { return }
        let library = AiboLibraryStore.shared
        if namingIsPendingPack {
            await library.confirmPendingNamedImport(displayName: name)
            guard isActive, step == .chooseAibo, choosePhase == .naming else { return }
            if let message = library.lastErrorMessage {
                errorMessage = message
                refreshPresentation()
                return
            }
            applyNamingLayout(to: library)
            tourCompanionName = name
            advance()
            return
        }
        guard let id = namingRecordID else {
            applyNamingLayout(to: library)
            tourCompanionName = name
            advance()
            return
        }
        switch library.rename(id: id, to: name) {
        case .renamed, .unchanged:
            applyNamingLayout(to: library)
            tourCompanionName = name
            advance()
        case .nameTaken(_, let suggested):
            namingDraft = suggested
            errorMessage = String(localized: "That name is already used.")
            refreshPresentation()
        }
    }

    func openPetdexSite() {
        NSWorkspace.shared.open(Self.petdexSiteURL)
    }

    /// If the user quits mid-replay, put the aibo back before position is persisted.
    func restorePositionIfNeeded() {
        guard isActive else { return }
        restoreReplayAppearanceIfNeeded()
        applyRestorePositionIfNeeded()
    }

    private func importPickedFile(_ url: URL) async {
        guard isChoosingAibo else { return }
        let accessed = url.startAccessingSecurityScopedResource()
        defer {
            if accessed { url.stopAccessingSecurityScopedResource() }
        }
        errorMessage = nil
        await AiboLibraryStore.shared.importLocal(from: url)
        guard isChoosingAibo else {
            AiboLibraryStore.shared.cancelPendingNamedImport()
            return
        }
        let library = AiboLibraryStore.shared
        if let pending = library.pendingNamedImport {
            presentNaming(
                preferredName: pending.suggestedDisplayName,
                recordID: nil,
                isPendingPack: true
            )
            return
        }
        if let message = library.lastErrorMessage {
            errorMessage = message
            refreshPresentation()
            return
        }
        let record = library.selectedRecord
        presentNaming(
            preferredName: record.displayName,
            recordID: record.id,
            isPendingPack: false
        )
    }

    private func presentNaming(preferredName: String, recordID: String?, isPendingPack: Bool) {
        guard isChoosingAibo else { return }
        let library = AiboLibraryStore.shared
        namingIsPendingPack = isPendingPack
        namingRecordID = recordID
        namingScalePercent = isPendingPack
            ? AiboLibraryRecord.defaultScalePercent
            : library.selectedRecord.scalePercent
        namingBubbleDistance = AiboLibraryRecord.defaultBubbleDistance
        if isPendingPack {
            namingDraft = library.pendingNamedImport?.suggestedDisplayName ?? preferredName
        } else {
            namingDraft = AiboLibraryNaming.uniqueDisplayName(
                preferredName,
                in: library.records,
                excludingID: recordID
            )
            library.setBubbleDistance(namingBubbleDistance)
        }
        errorMessage = nil
        choosePhase = .naming
        tourCompanionName = AiboLibraryNaming.normalizedDisplayName(namingDraft)
            ?? namingDraft
        refreshPresentation()
    }

    private func begin() {
        step = .welcome
        tourCompanionName = nil
        resetChooseAiboState()
        isActive = true
        AiboRuntime.shared.reloadPresentedBubbles()
        if AiboPanelController.shared.playOnboardingEntrance() {
            AiboPanelController.shared.updateOnboardingKeyWindow()
        } else {
            AiboPanelController.shared.syncGeometryNow()
            AiboPanelController.shared.updateOnboardingKeyWindow()
        }
    }

    private func finish() {
        guard isActive else { return }
        isActive = false
        step = .welcome
        AiboLibraryStore.shared.cancelPendingNamedImport()
        tourCompanionName = nil
        resetChooseAiboState()
        Self.markCompleted()
        restoreReplayAppearanceIfNeeded()
        applyRestorePositionIfNeeded()
        restoreXPercent = nil
        restoreYPercent = nil
        refreshPresentation()
    }

    private func resetChooseAiboState() {
        choosePhase = .options
        petdexURL = ""
        namingDraft = ""
        namingScalePercent = AiboLibraryRecord.defaultScalePercent
        namingBubbleDistance = AiboLibraryRecord.defaultBubbleDistance
        namingRecordID = nil
        namingIsPendingPack = false
        errorMessage = nil
    }

    private func applyNamingLayout(to library: AiboLibraryStore) {
        library.setScalePercent(namingScalePercent)
        library.setBubbleDistance(namingBubbleDistance)
    }

    private func refreshPresentation() {
        AiboRuntime.shared.reloadPresentedBubbles()
        AiboPanelController.shared.syncGeometryNow()
        AiboPanelController.shared.updateOnboardingKeyWindow()
    }

    private func restoreReplayAppearanceIfNeeded() {
        guard let snapshot = replaySnapshot else { return }
        replaySnapshot = nil
        AiboLibraryStore.shared.restoreOnboardingReplaySnapshot(snapshot)
        AiboPanelController.shared.syncGeometryNow()
    }

    private func applyRestorePositionIfNeeded() {
        guard let x = restoreXPercent, let y = restoreYPercent else { return }
        AiboPanelController.shared.placeAiboAtRelativePosition(xPercent: x, yPercent: y)
    }

    private static var storedCompleted: Bool? {
        guard UserDefaults.standard.object(forKey: completedKey) != nil else { return nil }
        return UserDefaults.standard.bool(forKey: completedKey)
    }

    private static func markCompleted() {
        UserDefaults.standard.set(true, forKey: completedKey)
    }

    /// Signals that this Mac already ran aibo before the tour existed.
    /// Must be evaluated before `AiboLibraryStore` writes migration flags.
    private static func hasExistingInstallEvidence() -> Bool {
        if FileManager.default.fileExists(atPath: AiboPaths.libraryURL.path) {
            return true
        }
        let defaults = UserDefaults.standard
        let keys = [
            "settings.aiboPositionXPercent",
            "settings.themeMode",
            "settings.migratedBubbleLayoutToLibrary",
            "settings.migratedAiboScaleToLibrary",
            "settings.webhookEnabled",
            "settings.publicWebhookURL",
        ]
        return keys.contains { defaults.object(forKey: $0) != nil }
    }
}
