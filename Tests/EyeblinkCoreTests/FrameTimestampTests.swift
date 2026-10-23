import XCTest
@testable import EyeblinkCore

final class FrameTimestampTests: XCTestCase {
    func testIntegerDeltaMatchesThreeActualShippedClockCalculations() throws {
        struct Reference: Decodable {
            var originalSHA256: String
            var samples: [Sample]
            struct Sample: Decodable { var tickStored: Int64; var previousTick: Int64; var frequency: Double; var storedDelta: Double }
        }
        let url = try XCTUnwrap(Bundle.module.url(forResource: "OriginalFrameClock", withExtension: "json", subdirectory: "Fixtures"))
        let reference = try JSONDecoder().decode(Reference.self, from: Data(contentsOf: url))
        XCTAssertEqual(reference.originalSHA256, "bd6808caee828c068c8d6614a96e9dabb9c02ecdc397d5be09da953cc6d134db")
        XCTAssertEqual(reference.samples.count, 3)
        for sample in reference.samples {
            let current = FrameTimestamp(ticks: sample.tickStored, frequency: sample.frequency)
            let previous = FrameTimestamp(ticks: sample.previousTick, frequency: sample.frequency)
            XCTAssertEqual(current.interval(since: previous), sample.storedDelta)
        }
    }

    func testLargeTickCounterRetainsAdjacentTickPrecision() {
        let before = FrameTimestamp(ticks: Int64.max - 13, frequency: 24_000_000)
        let after = FrameTimestamp(ticks: Int64.max - 10, frequency: 24_000_000)
        XCTAssertEqual(after.uptime, before.uptime, "Absolute Double seconds cannot retain these three ticks")
        XCTAssertEqual(after.interval(since: before), 3.0 / 24_000_000)
    }

    func testInvalidClockAndCounterChangesAreRejected() {
        let before = FrameTimestamp(ticks: 10, frequency: 32)
        XCTAssertNil(before.interval(since: before))
        XCTAssertNil(FrameTimestamp(ticks: 9, frequency: 32).interval(since: before))
        XCTAssertNil(FrameTimestamp(ticks: 11, frequency: 24).interval(since: before))
        for frequency in [Double.zero, -.infinity, .infinity, .nan, -1] {
            let value = FrameTimestamp(ticks: 11, frequency: frequency)
            XCTAssertFalse(value.isValid); XCTAssertNil(value.interval(since: before))
        }
        XCTAssertFalse(FrameTimestamp(ticks: -1, frequency: 32).isValid)
        XCTAssertEqual(FrameTimestamp(ticks: 0, frequency: 32).uptime, 0)
    }
}
