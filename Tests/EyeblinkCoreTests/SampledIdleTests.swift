import XCTest
@testable import EyeblinkCore

final class SampledIdleTests: XCTestCase {
    func testActivityIsRecordedAtSampleTimeAndNotAtIntermediateFrames() {
        var tracker = SampledIdleTracker(now: 0, cursor: .zero, keyCount: 5)
        XCTAssertEqual(tracker.observe(at: 30, cursor: .init(x: 10, y: 10), keyCount: 6), 30)
        XCTAssertEqual(tracker.observe(at: 60, cursor: .init(x: 10, y: 10), keyCount: 6), 0)
        XCTAssertEqual(tracker.observe(at: 120, cursor: .init(x: 10, y: 10), keyCount: 6), 60)
        XCTAssertEqual(tracker.observe(at: 180, cursor: .init(x: 10, y: 10), keyCount: 7), 0)
    }
    func testCursorReturningBetweenChecksPreservesOriginalSamplingBehavior() {
        var tracker = SampledIdleTracker(now: 0, cursor: .zero, keyCount: 0)
        _ = tracker.observe(at: 20, cursor: .init(x: 50, y: 50), keyCount: 0)
        XCTAssertEqual(tracker.observe(at: 60, cursor: .zero, keyCount: 0), 60)
        XCTAssertEqual(tracker.observe(at: 180, cursor: .zero, keyCount: 0), 180)
        XCTAssertEqual(tracker.observe(at: 240, cursor: .zero, keyCount: 0), 240)
    }
}
