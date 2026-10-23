import XCTest
@testable import EyeblinkCore

final class ControlRangeTests: XCTestCase {
    // Source: ui-spinboxes.otool.txt, object names tied to their min/max/step setters.
    func testOriginalLowerAndUpperValuesAreAllAvailable() {
        for (training, rest, natural) in [(2.0, 15.0, 2.0), (60.0, 80.0, 9.0)] {
            var value = AppSettings()
            value.trainingInterval = training
            value.breakInterval = rest * 60; value.naturalBreakDuration = natural * 60
            XCTAssertEqual(value.validatedForInterface(), value)
        }
    }
    func testPrototypeOutOfRangePreferencesAreClampedWithoutLosingOtherSettings() {
        var value = AppSettings()
        value.language = .english; value.mgdEnabled = true
        value.trainingInterval = 600; value.breakInterval = 5 * 60
        value.naturalBreakDuration = 30 * 60
        let restored = value.validatedForInterface()
        XCTAssertEqual(restored.trainingInterval, 60)
        XCTAssertEqual(restored.breakInterval, 15 * 60)
        XCTAssertEqual(restored.naturalBreakDuration, 9 * 60)
        XCTAssertEqual(restored.language, .english); XCTAssertTrue(restored.mgdEnabled)
    }
    func testIntegerControlsAndMalformedInputsHaveDeterministicRestoration() {
        var value = AppSettings()
        value.trainingInterval = 2.9; value.breakInterval = 15.9 * 60
        value.naturalBreakDuration = 2.9 * 60
        let integer = value.validatedForInterface()
        XCTAssertEqual(integer.trainingInterval, 2)
        XCTAssertEqual(integer.breakInterval, 15 * 60)
        XCTAssertEqual(integer.naturalBreakDuration, 2 * 60)
        value.trainingInterval = .nan; value.breakInterval = .infinity; value.naturalBreakDuration = -1
        let defaults = AppSettings()
        XCTAssertEqual(value.validatedForInterface().trainingInterval, defaults.trainingInterval)
        XCTAssertEqual(value.validatedForInterface().breakInterval, defaults.breakInterval)
        XCTAssertEqual(value.validatedForInterface().naturalBreakDuration, defaults.naturalBreakDuration)
    }
}
