import XCTest
@testable import EyeblinkCore

final class PauseAlignmentTests: XCTestCase {
    private func settings() -> AppSettings {
        var settings = AppSettings()
        settings.trainingEnabled = false; settings.measurementEnabled = false
        settings.breakEnabled = false; settings.exerciseEnabled = false
        return settings
    }

    func testTrainingExpiresWhilePausedButWaitsForResumeQuietPeriod() {
        var settings = settings(); settings.trainingEnabled = true; settings.trainingMode = .simple
        var engine = EyeblinkEngine(settings: settings)
        engine.setPaused(true, at: 10)
        engine.advance(to: 100)
        XCTAssertLessThanOrEqual(engine.state.trainingRemaining, 0)
        XCTAssertNil(engine.state.reminder)
        XCTAssertNil(engine.state.cameraToken)
        engine.setPaused(false, at: 100)
        engine.advance(to: 114.999)
        XCTAssertNil(engine.state.reminder)
        engine.advance(to: 115)
        XCTAssertEqual(engine.state.reminder, .training(.simple, mgd: false))
    }

    func testMeasurementDeadlineContinuesAcrossShortPause() {
        var settings = settings(); settings.measurementEnabled = true
        var engine = EyeblinkEngine(settings: settings)
        engine.setPaused(true, at: 10)
        engine.advance(to: 60)
        XCTAssertEqual(engine.state.measurementRemaining, 60)
        engine.setPaused(false, at: 60)
        engine.advance(to: 118)
        XCTAssertNil(engine.state.measurement)
        engine.advance(to: 120)
        XCTAssertNotNil(engine.state.measurement)
    }

    func testPausingVisibleSimpleReminderRestartsIntervalAtHideAndKeepsCounting() {
        var settings = settings(); settings.trainingEnabled = true; settings.trainingMode = .simple
        var engine = EyeblinkEngine(settings: settings)
        engine.advance(to: 30)
        XCTAssertNotNil(engine.state.reminder)
        engine.setPaused(true, at: 31)
        XCTAssertNil(engine.state.reminder)
        XCTAssertEqual(engine.state.trainingRemaining, 30)
        engine.setPaused(true, reason: .process("Zoom"), at: 32)
        XCTAssertEqual(engine.state.trainingRemaining, 29)
        engine.setPaused(false, reason: .process("Zoom"), at: 35)
        engine.setPaused(false, at: 36)
        engine.advance(to: 51)
        XCTAssertNil(engine.state.reminder)
        XCTAssertEqual(engine.state.trainingRemaining, 10)
        engine.advance(to: 59)
        XCTAssertNil(engine.state.reminder)
        engine.advance(to: 61)
        XCTAssertNotNil(engine.state.reminder)
    }

    func testExpiredMeasurementRetainsPriorityAfterLongPause() {
        var settings = settings(); settings.measurementEnabled = true; settings.trainingEnabled = true
        var engine = EyeblinkEngine(settings: settings)
        engine.setPaused(true, at: 10)
        engine.advance(to: 1000)
        XCTAssertLessThanOrEqual(engine.state.measurementRemaining, 0)
        XCTAssertNil(engine.state.measurement)
        engine.setPaused(false, at: 1000)
        engine.advance(to: 1014.999)
        XCTAssertNil(engine.state.cameraPurpose)
        engine.advance(to: 1015)
        XCTAssertEqual(engine.state.cameraPurpose, .measurement)
        XCTAssertFalse(engine.state.trainingSessionActive)
    }

    func testCancelledMeasurementRetryTimerRunsDuringPauseWithoutSaving() throws {
        var settings = settings(); settings.measurementEnabled = true
        var engine = EyeblinkEngine(settings: settings)
        let id = try XCTUnwrap(engine.startMeasurement(at: 20))
        let camera = try XCTUnwrap(engine.state.cameraToken)
        engine.setPaused(true, at: 30)
        XCTAssertEqual(engine.state.measurementRemaining, 480)
        engine.advance(to: 600)
        engine.cameraMeasurementFinished(token: camera, at: 600)
        XCTAssertLessThanOrEqual(engine.state.measurementRemaining, 0)
        XCTAssertEqual(engine.takeEffects(), [.measurementCancelled(id)])
        engine.setPaused(false, at: 600)
        engine.advance(to: 615)
        XCTAssertNotEqual(try XCTUnwrap(engine.state.measurement?.id), id)
        XCTAssertTrue(engine.takeEffects().isEmpty)
    }

    func testReenableTrainingRestartsFullConfiguredInterval() {
        var settings = settings(); settings.trainingEnabled = true; settings.trainingMode = .simple
        settings.trainingInterval = 60
        var engine = EyeblinkEngine(settings: settings)
        settings.trainingEnabled = false; engine.updateSettings(settings, at: 20)
        engine.advance(to: 500)
        settings.trainingEnabled = true; engine.updateSettings(settings, at: 500)
        XCTAssertEqual(engine.state.trainingRemaining, 60)
        engine.advance(to: 558)
        XCTAssertNil(engine.state.reminder)
        engine.advance(to: 560)
        XCTAssertEqual(engine.state.reminder, .training(.simple, mgd: false))
    }

    func testReenableWhilePausedRestartsTimerAndUnrelatedSettingsDoNotResetIt() {
        var settings = settings(); settings.trainingEnabled = true
        var engine = EyeblinkEngine(settings: settings)
        engine.setPaused(true, at: 10)
        settings.trainingEnabled = false; engine.updateSettings(settings, at: 20)
        settings.trainingEnabled = true; engine.updateSettings(settings, at: 100)
        XCTAssertEqual(engine.state.trainingRemaining, 30)
        settings.reminderSoundEnabled.toggle(); engine.updateSettings(settings, at: 110)
        XCTAssertEqual(engine.state.trainingRemaining, 20)
        XCTAssertNil(engine.state.cameraToken)
    }

    func testProcessRulesRequireFullLowercasedNameWhileWindowsUseSubstring() {
        var settings = settings()
        settings.pauseProcessKeywords = ["Zoom", "Code", " "]
        settings.pauseWindowKeywords = ["Meeting"]
        settings.pauseCameraKeywords = ["CALL"]
        let partial = AutomaticPauseMatches.evaluate(settings: settings, processes: ["zoom.us", "Visual Studio Code"], windowTitles: ["Weekly MEETING"], frontmostWindowTitles: ["Video call"])
        XCTAssertEqual(partial.all, [.window("Meeting")])
        XCTAssertEqual(partial.camera, [.window("CALL")])
        let exact = AutomaticPauseMatches.evaluate(settings: settings, processes: ["zOoM", "code"], windowTitles: [], frontmostWindowTitles: [])
        XCTAssertEqual(exact.all, [.process("Zoom"), .process("Code")])
    }
}
