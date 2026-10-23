import XCTest
@testable import EyeblinkCore

final class OpticalFlowTests: XCTestCase {
    func frames(scale: Double = 1) -> [EyeMotionFrame] {
        [(0.0, 0.0, 0.0), (0.03, 0.004, 0.004), (0.06, 0.004, 0.004),
         (0.09, -0.004, 0.004), (0.12, -0.004, 0.004), (0.15, 0.0, 0.0)]
            .map { .init(time: $0.0 * scale, meanY: $0.1, standardDeviation: $0.2) }
    }
    func testRecoveredThreePhaseMotionProducesCandidateExcludingFinalQuietFrame() {
        let candidates = OpticalFlowBlinkDetector().candidates(in: frames())
        XCTAssertEqual(candidates.count, 1)
        XCTAssertEqual(candidates[0].start, 0)
        XCTAssertEqual(candidates[0].end, 0.12)
        XCTAssertEqual(candidates[0].duration, 0.12, accuracy: 0.000001)
        XCTAssertEqual(candidates[0].accumulatedDeviation, 0.008)
    }
    func testTooShortLongOrSingleDirectionDoesNotBecomeBlink() {
        let detector = OpticalFlowBlinkDetector()
        XCTAssertTrue(detector.candidates(in: frames(scale: 0.5)).isEmpty)
        XCTAssertTrue(detector.candidates(in: frames(scale: 5)).isEmpty)
        XCTAssertTrue(detector.candidates(in: frames().map { .init(time: $0.time, meanY: abs($0.meanY), standardDeviation: $0.standardDeviation) }).isEmpty)
    }
    func testMergeUsesShippedInitialCandidateAndStrictBelowThreshold() {
        var detector = OpticalFlowBlinkDetector()
        XCTAssertEqual(detector.merge(.init(start: 0, end: 0.2, duration: 0.2)), 0.225)
        // Strong overlap is rejected by the actual original function.
        XCTAssertNil(detector.merge(.init(start: 0.05, end: 0.25, duration: 0.18)))
        // Even a rejected candidate becomes the next reference; disjoint passes.
        XCTAssertEqual(detector.merge(.init(start: 2, end: 2.2, duration: 0.2)), 0.19)
        XCTAssertNil(detector.merge(.init(start: 2.05, end: 2.25, duration: 0.16)))
        detector.reset()
        XCTAssertEqual(detector.merge(.init(start: 3, end: 3.2, duration: 0.2)), 0.225)
    }
    func testOverlapUsesFrameIndicesWhenFrameTimingIsIrregular() {
        var detector = OpticalFlowBlinkDetector()
        XCTAssertEqual(detector.merge(.init(start: 0, end: 0.19, duration: 0.19, startFrame: 0, endFrame: 4)), 0.22)
        // Time ratio is below .3, but frame ratio is 3/5 and must be rejected.
        XCTAssertNil(detector.merge(.init(start: 0.18, end: 0.21, duration: 0.12, startFrame: 1, endFrame: 5)))
    }
}
