//
//  MetalLabEffectView.swift
//  demo
//

import UIKit

/// An effect shown on one of the lab tabs (Metal Lab, GPU Compute, GPU Worlds).
protocol MetalLabEffectView: BenchmarkableAnimationView {
    /// Shown as "Active entities" in the profiler overlay, e.g. "250 000 particles".
    var activeEntityDescription: String { get }
    /// Optional workload metric for the overlay, e.g. "120 GFLOPS".
    var throughputDescription: String? { get }
    /// Mode-specific controls the lab controller shows under the effect.
    var controls: [LabControl] { get }
}

extension MetalLabEffectView {
    var throughputDescription: String? { nil }
    var controls: [LabControl] { [] }
}

/// A control a lab effect asks its controller to show. Handlers run on the main thread.
enum LabControl {
    case slider(
        title: String,
        range: ClosedRange<Float>,
        value: Float,
        isLogarithmic: Bool = false,
        format: (Float) -> String,
        onChange: (Float) -> Void
    )
    case segments(items: [String], selected: Int, onChange: (Int) -> Void)
    case button(title: String, action: () -> Void)
}

/// Formats large counts compactly: 950, 12.5k, 3.2M, 1.4B.
func compactCount(_ value: Double) -> String {
    switch value {
    case 1e9...: String(format: "%.1fB", value / 1e9)
    case 1e6...: String(format: "%.1fM", value / 1e6)
    case 1e3...: String(format: "%.1fk", value / 1e3)
    default: String(format: "%.0f", value)
    }
}
