import XCTest
@testable import EyeblinkCore

final class MultipleBlinkFrameTests: XCTestCase {
    func testOriginalSameFrameEmissionsReachMeasurementOnceAndRespectTokens() throws {
        var settings = AppSettings()
        settings.trainingEnabled = false; settings.exerciseEnabled = false
        settings.breakEnabled = false; settings.measurementEnabled = false
        var engine = EyeblinkEngine(settings: settings)
        let measurement = try XCTUnwrap(engine.startMeasurement(at: 15))
        let camera = try XCTUnwrap(engine.state.cameraToken)
        // Both values are emitted at frame 17 in the original temporal fixture.
        engine.sample(cameraToken: camera, token: measurement, at: 15, faceValid: true,
                      blinkDurations: [0.375, 0.3125, .nan, -1])
        engine.sample(cameraToken: camera, token: measurement, at: 15.03125, faceValid: true, blinkDurations: [0.125])
        // Repeated timestamps and stale camera tokens cannot add events.
        // A lost current face must not discard events from the previous eye ROI.
        engine.sample(cameraToken: camera, token: measurement, at: 15.03125, faceValid: true, blinkDurations: [0.5, 0.5])
        engine.sample(cameraToken: camera, token: measurement, at: 15.0625, faceValid: false, blinkDurations: [0.5, 0.5])
        engine.sample(cameraToken: UUID(), token: measurement, at: 15.09375, faceValid: true, blinkDurations: [0.5])
        XCTAssertEqual(engine.state.measurement?.blinkDurations, [0.375, 0.3125, 0.125, 0.5, 0.5])
        // Preserve the full original 180.001s measurement boundary.
        engine.cameraMeasurementFinished(token: camera, at: 195.001)
        let records = engine.takeEffects().compactMap { effect -> MeasurementRecord? in
            if case .measurementCompleted(let record) = effect { return record }
            return nil
        }
        let record = try XCTUnwrap(records.first)
        XCTAssertEqual(records.count, 1)
        XCTAssertEqual(record.blinkDurations, [0.375, 0.3125, 0.125, 0.5, 0.5])
        XCTAssertEqual(record.blinksPerMinute, Double(Float(5.0 / 3)))
        XCTAssertEqual(record.averageBlinkDurationMilliseconds, 362)
    }
}
