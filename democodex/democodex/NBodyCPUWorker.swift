import Foundation
import simd
import QuartzCore

struct NBodyState {
    var position: SIMD4<Float>
    var velocity: SIMD4<Float>
    static func initial(_ index: Int, count: Int) -> Self {
        let radius = 0.1 + 0.85 * sqrt((Float(index) + 0.5) / Float(count))
        let angle = Float(index) * 2.3999632
        let p = SIMD4<Float>(cos(angle)*radius, sin(angle)*radius, 0, 1 / Float(count))
        return Self(position: p, velocity: SIMD4(-p.y*0.2, p.x*0.2, 0, 0))
    }
}

private final class NBodyCPUJob: @unchecked Sendable {
    let input: [NBodyState]
    let output: UnsafeMutablePointer<NBodyState>
    init(_ input: [NBodyState]) {
        self.input = input
        output = .allocate(capacity: input.count)
        output.initialize(repeating: NBodyState(position: .zero, velocity: .zero), count: input.count)
    }
    deinit { output.deinitialize(count: input.count); output.deallocate() }
}

/// A single background job, parallelized across cores. Generation changes cancel old work.
/// No main-thread wait; only complete steps become visible to the renderer.
final class NBodyCPUWorker: @unchecked Sendable {
    struct Result { let states: [NBodyState]; let seconds: Double; let step: Int }
    private let lock = NSLock()
    private var generation = 0
    private var running = false
    private var state: [NBodyState] = []
    private var result: Result?
    private var step = 0

    func reset(count: Int) {
        lock.lock(); defer { lock.unlock() }
        generation += 1; step = 0; result = nil
        state = (0..<count).map { NBodyState.initial($0, count: count) }
    }
    func cancel() { lock.lock(); generation += 1; result = nil; lock.unlock() }
    func takeResult() -> Result? { lock.lock(); defer { lock.unlock() }; defer { result = nil }; return result }
    private func cancelled(_ token: Int) -> Bool { lock.lock(); defer { lock.unlock() }; return token != generation }
    func requestStep() {
        lock.lock()
        guard !running, !state.isEmpty else { lock.unlock(); return }
        running = true
        let token = generation, input = state
        lock.unlock()
        DispatchQueue.global(qos: .userInitiated).async { [self] in
            let job = NBodyCPUJob(input), count = input.count
            let chunks = min(ProcessInfo.processInfo.activeProcessorCount, max(1, count / 128))
            let start = CACurrentMediaTime()
            DispatchQueue.concurrentPerform(iterations: chunks) { chunk in
                let lower = chunk*count/chunks, upper = (chunk+1)*count/chunks
                for i in lower..<upper {
                    if cancelled(token) { break }
                    let body = job.input[i]
                    var ax: Float = 0, ay: Float = 0, az: Float = 0
                    for j in stride(from: 0, to: count, by: 4) {
                        let a = job.input[j].position, b = job.input[min(j+1,count-1)].position
                        let c = job.input[min(j+2,count-1)].position, d = job.input[min(j+3,count-1)].position
                        let dx = SIMD4(a.x,b.x,c.x,d.x) - SIMD4(repeating: body.position.x)
                        let dy = SIMD4(a.y,b.y,c.y,d.y) - SIMD4(repeating: body.position.y)
                        let dz = SIMD4(a.z,b.z,c.z,d.z) - SIMD4(repeating: body.position.z)
                        let squaredXY: SIMD4<Float> = dx*dx + dy*dy
                        let squared: SIMD4<Float> = squaredXY + dz*dz + SIMD4<Float>(repeating: 0.002)
                        let inv: SIMD4<Float> = simd.rsqrt(squared)
                        let inverseCubed: SIMD4<Float> = (inv*inv)*inv
                        let scale: SIMD4<Float> = inverseCubed * SIMD4<Float>(repeating: 1 / Float(count))
                        ax += simd_reduce_add(dx*scale); ay += simd_reduce_add(dy*scale); az += simd_reduce_add(dz*scale)
                    }
                    var velocity = body.velocity
                    velocity += SIMD4(ax,ay,az,0) * (1 / 120)
                    velocity *= 0.999
                    var position = body.position + velocity * (1 / 120)
                    position.w = body.position.w
                    job.output[i] = NBodyState(position: position, velocity: velocity)
                }
            }
            let seconds = CACurrentMediaTime() - start
            lock.lock()
            running = false
            if token == generation {
                state = Array(UnsafeBufferPointer(start: job.output, count: count))
                step += 1
                result = Result(states: state, seconds: seconds, step: step)
            }
            lock.unlock()
        }
    }
}
