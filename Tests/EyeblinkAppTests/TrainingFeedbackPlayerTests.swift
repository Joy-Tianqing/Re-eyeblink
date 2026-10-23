import XCTest
import AppKit
import EyeblinkCore
@testable import EyeblinkApp

@MainActor
final class TrainingFeedbackPlayerTests: XCTestCase {
    private final class Clock {
        var durations: [TimeInterval] = []
        var waits: [CheckedContinuation<Void, Never>] = []
        func sleep(_ duration: TimeInterval) async {
            durations.append(duration)
            await withCheckedContinuation { waits.append($0) }
        }
        func release() { waits.removeFirst().resume() }
        func drain(until count: Int) async {
            for _ in 0..<1000 {
                if durations.count >= count { break }
                await Task.yield()
            }
            XCTAssertEqual(durations.count, count)
        }
    }

    func testStaticPromptThenOneShotWithApprovedHoldDurations() async {
        let clock = Clock(), id = UUID()
        let player = TrainingFeedbackPlayer(sleep: { await clock.sleep($0) })
        var completed: [UUID] = []
        player.show(.training(.interactive, mgd: false)) { completed.append($0) }
        XCTAssertEqual(player.frame, .open)
        XCTAssertTrue(clock.durations.isEmpty)
        player.show(.trainingFeedback(id)) { completed.append($0) }
        XCTAssertEqual(player.frame, .wink)
        await clock.drain(until: 1)
        XCTAssertEqual(clock.durations, [0.7])
        player.show(.trainingFeedback(id)) { completed.append($0) }
        XCTAssertEqual(clock.durations, [0.7])
        XCTAssertTrue(completed.isEmpty)
        clock.release()
        await clock.drain(until: 2)
        XCTAssertEqual(player.frame, .open)
        XCTAssertEqual(clock.durations, [0.7, 0.3])
        XCTAssertTrue(completed.isEmpty)
        clock.release()
        for _ in 0..<1000 { if !completed.isEmpty { break }; await Task.yield() }
        XCTAssertEqual(completed, [id])
        XCTAssertNil(player.activeID)
    }

    func testCancellationDuringEitherHoldCannotInvokeCompletion() async {
        for cancelInSecondHold in [false, true] {
            let clock = Clock()
            let player = TrainingFeedbackPlayer(sleep: { await clock.sleep($0) })
            var completed = false
            player.show(.trainingFeedback(UUID())) { _ in completed = true }
            await clock.drain(until: 1)
            if cancelInSecondHold { clock.release(); await clock.drain(until: 2) }
            player.show(nil) { _ in XCTFail("nil reminder must not complete") }
            clock.release()
            for _ in 0..<50 { await Task.yield() }
            XCTAssertFalse(completed)
            XCTAssertNil(player.activeID)
            XCTAssertEqual(player.frame, .open)
        }
    }

    func testReplacedAnimationIgnoresOldContinuation() async {
        let clock = Clock(), oldID = UUID(), newID = UUID()
        let player = TrainingFeedbackPlayer(sleep: { await clock.sleep($0) })
        var completed: [UUID] = []
        player.show(.trainingFeedback(oldID)) { completed.append($0) }
        await clock.drain(until: 1)
        player.show(.trainingFeedback(newID)) { completed.append($0) }
        await clock.drain(until: 2)
        clock.release()
        for _ in 0..<50 { await Task.yield() }
        XCTAssertEqual(player.activeID, newID)
        XCTAssertEqual(player.frame, .wink)
        XCTAssertTrue(completed.isEmpty)
        clock.release()
        await clock.drain(until: 3)
        clock.release()
        for _ in 0..<1000 { if !completed.isEmpty { break }; await Task.yield() }
        XCTAssertEqual(completed, [newID])
    }

    func testBundledApprovedFramesLoadAtMatchingDimensions() {
        let open = TrainingReminderFrame.open.image, wink = TrainingReminderFrame.wink.image
        XCTAssertEqual(open.size, NSSize(width: 256, height: 208))
        XCTAssertEqual(open.size, wink.size)
        XCTAssertNotNil(open.tiffRepresentation)
        XCTAssertNotEqual(open.tiffRepresentation, wink.tiffRepresentation)
    }

    func testRecognitionClosesWithoutStartingThePreviewAnimation() async throws {
        var settings = AppSettings()
        settings.mgdEnabled = true; settings.trainingEnabled = true
        settings.measurementEnabled = false; settings.breakEnabled = false; settings.exerciseEnabled = false
        var engine = EyeblinkEngine(settings: settings)
        engine.advance(to: 30)
        let camera = try XCTUnwrap(engine.state.cameraToken)
        engine.cameraDidStart(token: camera, at: 30)
        let clock = Clock()
        let player = TrainingFeedbackPlayer(sleep: { await clock.sleep($0) })
        engine.sample(cameraToken: camera, token: nil, at: 30.2, faceValid: false, blinkDurations: [0.2])
        XCTAssertNotNil(engine.state.reminder, "Wait for the next worker iteration")
        engine.cameraTrainingProgress(token: camera, blinkDetected: true, at: 30.21)
        player.show(engine.state.reminder) { _ in XCTFail("Recognition does not play a success animation") }
        XCTAssertNil(engine.state.reminder)
        XCTAssertNil(player.activeID)
        XCTAssertTrue(clock.durations.isEmpty)
        XCTAssertEqual(engine.state.trainingRemaining, 30)
    }

    func testExplicitAnimationPreviewKeepsPromptForFullSecond() async {
        let player = TrainingFeedbackPlayer()
        let done = expectation(description: "One-shot completed")
        let started = ProcessInfo.processInfo.systemUptime
        player.show(.trainingFeedback(UUID())) { _ in
            XCTAssertGreaterThanOrEqual(ProcessInfo.processInfo.systemUptime - started, 1.0)
            XCTAssertEqual(player.frame, .open)
            done.fulfill()
        }
        XCTAssertEqual(player.frame, .wink)
        await fulfillment(of: [done], timeout: 4)
    }
}
