import Foundation
import EyeblinkCore
import CEyeFlow

/// One ordered frame-analysis owner. This is the capture callback's production
/// path, callable with frozen pixels without AVFoundation, permissions, or UI.
final class CameraFrameAnalysis {
    struct Result {
        var uptime: TimeInterval
        var frameInterval: TimeInterval?
        var eyes: CameraEyeTracking.Eyes?
        var flowStatus: Int32
        var features: EFResult
        var isValid: Bool
        var blinks: [TimeInterval]
    }
    private var noFaceTimeout: TimeInterval?
    private var absenceTimer: FaceAbsenceTimer?
    private var noFaceExpired = false
    private var tracking = CameraEyeTracking()
    private var motion = CameraMotionAnalysis()
    private let flow = ef_create()
    private let normalizer = ef_normalizer_create()
    private var firstTimestamp: FrameTimestamp?
    private var previousTimestamp: FrameTimestamp?
    var faceCount: Int { tracking.faceCount }
    var hasTimeBaseline: Bool { previousTimestamp != nil }

    deinit { ef_destroy(flow); ef_normalizer_destroy(normalizer) }

    func reset(noFaceTimeout: TimeInterval? = nil) {
        self.noFaceTimeout = noFaceTimeout.flatMap { $0.isFinite && $0 >= 0 ? $0 : nil }
        absenceTimer = nil; noFaceExpired = false
        tracking.reset(); motion.reset(); ef_reset(flow); ef_normalizer_reset(normalizer)
        firstTimestamp = nil; previousTimestamp = nil
    }

    func invalidate() {
        tracking.invalidateEyes(); motion.reset(); ef_reset(flow)
        firstTimestamp = nil; previousTimestamp = nil
    }

    func process(pixels: UnsafePointer<UInt8>, width: Int, height: Int, stride: Int,
                 predictor: DlibShapePredictor, clock: () -> FrameTimestamp, faceClock: (() -> FrameTimestamp)? = nil) throws -> Result {
        guard !noFaceExpired else { throw AnalysisError.noFace }
        let frame = try normalize(pixels: pixels, width: width, height: height, stride: stride)
        guard let pixels = frame.pixels else { throw AnalysisError.normalization }
        return try analyze(frame: frame, pixels: pixels, predictor: predictor, clock: clock, faceClock: faceClock)
    }

    func prime(pixels: UnsafePointer<UInt8>, width: Int, height: Int, stride: Int,
               clock: () -> FrameTimestamp) throws -> FrameTimestamp {
        guard !noFaceExpired else { throw AnalysisError.noFace }
        guard !hasTimeBaseline else { throw AnalysisError.clock }
        _ = try normalize(pixels: pixels, width: width, height: height, stride: stride)
        let timestamp = clock()
        guard timestamp.isValid else { throw AnalysisError.clock }
        // The pre-read frame establishes scale and ticks, never detection data.
        // Original pre-read gray is discarded at the no-previous-face gate.
        firstTimestamp = timestamp; previousTimestamp = timestamp
        return timestamp
    }

    private func normalize(pixels: UnsafePointer<UInt8>, width: Int, height: Int, stride: Int) throws -> EFNormalizedFrame {
        guard width > 0, height > 0, width <= Int32.max, height <= Int32.max, stride >= width * 4 else { throw AnalysisError.normalization }
        var frame = EFNormalizedFrame()
        let normalized = ef_normalize_bgra(normalizer, pixels, Int32(width), Int32(height), stride, &frame)
        guard normalized == EF_OK.rawValue, frame.pixels != nil else { throw AnalysisError.normalization }
        return frame
    }

    private func analyze(frame: EFNormalizedFrame, pixels: UnsafePointer<UInt8>, predictor: DlibShapePredictor,
                         clock: () -> FrameTimestamp, faceClock: (() -> FrameTimestamp)?) throws -> Result {
        // Shipped Model samples getTickCount after normalization and before
        // grayscale/landmarks/flow. Never consume a frame time on resize failure.
        let timestamp = clock()
        guard timestamp.isValid else { throw AnalysisError.clock }
        let frameInterval: TimeInterval?
        let relativeTime: TimeInterval
        if let previousTimestamp, let firstTimestamp {
            guard let interval = timestamp.interval(since: previousTimestamp),
                  let relative = timestamp.interval(since: firstTimestamp) else { throw AnalysisError.clock }
            frameInterval = interval; relativeTime = relative
        } else {
            firstTimestamp = timestamp; frameInterval = nil; relativeTime = 0
        }
        previousTimestamp = timestamp
        let width = Int(frame.width), height = Int(frame.height), stride = frame.stride
        let eyes = try tracking.process(pixels: pixels, width: width, height: height, stride: stride, predictor: predictor)
        // Shipped Model starts/checks its absence timer after tracking and
        // before flow. This clock must not replace the earlier frame timestamp.
        if eyes != nil { absenceTimer = nil }
        else if let faceClock {
            let checked = faceClock()
            guard checked.isValid, checked.frequency == timestamp.frequency,
                  checked.ticks >= timestamp.ticks else { throw AnalysisError.clock }
            if let noFaceTimeout {
                if absenceTimer == nil { absenceTimer = FaceAbsenceTimer(startedAt: checked) }
                if absenceTimer?.hasExpired(at: checked, after: noFaceTimeout) == true {
                    noFaceExpired = true
                    throw AnalysisError.noFace
                }
            }
        } else if noFaceTimeout != nil { throw AnalysisError.clock }
        var features = EFResult()
        // Original Model computes with the prior face even when this frame
        // loses the face. Cache the image and retain temporal history; the next
        // recovered face supplies a zero-feature baseline before flow resumes.
        let status = ef_process_with_face(flow, pixels, Int32(width), Int32(height), stride, eyes == nil ? 0 : 1,
            eyes?.left ?? EFEye(), eyes?.right ?? EFEye(), eyes?.normalizer ?? 1, &features)
        guard status >= 0 else { throw AnalysisError.flow }
        let result = motion.process(at: relativeTime, status: status, result: features, frameInterval: frameInterval)
        return Result(uptime: timestamp.uptime, frameInterval: frameInterval, eyes: eyes, flowStatus: status, features: features, isValid: eyes != nil && result.isValid, blinks: result.blinks)
    }

    enum AnalysisError: LocalizedError {
        case flow, normalization, clock, noFace
        var errorDescription: String? {
            switch self {
            case .noFace: return "持续未检测到人脸，本次检测已结束。"
            case .flow: return "眼部运动计算失败，请调整位置后重试。"
            case .normalization: return "摄像头画面尺寸无法转换，请重新连接设备。"
            case .clock: return "检测时钟发生变化，请重新连接摄像头。"
            }
        }
    }
}
