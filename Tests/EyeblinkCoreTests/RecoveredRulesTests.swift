import XCTest
@testable import EyeblinkCore

final class RecoveredRulesTests: XCTestCase {
    func settings() -> AppSettings {
        var value = AppSettings()
        value.trainingEnabled = false; value.exerciseEnabled = false
        value.breakEnabled = false; value.measurementEnabled = false
        return value
    }
    func exactPolicy() -> EnginePolicy {
        var value = EnginePolicy(); value.startupQuietPeriod = 0; value.featurePollingInterval = 0.001
        return value
    }
    func testProductionPolicyKeepsRecoveredTimings() {
        let policy = EnginePolicy()
        XCTAssertEqual(policy.startupQuietPeriod, 15)
        XCTAssertEqual(policy.featurePollingInterval, 2)
        XCTAssertEqual(policy.naturalBreakCheckInterval, 60)
        XCTAssertEqual(policy.trainingObservationDuration, 4.001)
        XCTAssertEqual(policy.exerciseBreakSeparation, 301)
        XCTAssertEqual(policy.firstMeasurementDelay, 120)
        XCTAssertEqual(policy.measurementFailureDelay, 480)
        XCTAssertEqual(AppSettings().exerciseInterval, 1140)
    }
    func testStartupAndResumeRequireFifteenSecondGate() {
        var settings = settings(); settings.trainingEnabled = true
        settings.trainingMode = .simple; settings.trainingInterval = 1
        var engine = EyeblinkEngine(settings: settings)
        engine.advance(to: 14.999); XCTAssertNil(engine.state.reminder)
        engine.advance(to: 15); XCTAssertNotNil(engine.state.reminder)
        engine.setPaused(true, at: 16); engine.setPaused(false, at: 100)
        engine.advance(to: 114.999); XCTAssertNil(engine.state.reminder)
        engine.advance(to: 115); XCTAssertNotNil(engine.state.reminder)
    }
    func testSimpleReminderLastsThreeSecondsThenStartsNewInterval() {
        var settings = settings(); settings.trainingEnabled = true; settings.trainingMode = .simple
        var engine = EyeblinkEngine(settings: settings, policy: exactPolicy())
        engine.advance(to: 30); XCTAssertNotNil(engine.state.reminder)
        engine.advance(to: 32.999); XCTAssertNotNil(engine.state.reminder)
        engine.advance(to: 33); XCTAssertNil(engine.state.reminder)
        engine.advance(to: 62.999); XCTAssertNil(engine.state.reminder)
        engine.advance(to: 63); XCTAssertNotNil(engine.state.reminder)
    }
    func testCameraDisabledDoesNotContinuouslyResetSimpleReminderDeadline() {
        var settings = settings(); settings.trainingEnabled = true; settings.cameraEnabled = false
        var engine = EyeblinkEngine(settings: settings, policy: exactPolicy())
        for time in 1...30 { engine.advance(to: Double(time)) }
        XCTAssertEqual(engine.state.reminder, .training(.simple, mgd: false))
        XCTAssertNil(engine.state.cameraPurpose)
    }
    func testInteractiveCameraOpensOnlyWhenDueAndWaitsForBlinkAfterTimeout() {
        var settings = settings(); settings.trainingEnabled = true
        var engine = EyeblinkEngine(settings: settings, policy: exactPolicy())
        engine.advance(to: 29.999); XCTAssertNil(engine.state.cameraPurpose)
        engine.advance(to: 30); XCTAssertEqual(engine.state.cameraPurpose, .training)
        let token = engine.state.cameraToken!
        engine.cameraDidStart(token: token, at: 30)
        for time in 30...34 { engine.sample(cameraToken: token, token: nil, at: Double(time), faceValid: true, blinkDurations: []) }
        engine.advance(to: 34); XCTAssertNil(engine.state.reminder)
        engine.advance(to: 34.001); XCTAssertNil(engine.state.reminder)
        engine.cameraTrainingProgress(token: token, blinkDetected: false, at: 34.001)
        XCTAssertNotNil(engine.state.reminder)
        for time in 35...39 { engine.sample(cameraToken: token, token: nil, at: Double(time), faceValid: true, blinkDurations: []) }
        engine.advance(to: 40); XCTAssertEqual(engine.state.cameraToken, token)
        // Callback timestamp can precede a timer tick without being an old camera lease.
        engine.sample(cameraToken: token, token: nil, at: 39.99, faceValid: true, blinkDurations: [0.15])
        XCTAssertEqual(engine.state.cameraToken, token)
        engine.cameraTrainingProgress(token: token, blinkDetected: true, at: 39.995)
        XCTAssertNil(engine.state.cameraPurpose)
        XCTAssertNil(engine.state.reminder)
        XCTAssertEqual(engine.state.trainingRemaining, 30)
    }
    func testMGDShowsImmediatelyAndOnlySoundsOnce() {
        var settings = settings(); settings.trainingEnabled = true; settings.mgdEnabled = true
        settings.reminderSoundEnabled = true
        var engine = EyeblinkEngine(settings: settings, policy: exactPolicy())
        engine.advance(to: 30)
        XCTAssertNil(engine.state.reminder)
        engine.cameraDidStart(token: engine.state.cameraToken!, at: 30)
        let camera = engine.state.cameraToken!
        for time in 30...34 { engine.sample(cameraToken: camera, token: nil, at: Double(time), faceValid: true, blinkDurations: []) }
        XCTAssertEqual(engine.state.reminder, .training(.interactive, mgd: true))
        XCTAssertEqual(engine.takeEffects(), [.playReminderSound])
        engine.advance(to: 34.001)
        engine.cameraTrainingProgress(token: camera, blinkDetected: false, at: 34.001)
        engine.cameraTrainingProgress(token: camera, blinkDetected: false, at: 34.1)
        XCTAssertEqual(engine.state.reminder, .training(.interactive, mgd: true))
        XCTAssertTrue(engine.takeEffects().isEmpty)
    }
    func testBusyTrainingIsNotPreemptedThenMeasurementHasPriority() {
        var settings = settings(); settings.trainingEnabled = true; settings.trainingInterval = 1
        settings.measurementEnabled = true; settings.measurementInterval = 2
        settings.breakEnabled = true; settings.breakInterval = 3
        var policy = exactPolicy(); policy.firstMeasurementDelay = 2
        var engine = EyeblinkEngine(settings: settings, policy: policy)
        engine.advance(to: 1)
        let camera = engine.state.cameraToken!
        engine.advance(to: 5.001)
        XCTAssertEqual(engine.state.cameraPurpose, .training)
        XCTAssertNil(engine.state.measurement)
        engine.sample(cameraToken: camera, token: nil, at: 5.1, faceValid: true, blinkDurations: [0.2])
        engine.cameraTrainingProgress(token: camera, blinkDetected: true, at: 5.1005)
        engine.advance(to: 5.101)
        XCTAssertEqual(engine.state.cameraPurpose, .measurement)
        XCTAssertNil(engine.state.reminder)
    }
    func testNoFaceErrorCancelsInsteadOfRecordingFakeZero() {
        var engine = EyeblinkEngine(settings: settings(), policy: exactPolicy())
        let id = engine.startMeasurement(at: 0)!, camera = engine.state.cameraToken!
        engine.sample(cameraToken: camera, token: id, at: 0, faceValid: false, blinkDurations: [])
        engine.sample(cameraToken: camera, token: id, at: 8, faceValid: false, blinkDurations: [])
        XCTAssertNotNil(engine.state.measurement)
        engine.cameraDetectionFailed(token: camera, reason: .noFace, at: 8.001)
        XCTAssertNil(engine.state.measurement)
        XCTAssertEqual(engine.takeEffects(), [.measurementCancelled(id)])
        XCTAssertEqual(engine.state.lastDetectionFailure, "measurement-no-face")
    }
    func testSourceMeasurementUsesElapsedThresholdAndFixedThreeMinuteRate() {
        var engine = EyeblinkEngine(settings: settings(), policy: exactPolicy())
        let id = engine.startMeasurement(at: 0)!, camera = engine.state.cameraToken!
        for frame in 0...720 {
            let time = Double(frame) / 4
            engine.sample(cameraToken: camera, token: id, at: time, faceValid: true, blinkDurations: [4, 8, 12].contains(frame) ? [0.15] : [])
        }
        XCTAssertNotNil(engine.state.measurement)
        engine.cameraMeasurementFinished(token: camera, at: 180.001)
        guard case .measurementCompleted(let record) = engine.takeEffects().first else { return XCTFail("Expected elapsed measurement") }
        XCTAssertEqual(record.bpm, 1)
        XCTAssertEqual(record.validDuration, 180.001)
        XCTAssertEqual(record.blinkDurations.count, 3)
    }
    func testNaturalThresholdIsStrictAndStillClosesCurrentRestWhenCreditsDisabled() {
        var settings = settings(); settings.breakEnabled = true; settings.breakInterval = 10
        settings.naturalBreaksEnabled = false
        var engine = EyeblinkEngine(settings: settings, policy: exactPolicy())
        engine.advance(to: 10)
        engine.advance(to: 60, idleDuration: 60)
        engine.advance(to: 120, idleDuration: 120)
        engine.advance(to: 180, idleDuration: 180)
        XCTAssertNotNil(engine.state.reminder)
        engine.advance(to: 239.999, idleDuration: 239.999)
        XCTAssertNotNil(engine.state.reminder)
        engine.advance(to: 240, idleDuration: 240)
        XCTAssertNil(engine.state.reminder)
        XCTAssertEqual(engine.state.exerciseRemaining, 1140)
    }
    func testExerciseSuppressedIfBreakIsLessThan301SecondsAway() {
        var settings = settings(); settings.exerciseEnabled = true; settings.exerciseInterval = 10
        settings.breakEnabled = true; settings.breakInterval = 310
        var engine = EyeblinkEngine(settings: settings, policy: exactPolicy())
        engine.advance(to: 10)
        XCTAssertNil(engine.state.reminder)
        settings.breakInterval = 311
        var boundary = EyeblinkEngine(settings: settings, policy: exactPolicy())
        boundary.advance(to: 10)
        XCTAssertEqual(boundary.state.reminder, .exercise(.lookFar, secondsRemaining: 10))
    }
    func testDeviceRestartRotatesLeaseWithoutWritingPreviewSamples() {
        var engine = EyeblinkEngine(settings: settings(), policy: exactPolicy())
        engine.setPreview(true, at: 0)
        let oldToken = engine.state.cameraToken!
        engine.invalidateCamera(at: 1)
        XCTAssertNotEqual(engine.state.cameraToken, oldToken)
        XCTAssertEqual(engine.state.cameraPurpose, .preview)
        engine.sample(cameraToken: oldToken, token: nil, at: 2, faceValid: true, blinkDurations: [0.2])
        XCTAssertTrue(engine.takeEffects().isEmpty)
    }
    func testUIActionWithoutIdleSampleCannotConsumeNaturalBreakPollingSlot() {
        var settings = settings(); settings.breakEnabled = true; settings.breakInterval = 10
        settings.naturalBreakDuration = 1
        var engine = EyeblinkEngine(settings: settings, policy: exactPolicy())
        engine.advance(to: 10, idleDuration: 0)
        engine.advance(to: 60)
        XCTAssertNotNil(engine.state.reminder)
        engine.advance(to: 60, idleDuration: 61)
        XCTAssertNil(engine.state.reminder)
    }
    func testAutomaticMeasurementUsesTwoMinuteInitialDelayAndEightMinuteFailureDelay() {
        var settings = settings(); settings.measurementEnabled = true
        var engine = EyeblinkEngine(settings: settings, policy: exactPolicy())
        engine.advance(to: 119.999); XCTAssertNil(engine.state.measurement)
        engine.advance(to: 120); XCTAssertNotNil(engine.state.measurement)
        let token = engine.state.cameraToken!, id = engine.state.measurement!.id
        engine.sample(cameraToken: token, token: id, at: 120, faceValid: false, blinkDurations: [])
        engine.cameraDetectionFailed(token: token, reason: .noFace, at: 128.001)
        XCTAssertNil(engine.state.measurement)
        XCTAssertEqual(engine.state.measurementRemaining, 480)
        engine.advance(to: 608); XCTAssertNil(engine.state.measurement)
        engine.advance(to: 608.001); XCTAssertNotNil(engine.state.measurement)
    }
    func testChangingBreakIntervalPreservesProgressAndDisabledBreakStillSuppressesExercise() {
        var settings = settings(); settings.breakEnabled = true; settings.breakInterval = 100
        var engine = EyeblinkEngine(settings: settings, policy: exactPolicy())
        engine.advance(to: 20)
        settings.breakInterval = 200; engine.updateSettings(settings, at: 20)
        XCTAssertEqual(engine.state.breakRemaining, 180)
        settings.breakEnabled = false; settings.exerciseEnabled = true; settings.exerciseInterval = 1
        engine.updateSettings(settings, at: 20); engine.advance(to: 21)
        XCTAssertNil(engine.state.reminder)
    }
    func testEnablingMeasurementStartsInitialDelayWithoutChangingSavedInterval() {
        var settings = settings()
        var engine = EyeblinkEngine(settings: settings, policy: exactPolicy())
        settings.measurementEnabled = true; engine.updateSettings(settings, at: 10)
        XCTAssertEqual(engine.state.measurementRemaining, 120)
        XCTAssertEqual(engine.settings.measurementInterval, 1800)
    }
}
