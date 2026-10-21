import UIKit
import Darwin

enum LavaEngine: String, CaseIterable {
    case uiKit = "UIKit"
    case metal = "Metal"
    var other: LavaEngine { self == .uiKit ? .metal : .uiKit }
}

struct RenderBatch {
    var cpuMS: [Double] = []
    var gpuMS: [Double] = []
    var latencyMS: [Double] = []
    var completedFrames = 0
    var failedFrames = 0
    var presentedFrames = 0
    var activeEntities: Int?
}

/// Metal completion handlers run off the main thread. A small locked mailbox
/// avoids dispatching one UI task per frame and rejects completions from old modes.
final class RenderMeasurements: @unchecked Sendable {
    private let lock = NSLock()
    private var token = 0
    private var batch = RenderBatch()

    var generation: Int {
        lock.lock()
        defer { lock.unlock() }
        return token
    }

    func reset() {
        lock.lock()
        defer { lock.unlock() }
        token += 1
        batch = RenderBatch()
    }

    func recordCPU(_ milliseconds: Double, generation: Int) {
        lock.lock()
        defer { lock.unlock() }
        guard generation == token else { return }
        batch.cpuMS.append(milliseconds)
    }

    func recordCompletion(gpuMS: Double?, latencyMS: Double, generation: Int) {
        lock.lock()
        defer { lock.unlock() }
        guard generation == token else { return }
        batch.completedFrames += 1
        if let gpuMS { batch.gpuMS.append(gpuMS) }
        batch.latencyMS.append(latencyMS)
    }

    func recordFailure(generation: Int) {
        lock.lock()
        defer { lock.unlock() }
        guard generation == token else { return }
        batch.failedFrames += 1
    }

    func recordPresentation(generation: Int) {
        lock.lock()
        defer { lock.unlock() }
        guard generation == token else { return }
        batch.presentedFrames += 1
    }

    func recordActiveEntities(_ count: Int, generation: Int) {
        lock.lock()
        defer { lock.unlock() }
        guard generation == token else { return }
        batch.activeEntities = count
    }

    func drain() -> RenderBatch {
        lock.lock()
        defer { lock.unlock() }
        let result = batch
        batch = RenderBatch()
        return result
    }
}

struct PerformanceSnapshot {
    let duration: Double
    let frameIntervalsMS: [Double]
    let cpuPercent: Double?
    let render: RenderBatch
    let thermalState: Int
    let lowPowerMode: Bool

    var fps: Double { frameIntervalsMS.isEmpty ? 0 : 1_000 / frameIntervalsMS.mean }
    var frameMS: Double { frameIntervalsMS.mean }
    var p95MS: Double { frameIntervalsMS.percentile95 }
    var completedFPS: Double { Double(render.completedFrames) / duration }
}

extension Array where Element == Double {
    var mean: Double { isEmpty ? 0 : reduce(0, +) / Double(count) }
    var percentile95: Double {
        guard !isEmpty else { return 0 }
        let sorted = sorted()
        return sorted[Swift.max(0, Int(ceil(Double(count) * 0.95)) - 1)]
    }
}

@MainActor
private final class DisplayLinkTarget: NSObject {
    weak var owner: PerformanceProfiler?
    @objc func tick(_ link: CADisplayLink) { owner?.tick(link) }
}

@MainActor
final class PerformanceProfiler {
    enum CPUScope { case process, mainThread }
    let cpuScope: CPUScope
    var onFrame: ((CFTimeInterval) -> Void)?
    var onSnapshot: ((PerformanceSnapshot) -> Void)?
    var measurements = RenderMeasurements()
    var targetFPS = 60 { didSet { configureRate() } }

    private let target = DisplayLinkTarget()
    private var displayLink: CADisplayLink?
    private var previousTimestamp: Double?
    private var intervals: [Double] = []
    private var windowStart = CACurrentMediaTime()
    private var previousCPU: Double?
    private let origin = CACurrentMediaTime()

    init(cpuScope: CPUScope = .process) {
        self.cpuScope = cpuScope
        target.owner = self
    }

    func start() {
        guard displayLink == nil else { return }
        reset()
        let link = CADisplayLink(target: target, selector: #selector(DisplayLinkTarget.tick(_:)))
        displayLink = link
        configureRate()
        link.add(to: .main, forMode: .common)
    }

    func stop() {
        displayLink?.invalidate()
        displayLink = nil
        reset()
    }

    func reset() {
        previousTimestamp = nil
        intervals.removeAll(keepingCapacity: true)
        windowStart = CACurrentMediaTime()
        previousCPU = cpuSeconds()
        measurements.reset()
    }

    private func configureRate() {
        let rate = Float(targetFPS)
        displayLink?.preferredFrameRateRange = CAFrameRateRange(minimum: rate, maximum: rate, preferred: rate)
    }

    fileprivate func tick(_ link: CADisplayLink) {
        if let previousTimestamp, link.timestamp > previousTimestamp {
            intervals.append((link.timestamp - previousTimestamp) * 1_000)
        }
        previousTimestamp = link.timestamp
        onFrame?(link.targetTimestamp - origin)

        let now = CACurrentMediaTime()
        let elapsed = now - windowStart
        guard elapsed >= 0.5 else { return }
        let cpuNow = cpuSeconds()
        let cpuPercent: Double?
        if let cpuNow, let previousCPU {
            cpuPercent = max(0, cpuNow - previousCPU) / elapsed * 100
        } else {
            cpuPercent = nil
        }
        let snapshot = PerformanceSnapshot(duration: elapsed, frameIntervalsMS: intervals,
                                           cpuPercent: cpuPercent, render: measurements.drain(),
                                           thermalState: ProcessInfo.processInfo.thermalState.rawValue,
                                           lowPowerMode: ProcessInfo.processInfo.isLowPowerModeEnabled)
        // Advance the window before callbacks: a callback can switch/reset modes.
        windowStart = now
        previousCPU = cpuNow
        intervals.removeAll(keepingCapacity: true)
        onSnapshot?(snapshot)
    }

    /// Whole-process CPU time across threads; 100% means one fully busy core.
    /// This can exceed 100% and excludes the out-of-process CA render server.
    private static func processCPUSeconds() -> Double? {
        var usage = rusage()
        guard getrusage(RUSAGE_SELF, &usage) == 0 else { return nil }
        return Double(usage.ru_utime.tv_sec) + Double(usage.ru_utime.tv_usec) / 1_000_000
             + Double(usage.ru_stime.tv_sec) + Double(usage.ru_stime.tv_usec) / 1_000_000
    }

    func cpuSeconds() -> Double? {
        switch cpuScope {
        case .process: return Self.processCPUSeconds()
        case .mainThread:
            // The profiler is MainActor-isolated, so this port is the main thread.
            let thread = mach_thread_self()
            defer { mach_port_deallocate(mach_task_self_, thread) }
            var info = thread_basic_info_data_t()
            var count = mach_msg_type_number_t(MemoryLayout<thread_basic_info_data_t>.size / MemoryLayout<integer_t>.size)
            let result = withUnsafeMutablePointer(to: &info) { pointer in
                pointer.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                    thread_info(thread, thread_flavor_t(THREAD_BASIC_INFO), $0, &count)
                }
            }
            guard result == KERN_SUCCESS else { return nil }
            return Double(info.user_time.seconds + info.system_time.seconds)
                + Double(info.user_time.microseconds + info.system_time.microseconds) / 1_000_000
        }
    }
}
