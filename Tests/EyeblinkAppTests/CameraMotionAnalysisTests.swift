import XCTest
import CEyeFlow
@testable import EyeblinkApp

final class CameraMotionAnalysisTests: XCTestCase {
    func testExplicitFrameIntervalsPreserveOriginalEventDuration() throws {
        let url = try XCTUnwrap(Bundle.module.url(forResource: "OriginalMotionFlow", withExtension: "json", subdirectory: "Fixtures"))
        let fixture = try JSONDecoder().decode(Fixture.self, from: Data(contentsOf: url))
        var analysis = CameraMotionAnalysis()
        for frame in fixture.cases {
            var result = EFResult()
            result.left.mean_y = frame.leftStats[0]; result.left.stddev_y = frame.leftStats[1]
            result.right.mean_y = frame.rightStats[0]; result.right.stddev_y = frame.rightStats[1]
            // Deliberately perturb ordering/display seconds. The authoritative
            // source interval remains the original 1/32-second tick difference.
            let actual = analysis.process(at: 1_000_000 + Double(frame.frame) * 0.03,
                status: frame.flowSkippedForMissingPreviousFace ? EF_WARMUP.rawValue : EF_OK.rawValue,
                result: result, frameInterval: frame.frame == 0 ? nil : 0.03125)
            XCTAssertEqual(actual.blinks, frame.emissions, "frame \(frame.frame)")
        }
    }
    private struct Fixture: Decodable {
        var originalSHA256: String
        var inputSHA256: String
        var cases: [Frame]
        struct Frame: Decodable {
            var frame: Int
            var time: Double
            var flowSkippedForMissingPreviousFace: Bool
            var leftStats: [Double]
            var rightStats: [Double]
            var emissions: [Double]
            var count: Double
            var totalDuration: Double
        }
    }

    func testWarmupHandoffMatchesOriginalPositiveImageSequenceFrameByFrame() throws {
        let url = try XCTUnwrap(Bundle.module.url(forResource: "OriginalMotionFlow", withExtension: "json", subdirectory: "Fixtures"))
        let fixture = try JSONDecoder().decode(Fixture.self, from: Data(contentsOf: url))
        XCTAssertEqual(fixture.originalSHA256, "bd6808caee828c068c8d6614a96e9dabb9c02ecdc397d5be09da953cc6d134db")
        XCTAssertEqual(fixture.cases.count, 7)
        XCTAssertEqual(fixture.cases.flatMap(\.emissions), [0.1875])
        // This is the exact production stage used by captureOutput. No camera,
        // session, UI, model loading, permissions, or system monitors are created.
        var analysis = CameraMotionAnalysis()
        var count = 0, duration: Double = 0
        for frame in fixture.cases {
            var result = EFResult()
            result.left.mean_y = frame.leftStats[0]; result.left.stddev_y = frame.leftStats[1]
            result.right.mean_y = frame.rightStats[0]; result.right.stddev_y = frame.rightStats[1]
            let status = frame.flowSkippedForMissingPreviousFace ? EF_WARMUP.rawValue : EF_OK.rawValue
            let actual = analysis.process(at: frame.time, status: status, result: result)
            XCTAssertTrue(actual.isValid)
            XCTAssertEqual(actual.blinks, frame.emissions, "frame \(frame.frame)")
            count += actual.blinks.count; duration += actual.blinks.reduce(0, +)
            XCTAssertEqual(Double(count), frame.count, "frame \(frame.frame)")
            XCTAssertEqual(duration, frame.totalDuration, "frame \(frame.frame)")
        }
    }
}

extension CameraMotionAnalysisTests {
    func testNonfiniteEyeDoesNotSwallowOtherEyeCandidate() {
        for bad in [Double.nan, .infinity, -.infinity] {
            var analysis = CameraMotionAnalysis()
            let means: [Double] = [0, 0.004, 0.004, -0.004, -0.004, 0]
            for (index, mean) in means.enumerated() {
                var features = EFResult()
                features.left.mean_y = mean
                features.left.stddev_y = mean == 0 ? 0 : 0.004
                features.right.mean_y = bad
                features.right.stddev_y = .nan
                let actual = analysis.process(at: Double(index) / 32,
                    status: EF_OK.rawValue, result: features)
                XCTAssertFalse(actual.isValid)
                XCTAssertEqual(actual.blinks, index == 5 ? [0.1875] : [], "frame \(index), right mean \(bad)")
            }
        }
    }
}
