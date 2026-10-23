import XCTest
@testable import EyeblinkCore

final class NoFaceClockPhaseTests: XCTestCase {
    private func stamp(_ ticks:Int64) -> FrameTimestamp {.init(ticks:ticks,frequency:1_000_000)}
    func testPostTrackingClockControlsBothNoFaceTimeouts() {
        let measurement = FaceAbsenceTimer(startedAt:stamp(17_100_000))
        XCTAssertFalse(measurement.hasExpired(at:stamp(25_100_500),after:8),"posttracking elapsed8000.5ms")
        XCTAssertTrue(measurement.hasExpired(at:stamp(25_101_000),after:8))
        let training = FaceAbsenceTimer(startedAt:stamp(32_250_000))
        XCTAssertFalse(training.hasExpired(at:stamp(33_250_500),after:1))
        XCTAssertTrue(training.hasExpired(at:stamp(33_251_000),after:1))
    }
    func testRawFaceClockRetainsFinalMillisecondBoundaryAtLargeTickEpoch() {
        let start = FrameTimestamp(ticks:Int64.max-10_000_000_000,frequency:1_000_000_000)
        let timer = FaceAbsenceTimer(startedAt:start)
        XCTAssertFalse(timer.hasExpired(at:.init(ticks:start.ticks+8_000_999_999,frequency:start.frequency),after:8))
        XCTAssertTrue(timer.hasExpired(at:.init(ticks:start.ticks+8_001_000_000,frequency:start.frequency),after:8))
    }
    func testInvalidRawClockDoesNotExpireOrMutateAbsenceTimer() {
        let timer = FaceAbsenceTimer(startedAt:stamp(17_100_000))
        for bad in [FrameTimestamp(ticks:-1,frequency:1),.init(ticks:17_000_000,frequency:1_000_000),.init(ticks:25_101_000,frequency:.nan),.init(ticks:25_101_000,frequency:2_000_000)] {
            XCTAssertFalse(timer.hasExpired(at:bad,after:8))
        }
        XCTAssertTrue(timer.hasExpired(at:stamp(25_101_000),after:8))
    }
}
