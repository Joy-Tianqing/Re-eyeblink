import XCTest
import EyeblinkCore
@testable import EyeblinkApp

final class CameraFrameSourceTests: XCTestCase {
    func testReadWaitsForANewCallbackInsteadOfReplayingBufferedFrames() {
        let source = CameraFrameSource<Int>()
        source.publish(1); source.publish(2)
        let waiting = DispatchSemaphore(value: 0)
        let done = expectation(description: "next callback")
        DispatchQueue.global().async {
            defer { done.fulfill() }
            do {
                let value = try source.read(onWait: { waiting.signal() })
                XCTAssertEqual(value, 3)
            }
            catch { XCTFail("Unexpected read error: \(error)") }
        }
        XCTAssertEqual(waiting.wait(timeout: .now() + 2), .success)
        source.publish(3)
        wait(for: [done], timeout: 2)
    }

    func testStopAndDeviceFailureWakeBlockedReadWithoutNeedingAnotherFrame() {
        for deviceFailure in [false, true] {
            let old = CameraFrameSource<Int>()
            let waiting = DispatchSemaphore(value: 0)
            let done = expectation(description: "read released")
            DispatchQueue.global().async {
                defer { done.fulfill() }
                do { _ = try old.read(onWait: { waiting.signal() }); XCTFail("Closed stream returned a frame") }
                catch CameraReadError.device(let message) { XCTAssertTrue(deviceFailure); XCTAssertEqual(message, "fixture") }
                catch CameraReadError.cancelled { XCTAssertFalse(deviceFailure) }
                catch { XCTFail("Wrong terminal result: \(error)") }
            }
            XCTAssertEqual(waiting.wait(timeout: .now() + 2), .success)
            old.close(deviceFailure ? .device("fixture") : .cancelled)
            old.publish(9)
            wait(for: [done], timeout: 2)
            XCTAssertThrowsError(try old.check())
            XCTAssertNoThrow(try CameraFrameSource<Int>().check(), "A new lease must be independent")
        }
    }

    func testOriginalOneSecondReadTimeoutIsNotANoFaceTimer() {
        let source = CameraFrameSource<Int>()
        let start = ProcessInfo.processInfo.systemUptime
        XCTAssertThrowsError(try source.read()) {
            guard case CameraReadError.timeout = $0 else { return XCTFail("Wrong error: \($0)") }
        }
        XCTAssertGreaterThanOrEqual(ProcessInfo.processInfo.systemUptime - start, 1)
        XCTAssertNoThrow(try source.check(), "Unchecked startup reads may retry after timeout")
    }

    func testSevenStartupReadsDoNotNormalizeImagesOrConsumeDetectorClocks() throws {
        let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        let predictor = try DlibShapePredictor(contentsOf: root.appendingPathComponent(".deps/models/data.dat"))
        let run = CameraFrameRun()
        run.reset(generation: UUID(), isPreview: false, noFaceTimeout: 8, measurementDuration: 180)
        var reads = 0, clocks = 0
        let pixels = [UInt8](repeating: 0, count: 640 * 480 * 4)
        let ready = pixels.withUnsafeBufferPointer { p in
            run.process(predictor: predictor, receivedAt: 0, clock: {
                clocks += 1
                XCTAssertEqual(reads, 8, "Only the checked priming image establishes time")
                return .init(ticks: 8, frequency: 32)
            }, acquirePixels: {
                reads += 1
                // Any normalization of these seven discarded images would fail.
                return .init(pixels: p.baseAddress!, width: reads < 8 ? 0 : 640,
                    height: reads < 8 ? 0 : 480, stride: 640 * 4)
            })
        }
        XCTAssertEqual(reads, 8)
        XCTAssertEqual(clocks, 2)
        XCTAssertEqual(ready?.isPriming, true)
        XCTAssertNil(ready?.error)
    }

    func testUncheckedStartupTimeoutsReachCheckedReadButCancellationStopsImmediately() throws {
        let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        let predictor = try DlibShapePredictor(contentsOf: root.appendingPathComponent(".deps/models/data.dat"))
        for cancelled in [false, true] {
            let run = CameraFrameRun()
            run.reset(generation: UUID(), isPreview: false, noFaceTimeout: 1, measurementDuration: nil)
            var reads = 0
            let result = run.process(predictor: predictor, receivedAt: 0, clock: { .init(ticks: 8, frequency: 1) }, acquirePixels: {
                reads += 1
                throw cancelled ? CameraReadError.cancelled : CameraReadError.timeout
            })
            XCTAssertEqual(reads, cancelled ? 1 : 8)
            if cancelled { XCTAssertNil(result) }
            else { XCTAssertEqual(result?.captureFailure, true); XCTAssertEqual(result?.endsRun, true) }
        }
    }
}
