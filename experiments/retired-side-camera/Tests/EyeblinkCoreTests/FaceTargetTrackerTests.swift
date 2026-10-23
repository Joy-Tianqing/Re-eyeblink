import XCTest
@testable import EyeblinkCore

final class FaceTargetTrackerTests: XCTestCase {
    private let user = CGRect(x: 0.15, y: 0.25, width: 0.25, height: 0.35)
    private let other = CGRect(x: 0.65, y: 0.2, width: 0.3, height: 0.4)
    private func lock(_ t: inout FaceTargetTracker, boxes: [CGRect], time: inout Double) -> FaceTargetSelection {
        var result: FaceTargetSelection!
        for _ in 0..<6 { time += 0.1; result = t.select(boxes, at: time) }
        return result
    }
    func testStableSoleFaceIsRequiredBeforeTracking() {
        var t = FaceTargetTracker(), time = 0.0
        XCTAssertEqual(t.select([user], at: time).status, .acquiring)
        let result = lock(&t, boxes: [user], time: &time)
        XCTAssertEqual(result.status, .tracking); XCTAssertEqual(result.selectedIndex, 0)
    }
    func testBystanderAndInputReorderingDoNotReplaceTargetEvenWhenBystanderIsLarger() {
        var t = FaceTargetTracker(), time = 0.0
        let initial = lock(&t, boxes: [user], time: &time)
        for i in 0..<20 {
            time += 0.1
            let boxes = i % 2 == 0 ? [other,user] : [user,other]
            let result = t.select(boxes, at: time)
            XCTAssertEqual(result.status, .tracking)
            XCTAssertEqual(boxes[result.selectedIndex!], user)
            XCTAssertEqual(result.revision, initial.revision)
            XCTAssertEqual(result.visibleFaceCount, 2)
        }
    }
    func testInitialSimilarSizedGroupIsAmbiguousButStableDominantForegroundCanAcquire() {
        var t = FaceTargetTracker(), time = 0.0
        XCTAssertEqual(lock(&t, boxes: [user,other], time: &time).status, .ambiguous)
        let small = CGRect(x: 0.7,y: 0.3,width: 0.08,height: 0.1)
        XCTAssertEqual(lock(&t, boxes: [small,user], time: &time).selectedIndex, 1)
        XCTAssertEqual(t.select([small,user], at: time+0.1).status, .tracking)
    }
    func testMissingUserDoesNotJumpToOnlyRemainingBystander() {
        var t = FaceTargetTracker(), time = 0.0
        let initial = lock(&t, boxes: [user], time: &time)
        for _ in 0..<30 { time += 0.1; let r = t.select([other], at: time); XCTAssertEqual(r.status, .lost); XCTAssertNil(r.selectedIndex) }
        let returned = lock(&t, boxes: [user,other], time: &time)
        XCTAssertEqual(returned.status, .tracking)
        XCTAssertGreaterThan(returned.revision, initial.revision)
    }
    func testOverlappingCandidatesPauseAndRequireReconfirmation() {
        var t = FaceTargetTracker(), time = 0.0
        let initial = lock(&t, boxes: [user], time: &time)
        let crossing = user.offsetBy(dx: 0.01, dy: 0)
        time += 0.1
        XCTAssertEqual(t.select([user,crossing], at: time).status, .ambiguous)
        let returned = lock(&t, boxes: [user], time: &time)
        XCTAssertEqual(returned.status, .tracking); XCTAssertGreaterThan(returned.revision, initial.revision)
    }
    func testSmoothMovementTracksWithoutReacquiring() {
        var t = FaceTargetTracker(), time = 0.0
        let initial = lock(&t, boxes: [user], time: &time)
        for i in 1...30 {
            time += 0.1
            let result = t.select([user.offsetBy(dx: Double(i)*0.003,dy: 0)], at: time)
            XCTAssertEqual(result.status, .tracking); XCTAssertEqual(result.revision, initial.revision)
        }
    }
    func testLeaseReconfirmsAnchorAndExplicitResetAllowsNewTarget() {
        var t = FaceTargetTracker(), time = 0.0
        let initial = lock(&t, boxes: [user], time: &time)
        t.beginLease(); time += 10
        XCTAssertEqual(t.select([other,user], at: time).status, .acquiring)
        let same = lock(&t, boxes: [other,user], time: &time)
        XCTAssertEqual(same.revision, initial.revision); XCTAssertEqual(same.selectedIndex, 1)
        t.reset()
        let replacement = lock(&t, boxes: [other], time: &time)
        XCTAssertEqual(replacement.status, .tracking)
        XCTAssertGreaterThan(replacement.revision, initial.revision)
    }
    func testGapNonmonotonicTimeAndInvalidGeometryCannotBecomeTrustedFrames() {
        var t = FaceTargetTracker(), time = 0.0
        let initial = lock(&t, boxes: [user], time: &time)
        time += 1
        XCTAssertEqual(t.select([user], at: time).status, .acquiring)
        let renewed = lock(&t, boxes: [user], time: &time)
        XCTAssertGreaterThan(renewed.revision, initial.revision)
        XCTAssertEqual(t.select([user], at: time).status, .lost)
        t.reset()
        for invalid in [CGRect(x: .nan,y: 0,width: 0.2,height: 0.2), CGRect(x: -0.1,y: 0,width: 0.2,height: 0.2), .zero] {
            XCTAssertEqual(lock(&t, boxes: [invalid], time: &time).status, .none)
        }
    }
}
