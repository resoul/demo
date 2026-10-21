//
//  PerformanceMonitor.swift
//  demo
//

import QuartzCore
import Darwin
import os

/// Thread-safe accumulator. Views report CPU work from the main thread and
/// GPU time from Metal completion handlers (background thread).
nonisolated final class FrameWorkRecorder: Sendable {
    struct Totals {
        var cpuSeconds: Double = 0
        var gpuSeconds: Double = 0
        var gpuSamples: Int = 0
        /// One per `recordCPU`, i.e. per frame a view actually prepared.
        var frames: Int = 0
    }

    private let state = OSAllocatedUnfairLock(initialState: Totals())

    func recordCPU(_ seconds: Double) {
        state.withLock {
            $0.cpuSeconds += seconds
            $0.frames += 1
        }
    }

    func recordGPU(_ seconds: Double) {
        guard seconds > 0 else { return }
        state.withLock {
            $0.gpuSeconds += seconds
            $0.gpuSamples += 1
        }
    }

    func drain() -> Totals {
        state.withLock {
            let totals = $0
            $0 = Totals()
            return totals
        }
    }
}

/// Samples FPS, frame interval, per-frame work and process CPU usage on a CADisplayLink.
final class PerformanceMonitor {
    struct Snapshot {
        /// Display refresh delivered to the main thread.
        var fps: Double
        /// Frames the recording views actually rendered, summed over all of them.
        var renderedFPS: Double
        var frameIntervalMs: Double
        /// CPU time the bars spent preparing a frame (layer updates / command encoding).
        var cpuWorkMs: Double
        /// GPU execution time per frame; nil when nothing was rendered with Metal.
        var gpuWorkMs: Double?
        /// Process CPU usage, 100% = one fully loaded core.
        var cpuUsagePercent: Double
        /// Share of wall time the main thread spent on the CPU.
        var mainThreadCPUPercent: Double
    }

    let recorder = FrameWorkRecorder()
    var onUpdate: ((Snapshot) -> Void)?

    private let sampleWindow: CFTimeInterval = 0.5
    private var displayLink: CADisplayLink?
    private var frames = 0
    private var windowStart: CFTimeInterval = 0
    private var cpuTimeAtWindowStart: Double = 0
    private var mainThread: thread_act_t = 0
    private var mainThreadTimeAtWindowStart: Double = 0

    func start() {
        guard displayLink == nil else { return }
        let link = CADisplayLink(target: self, selector: #selector(tick(_:)))
        link.preferredFrameRateRange = CAFrameRateRange(minimum: 60, maximum: 120, preferred: 120)
        link.add(to: .main, forMode: .common)
        displayLink = link
        // start() runs on the main thread, so this is the main thread's port.
        mainThread = mach_thread_self()
        reset()
    }

    func stop() {
        displayLink?.invalidate()
        displayLink = nil
        if mainThread != 0 {
            mach_port_deallocate(mach_task_self_, mainThread)
            mainThread = 0
        }
    }

    /// Starts a fresh measurement window, e.g. after switching implementations.
    func reset() {
        frames = 0
        windowStart = 0
        _ = recorder.drain()
    }

    @objc private func tick(_ link: CADisplayLink) {
        let now = link.timestamp
        guard windowStart > 0 else {
            windowStart = now
            cpuTimeAtWindowStart = Self.processCPUTime()
            mainThreadTimeAtWindowStart = mainThreadCPUTime()
            _ = recorder.drain()
            return
        }
        frames += 1
        let elapsed = now - windowStart
        guard elapsed >= sampleWindow else { return }

        let cpuTime = Self.processCPUTime()
        let mainThreadTime = mainThreadCPUTime()
        let work = recorder.drain()
        let frameCount = Double(max(frames, 1))
        let snapshot = Snapshot(
            fps: Double(frames) / elapsed,
            renderedFPS: Double(work.frames) / elapsed,
            frameIntervalMs: elapsed / frameCount * 1000,
            cpuWorkMs: work.cpuSeconds / frameCount * 1000,
            gpuWorkMs: work.gpuSamples > 0 ? work.gpuSeconds / frameCount * 1000 : nil,
            cpuUsagePercent: (cpuTime - cpuTimeAtWindowStart) / elapsed * 100,
            mainThreadCPUPercent: (mainThreadTime - mainThreadTimeAtWindowStart) / elapsed * 100
        )
        frames = 0
        windowStart = now
        cpuTimeAtWindowStart = cpuTime
        mainThreadTimeAtWindowStart = mainThreadTime
        onUpdate?(snapshot)
    }

    /// User + system CPU time consumed by the main thread so far.
    private func mainThreadCPUTime() -> Double {
        guard mainThread != 0 else { return 0 }
        var info = thread_basic_info()
        var count = mach_msg_type_number_t(MemoryLayout<thread_basic_info_data_t>.size / MemoryLayout<integer_t>.size)
        let result = withUnsafeMutablePointer(to: &info) {
            $0.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                thread_info(mainThread, thread_flavor_t(THREAD_BASIC_INFO), $0, &count)
            }
        }
        guard result == KERN_SUCCESS else { return 0 }
        func seconds(_ t: time_value_t) -> Double { Double(t.seconds) + Double(t.microseconds) / 1_000_000 }
        return seconds(info.user_time) + seconds(info.system_time)
    }

    /// Total user + system CPU time of this process, including threads that already exited.
    private static func processCPUTime() -> Double {
        var usage = rusage()
        guard getrusage(RUSAGE_SELF, &usage) == 0 else { return 0 }
        func seconds(_ t: timeval) -> Double { Double(t.tv_sec) + Double(t.tv_usec) / 1_000_000 }
        return seconds(usage.ru_utime) + seconds(usage.ru_stime)
    }
}
