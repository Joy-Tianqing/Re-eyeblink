import XCTest
@testable import EyeblinkCore

final class SideCameraBlinkTests: XCTestCase {
    private func eye(_ value: Double) -> EyeContourMeasurement { .init(aperture: value) }
    private func feed(_ d: inout SideCameraBlinkDetector, time: inout Double, left: Double = 0.3, right: Double = 0.18,
                      frames: Int, yaw: Double = 22, shift: Double = 0) -> [Double] {
        var blinks: [Double] = []
        for _ in 0..<frames {
            time += 1 / 30.0
            blinks += d.process(.init(time: time, left: eye(left), right: eye(right), yaw: yaw,
                                     faceCenter: .init(x: 0.5 + shift, y: 0.5))).blinks
        }
        return blinks
    }
    private func calibrated(yaw: Double = 22) -> (SideCameraBlinkDetector, Double) {
        var d = SideCameraBlinkDetector(), time = 0.0
        XCTAssertTrue(feed(&d, time: &time, frames: 50, yaw: yaw).isEmpty)
        for _ in 0..<3 {
            XCTAssertTrue(feed(&d, time: &time, left: 0.05, right: 0.025, frames: 3, yaw: yaw).isEmpty)
            XCTAssertTrue(feed(&d, time: &time, frames: 10, yaw: yaw).isEmpty)
        }
        let value = d.process(.init(time: time + 0.01, left: eye(0.3), right: eye(0.18), yaw: yaw))
        XCTAssertEqual(value.feedback.status, .ready); XCTAssertTrue(value.valid)
        return (d, time + 0.01)
    }
    func testEyeApertureIsInvariantToTranslationRollScaleAndMirroring() throws {
        let points = [CGPoint(x: -20,y: 0), .init(x: -10,y: 6), .init(x: 10,y: 6), .init(x: 20,y: 0), .init(x: 10,y: -6), .init(x: -10,y: -6)]
        let base = try XCTUnwrap(EyeContourMeasurement(points: points))
        for angle in [-0.5, 0, 0.5] { for scale in [0.8, 1.5] { for mirror in [-1.0, 1.0] {
            let transformed = points.map { p -> CGPoint in
                let x = Double(p.x) * mirror, y = Double(p.y)
                let rotatedX = x * cos(angle) - y * sin(angle)
                let rotatedY = x * sin(angle) + y * cos(angle)
                return CGPoint(x: rotatedX * scale + 100, y: rotatedY * scale + 200)
            }
            XCTAssertEqual(try XCTUnwrap(EyeContourMeasurement(points: transformed)).aperture, base.aperture, accuracy: 1e-12)
        } } }
        XCTAssertNotNil(EyeContourMeasurement(points: points.map { .init(x: $0.x,y: 0) }))
        XCTAssertNil(EyeContourMeasurement(points: Array(points.prefix(4))))
    }
    func testThreeCalibrationBlinksAreNotStatisticsThenAsymmetricEyesEmitOnce() {
        var (d, time) = calibrated()
        XCTAssertTrue(feed(&d, time: &time, left: 0.05, right: 0.025, frames: 3).isEmpty)
        let events = feed(&d, time: &time, frames: 10)
        XCTAssertEqual(events.count, 1); XCTAssertEqual(events.first ?? 0, 0.1, accuracy: 1e-9)
    }
    func testWinkAndLongClosureDoNotCount() {
        var (d, time) = calibrated()
        XCTAssertTrue(feed(&d, time: &time, left: 0.03, frames: 5).isEmpty)
        XCTAssertTrue(feed(&d, time: &time, frames: 10).isEmpty)
        XCTAssertTrue(feed(&d, time: &time, left: 0.03, right: 0.02, frames: 40).isEmpty)
        XCTAssertTrue(feed(&d, time: &time, frames: 10).isEmpty)
    }
    func testBothCameraSidesAtTargetAnglesCountTenClosuresOnceEach() {
        for yaw in [-30.0, -15, 15, 30] {
            var (d, time) = calibrated(yaw: yaw)
            var events: [Double] = []
            for _ in 0..<10 {
                events += feed(&d, time: &time, left: 0.05, right: 0.025, frames: 3, yaw: yaw)
                events += feed(&d, time: &time, frames: 10, yaw: yaw)
            }
            XCTAssertEqual(events.count, 10, "Synthetic contour sequence, yaw=\(yaw)")
        }
    }
    func testPoseJumpGapOcclusionAndLeaseResetCannotCompleteHalfBlink() {
        for interruption in 0..<4 {
            var (d, time) = calibrated()
            _ = feed(&d, time: &time, left: 0.03, right: 0.02, frames: 3)
            if interruption == 0 { _ = feed(&d, time: &time, frames: 1, yaw: 35) }
            if interruption == 1 { time += 1 }
            if interruption == 2 { time += 1/30.0; _ = d.process(.init(time: time, left: eye(0.3), right: nil, yaw: 22)) }
            if interruption == 3 { d.reset(keepCalibration: true) }
            XCTAssertTrue(feed(&d, time: &time, frames: 20).isEmpty)
            if interruption == 3 {
                let resumed = d.process(.init(time: time+0.01, left: eye(0.3), right: eye(0.18), yaw: 22))
                XCTAssertTrue(resumed.valid, "A new lease keeps numeric calibration, never its half-blink")
            }
        }
    }
    func testRigidTranslationDoesNotCountAndMissingPoseIsNotZeroDegrees() {
        var (d, time) = calibrated()
        for i in 0..<30 { XCTAssertTrue(feed(&d, time: &time, frames: 1, shift: Double(i)*0.001).isEmpty) }
        let result = d.process(.init(time: time+0.1, left: eye(0.3), right: eye(0.18), yaw: nil))
        XCTAssertEqual(result.feedback.status, .poseUnavailable); XCTAssertFalse(result.valid)
    }
    func testLargePoseJumpInvalidatesCandidateBeforeRecalibration() {
        var (d, time) = calibrated()
        _ = feed(&d, time: &time, left: 0.03, right: 0.02, frames: 3)
        let result = d.process(.init(time: time+0.03, left: eye(0.3), right: eye(0.18), yaw: 41))
        XCTAssertEqual(result.feedback.status, .moving)
        XCTAssertFalse(result.valid); XCTAssertTrue(result.blinks.isEmpty)
    }
    func testClosedEyesCannotCalibrateAndNewPoseNeedsNewBaseline() {
        var d = SideCameraBlinkDetector(), t = 0.0
        XCTAssertTrue(feed(&d, time: &t, left: 0.01, right: 0.01, frames: 100).isEmpty)
        var (ready, time) = calibrated()
        _ = feed(&ready, time: &time, frames: 30, yaw: -20)
        let result = ready.process(.init(time: time+0.02, left: eye(0.3), right: eye(0.18), yaw: -20))
        XCTAssertFalse(result.valid)
        ready.reset()
        _ = feed(&ready, time: &time, frames: 50)
        XCTAssertFalse(ready.process(.init(time: time+0.02, left: eye(0.3), right: eye(0.18), yaw: 22)).valid,
                       "An explicit recalibration removes old readiness")
    }
    func testCoverageDoesNotBridgeInvalidOrMissingFrames() {
        var c = SideCameraCoverage(); c.start(at: 0)
        for i in 0...100 { c.observe(at: Double(i)*0.1, valid: true) }
        XCTAssertEqual(c.report(at: 10).validFrameFraction, 1, accuracy: 1e-9)
        XCTAssertFalse(c.report(at: 20).isAcceptable)
        c.observe(at: 20, valid: true)
        XCTAssertEqual(c.report(at: 20).validFrameFraction, 0.5, accuracy: 1e-9)
        c.observe(at: 20.1, valid: false); c.observe(at: 20.2, valid: true)
        XCTAssertEqual(c.report(at: 20.2).validFrameFraction, 10/20.2, accuracy: 1e-9)
    }
}
