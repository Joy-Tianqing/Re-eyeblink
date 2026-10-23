import XCTest
@testable import EyeblinkCore

/// Numeric geometry and labelled synthetic eye closures, not human accuracy.
final class PrimaryTargetBlinkTests: XCTestCase {
    private struct Run {
        var tracker = FaceTargetTracker()
        var detector = SideCameraBlinkDetector(preferSingleEye: true)
        var time = 0.0
        var last: SideCameraBlinkDetector.Output?
        let user = CGRect(x: 0.15,y: 0.2,width: 0.25,height: 0.35)
        let other = CGRect(x: 0.65,y: 0.2,width: 0.3,height: 0.4)
        mutating func feed(aperture: Double = 0.3, frames: Int, bystander: Bool = false, missing: Bool = false, ambiguous: Bool = false) -> [Double] {
            var events: [Double] = []
            for i in 0..<frames {
                time += 1/30.0
                let boxes = missing ? [other] : ambiguous ? [user,user.offsetBy(dx: 0.01,dy: 0)] : bystander ? (i % 2 == 0 ? [other,user] : [user,other]) : [user]
                let selected = tracker.select(boxes, at: time)
                // The secondary face is open. If the selector jumped to it, a
                // user closure would disappear; the ten-event assertion fails.
                let eye = selected.selectedIndex.map { boxes[$0] == user ? aperture : 0.3 }
                last = detector.process(.init(time: time, left: eye.map { .init(aperture: $0) }, right: nil,
                    yaw: 25, faceCenter: .init(x: user.midX,y: user.midY), faceWidth: user.width,
                    faceCount: selected.selectedIndex == nil ? 0 : 1, target: selected))
                events += last!.blinks
            }
            return events
        }
        mutating func calibrate() {
            XCTAssertTrue(feed(frames: 60).isEmpty)
            for _ in 0..<3 {
                XCTAssertTrue(feed(aperture: 0.03, frames: 3).isEmpty)
                XCTAssertTrue(feed(frames: 10).isEmpty)
            }
            XCTAssertTrue(last!.valid)
        }
    }
    func testBystanderCannotConsumeUsersBlinkOrResetCalibrationAcrossTenClosures() {
        var run = Run(); run.calibrate()
        var events: [Double] = []
        for _ in 0..<10 {
            events += run.feed(aperture: 0.03, frames: 3, bystander: true)
            events += run.feed(frames: 10, bystander: true)
            XCTAssertTrue(run.last!.valid); XCTAssertEqual(run.last!.feedback.calibrationBlinks, 3)
        }
        XCTAssertEqual(events.count, 10)
        XCTAssertEqual(run.last?.feedback.target?.visibleFaceCount, 2)
    }
    func testTargetLossOrAmbiguityCannotCompleteHalfBlinkAndReacquisitionRequiresCalibration() {
        for ambiguous in [false,true] {
            var run = Run(); run.calibrate()
            _ = run.feed(aperture: 0.03, frames: 3)
            XCTAssertTrue(run.feed(frames: 4, missing: !ambiguous, ambiguous: ambiguous).isEmpty)
            XCTAssertFalse(run.last!.valid)
            XCTAssertTrue(run.feed(frames: 60).isEmpty)
            XCTAssertFalse(run.last!.valid); XCTAssertEqual(run.last!.feedback.calibrationBlinks, 0)
        }
    }
    func testFreshLeaseKeepsVerifiedTargetButNeverItsHalfBlink() {
        var run = Run(); run.calibrate()
        _ = run.feed(aperture: 0.03, frames: 3)
        run.tracker.beginLease(); run.detector.reset(keepCalibration: true); run.time += 3
        XCTAssertTrue(run.feed(frames: 60, bystander: true).isEmpty)
        XCTAssertTrue(run.last!.valid); XCTAssertEqual(run.last!.feedback.calibrationBlinks, 3)
    }
    func testStaleDifferentTargetRevisionCannotBypassMonotonicFrameGuard() {
        var run = Run(); run.calibrate()
        let oldTime = run.time
        let epoch = run.last!.feedback.target!.revision
        let stale = run.detector.process(.init(time: oldTime-1,left: .init(aperture: 0.3),right: nil,
            target: .init(status: .tracking,visibleFaceCount: 1,selectedIndex: 0,revision: epoch+1)))
        XCTAssertFalse(stale.valid)
        _ = run.feed(frames: 20)
        XCTAssertTrue(run.last!.valid); XCTAssertEqual(run.last!.feedback.calibrationBlinks, 3)
    }
    func testFullDurationBystanderStreamRetainsCoverageAndVersionedProvenance() throws {
        var run = Run(); run.calibrate()
        var coverage = SideCameraCoverage(); coverage.start(at: run.time)
        let start = run.time
        for _ in 0..<5400 {
            _ = run.feed(frames: 1, bystander: true)
            coverage.observe(at: run.time, valid: run.last!.valid, observationMode: run.last!.feedback.observationMode)
        }
        let report = coverage.report(at: run.time)
        XCTAssertEqual(run.time-start, 180, accuracy: 1e-8)
        XCTAssertGreaterThan(report.validFrameFraction, 0.99)
        XCTAssertEqual(report.algorithm, "side-contour-v4"); XCTAssertEqual(report.targeting, "spatial-primary-v2")
        XCTAssertTrue(report.isMonocularEstimate)
        XCTAssertEqual(try JSONDecoder().decode(MeasurementDetection.self, from: JSONEncoder().encode(report)), report)
    }
}
