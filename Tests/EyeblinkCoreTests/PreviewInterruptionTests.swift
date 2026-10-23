import XCTest
@testable import EyeblinkCore

final class PreviewInterruptionTests: XCTestCase {
    private func settings() -> AppSettings {
        var s = AppSettings()
        s.trainingEnabled = false; s.measurementEnabled = false
        s.exerciseEnabled = false; s.breakEnabled = false
        return s
    }
    func testCameraPreviewFinishesRestAndResetsBothCyclesLikeOriginalQuitBreak() {
        var s = settings(); s.breakEnabled = true; s.breakInterval = 900
        var engine = EyeblinkEngine(settings: s)
        engine.advance(to: 900, idleDuration: 0)
        XCTAssertEqual(engine.state.reminder, .rest)
        _ = engine.takeEffects()
        engine.setPreview(true, at: 901)
        XCTAssertEqual(engine.state.breakRemaining, 900)
        XCTAssertEqual(engine.state.exerciseRemaining, 1140)
        XCTAssertEqual(engine.takeEffects(), [.restTransition(.init(kind: .cameraPreview, uptime: 901))])
        engine.setPreview(false, at: 902)
        engine.advance(to: 904, idleDuration: 0)
        XCTAssertNil(engine.state.reminder, "Preview must not leave an expired break queued")
    }
    func testCameraPreviewFinishesExerciseAndAdvancesNextExerciseKind() {
        var s = settings(); s.exerciseEnabled = true
        var engine = EyeblinkEngine(settings: s)
        engine.advance(to: 1140, idleDuration: 0)
        XCTAssertEqual(engine.state.reminder, .exercise(.lookFar, secondsRemaining: 10))
        engine.setPreview(true, at: 1141)
        XCTAssertEqual(engine.state.exerciseRemaining, 1140)
        engine.setPreview(false, at: 1142)
        engine.advance(to: 1144, idleDuration: 0)
        XCTAssertNil(engine.state.reminder)
        engine.advance(to: 2284, idleDuration: 0)
        XCTAssertEqual(engine.state.reminder, .exercise(.squeezeBlink, secondsRemaining: 10))
    }
    func testCameraPreviewHidesSimpleReminderAndRestartsItsTrainingInterval() {
        var s = settings(); s.trainingEnabled = true; s.trainingMode = .simple
        var engine = EyeblinkEngine(settings: s)
        engine.advance(to: 30, idleDuration: 0)
        XCTAssertEqual(engine.state.reminder, .training(.simple, mgd: false))
        engine.setPreview(true, at: 31)
        XCTAssertEqual(engine.state.trainingRemaining, 30)
        engine.setPreview(false, at: 32)
        engine.advance(to: 34, idleDuration: 0)
        XCTAssertNil(engine.state.reminder)
        engine.advance(to: 64, idleDuration: 0)
        XCTAssertEqual(engine.state.reminder, .training(.simple, mgd: false))
    }
}
