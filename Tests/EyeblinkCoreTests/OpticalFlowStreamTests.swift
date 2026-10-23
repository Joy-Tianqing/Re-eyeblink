import XCTest
@testable import EyeblinkCore

final class OpticalFlowStreamTests: XCTestCase {
    func testBilateralMotionEmitsOnceAndDoesNotReplayCompletedCandidates() {
        var stream = OpticalFlowStream()
        var detections: [Double] = []
        let means: [Double] = [0, 0.01, 0.01, -0.01, -0.01, 0, 0, 0, 0]
        for (i, mean) in means.enumerated() {
            let deviation = mean == 0 ? 0.0 : 0.01
            detections.append(contentsOf: stream.process(at: Double(i) * 0.04, leftMean: mean, leftDeviation: deviation, rightMean: mean, rightDeviation: deviation))
        }
        XCTAssertEqual(detections.count, 1)
        if let duration = detections.first { XCTAssertGreaterThan(duration, 0.1) }
        for i in 9..<150 { XCTAssertTrue(stream.process(at: Double(i) * 0.04, leftMean: 0, leftDeviation: 0, rightMean: 0, rightDeviation: 0).isEmpty) }
    }
    func testOriginalCountsFirstEyeCandidateAndRetainsMergerOnCameraReset() {
        var stream = OpticalFlowStream()
        let means: [Double] = [0, 0.01, 0.01, -0.01, -0.01, 0]
        var detections: [Double] = []
        for (i, mean) in means.enumerated() {
            detections += stream.process(at: Double(i) * 0.04, leftMean: mean, leftDeviation: mean == 0 ? 0 : 0.01, rightMean: 0, rightDeviation: 0)
        }
        XCTAssertEqual(detections.count, 1)
        XCTAssertEqual(detections[0], 0.205, accuracy: 1e-12)
        stream.reset()
        for (i, mean) in means.enumerated() {
            XCTAssertTrue(stream.process(at: 2 + Double(i) * 0.04, leftMean: 0, leftDeviation: 0, rightMean: mean, rightDeviation: mean == 0 ? 0 : 0.01).isEmpty)
        }
    }
}

extension OpticalFlowStreamTests {
    func testCandidatesCrossMultipleRingWrapsWithoutReplayOrIndexReset() {
        var stream = OpticalFlowStream()
        var detections: [(Int, Double)] = []
        // Every candidate starts before a modulo-10000 boundary and ends after it.
        for index in 0...30_010 {
            let offset = index % 10_000
            let mean: Double = offset == 9_998 || offset == 9_999 ? 0.004 :
                (index >= 10_000 && (offset == 0 || offset == 1) ? -0.004 : 0)
            let values = stream.process(at: Double(index) / 32, leftMean: mean,
                leftDeviation: mean == 0 ? 0 : 0.004, rightMean: mean,
                rightDeviation: mean == 0 ? 0 : 0.004, frameInterval: 1.0 / 32)
            detections += values.map { (index, $0) }
        }
        XCTAssertEqual(detections.map(\.0), [10_002, 20_002, 30_002])
        XCTAssertEqual(detections.map(\.1), [0.1875, 0.125, 0.125])
    }

    func testSuspendedScannerResumesAtOriginalCursorWithoutLosingActivePhase() {
        var stream = OpticalFlowStream()
        let means: [Double] = [0, 0.004, 0.004, -0.004, -0.004, 0, 0, 0, 0]
        for (index, mean) in means.enumerated() {
            let values = stream.process(at: Double(index) / 32,
                leftMean: mean, leftDeviation: mean == 0 ? 0 : 0.004,
                rightMean: mean, rightDeviation: mean == 0 ? 0 : 0.004,
                scan: index < 3 || index >= 7)
            XCTAssertEqual(values, index == 7 ? [0.1875] : [], "frame \(index)")
        }
    }

    func testSuspensionBeyondRingCapacityUsesOriginalModuloSlotsWithoutClampingCursor() {
        var stream = OpticalFlowStream()
        for index in 0...20_006 {
            let mean: Double = index == 20_001 || index == 20_002 ? 0.004 :
                (index == 20_003 || index == 20_004 ? -0.004 : 0)
            let values = stream.process(at: Double(index) / 32, leftMean: mean,
                leftDeviation: mean == 0 ? 0 : 0.004, rightMean: 0, rightDeviation: 0,
                scan: index == 20_006)
            // The shipped cursor is not clamped to retained history: after a
            // long suspension the same modulo slots are visited three times.
            XCTAssertEqual(values, index == 20_006 ? [0.1875, 0.125, 0.125] : [])
        }
    }

    func testRejectedCandidateRewindsStartPlusTwoAcrossRingBoundary() {
        var stream = OpticalFlowStream()
        let means: [Double] = [0, 0.004, -0.004, 0.004, 0.004, -0.004, -0.004, 0]
        for index in 0...10_004 {
            let position = index - 9_997
            let mean = means.indices.contains(position) ? means[position] : 0
            let values = stream.process(at: Double(index) / 32, leftMean: mean,
                leftDeviation: mean == 0 ? 0 : 0.004, rightMean: 0, rightDeviation: 0)
            XCTAssertEqual(values, index == 10_004 ? [0.1875] : [], "frame \(index)")
        }
    }

    func testNaNFallsThroughOrderedComparisonWithoutResettingActivePhase() {
        var stream = OpticalFlowStream()
        let means: [Double] = [0, 0.004, 0.004, .nan, -0.004, -0.004, 0]
        for (index, mean) in means.enumerated() {
            let values = stream.process(at: Double(index) / 32, leftMean: mean,
                leftDeviation: mean == 0 ? 0 : 0.004, rightMean: 0, rightDeviation: 0)
            XCTAssertEqual(values, index == 6 ? [0.203125] : [], "frame \(index)")
        }
    }
}
