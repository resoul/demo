//
//  GPUCounterRing.swift
//  demo
//

import Metal
import os

/// A 32-bit counter that kernels increment with atomics and the CPU reads back once the frame's
/// command buffer completes. One buffer per frame in flight, so a reset never races a read.
final class GPUCounterRing {
    private let buffers: [MTLBuffer]
    private let latest = LatestValue()
    private var index = 0

    /// Value from the most recently completed frame.
    var value: Int { latest.current }

    init?(device: MTLDevice, framesInFlight: Int = 3) {
        let buffers = (0..<framesInFlight).compactMap { _ in
            device.makeBuffer(length: MemoryLayout<UInt32>.stride, options: .storageModeShared)
        }
        guard buffers.count == framesInFlight else { return nil }
        self.buffers = buffers
    }

    /// Zeroes this frame's counter on the GPU and schedules the read-back. Bind the returned
    /// buffer to the kernels that count.
    func next(in commandBuffer: MTLCommandBuffer) -> MTLBuffer {
        let buffer = buffers[index]
        index = (index + 1) % buffers.count
        if let blit = commandBuffer.makeBlitCommandEncoder() {
            blit.fill(buffer: buffer, range: 0..<buffer.length, value: 0)
            blit.endEncoding()
        }
        commandBuffer.addCompletedHandler(Self.reader(buffer: buffer, into: latest))
        return buffer
    }

    /// Built outside the main actor: Metal calls completion handlers on its own thread.
    private nonisolated static func reader(buffer: MTLBuffer, into latest: LatestValue) -> MTLCommandBufferHandler {
        { _ in
            latest.store(Int(buffer.contents().load(as: UInt32.self)))
        }
    }
}

nonisolated private final class LatestValue: Sendable {
    private let value = OSAllocatedUnfairLock(initialState: 0)

    var current: Int { value.withLock { $0 } }

    func store(_ newValue: Int) {
        value.withLock { $0 = newValue }
    }
}

/// Counts frames over a sliding second, for "per second" workload metrics.
struct RateMeter {
    private var timestamps: [CFTimeInterval] = []

    mutating func tick(at time: CFTimeInterval) {
        timestamps.append(time)
        timestamps.removeAll { time - $0 > 1 }
    }

    var framesPerSecond: Double {
        guard let first = timestamps.first, let last = timestamps.last, last > first else { return 0 }
        return Double(timestamps.count - 1) / (last - first)
    }
}
