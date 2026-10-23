import Foundation

/// Raw timer used by the ordered detector before optical flow is allowed.
public struct FaceAbsenceTimer: Equatable, Sendable {
    public let startedAt: FrameTimestamp
    public init(startedAt: FrameTimestamp) { self.startedAt = startedAt }
    public func hasExpired(at timestamp: FrameTimestamp, after timeout: TimeInterval) -> Bool {
        // Original QElapsedTimer truncates to integer ms before strict >.
        guard let elapsed = timestamp.interval(since: startedAt) else { return false }
        return elapsed >= timeout + 0.001
    }
}
