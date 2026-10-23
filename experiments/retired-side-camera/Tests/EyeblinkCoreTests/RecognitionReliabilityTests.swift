import XCTest
@testable import EyeblinkCore

/// Deterministic geometry/contours only; no camera or human accuracy claim.
final class RecognitionReliabilityTests: XCTestCase {
    private let face = CGRect(x: 0.15, y: 0.2, width: 0.25, height: 0.35)

    func testAcquisitionRequiresWholeWindowStabilityInsteadOfAdjacentFrameStability() {
        var tracker = FaceTargetTracker(), time = 0.0
        for index in 0..<12 {
            time += 0.05
            let selection = tracker.select([face.offsetBy(dx: Double(index)*0.015, dy: 0)], at: time)
            XCTAssertEqual(selection.status, .acquiring, "Slow cumulative drift must not establish a stable target")
        }
        let settled = face.offsetBy(dx: 11*0.015, dy: 0)
        var selection: FaceTargetSelection!
        for _ in 0..<10 { time += 0.05; selection = tracker.select([settled], at: time) }
        XCTAssertEqual(selection.status, .tracking)
    }

    func testReacquisitionCannotWalkItsConfirmationWindowAwayFromLostAnchor() {
        var tracker = FaceTargetTracker(), time = 0.0
        for _ in 0..<10 { time += 0.05; _ = tracker.select([face], at: time) }
        let initial = tracker.select([face], at: time+0.05)
        time += 0.1
        XCTAssertEqual(tracker.select([], at: time).status, .lost)
        for index in 0..<5 {
            time += 0.1
            let selection = tracker.select([face.offsetBy(dx: Double(index)*0.024, dy: 0)], at: time)
            XCTAssertEqual(selection.status, .acquiring)
            XCTAssertEqual(selection.revision, initial.revision, "No new epoch until the entire confirmation window is stable")
        }
        var selection: FaceTargetSelection!
        for _ in 0..<10 { time += 0.05; selection = tracker.select([face.offsetBy(dx: 4*0.024, dy: 0)], at: time) }
        XCTAssertEqual(selection.status, .tracking)
        XCTAssertEqual(selection.revision, initial.revision+1)
    }

    private func checkGradualPoseChange(pitchChanges: Bool) {
        var detector = SideCameraBlinkDetector(preferSingleEye: true), time = 0.0
        func sample(_ pose: Double, aperture: Double = 0.3) -> SideCameraBlinkDetector.Output {
            time += 1/30.0
            return detector.process(.init(time: time, left: .init(aperture: aperture), right: nil,
                yaw: pitchChanges ? 25 : pose, pitch: pitchChanges ? pose : 0))
        }
        // Every adjacent step passes the existing per-frame motion gate, but
        // the total movement exceeds one calibration's pose range.
        for index in 0..<60 {
            let result = sample(Double(index)-30)
            XCTAssertFalse(result.valid)
            XCTAssertNotEqual(result.feedback.status, .calibrating, "An open-eye baseline cannot pool a long head turn")
            XCTAssertTrue(result.blinks.isEmpty)
        }
        for _ in 0..<50 { _ = sample(29) }
        for _ in 0..<3 {
            for _ in 0..<3 { XCTAssertTrue(sample(29, aperture: 0.03).blinks.isEmpty) }
            for _ in 0..<10 { XCTAssertTrue(sample(29).blinks.isEmpty) }
        }
        XCTAssertTrue(sample(29).valid, "Settling at the new pose must recover without a manual reset")
        var events: [Double] = []
        for _ in 0..<10 {
            for _ in 0..<3 { events += sample(29, aperture: 0.03).blinks }
            for _ in 0..<10 { events += sample(29).blinks }
        }
        XCTAssertEqual(events.count, 10)
    }

    func testGradualYawChangeCannotMixOpenEyeBaselinesAndSettlingRecovers() {
        checkGradualPoseChange(pitchChanges: false)
    }
    func testGradualPitchChangeCannotMixOpenEyeBaselinesAndSettlingRecovers() {
        checkGradualPoseChange(pitchChanges: true)
    }
}
