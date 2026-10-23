import Foundation

/// Model's fixed feature rings and independent persistent left/right scanners.
/// A suspended scanner catches up from its cursor when a previous face returns.
public struct OpticalFlowStream: Sendable {
    private static let capacity = 10_000
    private static let zero = EyeMotionFrame(time: 0, meanY: 0, standardDeviation: 0)
    private var left = Array(repeating: zero, count: capacity)
    private var right = Array(repeating: zero, count: capacity)
    private var leftScanner = EyeMotionScanner()
    private var rightScanner = EyeMotionScanner()
    private var merger = OpticalFlowBlinkDetector()
    private var frameIndex = 0
    private var previousTime: TimeInterval?
    public init() {}

    public mutating func reset() {
        leftScanner = EyeMotionScanner(); rightScanner = EyeMotionScanner()
        // Original scanner reset leaves both the feature storage and prior merge
        // candidate in place. New-session samples overwrite their ring slots.
        frameIndex = 0; previousTime = nil
    }

    public mutating func process(at time: TimeInterval, leftMean: Double, leftDeviation: Double, rightMean: Double, rightDeviation: Double, frameInterval: TimeInterval? = nil, scan: Bool = true) -> [TimeInterval] {
        let interval = frameInterval ?? previousTime.map { time - $0 } ?? 0
        let slot = frameIndex % Self.capacity
        left[slot] = .init(time: time, meanY: leftMean, standardDeviation: leftDeviation,
                           frameIndex: frameIndex, frameInterval: interval)
        right[slot] = .init(time: time, meanY: rightMean, standardDeviation: rightDeviation,
                            frameIndex: frameIndex, frameInterval: interval)
        let latest = frameIndex
        frameIndex += 1; previousTime = time
        // Missing previous face still writes features/intervals, but skips both
        // scanner blocks without changing their cursors or phases.
        guard scan else { return [] }
        let newLeft = leftScanner.scan(through: latest, configuration: merger.configuration) { left[$0 % Self.capacity] }
        let newRight = rightScanner.scan(through: latest, configuration: merger.configuration) { right[$0 % Self.capacity] }
        var detected: [TimeInterval] = []
        // Original drains left completely before right, including deferred work.
        for candidate in newLeft + newRight {
            if let duration = merger.merge(candidate) { detected.append(duration) }
        }
        return detected
    }
}
