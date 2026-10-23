import Foundation

/// Mirrors the original once-per-minute cursor/key-counter activity observation.
/// Movement away and back between samples is intentionally not inferred.
public struct SampledIdleTracker: Sendable {
    private var lastSample: TimeInterval
    private var lastActivity: TimeInterval
    private var cursor: CGPoint
    private var keyCount: UInt32
    public let samplingInterval: TimeInterval
    public init(now: TimeInterval, cursor: CGPoint, keyCount: UInt32, samplingInterval: TimeInterval = 60) {
        lastSample = now; lastActivity = now; self.cursor = cursor; self.keyCount = keyCount
        self.samplingInterval = samplingInterval
    }
    public mutating func observe(at now: TimeInterval, cursor: CGPoint, keyCount: UInt32) -> TimeInterval {
        guard now.isFinite, now >= lastSample else { return 0 }
        if now - lastSample >= samplingInterval {
            if cursor.x != self.cursor.x || cursor.y != self.cursor.y || keyCount != self.keyCount { lastActivity = now }
            self.cursor = cursor; self.keyCount = keyCount; lastSample = now
        }
        return max(0, now - lastActivity)
    }
}
