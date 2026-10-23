import XCTest
@testable import EyeblinkCore

final class DetectorFailureTests: XCTestCase {
    private func settings(training: Bool = false) -> AppSettings {
        var value = AppSettings(); value.trainingEnabled = training; value.mgdEnabled = training
        value.measurementEnabled = false; value.breakEnabled = false; value.exerciseEnabled = false
        return value
    }
    func testNoFaceAtLateFrameCancelsWithoutCompletingOrPausingCamera() {
        var engine = EyeblinkEngine(settings: settings())
        let id = engine.startMeasurement(at: 15)!, token = engine.state.cameraToken!
        XCTAssertEqual(engine.cameraNoFaceTimeout, 8)
        engine.cameraDidStart(token: token, at: 15)
        engine.sample(cameraToken: token, token: id, at: 194.9, faceValid: true, blinkDurations: [])
        engine.cameraDetectionFailed(token: token, reason: .noFace, at: 196)
        XCTAssertNil(engine.state.measurement)
        XCTAssertEqual(engine.state.lastDetectionFailure, "measurement-no-face")
        XCTAssertEqual(engine.takeEffects(), [.measurementCancelled(id)])
        XCTAssertEqual(engine.state.measurementRemaining, 480)
        XCTAssertTrue(engine.state.cameraPauseReasons.isEmpty)
    }
    func testTrainingNoFaceHidesMGDPromptAndReleasesCamera() {
        var engine = EyeblinkEngine(settings: settings(training: true))
        engine.advance(to: 30);let token = engine.state.cameraToken!
        XCTAssertEqual(engine.cameraNoFaceTimeout, 1)
        engine.cameraDidStart(token: token, at: 31)
        XCTAssertNotNil(engine.state.reminder)
        engine.cameraDetectionFailed(token: token, reason: .noFace, at: 32.1)
        XCTAssertFalse(engine.state.trainingSessionActive)
        XCTAssertNil(engine.state.reminder)
        XCTAssertNil(engine.state.cameraToken)
        XCTAssertEqual(engine.state.trainingRemaining, 30)
        XCTAssertEqual(engine.state.lastDetectionFailure, "training-no-face")
        XCTAssertTrue(engine.state.cameraPauseReasons.isEmpty)
    }
    func testStaleAndDuplicateDetectorFailureCannotCancelAnotherLease() {
        var engine = EyeblinkEngine(settings: settings())
        _ = engine.startMeasurement(at: 15);let old = engine.state.cameraToken!
        engine.invalidateCamera(at: 16);_ = engine.takeEffects()
        let id = engine.startMeasurement(at: 17)!, token = engine.state.cameraToken!
        engine.cameraDetectionFailed(token: old, reason: .noFace, at: 1000)
        XCTAssertNotNil(engine.state.measurement)
        engine.cameraDetectionFailed(token: token, reason: .noFace, at: 18)
        engine.cameraDetectionFailed(token: token, reason: .noFace, at: 19)
        XCTAssertNil(engine.state.measurement)
        XCTAssertEqual(engine.takeEffects(), [.measurementCancelled(id)])
    }
    func testPreviewIgnoresNoFaceFailure() {
        var engine = EyeblinkEngine(settings: settings())
        engine.setPreview(true, at: 15);let token = engine.state.cameraToken!
        XCTAssertNil(engine.cameraNoFaceTimeout)
        engine.cameraDetectionFailed(token: token, reason: .noFace, at: 100)
        XCTAssertEqual(engine.state.cameraToken, token)
        XCTAssertEqual(engine.state.cameraPurpose, .preview)
        XCTAssertNil(engine.state.lastDetectionFailure)
    }
    func testCaptureFailureFallsBackToThreeSecondSimpleReminderEvenBeforeReady() throws {
        for started in [false, true] {
            var engine = EyeblinkEngine(settings: settings(training: true))
            engine.advance(to: 30)
            let token = try XCTUnwrap(engine.state.cameraToken)
            if started { engine.cameraDidStart(token: token, at: 30) }
            engine.cameraCaptureFailed(token: token, at: 31)
            XCTAssertEqual(engine.state.reminder, .training(.simple, mgd: true))
            XCTAssertNil(engine.state.cameraToken)
            XCTAssertFalse(engine.state.trainingSessionActive)
            XCTAssertEqual(engine.state.lastDetectionFailure, "training-capture")
            XCTAssertTrue(engine.state.cameraPauseReasons.isEmpty)
            engine.cameraCaptureFailed(token: token, at: 1000)
            engine.cameraTrainingProgress(token: token, blinkDetected: true, at: 1001)
            engine.advance(to: 33.999)
            XCTAssertEqual(engine.state.reminder, .training(.simple, mgd: true))
            engine.advance(to: 34)
            XCTAssertNil(engine.state.reminder)
            XCTAssertEqual(engine.state.trainingRemaining, 30)
            engine.advance(to: 64)
            XCTAssertEqual(engine.state.cameraPurpose, .training)
            XCTAssertNotEqual(engine.state.cameraToken, token)
        }
    }

    func testMeasurementCaptureFailureCancelsOnceAndRetriesAfterEightMinutes() throws {
        var configured = settings(); configured.measurementEnabled = true
        var policy = EnginePolicy(); policy.featurePollingInterval = 0.001
        var engine = EyeblinkEngine(settings: configured, policy: policy)
        engine.advance(to: 120)
        let token = try XCTUnwrap(engine.state.cameraToken)
        let id = try XCTUnwrap(engine.state.measurement?.id)
        engine.cameraDidStart(token: token, at: 120)
        engine.cameraCaptureFailed(token: token, at: 130)
        XCTAssertEqual(engine.takeEffects(), [.measurementCancelled(id)])
        XCTAssertNil(engine.state.measurement)
        XCTAssertNil(engine.state.reminder)
        XCTAssertEqual(engine.state.measurementRemaining, 480)
        XCTAssertTrue(engine.state.cameraPauseReasons.isEmpty)
        engine.cameraMeasurementFinished(token: token, at: 300.001)
        engine.cameraCaptureFailed(token: token, at: 1000)
        XCTAssertTrue(engine.takeEffects().isEmpty)
        engine.advance(to: 609)
        XCTAssertNil(engine.state.measurement)
        engine.advance(to: 610)
        XCTAssertNotNil(engine.state.measurement)
        XCTAssertNotEqual(engine.state.cameraToken, token)
        XCTAssertTrue(engine.state.cameraPauseReasons.isEmpty)
    }

    func testCaptureFailureFromReplacedLeaseCannotStopPreview() throws {
        var engine = EyeblinkEngine(settings: settings(training: true))
        engine.advance(to: 30)
        let old = try XCTUnwrap(engine.state.cameraToken)
        engine.setPreview(true, at: 31)
        let current = try XCTUnwrap(engine.state.cameraToken)
        engine.cameraCaptureFailed(token: old, at: 1000)
        XCTAssertEqual(engine.state.cameraToken, current)
        XCTAssertEqual(engine.state.cameraPurpose, .preview)
        XCTAssertNil(engine.state.lastDetectionFailure)
        engine.cameraCaptureFailed(token: current, at: 32)
        XCTAssertNil(engine.state.cameraToken)
        XCTAssertFalse(engine.state.previewRequested)
        XCTAssertTrue(engine.state.cameraPauseReasons.isEmpty)
        engine.setPreview(true, at: 33)
        XCTAssertEqual(engine.state.cameraPurpose, .preview)
        XCTAssertNotEqual(engine.state.cameraToken, current)
    }

}
