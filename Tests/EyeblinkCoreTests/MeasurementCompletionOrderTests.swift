import XCTest
@testable import EyeblinkCore

final class MeasurementCompletionOrderTests: XCTestCase {
    private func engine() -> EyeblinkEngine {
        var settings = AppSettings()
        settings.trainingEnabled = false; settings.measurementEnabled = false
        settings.exerciseEnabled = false; settings.breakEnabled = false
        return EyeblinkEngine(settings: settings)
    }
    func testTickerPastDeadlineCannotSaveBeforeInFlightFailure() throws {
        var engine = engine()
        let id = try XCTUnwrap(engine.startMeasurement(at: 15)), token = try XCTUnwrap(engine.state.cameraToken)
        engine.cameraDidStart(token: token, at: 15)
        engine.sample(cameraToken: token, token: id, at: 194.99, faceValid: true, blinkDurations: [0.1875])
        // Worker has entered a frame before the deadline. Main timer fires
        // during tracking; that same frame will then terminate for no face.
        engine.advance(to: 195.1)
        XCTAssertNotNil(engine.state.measurement)
        XCTAssertTrue(engine.takeEffects().isEmpty)
        engine.cameraDetectionFailed(token: token, reason: .noFace, at: 195.2)
        XCTAssertEqual(engine.takeEffects(), [.measurementCancelled(id)])
        XCTAssertEqual(engine.state.measurementRemaining, 480)
    }
    func testOnlyOrderedCompletionCanSaveAndStaleOrDuplicateCompletionIsIgnored() throws {
        var engine = engine()
        let id = try XCTUnwrap(engine.startMeasurement(at: 15)), token = try XCTUnwrap(engine.state.cameraToken)
        engine.cameraDidStart(token: token, at: 15)
        engine.sample(cameraToken: token, token: id, at: 194.99, faceValid: true, blinkDurations: [0.1875])
        engine.advance(to: 195.1)
        engine.cameraMeasurementFinished(token: UUID(), at: 1000)
        XCTAssertNotNil(engine.state.measurement)
        engine.cameraMeasurementFinished(token: token, at: 195.2)
        engine.cameraMeasurementFinished(token: token, at: 195.3)
        let effects = engine.takeEffects()
        XCTAssertEqual(effects.count, 1)
        guard case .measurementCompleted(let record) = effects.first else { return XCTFail("Expected serialized completion") }
        XCTAssertEqual(record.id, id)
        XCTAssertEqual(record.blinkDurations, [0.1875])
        XCTAssertEqual(record.blinksPerMinute, Double(Float(1.0 / 3)))
        XCTAssertEqual(engine.state.measurementRemaining, 1800)
    }
    func testPostDeadlineAnalyzedFrameStillWaitsForPreReadCompletionBoundary() throws {
        var engine = engine()
        let id = try XCTUnwrap(engine.startMeasurement(at: 15)), token = try XCTUnwrap(engine.state.cameraToken)
        engine.cameraDidStart(token: token, at: 15)
        // A synchronous read begun before the deadline can yield a frame after
        // it. That frame must finish normally before the next loop check.
        engine.sample(cameraToken: token, token: id, at: 195.1, faceValid: true, blinkDurations: [0.1875])
        XCTAssertNotNil(engine.state.measurement)
        XCTAssertTrue(engine.takeEffects().isEmpty)
        engine.cameraMeasurementFinished(token: token, at: 195.2)
        guard case .measurementCompleted(let record) = engine.takeEffects().first else { return XCTFail("Expected next loop completion") }
        XCTAssertEqual(record.blinkDurations, [0.1875])
    }
    func testCompletionCannotResurrectCancelledLeaseOrCompletePreview() throws {
        var engine = engine()
        let id = try XCTUnwrap(engine.startMeasurement(at: 15)), token = try XCTUnwrap(engine.state.cameraToken)
        engine.cameraDidStart(token: token, at: 15)
        engine.cameraDetectionFailed(token: token, reason: .noFace, at: 20)
        engine.cameraMeasurementFinished(token: token, at: 200)
        XCTAssertEqual(engine.takeEffects(), [.measurementCancelled(id)])
        engine.setPreview(true, at: 201)
        engine.cameraMeasurementFinished(token: try XCTUnwrap(engine.state.cameraToken), at: 1000)
        XCTAssertEqual(engine.state.cameraPurpose, .preview)
        XCTAssertTrue(engine.takeEffects().isEmpty)
    }
}
