//
//  MetalTransitionDelegate.swift
//  controller
//
//  Wires MetalTransitionAnimator into modal presentation and UINavigationController,
//  plus an edge-swipe interactive back gesture.
//

import UIKit

/// Use as `transitioningDelegate` (modal) and/or `navigationController.delegate` (push / pop).
/// Both of those properties are weak, so keep a strong reference to this object.
final class MetalTransitionDelegate: NSObject, UIViewControllerTransitioningDelegate, UINavigationControllerDelegate {
    var effect: MetalTransitionEffect {
        didSet { MetalTransitionRenderer.shared?.prewarm([effect]) }
    }
    /// Clamped to 0.4…0.8 s; `nil` uses the effect's default.
    var duration: TimeInterval?
    /// Where the effect originates, in window coordinates. Set it right before presenting.
    var touchPoint: CGPoint?
    let interaction = MetalInteractiveTransition()

    init(effect: MetalTransitionEffect = .rippleDissolve) {
        self.effect = effect
        super.init()
        MetalTransitionRenderer.shared?.prewarm([effect])
    }

    private func animator(_ operation: MetalTransitionAnimator.Operation) -> MetalTransitionAnimator {
        MetalTransitionAnimator(effect: effect, operation: operation, duration: duration, touchPoint: touchPoint)
    }

    // MARK: UIViewControllerTransitioningDelegate

    func animationController(forPresented presented: UIViewController, presenting: UIViewController,
                             source: UIViewController) -> UIViewControllerAnimatedTransitioning? {
        animator(.present)
    }

    func animationController(forDismissed dismissed: UIViewController) -> UIViewControllerAnimatedTransitioning? {
        animator(.dismiss)
    }

    func interactionControllerForDismissal(using animator: UIViewControllerAnimatedTransitioning)
        -> UIViewControllerInteractiveTransitioning? {
        interaction.isInteracting ? interaction : nil
    }

    // MARK: UINavigationControllerDelegate

    func navigationController(_ navigationController: UINavigationController,
                              animationControllerFor operation: UINavigationController.Operation,
                              from fromVC: UIViewController,
                              to toVC: UIViewController) -> UIViewControllerAnimatedTransitioning? {
        switch operation {
        case .push: animator(.push)
        case .pop: animator(.pop)
        default: nil
        }
    }

    func navigationController(_ navigationController: UINavigationController,
                              interactionControllerFor animationController: UIViewControllerAnimatedTransitioning)
        -> UIViewControllerInteractiveTransitioning? {
        interaction.isInteracting ? interaction : nil
    }
}

/// Swipe-from-left-edge back gesture. Progress is fed through UIPercentDrivenInteractiveTransition,
/// which pauses the transition container; the Metal renderer reads that paused timeline every frame.
final class MetalInteractiveTransition: UIPercentDrivenInteractiveTransition {
    private(set) var isInteracting = false
    /// Called when the swipe starts with its location in window coordinates: pop or dismiss here.
    var onBegan: ((CGPoint) -> Void)?

    override init() {
        super.init()
        completionCurve = .easeOut
    }

    @discardableResult
    func attach(to view: UIView) -> UIScreenEdgePanGestureRecognizer {
        let gesture = UIScreenEdgePanGestureRecognizer(target: self, action: #selector(handlePan(_:)))
        gesture.edges = .left
        view.addGestureRecognizer(gesture)
        return gesture
    }

    @objc private func handlePan(_ gesture: UIScreenEdgePanGestureRecognizer) {
        guard let view = gesture.view else { return }
        let progress = min(max(gesture.translation(in: view).x / max(view.bounds.width, 1), 0), 1)

        switch gesture.state {
        case .began:
            isInteracting = true
            onBegan?(gesture.location(in: nil))
        case .changed:
            update(progress)
        case .ended:
            isInteracting = false
            if progress > 0.4 || gesture.velocity(in: view).x > 700 {
                finish()
            } else {
                cancel()
            }
        case .cancelled, .failed:
            isInteracting = false
            cancel()
        default:
            break
        }
    }
}
