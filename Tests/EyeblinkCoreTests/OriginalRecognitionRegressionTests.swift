import XCTest
@testable import EyeblinkCore

final class OriginalRecognitionRegressionTests: XCTestCase {
    private func settings() -> AppSettings {
        var settings = AppSettings()
        settings.trainingEnabled = false; settings.measurementEnabled = false
        settings.exerciseEnabled = false; settings.breakEnabled = false
        return settings
    }

    func testFullThreeMinuteMeasurementDoesNotRequire85PercentCoverage() throws {
        var engine = EyeblinkEngine(settings: settings())
        let id = try XCTUnwrap(engine.startMeasurement(at: 15))
        let token = try XCTUnwrap(engine.state.cameraToken)
        engine.cameraDidStart(token: token, at: 15)
        // Alternate one second with/without a selected face: below 85% total,
        // but never near the original continuous eight-second absence limit.
        for frame in 1...5759 {
            let time = 15 + Double(frame) / 32
            let valid = (frame / 32) % 2 == 0
            engine.sample(cameraToken: token, token: id, at: time, faceValid: valid,
                          blinkDurations: frame == 64 ? [0.2] : [])
            engine.advance(to: time)
        }
        XCTAssertNotNil(engine.state.measurement)
        engine.cameraMeasurementFinished(token: token, at: 195.001)
        guard case .measurementCompleted(let record) = engine.takeEffects().first else {
            return XCTFail("Original elapsed-time measurement must finish without a coverage gate")
        }
        XCTAssertEqual(record.blinkDurations, [0.2])
        XCTAssertEqual(record.frequencyDuration, 180)
        XCTAssertEqual(record.blinksPerMinute, Double(Float(1.0 / 3)), "Keep the original Float conversion")
        XCTAssertNil(record.detection)
        XCTAssertNil(engine.state.lastDetectionFailure)
        engine.cameraMeasurementFinished(token: token, at: 196)
        XCTAssertTrue(engine.takeEffects().isEmpty)
    }

    func testTrainingAcceptsFirstBlinkAndHasNoThirtySecondCalibrationTimeout() throws {
        for wait in [0.1, 35.0] {
            var configured = settings()
            configured.trainingEnabled = true; configured.mgdEnabled = true
            var engine = EyeblinkEngine(settings: configured)
            engine.advance(to: 30)
            let token = try XCTUnwrap(engine.state.cameraToken)
            engine.cameraDidStart(token: token, at: 30)
            for frame in 1...Int(wait * 32) {
                let time = 30 + Double(frame) / 32
                engine.sample(cameraToken: token, token: nil, at: time, faceValid: true, blinkDurations: [])
                engine.advance(to: time)
            }
            XCTAssertEqual(engine.state.cameraToken, token)
            XCTAssertNil(engine.state.lastDetectionFailure)
            engine.sample(cameraToken: token, token: nil, at: 30 + wait + 0.1,
                          faceValid: true, blinkDurations: [0.2])
            XCTAssertEqual(engine.state.cameraToken, token)
            engine.cameraTrainingProgress(token: token, blinkDetected: true, at: 30 + wait + 0.11)
            XCTAssertNil(engine.state.reminder)
            XCTAssertNil(engine.state.cameraToken)
        }
    }

    func testOriginalMeasurementKeepsEmittedBlinkWhenCurrentFrameLosesFace() throws {
        var engine = EyeblinkEngine(settings: settings())
        XCTAssertEqual(engine.policy.measurementTiming, .originalElapsedTime)
        let id = try XCTUnwrap(engine.startMeasurement(at: 15))
        let token = try XCTUnwrap(engine.state.cameraToken)
        engine.cameraDidStart(token: token, at: 15)
        engine.sample(cameraToken: token, token: id, at: 15.1, faceValid: true, blinkDurations: [0.1])
        // The flow merger can finish a blink using the preceding eye region,
        // even though this frame's detector did not select a face.
        engine.sample(cameraToken: token, token: id, at: 15.2, faceValid: false,
                      blinkDurations: [0.2, .nan, .infinity, 0, -1])
        engine.sample(cameraToken: token, token: id, at: 15.3, faceValid: true, blinkDurations: [0.3])
        // Duplicate/out-of-order delivery must not duplicate the preserved event.
        engine.sample(cameraToken: token, token: id, at: 15.2, faceValid: false, blinkDurations: [0.2])
        engine.sample(cameraToken: UUID(), token: id, at: 15.4, faceValid: false, blinkDurations: [0.4])
        engine.sample(cameraToken: token, token: UUID(), at: 15.4, faceValid: false, blinkDurations: [0.4])
        XCTAssertEqual(engine.state.measurement?.blinkDurations, [0.1, 0.2, 0.3])
        engine.cameraMeasurementFinished(token: token, at: 195.001)
        guard case .measurementCompleted(let record) = engine.takeEffects().first else {
            return XCTFail("Expected original elapsed-time measurement")
        }
        XCTAssertEqual(record.blinkDurations, [0.1, 0.2, 0.3])
        XCTAssertEqual(record.frequencyDuration, 180)
        XCTAssertEqual(record.blinksPerMinute, 1)
    }

    func testLegacySideCameraRecordsRemainReadableWithoutRewritingProvenance() throws {
        for version in 1...4 {
            for mode: EyeObservationMode? in [nil, .both, .left, .right, .mixed] {
                let record = MeasurementRecord(date: Date(timeIntervalSince1970: 123), validDuration: 180,
                    blinkDurations: [0.2], frequencyDuration: 180,
                    detection: .init(algorithm: "side-contour-v\(version)", validFrameFraction: 0.74,
                                     observationMode: mode, targeting: version >= 3 ? "spatial-primary-v1" : nil))
                let data = try JSONEncoder().encode(record)
                let decoded = try JSONDecoder().decode(MeasurementRecord.self, from: data)
                XCTAssertEqual(decoded, record)
                XCTAssertEqual(decoded.isEstimated, mode?.isEstimated ?? false)
            }
        }
        let old = MeasurementRecord(date: .distantPast, validDuration: 180, blinkDurations: [0.2])
        XCTAssertEqual(try JSONDecoder().decode(MeasurementRecord.self, from: JSONEncoder().encode(old)), old)
        let v1 = try JSONDecoder().decode(MeasurementDetection.self,
            from: Data(#"{"algorithm":"side-contour-v1","validFrameFraction":0.9}"#.utf8))
        XCTAssertNil(v1.observationMode)
        XCTAssertNil(v1.targeting)
    }

    func testLegacySingleEyeEstimatesStaySeparateFromOriginalMeasurements() throws {
        let original = MeasurementRecord(date: .distantPast, validDuration: 180, blinkDurations: [0.1, 0.1, 0.1])
        for mode in [EyeObservationMode.left, .right, .mixed] {
            let estimate = MeasurementRecord(date: .distantPast, validDuration: 180, blinkDurations: [0.5],
                detection: .init(algorithm: "side-contour-v4", validFrameFraction: 0.95, observationMode: mode))
            let summary = StatisticsSummary(records: [original, estimate])
            XCTAssertEqual(summary.count, 1)
            XCTAssertEqual(summary.meanBPM, 1)
            XCTAssertEqual(try XCTUnwrap(summary.meanBlinkDurationMilliseconds), 100, accuracy: 1e-9)
        }
    }
}
