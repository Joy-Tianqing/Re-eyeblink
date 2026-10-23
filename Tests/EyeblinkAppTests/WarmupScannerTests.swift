import XCTest
import CEyeFlow
@testable import EyeblinkApp

final class WarmupScannerTests: XCTestCase {
    private struct Fixture: Decodable {
        var originalSHA256: String
        var frameInterval: Double
        var cases: [Sequence]
        struct Sequence: Decodable {
            var id: String
            var sessions: [Session]
        }
        struct Session: Decodable { var frames: [Frame] }
        struct Frame: Decodable {
            var frame: Int
            var time: Double
            var warmup: Bool
            var leftStats: [Double]
            var rightStats: [Double]
            var emissions: [Double]
            var count: Double
            var totalDuration: Double
        }
    }
    private func fixture() throws -> Fixture {
        let url = try XCTUnwrap(Bundle.module.url(forResource: "OriginalWarmupScanner", withExtension: "json", subdirectory: "Fixtures"))
        let fixture = try JSONDecoder().decode(Fixture.self, from: Data(contentsOf: url))
        XCTAssertEqual(fixture.originalSHA256, "bd6808caee828c068c8d6614a96e9dabb9c02ecdc397d5be09da953cc6d134db")
        return fixture
    }
    private func compare(_ sequence: Fixture.Sequence, interval: Double, timeBase: Double = 0, timeStep: Double? = nil,
                         file: StaticString = #filePath, line: UInt = #line) {
        var analysis = CameraMotionAnalysis()
        var count: Double = 0, total: Double = 0
        for (index, session) in sequence.sessions.enumerated() {
            if index > 0 { analysis.reset() }
            for frame in session.frames {
                var features = EFResult()
                features.left.mean_y = frame.leftStats[0]; features.left.stddev_y = frame.leftStats[1]
                features.right.mean_y = frame.rightStats[0]; features.right.stddev_y = frame.rightStats[1]
                let time = timeBase + (timeStep.map { Double(frame.frame) * $0 } ?? frame.time)
                let result = analysis.process(at: time, status: frame.warmup ? EF_WARMUP.rawValue : EF_OK.rawValue,
                    result: features, frameInterval: frame.frame == 0 ? nil : interval)
                count += Double(result.blinks.count); total += result.blinks.reduce(0,+)
                let context = "\(sequence.id) session\(index) frame\(frame.frame)"
                XCTAssertTrue(result.isValid, context, file: file, line: line)
                XCTAssertEqual(result.blinks, frame.emissions, context, file: file, line: line)
                XCTAssertEqual(count, frame.count, context, file: file, line: line)
                XCTAssertEqual(total, frame.totalDuration, context, file: file, line: line)
            }
        }
    }
    func testOriginalWarmupDefersScannerAndPreservesMergerAcrossReopen() throws {
        let fixture = try fixture()
        XCTAssertEqual(fixture.cases.count, 10)
        XCTAssertEqual(fixture.cases.flatMap(\.sessions).flatMap(\.frames).count, 92)
        for sequence in fixture.cases { compare(sequence, interval: fixture.frameInterval) }
    }
    func testDeferredSamplesRetainOriginalRawIntervalsDespiteDisplayTimeJitter() throws {
        let fixture = try fixture()
        let selected = fixture.cases.filter { ["bilateral-warmup3", "right_only-warmup1", "reset-before-deferred-merge"].contains($0.id) }
        XCTAssertEqual(selected.count, 3)
        for sequence in selected { compare(sequence, interval: fixture.frameInterval, timeBase: 1_000_000, timeStep: 0.03) }
    }
}
