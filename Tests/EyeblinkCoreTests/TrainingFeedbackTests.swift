import XCTest
@testable import EyeblinkCore

final class TrainingFeedbackTests: XCTestCase {
    private func ready(mgd: Bool = true) -> EyeblinkEngine {
        var settings = AppSettings()
        settings.trainingEnabled = true; settings.trainingMode = .interactive
        settings.mgdEnabled = mgd
        settings.exerciseEnabled = false; settings.breakEnabled = false; settings.measurementEnabled = false
        var engine = EyeblinkEngine(settings: settings)
        engine.advance(to: 30)
        engine.cameraDidStart(token: engine.state.cameraToken!, at: 30)
        return engine
    }

    func testWorkerSuccessImmediatelyHidesReminderAndRestartsInterval() throws {
        var engine = ready()
        let camera = try XCTUnwrap(engine.state.cameraToken)
        engine.sample(cameraToken: camera, token: nil, at: 30.1, faceValid: true, blinkDurations: [0.15])
        XCTAssertEqual(engine.state.cameraToken, camera, "Frame delivery must not complete the worker's next-loop decision")
        XCTAssertEqual(engine.state.reminder, .training(.interactive, mgd: true))
        engine.cameraTrainingProgress(token: camera, blinkDetected: true, at: 30.2)
        XCTAssertNil(engine.state.cameraToken)
        XCTAssertNil(engine.state.reminder)
        XCTAssertFalse(engine.state.trainingSessionActive)
        XCTAssertEqual(engine.state.trainingRemaining, 30)
        engine.advance(to: 31.2)
        XCTAssertEqual(engine.state.trainingRemaining, 29, accuracy: 1e-9)
        XCTAssertFalse(engine.finishTrainingFeedback(id: UUID(), at: 32))
        XCTAssertEqual(engine.state.trainingRemaining, 29, "Obsolete animation callbacks cannot reset the new interval")
    }

    func testSamplesCannotReplaceWorkerDecisionAndOldWorkerCannotCompleteTraining() throws {
        var engine = ready()
        let camera = try XCTUnwrap(engine.state.cameraToken)
        let reminder = engine.state.reminder
        engine.sample(cameraToken: UUID(), token: nil, at: 30.1, faceValid: true, blinkDurations: [0.2])
        engine.sample(cameraToken: camera, token: nil, at: 30.2, faceValid: false, blinkDurations: [0.2])
        engine.sample(cameraToken: camera, token: nil, at: 30.3, faceValid: true, blinkDurations: [.nan, .infinity, 0, -1])
        engine.sample(cameraToken: camera, token: nil, at: 30.25, faceValid: true, blinkDurations: [0.2])
        engine.cameraTrainingProgress(token: UUID(), blinkDetected: true, at: 1000)
        engine.cameraTrainingProgress(token: camera, blinkDetected: true, at: .nan)
        engine.cameraTrainingProgress(token: camera, blinkDetected: true, at: 29)
        XCTAssertEqual(engine.state.reminder, reminder)
        XCTAssertEqual(engine.state.cameraToken, camera)
        engine.cameraTrainingProgress(token: camera, blinkDetected: true, at: 30.4)
        XCTAssertNil(engine.state.reminder)
        XCTAssertNil(engine.state.cameraToken)
    }

    func testBlinkBeforePromptSuppressesReminderWithoutFeedback() throws {
        var engine = ready(mgd: false)
        let camera = try XCTUnwrap(engine.state.cameraToken)
        engine.sample(cameraToken: camera, token: nil, at: 30.1, faceValid: true, blinkDurations: [0.2])
        XCTAssertNil(engine.state.reminder)
        XCTAssertEqual(engine.state.cameraToken, camera)
        engine.cameraTrainingProgress(token: camera, blinkDetected: true, at: 30.2)
        XCTAssertNil(engine.state.reminder)
        XCTAssertNil(engine.state.cameraToken)
    }

    func testOldCompletionCannotDismissNextReminder() throws {
        var engine = ready()
        let oldCamera = try XCTUnwrap(engine.state.cameraToken)
        engine.dismissReminder(at: 30.2)
        engine.advance(to: 61)
        let nextCamera = try XCTUnwrap(engine.state.cameraToken)
        engine.cameraDidStart(token: nextCamera, at: 61)
        let nextReminder = engine.state.reminder
        XCTAssertNotNil(nextReminder)
        engine.cameraTrainingProgress(token: oldCamera, blinkDetected: true, at: 1000)
        engine.cameraTrainingProgress(token: oldCamera, blinkDetected: false, at: 1001)
        XCTAssertEqual(engine.state.reminder, nextReminder)
        XCTAssertEqual(engine.state.cameraToken, nextCamera)
        XCTAssertFalse(engine.finishTrainingFeedback(id: UUID(), at: 1002))
        engine.cameraTrainingProgress(token: nextCamera, blinkDetected: true, at: 61.1)
        XCTAssertNil(engine.state.reminder)
    }

    func testPauseDisableAndPreviewCancelPendingWorkerCompletion() throws {
        for action in 0..<3 {
            var engine = ready()
            let camera = try XCTUnwrap(engine.state.cameraToken)
            engine.sample(cameraToken: camera, token: nil, at: 30.1, faceValid: true, blinkDurations: [0.2])
            switch action {
            case 0: engine.setPaused(true, at: 30.2)
            case 1:
                var settings = engine.settings; settings.trainingEnabled = false
                engine.updateSettings(settings, at: 30.2)
            default: engine.setPreview(true, at: 30.2)
            }
            let replacement = engine.state.cameraToken
            engine.cameraTrainingProgress(token: camera, blinkDetected: true, at: 31.1)
            engine.cameraTrainingProgress(token: camera, blinkDetected: false, at: 31.2)
            XCTAssertNil(engine.state.reminder)
            XCTAssertEqual(engine.state.cameraToken, replacement)
            XCTAssertFalse(engine.state.trainingSessionActive)
            if action == 2 { XCTAssertEqual(engine.state.cameraPurpose, .preview) }
        }
    }

    func testQueuedMeasurementStartsAfterWorkerCompletionWithoutAnimationWait() throws {
        var engine = ready()
        let camera = try XCTUnwrap(engine.state.cameraToken)
        XCTAssertNil(engine.startMeasurement(at: 30.1))
        XCTAssertTrue(engine.state.measurementRequested)
        engine.sample(cameraToken: camera, token: nil, at: 30.2, faceValid: true, blinkDurations: [0.2])
        engine.advance(to: 34)
        XCTAssertNil(engine.state.measurement)
        engine.cameraTrainingProgress(token: camera, blinkDetected: true, at: 34.1)
        XCTAssertNil(engine.state.reminder)
        engine.advance(to: 36)
        XCTAssertEqual(engine.state.cameraPurpose, .measurement)
        XCTAssertNotNil(engine.state.measurement)
    }

    func testNoFaceHidesPromptAndNextScheduledAttemptUsesFreshLease() throws {
        var engine = ready()
        let oldCamera = try XCTUnwrap(engine.state.cameraToken)
        engine.cameraDetectionFailed(token: oldCamera, reason: .noFace, at: 31.1)
        XCTAssertNil(engine.state.reminder)
        XCTAssertNil(engine.state.cameraToken)
        XCTAssertFalse(engine.state.trainingSessionActive)
        XCTAssertEqual(engine.state.trainingRemaining, 30)
        XCTAssertFalse(engine.retryTraining(at: 32))
        engine.cameraTrainingProgress(token: oldCamera, blinkDetected: true, at: 1000)
        engine.advance(to: 60)
        XCTAssertNil(engine.state.cameraToken)
        engine.advance(to: 62)
        let newCamera = try XCTUnwrap(engine.state.cameraToken)
        XCTAssertNotEqual(oldCamera, newCamera)
        engine.cameraDidStart(token: newCamera, at: 62)
        engine.cameraDetectionFailed(token: oldCamera, reason: .noFace, at: 1001)
        XCTAssertEqual(engine.state.cameraToken, newCamera)
        engine.cameraTrainingProgress(token: newCamera, blinkDetected: true, at: 62.1)
        XCTAssertNil(engine.state.reminder)
        XCTAssertNil(engine.state.cameraToken)
    }

    func testMissingFramesDoNotFabricateNoFaceOrObservationComplete() throws {
        for mgd in [false, true] {
            var engine = ready(mgd: mgd)
            let camera = try XCTUnwrap(engine.state.cameraToken)
            engine.advance(to: 100)
            XCTAssertEqual(engine.state.cameraToken, camera)
            XCTAssertTrue(engine.state.trainingSessionActive)
            XCTAssertNil(engine.state.lastDetectionFailure)
            XCTAssertEqual(engine.state.reminder, mgd ? .training(.interactive, mgd: true) : nil)
            engine.cameraTrainingProgress(token: camera, blinkDetected: false, at: 100.1)
            XCTAssertEqual(engine.state.reminder, .training(.interactive, mgd: mgd))
        }
    }
}
