//
//  DisplayLinkAnimationView.swift
//  demo
//

import UIKit

/// Base for the UIKit / Core Animation implementations.
///
/// Subclasses that update layers every frame override `renderFrame(time:deltaTime:)`; the time spent
/// there is reported as main-thread CPU work. Effects driven purely by Core Animation
/// (render-server animations, emitters) return `false` from `usesDisplayLink`.
class DisplayLinkAnimationView: UIView, BenchmarkableAnimationView {
    var progress: Float = 0 {
        didSet {
            progress = min(max(progress, 0), 1)
            progressDidChange()
        }
    }
    var workRecorder: FrameWorkRecorder?
    var textureMemoryBytes: Int { 0 }
    var usesDisplayLink: Bool { true }

    /// Eased towards `progress` every frame (display-link effects only).
    private(set) var displayedProgress: Float = 0
    private(set) var touch = TouchInput()
    private(set) var isAnimating = false

    private var displayLink: CADisplayLink?
    private var startTime = CACurrentMediaTime()
    private var lastTimestamp: CFTimeInterval = 0

    var elapsedTime: CFTimeInterval { CACurrentMediaTime() - startTime }

    override init(frame: CGRect) {
        super.init(frame: frame)
        setUp()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        setUp()
    }

    // MARK: - Subclass hooks

    func setUp() {}
    func didStartAnimation() {}
    func didStopAnimation() {}
    func progressDidChange() {}
    func touchDidChange() {}
    func renderFrame(time: CFTimeInterval, deltaTime: CFTimeInterval) {}

    // MARK: - Animation

    func startAnimation() {
        guard !isAnimating else { return }
        isAnimating = true
        startTime = CACurrentMediaTime()
        lastTimestamp = startTime
        if usesDisplayLink {
            let link = CADisplayLink(target: self, selector: #selector(step(_:)))
            link.preferredFrameRateRange = CAFrameRateRange(minimum: 60, maximum: 120, preferred: 120)
            link.add(to: .main, forMode: .common)
            displayLink = link
        }
        didStartAnimation()
    }

    func stopAnimation() {
        guard isAnimating else { return }
        isAnimating = false
        displayLink?.invalidate()
        displayLink = nil
        didStopAnimation()
    }

    override func didMoveToWindow() {
        super.didMoveToWindow()
        if window == nil {
            stopAnimation()
        }
    }

    @objc private func step(_ link: CADisplayLink) {
        let workStart = CACurrentMediaTime()
        let dt = min(link.timestamp - lastTimestamp, 0.1)
        lastTimestamp = link.timestamp
        displayedProgress = eased(displayedProgress, toward: progress, deltaTime: dt)
        touch.advance(deltaTime: dt)
        renderFrame(time: link.timestamp - startTime, deltaTime: dt)
        workRecorder?.recordCPU(CACurrentMediaTime() - workStart)
    }

    // MARK: - Touches

    override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent?) {
        touch.track(touches, in: self, isActive: true)
        touchDidChange()
    }

    override func touchesMoved(_ touches: Set<UITouch>, with event: UIEvent?) {
        touch.track(touches, in: self, isActive: true)
        touchDidChange()
    }

    override func touchesEnded(_ touches: Set<UITouch>, with event: UIEvent?) {
        touch.track(touches, in: self, isActive: false)
        touchDidChange()
    }

    override func touchesCancelled(_ touches: Set<UITouch>, with event: UIEvent?) {
        touch.track(touches, in: self, isActive: false)
        touchDidChange()
    }
}
