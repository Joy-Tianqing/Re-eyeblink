import Foundation
import CoreGraphics

/// Dimensionless aperture in the eye's own axes. A closed contour is valid;
/// missing corners or an eye too small to resolve is not a zero aperture.
public struct EyeContourMeasurement: Equatable, Sendable {
    public let aperture: Double
    public let width: Double
    public let center: CGPoint
    public init?(points: [CGPoint]) {
        guard points.count >= 6, points.allSatisfy({ $0.x.isFinite && $0.y.isFinite }) else { return nil }
        var corners = (points[0], points[1]), longest: Double = 0
        for a in points.indices { for b in points.indices where b > a {
            let distance = hypot(points[b].x - points[a].x, points[b].y - points[a].y)
            if distance > longest { longest = distance; corners = (points[a], points[b]) }
        } }
        guard longest >= 10 else { return nil }
        let nx = -(corners.1.y - corners.0.y) / longest
        let ny = (corners.1.x - corners.0.x) / longest
        let heights = points.map { ($0.x - corners.0.x) * nx + ($0.y - corners.0.y) * ny }
        width = longest
        aperture = ((heights.max() ?? 0) - (heights.min() ?? 0)) / longest
        center = .init(x: (corners.0.x + corners.1.x) / 2, y: (corners.0.y + corners.1.y) / 2)
    }
    public init(aperture: Double, width: Double = 30, center: CGPoint = .zero) {
        self.aperture = aperture; self.width = width; self.center = center
    }
}

public enum SideCameraStatus: String, Codable, Sendable {
    case noFace, multipleFaces, acquiringTarget, targetLost, targetAmbiguous, poseUnavailable, eyesUnavailable, moving, learningOpenEyes, calibrating, ready
}
/// Region identifiers describe Vision contours, not the camera's physical side.
public enum EyeObservationMode: String, Codable, Sendable {
    case both, left, right, mixed
    public var isEstimated: Bool { self != .both }
}
public struct SideCameraFeedback: Equatable, Sendable {
    public var status: SideCameraStatus
    public var calibrationBlinks: Int
    public var yawDegrees: Double?
    public var pitchDegrees: Double?
    public var rollDegrees: Double?
    public var observationMode: EyeObservationMode?
    public var target: FaceTargetSelection?
    public init(status: SideCameraStatus, calibrationBlinks: Int = 0, yawDegrees: Double? = nil,
                pitchDegrees: Double? = nil, rollDegrees: Double? = nil, observationMode: EyeObservationMode? = nil, target: FaceTargetSelection? = nil) {
        self.status = status; self.calibrationBlinks = calibrationBlinks; self.yawDegrees = yawDegrees
        self.pitchDegrees = pitchDegrees; self.rollDegrees = rollDegrees; self.observationMode = observationMode; self.target = target
    }
}
public struct SideCameraSample: Sendable {
    public var time: TimeInterval
    public var left: EyeContourMeasurement?
    public var right: EyeContourMeasurement?
    public var yaw: Double?
    public var pitch: Double?
    public var roll: Double?
    public var faceCenter: CGPoint
    public var faceWidth: Double
    public var faceCount: Int
    public var target: FaceTargetSelection?
    public init(time: TimeInterval, left: EyeContourMeasurement?, right: EyeContourMeasurement?,
                yaw: Double? = 20, pitch: Double? = 0, roll: Double? = 0,
                faceCenter: CGPoint = .init(x: 0.5, y: 0.5), faceWidth: Double = 0.3, faceCount: Int = 1, target: FaceTargetSelection? = nil) {
        self.time = time; self.left = left; self.right = right; self.yaw = yaw; self.pitch = pitch; self.roll = roll
        self.faceCenter = faceCenter; self.faceWidth = faceWidth; self.faceCount = faceCount; self.target = target
    }
}

/// Calibrated contour detector, independent of Vision/camera/UI. All times are
/// monotonic seconds, all pose angles degrees. No candidate crosses a lease/gap.
public struct SideCameraBlinkDetector: Sendable {
    public struct Output: Sendable {
        public var feedback: SideCameraFeedback
        public var valid: Bool
        public var blinks: [TimeInterval]
    }
    private struct Calibration: Sendable {
        var yaw: Double, pitch: Double, left: Double, right: Double
        var mode: EyeObservationMode
        var lastUsed: TimeInterval
        var blinks = 0
    }
    private var calibrations: [Calibration] = []
    private var active: Int?
    private var eyeMode: EyeObservationMode?
    private var preferSingleEye = false
    private var targetRevision: UInt64?
    private var previous: SideCameraSample?
    private var stableSince: TimeInterval?
    private struct OpenEyeWarmup: Sendable {
        var startedAt: TimeInterval
        var yaw: Double, pitch: Double
        var samples: [(Double, Double)] = []
    }
    private var warmup: OpenEyeWarmup?
    private var closedAt: TimeInterval?
    private var armedAt: TimeInterval?
    private var refractoryUntil: TimeInterval = 0
    public init(preferSingleEye: Bool = false) { self.preferSingleEye = preferSingleEye }
    public mutating func reset(keepCalibration: Bool = false, preferSingleEye: Bool? = nil) {
        let policyChanged = preferSingleEye.map { $0 != self.preferSingleEye } ?? false
        if let preferSingleEye { self.preferSingleEye = preferSingleEye }
        if !keepCalibration || policyChanged { calibrations = []; targetRevision = nil }
        eyeMode = nil
        active = nil; previous = nil; warmup = nil
        stableSince = nil; closedAt = nil; armedAt = nil; refractoryUntil = 0
    }
    private mutating func discardCandidate() { closedAt = nil; armedAt = nil }

    public mutating func process(_ sample: SideCameraSample) -> Output {
        func output(_ status: SideCameraStatus, valid: Bool = false, blinks: [TimeInterval] = [], count: Int = 0) -> Output {
            .init(feedback: .init(status: status, calibrationBlinks: count, yawDegrees: sample.yaw, pitchDegrees: sample.pitch, rollDegrees: sample.roll, observationMode: eyeMode, target: sample.target), valid: valid, blinks: blinks)
        }
        guard sample.time.isFinite, previous.map({ sample.time > $0.time }) ?? true else {
            discardCandidate(); return output(.moving)
        }
        if let target = sample.target, target.status == .tracking, targetRevision != target.revision {
            reset(); targetRevision = target.revision
        }
        let old = previous; previous = sample
        if let target = sample.target, target.status != .tracking {
            discardCandidate(); stableSince = nil; warmup = nil
            switch target.status {
            case .none: return output(.noFace)
            case .acquiring: return output(.acquiringTarget)
            case .lost: return output(.targetLost)
            case .ambiguous: return output(.targetAmbiguous)
            case .tracking: break
            }
        }
        guard sample.faceCount == 1 else {
            discardCandidate(); stableSince = nil; warmup = nil
            return output(sample.faceCount == 0 ? .noFace : .multipleFaces)
        }
        guard let yaw = sample.yaw, let pitch = sample.pitch, let roll = sample.roll,
              [yaw, pitch, roll, sample.faceWidth, sample.faceCenter.x, sample.faceCenter.y].allSatisfy(\.isFinite),
              sample.faceWidth > 0 else { discardCandidate(); stableSince = nil; warmup = nil; return output(.poseUnavailable) }
        // Absolute pose is diagnostic, not evidence that a resolved eye is unusable.
        guard abs(yaw) <= 90, abs(pitch) <= 90, abs(roll) <= 180 else {
            discardCandidate(); stableSince = nil; warmup = nil; return output(.poseUnavailable)
        }
        if let old {
            let gap = sample.time - old.time
            let translation = hypot(sample.faceCenter.x - old.faceCenter.x, sample.faceCenter.y - old.faceCenter.y) / sample.faceWidth
            let poseJump = abs(yaw - (old.yaw ?? yaw)) > 6 || abs(pitch - (old.pitch ?? pitch)) > 6 || abs(roll - (old.roll ?? roll)) > 8
            let scale = old.faceWidth > 0 ? sample.faceWidth / old.faceWidth : 1
            if gap > 0.15 || old.faceCount != 1 || poseJump || translation > 0.16 || scale < 0.8 || scale > 1.25 {
                discardCandidate(); stableSince = nil; warmup = nil
                return output(.moving)
            }
        }
        func usable(_ eye: EyeContourMeasurement?) -> EyeContourMeasurement? {
            guard let eye, eye.aperture.isFinite, eye.width.isFinite, eye.aperture >= 0, eye.width >= 10 else { return nil }
            return eye
        }
        let left = usable(sample.left), right = usable(sample.right)
        let mode: EyeObservationMode
        switch (left, right) {
        case (nil, nil):
            discardCandidate(); stableSince = nil; warmup = nil; eyeMode = nil; active = nil
            return output(.eyesUnavailable)
        case (_?, nil): mode = .left
        case (nil, _?): mode = .right
        case let (l?, r?):
            if preferSingleEye {
                // Lock the eye across eyelid/width jitter. Never select by aperture:
                // a closing eye must not cause a switch to the other open eye.
                mode = eyeMode == .left || eyeMode == .right ? eyeMode! : (l.width >= r.width ? .left : .right)
            } else {
                let ratio = min(l.width, r.width) / max(l.width, r.width)
                if let eyeMode, eyeMode != .both, ratio < 0.75 { mode = eyeMode }
                else if ratio < 0.6 { mode = l.width >= r.width ? .left : .right }
                else { mode = .both }
            }
        }
        if mode != eyeMode {
            eyeMode = mode; active = nil; discardCandidate(); stableSince = nil; warmup = nil
        }
        // Inactive eyes use neutral values only in arithmetic, never as closure evidence.
        let leftAperture = mode == .right ? 1 : left!.aperture
        let rightAperture = mode == .left ? 1 : right!.aperture
        if stableSince == nil { stableSince = sample.time }
        guard sample.time - stableSince! >= 0.2 else { return output(.moving) }
        // Filter in BOTH pose dimensions before ranking. A closer yaw with an
        // incompatible pitch must never hide an already verified calibration.
        let eligible = calibrations.indices.filter {
            calibrations[$0].mode == mode && abs(calibrations[$0].yaw - yaw) <= 12 && abs(calibrations[$0].pitch - pitch) <= 12
        }
        let readyCalibrations = eligible.filter { calibrations[$0].blinks >= 3 }
        let candidates = readyCalibrations.isEmpty ? eligible : readyCalibrations
        let retained = active.flatMap { candidates.contains($0) ? $0 : nil }
        // A verified active baseline exits at 16 degrees, while another pose
        // enters at 12. This bounded hysteresis avoids recalibration at an edge.
        let verifiedRetained = active.flatMap { index -> Int? in
            let c = calibrations[index]
            return c.mode == mode && c.blinks >= 3 && abs(c.yaw - yaw) <= 16 && abs(c.pitch - pitch) <= 16 ? index : nil
        }
        let selected = verifiedRetained ?? retained ?? candidates.min {
            let a = calibrations[$0], b = calibrations[$1]
            return pow(a.yaw - yaw, 2) + pow(a.pitch - pitch, 2) < pow(b.yaw - yaw, 2) + pow(b.pitch - pitch, 2)
        }
        if selected != active { active = selected; discardCandidate(); warmup = nil }
        if active == nil {
            // Bound the complete learning window to one pose range, rather
            // than merely checking adjacent frames during a gradual head turn.
            if warmup == nil || abs(warmup!.yaw - yaw) > 12 || abs(warmup!.pitch - pitch) > 12 {
                warmup = .init(startedAt: sample.time, yaw: yaw, pitch: pitch)
            }
            warmup!.samples.append((leftAperture, rightAperture))
            guard sample.time - warmup!.startedAt >= 1, warmup!.samples.count >= 15 else { return output(.learningOpenEyes) }
            let l = warmup!.samples.map(\.0).sorted(), r = warmup!.samples.map(\.1).sorted()
            let index = min(l.count - 1, Int(Double(l.count) * 0.8))
            // A closed/occluded eye cannot establish its own "open" baseline.
            guard l[index] >= 0.08, r[index] >= 0.08 else {
                warmup = nil; return output(.eyesUnavailable)
            }
            if calibrations.count == 5 {
                // Exploration must not evict the only verified calibration.
                // Prefer the least-progressed entry, then the least recently used.
                let victim = calibrations.indices.min {
                    let a = calibrations[$0], b = calibrations[$1]
                    return a.blinks == b.blinks ? a.lastUsed < b.lastUsed : a.blinks < b.blinks
                }!
                calibrations.remove(at: victim)
            }
            calibrations.append(.init(yaw: yaw, pitch: pitch, left: l[index], right: r[index], mode: mode, lastUsed: sample.time))
            active = calibrations.count - 1; warmup = nil
        }
        guard let active else { return output(.calibrating) }
        var calibration = calibrations[active]
        calibration.lastUsed = sample.time
        let l = leftAperture / calibration.left, r = rightAperture / calibration.right
        let open = l >= 0.78 && r >= 0.78
        // A single observed eye estimates blinks; it cannot distinguish a wink.
        let closed = mode == .both ? min(l, r) < 0.55 && max(l, r) < 0.70 : (mode == .left ? l : r) < 0.55
        var events: [TimeInterval] = []
        if let started = closedAt {
            let duration = sample.time - started
            if duration > 0.8 { discardCandidate() }
            else if open {
                closedAt = nil; armedAt = sample.time; refractoryUntil = sample.time + 0.12
                if duration >= 0.06 {
                    if calibration.blinks < 3 { calibration.blinks += 1 }
                    else { events = [duration] }
                }
            }
        } else if open {
            if armedAt == nil { armedAt = sample.time }
            if calibration.blinks >= 3, l >= 0.85, r >= 0.85, l <= 1.25, r <= 1.25 {
                calibration.left += (leftAperture - calibration.left) * 0.002
                calibration.right += (rightAperture - calibration.right) * 0.002
            }
        } else if closed, let armedAt, sample.time - armedAt >= 0.15, sample.time >= refractoryUntil {
            closedAt = sample.time
        } else if !closed { armedAt = nil }
        calibrations[active] = calibration
        let ready = calibration.blinks >= 3
        return output(ready ? .ready : .calibrating, valid: ready, blinks: events, count: calibration.blinks)
    }
}

public struct MeasurementDetection: Codable, Equatable, Sendable {
    public var algorithm: String
    public var validFrameFraction: Double
    public var targeting: String?
    public var observationMode: EyeObservationMode?
    public init(algorithm: String, validFrameFraction: Double, observationMode: EyeObservationMode? = nil, targeting: String? = nil) {
        self.algorithm = algorithm; self.validFrameFraction = validFrameFraction; self.observationMode = observationMode; self.targeting = targeting
    }
    public var isMonocularEstimate: Bool { observationMode?.isEstimated == true }
    public var isAcceptable: Bool { validFrameFraction.isFinite && (0.85...1).contains(validFrameFraction) }
}
public struct SideCameraCoverage: Sendable {
    private var started: TimeInterval?
    private var previous: TimeInterval?
    private var wasValid = false
    private var previousMode: EyeObservationMode?
    private var aggregateMode: EyeObservationMode?
    private var validTime: TimeInterval = 0
    public init() {}
    public mutating func start(at time: TimeInterval) { self = .init(); started = time }
    public mutating func observe(at time: TimeInterval, valid: Bool, observationMode: EyeObservationMode? = nil) {
        guard time.isFinite, let started, time >= started, previous.map({ time > $0 }) ?? true else { return }
        if let previous, wasValid, valid, previousMode == observationMode, time - previous <= 0.15 { validTime += time - previous }
        if valid, let observationMode {
            aggregateMode = aggregateMode.map { $0 == observationMode ? $0 : .mixed } ?? observationMode
        }
        previous = time; wasValid = valid; previousMode = observationMode
    }
    public func report(at time: TimeInterval) -> MeasurementDetection {
        let elapsed = started.map { time - $0 } ?? 0
        return .init(algorithm: "side-contour-v4", validFrameFraction: elapsed > 0 ? min(1, max(0, validTime / elapsed)) : 0,
                     observationMode: aggregateMode, targeting: "spatial-primary-v2")
    }
}
