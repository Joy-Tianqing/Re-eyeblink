import XCTest
@testable import EyeblinkCore

/// Synthetic visible-eye evidence. These tests do not establish real-camera accuracy.
final class SideCameraVisibilityTests: XCTestCase {
    private func run(yaw: Double, pitch: Double = 0, roll: Double = 0, leftVisible: Bool, rightVisible: Bool) -> (SideCameraBlinkDetector.Output, [Double]) {
        var d = SideCameraBlinkDetector(), time = 0.0
        func feed(_ aperture: Double, frames: Int) -> SideCameraBlinkDetector.Output {
            var output: SideCameraBlinkDetector.Output?
            for _ in 0..<frames {
                time += 1/30.0
                output = d.process(.init(time: time,
                    left: leftVisible ? .init(aperture: aperture) : nil,
                    right: rightVisible ? .init(aperture: aperture*0.65) : nil,
                    yaw: yaw, pitch: pitch, roll: roll))
            }
            return output!
        }
        _ = feed(0.3, frames: 50)
        for _ in 0..<3 { _ = feed(0.03, frames: 3); _ = feed(0.3, frames: 10) }
        let calibrated = feed(0.3, frames: 10)
        _ = feed(0.03, frames: 3)
        let blink = feed(0.3, frames: 1)
        return (calibrated, blink.blinks)
    }
    func testOnlyLeftEyeCanCalibrateAndEmitOneVisibleEyeClosure() {
        let (ready, events) = run(yaw: 30, leftVisible: true, rightVisible: false)
        XCTAssertTrue(ready.valid); XCTAssertEqual(ready.feedback.calibrationBlinks, 3)
        XCTAssertEqual(events.count, 1)
    }
    func testOnlyRightEyeCanCalibrateAtStableHighYaw() {
        let (ready, events) = run(yaw: 51, leftVisible: false, rightVisible: true)
        XCTAssertTrue(ready.valid); XCTAssertEqual(events.count, 1)
    }
    func testStablePoseWithBothResolvedEyesIsNotRejectedJustForAbsoluteAngles() {
        for (yaw,pitch,roll) in [(45.0,0.0,0.0),(-51,0,0),(20,30,0),(20,0,40)] {
            let (ready, events) = run(yaw: yaw, pitch: pitch, roll: roll, leftVisible: true, rightVisible: true)
            XCTAssertTrue(ready.valid, "\(yaw)/\(pitch)/\(roll)")
            XCTAssertEqual(events.count, 1)
        }
    }
    func testNoResolvedEyeCannotCalibrateOrEmit() {
        let (ready, events) = run(yaw: 30, leftVisible: false, rightVisible: false)
        XCTAssertFalse(ready.valid); XCTAssertTrue(events.isEmpty)
    }
    private struct Harness {
        var detector: SideCameraBlinkDetector
        var time = 0.0
        init(preferSingleEye: Bool = false) { detector = .init(preferSingleEye: preferSingleEye) }
        mutating func feed(left: Double? = 0.3, right: Double? = 0.195, leftWidth: Double = 40, rightWidth: Double = 30, frames: Int = 1, yaw: Double = 48, pitch: Double = 0) -> SideCameraBlinkDetector.Output {
            var result: SideCameraBlinkDetector.Output!
            for _ in 0..<frames {
                time += 1/30.0
                result = detector.process(.init(time: time,
                    left: left.map { .init(aperture: $0, width: leftWidth) },
                    right: right.map { .init(aperture: $0, width: rightWidth) }, yaw: yaw, pitch: pitch))
            }
            return result
        }
        mutating func calibrate(right: Double? = 0.195, yaw: Double = 48, pitch: Double = 0) {
            _ = feed(right: right, frames: 50, yaw: yaw, pitch: pitch)
            for _ in 0..<3 {
                _ = feed(left: 0.03, right: right.map { $0 * 0.1 }, frames: 3, yaw: yaw, pitch: pitch)
                let result = feed(right: right, frames: 10, yaw: yaw, pitch: pitch)
                XCTAssertTrue(result.blinks.isEmpty, "Calibration never contributes an event")
            }
            XCTAssertTrue(feed(right: right, frames: 10, yaw: yaw, pitch: pitch).valid)
        }
    }
    func testPreferredSingleEyeRemainsLockedAcrossWidthJitterAndOtherEyeStayingOpen() {
        var h = Harness(preferSingleEye: true); h.calibrate()
        XCTAssertEqual(h.feed().feedback.observationMode, .left)
        _ = h.feed(left: 0.03, right: 0.195, leftWidth: 20, rightWidth: 60, frames: 3)
        let result = h.feed(leftWidth: 20, rightWidth: 60)
        XCTAssertEqual(result.feedback.observationMode, .left)
        XCTAssertEqual(result.blinks.count, 1, "A visible-eye closure is an estimate even if the other eye stays open")
    }
    func testSwitchingVisibleEyeCannotCompleteHalfBlinkAndRequiresOwnCalibration() {
        var h = Harness(); h.calibrate(right: nil)
        _ = h.feed(left: 0.03, right: nil, frames: 3)
        let changed = h.feed(left: nil, right: 0.195, frames: 50)
        XCTAssertFalse(changed.valid); XCTAssertTrue(changed.blinks.isEmpty)
        XCTAssertEqual(changed.feedback.observationMode, .right)
        XCTAssertEqual(changed.feedback.calibrationBlinks, 0)
    }
    func testSingleEyeOcclusionGapLongClosureAndLeaseResetCannotFinishCandidate() {
        for interruption in 0..<4 {
            var h = Harness(); h.calibrate(right: nil)
            _ = h.feed(left: 0.03, right: nil, frames: 3)
            switch interruption {
            case 0: _ = h.feed(left: nil, right: nil)
            case 1: h.time += 1
            case 2: _ = h.feed(left: 0.03, right: nil, frames: 40)
            default: h.detector.reset(keepCalibration: true)
            }
            for _ in 0..<30 { XCTAssertTrue(h.feed(right: nil).blinks.isEmpty) }
        }
    }
    func testUnresolvableOrNonfiniteEyeIsNotAClosedEye() {
        for width in [9.0, Double.nan] {
            var h = Harness()
            let result = h.feed(left: 0, right: nil, leftWidth: width, frames: 80)
            XCTAssertFalse(result.valid); XCTAssertEqual(result.feedback.status, .eyesUnavailable)
        }
        var h = Harness()
        XCTAssertFalse(h.feed(left: .nan, right: nil, frames: 80).valid)
    }
    func testAutomaticFallbackUsesResolvableLargerEyeAndReturnsToBothWithHysteresis() {
        var h = Harness()
        XCTAssertEqual(h.feed(leftWidth: 40, rightWidth: 20).feedback.observationMode, .left)
        XCTAssertEqual(h.feed(leftWidth: 40, rightWidth: 28).feedback.observationMode, .left)
        XCTAssertEqual(h.feed(leftWidth: 40, rightWidth: 32).feedback.observationMode, .both)
    }
    func testPolicyChangeDoesNotReuseSingleEyeCalibrationAsBothEyeCalibration() {
        var h = Harness(preferSingleEye: true); h.calibrate()
        h.detector.reset(keepCalibration: true, preferSingleEye: false)
        let result = h.feed(frames: 50)
        XCTAssertFalse(result.valid); XCTAssertEqual(result.feedback.observationMode, .both)
        XCTAssertEqual(result.feedback.calibrationBlinks, 0)
    }

    func testCalibratedSingleEyeEventStartsFeedbackBeforeDismissingReminder() throws {
        let (_, events) = run(yaw: 48, leftVisible: true, rightVisible: false)
        XCTAssertEqual(events.count, 1)
        var settings = AppSettings()
        settings.trainingEnabled = true; settings.trainingMode = .interactive; settings.mgdEnabled = true
        settings.exerciseEnabled = false; settings.breakEnabled = false; settings.measurementEnabled = false
        var policy = EnginePolicy(); policy.startupQuietPeriod = 0; policy.featurePollingInterval = 0.001
        var engine = EyeblinkEngine(settings: settings, policy: policy)
        engine.advance(to: 30)
        let token = try XCTUnwrap(engine.state.cameraToken)
        engine.cameraDidStart(token: token, at: 30)
        for time in 30...34 { engine.sample(cameraToken: token, token: nil, at: Double(time), faceValid: true, blinkDurations: []) }
        XCTAssertNotNil(engine.state.reminder)
        engine.sample(cameraToken: token, token: nil, at: 34.1, faceValid: true, blinkDurations: events)
        let feedback = try XCTUnwrap(engine.state.reminder?.trainingFeedbackID)
        XCTAssertNil(engine.state.cameraPurpose)
        XCTAssertTrue(engine.finishTrainingFeedback(id: feedback, at: 35.1))
        XCTAssertNil(engine.state.reminder)
    }

    func testCachedPoseWithCloserYawButWrongPitchCannotHideReadyCalibration() {
        var h = Harness(preferSingleEye: true); h.calibrate(yaw: 43, pitch: -17)
        XCTAssertFalse(h.feed(frames: 50, yaw: 48, pitch: 20).valid)
        let returned = h.feed(frames: 15, yaw: 47, pitch: -15)
        XCTAssertTrue(returned.valid)
        XCTAssertEqual(returned.feedback.calibrationBlinks, 3)
    }
    func testSmallPoseJitterKeepsActiveReadyBaselineInsteadOfIncompleteNeighbor() {
        var h = Harness(preferSingleEye: true); h.calibrate(yaw: 40)
        XCTAssertFalse(h.feed(frames: 50, yaw: 60).valid)
        XCTAssertTrue(h.feed(frames: 15, yaw: 40).valid)
        XCTAssertTrue(h.feed(frames: 10, yaw: 44).valid)
        XCTAssertTrue(h.feed(frames: 10, yaw: 49).valid)
        _ = h.feed(left: 0.03, frames: 3, yaw: 49)
        XCTAssertEqual(h.feed(yaw: 49).blinks.count, 1)
    }

    func testUnverifiedPoseExplorationCannotEvictVerifiedCalibration() {
        var h = Harness(preferSingleEye: true); h.calibrate(yaw: 40, pitch: 0)
        for yaw in [-40.0, -20, 0, 20, 40, 60] {
            XCTAssertFalse(h.feed(frames: 50, yaw: yaw, pitch: 20).valid)
        }
        let returned = h.feed(frames: 15, yaw: 40, pitch: 0)
        XCTAssertTrue(returned.valid, "Unverified poses must not replace the only verified baseline")
        XCTAssertEqual(returned.feedback.calibrationBlinks, 3)
    }

    func testVerifiedPoseHysteresisDoesNotRecalibrateAtWindowEdge() {
        var h = Harness(preferSingleEye: true); h.calibrate(yaw: 40)
        XCTAssertTrue(h.feed(frames: 10, yaw: 50).valid)
        for yaw in [51.0, 53, 51, 53] {
            let result = h.feed(frames: 10, yaw: yaw)
            XCTAssertTrue(result.valid, "Small jitter at the calibrated-pose boundary should not flap")
            XCTAssertTrue(result.blinks.isEmpty)
        }
        XCTAssertFalse(h.feed(frames: 10, yaw: 57).valid, "Hysteresis is finite, not permission to reuse any pose")
    }

}
