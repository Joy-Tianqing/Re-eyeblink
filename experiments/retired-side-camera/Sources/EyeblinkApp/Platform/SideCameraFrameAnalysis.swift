import Foundation
import CoreGraphics
import Vision
import ImageIO
import EyeblinkCore

/// Vision objects and borrowed image pixels stay on the existing capture queue.
/// Calibration is numeric, in-memory and keyed by device/recalibration/resolution.
final class SideCameraFrameAnalysis {
    struct Result {
        var uptime: TimeInterval
        var frameInterval: TimeInterval?
        var faceCount: Int
        var output: SideCameraBlinkDetector.Output
    }
    private let rectangles = VNDetectFaceRectanglesRequest()
    private let landmarks = VNDetectFaceLandmarksRequest()
    private var detector = SideCameraBlinkDetector()
    private var targetTracker = FaceTargetTracker()
    private var key = ""
    private var size = CGSize.zero
    private var previous: FrameTimestamp?
    private var absence: FaceAbsenceTimer?
    private var qualityStarted: TimeInterval?
    private var noFaceTimeout: TimeInterval?
    var hasTimeBaseline: Bool { previous != nil }
    init() {
        rectangles.revision = VNDetectFaceRectanglesRequestRevision3
        landmarks.revision = VNDetectFaceLandmarksRequestRevision3
        landmarks.constellation = .constellation76Points
    }
    func reset(key: String, noFaceTimeout: TimeInterval?, preferSingleEye: Bool = false) {
        if self.key == key { targetTracker.beginLease() } else { targetTracker.reset() }
        detector.reset(keepCalibration: self.key == key, preferSingleEye: preferSingleEye)
        self.key = key; self.noFaceTimeout = noFaceTimeout
        previous = nil; absence = nil; qualityStarted = nil
    }
    func endRun() {
        targetTracker.beginLease(); detector.reset(keepCalibration: true); previous = nil; absence = nil; qualityStarted = nil
    }
    func prime(_ input: CameraFrameInput, clock: () -> FrameTimestamp) throws -> FrameTimestamp {
        try updateSize(input)
        _ = try extract(input, time: 0, updateTracking: false) // Warm Vision before ready/watchdog starts.
        let stamp = clock()
        guard stamp.isValid else { throw CameraFrameAnalysis.AnalysisError.clock }
        previous = stamp
        return stamp
    }
    private func updateSize(_ input: CameraFrameInput) throws {
        guard input.width > 0, input.height > 0, input.width <= 4096, input.height <= 4096,
              input.stride >= input.width * 4, input.stride <= input.width * 4 + 4096 else {
            throw CameraFrameAnalysis.AnalysisError.normalization
        }
        let next = CGSize(width: input.width, height: input.height)
        if size != next { detector.reset(); targetTracker.reset(); size = next }
    }
    func process(_ input: CameraFrameInput, clock: () -> FrameTimestamp, faceClock: (() -> FrameTimestamp)?) throws -> Result {
        try updateSize(input)
        let stamp = clock()
        guard stamp.isValid, let previous, let interval = stamp.interval(since: previous), interval > 0 else {
            throw CameraFrameAnalysis.AnalysisError.clock
        }
        self.previous = stamp
        let sample = try extract(input, time: stamp.uptime)
        if sample.faceCount == 1 { absence = nil }
        else if let faceClock, let noFaceTimeout {
            let checked = faceClock()
            guard checked.isValid, checked.frequency == stamp.frequency, checked.ticks >= stamp.ticks else { throw CameraFrameAnalysis.AnalysisError.clock }
            if absence == nil { absence = FaceAbsenceTimer(startedAt: checked) }
            if absence?.hasExpired(at: checked, after: noFaceTimeout) == true { throw CameraFrameAnalysis.AnalysisError.noFace }
        }
        let output = detector.process(sample)
        if output.valid { qualityStarted = nil }
        else {
            if qualityStarted == nil { qualityStarted = stamp.uptime }
            if noFaceTimeout != nil, stamp.uptime - qualityStarted! > 30 { throw AnalysisError.insufficientQuality }
        }
        return .init(uptime: stamp.uptime, frameInterval: interval, faceCount: sample.faceCount, output: output)
    }
    func extract(_ input: CameraFrameInput, time: TimeInterval, updateTracking: Bool = true) throws -> SideCameraSample {
        try updateSize(input)
        return try autoreleasepool {
            let bytes = Data(bytes: input.pixels, count: input.stride * input.height)
            let bitmap = CGBitmapInfo.byteOrder32Little.union(CGBitmapInfo(rawValue: CGImageAlphaInfo.noneSkipFirst.rawValue))
            guard let provider = CGDataProvider(data: bytes as CFData),
                  let image = CGImage(width: input.width, height: input.height, bitsPerComponent: 8, bitsPerPixel: 32,
                    bytesPerRow: input.stride, space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: bitmap,
                    provider: provider, decode: nil, shouldInterpolate: false, intent: .defaultIntent) else { throw CameraFrameAnalysis.AnalysisError.normalization }
            let handler = VNImageRequestHandler(cgImage: image, orientation: .up)
            try handler.perform([rectangles])
            let faces = rectangles.results ?? []
            let target = updateTracking ? targetTracker.select(faces.map(\.boundingBox), at: time) : nil
            let index = updateTracking ? target?.selectedIndex : (faces.count == 1 ? 0 : nil)
            guard let index else {
                return .init(time: time, left: nil, right: nil, yaw: nil, pitch: nil, roll: nil,
                             faceCount: 0, target: target)
            }
            landmarks.inputFaceObservations = [faces[index]]
            try handler.perform([landmarks])
            guard let face = landmarks.results?.first else { return .init(time: time, left: nil, right: nil, yaw: nil, pitch: nil, roll: nil, faceCount: 1, target: target) }
            let box = face.boundingBox
            func eye(_ region: VNFaceLandmarkRegion2D?) -> EyeContourMeasurement? {
                guard (face.landmarks?.confidence ?? 0) >= 0.4, let region, region.pointCount >= 6 else { return nil }
                // These are placement-error estimates, not visibility probabilities.
                if let estimates = region.precisionEstimatesPerPoint,
                   estimates.contains(where: { !$0.isFinite || $0 > 0.05 }) { return nil }
                let points = (0..<region.pointCount).map { index -> CGPoint in
                    let p = region.normalizedPoints[index]
                    return .init(x: (box.minX + p.x * box.width) * Double(input.width),
                                 y: (box.minY + p.y * box.height) * Double(input.height))
                }
                guard points.allSatisfy({ $0.x >= 1 && $0.x <= Double(input.width-2) && $0.y >= 1 && $0.y <= Double(input.height-2) }) else { return nil }
                return EyeContourMeasurement(points: points)
            }
            func degrees(_ value: NSNumber?) -> Double? { value.map { $0.doubleValue * 180 / .pi } }
            return .init(time: time, left: eye(face.landmarks?.leftEye), right: eye(face.landmarks?.rightEye),
                yaw: degrees(face.yaw), pitch: degrees(face.pitch), roll: degrees(face.roll),
                faceCenter: .init(x: box.midX, y: box.midY), faceWidth: box.width, target: target)
        }
    }
    enum AnalysisError: Error { case insufficientQuality }
}
