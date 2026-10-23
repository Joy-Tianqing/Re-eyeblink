import XCTest
@testable import EyeblinkCore

final class OriginalTemporalTests: XCTestCase {
    private struct MergeFixture: Decodable {
        var originalSHA256: String
        var functionVA: String
        var cases: [Pair]
        struct Pair: Decodable {
            var id: String
            var previous: [Double]
            var current: [Double]
            var count: Double
            var totalDuration: Double
        }
    }

    func testMergeMatchesActualShippedFunctionIncludingStrictThreshold() throws {
        let url = try XCTUnwrap(Bundle.module.url(forResource: "OriginalMerge", withExtension: "json", subdirectory: "Fixtures"))
        let fixture = try JSONDecoder().decode(MergeFixture.self, from: Data(contentsOf: url))
        XCTAssertEqual(fixture.originalSHA256, "bd6808caee828c068c8d6614a96e9dabb9c02ecdc397d5be09da953cc6d134db")
        XCTAssertEqual(fixture.functionVA, "0x100144340")
        XCTAssertEqual(fixture.cases.count, 8)
        func candidate(_ fields: [Double]) -> EyeMotionCandidate {
            .init(start: fields[0], end: fields[1], duration: fields[2], accumulatedDeviation: fields[3],
                  startFrame: Int(fields[0]), endFrame: Int(fields[1]))
        }
        for pair in fixture.cases {
            var detector = OpticalFlowBlinkDetector()
            _ = detector.merge(candidate(pair.previous))
            let duration = detector.merge(candidate(pair.current))
            if pair.count == 0 { XCTAssertNil(duration, pair.id) }
            else { XCTAssertEqual(duration, Optional(pair.totalDuration), pair.id) }
        }
    }

    private struct StreamFixture: Decodable {
        var originalSHA256: String
        var cases: [Sequence]
        struct Sequence: Decodable { var id: String; var sessions: [Session] }
        struct Session: Decodable { var frames: [[Double]]; var results: [Result] }
        struct Result: Decodable { var frame: Int; var count: Double; var totalDuration: Double; var emissions: [Double]; var candidates: [Candidate] }
        struct Candidate: Decodable { var eye: Int; var values: [Double] }
    }

    func testStreamMatchesActualShippedScannerAndMergerAcrossThirteenSequences() throws {
        let url = try XCTUnwrap(Bundle.module.url(forResource: "OriginalTemporal", withExtension: "json", subdirectory: "Fixtures"))
        let fixture = try JSONDecoder().decode(StreamFixture.self, from: Data(contentsOf: url))
        XCTAssertEqual(fixture.originalSHA256, "bd6808caee828c068c8d6614a96e9dabb9c02ecdc397d5be09da953cc6d134db")
        XCTAssertEqual(fixture.cases.count, 13)
        for sequence in fixture.cases {
            var stream = OpticalFlowStream()
            var count = 0, total: Double = 0
            for (sessionIndex, session) in sequence.sessions.enumerated() {
                if sessionIndex > 0 { stream.reset() }
                XCTAssertEqual(session.frames.count, session.results.count)
                for (frame, expected) in zip(session.frames, session.results) {
                    let actual = stream.process(at: frame[0], leftMean: frame[1], leftDeviation: frame[2], rightMean: frame[3], rightDeviation: frame[4])
                    let context = "\(sequence.id)/session\(sessionIndex)/frame\(expected.frame)"
                    XCTAssertEqual(actual, expected.emissions, context)
                    count += actual.count; total += actual.reduce(0, +)
                    XCTAssertEqual(Double(count), expected.count, context)
                    XCTAssertEqual(total, expected.totalDuration, context)
                }
            }
        }
    }

    func testBatchCandidateRescansMatchActualShippedSubmissionsForBothEyes() throws {
        let url = try XCTUnwrap(Bundle.module.url(forResource: "OriginalTemporal", withExtension: "json", subdirectory: "Fixtures"))
        let fixture = try JSONDecoder().decode(StreamFixture.self, from: Data(contentsOf: url))
        for sequence in fixture.cases {
            for session in sequence.sessions {
                for eye in 0...1 {
                    let meanColumn = eye == 0 ? 1 : 3
                    let frames = session.frames.enumerated().map { index, frame in
                        EyeMotionFrame(time: frame[0], meanY: frame[meanColumn], standardDeviation: frame[meanColumn + 1], frameIndex: index)
                    }
                    let actual = OpticalFlowBlinkDetector().candidates(in: frames).map { candidate in
                        [Double(candidate.startFrame!), Double(candidate.endFrame!), candidate.duration, candidate.accumulatedDeviation]
                    }
                    let expected = session.results.flatMap(\.candidates).filter { $0.eye == eye }.map(\.values)
                    XCTAssertEqual(actual, expected, "\(sequence.id)/eye\(eye)")
                }
            }
        }
    }

    private struct MeasurementFixture: Decodable {
        var originalSHA256: String
        var executedRange: String
        var cases: [Result]
        struct Result: Decodable {
            var id: String; var durations: [Double]
            var frequency: Double; var durationMilliseconds: Int
        }
    }
    func testMeasurementOutputMatchesActualShippedFloatAndTruncationOrder() throws {
        let url = try XCTUnwrap(Bundle.module.url(forResource: "OriginalMeasurementStats", withExtension: "json", subdirectory: "Fixtures"))
        let fixture = try JSONDecoder().decode(MeasurementFixture.self, from: Data(contentsOf: url))
        XCTAssertEqual(fixture.originalSHA256, "bd6808caee828c068c8d6614a96e9dabb9c02ecdc397d5be09da953cc6d134db")
        XCTAssertEqual(fixture.executedRange, "0x10014055f..0x10014059b")
        XCTAssertEqual(fixture.cases.count, 6)
        for result in fixture.cases {
            let record = MeasurementRecord(date: Date(timeIntervalSince1970: 0), validDuration: 180,
                                           blinkDurations: result.durations, frequencyDuration: 180)
            XCTAssertEqual(record.blinksPerMinute, result.frequency, result.id)
            XCTAssertEqual(record.averageBlinkDurationMilliseconds, Double(result.durationMilliseconds), result.id)
        }
    }
}
