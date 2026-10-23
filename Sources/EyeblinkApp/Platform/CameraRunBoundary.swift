import Foundation
import EyeblinkCore

/// Evaluated on the ordered capture queue before consuming another image.
/// The main scheduler displays progress but cannot decide successful completion.
struct CameraRunBoundary {
    enum Decision: Equatable {
        case analyze, ignore
        case complete(FrameTimestamp)
        case trainingPrompt(FrameTimestamp), trainingComplete(FrameTimestamp)
    }
    private let measurementDuration: Double?
    private let trainingDuration: Double?
    private var startedAt: FrameTimestamp?
    private var terminated = false
    private var blinkDetected = false
    private var promptSent = false

    init(measurementDuration: Double?, trainingDuration: Double? = nil) {
        self.measurementDuration = measurementDuration
        self.trainingDuration = trainingDuration
    }

    mutating func recordBlinks(_ durations: [TimeInterval]) {
        if !durations.isEmpty { blinkDetected = true }
    }

    mutating func start(at timestamp: FrameTimestamp) throws {
        guard !terminated, timestamp.isValid else { throw CameraFrameAnalysis.AnalysisError.clock }
        // A recoverable frame-analysis invalidation can prime its image/time
        // baseline again. It must not restart the measurement's elapsed timer.
        if let startedAt {
            guard timestamp.frequency == startedAt.frequency, timestamp.ticks >= startedAt.ticks else { throw CameraFrameAnalysis.AnalysisError.clock }
            return
        }
        if let duration = measurementDuration, !duration.isFinite || duration <= 0 { throw CameraFrameAnalysis.AnalysisError.clock }
        startedAt = timestamp
    }

    mutating func nextFrame(clock: () -> FrameTimestamp) throws -> Decision {
        guard !terminated else { return .ignore }
        guard let startedAt, measurementDuration != nil || trainingDuration != nil else { return .analyze }
        let checked = clock()
        guard checked.isValid, checked.frequency == startedAt.frequency,
              checked.ticks >= startedAt.ticks else { throw CameraFrameAnalysis.AnalysisError.clock }
        let elapsed = Double(checked.ticks - startedAt.ticks) / checked.frequency
        if let trainingDuration {
            if blinkDetected {
                terminated = true
                return .trainingComplete(checked)
            }
            if !promptSent, elapsed >= trainingDuration {
                promptSent = true
                return .trainingPrompt(checked)
            }
            return .analyze
        }
        // Qt elapsed() truncates milliseconds: elapsed >= 180001ms.
        guard elapsed >= measurementDuration! + 0.001 else { return .analyze }
        terminated = true
        return .complete(checked)
    }

    /// All terminal sources share this latch on the capture queue.
    @discardableResult mutating func terminate() -> Bool {
        guard !terminated else { return false }
        terminated = true
        return true
    }
}
