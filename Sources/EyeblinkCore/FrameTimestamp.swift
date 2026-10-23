import Foundation

/// Raw monotonic clock sample. Duration math must retain the integer ticks;
/// uptime seconds are for the scheduler/observation boundary only.
public struct FrameTimestamp: Equatable, Sendable {
    public let ticks: Int64
    public let frequency: Double

    public init(ticks: Int64, frequency: Double) {
        self.ticks = ticks; self.frequency = frequency
    }

    public var isValid: Bool { ticks >= 0 && frequency.isFinite && frequency > 0 }
    public var uptime: TimeInterval { Double(ticks) / frequency }

    public func interval(since previous: Self) -> TimeInterval? {
        guard isValid, previous.isValid, frequency == previous.frequency, ticks > previous.ticks else { return nil }
        return Double(ticks - previous.ticks) / frequency
    }
}
