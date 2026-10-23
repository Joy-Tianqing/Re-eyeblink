import Foundation

/// Original Model checks every 31 frames using the mean of the latest 31 deltas,
/// truncates FPS toward zero, and aborts non-preview work at an integer rate <= 9.
public struct FrameRateMonitor: Sendable {
    private var previous: TimeInterval?
    private var deltas: [TimeInterval] = []
    private var frames = 0
    public init() {}
    public mutating func reset() { previous = nil; deltas.removeAll(keepingCapacity: true); frames = 0 }
    public mutating func observe(at time: TimeInterval, frameInterval: TimeInterval? = nil) -> Int? {
        guard time.isFinite else { return nil }
        guard let previous else { self.previous = time; return nil }
        guard time > previous else { return nil }
        let delta = frameInterval ?? (time - previous)
        guard delta.isFinite, delta > 0 else { return nil }
        self.previous = time
        deltas.append(delta)
        if deltas.count > 31 { deltas.removeFirst() }
        frames += 1
        guard frames % 31 == 0, deltas.count == 31 else { return nil }
        // Shipped scalar order is mean=sum/31, then reciprocal=1/mean.
        // Combining these into 31/sum changes truncation at integer boundaries.
        let mean = deltas.reduce(0, +) / Double(deltas.count)
        return Int((1 / mean).rounded(.towardZero))
    }
}
