import Foundation
import OSLog
import EyeblinkCore
import CEyeFlow

private let cameraDetectionLog = Logger(subsystem: "org.reeyeblink.app", category: "DetectionBoundary")

struct CameraObservation: Sendable {
    let generation: UUID
    let uptime: TimeInterval
    let faceCount: Int
    let eyeDetectionValid: Bool
    let blinkDurations: [TimeInterval]
    let framesPerSecond: Double
    let error: String?
    var terminalFailure = false
    var captureFailure = false
    var isPriming = false
    var detectionFailure: CameraDetectionFailure? = nil
    var measurementFinished = false
    var trainingReaction: Bool? = nil

    var endsRun: Bool { terminalFailure || detectionFailure != nil || measurementFinished || trainingReaction == true }
}

struct CameraFrameInput {
    let pixels: UnsafePointer<UInt8>
    let width: Int
    let height: Int
    let stride: Int
}

/// One capture-queue owner for ready/frame/failure/completion observations.
/// The caller keeps supplied pixels alive and locked until process returns.
/// Acquisition is lazy so the deadline still precedes locking/reading pixels.
final class CameraFrameRun {
    private var generation = UUID()
    private var isPreview = false
    private var rateMonitor = FrameRateMonitor()
    private var previousFrame: TimeInterval?
    private var smoothedFPS: Double = 0
    private let analysis = CameraFrameAnalysis()
    private var boundary = CameraRunBoundary(measurementDuration: nil)
    private var startupReadsRemaining = 7

    func reset(generation: UUID, isPreview: Bool, noFaceTimeout: TimeInterval?, measurementDuration: TimeInterval?) {
        self.generation = generation; self.isPreview = isPreview
        rateMonitor.reset(); previousFrame = nil; smoothedFPS = 0
        analysis.reset(noFaceTimeout: noFaceTimeout)
        startupReadsRemaining = 7
        boundary = CameraRunBoundary(measurementDuration: measurementDuration,
            trainingDuration: !isPreview && measurementDuration == nil ? 4.001 : nil)
    }

    /// Session notifications and image failures must compete with completion on
    /// the same queue/latch. A stale lease or a second terminal event is ignored.
    func fail(generation: UUID, message: String, at time: TimeInterval, captureFailure: Bool = false) -> CameraObservation? {
        guard generation == self.generation, boundary.terminate() else { return nil }
        return CameraObservation(generation: generation, uptime: time, faceCount: 0,
            eyeDetectionValid: false, blinkDurations: [], framesPerSecond: 0, error: message, terminalFailure: true, captureFailure: captureFailure)
    }

    private func failure(_ message: String, at time: TimeInterval, captureFailure: Bool = false) -> CameraObservation? {
        fail(generation: generation, message: message, at: time, captureFailure: captureFailure)
    }

    private func updateFrameRate(at now: TimeInterval, frameInterval: TimeInterval? = nil) -> Bool {
        if let previousFrame {
            let fps = 1 / max(frameInterval ?? (now - previousFrame), 0.001)
            smoothedFPS = smoothedFPS == 0 ? fps : smoothedFPS * 0.9 + fps * 0.1
        }
        previousFrame = now
        if let fps = rateMonitor.observe(at: now, frameInterval: frameInterval), fps <= 9, !isPreview { return false }
        return true
    }

    func process(predictor: DlibShapePredictor, receivedAt: TimeInterval,
                 clock: @escaping () -> FrameTimestamp, acquirePixels: () throws -> CameraFrameInput) -> CameraObservation? {
        do {
            switch try boundary.nextFrame(clock: clock) {
            case .ignore: return nil
            case .complete(let checked):
                cameraDetectionLog.notice("event=measurementDeadline uptime=\(checked.uptime, privacy: .public)")
                return CameraObservation(generation: generation, uptime: checked.uptime, faceCount: 0,
                    eyeDetectionValid: false, blinkDurations: [], framesPerSecond: smoothedFPS, error: nil, measurementFinished: true)
            case .trainingPrompt(let checked):
                return CameraObservation(generation: generation, uptime: checked.uptime, faceCount: 0,
                    eyeDetectionValid: false, blinkDurations: [], framesPerSecond: smoothedFPS, error: nil, trainingReaction: false)
            case .trainingComplete(let checked):
                return CameraObservation(generation: generation, uptime: checked.uptime, faceCount: 0,
                    eyeDetectionValid: false, blinkDurations: [], framesPerSecond: smoothedFPS, error: nil, trainingReaction: true)
            case .analyze: break
            }
        } catch { return failure("检测时钟发生变化，请重新连接摄像头。", at: receivedAt) }

        var frameTime = receivedAt
        func sampleClock() -> FrameTimestamp {
            let stamp = clock()
            if stamp.isValid { frameTime = stamp.uptime }
            return stamp
        }
        do {
            // Model::startBlinkDetection performs seven unchecked reads before
            // the checked priming image. No frame clocks or detector state advance.
            while startupReadsRemaining > 0 {
                startupReadsRemaining -= 1
                do { _ = try acquirePixels() }
                catch CameraReadError.cancelled { return nil }
                catch CameraReadError.timeout { continue }
            }
            let input = try acquirePixels()
            if !analysis.hasTimeBaseline {
                let baseline = try analysis.prime(pixels: input.pixels, width: input.width, height: input.height, stride: input.stride, clock: sampleClock)
                _ = updateFrameRate(at: baseline.uptime)
                let ready = sampleClock()
                try boundary.start(at: ready)
                return CameraObservation(generation: generation, uptime: ready.uptime, faceCount: 0,
                    eyeDetectionValid: false, blinkDurations: [], framesPerSecond: smoothedFPS, error: nil, isPriming: true)
            }
            let result = try analysis.process(pixels: input.pixels, width: input.width, height: input.height, stride: input.stride,
                predictor: predictor, clock: sampleClock, faceClock: isPreview ? nil : sampleClock)
            guard updateFrameRate(at: result.uptime, frameInterval: result.frameInterval) else {
                return failure("摄像头帧率低于 10 FPS，本次检测已停止。请关闭其他相机应用后重新连接。", at: result.uptime, captureFailure: true)
            }
            boundary.recordBlinks(result.blinks)
            return CameraObservation(generation: generation, uptime: result.uptime, faceCount: analysis.faceCount,
                eyeDetectionValid: result.isValid, blinkDurations: result.blinks, framesPerSecond: smoothedFPS, error: nil)
        } catch CameraReadError.cancelled { return nil
        } catch CameraReadError.timeout {
            return failure("摄像头未返回图像，本次检测已停止。", at: sampleClock().uptime, captureFailure: true)
        } catch CameraReadError.device(let message) {
            return failure(message, at: sampleClock().uptime, captureFailure: true)
        } catch CameraFrameAnalysis.AnalysisError.noFace {
            boundary.terminate()
            cameraDetectionLog.notice("event=noFace uptime=\(frameTime, privacy: .public)")
            return CameraObservation(generation: generation, uptime: frameTime, faceCount: 0,
                eyeDetectionValid: false, blinkDurations: [], framesPerSecond: smoothedFPS, error: nil, detectionFailure: .noFace)
        } catch {
            // A failed computation is not an ordinary no-face sample. Stop
            // before FPS/sample delivery and prevent queued deadline success.
            cameraDetectionLog.notice("event=processingFailure uptime=\(frameTime, privacy: .public)")
            return failure("画面处理失败，检测已停止。请重新连接摄像头。\n\(error.localizedDescription)", at: frameTime)
        }
    }
}
