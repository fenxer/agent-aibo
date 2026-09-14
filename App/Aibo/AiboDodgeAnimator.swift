import AiboCore
import AppKit
import QuartzCore

/// Short-lived screen display link for one dodge hop. Stopped the moment
/// the ease finishes or the caller cancels — not a resident timer.
@MainActor
final class AiboDodgeAnimator {
    private let tickProxy = TickProxy()
    private var displayLink: CADisplayLink?
    private var startedAt: CFTimeInterval = 0
    private var duration: TimeInterval = 0
    private var onProgress: ((Double) -> Void)?
    private var onCompleted: (() -> Void)?

    private final class TickProxy: NSObject {
        weak var owner: AiboDodgeAnimator?
        @objc func tick(_ link: CADisplayLink) {
            owner?.handleTick()
        }
    }

    init() {
        tickProxy.owner = self
    }

    deinit {
        displayLink?.invalidate()
    }

    var isRunning: Bool { displayLink != nil }

    func start(
        screen: NSScreen?,
        duration: TimeInterval,
        onProgress: @escaping (Double) -> Void,
        onCompleted: @escaping () -> Void
    ) {
        cancel()
        self.duration = max(duration, 0)
        self.onProgress = onProgress
        self.onCompleted = onCompleted
        startedAt = CACurrentMediaTime()
        onProgress(0)
        if self.duration == 0 {
            finish()
            return
        }
        let link = screen?.displayLink(
            target: tickProxy,
            selector: #selector(TickProxy.tick(_:))
        )
        guard let link else {
            finish()
            return
        }
        link.add(to: .main, forMode: .common)
        displayLink = link
    }

    func cancel() {
        displayLink?.invalidate()
        displayLink = nil
        onProgress = nil
        onCompleted = nil
    }

    private func handleTick() {
        let elapsed = CACurrentMediaTime() - startedAt
        let progress = MouseShakeDodge.easedProgress(elapsed: elapsed, duration: duration)
        onProgress?(progress)
        guard elapsed >= duration else { return }
        finish()
    }

    private func finish() {
        displayLink?.invalidate()
        displayLink = nil
        let completed = onCompleted
        onProgress = nil
        onCompleted = nil
        completed?()
    }
}
