import Foundation
import EyeblinkCore
import CEyeFlow

/// Device-independent flow-to-event stage, owned by the ordered camera queue.
/// Kept separate from AVFoundation so fixed original frame sequences can test
/// the exact production status/feature handoff without opening a camera.
struct CameraMotionAnalysis {
    private var temporal = OpticalFlowStream()

    mutating func reset() { temporal.reset() }

    mutating func process(at time: TimeInterval, status: Int32, result: EFResult, frameInterval: TimeInterval? = nil) -> (isValid: Bool, blinks: [TimeInterval]) {
        // Numeric validity remains diagnostic; each eye scanner must receive its
        // own features even when the other eye contains NaN or infinity.
        let valid = result.left.mean_y.isFinite && result.left.stddev_y.isFinite
            && result.right.mean_y.isFinite && result.right.stddev_y.isFinite
        // Warmup stores the original zero-feature baseline, but skips scanning
        // until a frame with a previous face. Neither drop the sample nor emit
        // a candidate while the original scanner/merger is suspended.
        let blinks = status >= EF_WARMUP.rawValue ? temporal.process(at: time,
            leftMean: result.left.mean_y, leftDeviation: result.left.stddev_y,
            rightMean: result.right.mean_y, rightDeviation: result.right.stddev_y, frameInterval: frameInterval,
            scan: status == EF_OK.rawValue) : []
        return (valid, blinks)
    }
}
