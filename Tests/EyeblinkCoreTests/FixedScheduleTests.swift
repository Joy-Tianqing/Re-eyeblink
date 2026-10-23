import XCTest
@testable import EyeblinkCore

final class FixedScheduleTests: XCTestCase {
    func testInterfaceRestoresOriginalFixedScheduleWithoutChangingOtherPreferences() throws {
        var prototype = AppSettings()
        prototype.measurementInterval = 5 * 60
        prototype.measurementDuration = 60
        prototype.exerciseInterval = 5 * 60
        prototype.measurementNotifications = false
        prototype.language = .english
        let persisted = try JSONEncoder().encode(prototype)
        let restored = try JSONDecoder().decode(AppSettings.self, from: persisted).validatedForInterface()
        XCTAssertEqual(restored.measurementInterval, 1800)
        XCTAssertEqual(restored.measurementDuration, 180)
        XCTAssertEqual(restored.exerciseInterval, 1140)
        XCTAssertFalse(restored.measurementNotifications)
        XCTAssertEqual(restored.language, .english)
        // Core fixtures can still use controlled time without changing production UI.
        XCTAssertEqual(prototype.validated().measurementDuration, 60)
    }

    private func engineSettings() -> AppSettings {
        var settings = AppSettings()
        settings.measurementEnabled = false
        settings.naturalBreaksEnabled = false
        settings.trainingMode = .simple
        return settings
    }

    private func policy() -> EnginePolicy {
        var policy = EnginePolicy()
        policy.startupQuietPeriod = 0
        policy.featurePollingInterval = 0.001
        return policy
    }

    func testExerciseStartsTwentySecondTrainingTimerInsteadOfImmediatelyRemindingAfterExercise() {
        var settings = engineSettings()
        settings.breakEnabled = false
        settings.exerciseInterval = 100
        var engine = EyeblinkEngine(settings: settings, policy: policy())
        engine.advance(to: 100)
        XCTAssertEqual(engine.state.reminder, .exercise(.lookFar, secondsRemaining: 10))
        XCTAssertEqual(engine.state.trainingRemaining, 20)
        engine.advance(to: 110)
        XCTAssertNil(engine.state.reminder)
        XCTAssertEqual(engine.state.trainingRemaining, 10)
        engine.advance(to: 119)
        XCTAssertNil(engine.state.reminder)
        engine.advance(to: 120)
        XCTAssertEqual(engine.state.reminder, .training(.simple, mgd: false))
    }

    func testSkippingRestPreservesTrainingDeadlineStartedAtRestEntry() {
        var settings = engineSettings()
        settings.exerciseEnabled = false
        settings.breakInterval = 100
        var engine = EyeblinkEngine(settings: settings, policy: policy())
        engine.advance(to: 100)
        XCTAssertEqual(engine.state.reminder, .rest)
        XCTAssertEqual(engine.state.trainingRemaining, 20)
        engine.dismissReminder(at: 101)
        XCTAssertEqual(engine.state.trainingRemaining, 19)
        settings.breakEnabled = false
        engine.updateSettings(settings, at: 101)
        engine.advance(to: 119)
        XCTAssertNil(engine.state.reminder)
        engine.advance(to: 120)
        XCTAssertEqual(engine.state.reminder, .training(.simple, mgd: false))
    }
}
