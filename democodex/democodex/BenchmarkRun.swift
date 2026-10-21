import UIKit

struct BenchmarkResult {
    let engine: LavaEngine
    let samples: [PerformanceSnapshot]
    var duration: Double { samples.reduce(0) { $0 + $1.duration } }
    var intervals: [Double] { samples.flatMap(\.frameIntervalsMS) }
    var fps: Double { intervals.isEmpty ? 0 : 1_000 / intervals.mean }
    var p95MS: Double { intervals.percentile95 }
    var cpuPercent: Double? {
        let available = samples.filter { $0.cpuPercent != nil }
        let duration = available.reduce(0) { $0 + $1.duration }
        guard duration > 0 else { return nil }
        return available.reduce(0) { $0 + $1.cpuPercent! * $1.duration } / duration
    }
    var gpuMS: [Double] { samples.flatMap { $0.render.gpuMS } }
    var cpuMS: [Double] { samples.flatMap { $0.render.cpuMS } }
    var latencyMS: [Double] { samples.flatMap { $0.render.latencyMS } }
    var completedFPS: Double { Double(samples.reduce(0) { $0 + $1.render.completedFrames }) / duration }
}

/// A/B runs keep progress, dimensions and requested refresh rate fixed.
/// Warm-up windows are excluded. Each measurement lasts at least ten seconds.
final class BenchmarkRun {
    enum Event { case collecting, measurementStarted, switchEngine(LavaEngine), finished }
    let requestedFPS: Int
    let progress: Float
    let drawableSize: CGSize
    let effect: AnimationEffect
    let startedAt = Date()
    let initialThermalState = ProcessInfo.processInfo.thermalState.rawValue
    let initialLowPowerMode = ProcessInfo.processInfo.isLowPowerModeEnabled
    private(set) var engine: LavaEngine
    private(set) var isWarmingUp = true
    private(set) var phaseElapsed = 0.0
    private(set) var results: [BenchmarkResult] = []
    private var currentSamples: [PerformanceSnapshot] = []

    init(firstEngine: LavaEngine, requestedFPS: Int, progress: Float, drawableSize: CGSize,
         effect: AnimationEffect = .lava) {
        engine = firstEngine
        self.requestedFPS = requestedFPS
        self.progress = progress
        self.drawableSize = drawableSize
        self.effect = effect
    }

    var status: String {
        let limit = isWarmingUp ? 2.0 : 10.0
        return "\(engine.rawValue) · \(isWarmingUp ? "прогрев" : "замер") · \(Int(ceil(max(0, limit - phaseElapsed)))) с"
    }

    func consume(_ sample: PerformanceSnapshot) -> Event {
        phaseElapsed += sample.duration
        if isWarmingUp {
            guard phaseElapsed >= 2 else { return .collecting }
            isWarmingUp = false
            phaseElapsed = 0
            return .measurementStarted
        }
        currentSamples.append(sample)
        guard phaseElapsed >= 10 else { return .collecting }
        results.append(BenchmarkResult(engine: engine, samples: currentSamples))
        currentSamples.removeAll()
        phaseElapsed = 0
        if results.count == 2 { return .finished }
        engine = engine.other
        isWarmingUp = true
        return .switchEngine(engine)
    }

    var environmentChanged: Bool {
        results.flatMap(\.samples).contains {
            $0.thermalState != initialThermalState || $0.lowPowerMode != initialLowPowerMode
        }
    }

    @MainActor
    func csv() -> String {
        var lines = ["# FX Lab A/B benchmark",
                     "# effect,\(effect.rawValue)",
                     "# started_at,\(ISO8601DateFormatter().string(from: startedAt))",
                     "# device,\(UIDevice.current.model)",
                     "# os,\(UIDevice.current.systemVersion)",
                     "# simulator,\(Self.isSimulator)",
                     "# build,\(Self.buildConfiguration)",
                     "# requested_fps,\(requestedFPS)",
                     "# progress,\(progress)",
                     "# drawable_pixels,\(Int(drawableSize.width)),\(Int(drawableSize.height))",
                     "# initial_thermal_state,\(initialThermalState)",
                     "# initial_low_power_mode,\(initialLowPowerMode)",
                     "# environment_changed,\(environmentChanged)",
                     "# CPU percent: process user+system time; 100 percent = one core; excludes CA render server",
                     "# Display FPS: CADisplayLink cadence; not proof of on-screen presentation",
                     "# GPU: completed Metal command buffers only; unavailable for UIKit",
                     "engine,window_seconds,display_fps,mean_frame_ms,p95_frame_ms,cpu_percent,cpu_update_encode_ms,gpu_ms,completion_latency_ms,completed_fps,failed_commands,thermal_state,low_power_mode"]
        for result in results {
            for sample in result.samples {
                let fields = [result.engine.rawValue, Self.number(sample.duration), Self.number(sample.fps),
                              Self.number(sample.frameMS), Self.number(sample.p95MS), Self.number(sample.cpuPercent),
                              Self.optionalMean(sample.render.cpuMS), Self.optionalMean(sample.render.gpuMS),
                              Self.optionalMean(sample.render.latencyMS),
                              result.engine == .metal ? Self.number(sample.completedFPS) : "",
                              String(sample.render.failedFrames), String(sample.thermalState), String(sample.lowPowerMode)]
                lines.append(fields.joined(separator: ","))
            }
        }
        lines.append("\nengine,total_seconds,display_fps,p95_frame_ms,cpu_percent,cpu_update_encode_ms,gpu_ms,completion_latency_ms,completed_fps")
        for result in results {
            lines.append([result.engine.rawValue, Self.number(result.duration), Self.number(result.fps),
                          Self.number(result.p95MS), Self.number(result.cpuPercent), Self.optionalMean(result.cpuMS),
                          Self.optionalMean(result.gpuMS), Self.optionalMean(result.latencyMS),
                          result.engine == .metal ? Self.number(result.completedFPS) : ""].joined(separator: ","))
        }
        return lines.joined(separator: "\n") + "\n"
    }

    private static func number(_ value: Double?) -> String {
        guard let value else { return "" }
        return String(format: "%.4f", locale: Locale(identifier: "en_US_POSIX"), value)
    }
    private static func optionalMean(_ values: [Double]) -> String { values.isEmpty ? "" : number(values.mean) }

    static var isSimulator: Bool {
        #if targetEnvironment(simulator)
        true
        #else
        false
        #endif
    }

    static var buildConfiguration: String {
        #if DEBUG
        "Debug"
        #else
        "Release"
        #endif
    }
}
