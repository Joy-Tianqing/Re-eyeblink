import XCTest
import EyeblinkCore
@testable import EyeblinkApp

final class CameraRunBoundaryTests: XCTestCase {
    func testTrainingPromptIsWorkerOwnedAndSuccessWinsBeforeNextRead() throws {
        var boundary = CameraRunBoundary(measurementDuration: nil, trainingDuration: 4.001)
        try boundary.start(at: .init(ticks: 30_000, frequency: 1000))
        XCTAssertEqual(try boundary.nextFrame { .init(ticks: 34_000, frequency: 1000) }, .analyze)
        let prompt = FrameTimestamp(ticks: 34_001, frequency: 1000)
        XCTAssertEqual(try boundary.nextFrame { prompt }, .trainingPrompt(prompt))
        XCTAssertEqual(try boundary.nextFrame { prompt }, .analyze, "Send false once; keep capturing")
        boundary.recordBlinks([0.2])
        let complete = FrameTimestamp(ticks: 34_010, frequency: 1000)
        XCTAssertEqual(try boundary.nextFrame { complete }, .trainingComplete(complete))
        XCTAssertEqual(try boundary.nextFrame { XCTFail("No clock/read after success"); return complete }, .ignore)

        var early = CameraRunBoundary(measurementDuration: nil, trainingDuration: 4.001)
        try early.start(at: .init(ticks: 30_000, frequency: 1000))
        early.recordBlinks([0.2])
        XCTAssertEqual(try early.nextFrame { prompt }, .trainingComplete(prompt), "Count check precedes reminder deadline")
    }
    func testOriginalIntegerMillisecondDeadlineAtLargeEpochCompletesExactlyOnce() throws {
        var boundary = CameraRunBoundary(measurementDuration: 180)
        XCTAssertEqual(try boundary.nextFrame { XCTFail("No deadline before ready"); return .init(ticks: 0, frequency: 1) }, .analyze)
        let epoch = Int64.max - 200_000_000_000
        try boundary.start(at: .init(ticks: epoch, frequency: 1_000_000_000))
        for delta: Int64 in [179_999_000_000,180_000_000_000,180_000_999_999] {
            XCTAssertEqual(try boundary.nextFrame { .init(ticks: epoch + delta, frequency: 1_000_000_000) }, .analyze)
        }
        let completed = FrameTimestamp(ticks: epoch + 180_001_000_000, frequency: 1_000_000_000)
        XCTAssertEqual(try boundary.nextFrame { completed }, .complete(completed))
        XCTAssertEqual(try boundary.nextFrame { XCTFail("Completed run must not consume clock or frame"); return completed }, .ignore)
        XCTAssertThrowsError(try boundary.start(at: completed))
    }
    func testPreviewAndTrainingHaveNoMeasurementDeadlineAndNewLeaseStartsFresh() throws {
        var boundary = CameraRunBoundary(measurementDuration: nil)
        try boundary.start(at: .init(ticks: 1, frequency: 1))
        for _ in 0..<3 {
            XCTAssertEqual(try boundary.nextFrame { XCTFail("Nonmeasurement run must not sample deadline clock"); return .init(ticks: 1000, frequency: 1) }, .analyze)
        }
        boundary.terminate()
        XCTAssertEqual(try boundary.nextFrame { XCTFail("Terminated run must ignore queued frames"); return .init(ticks: 1000, frequency: 1) }, .ignore)
        boundary = CameraRunBoundary(measurementDuration: 180)
        try boundary.start(at: .init(ticks: 1000, frequency: 1000))
        XCTAssertEqual(try boundary.nextFrame { .init(ticks: 181_000, frequency: 1000) }, .analyze)
        XCTAssertEqual(try boundary.nextFrame { .init(ticks: 181_001, frequency: 1000) }, .complete(.init(ticks: 181_001, frequency: 1000)))
    }
    func testInvalidClockCannotCompleteOrCorruptMeasurementBoundary() throws {
        var boundary = CameraRunBoundary(measurementDuration: 180)
        try boundary.start(at: .init(ticks: 1000, frequency: 1000))
        try boundary.start(at: .init(ticks: 51_000, frequency: 1000))
        for timestamp in [FrameTimestamp(ticks: 999, frequency: 1000), .init(ticks: 182_000, frequency: 2000), .init(ticks: -1, frequency: 1000)] {
            XCTAssertThrowsError(try boundary.nextFrame { timestamp })
        }
        XCTAssertEqual(try boundary.nextFrame { .init(ticks: 1000, frequency: 1000) }, .analyze)
        XCTAssertEqual(try boundary.nextFrame { .init(ticks: 181_001, frequency: 1000) }, .complete(.init(ticks: 181_001, frequency: 1000)))
        for invalid in [0.0, -1.0, .nan, .infinity] {
            var invalidBoundary = CameraRunBoundary(measurementDuration: invalid)
            XCTAssertThrowsError(try invalidBoundary.start(at: .init(ticks: 1, frequency: 1)))
        }
    }
    func testFrameStartedBeforeDeadlineMayFailAfterDeadlineAndSuppressCompletion() throws {
        var boundary = CameraRunBoundary(measurementDuration: 180)
        try boundary.start(at: .init(ticks: 0, frequency: 1_000_000))
        XCTAssertEqual(try boundary.nextFrame { .init(ticks: 179_999_000, frequency: 1_000_000) }, .analyze)
        // In-flight tracking finishes after the deadline with a terminal error.
        // Its catch terminates the run before another callback can check time.
        boundary.terminate()
        XCTAssertEqual(try boundary.nextFrame { XCTFail("Failure wins over later deadline"); return .init(ticks: 180_002_000, frequency: 1_000_000) }, .ignore)
    }
}
