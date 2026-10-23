import XCTest
@testable import EyeblinkCore

final class RestCompletionTests: XCTestCase {
    private func settings() -> AppSettings {
        var value = AppSettings()
        value.trainingEnabled = false; value.exerciseEnabled = false
        value.measurementEnabled = false; value.breakInterval = 10
        return value
    }

    func testOngoingInputCannotCompleteRestRegardlessOfElapsedWallTime() {
        var engine = EyeblinkEngine(settings: settings())
        engine.advance(to: 16, idleDuration: 0)
        XCTAssertEqual(engine.state.reminder, .rest)
        engine.advance(to: 3600, idleDuration: 0)
        XCTAssertEqual(engine.state.reminder, .rest)
    }

    func testIdleSettingStillControlsRestCompletionWithNaturalCreditsDisabled() {
        var value = settings()
        value.naturalBreakDuration = 60
        value.naturalBreaksEnabled = false
        var engine = EyeblinkEngine(settings: value)
        engine.advance(to: 16, idleDuration: 0)
        XCTAssertEqual(engine.state.reminder, .rest)
        engine.advance(to: 60, idleDuration: 0)
        engine.advance(to: 120, idleDuration: 60)
        XCTAssertEqual(engine.state.reminder, .rest, "The recovered comparison is strictly greater.")
        engine.advance(to: 179.999, idleDuration: 119.999)
        XCTAssertEqual(engine.state.reminder, .rest, "Completion waits for the next minute check.")
        engine.advance(to: 180, idleDuration: 120)
        XCTAssertNil(engine.state.reminder)
        XCTAssertEqual(engine.state.breakRemaining, value.breakInterval)
        XCTAssertEqual(engine.state.exerciseRemaining, value.exerciseInterval)
    }

    func testObsoletePrototypeDurationDoesNotDiscardOrControlSavedSettings() throws {
        var value = settings()
        value.language = .english; value.naturalBreakDuration = 180
        var json = try XCTUnwrap(JSONSerialization.jsonObject(with: JSONEncoder().encode(value)) as? [String: Any])
        json["breakDuration"] = 1 // Field from the earlier rebuild, absent in the original controller.
        let decoded = try JSONDecoder().decode(AppSettings.self, from: JSONSerialization.data(withJSONObject: json))
        XCTAssertEqual(decoded, value)
        let encoded = try XCTUnwrap(JSONSerialization.jsonObject(with: JSONEncoder().encode(decoded)) as? [String: Any])
        XCTAssertNil(encoded["breakDuration"])
        var engine = EyeblinkEngine(settings: decoded)
        engine.advance(to: 16, idleDuration: 0)
        engine.advance(to: 60, idleDuration: 0)
        XCTAssertEqual(engine.state.reminder, .rest)
    }
}
