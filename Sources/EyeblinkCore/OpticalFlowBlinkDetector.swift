import Foundation

/// Recovered temporal features, independent of the image/optical-flow backend.
/// See docs/recovered-rules.md, Model::detectBlink / Model::mergeBlinks.
/// The app must supply Farneback-equivalent features before claiming detector parity.
public struct EyeMotionFrame: Equatable, Sendable {
    public var time: TimeInterval
    public var meanY: Double
    public var standardDeviation: Double
    public var frameIndex: Int?
    public var frameInterval: TimeInterval?
    public init(time: TimeInterval, meanY: Double, standardDeviation: Double, frameIndex: Int? = nil, frameInterval: TimeInterval? = nil) {
        self.time = time; self.meanY = meanY; self.standardDeviation = standardDeviation
        self.frameIndex = frameIndex
        self.frameInterval = frameInterval
    }
}
public struct EyeMotionCandidate: Equatable, Sendable {
    public var start: TimeInterval
    public var end: TimeInterval
    public var duration: TimeInterval
    public var accumulatedDeviation: Double
    public var startFrame: Int?
    public var endFrame: Int?
    public init(start: TimeInterval, end: TimeInterval, duration: TimeInterval, accumulatedDeviation: Double = 0, startFrame: Int? = nil, endFrame: Int? = nil) {
        self.start = start; self.end = end; self.duration = duration; self.accumulatedDeviation = accumulatedDeviation
        self.startFrame = startFrame; self.endFrame = endFrame
    }
}
public struct OpticalFlowBlinkConfiguration: Equatable, Sendable {
    public var motionThreshold = 0.0025
    public var accumulatedDeviationThreshold = 0.0075
    public var minimumDuration: TimeInterval = 0.1
    public var maximumDuration: TimeInterval = 0.5
    public var overlapThreshold = 0.3
    public init() {}
}

public struct OpticalFlowBlinkDetector: Sendable {
    public var configuration: OpticalFlowBlinkConfiguration
    // Model's constructor seeds its prior blink with frames 0/0 and 0.25s.
    // Camera-open scanner resets deliberately leave that prior blink intact.
    private static let initialCandidate = EyeMotionCandidate(start: 0, end: 0, duration: 0.25, startFrame: 0, endFrame: 0)
    private var previousCandidate: EyeMotionCandidate = initialCandidate
    public init(configuration: OpticalFlowBlinkConfiguration = .init()) { self.configuration = configuration }
    public mutating func reset() { previousCandidate = Self.initialCandidate }

    /// Batch adapter for fixtures; production keeps the same scanner state across
    /// frames instead of rescanning the complete history.
    public func candidates(in frames: [EyeMotionFrame]) -> [EyeMotionCandidate] {
        var scanner = EyeMotionScanner()
        return scanner.scan(through: frames.count - 1, configuration: configuration) { frames[$0] }
    }

    /// The source compares consecutive eye candidates with this particular ratio,
    /// then unconditionally replaces previous. Do not substitute ordinary IoU.
    public mutating func merge(_ current: EyeMotionCandidate) -> TimeInterval? {
        defer { previousCandidate = current }
        let previous = previousCandidate
        let previousStart = previous.startFrame.map(Double.init) ?? previous.start
        let previousEnd = previous.endFrame.map(Double.init) ?? previous.end
        let currentStart = current.startFrame.map(Double.init) ?? current.start
        let currentEnd = current.endFrame.map(Double.init) ?? current.end
        let denominator = currentEnd - previousStart
        let ratio = (previousEnd - currentStart) / denominator
        // The actual shipped function accepts ratios BELOW 0.3, including
        // disjoint candidates. Its jbe skips equal/greater/unordered values.
        guard ratio < configuration.overlapThreshold else { return nil }
        return (previous.duration + current.duration) * 0.5
    }

}

/// The left/right Model scanner blocks at 0x100141e3d and 0x10014210b.
/// Cursor/start indices are absolute; only the feature storage wraps at 10000.
/// Ordered comparisons intentionally preserve the original NaN fall-through.
struct EyeMotionScanner: Sendable {
    private(set) var cursor = 1
    private var phase = 0
    private var startIndex = 0
    private var duration: TimeInterval = 0
    private var accumulated: Double = 0

    mutating func scan(through latest: Int, configuration: OpticalFlowBlinkConfiguration,
                       frameAt: (Int) -> EyeMotionFrame) -> [EyeMotionCandidate] {
        var result: [EyeMotionCandidate] = []
        let a = configuration.motionThreshold, b = configuration.accumulatedDeviationThreshold
        while cursor <= latest {
            if phase != 0 && duration > configuration.maximumDuration {
                phase = 0; cursor = startIndex + 2; continue
            }
            let frame = frameAt(cursor), previous = frameAt(cursor - 1)
            let dt = frame.frameInterval ?? (frame.time - previous.time)
            switch phase {
            case 0:
                if frame.meanY > a && frame.standardDeviation > a {
                    phase = 1; startIndex = cursor - 1
                    accumulated = frame.standardDeviation; duration = dt
                }
            case 1:
                if frame.meanY < -a && frame.standardDeviation > a && accumulated > b {
                    phase = 2; accumulated = frame.standardDeviation; duration += dt
                } else if frame.meanY > -a && frame.standardDeviation > a {
                    accumulated += frame.standardDeviation; duration += dt
                } else if frame.meanY < -a && frame.standardDeviation > a {
                    phase = 0; cursor = startIndex + 2; continue
                } else { duration += dt }
            case 2:
                if frame.meanY < a && frame.standardDeviation > a {
                    accumulated += frame.standardDeviation; duration += dt
                } else if accumulated > b && duration > configuration.minimumDuration {
                    let start = frameAt(startIndex)
                    result.append(.init(start: start.time, end: previous.time, duration: duration,
                        accumulatedDeviation: accumulated,
                        startFrame: startIndex, endFrame: cursor - 1))
                    phase = 0
                } else if frame.meanY > a && frame.standardDeviation > a {
                    phase = 0; cursor = startIndex + 2; continue
                } else { duration += dt }
            default: break
            }
            cursor += 1
        }
        return result
    }
}
