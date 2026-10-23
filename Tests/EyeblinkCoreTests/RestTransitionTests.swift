import XCTest
@testable import EyeblinkCore

final class RestTransitionTests: XCTestCase {
    private func engine() -> EyeblinkEngine {
        var settings = AppSettings()
        settings.trainingEnabled = false; settings.exerciseEnabled = false
        settings.measurementEnabled = false; settings.breakInterval = 900
        settings.naturalBreaksEnabled = false
        return EyeblinkEngine(settings: settings)
    }
    private func transitions(_ engine: inout EyeblinkEngine) -> [RestTransition] {
        engine.takeEffects().compactMap { if case .restTransition(let event) = $0 { return event }; return nil }
    }
    func testIdleCompletionIsRecordedOnlyAtStrictSampledBoundaryAndOnlyOnce() {
        var engine = engine()
        engine.advance(to: 900, idleDuration: 0)
        XCTAssertEqual(transitions(&engine), [.init(kind: .started, uptime: 900)])
        engine.advance(to: 960, idleDuration: 180)
        XCTAssertEqual(engine.state.reminder, .rest)
        XCTAssertTrue(transitions(&engine).isEmpty)
        engine.advance(to: 1019.999, idleDuration: 239.999)
        XCTAssertTrue(transitions(&engine).isEmpty)
        engine.advance(to: 1020, idleDuration: 240)
        XCTAssertEqual(transitions(&engine), [.init(kind: .idleCompletion, uptime: 1020, idleDuration: 240)])
        XCTAssertNil(engine.state.reminder)
        XCTAssertEqual(engine.state.breakRemaining, 900)
        engine.advance(to: 1080, idleDuration: 300)
        XCTAssertTrue(transitions(&engine).isEmpty)
    }
    func testSnoozeAndSkipAreDistinctFromIdleCompletionWithoutChangingTheirClocks() {
        var engine = engine()
        engine.advance(to: 900, idleDuration: 0)
        engine.snoozeBreak(at: 901)
        XCTAssertEqual(transitions(&engine), [.init(kind: .started, uptime: 900), .init(kind: .snoozed, uptime: 901)])
        XCTAssertEqual(engine.state.breakRemaining, 300)
        engine.advance(to: 1201, idleDuration: 0)
        engine.dismissReminder(at: 1202)
        XCTAssertEqual(transitions(&engine), [.init(kind: .started, uptime: 1201), .init(kind: .skipped, uptime: 1202)])
        XCTAssertEqual(engine.state.breakRemaining, 900)
        engine.dismissReminder(at: 1203); engine.snoozeBreak(at: 1203)
        XCTAssertTrue(transitions(&engine).isEmpty)
    }
    func testOtherRestInterruptionsCannotBeMislabelledAsIdleCompletion() {
        for kind: RestTransition.Kind in [.paused, .disabled, .cameraPreview] {
            var engine = engine()
            engine.advance(to: 900, idleDuration: 0)
            switch kind {
            case .paused: engine.setPaused(true, at: 901)
            case .disabled:
                var settings = engine.settings; settings.breakEnabled = false
                engine.updateSettings(settings, at: 901)
            case .cameraPreview: engine.setPreview(true, at: 901)
            default: XCTFail("Unreachable")
            }
            XCTAssertEqual(transitions(&engine), [.init(kind: .started, uptime: 900), .init(kind: kind, uptime: 901)])
            XCTAssertNil(engine.state.reminder)
        }
    }
}
