import XCTest
import AVFoundation
import EyeblinkCore
@testable import EyeblinkApp

/// NotificationCenter + the production frame-run terminal boundary, without
/// AVCaptureSession.startRunning, a camera, or a shortened measurement deadline.
final class CameraTerminalOrderingTests: XCTestCase {
    func testWorkerCompletionPrecedesADeviceFailureObservedByNextRead() throws {
        let predictor = try predictor(), run = CameraFrameRun()
        run.reset(generation: UUID(), isPreview: false, noFaceTimeout: 8, measurementDuration: 180)
        try prime(run, predictor: predictor)
        let source = CameraFrameSource<Int>()
        source.close(.device("disconnected after last analyzed frame"))
        let completed = run.process(predictor: predictor, receivedAt: 195.001,
            clock: { self.stamp(195_001) }, acquirePixels: {
                XCTFail("Original checks the deadline before attempting the next read")
                _ = try source.read()
                throw CameraReadError.cancelled
            })
        XCTAssertEqual(completed?.measurementFinished, true)
        XCTAssertFalse(completed?.terminalFailure ?? true)

        let unfinished = CameraFrameRun()
        unfinished.reset(generation: UUID(), isPreview: false, noFaceTimeout: 8, measurementDuration: 180)
        try prime(unfinished, predictor: predictor)
        let failed = unfinished.process(predictor: predictor, receivedAt: 194,
            clock: { self.stamp(194_000) }, acquirePixels: {
                _ = try source.read()
                throw CameraReadError.cancelled
            })
        XCTAssertEqual(failed?.captureFailure, true, "Before the deadline the failed read still terminates")
        XCTAssertFalse(failed?.measurementFinished ?? true)
    }
    private func predictor() throws -> DlibShapePredictor {
        let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        return try DlibShapePredictor(contentsOf: root.appendingPathComponent(".deps/models/data.dat"))
    }
    private func stamp(_ milliseconds: Int64) -> FrameTimestamp { .init(ticks: milliseconds, frequency: 1000) }
    private func prime(_ run: CameraFrameRun, predictor: DlibShapePredictor) throws {
        let pixels = [UInt8](repeating: 0, count: 640*480*4)
        let value = pixels.withUnsafeBufferPointer { p in
            run.process(predictor: predictor, receivedAt: 15, clock: { self.stamp(15_000) }, acquirePixels: {
                .init(pixels: p.baseAddress!, width: 640, height: 480, stride: 640*4)
            })
        }
        XCTAssertEqual(value?.isPriming, true)
    }
    private func queuedFrame(_ run: CameraFrameRun, predictor: DlibShapePredictor) -> CameraObservation? {
        run.process(predictor: predictor, receivedAt: 195.001, clock: { self.stamp(195_001) }, acquirePixels: {
            XCTFail("Terminal/deadline callbacks must not acquire pixels")
            throw CameraFrameAnalysis.AnalysisError.normalization
        })
    }
    func testEachPlatformFailureBeforeQueuedDeadlineEmitsOneFailureAndCancelsEngineMeasurement() throws {
        let predictor = try predictor()
        for name in [AVCaptureSession.runtimeErrorNotification, AVCaptureDevice.wasDisconnectedNotification, AVCaptureSession.wasInterruptedNotification] {
            let queue = DispatchQueue(label: "camera.terminal.failure-first"), center = NotificationCenter()
            let session = NSObject(), device = NSObject(), run = CameraFrameRun()
            var settings = AppSettings()
            settings.trainingEnabled = false; settings.measurementEnabled = false; settings.exerciseEnabled = false; settings.breakEnabled = false
            var engine = EyeblinkEngine(settings: settings)
            let id = try XCTUnwrap(engine.startMeasurement(at: 15)), token = try XCTUnwrap(engine.state.cameraToken)
            XCTAssertEqual(engine.state.measurement?.targetDuration, 180)
            var values: [CameraObservation] = []
            let observer = CameraFailureObserver(queue: queue, center: center) { generation, _ in
                dispatchPrecondition(condition: .onQueue(queue))
                if let result = run.fail(generation: generation, message: "fixture platform failure", at: 194.999) { values.append(result) }
            }
            try queue.sync {
                run.reset(generation: token, isPreview: false, noFaceTimeout: 8, measurementDuration: 180)
                try prime(run, predictor: predictor)
                observer.start(generation: token, session: session, device: device)
                // Both notification callbacks and subsequent frames queue behind
                // this block; the notification was submitted first.
                center.post(name: name, object: name == AVCaptureDevice.wasDisconnectedNotification ? device : session)
                queue.async { if let result = self.queuedFrame(run, predictor: predictor) { values.append(result) } }
            }
            queue.sync {
                XCTAssertEqual(values.count, 1)
                XCTAssertEqual(values.first?.terminalFailure, true)
                XCTAssertFalse(values.contains { $0.measurementFinished })
                XCTAssertNil(run.fail(generation: token, message: "duplicate", at: 196))
                observer.stop()
            }
            engine.cameraDidStart(token: token, at: 15)
            for value in values where value.terminalFailure { engine.setCameraPaused(true, reason: .unavailable, at: value.uptime) }
            engine.cameraMeasurementFinished(token: token, at: 196)
            XCTAssertNil(engine.state.measurement)
            XCTAssertEqual(engine.takeEffects(), [.measurementCancelled(id)])
        }
    }

    func testCompletedDeadlineRejectsLaterPlatformFailureAndDuplicateCompletion() throws {
        let predictor = try predictor(), run = CameraFrameRun(), token = UUID()
        run.reset(generation: token, isPreview: false, noFaceTimeout: 8, measurementDuration: 180)
        try prime(run, predictor: predictor)
        XCTAssertEqual(queuedFrame(run, predictor: predictor)?.measurementFinished, true)
        XCTAssertNil(run.fail(generation: token, message: "late disconnect", at: 196))
        XCTAssertNil(queuedFrame(run, predictor: predictor))
    }

    func testStaleFailureCannotStopReplacementLeaseAndNewLeaseCanPrimeAfterFailure() throws {
        let predictor = try predictor(), run = CameraFrameRun(), old = UUID(), replacement = UUID()
        run.reset(generation: old, isPreview: false, noFaceTimeout: 8, measurementDuration: 180)
        XCTAssertEqual(run.fail(generation: old, message: "startup failed", at: 0)?.terminalFailure, true)
        XCTAssertNil(run.process(predictor: predictor, receivedAt: 1, clock: {
            XCTFail("Failed startup cannot consume clocks"); return self.stamp(1000)
        }, acquirePixels: { XCTFail("Failed startup cannot touch pixels"); throw CameraFrameAnalysis.AnalysisError.normalization }))
        run.reset(generation: replacement, isPreview: true, noFaceTimeout: nil, measurementDuration: nil)
        XCTAssertNil(run.fail(generation: old, message: "late old error", at: 2))
        try prime(run, predictor: predictor)
        XCTAssertEqual(run.fail(generation: replacement, message: "new disconnect", at: 3)?.generation, replacement)
        XCTAssertNil(run.fail(generation: replacement, message: "duplicate", at: 4))
    }
}
