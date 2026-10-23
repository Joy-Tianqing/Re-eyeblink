import XCTest
@testable import EyeblinkCore

final class CameraStartupTests: XCTestCase {
    func testReadyWithoutFramesDoesNotFabricateDetectorFailureOrCompletion() {
        var training = makeEngine()
        training.advance(to: 30)
        let trainingToken = training.state.cameraToken!
        training.cameraDidStart(token: trainingToken, at: 31)
        training.advance(to: 100)
        XCTAssertTrue(training.state.trainingSessionActive)
        XCTAssertEqual(training.state.cameraToken, trainingToken)
        XCTAssertNil(training.state.lastDetectionFailure)
        XCTAssertNil(training.state.reminder)

        var settings = AppSettings(); settings.trainingEnabled = false
        var measurement = EyeblinkEngine(settings: settings)
        _ = measurement.startMeasurement(at: 15)
        let measurementToken = measurement.state.cameraToken!
        measurement.cameraDidStart(token: measurementToken, at: 16)
        measurement.advance(to: 300)
        XCTAssertNotNil(measurement.state.measurement)
        XCTAssertEqual(measurement.state.cameraToken, measurementToken)
        XCTAssertNil(measurement.state.lastDetectionFailure)
        XCTAssertTrue(measurement.takeEffects().isEmpty)
        measurement.cameraMeasurementFinished(token: measurementToken, at: 300.1)
        XCTAssertNil(measurement.state.measurement)
        XCTAssertEqual(measurement.takeEffects().count, 1)
    }
    func makeEngine(mgd: Bool = false) -> EyeblinkEngine {
        var settings = AppSettings()
        settings.exerciseEnabled = false; settings.breakEnabled = false
        settings.measurementEnabled = false; settings.mgdEnabled = mgd
        return EyeblinkEngine(settings: settings)
    }
    func testTrainingObservationStartsAfterCameraInitialization() {
        var engine = makeEngine()
        engine.advance(to: 30)
        let token = engine.state.cameraToken!
        engine.advance(to: 34.1)
        XCTAssertNil(engine.state.reminder)
        engine.cameraDidStart(token: token, at: 35)
        for time in 35...39 { engine.sample(cameraToken: token, token: nil, at: Double(time), faceValid: true, blinkDurations: []) }
        engine.advance(to: 39)
        XCTAssertNil(engine.state.reminder)
        engine.advance(to: 39.001)
        XCTAssertNil(engine.state.reminder, "The GUI timer cannot synthesize the worker's 4001ms decision")
        engine.cameraTrainingProgress(token: token, blinkDetected: false, at: 39.001)
        XCTAssertEqual(engine.state.reminder, .training(.interactive, mgd: false))
    }
    func testMGDWaitsForActualReadyWithoutIndependentStartupDeadline() {
        var engine = makeEngine(mgd: true)
        engine.advance(to: 30)
        let token = engine.state.cameraToken!
        XCTAssertNil(engine.state.reminder)
        engine.advance(to: 60)
        XCTAssertTrue(engine.state.trainingSessionActive)
        XCTAssertEqual(engine.state.cameraToken, token)
        XCTAssertNil(engine.state.lastDetectionFailure)
        engine.cameraTrainingProgress(token: token, blinkDetected: true, at: 60.1)
        XCTAssertEqual(engine.state.cameraToken, token, "An uninitialized worker cannot complete training")
        engine.cameraDidStart(token: token, at: 61)
        XCTAssertEqual(engine.state.reminder, .training(.interactive, mgd: true))
    }
    func testOldLeaseCannotResetCurrentMeasurementClock() {
        var settings = AppSettings(); settings.trainingEnabled = false
        var engine = EyeblinkEngine(settings: settings)
        _ = engine.startMeasurement(at: 15)
        let old = engine.state.cameraToken!
        engine.invalidateCamera(at: 16)
        _ = engine.startMeasurement(at: 17)
        let current = engine.state.cameraToken!
        engine.cameraDidStart(token: old, at: 18)
        XCTAssertFalse(engine.state.cameraHasStarted)
        engine.cameraDidStart(token: current, at: 19)
        XCTAssertTrue(engine.state.cameraHasStarted)
        XCTAssertEqual(engine.state.measurement?.startedAt, 19)
    }
}
